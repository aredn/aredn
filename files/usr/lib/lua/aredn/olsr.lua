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
require("aredn.http")

-------------------------------------
-- Public API is attached to table
-------------------------------------
local model = {}

function model.getOLSRLinks()
  local links=fetch_json("http://127.0.0.1:9090/links")
  return links['links']
end

function model.getOLSRInterfaceType(iface)
  local it=""
  if string.match(iface,"wlan") then
    it="RF"
  elseif string.match(iface,"eth") then
    it="DTD"
  elseif string.match(iface,"tun") then
    it="TUN"
  end
  return it
end

function model.getCurrentNeighbors()
  local info={}
  local links=model.getOLSRLinks()
  for k,v in pairs(links) do
    local host
    local remip=v['remoteIP']
    local remhost=nslookup(remip)
    info[remip]={}
    info[remip]['olsrInterface']=v['olsrInterface']
    info[remip]['linkType']= model.getOLSRInterfaceType(v['olsrInterface'])    -- RF or DTD or TUN
    info[remip]['linkQuality']=v['linkQuality']
    info[remip]['neighborLinkQuality']=v['neighborLinkQuality']
    host = string.gsub(remhost,"dtdlink%.", "")
    host = string.gsub(host,"mid%d.", "")
    info[remip]['hostname']=host
    -- services
    -- info[remip]['services']={}
    -- get TxMBPS
    -- info[remip]['rate']="0"
  end
  return info
end

function model.getServicesByNode(node)
    return {}
end

return model