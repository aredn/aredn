--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
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

function rssi_monitor()
    if string.match(get_ifname("wifi"), "^eth.") then
        exit_app()
    else
        wait_for_ticks(math.max(1, 120 - nixio.sysinfo().uptime))
        while true
        do
            run_monitor()
            wait_for_ticks(60) -- 1 minute
        end
    end
end

local logfile = "/tmp/rssi_ath10k.log"

if not file_exists(logfile) then
    io.open(logfile, "w+"):close()
end

local last_station_count = 0

local wifiiface = get_ifname("wifi")
local phy = iwinfo.nl80211.phyname(wifiiface)

local log = aredn.log.open(logfile, 16000)

function run_monitor()

    -- ath10k only
    if not nixio.fs.stat("/sys/kernel/debug/ieee80211/" .. phy .. "/ath10k") then
        exit_app()
        return
    end

    local station_count = 0
    local stations = iwinfo.nl80211.assoclist(wifiiface)
    for mac, station in pairs(stations)
    do
        station_count = station_count + 1
    end

    if station_count == 0 and last_station_count ~= 0 then
         -- reset
         os.execute("/usr/sbin/iw " .. wifiiface .. " scan")
         wait_for_ticks(5)
         log:write("No stations detected")
         log:flush()
    end
    last_station_count = station_count
end

return rssi_monitor
