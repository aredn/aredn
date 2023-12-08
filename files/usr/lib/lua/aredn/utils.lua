#!/usr/bin/lua
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2019 Darryl Quinn
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
	version.

--]]


local nxo = require("nixio")
local ipc = require("luci.ip")
require('luci.ohttp')
require("uci")

function round2(num, idp)
  return tonumber(string.format("%." .. (idp or 0) .. "f", num))
end

function adjust_rate(r,b)
	local ar
	if b==5 then
		ar=round2(r/4,1)
	elseif b==10 then
		ar=round2(r/2,1)
	else
		ar=round2(r/1,1)
	end
	return ar
end

function string:split(delim)
	local t = {}
	local function helper(line) table.insert(t, line) return "" end
		helper((self:gsub("(.-)"..delim, helper)))
	return t
end

function parseQueryString(qs)
	local qsa={}
	if qs ~=nil then
		qsa = luci.http.urldecode_params(qs)
	end
	return qsa
end

function setContains(set, key)
    return set[key] ~= nil
end

function sleep(n)  -- seconds
	nxo.nanosleep(n, 0)
end

function get_ip_type(ip)
  local R = {ERROR = 0, IPV4 = 1, IPV6 = 2, STRING = 3}
  if type(ip) ~= "string" then return R.ERROR end

  -- check for format 1.11.111.111 for ipv4
  local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
  if #chunks == 4 then
	for _,v in pairs(chunks) do
	  if tonumber(v) > 255 then return R.STRING end
	end
	return R.IPV4
  end

  --[[
  -- TODO
  -- check for ipv6 format, should be 8 'chunks' of numbers/letters
  -- without trailing chars
  local chunks = {ip:match(("([a-fA-F0-9]*):"):rep(8):gsub(":$","$"))}
  if #chunks == 8 then
	for _,v in pairs(chunks) do
	  if #v > 0 and tonumber(v, 16) > 65535 then return R.STRING end
	end
	return R.IPV6
  end
	--]]
  return R.STRING
end

-------------------------------------
-- Returns name of the radio (radio0 or radio1) for the selected wifi interface (wifi or lan)
-------------------------------------
function get_radio(ifn)
	local device = nil
	uci.cursor():foreach("wireless", "wifi-iface",
		function(s)
			if s.network == ifn then
				device = s.device
			end
		end
	)
	return device
end

-------------------------------------
-- Returns PHY name of the radio (phy0 or phy1) for the selected wifi interface (wifi or lan)
-------------------------------------
function get_radiophy(ifn)
	local rname=get_radio(ifn)
	return string.format("phy%d",string.sub(rname,-1))
end

-------------------------------------
-- Reset the auto-distance calculation for the radio
-------------------------------------
function reset_auto_distance()
    local rc=0
    local radio = get_radio("wifi") -- get radio number from /etc/config/wireless and convert to -> phy0 or phy1
    local u=uci.cursor()
	local distance=u:get("wireless",radio,"distance")
	print("DISTANCE=" .. distance)
    if distance=="0" then
    	local phyname = get_radiophy("wifi") -- get radio number from /etc/config/wireless and convert to -> phy0 or phy1
		print("iw phy " .. phyname .. " set distance 60000")
    	print("iw phy " .. phyname .. " set distance auto")
    	os.execute("iw phy " .. phyname .. " set distance 60000")
		rc=os.execute("iw phy " .. phyname .. " set distance auto")
	else
		rc=-1
	end
	return rc
end

function get_ifname(ifn)
	local u=uci.cursor()
	local iface=u:get("network",ifn,"ifname")
	if not iface then
		iface=u:get("network",ifn,"device")
	end
	return iface
end

-- Copyright 2009-2015 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.
function get_interfaces()
	local _interfaces={}
	local n, i
	for n, i in ipairs(nxo.getifaddrs()) do
		local name = i.name:match("[^:]+")
		_interfaces[name] = _interfaces[name] or {
						idx      = i.ifindex or n,
						name     = name,
						rawname  = i.name,
						ipaddrs  = { },
		}

		if i.family == "packet" then
						_interfaces[name].stats   = i.data
						_interfaces[name].macaddr = i.addr
		elseif i.family == "inet" then
						_interfaces[name].ipaddrs[#_interfaces[name].ipaddrs+1] = ipc.IPv4(i.addr, i.netmask)
		end
	end
	return _interfaces
end

-- checks if a file exists and can be read
function file_exists(name)
	local f=io.open(name,"r")
	if f~=nil then io.close(f) return true else return false end
end

function dir_exists(name)
	return (nixio.fs.stat(name, "type") == 'dir')
end

function hardware_boardid()
	local bid=""
	local ssdid="/sys/devices/pci0000:00/0000:00:00.0/subsystem_device"
	if file_exists(ssdid) then
		local bfile, err=io.open(ssdid,"r")
		if bfile~=nil then
			bid=bfile:read()
			bfile:close()
		end
	else
		bid=capture("/usr/local/bin/get_boardid")
	end
	return bid:chomp()
end

-- get IP from CIDR (strip network)
function ipFromCIDR(ip)
	return string.match(ip,"(%d+%.%d+%.%d+%.%d+)")
end

-- strips newline from a string
-- ex.   mystr=mystr:chomp()
function string:chomp()
	return(self:gsub("\n$", ""))
end

-- splits a string on newlines
-- ex. newtable=mystrings.splitNewLine()
function string:splitNewLine()
	local t = {}
	local function helper(line) table.insert(t, line) return "" end
		helper((self:gsub("(.-)\r?\n", helper)))
	return t
end

-- splits a string into words
function string:splitWhiteSpace()
	local t = {}
	local function helper(line) table.insert(t, line) return "" end
		helper((self:gsub("%S+", helper)))
	return t
end

function nslookup(ip)
        local hostname=nil
        if get_ip_type(ip)==1 then
                o1, o2, o3, o4 = ip:match("([^%.]+)%.([^%.]+)%.([^%.]+)%.([^%.]+)")
                rip = o4.."."..o3.."."..o2.."."..o1
                nso = capture("nslookup "..ip)
                hostname = nso:match(rip.."%.in%-addr%.arpa[%s]+name[%s]+=[%s]+(.*)")
				if hostname ~= nil then
                	hostname=hostname:chomp()
                	hostname=hostname:chomp()
					return hostname
                end
        end
end

-------------------------------------
-- Returns first IP of given host
-------------------------------------
function iplookup(host)
	if host:find("dtd.*%.") or host:find("mid%d+%.") then
		host=host:match("%.(.*)")
	end
	local nso=capture("nslookup "..host)
	local ip=nso:match("Address 1: (.*)%c")
	if not ip then
		ip=nso:match("Address: ([%d%.]+)")
	end
	return ip
end

function file_trim(filename, maxl)
	local lines={}
	local tmpfilename=filename..".tmp"
	if file_exists(filename) then
		for line in io.lines(filename) do table.insert(lines,line) end
		if (#lines > maxl) then
			local startline=(#lines-maxl)+1
			nxo.fs.rename(filename,tmpfilename)
			local f,err=io.open(filename,"w+")

			for n, l in pairs(lines) do
				if (n>=startline) then
					f:write(l.."\n")
				end
			end
			nxo.fs.remove(tmpfilename)
			f:close()
		end
	end
end

-- secondsToClock
function secondsToClock(seconds)
	local seconds = tonumber(seconds)
	if seconds <= 0 then
		return "00:00:00";
	else
		days = string.format("%d", math.floor(seconds/86400));
		hours = string.format("%d", math.floor(math.mod(seconds, 86400)/3600));
		mins = string.format("%02d", math.floor(math.mod(seconds,3600)/60));
		secs = string.format("%02d", math.floor(math.mod(seconds,60)));
		return days.." days, "..hours..":"..mins..":"..secs
	end
end

-- os.capture = captures output from a shell command
function capture(cmd)
	local handle= io.popen(cmd)
	local result=handle:read("*a")
	handle:close()
	return(result)
end

-- copy a file
function filecopy(from, to, ifchanged)
	local f = io.open(from, "r")
	if not f then
		return false
	end
	local r = f:read("*a")
	f:close()

	if ifchanged then
		local t = io.open(to, "r")
		if t then
			if r == t:read("*a") then
				t:close()
				return true, false
			end
			t:close()
		end
	end
	local t = io.open(to, "w")
	if not t then
		return false
	end
	t:write(r)
	t:close()
	return true, true
end

-- remove all files (including recursively into directories)
function remove_all(name)
    local type = nixio.fs.stat(name, "type")
    if type then
        if type == "dir" then
            for subname in nixio.fs.dir(name)
            do
                remove_all(name .. "/" .. subname)
            end
            nixio.fs.rmdir(name)
        else
            nixio.fs.remove(name)
        end
    end
end

-- write all data to a file in one go
function write_all(filename, data, ifchanged)
	if ifchanged then
		local t = io.open(filename, "r")
		if t then
			if data == t:read("*a") then
				t:close()
				return true, false
			end
			t:close()
		end
	end
    local f = io.open(filename, "w")
    if f then
        f:write(data)
        f:close()
		return true, true
    end
	return false
end

-- read all data from file in one go
function read_all(filename)
	local f = io.open(filename, "r")
	local data
	if f then
		data = f:read("*a")
		f:close()
	end
	return data
end

-- Return list of MAC to Hostname files
function mac2host(dir)
	dir = dir or "/tmp/snrlog"
	local i, list, popen = 0, {}, io.popen
	local pfile = popen("ls -A " .. dir)
	for filename in pfile:lines() do
		i = i + 1
		list[i] = filename
	end
	pfile:close()
	return list
end

function mac_to_ip(mac, shift)
    local a, b, c = mac:match("%w%w:%w%w:%w%w:(%w%w):(%w%w):(%w%w)")
	if not a then
		return "0.0.0"
	end
    return string.format("%d.%d.%d", tonumber(a, 16), tonumber(b, 16), tonumber(c, 16))
end

function decimal_to_ip(val)
    return (math.floor(val / 16777216) % 256) .. "." .. (math.floor(val / 65536) % 256) .. "." .. (math.floor(val / 256) % 256) .. "." .. (val % 256)
end

function ip_to_decimal(ip)
    local a, b, c, d = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
    if a then
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return 0
end

function netmask_to_cidr(mask)
	local v = ip_to_decimal(mask)
	cidr = 0
	while v ~= 0
	do
		cidr = cidr + 1
		v = (v * 2) % 0x100000000
	end
	return cidr
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
    if a == "0" or a == "128" or a == "192" or a == "224" or a == "240" or a == "248" or a == "252" or a == "254" or a == "255" then
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

function validate_fqdn(name)
	return name and name:match('^[%d%a_.-]+$') ~= nil and name:sub(0, 1) ~= '.' and name:sub(-1) ~= '.' and name:find('%.%.') == nil
end

function validate_hostname(name)
	if not name then
		return false
	end
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if name:match("_") or not name:match("^[%w%-]+$") then
		return false
	end
	return true
end

function validate_port(port)
	if not port then
		return false
	end
	port = port:gsub("^%s+", ""):gsub("%s+$", "")
	if port == "" or port:match("%D") then
		return false
	end
	port = tonumber(port)
	if port < 1 or port > 65535 then
		return false
	end
	return true
end

function validate_port_range(range)
	if not range then
		return false
	end
	local port1, port2 = range:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
	if not port2 then
		return false
	end
	if not validate_port(port1) or not validate_port(port2) then
		return false
	end
	if tonumber(port1) > tonumber(port2) then
		return false
	end
	return true
end

-- return true if 32mb node
function isLowMemNode()
    totalmem = nixio.sysinfo().totalram
    if totalmem <= 33554432 then
        return true
    end
    return false
end

--[[
LuCI - System library

Description:
Utilities for interaction with the Linux system

FileId:
$Id: sys.lua 9662 2013-01-30 13:36:20Z soma $

License:
Copyright 2008 Steven Barth <steven@midlink.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

]]--
--- Returns the current arp-table entries as two-dimensional table.
-- @return	Table of table containing the current arp entries.
--			The following fields are defined for arp entry objects:
--			{ "IP address", "HW address", "HW type", "Flags", "Mask", "Device" }
function arptable(callback)
	local arp, e, r, v
	if nixio.fs.access("/proc/net/arp") then
		for e in io.lines("/proc/net/arp") do
			local r = { }, v
			for v in e:gmatch("%S+") do
				r[#r+1] = v
			end

			if r[1] ~= "IP" then
				local x = {
					["IP address"] = r[1],
					["HW type"]    = r[2],
					["Flags"]      = r[3],
					["HW address"] = r[4],
					["Mask"]       = r[5],
					["Device"]     = r[6]
				}

				if callback then
					callback(x)
				else
					arp = arp or { }
					arp[#arp+1] = x
				end
			end
		end
	end
	return arp
end
