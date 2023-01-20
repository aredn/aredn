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

reqire("iwinfo")

local wifistaprops = {
    { "noise", "noise" },
    { "receive_mcs", "rx_mcs" },
    { "receive_packets_total", "rx_packets" },
    { "receive_rate_bits_per_second", "rx_rate", 1024 },
    { "signal", "signal" },
    { "transmit_mcs", "tx_mcs" },
    { "transmit_packets_total", "tx_packets" },
    { "transmit_rate_bits_per_second", "tx_rate", 1024 },
}
for _, keys in ipairs(wifistaprops)
do
    print('# HELP node_wifi_station_' .. keys[1])
    print('# TYPE node_wifi_station_' .. keys[1] .. (keys[1]:match('_total$') and ' counter' or ' gauge'))
    for _, wlan in ipairs({ "wlan0", "wlan1" })
    do
        local stations = iwinfo.nl80211.assoclist(wlan)
        for mac, station in pairs(stations)
        do
            local val = station[keys[2]]
            if val then
                if keys[3] then
                    val = val * keys[3]
                end
                print('node_wifi_station_' .. keys[1] .. '{device="' .. wlan .. '",mac="' .. mac .. '"} ' .. val)
            end
        end
    end
end
