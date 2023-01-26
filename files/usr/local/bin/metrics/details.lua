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

require("aredn.hardware")
local info = require("aredn.info")

local lat, lon = info.getLatLon()

print('node_details_basics{' ..
		'board_id="' .. hardware_boardid() .. '"' ..
		',description="' .. info.getNodeDescription() .. '"' ..
		',firmware_version="' .. info.getFirmwareVersion() .. '"' ..
		',gridsquare="' .. info.getGridSquare() .. '"' ..
		',lat="' .. lat .. '"' ..
		',lon="' .. lon .. '"' ..
		',model="' .. info.getModel() .. '"' ..
        ',node="' .. info.getNodeName() .. '"' ..
        ',tactical="' .. info.getTacticalName() .. '"' ..
    '} 1')

local dev = info.getMeshRadioDevice()
if dev ~= "" then
    print('node_details_meshrf{' ..
		'band="' .. info.getBand(dev) .. '"' ..
        ',channel="' .. info.getChannel(dev) .. '"' ..
        ',chanbw="' .. info.getChannelBW(dev) .. '"' ..
        ',device="' .. dev .. '"' ..
        ',frequency="' .. info.getFreq() .. '"' ..
		',ssid="' .. info.getSSID() .. '"' ..
    '} 1')
else
    print('node_details_meshrf 0')
end
