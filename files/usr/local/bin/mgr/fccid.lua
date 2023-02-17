--[[

    Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
    Copyright (C) 2021 Tim Wilkinson
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

function fccid()
    local c = uci.cursor()
    local device = c:get("network", "wifi", "device")
    local name = c:get("system","@system[0]", "hostname") or "localnode"
    local lat = c:get("aredn", "@location[0]", "lat")
    local lon = c:get("aredn", "@location[0]", "lon")
    local id = "ID: " .. name
    if lat and lon then
        id = id .. " LOCATION: " .. lat .. "," .. lon
    end
    local beacon = "echo '" .. id .. "' | /usr/bin/socat - udp-datagram:10.255.255.255:4919,bind=:4191,broadcast,so-bindtodevice=" .. device
    while true
    do
        os.execute(beacon)
        wait_for_ticks(5 * 60) -- 5 minutes
    end
end

return fccid
