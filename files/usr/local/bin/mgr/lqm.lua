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

local json = require("luci.jsonc")
local ip = require("luci.ip")
local info = require("aredn.info")

local refresh_timeout = 15 * 60 -- refresh high cost data every 15 minutes
local pending_timeout = 5 * 60 -- pending node wait 5 minutes before they are included
local first_run_timeout = 4 * 60 -- first ever run can adjust the config to make sure we dont ignore evereyone
local lastseen_timeout = 60 * 60 -- age out nodes we've not seen for 1 hour
local snr_run_avg = 0.8 -- snr running average
local quality_min_packets = 100 -- minimum number of tx packets before we can safely calculate the link quality
local quality_injection_max = 10 -- number of packets to inject into poor links to update quality
local tx_quality_run_avg = 0.8 -- tx quality running average
local ping_timeout = 1.0 -- timeout before ping gives a qualtiy penalty

local myhostname = (info.get_nvram("node") or "localnode"):lower()
local now = 0

function get_config()
    local c = uci.cursor() -- each time as /etc/config/aredn may have changed
    return {
        margin = tonumber(c:get("aredn", "@lqm[0]", "margin_snr")),
        low = tonumber(c:get("aredn", "@lqm[0]", "min_snr")),
        min_distance = tonumber(c:get("aredn", "@lqm[0]", "min_distance")),
        max_distance = tonumber(c:get("aredn", "@lqm[0]", "max_distance")),
        min_quality = tonumber(c:get("aredn", "@lqm[0]", "min_quality")),
        margin_quality = tonumber(c:get("aredn", "@lqm[0]", "margin_quality")),
        ping_penalty = tonumber(c:get("aredn", "@lqm[0]", "ping_penalty")),
        user_blocks = c:get("aredn", "@lqm[0]", "user_blocks") or ""
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
    if is_pending(track) then
        return track.blocks.dtd or track.blocks.user
    else
        return track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.dup or track.blocks.quality
    end
end

function should_nonpair_block(track)
    return track.blocks.dtd or track.blocks.signal or track.blocks.distance or track.blocks.user or track.blocks.quality
end

function only_quality_block(track)
    return track.blocked and track.blocks.quality and not (
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

function update_block(track)
    if should_block(track) then
        if not track.blocked then
            track.blocked = true
            os.execute("/usr/sbin/iptables -D input_lqm -p udp --destination-port 698 -m mac --mac-source " .. track.mac .. " -j DROP 2> /dev/null")
            os.execute("/usr/sbin/iptables -I input_lqm -p udp --destination-port 698 -m mac --mac-source " .. track.mac .. " -j DROP 2> /dev/null")
            return "blocked"
        end
    else
        if track.blocked then
            track.blocked = false
            os.execute("/usr/sbin/iptables -D input_lqm -p udp --destination-port 698 -m mac --mac-source " .. track.mac .. " -j DROP 2> /dev/null")
            return "unblocked"
        end
    end
    return "unchanged"
end

-- Distance in meters between two points
function calc_distance(lat1, lon1, lat2, lon2)
    local r2 = 12742000 -- diameter earth (meters)
    local p = 0.017453292519943295 --  Math.PI / 180
    local v = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return math.floor(r2 * math.asin(math.sqrt(v)))
end

-- Clear old data
local f = io.open("/tmp/lqm.info", "w")
f:write("{}")
f:close()

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
local phy = "phy" .. radioname:match("radio(%d+)")
local wlan = get_ifname("wifi")

function lqm()

    if cursor:get("aredn", "@lqm[0]", "enable") ~= "1" then
        exit_app()
        return
    end

    -- Let things startup for a while before we begin
    wait_for_ticks(math.max(1, 30 - nixio.sysinfo().uptime))

    -- Create filters (cannot create during install as they disappear on reboot)
    os.execute("/usr/sbin/iptables -F input_lqm 2> /dev/null")
    os.execute("/usr/sbin/iptables -X input_lqm 2> /dev/null")
    os.execute("/usr/sbin/iptables -N input_lqm 2> /dev/null")
    os.execute("/usr/sbin/iptables -D INPUT -j input_lqm -m comment --comment 'block low quality links' 2> /dev/null")
    os.execute("/usr/sbin/iptables -I INPUT -j input_lqm -m comment --comment 'block low quality links' 2> /dev/null")

    -- We dont know any distances yet
    os.execute("iw " .. phy .. " set distance auto")

    -- Setup a first_run timeout if this is our first every run
    if cursor:get("aredn", "@lqm[0]", "first_run") == "0" then
        first_run_timeout = 0
    else
        first_run_timeout = first_run_timeout + nixio.sysinfo().uptime
    end

    local tracker = {}
    while true
    do
        now = nixio.sysinfo().uptime

        local config = get_config()

        local lat = tonumber(cursor:get("aredn", "@location[0]", "lat"))
        local lon = tonumber(cursor:get("aredn", "@location[0]", "lon"))

        local arps = {}
        arptable(
            function (entry)
                arps[entry["HW address"]:upper()] = entry
            end
        )

        local kv = {
            ["signal avg:"] = "signal",
            ["tx packets:"] = "tx_packets",
            ["tx retries:"] = "tx_retries",
            ["tx failed:"] = "tx_fail",
            ["tx bitrate:"] = "tx_rate"
        }
        local stations = {}
        local station = {}
        local noise = iwinfo.nl80211.noise(wlan) or -95
        for line in io.popen("iw " .. wlan .. " station dump"):lines()
        do
            local mac = line:match("^Station ([0-9a-f:]+) ")
            if mac then
                station = {
                    signal = 0,
                    noise = noise,
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

        for mac, station in pairs(stations)
        do
            if station.signal ~= 0 then
                local snr = station.signal - station.noise
                if not tracker[mac] then
                    tracker[mac] = {
                        firstseen = now,
                        lastseen = now,
                        pending = now + pending_timeout,
                        refresh = 0,
                        mac = mac,
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
                        links = {},
                        tx_rate = 0,
                        last_tx = nil,
                        last_tx_total = nil,
                        tx_quality = 100,
                        ping_quality = 100,
                        quality = 100
                    }
                end
                local track = tracker[mac]

                -- If we have a direct dtd connection to this device, make sure we use that
                local entry = arps[mac]
                if entry then
                    track.ip = entry["IP address"]
                    local a, b, c = mac:match("^(..:..:..:)(..)(:..:..)$")
                    local dtd = arps[string.format("%s%02x%s", a, tonumber(b, 16) + 1, c):upper()]
                    if dtd and dtd.Device:match("%.2$") then
                        track.blocks.dtd = true
                    end
                    local hostname = nixio.getnameinfo(track.ip)
                    if hostname then
                        track.hostname = hostname:lower():match("^(.*)%.local%.mesh$")
                    end
                end

                -- Running average SNR
                if track.snr == 0 then
                    track.snr = snr
                else
                    track.snr = math.ceil(snr_run_avg * track.snr + (1 - snr_run_avg) * snr)
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

                track.tx_rate = station.tx_rate

                track.lastseen = now
            end
        end

        local distance = -1
        local alt_distance = -1
        local coverage = -1

        -- Update link tracking state
        for _, track in pairs(tracker)
        do
            -- Only refresh remote attributes periodically
            if track.ip and (now > track.refresh or is_pending(track)) then
                track.refresh = now + refresh_timeout
                local info = json.parse(luci.sys.httpget("http://" .. track.ip .. ":8080/cgi-bin/sysinfo.json?link_info=1&lqm=1"))
                if info then
                    if tonumber(info.lat) and tonumber(info.lon) then
                        track.lat = tonumber(info.lat)
                        track.lon = tonumber(info.lon)
                        if lat and lon then
                            track.distance = calc_distance(lat, lon, track.lat, track.lon)
                        end
                    end
                    local old_rev_snr = track.rev_snr
                    track.links = {}
                    -- Note: We cannot assume a missing link means no wifi connection
                    track.rev_snr = null
                    if info.lqm and info.lqm.enabled then
                        for _, rtrack in pairs(info.lqm.info.trackers)
                        do
                            if rtrack.hostname then
                                local hostname = rtrack.hostname:lower():gsub("^dtdlink%.",""):gsub("%.local%.mesh$", "")
                                track.links[hostname] = {
                                    type = "RF",
                                    snr = rtrack.snr
                                }
                                if myhostname == hostname then
                                    if not old_rev_snr or not rtrack.snr then
                                        track.rev_snr = rtrack.snr
                                    else
                                        track.rev_snr = math.ceil(snr_run_avg * old_rev_snr + (1 - snr_run_avg) * rtrack.snr)
                                    end
                                end
                            end
                        end
                        for ip, link in pairs(info.link_info)
                        do
                            if link.hostname and link.linkType == "DTD" then
                                track.links[link.hostname:lower()] = { type = "DTD" }
                            end
                        end
                    else
                        -- If there's no LQM information we fallback on using link information.
                        for ip, link in pairs(info.link_info)
                        do
                            if link.hostname then
                                local hostname = link.hostname:lower():gsub("^dtdlink%.",""):gsub("%.local%.mesh$", "")
                                if link.linkType == "DTD" then
                                    track.links[hostname] = { type = link.linkType }
                                elseif link.linkType == "RF" and link.signal and link.noise then
                                    local snr = link.signal - link.noise
                                    if not track.links[hostname] then
                                        track.links[hostname] = {
                                            type = link.linkType,
                                            snr = snr
                                        }
                                    end
                                    if myhostname == hostname then
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
                else
                    -- Clear these if we cannot talk to the other end, so we dont use stale values
                    track.links = {}
                    track.rev_snr = nil
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
                -- Make an arp request to the target ip to see if we get a timely reply. By using ARP we avoid any
                -- potential routing issues and avoid any firewall blocks on the other end.
                -- As the request is broadcast, we avoid any potential distance/scope timing issues as we dont wait for the
                -- packet to be acked. The reply will be unicast to us, and our ack to that is unimportant to the latency test.
                local success = 100
                if os.execute("/usr/sbin/arping -f -w " .. ping_timeout .. " -I " .. wlan .. " " .. track.ip .. " >/dev/null") ~= 0 then
                    success = 0
                end
                local ping_loss_run_avg = 1 - config.ping_penalty / 100
                track.ping_quality = math.ceil(ping_loss_run_avg * track.ping_quality + (1 - ping_loss_run_avg) * success)
            end

            -- Calculate overall link quality
            track.quality = math.ceil((track.tx_quality + track.ping_quality) / 2)

            -- Inject traffic into links with poor quality
            -- We do this so we can keep measuring the current link quality otherwise, once it becomes
            -- bad, it wont be used and we can never tell if it becomes good again. Beware injecting too
            -- much traffic because, on very poor links, this can generate multiple retries per packet, flooding
            -- the wifi channel
            if track.ip and only_quality_block(track) then
                -- Create socket we use to inject traffic into degraded links
                -- This is setup so it ignores routing and will always send to the correct wifi station
                local sigsock = nixio.socket("inet", "dgram")
                sigsock:setopt("socket", "bindtodevice", wlan)
                sigsock:setopt("socket", "dontroute", 1)
                for _ = 1,quality_injection_max
                do
                    sigsock:sendto("", track.ip, 8080)
                end
                sigsock:close()
            end
        end

        -- First run handling (emergency node)
        -- If this is the very first time this has even been run, either because this is an upgrade or a new install,
        -- we make sure we can talk to *something* by adjusting config options so that's possible and we don't
        -- accidentally isolate the node.
        if first_run_timeout ~= 0 and now >= first_run_timeout then
            local changes = {
                snr = -1,
                distance = nil,
                quality = nil
            }
            -- Scan through the list of nodes we're tracking and select the node with the best SNR then
            -- adjust our settings so that this node is valid
            for _, track in pairs(tracker)
            do
                local snr = track.snr
                if track.rev_snr and track.rev_snr ~= 0 and track.rev_snr < snr then
                    snr = track.rev_snr
                end
                if snr > changes.snr then
                    changes.snr = snr
                    changes.distance = track.distance
                    changes.quality = track.quality
                end
            end
            local cursorb = uci.cursor("/etc/config.mesh")
            if changes.snr > -1 then
                if changes.snr < config.low then
                    cursor:set("aredn", "@lqm[0]", "min_snr", math.max(1, changes.snr - 3))
                    cursorb:set("aredn", "@lqm[0]", "min_snr", math.max(1, changes.snr - 3))
                end
                if changes.distance and changes.distance > config.max_distance then
                    cursor:set("aredn", "@lqm[0]", "max_distance", changes.distance)
                    cursorb:set("aredn", "@lqm[0]", "max_distance", changes.distance)
                end
                if changes.quality and changes.quality < config.min_quality then
                    cursor:set("aredn", "@lqm[0]", "min_quality", math.max(0, math.floor(changes.quality - 20)))
                    cursorb:set("aredn", "@lqm[0]", "min_quality", math.max(0, math.floor(changes.quality - 20)))
                end
            end
            cursor:set("aredn", "@lqm[0]", "first_run", "0")
            cursorb:set("aredn", "@lqm[0]", "first_run", "0")
            cursor:commit("aredn")
            cursorb:commit("aredn")
            first_run_timeout = 0
        end

        -- Work out what to block, unblock and limit
        for _, track in pairs(tracker)
        do
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

            -- Block if user requested it
            track.blocks.user = false
            for val in string.gmatch(config.user_blocks, "([^,]+)")
            do
                if val == track.mac then
                    track.blocks.user = true
                    break
                end
            end

            -- Block if quality is poor
            if track.quality then
                if not track.blocks.quality and track.quality < config.min_quality then
                    track.blocks.quality = true
                elseif track.blocks.quality and track.quality >= config.min_quality + config.margin_quality then
                    track.blocks.quality = false
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
                        local connection = track.links[track2.hostname]
                        if connection and connection.type == "DTD" then
                            tracklist[#tracklist + 1] = track2
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

        -- Update the block state and calculate the routable distance
        for _, track in pairs(tracker)
        do
            if is_connected(track) then 
                if update_block(track) == "unblocked" then
                    -- If the link becomes unblocked, return it to pending state
                    track.pending = now + pending_timeout
                end

                -- Find the most distant, unblocked, routable, node
                if not track.blocked and track.distance then
                    if not is_pending(track) and track.routable then
                        if track.distance > distance then 
                            distance = track.distance
                        end
                    else
                        if track.distance > alt_distance then
                            alt_distance = track.distance
                        end
                    end
                end
            end

            -- Remove any trackers which are too old or if they disconnect when first seen
            if ((now > track.lastseen + lastseen_timeout) or (not is_connected(track) and track.firstseen + pending_timeout > now)) then
                track.blocked = true;
                track.blocks = {}
                update_block(track)
                tracker[track.mac] = nil
            end
        end

        distance = distance + 1
        alt_distance = alt_distance + 1

        -- Update the wifi distance
        if distance > 0 then
            coverage = math.floor((distance * 2 * 0.0033) / 3) -- airtime
            os.execute("iw " .. phy .. " set coverage " .. coverage)
        elseif alt_distance > 1 then
            coverage = math.floor((alt_distance * 2 * 0.0033) / 3)
            os.execute("iw " .. phy .. " set coverage " .. coverage)
        else
            os.execute("iw " .. phy .. " set distance auto")
        end

        -- Save this for the UI
        f = io.open("/tmp/lqm.info", "w")
        if f then
            f:write(json.stringify({
                now = now,
                trackers = tracker,
                distance = distance,
                coverage = coverage
            }, true))
            f:close()
        end

        wait_for_ticks(60) -- 1 minute
    end
end

return lqm
