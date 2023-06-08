--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2023 Tim Wilkinson
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

local unresponsive_max = 5
local unresponsive_report = 3
local last = {}
local wifiiface
local frequency
local ssid

local IW = "/usr/sbin/iw"
local ARPING = "/usr/sbin/arping"

local logfile = "/tmp/station_monitor.log"
if not file_exists(logfile) then
    io.open(logfile, "w+"):close()
end
local log = aredn.log.open(logfile, 8000)

function rejoin_network()
    os.execute(IW .. " " .. wifiiface .. " ibss leave")
    os.execute(IW .. " " .. wifiiface .. " ibss join " .. ssid .. " " .. frequency .. " fixed-freq")
    log:write("Rejoining network")
    log:flush()
end

function station_monitor()
    if not string.match(get_ifname("wifi"), "^wlan") then
        exit_app()
    else
        wait_for_ticks(math.max(1, 120 - nixio.sysinfo().uptime))

        wifiiface = get_ifname("wifi")
        frequency = iwinfo.nl80211.frequency(wifiiface)
        ssid = iwinfo.nl80211.ssid(wifiiface)

        -- If frequency or ssid is missing (some kind of bad configuration) just exit this
        if not (frequency and ssid) then
            exit_app()
            return
        end

        -- Mikrotik AC hardware has some startup issues which we try to resolve
        -- by leaving and rejoining the network
        local boardid = aredn.hardware.get_board_id():lower()
        if boardid:match("mikrotik") and boardid:match("ac") then
            rejoin_network()
        end

        -- Only monitor if we have LQM information
        if uci.cursor():get("aredn", "@lqm[0]", "enable") ~= "1" then
            exit_app()
            return
        end

        while true
        do
            run_station_monitor()
            wait_for_ticks(60) -- 1 minute
        end
    end
end

function run_station_monitor()

    -- Use the LQM state to ignore nodes we dont care about
    local trackers = nil
    local f = io.open("/tmp/lqm.info")
    if f then
        local lqm = luci.jsonc.parse(f:read("*a"))
        f:close()
        trackers = lqm.trackers
    end
    local now = nixio.sysinfo().uptime

    -- Check each station to make sure we can broadcast and unicast to them
    local total = 0
    local old = last
    last = {}
    arptable(
        function (entry)
            if entry.Device == wifiiface then
                local ip = entry["IP address"]
                local mac = entry["HW address"] or ""
                -- Only consider nodes which have valid ip and macs, routable and not pending
                local tracker = { pending = 0, routable = true }
                if trackers then
                    tracker = trackers[mac:upper()] or { pending = now, routable = false }
                end
                if entry["Flags"] ~= "0x0" and ip and mac ~= "" and tracker.routable and tracker.pending < now then
                    -- Two arp pings - the first is broadcast, the second unicast
                    for line in io.popen(ARPING .. " -c 2 -I " .. wifiiface .. " " .. ip):lines()
                    do
                        -- If we see exactly one response then we neeed to force the station to reassociate
                        -- This indicates that broadcasts work, but unicasts dont
                        if line:match("Received 1 response") then
                            local val = (old[ip] or 0) + 1
                            last[ip] = val
                            if val > unresponsive_report then
                                log:write("Possible unresponsive node: " .. ip .. " [" .. mac .. "]")
                                log:flush()
                            end
                            if val > total then
                                total = val
                            end
                            break
                        end
                    end
                end
            end
        end
    )

    -- If we find unresponsive nodes too often then we leave and rejoin the network
    -- to reset everything
    if total >= unresponsive_max then
        last = {}
        rejoin_network()
    end
end

return station_monitor
