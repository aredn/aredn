--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

local link1led

function linkled()
    local link = aredn.hardware.get_link_led()
    if not link then
        exit_app()
    else
        -- Reset leds
        write_all(link .. "/trigger", "none")
        write_all(link .. "/brightness", "1")

		-- Wait for 2 minutes before monitoring status. During this time the led is on
		wait_for_ticks(120)

        while true
        do
			local raw = io.popen("/usr/bin/wget -O - http://127.0.0.1:9090/neighbors 2> /dev/null")
			local nei = luci.jsonc.parse(raw:read("*a"))
			raw:close()
            if nei and #nei.neighbors > 0 then
				-- Led on when link established. Retest every 10 seconds
                write_all(link .. "/brightness", "1")
				wait_for_ticks(10)
            else
				-- Flash led slowly - off 3 seconds, on 3 seconds - when no links
                write_all(link .. "/brightness", "0")
				wait_for_ticks(3)
				write_all(link .. "/brightness", "1")
				wait_for_ticks(3)
            end
        end
    end
end

return linkled
