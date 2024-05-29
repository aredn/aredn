--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

function run_scripts(dir)
    if nixio.fs.stat(dir, "type") == "dir" then
        for script in nixio.fs.dir(dir)
        do
            local stat = nixio.fs.stat(dir .. "/" .. script)
            if script:match("^[a-zA-Z0-9_%-]+$") and stat.type == "reg" and nixio.bit.band(tonumber(stat.modedec, 8), tonumber(111, 8)) ~= 0 then
                os.execute("(cd /tmp;" .. dir .. "/" .. script .. " 2>&1 | logger -p daemon.debug -t " .. script .. ")&")
            end
        end
    end
end

function periodic()
    run_scripts("/etc/cron.boot")
    wait_for_ticks(120) -- Initial wait before starting up period tasks
    local hours = 0
    local days = 0
    while true
    do
        run_scripts("/etc/cron.hourly")
        hours = hours - 1
        if hours <= 0 then
            run_scripts("/etc/cron.daily")
            hours = 24
            days = days - 1
            if days <= 0 then
                run_scripts("/etc/cron.weekly")
                days = 7
            end
        end
        wait_for_ticks(60 * 60)
    end
end

return periodic
