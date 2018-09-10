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
require("aredn.uci")
require("aredn.utils")
-- require("aredn.http")
local lip=require("luci.ip")
require("nixio")
require("ubus")

function getNodeName()
	css=getUciConfType("system", "system")
	return css[0]['hostname']
end

function getNodeDescription()
	css=getUciConfType("system", "system")
	return css[0]['description']
end

function getLatLon()
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

function getGridSquare()
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

function getFirmwareVersion()
	local relfile=io.open("/etc/mesh-release","r")
	local fv=""
	if relfile~=nil then
		fv=relfile:read():chomp()
		relfile:close()
	end
	return fv
end

function getModel()
	m=os.capture("/usr/local/bin/get_model")
	return m:chomp()
end

function getSSID()
	-- SSID
	local myssid=""
	local wif=getUciConfType("wireless", "wifi-iface")
	for pos, t in pairs(wif) do
		if wif[pos]['network']=="wifi" then
			myssid=wif[pos]['ssid']
		end
	end
	return myssid
end

function getMeshRadioDevice()
	--Determine radio device for mesh
	local radio=""
	local wifiinterfaces=getUciConfType("wireless","wifi-iface")
	for pos,i in pairs(wifiinterfaces) do
		if wifiinterfaces[pos]['mode']=="adhoc" then
			radio=wifiinterfaces[pos]['device']
		end
	end
	return radio
end

function getBand(radio)
	return ""
end

function getFrequency(radio)
	return ""
end

function getChannel(radio)
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

function getChannelBW(radio)
	--Wifi Bandwidth
	ctx = uci.cursor()
	if not ctx then
			error("Failed to get uci cursor")
	end
	local chanbw=""
	chanbw = ctx:get("wireless", radio, "chanbw")
	return chanbw
end

function getUptime()
	local mynix=nixio.sysinfo()
	local upsecs=mynix['uptime']
	return secondsToClock(upsecs)
end

function getDate()
	return os.date("%a %b %d %Y")
end

function getTime()
	return os.date("%H:%M:%S %Z")
end

function getLoads()
	local loads={}
	local mynix=nixio.sysinfo()
	loads=mynix['loads']
	for n,x in ipairs(loads) do
	  loads[n]=round2(x,2)
	end
	return loads
end

function getFreeMemory()
	local mem={}
	local mynix=nixio.sysinfo()
	mem['freeram']=mynix['freeram']/1024
	mem['sharedram']=mynix['sharedram']/1024
	mem['bufferram']=mynix['bufferram']/1024
	return mem
end

function getFSFree()
	local fsf={}
	local mynix=nixio.fs.statvfs("/")
	fsf['rootfree']=mynix['bfree']*4
	mynix=nixio.fs.statvfs("/tmp")
	fsf['tmpfree']=mynix['bfree']*4
	mynix=nil
	return fsf
end

function getOLSRInfo()
	local info={}
	tot=os.capture('/sbin/ip route list table 30|wc -l')
	info['entries']=tot:chomp()
	nodes=os.capture('/sbin/ip route list table 30|grep -E "/"|wc -l')
	info['nodes']=nodes:chomp()
	return info
end

function getInterfaceIPAddress(interface)
	return getUciConfSectionOption("network",interface,"ipaddr")
end

function getDefaultGW()
	local gw=""
  	local rt=lip.route("8.8.8.8")
 	if rt ~= "" then
		gw=tostring(rt.gw)
 	end
	return gw
end

function getWAN()
	local cubus = ubus.connect()
	niws=cubus:call("network.interface.wan","status",{})
	return niws['ipv4-address'][1]['address']
end
