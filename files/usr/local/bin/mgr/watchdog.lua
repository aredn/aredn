
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
	Original Shell Copyright (C) 2019 Joe Ayers AE6XE
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

local watchdogfile = "/tmp/olsrd.watchdog"
local pidfile = "/var/run/olsrd.pid"
local logfile = "/tmp/olsrd.log"

function olsrd_restart()
    -- print "olsrd_restart"

    os.execute("/etc/init.d/olsrd restart")

    if nixio.fs.stat(logfile) then
        local lines = read_all(logfile):splitNewLine()
        lines[#lines + 1] = secondsToClock(nixio.sysinfo().uptime) .. " " .. os.date()
        local start = 1
        if #lines > 300 then
            start = #lines - 275
        end
        local f = io.open(logfile, "w")
        if f then
            for i = start, #lines
            do
                f:write(lines[i] .. "\n")
            end
            f:close()
        end
    end
end

function watchdog()
    while true
    do
        wait_for_ticks(223)

        local pid = read_all(pidfile)
        if pid and nixio.fs.stat("/proc/" .. pid) then
            if nixio.fs.stat(watchdogfile) then
                os.remove(watchdogfile)
            else
                olsrd_restart()
            end
        else
            local pids = capture("pidof olsrd"):splitWhiteSpace()
            if #pids == 1 then
                write_all(pidfile, pids[1]);
            elseif #pids == 0 then
                olsrd_restart()
            end
        end

    end
end

return watchdog
