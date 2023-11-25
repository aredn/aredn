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
-- Returns build target type
-------------------------------------
function model.getTargetType()
	local cubus = ubus.connect()
	sb=cubus:call("system","board",{})
	if sb['release']['target'] == nil then
		return ""
	end
	return sb['release']['target']
end

-------------------------------------
-- Returns name of the node
-------------------------------------
function model.getNodeName()
	css=aredn_uci.getUciConfType("system", "system")
	return css[1]['hostname']
end

-------------------------------------
-- Returns tactical name of the node
-------------------------------------
function model.getTacticalName()
	css=aredn_uci.getNonStandardUciConfType("/etc/local/uci/", "hsmmmesh", "settings")
	return css[1]['tactical']
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
	loc=aredn_uci.getUciConfType("aredn", "location")
	return loc[1]['lat'], loc[1]['lon']
end

-------------------------------------
-- Returns Grid Square of Node
-------------------------------------
function model.getGridSquare()
		loc=aredn_uci.getUciConfType("aredn", "location")
	return loc[1]['gridsquare']
end

-------------------------------------
-- Returns antenna azimuth
-------------------------------------
function model.getAzimuth()
	loc=aredn_uci.getUciConfType("aredn", "location")
	return loc[1]['azimuth']
end

-------------------------------------
-- Returns antenna elevation
-------------------------------------
function model.getElevation()
	loc=aredn_uci.getUciConfType("aredn", "location")
	return loc[1]['elevation']
end

-------------------------------------
-- Returns antenna height
-------------------------------------
function model.getHeight()
	loc=aredn_uci.getUciConfType("aredn", "location")
	return loc[1]['height']
end

-------------------------------------
-- Returns AREDN Alert (if exists)
-------------------------------------
function model.getArednAlert()
	local fname="/tmp/aredn_message"
	local alert=""
	if file_exists(fname) then
		afile=io.open(fname,"r")
		if afile~=nil then
			alert=afile:read("*a")
			afile:close()
		end
	end
        if #alert~=0 then return alert
        else return ""
        end
end

-------------------------------------
-- Returns LOCAL Alert (if exists)
-------------------------------------
function model.getLocalAlert()
	local fname="/tmp/local_message"
	local alert=""
	if file_exists(fname) then
		afile=io.open(fname,"r")
		if afile~=nil then
			alert=afile:read("*a")
			afile:close()
		end
	end
        if #alert~=0 then return alert
        else return ""
        end
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
			break
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
			break
		end
	end
	return radio
end

-------------------------------------
-- Determine if Radio Device for Mesh is enabled
-------------------------------------
function model.isMeshRadioEnabled(radio)
	local wifidevice=aredn_uci.getUciConfType("wireless","wifi-device")
	for pos,i in pairs(wifidevice) do
		if wifidevice[pos]['.name']==radio then
			disabled=wifidevice[pos]['disabled']
			break
		end
	end
	
	if disabled == "0" then
		return true
	else
		return false
	end
end

-------------------------------------
-- Determine distance value for Mesh radio
-------------------------------------
function model.getMeshRadioDistance(radio)
	local distance = ""
	local wifidevice=aredn_uci.getUciConfType("wireless","wifi-device")
	for pos,i in pairs(wifidevice) do
		if wifidevice[pos]['.name']==radio then
			distance=wifidevice[pos]['distance']
			break
		end
	end
	return distance
end

-------------------------------------
-- TODO: Return Band
-------------------------------------
function model.getBand(radio)
	return ""
end

-------------------------------------
-- Return TX Power
-------------------------------------
function model.getTXPower(wlanInf)
	local api=iwinfo.type(wlanInf)
	local iw = iwinfo[api]
	local power = iw.txpower(wlanInf)
	return tostring(power)
end

-------------------------------------
-- Return Frequency
-------------------------------------
function model.getFreq(radio)
	local api=iwinfo.type(radio)
	local iw = iwinfo[api]
	local freq = iw.frequency(radio)
	local chan = tonumber(uci.cursor():get("wireless", radio, "channel") or 0)
	-- 3GHZ channel -> Freq conversion
	if (chan >= 76 and chan <= 99) then
		freq = freq - 2000
	end
	return tostring(freq)
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
			local link,protocol,name,ip = string.match(val,"^([^|]*)|(.+)|([^\t]*)\t#(.*)")
			if link and protocol and name then
				if string.match(link,":0/") then
					service['link']=""
				else
					service['link']=link
				end
				service['protocol']=protocol
				service['name']=name
				if ip==" my own service" then
					service['ip']=model.getInterfaceIPAddress("wifi")
				else
					service['ip']=ip
				end
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
	local hfile=io.open("/var/run/hosts_olsr.stable","r")
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
						if not string.match(name,"^(mid%d+[.]).*") then
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
	return secondsToClock(upsecs)
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
	mem['totalram']=mynix['totalram']/1024
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
	fsf['roottotal']=mynix['blocks']*4
	mynix=nixio.fs.statvfs("/tmp")
	fsf['tmpfree']=mynix['bfree']*4
	fsf['tmptotal']=mynix['blocks']*4
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
-- Returns Interface Netmask
-- @param interface name of interface 'wifi' | 'lan' | 'wan'
-------------------------------------
function model.getInterfaceNetmask(interface)
	-- special case
	-- if interface == "wan" then
	-- 	return getWAN()
	-- end
	return aredn_uci.getUciConfSectionOption("network",interface,"netmask")
end

-------------------------------------
-- Returns Default Gateway
-------------------------------------
function model.getDefaultGW()
	local gw=""
  	local rt=lip.route("8.8.8.8")
 	if rt ~= nil then
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
  local localhosts = {}
  myhosts=os.capture('/bin/grep "# myself" /var/run/hosts_olsr.stable|grep -v dtdlink')
  local lines = myhosts:splitNewLine()
  data = {}
  for k,v in pairs(lines) do
    data = v:splitWhiteSpace()
    local ip = data[1]
    local hostname = data[2]
    if ip and hostname then
      local entry = {}
      entry['ip'] = ip
      entry['hostname'] = hostname
      if hostname:lower() == string.lower( model.getNodeName() ) then
        entry['cnxtype'] = "RF"
      else
        entry['cnxtype'] = "LAN"
      end
      table.insert(localhosts, entry)
    end
  end
  return localhosts
end

-------------------------------------
-- Returns Mesh gateway setting
-------------------------------------
function model.getMeshGatewaySetting()
	return uci.cursor():get("aredn", "@wan[0]", "olsrd_gw") or ""
end

-------------------------------------
-- Returns LAN Mode (dmz_mode)
-------------------------------------
function model.getLANMode()
	lm=os.capture("cat /etc/config.mesh/_setup|grep dmz_mode|cut -d'=' -f2|tr -d ' ' ")
	lm=lm:chomp()
	return lm
end

-------------------------------------
-- is LAN DHCP enabled
-------------------------------------
function model.isLANDHCPEnabled()
	r=os.capture("cat /etc/config.mesh/_setup|grep lan_dhcp|cut -d'=' -f2|tr -d ' ' ")
	r=r:chomp()
	if r=="0" then
		return false
	else
		return true
	end
end

-------------------------------------
-- is Mesh olsr gateway enabled
-------------------------------------
function model.isMeshGatewayEnabled()
	local r = model.getMeshGatewaySetting()
	if r=="0" then
		return false
	else
		return true
	end
end


-------------------------------------
-- Get and set NVRAM values
-------------------------------------
function model.get_nvram(var)
    return uci.cursor("/etc/local/uci"):get("hsmmmesh", "settings", var) or ""
end

function model.set_nvram(var, val)
    local c = uci.cursor("/etc/local/uci")
    c:set("hsmmmesh", "settings", var, val)
    c:commit("hsmmmesh")
end

return model
