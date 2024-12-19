--[[

	Copyright (C) 2022-2024 Tim Wilkinson
	See Contributors file for additional contributors

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation version 3 of the License.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.

	Additional Terms:

	Additional use restrictions exist on the AREDN® trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN® Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN® project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version

--]]

local ip = require("luci.ip")
require("aredn.info")

local refresh_timeout_base = 12 * 60 -- refresh high cost data every 12 minutes
local refresh_timeout_limit = 17 * 60 -- to 17 minutes
local refresh_retry_timeout = 5 * 60
local pending_timeout = 5 * 60 -- pending node wait 5 minutes before they are included
local lastseen_timeout = 60 * 60 -- age out nodes we've not seen for 1 hour
local snr_run_avg = 0.8 -- snr running average
local quality_min_packets = 100 -- minimum number of tx packets before we can safely calculate the link quality
local tx_quality_run_avg = 0.8 -- tx quality running average
local ping_timeout = 1.0 -- timeout before ping gives a qualtiy penalty
local ping_time_run_avg = 0.8 -- ping time runnng average
local bitrate_run_avg = 0.8 -- rx/tx running average
local dtd_distance = 50 -- distance (meters) after which nodes connected with DtD links are considered different sites
local connect_timeout = 5 -- timeout (seconds) when fetching information from other nodes
local speed_time = 10 --
local speed_limit = 1000 -- close connection if it's too slow (< 1kB/s for 10 seconds)
local default_short_retries = 20 -- More link-level retries helps overall tcp performance (factory default is 7)
local default_long_retries = 20 -- (factory default is 4)
local wireguard_alive_time = 300 -- 5 minutes

local NFT = "/usr/sbin/nft"
local IW = "/usr/sbin/iw"
local ARPING = "/usr/sbin/arping"
local CURL = "/usr/bin/curl"
local IPCMD = "/sbin/ip"

local now = 0
local config = {}

local total_node_route_count = nil

function update_config()
    local c = uci.cursor() -- each time as /etc/config/aredn may have changed
    config = {
        enable = c:get("aredn", "@lqm[0]", "enable") == "1",
        margin = tonumber(c:get("aredn", "@lqm[0]", "margin_snr")),
        low = tonumber(c:get("aredn", "@lqm[0]", "min_snr")),
        rts_threshold = tonumber(c:get("aredn", "@lqm[0]", "rts_threshold") or "1"),
        min_distance = tonumber(c:get("aredn", "@lqm[0]", "min_distance")),
        max_distance = tonumber(c:get("aredn", "@lqm[0]", "max_distance")),
        auto_distance = tonumber(c:get("aredn", "@lqm[0]", "auto_distance") or "0"),
        min_quality = tonumber(c:get("aredn", "@lqm[0]", "min_quality")),
        margin_quality = tonumber(c:get("aredn", "@lqm[0]", "margin_quality")),
        ping_penalty = tonumber(c:get("aredn", "@lqm[0]", "ping_penalty")),
        user_blocks = c:get("aredn", "@lqm[0]", "user_blocks") or "",
        user_allows = c:get("aredn", "@lqm[0]", "user_allows") or ""
    }
end

-- Connected if we have tracked this link recently
function is_connected(track)
    if track.lastseen >= now then
        return true
    else
        return false
    end
end

-- Pending if this link is too new
function is_pending(track)
    if track.pending > now then
        return true
    else
        return false
    end
end

function is_user_blocked(track)
    if not track.user_allow and track.blocks.user then
        return true
    end
    return false
end

function should_block(track)
    if track.user_allow then
        return false
    elseif not config.enable then
        return track.blocks.user
    elseif is_pending(track) then
        return track.blocks.dtd or track.blocks.user
    else
        return track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.dup or track.blocks.quality
    end
end

function should_nonpair_block(track)
    return track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.quality or track.type ~= "RF"
end

function should_ping(track)
    if not track.ip or is_user_blocked(track) or track.lastseen < now then
        return false
    end
    if track.type == "Tunnel" or track.type == "Wireguard" then
        -- Tunnels use L3 pings, so we can only ping if we're not blocked
        if track.blocked then
            return false
        end
    else
        -- Non-tunnels use L2 pings, so we can still ping even when blocked
        -- but we dont ping if the node is too distance, the signal is too low, or we dont use this RF because
        -- we have a DTD connection instead
        if track.blocks.distance or track.blocks.signal or track.blocks.dtd then
            return false
        end
    end
    return true
end

function should_update_info(track)
    if track.blocked and not track.blocks.distance then
        return false
    end
    return true
end

function nft(cmd)
    os.execute(NFT .. " " .. cmd)
end

function nft_insert(chain, cmd)
    os.execute(NFT .. " insert rule ip fw4 " .. chain .. " " .. cmd)
end

function nft_delete(chain, handle)
    os.execute(NFT .. " delete rule ip fw4 " .. chain .. " handle " .. handle)
end

function _nft_handle(chain, query)
    for line in io.popen(NFT .. " -a list chain ip fw4 " .. chain):lines()
    do
        local handle = line:match(query .. ".*# handle (%d+)$")
        if handle then
            return handle
        end
    end
    return nil
end

function nft_handle(chain, query)
    local ok, result = pcall(_nft_handle, chain, query)
    if not ok then
        -- Retry to handle occasional EINTR
        ok, result = pcall(_nft_handle, chain, query)
    end
    return ok and result or nil
end

function update_block(track)
    if should_block(track) then
        track.blocked = true
        if track.type == "Tunnel" or track.type == "Wireguard" then
            if not nft_handle("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop") then
                nft_insert("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop 2> /dev/null")
                return "blocked"
            end
        else
            if not nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac .. " drop") then
                nft_insert("input_lqm", "udp dport 698 ether saddr " .. track.mac .. " drop 2> /dev/null")
                return "blocked"
            end
        end
    else
        track.blocked = false
        if track.type == "Tunnel" or track.type == "Wireguard" then
            local handle = nft_handle("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop")
            if handle then
                nft_delete("input_lqm", handle)
                return "unblocked"
            end
        else
            local handle = nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac .. " drop")
            if handle then
                nft_delete("input_lqm", handle)
                return "unblocked"
            end
        end
    end
    return "unchanged"
end

function force_remove_block(track)
    track.blocked = false
    local handle = nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac .. " drop")
    if handle then
        nft_delete("input_lqm", handle)
    end
    handle = nft_handle("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop")
    if handle then
        nft_delete("input_lqm", handle)
    end
end

function refresh_timeout()
     return math.random(refresh_timeout_base, refresh_timeout_limit)
end

-- Distance in meters between two points
function calc_distance(lat1, lon1, lat2, lon2)
    local r2 = 12742000 -- diameter earth (meters)
    local p = 0.017453292519943295 --  Math.PI / 180
    local v = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return math.floor(r2 * math.asin(math.sqrt(v)))
end

function av(c, f, n, o)
    if c and o and n then
        return f * c + (1 - f) * (n - o)
    else
        return n
    end
end

function round(v)
    return math.floor(v + 0.5)
end

-- Canonical hostname
function canonical_hostname(hostname)
    return hostname and hostname:lower():gsub("^dtdlink%.",""):gsub("^mid%d+%.",""):gsub("^xlink%d+%.",""):gsub("%.local%.mesh$", "")
end

local myhostname = canonical_hostname(aredn.info.get_nvram("node") or "localnode")
local myip = uci.cursor():get("network", "wifi", "ipaddr")
local is_supernode = uci.cursor():get("aredn", "@supernode[0]", "enable") == "1"

local wgsupport = nixio.fs.stat("/usr/bin/wg")

-- Clear old data
local f = io.open("/tmp/lqm.info", "w")
f:write('{"trackers":{},"hidden_nodes":[]}')
f:close()

-- Get radio
local radiomode = "none"
local wlan = aredn.hardware.get_iface_name("wifi")
local phy = "none"
local wlanid = wlan:match("^wlan(%d+)$")
if wlanid then
    phy = "phy" .. wlanid
    radiomode = "adhoc"
end

function iw_set(cmd)
    if phy ~= "none" then
        os.execute(IW .. " " .. phy .. " set " .. cmd .. " > /dev/null 2>&1")
    end
end

function gettimems()
    local sec, usec = nixio.gettimeofday()
    return sec * 1000 + usec / 1000;
end

function lqm_run()
    -- Create filters (cannot create during install as they disappear on reboot)
    nft("flush chain ip fw4 input_lqm 2> /dev/null")
    nft("delete chain ip fw4 input_lqm 2> /dev/null")
    nft("add chain ip fw4 input_lqm 2> /dev/null")
    local handle = nft_handle("input", "jump input_lqm comment")
    if handle then
        nft_delete("input", handle)
    end
    nft_insert("input", "jump input_lqm comment \\\"block low quality links\\\"")

    -- We dont know any distances yet
    iw_set("distance auto")
    -- Or any hidden nodes
    iw_set("rts off")
    if config.enable then
        -- Set the default retries
        iw_set("retry short " .. default_short_retries .. " long " .. default_long_retries)
    end

    -- If the channel bandwidth is less than 20, we need to adjust what we report as the values from 'iw' will not
    -- be correct
    local channel_bw_scale = 1
    local chanbw = read_all("/sys/kernel/debug/ieee80211/" .. phy .. "/ath10k/chanbw")
    if not chanbw then
        chanbw = read_all("/sys/kernel/debug/ieee80211/" .. phy .. "/ath9k/chanbw")
    end
    if chanbw then
        chanbw = tonumber(chanbw)
        if chanbw == 10 then
            channel_bw_scale = 0.5
        elseif chanbw == 5 then
            channel_bw_scale = 0.25
        end
    end

    local noise = -95
    local tracker = {}
    local dtdlinks = {}
    local rflinks = {}
    local hidden_nodes = {}
    local last_coverage = -1
    local last_short_retries = -1
    local last_long_retries = -1
    local pending_count = 0

    os.remove("/tmp/lqm.reset")
    -- Run until reset is detected
    while not nixio.fs.stat("/tmp/lqm.reset")
    do
        now = nixio.sysinfo().uptime

        update_config()

        local cursor = uci.cursor()
        local cursorm = uci.cursor("/etc/config.mesh")

        local lat = cursor:get("aredn", "@location[0]", "lat")
        local lon = cursor:get("aredn", "@location[0]", "lon")
        lat = tonumber(lat)
        lon = tonumber(lon)

        local arps = {}
        for line in io.popen(IPCMD .. " neigh show"):lines()
        do
            local ip, dev, mac, probes, state = line:match("^(%S+) dev (%S+) lladdr (%S+) .+ probes (%d+) (.+)$")
            if ip and (tonumber(probes) < 4 or state ~= "STALE") then
                arps[#arps + 1] = {
                    Device = dev,
                    ["HW address"] = mac:lower(),
                    ["IP address"] = ip
                }
            end
        end

        -- Find all our devices and know our macs so we can exclude them
        local devices = {}
        for _, i in ipairs(nixio.getifaddrs())
        do
            if i.name then
                local dev = devices[i.name]
                if not dev then
                    dev = { name = i.name }
                    devices[i.name] = dev
                end
                if i.family == "packet" then
                    if i.addr then
                        dev.mac = i.addr:lower()
                    end
                    dev.tx_packets = i.data.tx_packets
                    dev.tx_fail = i.data.tx_errors
                end
                if i.family == "inet" then
                    dev.ip = i.addr
                    dev.dstip = i.dstaddr
                    if not dev.mac then
                        -- Fake a mac from the ip if we need one
                        local a, b, c, d = dev.ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
                        dev.mac = string.format("00:00:%02X:%02X:%02X:%02X", a, b, c, d)
                    end
                end
            end
        end

        -- Find the wireguard tunnels that are active
        local wgtuns = {}
        if wgsupport then
            local f = io.popen("/usr/bin/wg show all latest-handshakes")
            if f then
                for line in f:lines()
                do
                    local iface, handshake = line:match("^(%S+)%s+%S+%s+(%d+)%s*$")
                    if iface and tonumber(handshake) + wireguard_alive_time > os.time() then
                        wgtuns[iface] = true
                    end
                end
                f:close()
            end
        end

        local stations = {}

        -- Legacy and wireguard tunnels
        for _, dev in pairs(devices)
        do
            if dev.name:match("^tun%d+") then
                stations[#stations + 1] = {
                    type = "Tunnel",
                    device = dev.name,
                    ip = dev.dstip,
                    mac = dev.mac,
                    tx_packets = dev.tx_packets,
                    tx_fail = dev.tx_fail
                }
            elseif dev.name:match("^wgc%d+") and wgtuns[dev.name] then
                local ip123, ip4 = dev.ip:match("^(%d+%.%d+%.%d+%.)(%d+)$")
                stations[#stations + 1] = {
                    type = "Wireguard",
                    device = dev.name,
                    ip = ip123 .. (tonumber(ip4) + 1),
                    mac = dev.mac,
                    tx_packets = dev.tx_packets,
                    tx_fail = dev.tx_fail
                }
            elseif dev.name:match("^wgs%d+") and wgtuns[dev.name] then
                local ip123, ip4 = dev.ip:match("^(%d+%.%d+%.%d+%.)(%d+)$")
                stations[#stations + 1] = {
                    type = "Wireguard",
                    device = dev.name,
                    ip = ip123 .. (tonumber(ip4) - 1),
                    mac = dev.mac,
                    tx_packets = dev.tx_packets,
                    tx_fail = dev.tx_fail
                }
            end
        end

        -- Xlink interfaces
        local xlinks = {}
        cursorm:foreach("xlink", "interface",
            function(section)
                if section.ifname then
                    xlinks[section.ifname] = true
                end
            end
        )

        -- DtD & Xlinks
        for _, entry in ipairs(arps)
        do
            if entry.Device:match("%.2$") or entry.Device:match("^br%-dtdlink") then
                stations[#stations + 1] = {
                    type = "DtD",
                    device = entry.Device,
                    ip = entry["IP address"],
                    mac = entry["HW address"]
                }
            elseif xlinks[entry.Device] then
                stations[#stations + 1] = {
                    type = "Xlink",
                    device = entry.Device,
                    ip = entry["IP address"],
                    mac = entry["HW address"]
                }
            end
        end

        -- RF
        if radiomode == "adhoc" then
            local kv = {
                ["signal avg:"] = "signal",
                ["tx packets:"] = "tx_packets",
                ["tx retries:"] = "tx_retries",
                ["tx failed:"] = "tx_fail",
                ["tx bitrate:"] = "tx_bitrate",
                ["rx bitrate:"] = "rx_bitrate"
            }
            local station = {}
            local cnoise = iwinfo.nl80211.noise(wlan)
            if cnoise and cnoise < -70 then
                noise = round(noise * 0.9 + cnoise * 0.1)
            end
            for line in io.popen(IW .. " " .. wlan .. " station dump"):lines()
            do
                local mac = line:match("^Station ([0-9a-fA-F:]+) ")
                if mac then
                    station = {
                        type = "RF",
                        device = wlan,
                        mac = mac:lower(),
                        signal = nil,
                        noise = noise,
                        ip = nil,
                        tx_bitrate = 0,
                        rx_bitrate = 0
                    }
                    for _, entry in ipairs(arps)
                    do
                        if entry["HW address"] == station.mac and entry.Device:match("^wlan") then
                            station.ip = entry["IP address"]
                            break
                        end
                    end
                else
                    for k, v in pairs(kv)
                    do
                        local val = line:match(k .. "%s*([%d%-]+)")
                        if val then
                            station[v] = tonumber(val)
                            if v == "tx_bitrate" or v == "rx_bitrate" then
                                station[v] = station[v] * channel_bw_scale
                            end
                            if v == "signal" then
                                stations[#stations + 1] = station
                            end
                        end
                    end
                end
            end
        end

        -- Update the trackers based on the latest station information
        for _, station in ipairs(stations)
        do
            if not tracker[station.mac] then
                tracker[station.mac] = {
                    type = station.type,
                    device = station.device,
                    firstseen = now,
                    lastseen = now,
                    rev_lastseen = now,
                    pending = now + pending_timeout,
                    refresh = 0,
                    mac = station.mac,
                    ip = nil,
                    hostname = nil,
                    lat = nil,
                    lon = nil,
                    distance = nil,
                    localarea = nil,
                    blocks = {
                        dtd = false,
                        signal = false,
                        distance = false,
                        pair = false,
                        quality = false
                    },
                    blocked = false,
                    snr = nil,
                    rev_snr = nil,
                    avg_snr = nil,
                    last_tx = nil,
                    tx_quality = nil,
                    ping_quality = nil,
                    ping_success_time = nil,
                    tx_bitrate = nil,
                    rx_bitrate = nil,
                    quality = nil,
                    quality0_seen = nil,
                    quality_block_snr = nil,
                    last_tx_fail = nil,
                    last_tx_retries = nil,
                    avg_tx = nil,
                    avg_tx_retries = nil,
                    avg_tx_fail = nil,
                    node_route_count = 0,
                    rev_ping_quality = nil,
                    rev_ping_success_time = nil,
                    rev_quality = nil
                }
            end
            local track = tracker[station.mac]

            -- IP and Hostname
            if station.ip and station.ip ~= track.ip then
                track.ip = station.ip
                track.hostname = nil
            end
            if not track.hostname and track.ip then
                track.hostname = canonical_hostname(nixio.getnameinfo(track.ip))
            end

            -- Running average SNR
            if station.signal and station.noise then
                track.snr = round(av(track.snr, snr_run_avg, station.signal - station.noise, 0))
            end

            -- Running average estimate of link quality
            local tx = station.tx_packets
            local tx_retries = station.tx_retries
            local tx_fail = station.tx_fail

            if tx and track.tx and tx >= track.tx + quality_min_packets then
                track.avg_tx = av(track.avg_tx, tx_quality_run_avg, tx, track.tx)
                track.avg_tx_retries = av(track.avg_tx_retries, tx_quality_run_avg, tx_retries, track.tx_retries)
                track.avg_tx_fail = av(track.avg_tx_fail, tx_quality_run_avg, tx_fail, track.tx_fail)

                local bad = math.max((track.avg_tx_fail or 0), (track.avg_tx_retries or 0))
                track.tx_quality = 100 * (1 - math.min(1, math.max(track.avg_tx > 0 and bad / track.avg_tx or 0, 0)))
            end

            track.tx = tx
            track.tx_retries = tx_retries
            track.tx_fail = tx_fail

            track.tx_bitrate = av(track.tx_bitrate, bitrate_run_avg, station.tx_bitrate, track.tx_bitrate)
            track.rx_bitrate = av(track.rx_bitrate, bitrate_run_avg, station.rx_bitrate, track.rx_bitrate)

            track.lastseen = now
        end

        -- Update link tracking state
        local ip2tracker = {}
        pending_count = 0
        for _, track in pairs(tracker)
        do            
            if not track.ip then
                track.routable = false
            else
                ip2tracker[track.ip] = track

                -- Update if link is routable
                local rt = ip.route(track.ip)
                if rt and tostring(rt.gw) == track.ip then
                    track.routable = true
                else
                    track.routable = false
                end

                -- Refresh remote attributes periodically as this is expensive
                -- We dont do it the very first time so we can populate the LQM state with a new node quickly
                if now > track.refresh and track.firstseen ~= track.lastseen then

                    -- Refresh the hostname periodically as it can change
                    track.hostname = canonical_hostname(nixio.getnameinfo(track.ip)) or track.hostname

                    if not should_update_info(track) then
                        -- We cannot update so invalidate any information considered stale and set time to attempt refresh
                        track.refresh = is_pending(track) and 0 or now + refresh_retry_timeout
                        track.rev_snr = nil
                        track.rev_ping_success_time = nil
                        track.rev_ping_quality = nil
                        track.rev_quality = nil
                    else
                        local raw = io.popen(CURL .. " --retry 0 --connect-timeout " .. connect_timeout .. " --speed-time " .. speed_time .. " --speed-limit " .. speed_limit .. " -s \"http://" .. track.ip .. ":8080/cgi-bin/sysinfo.json?link_info=1&lqm=1\" -o - 2> /dev/null")
                        local info = luci.jsonc.parse(raw:read("*a"))
                        raw:close()

                        wait_for_ticks(0)

                        if not info then
                            -- Failed to fetch information. Set time for retry and invalidate any information
                            -- considered stale
                            track.refresh = is_pending(track) and 0 or now + refresh_retry_timeout
                            track.rev_snr = nil
                            track.rev_ping_success_time = nil
                            track.rev_ping_quality = nil
                            track.rev_quality = nil
                        else
                            track.refresh = is_pending(track) and 0 or now + refresh_timeout()
                            track.rev_lastseen = now

                            dtdlinks[track.mac] = {}

                            -- Update the distance to the remote node
                            track.lat = tonumber(info.lat) or track.lat
                            track.lon = tonumber(info.lon) or track.lon
                            if track.lat and track.lon and lat and lon then
                                track.distance = calc_distance(lat, lon, track.lat, track.lon)
                                if track.type == "DtD" and track.distance < dtd_distance then
                                    track.localarea = true
                                else
                                    track.localarea = false
                                end
                            end

                            -- Keep some useful info
                            if info.node_details then
                                track.model = info.node_details.model
                                track.firmware_version = info.node_details.firmware_version
                            end

                            if info.lqm and info.lqm.enabled and info.lqm.info and info.lqm.info.trackers then
                                for _, rtrack in pairs(info.lqm.info.trackers)
                                do
                                    if myhostname == canonical_hostname(rtrack.hostname) then
                                        track.rev_ping_success_time = rtrack.ping_success_time
                                        track.rev_ping_quality = rtrack.ping_quality
                                        track.rev_quality = rtrack.quality
                                        break
                                    end
                                end
                            end

                            if track.type == "RF" then
                                rflinks[track.mac] = nil
                                if info.lqm and info.lqm.enabled and info.lqm.info and info.lqm.info.trackers then
                                    rflinks[track.mac] = {}
                                    for _, rtrack in pairs(info.lqm.info.trackers)
                                    do
                                        if rtrack.type == "RF" or not rtrack.type then
                                            local rhostname = canonical_hostname(rtrack.hostname)
                                            if rtrack.ip and rtrack.routable then
                                                local rdistance = nil
                                                if tonumber(rtrack.lat) and tonumber(rtrack.lon) and lat and lon then
                                                    rdistance = calc_distance(lat, lon, tonumber(rtrack.lat), tonumber(rtrack.lon))
                                                end
                                                rflinks[track.mac][rtrack.ip] = {
                                                    ip = rtrack.ip,
                                                    hostname = rhostname,
                                                    distance = rdistance
                                                }
                                            end
                                            if myhostname == rhostname then
                                                track.rev_snr = (track.rev_snr and rtrack.snr) and round(snr_run_avg * track.rev_snr + (1 - snr_run_avg) * rtrack.snr) or rtrack.snr
                                            end
                                        end
                                    end
                                    for ip, link in pairs(info.link_info)
                                    do
                                        if link.hostname and link.linkType == "DTD" then
                                            dtdlinks[track.mac][canonical_hostname(link.hostname)] = true
                                        end
                                    end
                                elseif info.link_info then
                                    rflinks[track.mac] = {}
                                    -- If there's no LQM information we fallback on using link information.
                                    for ip, link in pairs(info.link_info)
                                    do
                                        local rhostname = canonical_hostname(link.hostname)
                                        if link.linkType == "RF" then
                                            rflinks[track.mac][ip] = {
                                                ip = ip,
                                                hostname = rhostname
                                            }
                                        end
                                        if rhostname then
                                            if link.linkType == "DTD" then
                                                dtdlinks[track.mac][rhostname] = true
                                            elseif link.linkType == "RF" and link.signal and link.noise and myhostname == rhostname then
                                                local snr = link.signal - link.noise
                                                track.rev_snr = track.rev_snr and round(snr_run_avg * track.rev_snr + (1 - snr_run_avg) * snr) or snr
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Update avg snr using both ends (if we have them)
            if track.snr then
                if track.rev_snr then
                    track.avg_snr = round((track.snr + track.rev_snr) / 2)
                else
                    track.avg_snr = track.snr
                end
            else
                track.avg_snr = nil
            end

            -- Count number of pending trackers
            if is_pending(track) then
                pending_count = pending_count + 1
            end

            -- Ping addresses and penalize quality for excessively slow links
            if should_ping(track) then
                local success = false
                local ptime

                if track.type ~= "Tunnel" and track.type ~= "Wireguard" then
                    -- For devices which support ARP, send an ARP request and wait for a reply. This avoids the other ends routing
                    -- table and firewall messing up the response packet.
                    local pstart = gettimems()
                    if os.execute(ARPING .. " -q -c 1 -D -w " .. round(ping_timeout) .. " -I " .. track.device .. " " .. track.ip) ~= 0 then
                        success = true
                    end
                    ptime = gettimems() - pstart
                end
                if not success then
                    if track.routable then
                        -- If that fails, measure the "ping" time directly to the device by sending a UDP packet
                        local sigsock = nixio.socket("inet", "dgram")
                        sigsock:setopt("socket", "rcvtimeo", ping_timeout)
                        sigsock:setopt("socket", "bindtodevice", track.device)
                        sigsock:setopt("socket", "dontroute", 1)
                        -- Must connect or we wont see the error
                        sigsock:connect(track.ip, 8080)
                        local pstart = gettimems()
                        sigsock:send("")
                        -- There's no actual UDP server at the other end so recv will either timeout and return 'false' if the link is slow,
                        -- or will error and return 'nil' if there is a node and it send back an ICMP error quickly (which for our purposes is a positive)
                        if sigsock:recv(0) ~= false then
                            success = true
                        end
                        ptime = gettimems() - pstart
                        sigsock:close()
                    else
                        -- We can't ping non-routable targets so don't consider them errors
                        ptime = nil
                    end
                end

                wait_for_ticks(0)

                track.ping_quality = track.ping_quality and (track.ping_quality + 1) or 100
                if ptime then
                    if success then
                        track.ping_success_time = track.ping_success_time and (track.ping_success_time * ping_time_run_avg + ptime * (1 - ping_time_run_avg)) or ptime
                    else
                        track.ping_quality = track.ping_quality - config.ping_penalty
                    end
                end
                track.ping_quality = math.max(0, math.min(100, track.ping_quality))
                if not success and track.type == "DtD" and track.firstseen == now then
                    -- If local ping immediately fail, ditch this tracker. This can happen sometimes when we
                    -- find arp entries which aren't valid.
                    tracker[track.mac] = nil
                end
            else
                track.ping_quality = nil
                track.ping_success_time = nil
            end

            -- Calculate overall link quality
            if track.tx_quality then
                if track.ping_quality then
                    track.quality = round((track.tx_quality + track.ping_quality) / 2)
                else
                    track.quality = round(track.tx_quality)
                end
            elseif track.ping_quality then
                track.quality = round(track.ping_quality)
            else
                track.quality = nil
            end
            if track.quality and track.quality == 0 and not track.quality0_seen then
                track.quality0_seen = now
            end

            track.node_route_count = 0
        end

        --
        -- Pull in the routing table to see how many node routes are associated with each tracker.
        -- We don't do this for supernodes as the table is very big and we don't use the information.
        -- Don't pull the data from OLSR as this can be too distruptive to its operation on slower nodes
        -- with large routing tables.
        --
        if not is_supernode then
            total_node_route_count = 0
            for line in io.popen(IPCMD .. " route show table 30"):lines()
            do
                local gw = line:match("^10%.%d+%.%d+%.%d+ via (%d+%.%d+%.%d+%.%d+) dev")
                if gw then
                    local track = ip2tracker[gw];
                    if track then
                        track.node_route_count = track.node_route_count + 1
                        total_node_route_count = total_node_route_count + 1
                    end
                end
            end
        end

        --
        -- At this point we have gather all the data we need to determine which links are best to use and
        -- which links should be blocked.
        --
        for _, track in pairs(tracker)
        do
            for _ = 1,1
            do
                -- Clear state
                local oldblocks = track.blocks;
                track.blocks = {
                    dtd = false,
                    signal = false,
                    distance = false,
                    pair = false,
                    quality = false
                }
    
                -- Always allow if user requested it
                for val in string.gmatch(config.user_allows, "([^,]+)")
                do
                    if val:gsub("%s+", ""):gsub("-", ":"):lower() == track.mac then
                        track.user_allow = true
                        break
                    end
                end
                if track.user_allow then
                    break
                end

                -- Block if user requested it
                for val in string.gmatch(config.user_blocks, "([^,]+)")
                do
                    if val:gsub("%s+", ""):gsub("-", ":"):lower() == track.mac then
                        track.blocks.user = true
                        break
                    end
                end
                if track.blocks.user then
                    break
                end
        
                -- SNR and distance blocks only related to RF links
                if track.type == "RF" then

                    -- Block any nodes which are too distant
                    if track.distance and (track.distance < config.min_distance or track.distance > config.max_distance) then
                        track.blocks.distance = true
                        break
                    end

                    -- If we have a direct dtd connection to this device, make sure we use that
                    for _, dtd in pairs(tracker) do
                        if dtd.type == "DtD" and dtd.hostname == track.hostname then
                            if dtd.distance and dtd.distance < dtd_distance and dtd.routable then
                                track.blocks.dtd = true
                            end
                            break
                        end
                    end
                    if track.blocks.dtd then
                        break
                    end

                    -- When unblocked link signal becomes too low, block
                    if not oldblocks.signal then
                        if track.snr < config.low or (track.rev_snr and track.rev_snr < config.low) then
                            track.blocks.signal = true
                            break
                        end 
                    -- when blocked link becomes (low+margin) again, dont maintain block
                    else
                        if track.snr < config.low + config.margin or (track.rev_snr and track.rev_snr < config.low + config.margin) then
                            track.blocks.signal = true
                            break
                        else
                            -- When signal is good enough to unblock a link but the quality is low, artificially bump
                            -- it up to give the link chance to recover
                            if oldblocks.quality then
                                track.quality = config.min_quality + config.margin_quality
                                track.quality0_seen = nil
                            end
                        end
                    end

                    -- If we have a quality block and the snr gets sufficiently better, bump the quality to unblock it and see if things have improved
                    if oldblocks.quality and track.quality_block_snr and track.avg_snr and track.avg_snr > track.quality_block_snr + config.margin then
                        track.quality = config.min_quality + config.margin_quality
                        track.quality0_seen = nil
                    end
                end

                -- Block if quality is poor
                if track.quality and (track.type ~= "DtD" or (track.distance and track.distance >= dtd_distance)) then
                    if not oldblocks.quality then
                        if track.quality < config.min_quality then
                            track.blocks.quality = true
                            track.quality_block_snr = track.avg_snr
                        end
                    else
                        if track.quality < config.min_quality + config.margin_quality then
                            track.blocks.quality = true
                        end
                    end
                end
            end
        end

        -- Eliminate link pairs, where we might have links to multiple radios at the same site
        -- Find them and select the one with the best SNR avg on both ends
        for _, track in pairs(tracker)
        do
            if track.hostname and not should_nonpair_block(track) then
                -- Get a list of radio pairs. These are radios we're associated with which are DTD'ed together
                local tracklist = { track }
                for _, track2 in pairs(tracker)
                do
                    if track ~= track2 and track2.hostname and not should_nonpair_block(track2) then
                        if dtdlinks[track.mac] and dtdlinks[track.mac][track2.hostname] then
                            if not (track.lat and track.lon and track2.lat and track2.lon) or calc_distance(track.lat, track.lon, track2.lat, track2.lon) < dtd_distance then
                                tracklist[#tracklist + 1] = track2
                            end
                        end
                    end
                end
                if #tracklist == 1 then
                    track.blocks.dup = false
                else
                    -- Find the link with the best average snr overall as well as unblocked
                    local bestany = track
                    local bestunblocked = nil
                    for _, track2 in ipairs(tracklist)
                    do
                        if track2.avg_snr > bestany.avg_snr then
                            bestany = track2
                        end
                        if not track2.blocks.dup and (not bestunblocked or (track2.avg_snr > bestunblocked.avg_snr)) then
                            bestunblocked = track2
                        end
                    end
                    -- A new winner if it's sufficiently better than the current
                    if not bestunblocked or bestany.avg_snr >= bestunblocked.avg_snr + config.margin then
                        bestunblocked = bestany
                    end
                    for _, track2 in ipairs(tracklist)
                    do
                        if track2 == bestunblocked then
                            track2.blocks.dup = false
                        else
                            track2.blocks.dup = true
                        end
                    end
                end
            end
        end

        --
        -- We now have updated state on what is blocked and what is not.
        -- Reflect this state with the firewall and various other
        -- node parameters (e.g. rts, coverage)
        --
        local distance = -1
        -- Update the block state and calculate the routable distance
        for _, track in pairs(tracker)
        do
            if is_connected(track) then
                if update_block(track) == "unblocked" then
                    -- If the link becomes unblocked, return it to pending state
                    track.pending = now + pending_timeout
                end

                if track.type == "RF" then
                    -- Find the most distant, unblocked, RF node
                    if track.distance then
                        if track.distance > distance and (not track.blocked or is_pending(track)) then
                            distance = track.distance
                        end
                    elseif is_pending(track) then
                        distance = config.max_distance
                    end
                end
            end

            -- Remove any trackers which are too old or if they disconnect when first seen
            if ((now > track.lastseen + lastseen_timeout) or
                (now > track.rev_lastseen + lastseen_timeout) or
                (not is_connected(track) and track.firstseen + pending_timeout > now) or
                (track.quality0_seen and now > track.quality0_seen + lastseen_timeout)
            ) then
                force_remove_block(track)
                tracker[track.mac] = nil
            end
        end

        -- Default distances if we haven't calcuated anything
        if distance < 0 then
            if config.auto_distance > 0 then
                distance = config.auto_distance
            else
                distance = config.max_distance
            end
        end
        -- Update the wifi distance
        local coverage = math.min(255, math.floor((distance * 2 * 0.0033) / 3))
        if config.enable and coverage ~= last_coverage then
            iw_set("coverage " .. coverage)
            last_coverage = coverage
        end

        -- Set the RTS/CTS state depending on whether everyone can see everyone
        -- Build a list of all the nodes our neighbors can see
        local theres = {}
        for mac, rfneighbor in pairs(rflinks)
        do
            local track = tracker[mac]
            if track and not track.blocked and track.routable then
                for nip, ninfo in pairs(rfneighbor)
                do
                    theres[nip] = ninfo
                end
            end
        end
        -- Remove all the nodes we can see from this set
        for _, track in pairs(tracker)
        do
            if track.ip then
                theres[track.ip] = nil
            end
        end
        -- Including ourself
        theres[myip] = nil

        -- If there are any nodes left, then our neighbors can see hidden nodes we cant. Enable RTS/CTS
        local hidden = {}
        for _, ninfo in pairs(theres)
        do
            hidden[#hidden + 1] = ninfo
        end
        if config.enable and (#hidden == 0) ~= (#hidden_nodes == 0) and config.rts_threshold >= 0 and config.rts_threshold <= 2347 then
            if #hidden > 0 then
                iw_set("rts " .. config.rts_threshold)
            else
                iw_set("rts off")
            end
        end
        hidden_nodes = hidden

        -- Save this for the UI
        f = io.open("/tmp/lqm.info", "w")
        if f then
            f:write(luci.jsonc.stringify({
                now = now,
                trackers = tracker,
                distance = distance,
                coverage = coverage,
                hidden_nodes = hidden_nodes,
                total_node_route_count = total_node_route_count
            }, true))
            f:close()
        end

        -- Save valid (unblocked) rf mac list for use by OLSR
        if config.enable and phy ~= "none" then
            if pending_count > 0 then
                os.remove( "/tmp/lqm." .. phy .. ".macs")
            else
                local tmpfile = "/tmp/lqm." .. phy .. ".macs.tmp"
                f = io.open(tmpfile, "w")
                if f then
                    for _, track in pairs(tracker)
                    do
                        if track.device == wlan and is_connected(track) and not track.blocked then
                            f:write(track.mac .. "\n")
                        end
                    end
                    f:close()
                    filecopy(tmpfile, "/tmp/lqm." .. phy .. ".macs", true)
                    os.remove(tmpfile)
                end
            end
        end

        wait_for_ticks(60) -- 1 minute
    end
    os.remove("/tmp/lqm.reset")
end

function lqm()
    -- Let things startup for a while before we begin
    wait_for_ticks(math.max(0, 30 - nixio.sysinfo().uptime))
    while true
    do
        lqm_run()
    end
end

return lqm
