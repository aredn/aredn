--[[

	Copyright (C) 2025 Tim Wilkinson
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

local BAD_COST = 65535
local MIN_LQ = 50

local M = {};

function M.reach2lq(r)
    local i = 1
    local count = 0
    r = tonumber(r, 16)
    while i < 0x10000
    do
        if nixio.bit.band(r, i) ~= 0 then
            count = count + 1
        end
        i = i * 2
    end
    return math.floor(0.5 + 100 * count / 16)
end


function M.babelmon()
    if not nixio.fs.stat("/usr/sbin/babeld") then
        exit_app()
        return
    end

    wait_for_ticks(math.max(0, 60 - nixio.sysinfo().uptime))
    while true
    do
        local reset = false
        local neighbors
        for line in io.popen("echo 'dump-neighbors' | socat UNIX-CLIENT:/var/run/babel.sock -"):lines()
        do
            local reach, cost = line:match("reach (%S+).+ cost (%S+)")
            if reach and tonumber(cost) == BAD_COST and M.reach2lq(reach) > MIN_LQ then
                reset = true
            end
        end

        if reset then
            nixio.syslog("err", "Hard restarting babel to reset sequence number")
            os.execute("/etc/init.d/babel stop; rm -f /etc/state/babel-state ; /etc/init.d/babel start");
            wait_for_ticks(300)
        else
            wait_for_ticks(60)
        end
    end
end

return M.babelmon
