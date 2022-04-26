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

local nixio = require("nixio")
local uci = require("uci")
local json = require("luci.jsonc")
local sys = require("luci.sys")
local ip = require("luci.ip")

local refresh_timeout = 60 * 60 -- refresh high cost data evey hour
local wait_timeout = 5 * 60 -- wait 5 minutes after node is first seen before banning
local lastseen_timeout = 60 * 60 -- age out nodes we've not seen in an hour


function update_block(track)
    if not track.pending then
        if track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user then
            if not track.blocked then
                track.blocked = true
                os.execute("/usr/sbin/iptables -D input_lqm -p udp --destination-port 698 -m mac --mac-source " .. track.mac .. " -j DROP 2> /dev/null")
                os.execute("/usr/sbin/iptables -I input_lqm -p udp --destination-port 698 -m mac --mac-source " .. track.mac .. " -j DROP 2> /dev/null")
            end
        else
            if track.blocked then
                track.blocked = false
                os.execute("/usr/sbin/iptables -D input_lqm -p udp --destination-port 698 -m mac --mac-source " .. track.mac .. " -j DROP 2> /dev/null")
            end
        end
    end
end

function calcDistance(lat1, lon1, lat2, lon2)
    local r2 = 12742000 -- diameter earth (meters)
    local p = 0.017453292519943295 --  Math.PI / 180
    local v = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return math.floor(r2 * math.asin(math.sqrt(v)))
end

-- Clear old data
io.open("/tmp/lqm.info", "w"):close()

local cursor = uci.cursor()

-- Get radio
local radioname = "radio0"
for i = 0,2
do
    if cursor:get("wireless","@wifi-iface[" .. i .. "]", "network") == "wifi" then
        radioname = cursor:get("wireless","@wifi-iface[" .. i .. "]", "device")
        break
    end
end

function lqm()

    if cursor:get("aredn", "@lqm[0]", "enable") ~= "1" then
        exit_app()
    end

    -- Create filters
    os.execute("/usr/sbin/iptables -F input_lqm 2> /dev/null")
    os.execute("/usr/sbin/iptables -X input_lqm 2> /dev/null")
    os.execute("/usr/sbin/iptables -N input_lqm 2> /dev/null")
    os.execute("/usr/sbin/iptables -D INPUT -j input_lqm -m comment --comment 'block low quality links' 2> /dev/null")
    os.execute("/usr/sbin/iptables -I INPUT -j input_lqm -m comment --comment 'block low quality links' 2> /dev/null")
    
    local tracker = {}
    local last_distance = -1
    while true
    do

        local c = uci.cursor() -- each time as /etc/config/aredn may have changed
        local config = {
            margin = tonumber(c:get("aredn", "@lqm[0]", "margin")),
            low = tonumber(c:get("aredn", "@lqm[0]", "low")),
            min_distance = tonumber(c:get("aredn", "@lqm[0]", "min_distance")),
            max_distance = tonumber(c:get("aredn", "@lqm[0]", "max_distance")),
            user_blocks = c:get("aredn", "@lqm[0]", "user_blocks") or ""
        }

        local lat = tonumber(cursor:get("aredn", "@location[0]", "lat"))
        local lon = tonumber(cursor:get("aredn", "@location[0]", "lon"))

        local arps = {}
        arptable(
            function (entry)
                arps[entry["IP address"]] = entry
                arps[entry["HW address"]:upper()] = entry
            end
        )

        local kv = {
            ["signal avg:"] = "signal",
            ["last ack signal:"] = "ack_signal",
            ["tx packets:"] = "tx_packets",
            ["tx retries:"] = "tx_retries",
            ["tx failed:"] = "tx_fail",
            ["tx bitrate:"] = "tx_rate",
            ["tx bitrate:.+MCS"] = "tx_mcs",
            ["rx packets:"] = "rx_packets",
            ["rx drop misc:"] = "rx_drop",
            ["rx bitrate:"] = "rx_rate",
            ["rx bitrate:.+MCS"] = "rx_mcs",
            ["expected throughput:"] = "thru"
        }
        local stations = {}
        local station = {}
        for line in io.popen("iw " .. get_ifname("wifi") .. " station dump"):lines()
        do
            local mac = line:match("^Station ([0-9a-f:]+) ")
            if mac then
                station = {
                    signal = 0,
                    noise = -95,
                }
                stations[mac:upper()] = station
            else
                for k, v in pairs(kv)
                do
                    local val = line:match(k .. "%s*([%d%-]+)")
                    if val then
                        station[v] = tonumber(val)
                    end
                end
            end
        end

        local now = os.time()

        for mac, station in pairs(stations)
        do
            if station.signal ~= 0 then
                local snr = station.signal - station.noise
                if not tracker[mac] then
                    tracker[mac] = {
                        firstseen = now,
                        refresh = 0,
                        mac = mac,
                        station = nil,
                        ip = nil,
                        lat = nil,
                        lon = nil,
                        distance = nil,
                        blocks = {
                            dtd = false,
                            signal = false,
                            distance = false
                        },
                        blocked = false,
                        pending = true
                    }
                end
                local track = tracker[mac]

                -- If we have a direct dtd connection to this device, make sure we use that
                local macdtd = false
                local entry = arps[mac]
                if entry then
                    track.ip = entry["IP address"]
                    local a, b, c = track.ip:match("^(%d+%.)(%d+)(%.%d+%.%d+)$")
                    local dtd = arps[string.format("%s%d%s", a, tonumber(b) + 1, c)]
                    if dtd and dtd.Device:match("%.2$") and dtd["HW address"] ~= "00:00:00:00:00:00" then
                        macdtd = true
                    end
                    track.hostname = (nixio.getnameinfo(track.ip) or ""):match("^(.*)%.local%.mesh$")
                end
                if macdtd and not track.dtd then
                    track.blocks.dtd = true
                elseif not macdtd and track.dtd then
                    track.blocks.dtd = false
                end
                if not track.dtd then
                    -- When unblocked link becomes too low, block
                    if not track.blocks.signal then
                        if snr < config.low then
                            track.blocks.signal = true
                        end 
                    -- when blocked link becomes (low+margin) again, unblock
                    elseif track.blocks.signal then
                        if snr >= config.low + config.margin then
                            track.blocks.signal = false
                        end 
                    end
                end

                track.lastseen = now
                track.station = station
            end
        end

        local distance = -1

        for _, track in pairs(tracker)
        do
            -- Release pending nodes after the wait time
            if now > track.firstseen + wait_timeout then
                track.pending = false
            end

            -- Clear signal when we've not seen the node
            if track.lastseen < now then
                track.station.signal = track.station.noise
            end

            -- Only refesh certain attributes periodically
            if track.refresh < now then
                if not track.pending then
                    track.refresh = now + refresh_timeout
                end
                if not track.blocked and not track.lat and track.ip then
                    local info = json.parse(sys.httpget("http://" .. track.ip .. ":8080/cgi-bin/sysinfo.json"))
                    if info and tonumber(info.lat) and tonumber(info.lon) then
                        track.lat = tonumber(info.lat)
                        track.lon = tonumber(info.lon)
                        if lat and lon then
                            track.distance = calcDistance(lat, lon, track.lat, track.lon)
                        end
                    end
                end
            end

            -- Routable
            local rt = track.ip and ip.route(track.ip) or nil
            if rt and tostring(rt.gw) == track.ip then
                track.routable = true
            else
                track.routable = false
            end

            -- Block any nodes which are too distant
            if track.distance and track.distance >= config.min_distance and track.distance <= config.max_distance then
                track.blocks.distance = false
            else
                track.blocks.distance = true
            end

            -- Block is user requested it
            track.blocks.user = false
            for val in string.gmatch(config.user_blocks, "([^,]+)")
            do
                if val == track.mac then
                    track.blocks.user = true
                    break
                end
            end

            update_block(track)

            -- Find the most distant, unblocked, routable, node
            if not track.pending and not track.blocked and track.routable and track.distance and track.distance > distance then
                distance = track.distance
            end

            -- Remove any trackers which are too old
            if now > track.lastseen + lastseen_timeout then
                track.blocked = true;
                track.blocks = {}
                update_block(track)
                tracker[mac] = nil
            end
        end

        if distance ~= last_distance then
            last_distance = distance
            distance = distance + 1

            -- Update the wifi distance for better bandwidth utilization
            os.execute("iw phy phy" .. radioname:match("radio(%d+)") .. " set distance " .. (distance > 0 and distance or "auto"))

            cursor:set("wireless", radioname, "distance", distance)
            cursor:commit("wireless")

            -- Update the global _setup
            local lines = {}
            for line in io.lines("/etc/config.mesh/_setup")
            do
                if line:match("^wifi_distance = ") then
                    lines[#lines + 1] = "wifi_distance = " .. distance
                else
                    lines[#lines + 1] = line
                end
            end
            local f = io.open("/etc/config.mesh/_setup", "w")
            if f then
                for _, line in ipairs(lines)
                do
                    f:write(line .. "\n")
                end
                f:close()
            end
        end

        -- Save this for the UI
        f = io.open("/tmp/lqm.info", "w")
        if f then
            f:write(json.stringify({
                trackers = tracker,
                distance = distance
            }, true))
            f:close()
        end

        wait_for_ticks(60) -- 1 minute
    end
end

return lqm
