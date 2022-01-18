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

local log = {}
log.__index = log

function log.open(name, maxsize)
    local l = {}
    setmetatable(l, log)
    l.logfile = name
    l.logmax = maxsize
    l.logf = nil
    return l
end

function log:write(str)
    if not self.logf then
        self.logf = io.open(self.logfile, "a")
    end
    self.logf:write(string.format("%s: %s\n", os.date("%m/%d %H:%M:%S", os.time()), str))
    if self.logf:seek() > self.logmax then
        self:flush(true)
    end
end

function log:flush(archive)
    if self.logf then
        self.logf:close()
        self.logf = nil
        if archive then
            local old = self.logfile .. '.0'
            if nixio.fs.stat(old) then
                os.remove(old)
            end
            os.rename(self.logfile, old)
        end
    end
end

function log:close()
    self:flush()
end

if not aredn then
    aredn = {}
end
aredn.log = log
return log
