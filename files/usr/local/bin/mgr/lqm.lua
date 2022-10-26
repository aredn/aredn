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

local refresh_timeout = 15 * 60 -- refresh high cost data every 15 minutes
local pending_timeout = 5 * 60 -- pending node wait 5 minutes before they are included
local first_run_timeout = 4 * 60 -- first ever run can adjust the config to make sure we dont ignore evereyone
local lastseen_timeout = 60 * 60 -- age out nodes we've not seen for 1 hour
local snr_run_avg = 0.8 -- snr running average
local quality_min_packets = 100 -- minimum number of tx packets before we can safely calculate the link quality
local quality_injection_max = 10 -- number of packets to inject into poor links to update quality
local tx_quality_run_avg = 0.8 -- tx quality running average
local ping_timeout = 1.0 -- timeout before ping gives a qualtiy penalty
local dtd_distance = 50 -- distance (meters) after which nodes connected with DtD links are considered different sites

local NFT = "/usr/sbin/nft"
local IW = "/usr/sbin/iw"
local ARPING = "/usr/sbin/arping"

local myhostname = (info.get_nvram("node") or "localnode"):lower()
local now = 0

function get_config()
    local c = uci.cursor() -- each time as /etc/config/aredn may have changed
    return {
        margin = tonumber(c:get("aredn", "@lqm[0]", "margin_snr")),
        low = tonumber(c:get("aredn", "@lqm[0]", "min_snr")),
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
    for line in io.popen(NFT .. " -a list chain inet fw4 " .. list):lines()
    do
        local handle = line:match(query .. "%s*# handle (%d+)")
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
            if not nft_handle("input_lqm", "iifname \\\"" .. trace.device .. "\\\" udp dport 698 .* drop") then
                os.execute(NFT .. " insert rule inet fw4 input_lqm iifname \\\"" .. trace.device .. "\\\" udp dport 698 counter drop 2> /dev/null")
                return "blocked"
            end
        else
            if not nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac:lower() .. " .* drop") then
                os.execute(NFT .. " insert rule inet fw4 input_lqm udp dport 698 ether saddr " .. track.mac .. " counter drop 2> /dev/null")
                return "blocked"
            end
        end
    else
        track.blocked = false
        if track.type == "Tunnel" then
            local handle = nft_handle("input_lqm", "iifname \\\"" .. trace.device .. "\\\" udp dport 698 .* drop")
            if handle then
                os.execute(NFT .. " delete rule inet fw4 input_lqm handle " .. handle)
                return "unblocked"
            end
        else
            local handle = nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac:lower() .. " .* drop") 
            if handle then
                os.execute(NFT .. " delete rule inet fw4 input_lqm handle " .. handle)
                return "unblocked"
            end
        end
    end
    return "unchanged"
end

function force_remove_block(track)
    track.blocked = false
    local handle = nft_handle("input_lqm", "udp dport 698 ether saddr " .. track.mac:lower() .. " .* drop") 
    if handle then
        os.execute(NFT .. " delete rule inet fw4 input_lqm handle " .. handle)
    end
    handle = nft_handle("input_lqm", "iifname \\\"" .. trace.device .. "\\\" udp dport 698 .* drop")
    if handle then
        os.execute(NFT .. " delete rule inet fw4 input_lqm handle " .. handle)
    end
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
f:write('{"trackers":{}}')
f:close()

local cursor = uci.cursor()

-- Get radio
local radioname = "radio0"
local radiomode = "none"
for i = 0,2
do
    if cursor:get("wireless", "@wifi-iface[" .. i .. "]", "network") == "wifi" then
        radioname = cursor:get("wireless", "@wifi-iface[" .. i .. "]", "device")
        radiomode = cursor:get("wireless", "@wifi-iface[" .. i .. "]", "mode")
        break
    end
end
local phy = "phy" .. radioname:match("radio(%d+)")
local wlan = aredn.hardware.get_board_network_ifname("wifi")

function lqm()

    if cursor:get("aredn", "@lqm[0]", "enable") ~= "1" then
        exit_app()
        return
    end

    -- Let things startup for a while before we begin
    wait_for_ticks(math.max(1, 30 - nixio.sysinfo().uptime))

    -- Create filters (cannot create during install as they disappear on reboot)
    os.execute(NFT .. " flush chain inet fw4 input_lqm")
    os.execute(NFT .. " delete chain inet fw4 input_lqm")
    os.execute(NFT .. " add chain inet fw4 input_lqm")
    local handle = nft_handle("input", "jump input_lqm comment \\\"block low quality links\\\"")
    if handle then
        os.execute(NFT .. " delete rule inet fw4 input handle " .. handle)
    end
    os.execute(NFT .. " insert rule inet fw4 input counter jump input_lqm comment \\\"block low quality links\\\"")

    -- We dont know any distances yet
    os.execute(IW .. " " .. phy .. " set distance auto")

    -- Setup a first_run timeout if this is our first every run
    if cursor:get("aredn", "@lqm[0]", "first_run") == "0" then
        first_run_timeout = 0
    else
        first_run_timeout = first_run_timeout + nixio.sysinfo().uptime
    end

    local tracker = {}
    local dtdlinks = {}
    while true
    do
        now = nixio.sysinfo().uptime

        local config = get_config()

        local lat = tonumber(cursor:get("aredn", "@location[0]", "lat"))
        local lon = tonumber(cursor:get("aredn", "@location[0]", "lon"))

        local arps = {}
        arptable(
            function (entry)
                if entry["Flags"] ~= "0x0" then
                    arps[entry["HW address"]:upper()] = entry
                end
            end
        )

        -- Know our macs so we can exclude them
        local our_macs = {}
        for _, i in ipairs(nixio.getifaddrs()) do
            if i.family == "packet" and i.addr then
                our_macs[i.addr] = true
            end
        end

        local stations = {}

        -- RF
        if radiomode == "adhoc" then
            local kv = {
                ["signal avg:"] = "signal",
                ["tx packets:"] = "tx_packets",
                ["tx retries:"] = "tx_retries",
                ["tx failed:"] = "tx_fail"
            }
            local station = {}
            local noise = iwinfo.nl80211.noise(wlan) or -95
            for line in io.popen(IW .. " " .. wlan .. " station dump"):lines()
            do
                local mac = line:match("^Station ([0-9a-f:]+) ")
                if mac then
                    station = {
                        type = "RF",
                        device = wlan,
                        mac = mac:upper(),
                        signal = 0,
                        noise = noise,
                        ip = nil
                    }
                    local entry = arps[station.mac]
                    if entry then
                        station.ip = entry["IP address"]
                    end
                    stations[#stations + 1] = station
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
                    tx_retries = 0
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

        -- DtD
        for mac, entry in pairs(arps)
        do
            if entry.Device:match("%.2$") or entry.Device == "br-dtdlink" then
                stations[#stations + 1] = {
                    type = "DtD",
                    device = entry.Device,
                    signal = nil,
                    ip = entry["IP address"],
                    mac = mac:upper(),
                    tx_packets = 0,
                    tx_fail = 0,
                    tx_retries = 0
                }
            end
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
                        quality = 100
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
                        track.hostname = hostname:lower():gsub("^dtdlink%.",""):gsub("^mid%d+%.",""):gsub("%.local%.mesh$", "")
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

                local old_rev_snr = track.rev_snr
                track.rev_snr = null
                dtdlinks[track.mac] = {}

                local raw = io.popen("/usr/bin/wget -O - 'http://" .. track.ip .. ":8080/cgi-bin/sysinfo.json?link_info=1&lqm=1' 2>/dev/null")
                local info = luci.jsonc.parse(raw:read("*a"))
                raw:close()
                if info then
                    if tonumber(info.lat) and tonumber(info.lon) then
                        track.lat = tonumber(info.lat)
                        track.lon = tonumber(info.lon)
                        if lat and lon then
                            track.distance = calc_distance(lat, lon, track.lat, track.lon)
                        end
                    end
                    if track.type == "RF" then
                        if info.lqm and info.lqm.enabled then
                            for _, rtrack in pairs(info.lqm.info.trackers)
                            do
                                if myhostname == rtrack.hostname and (not rtrack.type or rtrack.type == "RF") then
                                    if not old_rev_snr or not rtrack.snr then
                                        track.rev_snr = rtrack.snr
                                    else
                                        track.rev_snr = math.ceil(snr_run_avg * old_rev_snr + (1 - snr_run_avg) * rtrack.snr)
                                    end
                                end
                            end
                            for ip, link in pairs(info.link_info)
                            do
                                if link.hostname and link.linkType == "DTD" then
                                    dtdlinks[track.mac][link.hostname:lower():gsub("^dtdlink%.",""):gsub("%.local%.mesh$", "")] = true
                                end
                            end
                        elseif info.link_info then
                            -- If there's no LQM information we fallback on using link information.
                            for ip, link in pairs(info.link_info)
                            do
                                if link.hostname then
                                    local hostname = link.hostname:lower():gsub("^dtdlink%.",""):gsub("%.local%.mesh$", "")
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
                if track.type == "Tunnel" then
                    -- Tunnels have no MAC, so we can only use IP level pings.
                    local sigsock = nixio.socket("inet", "dgram")
                    sigsock:setopt("socket", "bindtodevice", track.device)
                    sigsock:setopt("socket", "dontroute", 1)
                    sigsock:setopt("socket", "rcvtimeo", ping_timeout)
                    -- Must connect or we wont see the error
                    sigsock:connect(track.ip, 8080)
                    sigsock:send("")
                    -- There's no actual UDP server at the other end so recv will either timeout and return 'false' if the link is slow,
                    -- or will error and return 'nil' if there is a node and it send back an ICMP error quickly (which for our purposes is a positive)
                    if sigsock:recv(0) == false then
                        success = 0
                    end
                    sigsock:close()
                else
                    -- Make an arp request to the target ip to see if we get a timely reply. By using ARP we avoid any
                    -- potential routing issues and avoid any firewall blocks on the other end.
                    -- As the request is broadcast, we avoid any potential distance/scope timing issues as we dont wait for the
                    -- packet to be acked. The reply will be unicast to us, and our ack to that is unimportant to the latency test.
                    if os.execute(ARPING .. " -f -w " .. ping_timeout .. " -I " .. track.device .. " " .. track.ip .. " >/dev/null") ~= 0 then
                        success = 0
                    end
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
            -- SNR and distance blocks only related to RF links
            if track.type == "RF" then

                -- If we have a direct dtd connection to this device, make sure we use that
                local a, b, c = track.mac:match("^(..:..:..:)(..)(:..:..)$")
                local dtd = tracker[string.format("%s%02X%s", a, tonumber(b, 16) + 1, c)]
                if dtd and dtd.type == "DtD" and dtd.distance < dtd_distance then
                    track.blocks.dtd = true
                else
                    track.blocks.dtd = false
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

        -- Update the block state and calculate the routable distance
        for _, track in pairs(tracker)
        do
            if is_connected(track) then 
                if update_block(track) == "unblocked" then
                    -- If the link becomes unblocked, return it to pending state
                    track.pending = now + pending_timeout
                end

                -- Find the most distant, unblocked, routable, RF node
                if track.type == "RF" and not track.blocked and track.distance then
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
                force_remove_block(track)
                tracker[track.mac] = nil
            end
        end

        distance = distance + 1
        alt_distance = alt_distance + 1

        -- Update the wifi distance
        if distance > 0 then
            coverage = math.min(255, math.floor((distance * 2 * 0.0033) / 3)) -- airtime
            os.execute(IW .. " " .. phy .. " set coverage " .. coverage)
        elseif alt_distance > 1 then
            coverage = math.min(255, math.floor((alt_distance * 2 * 0.0033) / 3))
            os.execute(IW .. " " .. phy .. " set coverage " .. coverage)
        elseif config.auto_distance > 0 then
            os.execute(IW .. " " .. phy .. " set distance " .. config.auto_distance)
        else
            os.execute(IW .. " " .. phy .. " set distance auto")
        end

        -- Save this for the UI
        f = io.open("/tmp/lqm.info", "w")
        if f then
            f:write(luci.jsonc.stringify({
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
