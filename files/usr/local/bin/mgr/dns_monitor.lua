--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2024,2025 Tim Wilkinson
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
        local need_supernodes = false
        local c = uci.cursor()
        if c:get("aredn", "@supernode[0]", "enable") ~= "1" and c:get("aredn", "@supernode[0]", "support") ~= "0" then
            need_supernodes = true
        end
        local subdomains, supernodes = M.find_special_domains(need_supernodes)
        local changed1 = M.update_subdomains(subdomains)
        local changed2 = M.update_supernode(M.find_best_supernode(supernodes))
        if changed1 or changed2 then
            os.execute("/etc/init.d/dnsmasq restart")
        end
        wait_for_ticks(300)
    end
end

function M.find_special_domains(need_supernodes)
    local subdomains = ""
    local supernodes = {}
    for name in nixio.fs.dir("/var/run/arednlink/hosts")
	do
		for line in io.lines("/var/run/arednlink/hosts/" .. name)
		do
            local ip, subname = line:match("^([0-9%.]+)%s+%*%.(%S+)$")
            if ip then
                subdomains = subdomains .. "address=/." .. subname .. "/" ..  ip .. "\n"
            elseif need_supernodes then
                ip, subname = line:match("^([0-9%.]+)%s+supernode%.(%S+)$")
                if ip then
                    supernodes[#supernodes + 1] = { name = subname, ip = ip }
                end
            end
        end
    end
    return subdomains, supernodes
end

function M.update_subdomains(subdomains)
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

function M.update_supernode(supernode)
    local revdest = ""
    local dest = ""
    local dns = ""
    if supernode then
        dns = dns .. "#" .. supernode.name .. "\n"
        dest = supernode.ip
        revdest = "," .. dest
    end
    dns = dns .. "server=/local.mesh/" .. dest .. "\nrev-server=10.0.0.0/8" .. revdest .. "\nrev-server=172.31.0.0/16" .. revdest  .. "\nrev-server=172.30.0.0/16" .. revdest
    if nixio.fs.stat("/etc/44net.conf") then
        for line in io.lines("/etc/44net.conf")
        do
            dns = dns .. "\nrev-server=" .. line .. revdest
        end
    end
    dns = dns .. "\n"
    local odns = ""
    local f = io.open("/tmp/dnsmasq.d/supernode.conf")
    if f then
        odns = f:read("*a")
        f:close()
    end
    if odns ~= dns then
        f = io.open("/tmp/dnsmasq.d/supernode.conf", "w+")
        if f then
            f:write(dns)
            f:close()
            return true
        end
    end
    return false
end

function M.find_best_supernode(supernodes)
    if #supernodes == 0 then
        return nil
    elseif #supernodes == 1 then
        return supernodes[1]
    end
    local best = { metric = 99999999, supernode = nil }
    for _, supernode in ipairs(supernodes)
    do
        local metric = capture("/sbin/ip route show table 20 | grep " .. supernode.ip):match(" metric (%d+)")
        if metric then
            metric = tonumber(metric)
            if metric < best.metric then
                best.metric = metric
                best.supernode = supernode
            end
        end
    end
    return best.supernode
end

return M.dns_monitor
