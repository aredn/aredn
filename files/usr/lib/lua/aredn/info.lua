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
-- require("aredn.http")
local lip=require("luci.ip")
require("nixio")
require("ubus")

-------------------------------------
-- Public API is attached to table
-------------------------------------
local model = {}

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
	return css[0]['hostname']
end

-------------------------------------
-- Returns description of the node
-------------------------------------
function model.getNodeDescription()
	css=aredn_uci.getUciConfType("system", "system")
	return css[0]['description']
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
-- TODO: Return Frequency
-------------------------------------
function model.getFrequency(radio)
	return ""
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



return model