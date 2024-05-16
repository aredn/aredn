#!/usr/bin/lua
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
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

package.path = package.path .. ";/usr/local/bin/?.lua"

require("uci")
require("nixio")
require("aredn.utils")
require("iwinfo")
require("aredn.hardware")
require("aredn.olsr")
require("luci.jsonc")
require("ubus")

-- aggressive gc on low memory devices
if nixio.sysinfo().totalram < 32 * 1024 * 1024 then
	collectgarbage("setstepmul", 1000)
end

function wait_for_ticks(ticks)
	if ticks <= 0 then
		coroutine.yield(0)
	else
		local when = nixio.sysinfo().uptime + ticks
		while true
		do
			if ticks > 0 then
				coroutine.yield(ticks)
			else
				break
			end
			ticks = when - nixio.sysinfo().uptime
		end
	end
end

function exit_app()
	coroutine.yield('exit')
end

-- Load management tasks
local tasks = {}
for name in nixio.fs.dir("/usr/local/bin/mgr")
do
	local task = name:match("^(.+)%.lua$")
	if task then
		tasks[#tasks + 1] = { name = task, app = require("mgr." .. task) }
	end
end

for i, task in ipairs(tasks)
do
	task.routine = coroutine.create(task.app)
	task.time = 0
end

while true
do
	for i, task in ipairs(tasks)
	do
		if task.time <= os.time() then
			nixio.openlog("manager." .. task.name)
			local status, newdelay = coroutine.resume(task.routine)
			if not status then
				nixio.syslog("err", newdelay)
				task.routine = coroutine.create(task.app)
				task.time = 120 + os.time() -- 2 minute restart delay
			elseif not newdelay then
				task.time = 60 + os.time() -- 1 minute default delay
			elseif newdelay == "exit" then
				task.routine = null
				task.time = math.huge
				nixio.syslog("notice", "Terminating manager task: " .. task.name)
			else
				task.time = newdelay + os.time()
			end
			nixio.closelog()
		end
	end
	table.sort(tasks, function(a,b) return a.time < b.time end)
	local delay = tasks[1].time - os.time()
	if delay > 0 then
		collectgarbage("collect")
		delay = tasks[1].time - os.time()
		if delay > 0 then
			nixio.nanosleep(delay, 0)
		end
	end
end
