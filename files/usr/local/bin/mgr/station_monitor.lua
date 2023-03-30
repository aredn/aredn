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

local wifiiface

local IW = "/usr/sbin/iw"
local ARPING = "/usr/sbin/arping"

function station_monitor()
    if not string.match(get_ifname("wifi"), "^wlan") then
        exit_app()
    else
        wait_for_ticks(math.max(1, 120 - nixio.sysinfo().uptime))

        wifiiface = get_ifname("wifi")

        while true
        do
            run_station_monitor()
            wait_for_ticks(300) -- 5 minute
        end
    end
end

local logfile = "/tmp/station_monitor.log"
if not file_exists(logfile) then
    io.open(logfile, "w+"):close()
end
local log = aredn.log.open(logfile, 8000)

function run_station_monitor()

    -- Check each station to make sure we can broadcast and unicast to them
    arptable(
        function (entry)
            if entry.Device == wifiiface then
                local ip = entry["IP address"]
                local mac = entry["HW address"]
                if entry["Flags"] ~= "0x0" and ip and mac then
                    -- Two arp pings - the first is broadcast, the second unicast
                    for line in io.popen(ARPING .. " -c 2 -I " .. wifiiface .. " " .. ip):lines()
                    do
                        -- If we see exactly one response then we neeed to force the station to reassociate
                        -- This indicates that broadcasts work, but unicasts dont
                        if line:match("Received 1 response") then
                            log:write("Unresponsive node: ip " .. ip .. ", mac " .. mac)
                            log:flush()
                            break
                        end
                    end
                end
            end
        end
    )
end

return station_monitor
