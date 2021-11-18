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

require("mgr.utils")
require("nixio")
require("aredn.utils")
local aredn_info = require('aredn.info')
local hw = require("aredn.hardware")

-- suffix to add to various file and directories while debugging this
-- to avoid blowing away the real config
local suffix = ".alt" 

-- helpers start

function is_null(v)
    if not v or v == "" or v == 0 then
        return true
    else
        return false
    end
end

function decimal_to_ip(val)
    return nixio.bit.band(val / 16777216, 255) .. "." .. nixio.bit.band(val / 65536, 255) .. "." .. nixio.bit.band(val / 256, 255) .. "." .. nixio.bit.band(val, 255)
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
    if nixio.bit.band(ip1, mask) == nixio.bit.band(ip2, mask) then
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
    if tonumber(a) > 255 or tonumber(b) > 255 or tonumber(c) > 255 or tonumber(d) > 255 then
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
    if a == "255" then
        if b == "255" then
            if c == "255" then
                a = d
            elseif d ~= "0" then
                return false
            else
                a = c
            end
        elseif not (c == "0" and d == "0") then
            return false
        else
            a = b
        end
    elseif not (b == "0" and c == "0" and d == "0") then
        return false
    end
    if a == "128" or a == "192" or a == "224" or a == "240" or a == "248" or a == "252" or a == "254" or a == "255" then
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
    if nixio.bit.band(ip, notmask) == 0 or nixio.bit.band(ip, notmask) == notmask then
        return false
    end
    return true
end

-- helpers end

-- validate args
local auto = false
local do_basic = true
local config = nil
for i, a in ipairs(arg)
do
    if a == "-a" then
        auto = true
    elseif a == "-p" then
        do_basic = false
    elseif a[1] == '-' then
        break
    else
        config = a
        break
    end
end
if not config then
    print "usage: node-setup [-a] [-p] <configname>"
    print "-a: automatic mode - don't ask any questions"
    print "-p: only process port forwarding and dhcp settings"
    return -1
end

if not (config == "mesh" and nixio.fs.access("/etc/config.mesh/_setup", "r")) then
    print (string.format("'%s' is not a valid configuration", config))
    return -1
end

local lanintf = hw.get_iface_name("lan")
local node = aredn_info.get_nvram("node")
local tactical = aredn_info.get_nvram("tactical")
local mac2 = mac_to_ip(hw.get_interface_mac(hw.get_iface_name("wifi")), 0)
local dtdmac = mac_to_ip(hw.get_interface_mac(lanintf), 0) -- *not* based of dtdlink

local deleteme = {}
local cfg = {
    lan_intf = lanintf,
    wan_intf = "dummy",
    dtdlink_intf = hw.get_iface_name('dtdlink')
}

if not auto then
    -- Is this used now?
    print "Non-auto mode no longer supported."
    return -1
end

-- load the verify the selected configuration

for line in io.lines("/etc/config.mesh/_setup")
do
    if not (line:match("^%s#") or line:match("^%s$")) then
        line = line:gsub("<NODE>", node):gsub("<MAC2>", mac2):gsub("<DTDMAC>", dtdmac)
        local k, v = line:match("^([^%s]*)%s*=%s*(.*)%s*$")
        cfg[k] = v
    end
end

-- debug
-- for k, v in pairs(cfg)
-- do
--    print ("'" .. k .. "'", " -> ", "'" .. v .. "'")
-- end

if cfg.wifi_enable == "1" then
    cfg.wifi_intf = hw.get_iface_name("wifi"):match("wlan(.*)")
else
    cfg.wifi_intf = lanintf:match("([%w]*)") .. ".3975"
end

-- delete some config lines if necessary

if cfg.wan_proto == "dhcp" then
    deleteme.wan_ip = true
    deleteme.wan_gw = true
    deleteme.wan_mask = true
end
if cfg.dmz_mode == "1" or cfg.wan_proto ~= "disabled" then
    deleteme.lan_gw = true
end

-- lan_dhcp sense is inverted in the dhcp config file
-- and it is a checkbox so it may not be defined - this fixes that
if cfg.lan_dhcp == "1" then
    cfg.lan_dhcp = 0
else
    cfg.lan_dhcp = 1
end

-- verify that we have all the variables we need
for file in nixio.fs.glob("/etc/config.mesh/*")
do
    for line in io.lines(file)
    do
        if line:match("^[^#]") then
            for parm in line:gmatch("<([^%s]*)>")
            do
                if parm:upper() == parm then
                    -- nvram variable
                    if aredn_info.get_nvram(parm:lower()) == "" then
                        print ("nv parameter '" .. parm .. "' in file '" .. file .. "' does not exist")
                        return -1
                    end
                else
                    if not cfg[parm] and not deleteme[parm] then
                        print ("parameter '" .. parm .. "' in file '" .. file .. "' does not exist")
                        return -1
                    end
                end
            end
        end
    end
end

-- sensible dmz_mode default
if is_null(cfg.dmz_mode) then
    cfg.dmz_mode = 0
end

-- switch to dmz values if needed
if not is_null(cfg.dmz_mode) then
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
local servfile = "/etc/config.mesh/_setup.services"
if cfg.dmz_mode == 0 then
    portfile = portfile .. ".nat"
    dhcpfile = dhcpfile .. ".nat"
    aliasfile = aliasfile .. ".nat"
    servfile = servfile .. ".nat"
else
    portfile = portfile .. ".dmz"
    dhcpfile = dhcpfile .. ".dmz"
    aliasfile = aliasfile .. ".dmz"
    servfile = servfile .. ".dmz"
end

-- check for old aliases file, copy it to .dmz and create symlink
-- just in case anyone is already using the fule for some script or something
local astat = nixio.fs.stat("/etc/config.mesh/aliases", "type")
if not (astat and astat == "lnk") then
    if astat then
        filecopy("/etc/config.mesh/aliases", "/etc/config.mesh/aliases.dmz")
        os.remove("/etc/config.mesh/aliases")
    else
        io.open("/etc/config.mesh/aliases.dmz", "w"):close()
    end
    nixio.fs.symlink("aliases.dmz", "/etc/config.mesh/aliases")
end

-- basic configuration
if do_basic then
    utils.remove_all("/tmp/new_config")
    nixio.fs.mkdir("/tmp/new_config")

    for file in nixio.fs.glob("/etc/config.mesh/*")
    do
        local bfile = nixio.fs.basename(file)
        if not (bfile:match("^_setup") or bfile:match("^firewall.user") or bfile:match("^olsrd")) then
            local f = io.open("/tmp/new_config/" .. bfile, "w")
            if f then
                for line in io.lines(file)
                do
                    local out = true
                    local inc = line:match("^include%s+(.*)%s*")
                    if inc then
                        for iline in io.lines(inc)
                        do
                            f:write(iline .. "\n")
                        end
                        out = false
                    elseif line:match("^[^#]") then
                        for parm in line:gmatch("<([^%s]*)>")
                        do
                            if deleteme[parm] then
                                out = false
                            elseif parm == "NODE" then
                                line = line:gsub("<NODE>", node)
                            elseif parm == "MAC2" then
                                line = line:gsub("<MAC2>", mac2)
                            elseif parm == "DTDMAC" then
                                line = line:gsub("<DTDMAC>", dtdmac)
                            else
                                line = line:gsub("<" .. parm .. ">", cfg[parm])
                            end
                        end
                    end
                    if out then
                        f:write(line .. "\n")
                    end
                end
                f:close()
            end
        end
    end

    -- make it official
    for file in nixio.fs.glob("/etc/config/*" .. suffix)
    do
        nixio.fs.remove(file)
    end
    for file in nixio.fs.glob("/tmp/new_config/*")
    do
        filecopy(file, "/etc/config/" .. nixio.fs.basename(file) .. suffix)
        nixio.fs.remove(file)
    end
    nixio.fs.rmdir("/etc/new_config")
    filecopy("/etc/config.mesh/firewall.user", "/etc/firewall.user" .. suffix)

    aredn_info.set_nvram("config", "mesh")
    aredn_info.set_nvram("node", node)
    aredn_info.set_nvram("tactical", tactical)
end

-- generate the system files

local h = io.open("/etc/hosts" .. suffix, "w")
local e = io.open("/etc/ethers" .. suffix, "w")
if h and e then
    h:write("# automatically generated file - do not edit\n")
    h:write("# use /etc/hosts.user for custom entries\n")
    h:write("127.0.0.1\tlocalhost\n")
    if not is_null(cfg.wifi_ip) then
        h:write(cfg.lan_ip .. "\tlocalnode\n")
        h:write(cfg.wifi_ip .. "\t" .. node .. " " .. tactical .. "\n")
    else
        h:write(cfg.lan_ip .. "\tlocalnode " .. node .. " " .. tactical .. "\n")
    end
    if not is_null(cfg.dtdlink_ip) then
        h:write(cfg.dtdlink_ip .. "\tdtdlink." .. node .. ".local.mesh dtdlink." .. node .."\n")
    end
    if is_null(cfg.dmz_mode) then
        h:write(decimal_to_ip(ip_to_decimal(cfg.lan_ip) + 1) .. "\tlocalap\n")
    end

    e:write("# automatically generated file - do not edit\n")
    e:write("# use /etc/ethers.user for custom entries\n")

    local netaddr = nixio.bit.band(ip_to_decimal(cfg.lan_ip), ip_to_decimal(cfg.lan_mask))

    for line in io.lines(dhcpfile)
    do
        if not (line:match("^%s#") or line:match("^%s$")) then
            local mac, ip, host, noprop = line:match("(.*)%s+(.*)%s+(.*)%s+(.*)")
            ip = decimal_to_ip(netaddr + ip)
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

    if nixio.fs.access("/etc/hosts.user", "r") then
        for line in io.lines("/etc/hosts.user")
        do
            h:write(line .. "\n")
        end
    end
    if nixio.fs.access("/etc/ethers.user", "r") then
        for line in io.lines("/etc/ethers.user")
        do
            e:write(line .. "\n")
        end
    end
    
    h:close()
    e:close()
end

if not do_basic then
    filecopy("/etc/config.mesh/firewall", "/etc/config/firewall" .. suffix)
    filecopy("/etc/config.mesh/firewall.user", "/etc/firewall.user" .. suffix)
end

-- for all the uci changes
local c = uci.cursor()

-- append to firewall
local fw = io.open("/etc/config/firewall" .. suffix, "a")
if fw then
    if not is_null(cfg.dmz_mode) then
        fw:write("\nconfig forwarding\n        option src    wifi\n        option dest   lan\n")
        fw:write("\nconfig forwarding\n        option src    dtdlink\n        option dest   lan\n")
        c:set("firewall", "@zone[2]", "masq", "0")
        c:commit("firewall")
    else
        fw:write("\nconfig 'include'\n        option 'path' '/etc/firewall.natmode'\n        option 'reload' '1'\n")
    end

    if not is_null(cfg.olsrd_gw) then
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
                    local match = "option src_dport " .. oport .. "\n"
                    if type == "tcp" then
                        match = match .. "option proto tcp\n"
                    elseif type == "udp" then
                        match = match .. "option proto udp\n"
                    end
                    -- uci the host and then
                    -- set the inside port unless the rule uses an outside port range
                    host = "option dest_ip    " .. host .. "\n"
                    if oport:match("-") then
                        host = host .. "        option dest_port " .. iport .. "\n"
                    end
                    if not is_null(cfg.dmz_mode) and intf == "both" then
                        intf = "wan"
                    end
                    if intf == "both" then
                        fw:write("\nconfig redirect\n        option src  wifi\n        " .. match .. "        option src_dip " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("\nconfig redirect\n        option src dtdlink\n        " .. match .. "        option src_dip " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("config redirect\n        option src wan\n        " .. match .. "        " .. host .. "\n")
                    elseif intf == "wifi" and is_null(cfg.dmz_mode) then
                        fw:write("\nconfig redirect\n        option src dtdlink\n        " .. match .. "        option src_dip " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("\nconfig redirect\n        option src wifi\n        " .. match .. "        option src_dip " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                    elseif intf == "wan" then
                        fw:write("\nconfig redirect\n        option src dtdlink\n        " .. match .. "        option src_dip " .. cfg.wifi_ip .. "\n        " .. host .. "\n")
                        fw:write("config redirect\n        option src wan\n        " .. match .. "        " .. host .. "\n")
                    end
                end
            end
        end
    end

    fw:close();
end

-- generate the services file

local sf = io.open("/etc/config/services" .. suffix, "w")
if sf then
    for line in io.lines(servfile)
    do
        if not (line:match("^%s#") or line:match("^%s$")) then
            local name, link, proto, host, port, sffx = line:match("(.*)|(.*)|(.*)|(.*)|(.*)|(.*)")
            if name and name ~= "" and host ~= "" then
                if proto == "" then
                    proto = "http"
                end
                if link == "" then
                    port = "0"
                end
                sf:write(string.format("%s://%s:%s/%s|tcp|%s\n", proto, host, port, suffix, name))
            end
        end
    end
    sf:close()
end

local sf = io.open("/etc/local/services" .. suffix, "w")
if sf then
    sf:write("#!/bin/sh\n")
    if cfg.wifi_proto ~= "disabled" then
        if is_null(cfg.wifi_txpower) or tonumber(cfg.wifi_txpower) > hw.wifi_maxpower(cfg.wifi_channel) then
            cfg.wifi_txpower = hw.wifi_maxpower(cfg.wifi_channel)
        elseif tonumber(cfg.wifi_txpower) < 1 then
            cgs.wifi_txpower = 1
        end
        if cfg.wifi_enable == 1 then
            sf:write("/usr/sbin/iw dev " .. cfg.wifi_intf .. " set txpower fixed " .. cfg.wifi_txpower .. "00\n")
        end
        if not is_null(cfg.aprs_lat) and not is_null(cfg.aprs_lon) then
            c:set("aredn", "@location[0]", "lat", cfg.aprs_lat)
            c:set("aredn", "@location[0]", "lon", cfg.aprs_lon)
            c:commit("aredn")
        end
    end
    sf:close()
    nixio.fs.chmod("/etc/local/services" .. suffix, "777")
end

-- generate olsrd.conf

if nixio.fs.access("/etc/config.mesh/olsrd", "r") then
    local of = io.open("/etc/config/olsrd" .. suffix, "w")
    if of then
        for line in io.lines("/etc/config.mesh/olsrd")
        do
            if line:match("<olsrd_bridge>") then
                if is_null(cfg.olsrd_bridge) then
                    line = line:gsub("<olsrd_bridge>", '"wifi" "lan"')
                else
                    line = line:gsub("<olsrd_bridge>", '"lan"')
                end
            elseif line:match("^[^#]") then
                for parm in line:gmatch("<([^%s]*)>")
                do
                    line = line:gsub("<" .. parm .. ">", cfg[parm])
                end
            end
            of:write(line .. "\n")
        end

        if not is_null(cfg.dmz_mode) then
            local a, b, c, d = cfg.dmz_lan_ip:match("(.*)%.(.*)%.(.*)%.(.*)")
            of:write(string.format("\nconfig Hna4\n\toption netaddr %s.%s.%s.%d\n\toption netmask 255.255.255.%d\n\n", a, b, c, d - 1, nixio.bit.band(255 * 2 ^ cfg.dmz_mode, 255)))
        end
    
        if not is_null(cfg.olsrd_gw) then
            of:write("config LoadPlugin\n\toption library 'olsrd_dyn_gw.so.0.5'\n\toption Interval '60'\n\tlist Ping '8.8.8.8'\n\tlist Ping '8.8.4.4'\n\n\n")
        end

        of:close()
    end

end

-- indicate whether lan is running in dmz mode

c:set("aredn", "dmz", "mode", cfg.dmz_mode)
c:commit("aredn")

-- setup node lan dhcp

if not is_null(cfg.lan_dhcp_noroute) then
    c:set("dhcp", "@dhcp[0]", "dhcp_option", {
        "121,10.0.0.0/8," .. cfg.lan_ip .. ",172.16.0.0/12," .. cfg.lan_ip,
        "249,10.0.0.0/8," .. cfg.lan_ip .. ",172.16.0.0/12," .. cfg.lan_ip,
        "3"
    })
else
    c:set("dhcp", "@dhcp[0]", "dhcp_option", {
        "121,10.0.0.0/8" .. cfg.lan_ip .. ",172.16.0.0/12," .. cfg.lan_ip .. ",0.0.0.0/0," .. cfg/lan_ip,
        "249,10.0.0.0/8" .. cfg.lan_ip .. ",172.16.0.0/12," .. cfg.lan_ip .. ",0.0.0.0/0," .. cfg/lan_ip
    })
end
c:commit("dhcp")

-- generate the wireless config file
-- TODO - move that into lua
shell_no_capture("/usr/local/bin/wifi-setup")

if not auto then
    print "configuration complete.";
    print "you should now reboot the router.";
end

return 0
