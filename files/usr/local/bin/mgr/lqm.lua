--[[

	Copyright (C) 2022-2025 Tim Wilkinson
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

local luciip = require("luci.ip")
require("aredn.info")

local refresh_timeout_base = 12 * 60 -- refresh high cost data every 12 minutes
local refresh_timeout_limit = 17 * 60 -- to 17 minutes
local refresh_retry_timeout = 5 * 60
local lastseen_timeout = 24 * 60 * 60 -- age out nodes we've not seen for 24 hours
local snr_run_avg = 0.8 -- snr running average
local quality_min_packets = 100 -- minimum number of tx packets before we can safely calculate the link quality
local tx_quality_run_avg = 0.8 -- tx quality running average
local ping_timeout = 1.0 -- timeout before ping gives a qualtiy penalty
local ping_time_run_avg = 0.8 -- ping time runnng average
local bitrate_run_avg = 0.8 -- rx/tx running average
local dtd_distance = 50 -- distance (meters) after which nodes connected with DtD links are considered different sites
local connect_timeout = 5 -- timeout (seconds) when fetching information from other nodes
local default_short_retries = 20 -- More link-level retries helps overall tcp performance (factory default is 7)
local default_long_retries = 20 -- (factory default is 4)
local wireguard_alive_time = 600 -- 10 minutes
local default_max_distance = 80550 -- 50.1 miles
local rts_threshold = 1 -- RTS setting when hidden nodes are detected
local ping_penalty = 5 -- Cost of a failed ping to measure of a link's quality

local NFT = "/usr/sbin/nft"
local IW = "/usr/sbin/iw"
local ARPING = "/usr/sbin/arping"
local UFETCH = "/bin/uclient-fetch"
local IPCMD = "/sbin/ip"
local PING6 = "/bin/ping6"

local now = 0
local config = {}

local total_node_route_count = nil
local total_babel_route_count = nil

-- Get radio
local radiomode = "none"
local wlan = aredn.hardware.get_iface_name("wifi")
local phy = "none"
local radio = "none"
local wlanid = wlan:match("^wlan(%d+)$")
local ac = false;
if wlanid then
    phy = "phy" .. wlanid
    radio = "radio" .. wlanid
    radiomode = "mesh"
end
if aredn.hardware.get_radio().name:lower():match("ac") then
    ac = true
end

function update_config()
    local c = uci.cursor() -- each time as /etc/config/aredn may have changed
    local cm = uci.cursor("/etc/config.mesh")
    local max_distance = tonumber(cm:get("setup", "globals", radio .. "_distance") or default_max_distance)
    config = {
        max_distance = max_distance > 0 and max_distance or default_max_distance,
        user_blocks = c:get("aredn", "@lqm[0]", "user_blocks") or ""
    }
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

function gettime()
    local sec, usec = nixio.gettimeofday()
    return sec + usec / 1000000;
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
    return hostname and hostname:lower():gsub("^dtdlink%.",""):gsub("^mid%d+%.",""):gsub("^xlink%d+%.",""):gsub("^lan%.", ""):gsub("%.local%.mesh$", "")
end

local myhostname = canonical_hostname(aredn.info.get_nvram("node") or "localnode")
local myip = uci.cursor():get("network", "wifi", "ipaddr")
local is_supernode = uci.cursor():get("aredn", "@supernode[0]", "enable") == "1"

local wgsupport = nixio.fs.stat("/usr/bin/wg")

-- Clear old data
local f = io.open("/tmp/lqm.info", "w")
f:write('{"trackers":{},"hidden_nodes":[]}')
f:close()

function iw_set(cmd)
    if phy ~= "none" then
        os.execute(IW .. " " .. phy .. " set " .. cmd .. " > /dev/null 2>&1")
    end
end

function update_allow_list()
    local f = "/var/run/hostapd-" .. wlan .. ".maclist"
    local o = read_all(f)
    if not o then
        return false
    end
    local n = ""

    local peer = uci.cursor("/etc/config.mesh"):get("setup", "globals", radio .. "_peer")
    if peer then
        n = peer .. "\n"
    end
    if o == n then
        return false
    end
    write_all(f, n)
    os.execute("/usr/bin/killall -HUP hostapd")
    return true
end

function update_deny_list(tracker)
    local f = "/var/run/hostapd-" .. wlan .. ".maclist"
    local o = read_all(f)
    if not o then
        return false
    end
    local n = ""
    for mac, track in pairs(tracker)
    do
        if track.user_blocks then
            n = n .. mac .. "\n"
        end
    end
    if o == n then
        return false
    end
    write_all(f, n)
    os.execute("/usr/bin/killall -HUP hostapd")
    return true
end

function lqm_run()
    local noise = -95
    local tracker = {}
    local rflinks = {}
    local hidden_nodes = {}
    local last_coverage = -1
    local last_short_retries = -1
    local last_long_retries = -1
    local ptp = uci.cursor("/etc/config.mesh"):get("setup", "globals", radio .. "_mode") == "meshptp"

    update_config()

    -- We dont know any distances yet
    if ac then
        -- And AC doesn't support auto
        last_coverage = math.min(255, math.floor(config.max_distance / 450))
        iw_set("coverage " .. last_coverage)
    else
        iw_set("distance auto")
    end
    -- Or any hidden nodes
    iw_set("rts off")
    -- Set the default retries
    iw_set("retry short " .. default_short_retries .. " long " .. default_long_retries)

    if ptp then
        -- In ptp mode we allow a single mac address
        update_allow_list()
    else
        -- Clear the deny list
        update_deny_list({})
    end

    os.remove("/tmp/lqm.reset")
    -- Run until reset is detected
    while not nixio.fs.stat("/tmp/lqm.reset")
    do
        now = nixio.sysinfo().uptime

        update_config()

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

        local cursor = uci.cursor()
        local cursorm = uci.cursor("/etc/config.mesh")

        local lat = cursor:get("aredn", "@location[0]", "lat")
        local lon = cursor:get("aredn", "@location[0]", "lon")
        lat = tonumber(lat)
        lon = tonumber(lon)

        local arps = {}
        local ipv6neigh = {}
        for line in io.popen(IPCMD .. " neigh show"):lines()
        do
            local ip, dev, mac = line:match("^([0-9%.]+) dev (%S+) lladdr (%S+) .+$")
            if ip then
                -- Filter neighbors so we ignore entries which aren't immediately routable
                local routable = false;
                local rt = luciip.route(ip)
                if rt and tostring(rt.gw) == ip then
                    routable = true;
                end
                mac = mac:lower()
                if routable or not arps[mac] or arps[mac].Routable == false then
                    arps[mac] = {
                        Device = dev,
                        ["HW address"] = mac,
                        ["IP address"] = ip,
                        Routable = routable
                    }
                end
            end
            local ipv6, dev, mac = line:match("^([0-9a-f:]+) dev (%S+) lladdr (%S+) .+$")
            if ipv6 then
                ipv6neigh[mac] = {
                    ipv6 = ipv6,
                    device = dev,
                    mac = mac
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
                if i.family == "inet6" then
                    dev.ipv6 = i.addr
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
        for _, entry in pairs(arps)
        do
            if (entry.Device:match("%.2$") or entry.Device:match("^br%-dtdlink")) and entry.Routable then
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
        if radiomode == "mesh" then
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
                    local entry = arps[station.mac]
                    if entry and entry.Device:match("^wlan") then
                        station.ip = entry["IP address"]
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
                    rev_lastseen = nil,
                    refresh = 0,
                    mac = station.mac,
                    ip = nil,
                    ipv6 = nil,
                    hostname = nil,
                    canonical_ip = nil,
                    lat = nil,
                    lon = nil,
                    distance = nil,
                    localarea = nil,
                    user_blocks = false;
                    snr = nil,
                    rev_snr = nil,
                    last_tx = nil,
                    tx_quality = nil,
                    ping_quality = nil,
                    ping_success_time = nil,
                    tx_bitrate = nil,
                    rx_bitrate = nil,
                    quality = nil,
                    last_tx_fail = nil,
                    last_tx_retries = nil,
                    avg_tx = nil,
                    avg_tx_retries = nil,
                    avg_tx_fail = nil,
                    node_route_count = 0,
                    babel_route_count = 0,
                    rev_ping_quality = nil,
                    rev_ping_success_time = nil,
                    rev_quality = nil,
                    babel_metric = nil
                }
            end
            local track = tracker[station.mac]

            -- IP and Hostname
            if station.ip and station.ip ~= track.ip then
                track.ip = station.ip
                track.hostname = nil
                track.canonical_ip = nil
            end
            if not track.hostname and track.ip then
                track.hostname = canonical_hostname(nixio.getnameinfo(track.ip))
                track.canonical_ip = track.hostname and iplookup(track.hostname)
            end
            if not track.ipv6ll then
                local ipv6 = ipv6neigh[track.mac]
                if ipv6 then
                    track.ipv6ll = ipv6.ipv6
                elseif track.type == "Wireguard" and track.ip then
                    local a, b, c, d = track.ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
                    track.ipv6ll = string.format("fe80::%02x%02x:%02x%02x", a, b, c, d)
                end
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

            track.tx_bitrate = av(track.tx_bitrate, bitrate_run_avg, station.tx_bitrate, 0)
            track.rx_bitrate = av(track.rx_bitrate, bitrate_run_avg, station.rx_bitrate, 0)
        end

        -- Max RF distance
        local distance = -1;

        -- Update link tracking state
        local ip2tracker = {}
        local refresh = false
        for _, track in pairs(tracker)
        do
            -- Clear route counters
            track.node_route_count = 0
            track.babel_route_count = 0

            if not track.ip then
                track.routable = false
            else
                ip2tracker[track.ip] = track

                -- Update if link is routable
                track.routable = false
                local rts = luciip.routes({ dest_exact = track.canonical_ip or track.ip })
                if #rts then
                    for _, rt in ipairs(rts)
                    do
                        if rt.table == 20 then
                            track.babel_metric = rt.metric
                        end
                        local gw = tostring(rt.gw)
                        if gw == track.ip or gw == track.canonical_ip then
                            track.routable = true
                        end
                    end
                end

                -- Refresh remote attributes periodically as this is expensive
                -- We dont do it the very first time so we can populate the LQM state with a new node quickly
                if track.refresh == 0 then
                    refresh = true
                    track.refresh = now
                elseif now > track.refresh then

                    -- Refresh the hostname periodically as it can change
                    track.hostname = canonical_hostname(nixio.getnameinfo(track.ip)) or track.hostname
                    track.canonical_ip = track.hostname and iplookup(track.hostname)

                    local raw = io.popen("exec " .. UFETCH .. " -T " .. connect_timeout .. " \"http://" .. track.ip .. ":8080/cgi-bin/sysinfo.json?link_info=1&lqm=1\" -O - 2> /dev/null")
                    local info = luci.jsonc.parse(raw:read("*a") or "")
                    raw:close()

                    wait_for_ticks(0)

                    if not info then
                        -- Failed to fetch information. Set time for retry and invalidate any information
                        -- considered stale
                        track.refresh = now + refresh_retry_timeout
                        track.rev_snr = nil
                        track.rev_ping_success_time = nil
                        track.rev_ping_quality = nil
                        track.rev_quality = nil
                    else
                        track.refresh = now + refresh_timeout()
                        track.rev_lastseen = now

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

                        if info.lqm and info.lqm.info and info.lqm.info.trackers then
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
                            if info.lqm and info.lqm.info and info.lqm.info.trackers then
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
                                    if rhostname and link.linkType == "RF" and link.signal and link.noise and myhostname == rhostname then
                                        local snr = link.signal - link.noise
                                        track.rev_snr = track.rev_snr and round(snr_run_avg * track.rev_snr + (1 - snr_run_avg) * snr) or snr
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Refresh user blocks
            track.user_blocks = false;
            for val in string.gmatch(config.user_blocks, "([^,]+)")
            do
                if val:gsub("%s+", ""):gsub("-", ":"):lower() == track.mac then
                    track.user_blocks = true
                    break
                end
            end

            -- Ping addresses and penalize quality for excessively slow links
            if track.ip and not track.user_blocks then
                local ptime = nil
                -- Once the Babel transition is completed, a IPv6 Link-layer ping is all we will need here as it will work for everything
                if track.ipv6ll then
                    for line in io.popen(PING6 .. " -c 1 -W " .. round(ping_timeout) .. " -I " .. track.device .. " " .. track.ipv6ll):lines()
                    do
                        local t = line:match("^64 bytes from .* time=(%S+) ms$")
                        if t then
                            track.routable = true
                            ptime = tonumber(t) / 1000
                        end
                    end
                end
                -- But for now we need older mechanisms as well
                if not ptime and track.type ~= "Tunnel" and track.type ~= "Wireguard" then
                    -- For devices which support ARP, send an ARP request and wait for a reply. This avoids the other ends routing
                    -- table and firewall messing up the response packet.
                    for line in io.popen(ARPING .. " -c 1 -D -w " .. round(ping_timeout) .. " -I " .. track.device .. " " .. track.ip):lines()
                    do
                        local t = line:match("^Unicast reply .* (%S+)ms$")
                        if t then
                            ptime = tonumber(t) / 1000
                        end
                    end
                end
                if not ptime and track.routable then
                    -- If that fails, measure the "ping" time directly to the device by sending a UDP packet
                    local sigsock = nixio.socket("inet", "dgram")
                    sigsock:setopt("socket", "rcvtimeo", ping_timeout)
                    sigsock:setopt("socket", "bindtodevice", track.device)
                    sigsock:setopt("socket", "dontroute", 1)
                    -- Must connect or we wont see the error
                    sigsock:connect(track.ip, 8080)
                    local pstart = gettime()
                    sigsock:send("")
                    -- There's no actual UDP server at the other end so recv will either timeout and return 'false' if the link is slow,
                    -- or will error and return 'nil' if there is a node and it send back an ICMP error quickly (which for our purposes is a positive)
                    if sigsock:recv(0) ~= false then
                        ptime = gettime() - pstart
                    end
                    sigsock:close()
                end

                wait_for_ticks(0)

                track.ping_quality = track.ping_quality and (track.ping_quality + 1) or 100
                if ptime then
                    track.ping_success_time = track.ping_success_time and (track.ping_success_time * ping_time_run_avg + ptime * (1 - ping_time_run_avg)) or ptime
                else
                    track.ping_quality = track.ping_quality - ping_penalty
                end
                track.ping_quality = math.max(0, math.min(100, track.ping_quality))
                if ptime then
                    track.lastseen = now
                elseif track.type == "DtD" and track.firstseen == now then
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

            -- Calculate the max RF distance as we go
            if track.type == "RF" and track.lastseen >= now then
                if track.distance then
                    if not track.user_blocks and track.distance > distance then
                        distance = track.distance
                    end
                else
                    distance = config.max_distance
                end
            end
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
        -- We will do this for babel, at least for now, to gather more data
        total_babel_route_count = 0
        for line in io.popen(IPCMD .. " route show table 20"):lines()
        do
            local gw = line:match("^10%.%d+%.%d+%.%d+ via (%d+%.%d+%.%d+%.%d+) dev")
            if gw then
                local track = ip2tracker[gw];
                if track then
                    track.babel_route_count = track.babel_route_count + 1
                    total_babel_route_count = total_babel_route_count + 1
                end
            end
        end
        for line in io.popen(IPCMD .. " route show table 21"):lines()
        do
            local gw = line:match("^10%.0%.0%.0/8 via (%d+%.%d+%.%d+%.%d+) dev")
            if gw then
                local track = ip2tracker[gw];
                if track then
                    track.babel_route_count = track.babel_route_count + 1
                    total_babel_route_count = total_babel_route_count + 1
                end
            end
        end

        -- Remove any trackers which are too old or if they disconnect when first seen
        for _, track in pairs(tracker)
        do
            -- DONT* remove any user blocked trackers. If we block these devices at a low level (via
            -- the deny list for example) then we never see them again at this level and we loose the ability
            -- to unblock them without a reboot.
            if not track.user_blocks then
                if ((now > track.lastseen + lastseen_timeout) or
                    (track.rev_lastseen and now > track.rev_lastseen + lastseen_timeout)
                ) then
                    tracker[track.mac] = nil
                end
            end
        end

        if ptp then
            -- In ptp mode we allow a single mac address.
            -- Update this every time in case the file gets overwritten (which happens when
            -- hostapd gets restarted)
            update_allow_list()
        else
            -- Update denied mac list
            update_deny_list(tracker)
        end

        -- Update the wifi distance
        if distance < 0 then
            distance = config.max_distance
        else
            distance = math.min(distance, config.max_distance)
        end
        local coverage = math.min(255, math.floor(distance / 450))
        if coverage ~= last_coverage then
            iw_set("coverage " .. coverage)
            last_coverage = coverage
        end

        -- Set the RTS/CTS state depending on whether everyone can see everyone
        -- Build a list of all the nodes our neighbors can see
        local theres = {}
        for mac, rfneighbor in pairs(rflinks)
        do
            local track = tracker[mac]
            if track and not track.user_blocks and track.routable then
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
        if (#hidden == 0) ~= (#hidden_nodes == 0) then
            if #hidden > 0 then
                iw_set("rts " .. rts_threshold)
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

        wait_for_ticks(refresh and 1 or 60) -- 1 second or 1 minute
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
