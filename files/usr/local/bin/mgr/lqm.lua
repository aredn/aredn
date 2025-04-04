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

require("luci.ip")
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

local IW = "/usr/sbin/iw"
local UFETCH = "/bin/uclient-fetch"
local IPCMD = "/sbin/ip"
local PING6 = "/bin/ping6"

local now = 0
local config = {}

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

function reach_to_lq(reach)
    reach = tonumber(reach, 16)
    local count = 0
    local flag = 1
    for i = 1, 16
    do
        if nixio.bit.check(reach, flag) then
            count = count + 1
        end
        flag = flag * 2
    end
    return math.ceil(100 * count / 16)
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
        local refresh = false

        local lat = cursor:get("aredn", "@location[0]", "lat")
        local lon = cursor:get("aredn", "@location[0]", "lon")
        lat = tonumber(lat)
        lon = tonumber(lon)

        -- Find the Xlink interfaces so we can correctly identify the types
        local xlinks = {}
        cursorm:foreach("xlink", "interface",
            function(section)
                if section.ifname then
                    xlinks[section.ifname] = true
                end
            end
        )

        -- Babel neighbors
        function device2type(device)
            if device == "br-dtdlink" then
                return "DtD"
            elseif device:match("^wlan") then
                return "RF"
            elseif device:match("^wg") then
                return "Wireguard"
            elseif xlinks[device] then
                return "Xlink"
            else
                return nil
            end
        end
    
        for line in io.popen("echo dump-neighbors | /usr/bin/socat UNIX-CLIENT:/var/run/babel.sock -"):lines()
        do
            local address, device, reach, rxcost, txcost = line:match("^add.*address (%S+) if (%S+) reach (%S+) .* rxcost (%S+) txcost (%S+)")
            if address then
                local type = device2type(device)
                local mac = luci.ip.new(address):tomac():string():lower()
                local track = tracker[mac]
                if not track and type then
                    track = {
                        type = type,
                        device = device,
                        mac = mac,
                        ipv6ll = address,
                        refresh = 0
                    }
                    tracker[mac] = track
                end
                if track then
                    track.lq = reach_to_lq(reach)
                    track.rxcost = tonumber(rxcost)
                    track.txcost = tonumber(txcost)
                    if type == "Wireguard" then
                        local rtt = line:match("rtt (%S+)")
                        if rtt then
                            track.rtt = tonumber(rtt)
                        end
                    end
                end
            end
        end

        -- Update RF information
        if radiomode == "mesh" then
            local kv = {
                ["signal avg:"] = "signal",
                ["tx packets:"] = "tx_packets",
                ["tx retries:"] = "tx_retries",
                ["tx failed:"] = "tx_fail",
                ["tx bitrate:"] = "tx_bitrate",
                ["rx bitrate:"] = "rx_bitrate"
            }
            local track = {}
            local cnoise = iwinfo.nl80211.noise(wlan)
            if cnoise and cnoise < -70 then
                noise = round(noise * 0.9 + cnoise * 0.1)
            end
            for line in io.popen(IW .. " " .. wlan .. " station dump"):lines()
            do
                local mac = line:match("^Station ([0-9a-fA-F:]+) ")
                if mac then
                    track = tracker[mac:lower()] or track
                else
                    for k, v in pairs(kv)
                    do
                        local val = line:match(k .. "%s*([%d%-]+)")
                        if val then
                            track[v] = tonumber(val)
                            if v == "tx_bitrate" or v == "rx_bitrate" then
                                track[v] = track[v] * channel_bw_scale
                            end
                        end
                    end
                end
            end
        end

        -- Update running averages
        for _, track in pairs(tracker)
        do
            if track.type == "RF" then
                if track.tx_packets then
                    if not track.last_tx_packets then
                        track.avg_tx = 0
                    else
                        track.avg_tx = track.avg_tx * tx_quality_run_avg + (track.tx_packets - track.last_tx_packets) * (1 - tx_quality_run_avg)
                    end
                    track.last_tx_packets = track.tx_packets
                end
                if track.tx_retries then
                    if not track.last_tx_retries then
                        track.avg_tx_retries = 0
                    else
                        track.avg_tx_retries = track.avg_tx_retries * tx_quality_run_avg + (track.tx_retries - track.last_tx_retries) * (1 - tx_quality_run_avg)
                    end
                    track.last_tx_retries = track.tx_retries
                end
                if track.tx_fail then
                    if not track.last_tx_fail then
                        track.avg_tx_fail = 0
                    else
                        track.avg_tx_fail = track.avg_tx_fail * tx_quality_run_avg + (track.tx_fail - track.last_tx_fail) * (1 - tx_quality_run_avg)
                    end
                    track.last_tx_fail = track.tx_fail
                end
                if track.tx_bitrate then
                    if not track.avg_tx_bitrate then
                        track.avg_tx_bitrate = track.avg_tx_bitrate
                    else
                        track.avg_tx_bitrate = track.avg_tx_bitrate * bitrate_run_avg + track.tx_bitrate * (1 - bitrate_run_avg)
                    end
                end
                if track.rx_bitrate then
                    if not track.avg_rx_bitrate then
                        track.avg_rx_bitrate = track.avg_rx_bitrate
                    else
                        track.avg_rx_bitrate = track.avg_rx_bitrate * bitrate_run_avg + track.rx_bitrate * (1 - bitrate_run_avg)
                    end
                end
                if track.avg_tx > 0 then
                    local bad = math.max(track.avg_tx_fail or 0, track.avg_tx_retries or 0)
                    track.tx_quality = 100 * (1 - math.min(1, bad / track.avg_tx))
                end
            end
        end

        -- Refresh remote attributes periodically as this is expensive
        -- We dont do it the very first time so we can populate the LQM state with a new node quickly
        for _, track in pairs(tracker)
        do
            if track.refresh == 0 then
                refresh = true
                track.refresh = now
            elseif now > track.refresh and track.ipv6ll then
                local raw = io.popen("exec " .. UFETCH .. " -T " .. connect_timeout .. " \"http://[" .. track.ipv6ll .. "%" .. track.device .. "]:8080/cgi-bin/sysinfo.json?lqm=1\" -O - 2> /dev/null")
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

                    track.hostname = info.node:lower()
                    track.canonical_ip = iplookup(track.hostname)
                    if track.type == "Wireguard" then
                        local address = cursor:get_all("network", track.device, "addresses")[1]
                        local abc, d = address:match("^(%d+%.%d+%.%d+%.)(%d+)")
                        if track.device:match("^wgs") then
                            track.ip = abc .. tonumber(d) - 1
                        else
                            track.ip = abc .. tonumber(d) + 1
                        end
                    else
                        for _, iface in ipairs(info.interfaces)
                        do
                            if iface.mac and iface.mac:lower() == track.mac then
                                track.ip = iface.ip
                                break
                            end
                        end
                    end

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
                        end
                    end
                end
            end
        end

        -- Max RF distance
        local distance = -1;

        -- Update link tracking state
        local ip2tracker = {}
        for _, track in pairs(tracker)
        do
            -- Clear route counters
            track.babel_route_count = 0

            if not track.ip then
                track.routable = false
            else
                ip2tracker[track.ip] = track

                -- Update if link is routable
                track.routable = false
                local rts = luci.ip.routes({ dest_exact = track.canonical_ip or track.ip })
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

            -- Include babel info for this link.
            track.babel_config = {
                hello_interval = tonumber(cursor:get("babel", "default", "hello_interval")),
                update_interval = tonumber(cursor:get("babel", "default", "update_interval"))
            }
            if track.type == "Wireguard" then
                track.babel_config.rxcost = tonumber(cursor:get("babel", "tunnel", "rxcost"))
                local weight = tonumber(cursor:get("network", track.device, "weight") or nil)
                if weight then
                    track.babel_config.rxcost = track.babel_config.rxcost + tonumber(cursor:get("babel", "tunnel", "rxscale")) * weight
                end
            elseif track.type == "Xlink" then
                track.babel_config.rxcost = tonumber(cursor:get("babel", "xlink", "rxcost"))
                local weight = nil
                for x = 0, 15
                do
                    if cursor:get("network", "xlink" .. x, "ifname") == track.device then
                        weight = tonumber(cursor:get("network", "xlink" .. x, "weight") or nil)
                        break
                    end
                end
                if weight then
                    track.babel_config.rxcost = track.babel_config.rxcost + tonumber(cursor:get("babel", "xlink", "rxscale")) * weight
                end
            else
                track.babel_config.rxcost = tonumber(cursor:get("babel", "default", "rxcost"))
            end

            -- Ping addresses and penalize quality for excessively slow links
            if track.ipv6ll and not track.user_blocks then
                local ptime = nil
                for line in io.popen(PING6 .. " -c 1 -W " .. round(ping_timeout) .. " -I " .. track.device .. " " .. track.ipv6ll):lines()
                do
                    local t = line:match("^64 bytes from .* time=(%S+) ms$")
                    if t then
                        track.routable = true
                        ptime = tonumber(t) / 1000
                    end
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
        --
        if not is_supernode then
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
                total_babel_route_count = total_babel_route_count
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
