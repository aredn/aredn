#! /usr/bin/lua
--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021-2023 Tim Wilkinson
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

require("nixio")
require("aredn.utils")
require("aredn.hardware")
require('aredn.info')
require("uci")

-- Whether to validate hosts and services before publishing
local validation_timeout = 150 * 60 -- 2.5 hours (so must fail 3 times in a row)
local validation_state = "/tmp/service-validation-state"

--
-- Get all the known node names, host and services
--  with optional validation
--
local function get(validate)

    local names = {}
    local hosts = {}
    local services = {}

    -- canonical names for this node
    -- (they should up in reverse order, make the official name last)
    local name = aredn.info.get_nvram("tactical")
    if name ~= "" then
        names[#names + 1] = name
    end
    name = aredn.info.get_nvram("node")
    if name ~= "" then
        names[#names + 1] = name
    end

    local dmz_mode = uci.cursor("/etc/config.mesh"):get("setup", "globals", "dmz_mode")
    if dmz_mode ~= "0" then
        if nixio.fs.stat("/etc/config.mesh/aliases.dmz") then
            for line in io.lines("/etc/config.mesh/aliases.dmz")
            do
                local ip, host = line:match("(.*) (.*)")
                if host then
                    hosts[#hosts + 1] = { ip = ip, host = host }
                end
            end
        end
        if nixio.fs.stat("/etc/ethers") then
            local noprop_ip = {}
            if nixio.fs.stat("/etc/hosts") then
                for line in io.lines("/etc/hosts")
                do
                    local ip = line:match("^(%S+)%s.*#NOPROP$")
                    if ip then
                        noprop_ip[ip] = true
                    end
                end
            end
            for line in io.lines("/etc/ethers")
            do
                local ip = line:match("[0-9a-fA-F:]+%s+([%d%.]+)")
                if ip and not noprop_ip[ip] then
                    local host = nixio.getnameinfo(ip)
                    if host then
                        hosts[#hosts + 1] = { ip = ip, host = host }
                    end
                end
            end
        end
    end

    -- add a name for the dtdlink and xlink interfaces
    if name then
        if nixio.fs.stat("/etc/hosts") then
            for line in io.lines("/etc/hosts")
            do
                local dtdip = line:match("^(%d+%.%d+%.%d+%.%d+)%s+dtdlink%.")
                if dtdip then
                    hosts[#hosts + 1] = { ip = dtdip, host = "dtdlink." .. name .. ".local.mesh" }
                end
                local lanip = line:match("^(%d+%.%d+%.%d+%.%d+)%s+localnode$")
                if lanip then
                    hosts[#hosts + 1] = { ip = lanip, host = "lan." .. name .. ".local.mesh" }
                end
            end
        end
        if nixio.fs.stat("/etc/config.mesh/xlink") then
            local count = 0
            uci.cursor("/etc/config.mesh"):foreach("xlink", "interface",
                function(section)
                    if section.ipaddr then
                        hosts[#hosts + 1] = { ip = section.ipaddr, host = "xlink" .. count .. "." .. name .. ".local.mesh" }
                        count = count + 1
                    end
                end
            )
        end
    end

    -- load the services
    local svcs = uci.cursor("/etc/config.mesh"):get_all("setup", "services", "service") or {}
    for _, svc in ipairs(svcs)
    do
        local name, link, proto, host, port, sffx = svc:match("(.*)|(.*)|(.*)|(.*)|(.*)|(.*)")
        if name and name ~= "" and host ~= "" then
            if proto == "" then
                proto = "http"
            end
            if link == "0" then
                port = "0"
            end
            services[#services + 1] = string.format("%s://%s:%s/%s|tcp|%s", proto, host, port, sffx, name)
        end
    end
    --

    -- validation
    if validate then
        -- Load previous state
        local vstate = {}
        if nixio.fs.stat(validation_state) then
            for line in io.lines(validation_state)
            do
                local last, key = line:match("^(%d+) (.*)$")
                if last then
                    vstate[key] = tonumber(last)
                end
            end
        end
        local now = os.time()
        local last = now + validation_timeout
        local laniface = aredn.hardware.get_iface_name("lan")
        -- Add in local names so services checks pass
        for _, name in ipairs(names)
        do
            vstate[name:lower()] = last
        end
        -- Check we can reach all the IP addresses
        for _, host in ipairs(hosts)
        do
            if os.execute("/bin/ping -q -c 1 -W 1 " .. host.ip .. " > /dev/null 2>&1") == 0 then
                vstate[host.host:lower()] = last
                services[#services + 1] = string.format("pseudo://%s:80/|tcp|pseudo", host.host)
                services[#services + 1] = string.format("pseudo://%s:443/|tcp|pseudo", host.host)
            elseif os.execute("/usr/sbin/arping -q -f -c 1 -w 1 -I " .. laniface .. " " .. host.ip .. " > /dev/null 2>&1") == 0 then
                vstate[host.host:lower()] = last
                services[#services + 1] = string.format("pseudo://%s:80/|tcp|pseudo", host.host)
                services[#services + 1] = string.format("pseudo://%s:443/|tcp|pseudo", host.host)
            end
        end
        -- Load NAT
        local nat = nil
        if dmz_mode == "0" then
            local ports = uci.cursor("/etc/config.mesh"):get_all("setup", "ports", "port")
            if ports then
                nat = {}
                local lname = name:lower() .. ".local.mesh"
                for _, line in ipairs(ports)
                do
                    local _, type, sport, addr, dport, enable = line:match("^(.+):(.+):(.+):(.+):(%d+):(%d)$")
                    if enable == "1" then
                        local sp, ep = sport:match("^(%d+)%-(%d+)$")
                        if not sp then
                            sp = sport
                            ep = sport
                        end
                        sp = tonumber(sp)
                        ep = tonumber(ep)
                        dport = tonumber(dport)
                        for p = sp, ep
                        do
                            if type == "udp" or type == "both" then
                                nat[lname .. ":udp:" .. p] = { hostname = addr, port = dport + p - sp }
                            end
                            if type == "tcp" or type == "both" then
                                nat[lname .. ":tcp:" .. p] = { hostname = addr, port = dport + p - sp }
                            end
                        end
                    end
                end
            end
        end
        -- Check all the services have a valid host
        local havecurl = nixio.fs.stat("/usr/bin/curl") ~= nil
        for _, service in ipairs(services)
        do
            local proto, hostname, port, path = service:match("^(%w+)://([%w%-%.]+):(%d+)(.*)|...|[^|]+$")
            if proto then
                local vs = vstate[hostname:lower()]
                if not vs or vs > now or dmz_mode == "0" then
                    if port == "0" then
                        -- no port so not a link - we can only check the hostname so have to assume the service is good
                        vstate[service] = last
                    elseif havecurl and (proto == "http" or (proto == "pseudo" and port == "80")) then
                        -- http so looks like a link. http check it
                        if not hostname:match("%.local%.mesh$") then
                            hostname = hostname .. ".local.mesh"
                        end
                        -- nat translation
                        local m = nat and nat[hostname:lower() .. ":tcp:" .. port]
                        if m then
                            hostname = m.hostname
                            port = m.port
                        end
                        local cf = io.popen("/usr/bin/curl --max-time 10 --retry 0 --connect-timeout 2 --speed-time 5 --speed-limit 1000 --silent --output /dev/null --cookie-jar /tmp/service-test-cookies --location --write-out '%{http_code} %{url_effective}' " .. "http://" .. hostname .. ":" .. port .. path)
                        local status, effective_url = cf:read("*a"):match("^(%d+) (.*)")
                        cf:close()
                        os.remove("/tmp/service-test-cookies")
                        if status == "200" or status == "401" then
                            vstate[service] = last
                        elseif status == "301" or status == "302" or status == "303" or status == "307" or status == "308" then
                            -- Ended at a redirect rather than an actual page.
                            if effective_url:match("^https:") then
                                -- We cannot validate https: links so we just assume they're okay
                                vstate[service] = last
                            end
                        end
                    else
                        -- valid port, but we dont know the protocol (we cannot trust the one defined in the services file because the UI wont set
                        -- anything but 'tcp'). Check both tcp and udp and assume valid it either is okay
                        -- tcp
                        local s = nixio.socket("inet", "stream")
                        s:setopt("socket", "sndtimeo", 2)
                        local r
                        local m = nat and nat[hostname:lower() .. ":tcp:" .. port]
                        if m then
                            r = s:connect(m.hostname, tonumber(m.port))
                        else
                            r = s:connect(hostname, tonumber(port))
                        end
                        s:close()
                        if r == true then
                            -- tcp connection succeeded
                            vstate[service] = last
                        else
                            -- udp
                            s = nixio.socket("inet", "dgram")
                            s:setopt("socket", "rcvtimeo", 2)
                            local m = nat and nat[hostname:lower() .. ":udp:" .. port]
                            if m then
                                s:connect(m.hostname, tonumber(m.port))
                            else
                                s:connect(hostname, tonumber(port))
                            end
                            s:send("")
                            r = s:recv(0)
                            s:close()
                            if r ~= nil then
                                -- A nil response is an explicity rejection of the udp request. Otherwise we have
                                -- to assume the service is valid
                                vstate[service] = last
                            end
                        end
                    end
                end
            end
        end

        -- Generate new hosts and services as long as they're valid
        local old_hosts = hosts
        hosts = {}
        for _, host in ipairs(old_hosts)
        do
            local lname = host.host:lower()
            local vs = vstate[lname]
            if not vs then
                hosts[#hosts + 1] = host
                vstate[lname] = last
            elseif vs > now then
                hosts[#hosts + 1] = host
            end
        end
        local old_services = services
        services = {}
        for _, service in ipairs(old_services)
        do
            if not service:match("^pseudo:") then
                local vs = vstate[service]
                if not vs then
                    -- New services will be valid for a while, even if they're not there yet
                    services[#services + 1] = service
                    vstate[service] = last
                elseif vs > now then
                    services[#services + 1] = service
                end
            end
        end

        -- Store state for next time
        local f = io.open(validation_state, "w")
        if f then
            f:write(now .. "\n")
            for key, last in pairs(vstate)
            do
                f:write(last .. " " .. key .. "\n")
            end
            f:close()
        end
    end
    -- end validation

    return names, hosts, services
end

--
-- Reset validation
--
local function reset_validation()
    os.remove(validation_state)
end

if not aredn then
    aredn = {}
end
aredn.services = {
    get = get,
    reset_validation = reset_validation
}
return aredn.services
