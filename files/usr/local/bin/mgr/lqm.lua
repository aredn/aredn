--[[

	Copyright (C) 2022 Tim Wilkinson
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

	Additional use restrictions exist on the AREDN(TM) trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version

--]]

local ip = require("luci.ip")
local info = require("aredn.info")
local socket = require("socket")

local refresh_timeout = 15 * 60 -- refresh high cost data every 15 minutes
local pending_timeout = 5 * 60 -- pending node wait 5 minutes before they are included
local lastseen_timeout = 60 * 60 -- age out nodes we've not seen for 1 hour
local snr_run_avg = 0.8 -- snr running average
local quality_min_packets = 100 -- minimum number of tx packets before we can safely calculate the link quality
local quality_injection_max = 10 -- number of packets to inject into poor links to update quality
local tx_quality_run_avg = 0.8 -- tx quality running average
local ping_timeout = 1.0 -- timeout before ping gives a qualtiy penalty
local ping_time_run_avg = 0.8 -- ping time runnng average
local bitrate_run_avg = 0.8 -- rx/tx running average
local dtd_distance = 50 -- distance (meters) after which nodes connected with DtD links are considered different sites
local connect_timeout = 5 -- timeout (seconds) when fetching information from other nodes
local speed_time = 10 --
local speed_limit = 1000 -- close connection if it's too slow (< 1kB/s for 10 seconds)

local NFT = "/usr/sbin/nft"
local IW = "/usr/sbin/iw"

local now = 0

function get_config()
    local c = uci.cursor() -- each time as /etc/config/aredn may have changed
    return {
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

function should_block(track)
    if track.user_allow then
        return false
    elseif is_pending(track) then
        return track.blocks.dtd or track.blocks.user
    else
        return track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.dup or track.blocks.quality
    end
end

function should_nonpair_block(track)
    return track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.quality or track.type ~= "RF"
end

function inject_quality_traffic(track)
    return track.ip and track.type ~= "DtD" and track.blocked and track.blocks.quality and not (
        track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.dup
    )
end

function should_ping(track)
    if track.ip and is_connected(track) and not (track.blocks.dtd or track.blocks.distance or track.blocks.user) then
        return true
    else
        return false
    end
end

function nft_handle(list, query)
    for line in io.popen(NFT .. " -a list chain ip fw4 " .. list):lines()
    do
        local handle = line:match(query .. ".*# handle (%d+)$")
        if handle then
            return handle
        end
    end
    return nil
end

function update_block(track)
    if should_block(track) then
        track.blocked = true
        if track.type == "Tunnel" then
            if not nft_handle("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop") then
                os.execute(NFT .. " insert rule ip fw4 input_lqm iifname \\\"" .. track.device .. "\\\" udp dport 698 drop 2> /dev/null")
                return "blocked"
            end
        else
            if not nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac:lower() .. " drop") then
                os.execute(NFT .. " insert rule ip fw4 input_lqm udp dport 698 ether saddr " .. track.mac .. " drop 2> /dev/null")
                return "blocked"
            end
        end
    else
        track.blocked = false
        if track.type == "Tunnel" then
            local handle = nft_handle("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop")
            if handle then
                os.execute(NFT .. " delete rule ip fw4 input_lqm handle " .. handle)
                return "unblocked"
            end
        else
            local handle = nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac:lower() .. " drop")
            if handle then
                os.execute(NFT .. " delete rule ip fw4 input_lqm handle " .. handle)
                return "unblocked"
            end
        end
    end
    return "unchanged"
end

function force_remove_block(track)
    track.blocked = false
    local handle = nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac:lower() .. " drop")
    if handle then
        os.execute(NFT .. " delete rule ip fw4 input_lqm handle " .. handle)
    end
    handle = nft_handle("input_lqm", "iifname \\\"" .. track.device .. "\\\" udp dport 698 drop")
    if handle then
        os.execute(NFT .. " delete rule ip fw4 input_lqm handle " .. handle)
    end
end

-- Distance in meters between two points
function calc_distance(lat1, lon1, lat2, lon2)
    local r2 = 12742000 -- diameter earth (meters)
    local p = 0.017453292519943295 --  Math.PI / 180
    local v = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return math.floor(r2 * math.asin(math.sqrt(v)))
end

-- Canonical hostname
function canonical_hostname(hostname)
    if hostname then
        hostname = hostname:lower():gsub("^dtdlink%.",""):gsub("^mid%d+%.",""):gsub("^xlink%d+%.",""):gsub("%.local%.mesh$", "")
    end
    return hostname
end

local cursor = uci.cursor()
local cursorm = uci.cursor("/etc/config.mesh")

local myhostname = canonical_hostname(info.get_nvram("node") or "localnode")
local myip = cursor:get("network", "wifi", "ipaddr")

-- Clear old data
local f = io.open("/tmp/lqm.info", "w")
f:write('{"trackers":{},"hidden_nodes":[]}')
f:close()

-- Get radio
local radiomode = "none"
local wlan = aredn.hardware.get_iface_name("wifi")
local phy = "none"
if wlan:match("^wlan(%d+)$") then
  phy = iwinfo.nl80211.phyname(wlan)
  radiomode = "adhoc"
end

function lqm()

    if cursor:get("aredn", "@lqm[0]", "enable") ~= "1" then
        exit_app()
        return
    end

    -- Let things startup for a while before we begin
    wait_for_ticks(math.max(1, 30 - nixio.sysinfo().uptime))

    -- Create filters (cannot create during install as they disappear on reboot)
    os.execute(NFT .. " flush chain ip fw4 input_lqm 2> /dev/null")
    os.execute(NFT .. " delete chain ip fw4 input_lqm 2> /dev/null")
    os.execute(NFT .. " add chain ip fw4 input_lqm 2> /dev/null")
    local handle = nft_handle("input", "jump input_lqm comment")
    if handle then
        os.execute(NFT .. " delete rule ip fw4 input handle " .. handle)
    end
    os.execute(NFT .. " insert rule ip fw4 input jump input_lqm comment \\\"block low quality links\\\"")

    -- We dont know any distances yet
    os.execute(IW .. " " .. phy .. " set distance auto > /dev/null 2>&1")
    -- Or any hidden nodes
    os.execute(IW .. " " .. phy .. " set rts off > /dev/null 2>&1")

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
    while true
    do
        now = nixio.sysinfo().uptime

        local config = get_config()

        local lat = cursor:get("aredn", "@location[0]", "lat")
        local lon = cursor:get("aredn", "@location[0]", "lon")
        lat = tonumber(lat)
        lon = tonumber(lon)

        local arps = {}
        arptable(
            function (entry)
                if entry["Flags"] ~= "0x0" then
                    entry["HW address"] = entry["HW address"]:upper()
                    arps[#arps + 1] = entry
                end
            end
        )

        -- Know our macs so we can exclude them
        local our_macs = {}
        for _, i in ipairs(nixio.getifaddrs()) do
            if i.family == "packet" and i.addr then
                our_macs[i.addr:upper()] = true
            end
        end

        local stations = {}

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
                noise = math.ceil(noise * 0.9 + cnoise * 0.1)
            end
            for line in io.popen(IW .. " " .. wlan .. " station dump"):lines()
            do
                local mac = line:match("^Station ([0-9a-fA-F:]+) ")
                if mac then
                    station = {
                        type = "RF",
                        device = wlan,
                        mac = mac:upper(),
                        signal = 0,
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
                    stations[#stations + 1] = station
                else
                    for k, v in pairs(kv)
                    do
                        local val = line:match(k .. "%s*([%d%-]+)")
                        if val then
                            station[v] = tonumber(val)
                            if v == "tx_bitrate" or v == "rx_bitrate" then
                                station[v] = station[v] * channel_bw_scale
                            end
                        end
                    end
                end
            end
        end

        -- Tunnels
        local tunnel = {}
        for line in io.popen("ifconfig"):lines()
        do
            local tun = line:match("^(tun%d+)%s")
            if tun then
                tunnel = {
                    type = "Tunnel",
                    device = tun,
                    signal = nil,
                    ip = nil,
                    mac = nil,
                    tx_packets = 0,
                    tx_fail = 0,
                    tx_retries = 0,
                    tx_bitrate = 0,
                    rx_bitrate = 0
                }
                stations[#stations + 1] = tunnel
            else
                local ip = line:match("P-t-P:(%d+%.%d+%.%d+%.%d+)")
                if ip then
                    tunnel.ip = ip
                    -- Fake a mac from the ip
                    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
                    tunnel.mac = string.format("00:00:%02X:%02X:%02X:%02X", a, b, c, d)
                end
                local txp, txf = line:match("TX packets:(%d+)%s+errors:(%d+)")
                if txp and txf then
                    tunnel.tx_packets = txp
                    tunnel.tx_fail = txf
                end
            end
        end

        -- Wireguard
        cursorm:foreach("wireguard", "client",
            function(s)
                if s.enabled == "1" then
                    local a, b, c, d = s.clientip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
                    stations[#stations + 1] = {
                        type = "Tunnel",
                        device = "wgc",
                        signal = nil,
                        ip = s.clientip,
                        mac = string.format("00:00:%02X:%02X:%02X:%02X", a, b, c, d),
                        tx_packets = 0,
                        tx_fail = 0,
                        tx_retries = 0,
                        tx_bitrate = 0,
                        rx_bitrate = 0
                    }
                end
            end
        )
        local wgs = 0
        cursorm:foreach("vtun", "server",
            function(s)
                if s.enabled == "1" and s.netip:match("/") then
                    local a, b, c, d, m = s.netip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)$")
                    local d = nixio.bit.band(d, nixio.bit.lshift(255, 32 - m)) + 1
                    stations[#stations + 1] = {
                        type = "Tunnel",
                        device = "wgs" .. wgs,
                        signal = nil,
                        ip = string.format("%d.%d.%d.%d", a, b, c, d),
                        mac = string.format("00:00:%02X:%02X:%02X:%02X", a, b, c, d),
                        tx_packets = 0,
                        tx_fail = 0,
                        tx_retries = 0,
                        tx_bitrate = 0,
                        rx_bitrate = 0
                    }
                    wgs = wgs + 1
                end
            end
        )

        -- DtD
        for _, entry in ipairs(arps)
        do
            if entry.Device:match("%.2$") or entry.Device:match("^br%-dtdlink") then
                stations[#stations + 1] = {
                    type = "DtD",
                    device = entry.Device,
                    signal = nil,
                    ip = entry["IP address"],
                    mac = entry["HW address"],
                    tx_packets = 0,
                    tx_fail = 0,
                    tx_retries = 0,
                    tx_bitrate = 0,
                    rx_bitrate = 0
                }
            end
        end

        -- Xlink
        if nixio.fs.stat("/etc/config/xlink") then
            uci.cursor("/etc/config"):foreach("xlink", "interface",
                function(section)
                    if section.ifname then
                        for _, entry in ipairs(arps)
                        do
                            if entry["Device"] == section.ifname then
                                stations[#stations + 1] = {
                                    type = "Xlink",
                                    device = section.ifname,
                                    signal = nil,
                                    ip = entry["IP address"],
                                    mac = entry["HW address"],
                                    tx_packets = 0,
                                    tx_fail = 0,
                                    tx_retries = 0,
                                    tx_bitrate = 0,
                                    rx_bitrate = 0
                                }
                            end
                        end
                    end
                end
            )
        end

        for _, station in ipairs(stations)
        do
            if station.signal ~= 0 and not our_macs[station.mac] then
                if not tracker[station.mac] then
                    tracker[station.mac] = {
                        type = station.type,
                        device = station.device,
                        firstseen = now,
                        lastseen = now,
                        pending = now + pending_timeout,
                        refresh = 0,
                        mac = station.mac,
                        station = nil,
                        ip = nil,
                        hostname = nil,
                        lat = nil,
                        lon = nil,
                        distance = nil,
                        blocks = {
                            dtd = false,
                            signal = false,
                            distance = false,
                            pair = false,
                            quality = false
                        },
                        blocked = false,
                        snr = 0,
                        rev_snr = nil,
                        avg_snr = 0,
                        last_tx = nil,
                        last_tx_total = nil,
                        tx_quality = 100,
                        ping_quality = 100,
                        ping_success_time = 0,
                        tx_bitrate = nil,
                        rx_bitrate = nil,
                        quality = 100,
                        exposed = false
                    }
                end
                local track = tracker[station.mac]

                -- IP and Hostname
                if station.ip and station.ip ~= track.ip then
                    track.ip = station.ip
                    track.hostname = nil
                end
                if not track.hostname and track.ip then
                    local hostname = nixio.getnameinfo(track.ip)
                    if hostname then
                        track.hostname = canonical_hostname(hostname)
                    end
                end

                -- Running average SNR
                if station.type == "RF" then
                    local snr = station.signal - station.noise
                    if track.snr == 0 then
                        track.snr = snr
                    else
                        track.snr = math.ceil(snr_run_avg * track.snr + (1 - snr_run_avg) * snr)
                    end
                end

                -- Running average estimate of link quality
                local tx = station.tx_packets
                local tx_total = station.tx_packets + station.tx_fail + station.tx_retries
                if not track.last_tx then
                    track.last_tx = tx
                    track.last_tx_total = tx_total
                    track.tx_quality = 100
                elseif tx_total >= track.last_tx_total + quality_min_packets then
                    local tx_quality = 100 * (tx - track.last_tx) / (tx_total - track.last_tx_total)
                    track.last_tx = tx
                    track.last_tx_total = tx_total
                    track.last_quality = tx_quality
                    track.tx_quality = math.min(100, math.max(0, math.ceil(tx_quality_run_avg * track.tx_quality + (1 - tx_quality_run_avg) * tx_quality)))
                end
                if not track.tx_bitrate then
                    track.tx_bitrate = station.tx_bitrate
                else
                    track.tx_bitrate = track.tx_bitrate * bitrate_run_avg + station.tx_bitrate * (1 - bitrate_run_avg)
                end
                if not track.rx_bitrate then
                    track.rx_bitrate = station.rx_bitrate
                else
                    track.rx_bitrate = track.rx_bitrate * bitrate_run_avg + station.rx_bitrate * (1 - bitrate_run_avg)
                end

                track.lastseen = now
            end
        end

        -- Count the RF links we have
        local rfcount = 0
        for _, track in pairs(tracker)
        do
            if track.type == "RF" then
                rfcount = rfcount + 1
            end
        end

        -- Update link tracking state
        for _, track in pairs(tracker)
        do
            -- Only refresh remote attributes periodically
            if track.ip and (now > track.refresh or is_pending(track)) then
                track.refresh = now + refresh_timeout

                local old_rev_snr = track.rev_snr
                track.rev_snr = null
                dtdlinks[track.mac] = {}
                track.exposed = false

                -- Refresh the hostname periodically as it can change
                local hostname = nixio.getnameinfo(track.ip)
                if hostname then
                    track.hostname = canonical_hostname(hostname)
                end

                local raw = io.popen("/usr/bin/curl --retry 0 --connect-timeout " .. connect_timeout .. " --speed-time " .. speed_time .. " --speed-limit " .. speed_limit .. " -s \"http://" .. track.ip .. ":8080/cgi-bin/sysinfo.json?link_info=1&lqm=1\" -o - 2> /dev/null")
                local info = luci.jsonc.parse(raw:read("*a"))
                raw:close()
                if info then
                    rflinks[track.mac] = nil
                    if tonumber(info.lat) and tonumber(info.lon) then
                        track.lat = tonumber(info.lat)
                        track.lon = tonumber(info.lon)
                        if lat and lon then
                            track.distance = calc_distance(lat, lon, track.lat, track.lon)
                        end
                    end
                    if track.type == "RF" then
                        if info.lqm and info.lqm.enabled and info.lqm.info and info.lqm.info.trackers then
                            rflinks[track.mac] = {}
                            for _, rtrack in pairs(info.lqm.info.trackers)
                            do
                                if not rtrack.type or rtrack.type == "RF" then
                                    local rhostname = canonical_hostname(rtrack.hostname)
                                    if rtrack.ip then
                                        local rdistance = nil
                                        if tonumber(rtrack.lat) and tonumber(rtrack.lon) and lat and lon then
                                            rdistance = calc_distance(lat, lon, tonumber(rtrack.lat), tonumber(rtrack.lon))
                                        end
                                        if rtrack.routable then
                                            rflinks[track.mac][rtrack.ip] = {
                                                ip = rtrack.ip,
                                                hostname = rhostname,
                                                distance = rdistance
                                            }
                                        end
                                    end
                                    if myhostname == rhostname then
                                        if not old_rev_snr or not rtrack.snr then
                                            track.rev_snr = rtrack.snr
                                        else
                                            track.rev_snr = math.ceil(snr_run_avg * old_rev_snr + (1 - snr_run_avg) * rtrack.snr)
                                        end
                                    end
                                    if rtrack.routable and not tracker[rtrack.mac] and not our_macs[rtrack.mac] and rfcount > 1 then
                                        track.exposed = true
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
                                if link.linkType == "RF" then
                                    rflinks[track.mac][ip] = {
                                        ip = ip,
                                        hostname = canonical_hostname(link.hostname)
                                    }
                                end
                                if link.hostname then
                                    local hostname = canonical_hostname(link.hostname)
                                    if link.linkType == "DTD" then
                                        dtdlinks[track.mac][hostname] = true
                                    elseif link.linkType == "RF" and link.signal and link.noise and myhostname == hostname then
                                        local snr = link.signal - link.noise
                                        if not old_rev_snr then
                                            track.rev_snr = snr
                                        else
                                            track.rev_snr = math.ceil(snr_run_avg * old_rev_snr + (1 - snr_run_avg) * snr)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if is_connected(track) then
                -- Update avg snr using both ends (if we have them)
                track.avg_snr = (track.snr + (track.rev_snr or track.snr)) / 2
                -- Routable
                local rt = track.ip and ip.route(track.ip) or nil
                if rt and tostring(rt.gw) == track.ip then
                    track.routable = true
                else
                    track.routable = false
                end
            else
                -- Clear snr when we've not seen the node this time (disconnected)
                track.snr = 0
                track.rev_snr = nil
                track.routable = false
            end

            -- Ping addresses and penalize quality for excessively slow links
            if config.ping_penalty <= 0 then
                track.ping_quality = 100
            elseif should_ping(track) then
                local success = 100
                local ptime = ping_timeout

                -- Measure the "ping" time directly to the device
                local sigsock = nixio.socket("inet", "dgram")
                sigsock:setopt("socket", "rcvtimeo", ping_timeout)
                sigsock:setopt("socket", "bindtodevice", track.device)
                sigsock:setopt("socket", "dontroute", 1)
                -- Must connect or we wont see the error
                sigsock:connect(track.ip, 8080)
                local pstart = socket.gettime(0)
                sigsock:send("")
                -- There's no actual UDP server at the other end so recv will either timeout and return 'false' if the link is slow,
                -- or will error and return 'nil' if there is a node and it send back an ICMP error quickly (which for our purposes is a positive)
                if sigsock:recv(0) == false then
                    success = 0
                end
                ptime = socket.gettime(0) - pstart
                sigsock:close()

                local ping_loss_run_avg = 1 - config.ping_penalty / 100
                if success > 0 then
                    track.ping_success_time = track.ping_success_time * ping_time_run_avg + ptime * (1 - ping_time_run_avg)
                end
                track.ping_quality = math.ceil(ping_loss_run_avg * track.ping_quality + (1 - ping_loss_run_avg) * success)
                if success == 0 and track.type == "DtD" and track.firstseen == now then
                    -- If local ping immediately fail, ditch this tracker. This can happen sometimes when we
                    -- find arp entries which aren't valid.
                    tracker[track.mac] = nil
                end
            end

            -- Calculate overall link quality
            track.quality = math.ceil((track.tx_quality + track.ping_quality) / 2)

            -- Inject traffic into links with poor quality
            -- We do this so we can keep measuring the current link quality otherwise, once it becomes
            -- bad, it wont be used and we can never tell if it becomes good again. Beware injecting too
            -- much traffic because, on very poor links, this can generate multiple retries per packet, flooding
            -- the wifi channel
            if inject_quality_traffic(track) then
                -- Create socket we use to inject traffic into degraded links
                -- This is setup so it ignores routing and will always send to the correct wifi station
                local sigsock = nixio.socket("inet", "dgram")
                sigsock:setopt("socket", "bindtodevice", track.device)
                sigsock:setopt("socket", "dontroute", 1)
                for _ = 1,quality_injection_max
                do
                    sigsock:sendto("", track.ip, 8080)
                end
                sigsock:close()
            end
        end

        -- Work out what to block, unblock and limit
        for _, track in pairs(tracker)
        do
            -- SNR and distance blocks only related to RF links
            if track.type == "RF" then

                -- If we have a direct dtd connection to this device, make sure we use that
                track.blocks.dtd = false
                for _, dtd in pairs(tracker) do
                    if dtd.type == "DtD" and dtd.hostname == track.hostname then
                        if dtd.distance and dtd.distance < dtd_distance then
                            track.blocks.dtd = true
                        end
                        break
                    end
                end

                -- When unblocked link signal becomes too low, block
                if not track.blocks.signal then
                    if track.snr < config.low or (track.rev_snr and track.rev_snr < config.low) then
                        track.blocks.signal = true
                    end 
                -- when blocked link becomes (low+margin) again, unblock
                else
                    if track.snr >= config.low + config.margin and (not track.rev_snr or track.rev_snr >= config.low + config.margin) then
                        track.blocks.signal = false
                        -- When signal is good enough to unblock a link but the quality is low, artificially bump
                        -- it up to give the link chance to recover
                        if track.blocks.quality then
                            track.quality = config.min_quality + config.margin_quality
                        end
                    end 
                end

                -- Block any nodes which are too distant
                if not track.distance or (track.distance >= config.min_distance and track.distance <= config.max_distance) then
                    track.blocks.distance = false
                else
                    track.blocks.distance = true
                end

            end

            -- Block if user requested it
            track.blocks.user = false
            for val in string.gmatch(config.user_blocks, "([^,]+)")
            do
                if val:gsub("%s+", ""):gsub("-", ":"):upper() == track.mac then
                    track.blocks.user = true
                    break
                end
            end

            -- Block if quality is poor
            if track.quality then
                if not track.blocks.quality and track.quality < config.min_quality and (track.type ~= "DtD" or (track.distance and track.distance >= dtd_distance)) then
                    track.blocks.quality = true
                elseif track.blocks.quality and track.quality >= config.min_quality + config.margin_quality then
                    track.blocks.quality = false
                end
            end

            -- Always allow if user requested it
            track.user_allow = false;
            for val in string.gmatch(config.user_allows, "([^,]+)")
            do
                if val:gsub("%s+", ""):gsub("-", ":"):upper() == track.mac then
                    track.user_allow = true
                    break
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
                        if dtdlinks[track.mac][track2.hostname] then
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

        local distance = -1

        -- Update the block state and calculate the routable distance
        for _, track in pairs(tracker)
        do
            if is_connected(track) then 
                if update_block(track) == "unblocked" then
                    -- If the link becomes unblocked, return it to pending state
                    track.pending = now + pending_timeout
                end

                -- Find the most distant, unblocked, RF node
                if track.type == "RF" then
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
            if ((now > track.lastseen + lastseen_timeout) or (not is_connected(track) and track.firstseen + pending_timeout > now)) then
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
        if coverage ~= last_coverage then
            os.execute(IW .. " " .. phy .. " set coverage " .. coverage .. " > /dev/null 2>&1")
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
        -- Don't adjust RTS on ath10k for the moment - appear to be some bug to be worked out here
        if (#hidden == 0) ~= (#hidden_nodes == 0) and config.rts_threshold >= 0 and config.rts_threshold <= 2347 then
            if #hidden > 0 then
                os.execute(IW .. " " .. phy .. " set rts " .. config.rts_threshold .. " > /dev/null 2>&1")
            else
                os.execute(IW .. " " .. phy .. " set rts off > /dev/null 2>&1")
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
                hidden_nodes = hidden_nodes
            }, true))
            f:close()
        end

        wait_for_ticks(60) -- 1 minute
    end
end

return lqm
