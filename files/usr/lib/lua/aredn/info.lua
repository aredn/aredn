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

require("uci")
local aredn_uci = require("aredn.uci")
require("aredn.utils")
local olsr=require("aredn.olsr")
-- require("aredn.http")
local lip=require("luci.ip")
require("nixio")
require("ubus")
require("iwinfo")

-------------------------------------
-- Public API is attached to table
-------------------------------------
local model = {}


-------------------------------------
-- Get FIRST_BOOT status
-------------------------------------
function model.getFirstBoot()
	return (model.getNodeName()=="NOCALL")
end

-------------------------------------
-- Returns WAN Address
-------------------------------------
local function getWAN()
	local cubus = ubus.connect()
	niws=cubus:call("network.interface.wan","status",{})
	if niws['ipv4-address'] == nil or niws['ipv4-address'][1] == nil then
		return ""
	end
	return niws['ipv4-address'][1]['address']
end


-------------------------------------
-- Returns name of the node
-------------------------------------
function model.getNodeName()
	css=aredn_uci.getUciConfType("system", "system")
	return css[1]['hostname']
end

-------------------------------------
-- Returns description of the node
-------------------------------------
function model.getNodeDescription()
	css=aredn_uci.getUciConfType("system", "system")
	return css[1]['description']
end

-------------------------------------
-- Returns array [Latitude, Longitude]
-------------------------------------
function model.getLatLon()
	local llfname="/etc/latlon"
	local lat=""
	local lon=""
	if file_exists(llfname) then
		llfile=io.open(llfname,"r")
		if llfile~=nil then
			lat=llfile:read()
			lon=llfile:read()
			llfile:close()
		end
	end
	return lat,lon
end

-------------------------------------
-- Returns Grid Square of Node
-------------------------------------
function model.getGridSquare()
	local gsfname="/etc/gridsquare"
	local grid=""
	if file_exists(gsfname) then
		gsfile=io.open(gsfname,"r")
		if gsfile~=nil then
			grid=gsfile:read()
			gsfile:close()
		end
	end
	return grid
end

-------------------------------------
-- Returns Current Firmware Version
-------------------------------------
function model.getFirmwareVersion()
	local relfile=io.open("/etc/mesh-release","r")
	local fv=""
	if relfile~=nil then
		fv=relfile:read():chomp()
		relfile:close()
	end
	return fv
end


-------------------------------------
-- Retuns Model / Device name
-------------------------------------
function model.getModel()
	m=os.capture("/usr/local/bin/get_model")
	return m:chomp()
end

-------------------------------------
-- Returns current SSID
-------------------------------------
function model.getSSID()
	-- SSID
	local myssid=""
	local wif=aredn_uci.getUciConfType("wireless", "wifi-iface")
	for pos, t in pairs(wif) do
		if wif[pos]['network']=="wifi" then
			myssid=wif[pos]['ssid']
		end
	end
	return myssid
end


-------------------------------------
-- Determine Radio Device for Mesh
-------------------------------------
function model.getMeshRadioDevice()
	--Determine radio device for mesh
	local radio=""
	local wifiinterfaces=aredn_uci.getUciConfType("wireless","wifi-iface")
	for pos,i in pairs(wifiinterfaces) do
		if wifiinterfaces[pos]['mode']=="adhoc" then
			radio=wifiinterfaces[pos]['device']
		end
	end
	return radio
end

-------------------------------------
-- TODO: Return Band
-------------------------------------
function model.getBand(radio)
	return ""
end

-------------------------------------
-- Return Frequency
-------------------------------------
function model.getFreq()
	local wlanInf=get_ifname('wifi')
	local freq=""
	freq=os.capture("iwinfo " .. wlanInf .. " info | egrep 'Mode:'")
	freq=freq:gsub("^%s*(.-)%s*$", "%1")
	freq=string.match(freq, "%((.-)%)")
	return freq
end

-------------------------------------
-- Return locally hosted services (for sysinfo.json)
-------------------------------------
function model.local_services()
	local filelines={}
	local lclsrvs={}
	local lclsrvfile=io.open("/etc/config/services", "r")
	if lclsrvfile~=nil then
		for line in lclsrvfile:lines() do
			table.insert(filelines, line)
		end
		lclsrvfile:close()
		for pos,val in pairs(filelines) do
			local service={}
			local link,protocol,name = string.match(val,"^([^|]*)|(.+)|([^\t]*).*")
			if link and protocol and name then
				service['name']=name
				service['protocol']=protocol
				service['link']=link
				table.insert(lclsrvs, service)
			end
		end
	else
		service['error']="Cannot read local services file"
		table.insert(lclsrvs, service)
	end
	return lclsrvs
end

-------------------------------------
-- Return *All* Network Services
-------------------------------------
function model.all_services()
	local services={}
	local lines={}
	local pos, val
	local hfile=io.open("/var/run/services_olsr","r")
	if hfile~=nil then
		for line in hfile:lines() do
			table.insert(lines,line)
		end
		hfile:close()
		for pos,val in pairs(lines) do
			local service={}
			local link,protocol,name = string.match(val,"^([^|]*)|(.+)|([^\t]*)\t#.*")
			if link and protocol and name then
				service['link']=link
				service['protocol']=protocol
				service['name']=name
				table.insert(services,service)
			end
		end
	else
		service['error']="Cannot read services file"
		table.insert(services,service)
	end
	return services
end

-------------------------------------
-- Return *All* Hosts
-------------------------------------
function model.all_hosts()
	local hosts={}
	local lines={}
	local pos, val
	local hfile=io.open("/var/run/hosts_olsr","r")
	if hfile~=nil then
		for line in hfile:lines() do
			table.insert(lines,line)
		end
		hfile:close()
		for pos,val in pairs(lines) do
			local host={}

			-- local data,comment = string.match(val,"^([^#;]+)[#;]*(.*)$")
			local data,comment = string.match(val,"^([^#;]+)[#;]*(.*)$")

			if data then
				--local ip, name=string.match(data,"^%s*([%x%.%:]+)%s+(%S.*)\t%s*$")
				local ip, name=string.match(data,"^([%x%.%:]+)%s+(%S.*)\t%s*$")
				if ip and name then
					if not string.match(name,"^(dtdlink[.]).*") then
						if not string.match(name,"^(mid[0-9][.]).*") then
							host['name']=name
							host['ip']=ip
							table.insert(hosts,host)
						end
					end
				end
			end
		end
	else
		host['error']="Cannot read hosts file"
		table.insert(hosts,host)
	end
	return hosts
end

-------------------------------------
-- Return Channel for Radio
-- @param radio Radio Device.
-------------------------------------
function model.getChannel(radio)
	--Wifi Channel Number
	local ctx = uci.cursor()
	if not ctx then
			error("Failed to get uci cursor")
	end
	local chan=""
	chan = tonumber(ctx:get("wireless", radio, "channel"))
	-- 3GHZ channel -> Freq conversion
	if (chan >= 76 and chan <= 99) then
		chan=(chan * 5) + 3000
	end
	return tostring(chan)
end


-------------------------------------
-- Return Channel BW for Radio
-- @param radio Radio Device.
-------------------------------------
function model.getChannelBW(radio)
	--Wifi Bandwidth
	ctx = uci.cursor()
	if not ctx then
			error("Failed to get uci cursor")
	end
	local chanbw=""
	chanbw = ctx:get("wireless", radio, "chanbw")
	return chanbw
end

-------------------------------------
-- Current System Uptime
-------------------------------------
function model.getUptime()
	local mynix=nixio.sysinfo()
	local upsecs=mynix['uptime']
	return upsecs
end


-------------------------------------
-- System Date Formatted
-------------------------------------
function model.getDate()
	return os.date("%a %b %d %Y")
end

-------------------------------------
-- System Time Formatted
-------------------------------------
function model.getTime()
	return os.date("%H:%M:%S %Z")
end


-------------------------------------
-- Returns current epoch time
-------------------------------------
function getEpoch()
	return os.time()
end

-------------------------------------
-- Returns last three average loads
-------------------------------------
function model.getLoads()
	local loads={}
	local mynix=nixio.sysinfo()
	loads=mynix['loads']
	for n,x in ipairs(loads) do
	  loads[n]=round2(x,2)
	end
	return loads
end

-------------------------------------
-- Returns memory details
-------------------------------------
function model.getFreeMemory()
	local mem={}
	local mynix=nixio.sysinfo()
	mem['freeram']=mynix['freeram']/1024
	mem['sharedram']=mynix['sharedram']/1024
	mem['bufferram']=mynix['bufferram']/1024
	return mem
end

-------------------------------------
-- Returns FS Usage details
-------------------------------------
function model.getFSFree()
	local fsf={}
	local mynix=nixio.fs.statvfs("/")
	fsf['rootfree']=mynix['bfree']*4
	mynix=nixio.fs.statvfs("/tmp")
	fsf['tmpfree']=mynix['bfree']*4
	mynix=nil
	return fsf
end

-------------------------------------
-- Returns OLSR info
-------------------------------------
function model.getOLSRInfo()
	local info={}
	tot=os.capture('/sbin/ip route list table 30|wc -l')
	info['entries']=tot:chomp()
	nodes=os.capture('/sbin/ip route list table 30|grep -E "/"|wc -l')
	info['nodes']=nodes:chomp()
	return info
end

-------------------------------------
-- Returns Interface IP Address
-- @param interface name of interface 'wifi' | 'lan' | 'wan'
-------------------------------------
function model.getInterfaceIPAddress(interface)
	-- special case
	if interface == "wan" then
		return getWAN()
	end

	return aredn_uci.getUciConfSectionOption("network",interface,"ipaddr")
end

-------------------------------------
-- Returns Default Gateway
-------------------------------------
function model.getDefaultGW()
	local gw=""
  	local rt=lip.route("8.8.8.8")
 	if rt ~= "" then
		gw=tostring(rt.gw)
 	end
	return gw
end

-------------------------------------
-- Returns Table of current DHCP leases 
-------------------------------------
function model.getCurrentDHCPLeases()
    local lines={}
    local leases={}
    local filename="/tmp/dhcp.leases"
    if file_exists(filename) then
        for line in io.lines(filename) do table.insert(lines,line) end
        for n, l in pairs(lines) do
	        local lease={}
	        local data=l:splitWhiteSpace()
	        lease["mac"]=data[2]
	        lease["ip"]=data[3]
	        lease["host"]=data[4]
	        table.insert(leases, lease)
        end
    end
    return leases
end

-------------------------------------
-- Returns Local Hosts
-------------------------------------
function model.getLocalHosts()
	local hosts, line
	if nixio.fs.access("/etc/hosts") then
		for line in io.lines("/etc/hosts") do
			line = line:lower()
			-- line is not a comment
			local data = line:match("^([^#;]+)[#;]*(.*)$")
			if data then 
				local hostname, entries
				local ip, entries = data:match("^%s*([%[%]%x%.%:]+)%s+(%S.-%S)%s*$")

				if ip then 
					local entry = {
						["ip"] = ip,
						["hostnames"] = { }
					}
					local index = 0
					for hostname in entries:gmatch("%S+") do
						entry["hostnames"][index] = hostname
						index = index + 1
					end
					hosts = hosts or { }
					hosts[#hosts+1] = entry
				end
			end
		end
	end
	return hosts
end

return model