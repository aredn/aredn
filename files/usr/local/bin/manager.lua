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
socket = require("socket")
require("aredn.utils")
aredn_info = require("aredn.info")
require("iwinfo")
require("aredn.http")
require("aredn.hardware")
require("aredn.log")
require("luci.sys")

-- aggressive gc on low memory devices
if aredn_info.getFreeMemory().totalram < 32768 then
	collectgarbage("setstepmul", 1000)
end

function wait_for_ticks(ticks)
    coroutine.yield(ticks)
end

function exit_app()
	coroutine.yield('exit')
end

-- Define the list of management task
local tasks = {
	{ app = require("mgr.rssi_monitor") },
	{ app = require("mgr.linkled") },
	{ app = require("mgr.namechange") },
	{ app = require("mgr.watchdog") },
	{ app = require("mgr.fccid") },
	{ app = require("mgr.snrlog") },
	{ app = require("mgr.aredn_message") }
}

local log = aredn.log.open("/tmp/manager.log", 8000)

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
			local status, newdelay = coroutine.resume(task.routine)
			if not status then
				log:write(newdelay) -- error message
				log:flush()
				task.routine = coroutine.create(task.app)
				task.time = 120 + os.time() -- 2 minute restart delay
			elseif not newdelay then
				task.time = 60 + os.time() -- 1 minute default delay
			elseif newdelay == "exit" then
				task.routine = null
				task.time = math.huge
			else
				task.time = newdelay + os.time()
			end
		end
	end
	table.sort(tasks, function(a,b) return a.time < b.time end)
	local delay = tasks[1].time - os.time()
	if delay > 0 then
		nixio.nanosleep(delay, 0)
	end
end
