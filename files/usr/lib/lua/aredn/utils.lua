#!/usr/bin/lua
--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2016 Darryl Quinn
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
local posix = require("posix.unistd")
require("uci")

function round2(num, idp)
  return tonumber(string.format("%." .. (idp or 0) .. "f", num))
end

function adjust_rate(r,b)
	local ar=r
	if b==5 then
		ar=round2(ar/4,1)
	elseif b==10 then
		ar=round2(ar/2,1)
	end
	return ar
end

function get_bandwidth()
	local curs=uci.cursor()
	local b
	b=curs:get("wireless","radio0","chanbw")
	return tonumber(b)
end

function sleep(n)  -- seconds
	posix.sleep(n)
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

function get_ifname(ifn)
	local u=uci.cursor()
	iface=u:get("network",ifn,"ifname")
	return iface
end

-- Copyright 2009-2015 Jo-Philipp Wich <jow@openwrt.org>
-- Licensed to the public under the Apache License 2.0.
function get_interfaces()
	_interfaces={}
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
	return string.match(ip,"(.*)/.-")
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
		hostname=capture("nslookup '"..ip.."'|grep 'Address 1'|grep -v 'localhost'|cut -d' ' -f4 2>&1")
		hostname=hostname:chomp()
		if hostname=="" then
			hostname=nil
		end
	end
	return hostname
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

-- table.print = pretty prints a table
function print_r(t)
	local print_r_cache={}
	local function sub_print_r(t,indent)
			if (print_r_cache[tostring(t)]) then
					print(indent.."*"..tostring(t))
			else
					print_r_cache[tostring(t)]=true
					if (type(t)=="table") then
							for pos,val in pairs(t) do
									if (type(val)=="table") then
											print(indent.."["..pos.."] => "..tostring(t).." {")
											sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
											print(indent..string.rep(" ",string.len(pos)+6).."}")
									elseif (type(val)=="string") then
											print(indent.."["..pos..'] => "'..val..'"')
									else
											print(indent.."["..pos.."] => "..tostring(val))
									end
							end
					else
							print(indent..tostring(t))
					end
			end
	end
	if (type(t)=="table") then
			print(tostring(t).." {")
			sub_print_r(t,"  ")
			print("}")
	else
			sub_print_r(t,"  ")
	end
	print()
end

-- os.capture = captures output from a shell command
function capture(cmd)
	local handle= io.popen(cmd)
	local result=handle:read("*a")
	handle:close()
	return(result)
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
