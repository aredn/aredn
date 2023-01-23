#!/usr/bin/lua
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

require("luci.jsonc")

local f = io.open("/tmp/lqm.info")
if f then
    local lqm = luci.jsonc.parse(f:read("*a"))
    f:close()

    local props = {
        "avg_snr",
        "blocked",
        "distance",
        "exposed",
        "hidden",
        "last_tx_total",
        "lat",
        "lon",
        "ping_quality",
        "quality",
        "rev_snr",
        "routable",
        "tx_quality",
        "user_allow"
    }
    
    for _, key in ipairs(props)
    do
        print("# HELP node_lqm_tracker_" .. key)
        print('# TYPE node_lqm_tracker_' .. key .. (key:match('_total$') and ' counter' or ' gauge'))
        for mac, tracker in pairs(lqm.trackers)
        do
            local ip = tracker.ip or ""
            local hostname = tracker.hostname or ip
            local ltype = tracker.type or "unknown"
            local val = tracker[key]
            if val then
                if type(val) == "boolean" then
                    val = val and 1 or 0
                end
                print('node_lqm_tracker_' .. key .. '{type="' .. ltype .. '",hostname="' .. hostname .. '",ip="' .. ip .. '",mac="' .. mac .. '"} ' .. val)
            end
        end
    end
end
