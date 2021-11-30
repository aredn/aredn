--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
	Original Shell Copyright (C) 2018 Joe Ayers AE6XE
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

function clean_zombie()
    while true
    do
        clean()
        wait_for_ticks(60) -- 1 minute
    end
end

local zombies = { "iw" }

local log = aredn.log.open("/tmp/zombie.log", 12000)

function clean()
    for i, name in ipairs(zombies)
    do
        local pids = capture("pidof " .. name):splitWhiteSpace()
        for j, pid in ipairs(pids)
        do
            local zombie = false
            local ppid = nil
            local all = read_all("/proc/" .. pid .. "/status")
            if all then
                for k, line in ipairs(all:splitNewLine())
                do
                    -- Look for a zombie
                    local m = string.match(line, "State:%s[ZT]")
                    if m then
                        zombie = true
                    end
                    if zombie then
                        m = string.match(line, "PPid:%s([0-9]*)")
                        if m then
                            ppid = m
                            break
                        end
                    end
                end
                if ppid and ppid ~= 1 then
                    log:write("Killed " .. ppid)
                    nixio.kill(ppid, 9)
                end
            end
        end
    end
    log:flush()
end

return clean_zombie
