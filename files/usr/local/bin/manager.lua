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

require("mgr.utils")
require("uci")
require("posix")
socket = require("socket")
require("aredn.utils")
aredn_info = require("aredn.info")
require("aredn.uci")
nxo = require("nixio")
require("iwinfo")
require("luci.sys")

local tasks = {
	coroutine.create(require("mgr.rssi_monitor")),
	coroutine.create(require("mgr.linkled")),
	coroutine.create(require("mgr.namechange")),
	coroutine.create(require("mgr.watchdog")),
	coroutine.create(require("mgr.fccid")),
	coroutine.create(require("mgr.snrlog"))
}

local delay = 0
while true
do
	print "Tick"
	local times = {}
	for i,task in ipairs(tasks)
	do
		local status, newdelay = coroutine.resume(task, delay)
		if not status then
			print (newdelay) -- error message
			newdelay = 1
		elseif not newdelay then
			newdelay = 1
		end
		times[i] = newdelay + os.time()
	end
	table.sort(times)
	delay = times[1] - os.time()
	if delay > 0 then
		posix.unistd.sleep(delay)
	else
		delay = 0
	end
end
