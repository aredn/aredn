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

local http = require("socket.http")
local json = require("luci.jsonc")

local resp, status_code = http.request("http://127.0.0.1:9090/links")
if status_code == 200 then
    local links = json.parse(resp).links

    local props = {
        { "asymmetry_time", "asymmetryTime" },
        { "hello_time", "helloTime" },
        { "hysteresis", "hysteresis" },
        { "last_hello_time", "lastHelloTime", },
        { "link_cost", "linkCost" },
        { "link_quality", "linkQuality" },
        { "loss_hello_interval", "lossHelloInterval" },
        { "loss_multiplier", "lossMultiplier" },
        { "loss_time", "lossTime" },
        { "lost_link_time", "lostLinkTime" },
        { "neighbor_link_quality", "neighborLinkQuality" },
        { "pending", "pending" },
        { "seqno", "seqno" },
        { "seqno_valid", "seqnoValid" },
        { "symmetry_time", "symmetryTime" },
        { "validity_time", "validityTime" },
        { "vtime", "vtime" }
    }
    
    for _, keys in ipairs(props)
    do
        local key = keys[1]
        print("# HELP node_olsr_link_" .. key)
        print('# TYPE node_olsr_link_' .. key .. ' gauge')
        for _, link in pairs(links)
        do
            local val = link[keys[2]]
            if val then
                if type(val) == "boolean" then
                    val = val and 1 or 0
                end
                local ip = link.localIP or ""
                local remote = link.remoteIP or ""
                local device = link.olsrInterface or ""
                print('node_olsr_link_' .. key .. '{device="' .. device .. '",local_ip="' .. ip .. '",remote_ip="' .. remote .. '"} ' .. val)
            end
        end
    end
end
