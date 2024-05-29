--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

function namechange()

    local count = 0
    while true
    do
        local exists = nixio.fs.stat("/tmp/namechange")
        if not exists and count < 12 then
            count = count + 1
            wait_for_ticks(5)
        else
            if exists then
                os.remove("/tmp/namechange")
            end
            local reload = do_namechange()
            if not exists or reload then
                dns_update(reload)
            end
            count = 0
        end
    end

end

function do_namechange()
    -- Do nothing if olsrd is not running
    if capture("pidof olsrd") == "" then
        return false
    end

    local uptime = nixio.sysinfo().uptime

    local hosts = {}
    local history = {}
    local subdomains = ""

    -- Load the hosts file
    for line in aredn.olsr.getHostAsLines()
    do
        local v = line:splitWhiteSpace()
        local ip = v[1]
        local name = v[2]
        local originator = v[4]
        local mid = v[5]
        if ip then
            if ip:match("^%d") and originator and originator ~= "myself" and (ip == originator or mid == "(mid") then
                if hosts[ip] then
                    hosts[ip] = hosts[ip] .. "/" .. name
                else
                    hosts[ip] = name
                end
            end
            if name and name:sub(1,2) == "*." then
                if not name:match("%.local%.mesh$") then
                    name = name .. ".local.mesh"
                end
                subdomains = subdomains .. "address=/." .. name:sub(3) .. "/" ..  ip .. "\n"
            end
        end
    end

    -- Find the current neighbors
    local raw = io.popen("/usr/bin/wget -O - http://127.0.0.1:9090/links 2> /dev/null")
    local links = luci.jsonc.parse(raw:read("*a"))
    raw:close()
    if not (links and links.links and #links.links > 0) then
        return false
    end
    for i, link in ipairs(links.links)
    do
        history[link.remoteIP] = { age = uptime, name = hosts[link.remoteIP] or "" }
    end

    -- load the strip the current history
    if nixio.fs.stat("/tmp/node.history") then
        for line in io.lines("/tmp/node.history")
        do
            local ip, age, name = line:match("^(%S*) (%d+) +(.*)$")
            if ip and age and not history[ip] and uptime - tonumber(age) < 86400 then
                history[ip] = { age = age, name = name }
            end
        end
    end

    -- write the new history
    local f = io.open("/tmp/node.history", "w")
    if f then
        for k,v in pairs(history)
        do
            f:write(k .. " " .. v.age .. " " .. v.name .. "\n")
        end
        f:close()
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
            return true
        end
    end

    return false
end

function dns_update(reload)
    if reload then
        os.execute("/etc/init.d/dnsmasq restart")
    elseif nixio.fs.stat("/var/run/dnsmasq/dnsmasq.pid") then
        local pid = tonumber(read_all("/var/run/dnsmasq/dnsmasq.pid"))
        if pid then
            nixio.kill(pid, 1)
        end
    end
end

return namechange
