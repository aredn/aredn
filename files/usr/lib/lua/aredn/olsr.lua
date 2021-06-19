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
require("aredn.utils")
local ai=require("aredn.info")
-------------------------------------
-- Public API is attached to table
-------------------------------------
local model = {}

function model.getOLSRLinks()
  local links=fetch_json("http://127.0.0.1:9090/links")
  return links['links']
end

function model.getOLSRRoutes()
  local routes=fetch_json("http://127.0.0.1:9090/routes")
  return routes['routes']
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

function model.getCurrentNeighbors(RFinfo)
  local RFinfo = RFinfo or false
  local info={}
  local links=model.getOLSRLinks()  -- Get info for all current neighbors
  for k,v in pairs(links) do
    local host
    local linkip=v['remoteIP']

    local linkhost=nslookup(linkip) -- TOTO: stop using nslookup? use /var/run/olsr_hosts
    linkip=iplookup(linkhost)

    info[linkip]={}
    info[linkip]['olsrInterface']=v['olsrInterface']
    info[linkip]['linkType']= model.getOLSRInterfaceType(v['olsrInterface'])  -- RF or DTD or TUN
    info[linkip]['linkQuality']=v['linkQuality']
    info[linkip]['neighborLinkQuality']=v['neighborLinkQuality']

    if linkhost~=nil then
      host = string.gsub(linkhost,"mid%d+.", "")
      host = string.gsub(host,"dtdlink%.", "")
      host = string.gsub(host,".local.mesh$","")
      info[linkip]['hostname']=host
    else
      info[linkip]['hostname']=linkip
    end

    if info[linkip]['linkType'] == "RF" and RFinfo then  -- get additional info for RF link
      require("iwinfo")
      info[linkip]["rfip"] = linkip
      local radio = ai.getMeshRadioDevice()
      local bandwidth = tonumber(ai.getChannelBW(radio))
      local wlan=get_ifname('wifi')
      local RFneighbors=iwinfo['nl80211'].assoclist(wlan)
      local mac2node=mac2host()
      for i, mac_host in pairs(mac2node) do
        local mac=string.match(mac_host, "^(.-)\-")
        mac=mac:upper()
        local node=string.match(mac_host, "\-(.*)")  -- add error checking here?
        if node == "" then node=linkhost end
        if linkhost == node or linkip == node then
          for stn in pairs(RFneighbors) do
            stnInfo=iwinfo['nl80211'].assoclist(wlan)[mac]
            if stnInfo ~= nil then
              info[linkip]["signal"]=tonumber(stnInfo.signal)
              info[linkip]["noise"]=tonumber(stnInfo.noise)
              info[linkip]["tx_rate"]=adjust_rate(stnInfo.tx_rate/1000,bandwidth)
              info[linkip]["rx_rate"]=adjust_rate(stnInfo.rx_rate/1000,bandwidth)
              info[linkip]["expected_throughput"]=adjust_rate(stnInfo.expected_throughput/1000,bandwidth)
            end
          end
        end
      end
    else  -- Get RF IP for non-RF nodes to display services keyed to RF IP
      local allhosts=ai.all_hosts()
      for k,v in pairs(allhosts) do
        if linkhost == v['name'] or host == v['name'] then
          info[linkip]["rfip"]=v['ip']
        end
      end
    end
  end
  return info
end

function model.getServicesByNode(node)
    return {}
end

return model
