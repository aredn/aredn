--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2024 Tim Wilkinson
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

local M = {}

function M.dns_monitor()
    while true
    do
        local changed = M.find_subdomains()
        if changed then
            os.execute("/etc/init.d/dnsmasq restart")
        end
        wait_for_ticks(300)
    end
end

function M.find_subdomains()
    -- Do nothing if olsrd is not running
    if capture("pidof olsrd") == "" then
        return false
    end

    local reload = false

    -- Load the hosts file
    local subdomains = ""
    for line in aredn.olsr.getHostAsLines()
    do
        local v = line:splitWhiteSpace()
        local ip = v[1]
        local name = v[2]
        if ip and name and name:sub(1,2) == "*." then
            if not name:match("%.local%.mesh$") then
                name = name .. ".local.mesh"
            end
            subdomains = subdomains .. "address=/." .. name:sub(3) .. "/" ..  ip .. "\n"
        end
    end

    -- Write out the subdomains
    local osubdomains = ""
    f = io.open("/tmp/dnsmasq.d/subdomains.conf")
    if f then
        osubdomains = f:read("*a")
        f:close()
    end
    if osubdomains ~= subdomains then
        local w = io.open("/tmp/dnsmasq.d/subdomains.conf", "w+")
        if w then
            w:write(subdomains)
            w:close()
            reload = true
        end
    end

    return reload
end

return M.dns_monitor
