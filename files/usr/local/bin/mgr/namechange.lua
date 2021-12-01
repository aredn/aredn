--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
	Original Perl Copyright (C) 2015 Conrad Lara
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

function namechange()

    local count = 0
    while true
    do
        if not nixio.fs.stat("/tmp/namechange") and count < 12 then
            count = count + 1
            wait_for_ticks(5)
        else
            os.remove("/tmp/namechange")
            do_namechange()
            count = 0
        end
    end

end

function do_namechange()
    -- Do nothing if olsrd is not running
    if capture("pidof olsrd") == "" then
        return
    end

    local uptime = nixio.sysinfo().uptime

    local hosts = {}
    local history = {}

    -- Load the hosts file
    for line in io.lines("/var/run/hosts_olsr")
    do
        local v = line:splitWhiteSpace()
        local ip = v[1]
        local name = v[2]
        local originator = v[4]
        local mid = v[5]
        if ip and string.match(ip, "^%d") and originator and originator ~= "myself" and (ip == originator or mid == "(mid") then
            if hosts[ip] then
                hosts[ip] = hosts[ip] .. "/" .. name
            else
                hosts[ip] = name
            end
        end
    end

    -- Find the current neighbors
    local links = fetch_json("http://127.0.0.1:9090/links")
    if #links.links == 0 then
        return
    end
    for i, link in ipairs(links.links)
    do
        history[link.remoteIP] = { age = uptime, name = hosts[link.remoteIP] or "" }
    end

    -- load the strip the current history
    if nixio.fs.stat("/tmp/node.history") then
        for line in io.lines("/tmp/node.history")
        do
            local v = line:splitWhiteSpace()
            local ip = v[1]
            local age = 0
            if v[2] then
                age = math.floor(v[2])
            end
            local name = v[3]
            if age and not history[ip] and uptime - age < 86400 then
                history[ip] = { age = age, name = name or "" }
            end
        end
    end

    -- write the new history
    local f = io.open("/tmp/node.history", "w")
    if f then
        for k,v in pairs(history)
        do
            f:write(string.format("%s %d %s\n", k, v.age, v.name))
        end
        f:close()
    end

end

return namechange
