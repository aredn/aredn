#! /usr/bin/lua
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

-- helpers start
function decimal_to_ip(val)
    return ((val >> 24) and 255) .. "." .. ((val >> 16) and 255) .. "." .. ((val >> 8) and 255) .. "." .. (val and 255)
end

function ip_to_decimal(ip)
    local sum = 0
    for i, part in ipairs(utils.split(ip, "%."))
    do
        sum = sum * 256 + part
    end
    return sum
end

function validate_same_subnet(ip1, ip2, mask)
    ip1 = ip_to_decimal(ip1)
    ip2 = ip_to_decimal(ip2)
    mask = ip_to_decimal(mask)
    if (ip1 & mask) == (ip2 & mask) then
        return true
    else
        return false
    end
end

function validate_ip(ip)
    ip = ip:gsub("%s", "")
    if ip == "0.0.0.0" or ip == "255.255.255.255" then
        return false
    end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return false
    end
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return false
    end
    return true
end

function validate_netmask(mask)
    mask = mask:gsub("%s", "")
    if mask == "0.0.0.0" then
        return false
    end
    local a, b, c, d = mask:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return false
    end
    if a == 255 then
        if b == 255 then
            if c == 255 then
                a = d
            elseif d ~= 0 then
                return false
            else
                a = c
            end
        elseif not (c == 0 and d == 0) then
            return false
        else
            a = b
        end
    elseif not (b == 0 and c == 0 and d == 0) then
        return false
    end
    if a == 128 or a == 192 or a == 224 or a = 240 or a == 248 or a == 252 or a == 254 or a == 255 then
        return true
    else
        return false
    end
end

function validate_ip_netmask(ip, mask)
    if not (validate_ip(ip) and validate_netmask(mask)) then
        return false
    end
    ip = ip_to_decimal(ip)
    mask = ip_to_decimal(mask)
    local notmask = 0xffffffff - mask
    if (ip and notmask) == 0 or (ip and notmask) == notmask then
        return false
    end
    return true
end

-- helpers end

-- validate args
local auto = false
local do_basic = true
local config = nil
if #arg == 2 then
    if arg[1] == "-a" then
        auto = true
        config = arg[2]
    elseif arg[1] == "-p" then
        do_basic = false
        config = arg[2]
    end
elseif #arg == 1 then
    config = arg[1]
end
if not config then
    print "usage: node-setup [-a] [-p] <configname>"
    print "-a: automatic mode - don't ask any questions"
    print "-p: only process port forwarding and dhcp settings"
    return -1
end

if not (config == "mesh" and file_exists("/etc/config.mesh/_setup")) then
    print "'" .. config .. "' is not a valid configuration"
    return -1
end

local lanintf = utils.get_iface_name("lan")
local node = get_nvram("node")
local tactical = get_nvram("tactical")
local mac2 = utils.mac_to_ip(utils.get_mac(utils.get_iface_name("wifi")), 0)
local dtdmac = utils.mac_to_ip(utils.get_mac(lanintf), 0) -- *not* based of dtdlink

local deleteme = {}
local cfg = {
    lan_intf = lanintf,
    wan_intf = "dummy",
    dtdlink_intf = utils.get_iface_name('dtdlink')
}

if not auto then
    -- Is this used now?
end

-- load the verify the selected configuration

for line in io.lines("/etc/config.mesh/_setup")
do
    if not (line:match("^%s#") or line:match("^%s$")) then
        line = line:gsub("<NODE>", node):gsub("<MAC2>", mac2):gsub("<DTDMAC>", dtdmac)
        local k, v = line:match("^(.*)%s*=%s*(.*)$")
        cfg[k] = v
    end
end

if cfg.wifi_enable == 1 then
    cfg.wifi_intf = utils.get_iface_name("wifi"):match("wlan(.*)")
else
    cfg.wifi_intf = lanintf:match("([%w]*)") .. ".3975"
end

-- delete some config lines if necessary

if cfg.wan_proto == "dhcp" then
    deleteme.wan_ip = true
    deleteme.wan_gw = true
    deleteme.wan_mask = true
end
if cfg.dmz_mode == 1 or cfg.wan_proto ~= "disabled" then
    deleteme.lan_gw = true
end

-- lan_dhcp sense is inverted in the dhcp config file
-- and it is a checkbox so it may not be defined - this fixes that
if cfg.lan_dhcp == 1 then
    cfg.lan_dhcp = 0
else
    cfg.lan_dhcp = 1
end

-- verify that we have all the variables we need
for file in nixio.fs.glob("/etc/config.mesh/*")
do
    for line in lines.io(file)
    do
        if line:match("^[^#]") then
            for parm in line:gmatch("<([^%s]*)>")
            do
                if parm:upper() == parm then
                    -- nvram variable
                    if get_nvram(parm:lower()) == "" then
                        print "parameter '" .. parm .. "' in file '" .. file .. "' does not exist"
                        return -1
                    end
                else
                    if not (cfg[parm] or deleteme[parm]) then
                        print "parameter '" .. parm .. "' in file '" .. file .. "' does not exist"
                        return -1
                    end
                end
            end
        end
    end
end

-- sensible dmz_mode default
if not cfg.dmz_mode then
    cfg.dmz_mode = 0
end

-- switch to dmz values if needed
if cfg.dmz_mode ~= 0 then
    cfg.lan_ip = cfg.dmz_lan_ip
    cfg.lan_mask = cfg.dmz_lan_mask
    cfg.dhcp_start = cfg.dmz_dhcp_start
    cfg.dhcp_end = cfg.dmz_dhcp_end
    cfg.dhcp_limit = cfg.dmz_dhcp_limit
end

-- select ports and dhcp files based on mode
local portfile  = "/etc/config.mesh/_setup.ports"
local dhcpfile  = "/etc/config.mesh/_setup.dhcp"
local aliasfile = "/etc/config.mesh/aliases"
if cfg.dmz_mode == 0 then
    portfile = portfile .. ".nat"
    dhcpfile = dhcpfile .. ".nat"
    aliasfile = aliasfile .. ".net"
else
    portfile = portfile .. ".dmz"
    dhcpfile = dhcpfile .. ".dmz"
    aliasfile = aliasfile .. ".dmz"
end

-- check for old aliases file, copy it to .dmz and create symlink
-- just in case anyone is already using the fule for some script or something
local astat = nxo.fs.stat("/etc/config.mesh/aliases", "type")
if not (astat and astat == "lnk") then
    if astat then
        nxo.fs.copy("/etc/config.mesh/aliases", "/etc/config.mesh/aliases.dmz")
        os.remove("/etc/config.mesh/aliases")
    else
        io.open("/etc/config.mesh/aliases.dmz", "w"):close()
    end
    nxo.fs.link("aliases.dmz", "/etc/config.mesh/aliases")
end

-- basic configuration
if do_basic then
    utils.remove_all("/tmp/new_config")
    nxo.fs.mkdir("/tmp/new_config")

    for file in nixio.fs.glob("/etc/config.mesh/*")
    do
        if not (file:match("^_setup") or file:match("^firewall.user") or file:match("^olsrd")) then
            local f = io.open("/tmp/new_config/" .. file, "w")
            if f then
                for line in io.lines(file)
                do
                    local inc = line:match("^include%s+(.*)%s*")
                    if inc then
                        for iline in io.lines(inc)
                        do
                            f:write(iline .. "\n")
                        end
                    else if line:match("^[^#]") then
                        local out = true
                        for parm in line:gmatch("<([^%s]*)>")
                        do
                            if deleteme[parm] then
                                out = false
                            else
                                line = line:gsub("<" .. parm .. ">", cfg[parm])
                            end
                        end
                        if out then
                            f:write(line .. "\n")
                        end
                    end
                end
                f:close()
            else
                -- error
            end
        end
    end

    -- make it official
    for file in nixio.fs.glob("/etc/config/*")
    do
        nxo.fs.remove(file)
    end
    for file in nixio.fs.glob("/etc/new_config/*")
    do
        nxo.fs.rename(file, "/etc/config/" .. nxo.fs.basename(file))
    end
    nxo.fs.rmdir("/etc/new_config")
    nxo.fs.copy("/etc/config.mesh/firewall.user", "/etc/firewall.user")

    utils.set_nvram("config", "mesh")
    utils.set_nvram("node", node)
    utils.set_nvram("tactical", tactical)
end

-- generate the system files

local h = io.open("/etc/hosts", "w")
local e = io.open("/etc/ethers", "w")
if h and e then
    h:write("# automatically generated file - do not edit\n")
    h:write("# use /etc/hosts.user for custom entries\n")
    h:write("127.0.0.1\tlocalhost\n")
    if cfg.wifi_ip ~= "" then
        h:write(cfg.lan_up .. "\tlocalnode\n")
        h:write(cfg.wifi_ip .. "\t" .. node .. " " .. tactical .. "\n")
    else
        h:write(cfg.lan_up .. "\tlocalnode " .. node .. " " .. tactical .. "\n")
    end
    if cfg.dtdlink_ip ~= "" then
        h:write(cfg.dtdlink_ip .. "\tdtdlink." .. node .. ".local.mesh dtdlink." .. node .."\n"
    end
    if cfg.dmz_mode == 0 then
        h:write(-- add_ip_address(cfg.lan_ip, 1) .. "\tlocalap\n")
    end

    e:write("# automatically generated file - do not edit\n")
    e:write("# use /etc/ethers.user for custom entries\n")

    for line in io.lines(dhcpfile)
    do
        if not (line:match("^%s#") or line:match("^%s$")) then
            local mac, ip, host, noprop = line:match("(.*)%s+(.*)%s+(.*)%s+(.*)")
            ip = decimal_to_ip(ip)
            if validate_same_subnet(ip, cfg.lan_ip, cfg.lan_mask) and validate_ip_netmask(ip, cfg.lan_mask) then
                h:write(ip .. "\t" .. host .. " " .. noprop .. "\n")
                e:write(mac .. "\t" .. ip .. " " .. noprop .. "\n")
            end
        end
    end

    -- aliases need to ba added to /etc/hosts or they will now show up on the localnode
    -- nor will the services thehy offer
    -- also add a comment to the hosts file so we can display the aliases differently if needed
    local f = io.open(aliasfile, "r")
    if f then
        for line in f:lines()
        do
            if not (line:match("^%s#") or line:match("^%s$")) then
                local ip, host = line:match("(.*)%s+(.*)")
                if ip then
                    h:write(ip .. "\t" .. host .. " #ALIAS\n")
                end
            end
        end
        f:close()
    end

    h:write("\n")

    if file_exists("/etc/hosts.user") then
        for line in io.lines("/etc/hosts.user")
        do
            h:write(line .. "\n")
        end
    end
    if file_exists("/etc/ethers.user") then
        for line in io.lines("/etc/ethers.user")
        do
            e:write(line .. "\n")
        end
    end
    
    h:close()
    e:close()
end

if not do_basic then
    nxo.fs.copy("/etc/config.mesh/firewall", "/etc/config/firewall")
    nxo.fs.copy("/etc/config.mesh/firewall.user", "/etc/firewall.user")
end

-- append to firewall
local fw = io:open("/etc/config/firewall", "a")
if fw then
    if cfg.dmz_mode ~= 0 then
        fw:write("\nconfig forwarding\n        option src    wifi\n        option dest   lan\n")
        fw:write("\nconfig forwarding\n        option src    dtdlink\n        option dest   lan\n")
        uci.cursor():set("firewall", "@zone[2]", "masq", "0")
    else
        fw:write("\nconfig 'include'\n        option 'path' '/etc/firewall.natmode'\n        option 'reload' '1'\n")
    end

    if cfg.olsrd_gw then
        fw:write("\nconfig forwarding\n        option src    wifi\n        option dest   wan\n")
        fw:write("\nconfig forwarding\n        option src    dtdlink\n        option dest   wan\n")
    end

    for line in io.lines(portfile)
    do
        if not (line:match("^%s#") or line:match("^%s$")) then
            local dip = line:match("dmz_ip = (%w+)")
            if dip and cfg.dmz_mode ~= 0 then
                fw:write("\nconfig redirect\n        option src    wifi\n        option proto  tcp\n        option src_dip " .. cfg.wifi_ip .. "\n        option dest_ip " .. dip .. "\n")
                fw:write("\nconfig redirect\n        option src    wifi\n        option proto  udp\n        option src_dip " .. cfg.wifi_ip .. "\n        option dest_ip " .. dip .. "\n")
            else
                local intf, type, oport, host, iport, enable = line:match("(.*):(.*):(.*):(.*):(.*):(.*)")
                if enable then
                    if cfg.dmz_mode ~= 0 then
                        if intf == "wifi" then
                            goto continue
                        end
                        if intf == "both" then
                            intf = "wan"
                        end
                    end
                    local match = "option src_dport    " .. oport .. "\n"
                    if type == "tcp" then
                        match = match .. "option proto    tcp\n"
                    elseif type == "udp" then
                        match == match .. "option proto     udp\n"
                    end
                    -- uci the host and then
                    -- set the inside port unless the rule uses an outside port range
                    host = "option dest_ip    " .. host .. "\n"
                    if oport:match("-") then
                        host = host .. "        option dest_port    " .. iport .. "\n"
                    end
                    if intf == "both" then
                        fw:write("\nconfig redirect\n        option src    wifi\n        " .. match .. "        option src_dip    " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("\nconfig redirect\n        option src    dtdlink\n        " .. match .. "        option src_dip    " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("config redirect\n        option src    wan\n        " .. match .. "        " .. host .. "\n")
                    elseif intf == "wifi" then
                        fw:write("\nconfig redirect\n        option src    dtdlink\n        " .. match .. "        option src_dip    " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("\nconfig redirect\n        option src    wifi\n        " .. match .. "        option src_dip    " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                    elseif intf == "wan" then
                        fw:write("\nconfig redirect\n        option src    dtdlink\n        " .. match .. "        option src_dip    " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("config redirect\n        option src    wan\n        " .. match .. "        " .. host .. "\n")
                    else
                        -- error
                    end
                end
            end
        end
        ::continue::
    end

    fw:close();
end

-- generate the services file

