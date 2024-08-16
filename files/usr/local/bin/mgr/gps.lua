--[[

    Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
    Copyright (C) 2024 Tim Wilkinson
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

    Additional use restrictions exist on the AREDN® trademark and logo.
        See AREDNLicense.txt for more info.

    Attributions to the AREDN® Project must be retained in the source code.
    If importing this code into a new or existing project attribution
    to the AREDN® project must be added to the source code.

    You must not misrepresent the origin of the material contained within.

    Modified versions must be modified to attribute to the original source
    and be marked in reasonable ways as differentiate it from the original
    version

--]]

local app = {}
local CONFIG0 = "/etc/config.mesh/gpsd"
local CONFIG1 = "/etc/config/gpsd"
local CHANGEMARGIN = 0.0001

function app.run()

    wait_for_ticks(60)

    local gps
    while true
    do
        gps = aredn.hardware.gps_find()
        if gps then
            break
        end
        wait_for_ticks(600) -- 10 minutes
    end

    -- Create the GPSD daemon if device is local,
    -- otherwise we get the GPS info from another node on our local network
    if gps:match("^/dev/") then
        local f = io.open(CONFIG0, "w")
        f:write(
[[config gpsd 'core'
    option enabled '1'
    option device ']] .. gps .. [['
    option port '2947'
    option listen_globally '1'
]])
        f:close()
        filecopy(CONFIG0, CONFIG1, true)
        os.execute("nft insert rule ip fw4 input_dtdlink tcp dport 2947 accept comment \"gpsd\" 2> /dev/null")
        os.execute("/etc/init.d/gpsd restart")
    end

    while true
    do
        local c = uci.cursor()
        local j = aredn.hardware.gps_read_llt(gps)

        -- Update time and date
        if c:get("aredn", "@time[0]", "gps_enable") == "1" and j.time then
            os.execute("/bin/date -u -s '" .. j.time .. "' > /dev/nul 2>&1")
            write_all("/tmp/timesync", "gps")
        end

        -- Set location if significantly changed
        if c:get("aredn", "@location[0]", "gps_enable") == "1" then
            local clat = tonumber(c:get("aredn", "@location[0]", "lat") or 0)
            local clon = tonumber(c:get("aredn", "@location[0]", "lon") or 0)
            if math.abs(clat - j.lat) > CHANGEMARGIN or math.abs(clon - j.lon) > CHANGEMARGIN then
                -- Calculate gridsquare from lat/lon
                local alat = j.lat + 90
                local flat = 65 + math.floor(alat / 10)
                local slat = math.floor(alat % 10)
                local ulat = 97 + math.floor((alat - math.floor(alat)) * 60 / 2.5)

                local alon = j.lon + 180
                local flon = 65 + math.floor(alon / 20)
                local slon = math.floor((alon / 2) % 10)
                local ulon = 97 + math.floor((alon - 2 * math.floor(alon / 2)) * 60 / 5)

                local gridsquare = string.format("%c%c%d%d%c%c", flon, flat, slon, slat, ulon, ulat)

                -- Update location information
                c:set("aredn", "@location[0]", "lat", j.lat)
                c:set("aredn", "@location[0]", "lon", j.lon)
                c:set("aredn", "@location[0]", "gridsquare", gridsquare)
                c:set("aredn", "@location[0]", "source", "gps")
                c:commit("aredn")
                local cm = uci.cursor("/etc/config.mesh")
                cm:set("aredn", "@location[0]", "lat", j.lat)
                cm:set("aredn", "@location[0]", "lon", j.lon)
                cm:set("aredn", "@location[0]", "gridsquare", gridsquare)
                cm:set("aredn", "@location[0]", "source", "gps")
                cm:commit("aredn")
            end
        end

        wait_for_ticks(600) -- 10 minutes
    end
end

return app.run
