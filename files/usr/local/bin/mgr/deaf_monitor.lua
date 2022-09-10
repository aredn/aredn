--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2022 Tim Wilkinson
	Original Shell Copyright (C) 2015 Conrad Lara
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

local log = aredn.log.open("/tmp/deaf.log", 16000)

function deaf_monitor()

    local wifiiface = get_ifname("wifi")

    -- if Mesh RF is turned off do nothing
    if wifiiface:match("eth.*") then
        exit_app()
    end

    local isdeaf = false
    log:write("Starting")

    while true
    do
        wait_for_ticks(5 * 60) -- 5 minutes

        -- Count the number of stations associated with the node. If it's zero we may be deaf
        local stations = iwinfo.nl80211.assoclist(wifiiface)
        local active = false
        for _, station in pairs(stations)
        do
            if station.signal ~= 0 then
                active = true
                isdeaf = false
                break
            end
        end
        if not active then
            -- Only print this message once when we think the node goes deaf
            if not isdeaf then
                log:write("Possible deaf node after " .. nixio.sysinfo().uptime)
                isdeaf = true
            end
            -- A scan will restore the node's hearing
            os.execute("/usr/sbin/iw " .. wifiiface .. " scan freq " .. aredn_info.getFreq() .. " passive")
        end
    end
end

return deaf_monitor
