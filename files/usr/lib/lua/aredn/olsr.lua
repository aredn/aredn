#!/usr/bin/lua
--[[

  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

  Additional use restrictions exist on the AREDN® trademark and logo.
    See AREDNLicense.txt for more info.

  Attributions to the AREDN® Project must be retained in the source code.
  If importing this code into a new or existing project attribution
  to the AREDN® project must be added to the source code.

  You must not misrepresent the origin of the material contained within.

  Modified versions must be modified to attribute to the original source
  and be marked in reasonable ways as differentiate it from the original
  version.

--]]

require("nixio")
require("aredn.utils")
require("aredn.info")
require("luci.jsonc")

function fetch_json(url)
  local raw = io.popen("/usr/bin/curl --retry 0 --connect-timeout 5 -s \"" .. url .. "\" -o - 2> /dev/null")
  local j = luci.jsonc.parse(raw:read("*a"))
  raw:close()
  return j
end

-------------------------------------
-- Public API is attached to table
-------------------------------------
local model = {}

function model.getOLSRLinks()
  local links=fetch_json("http://127.0.0.1:9090/links")
  return links and links['links'] or {}
end

function model.getOLSRRoutes()
  local routes=fetch_json("http://127.0.0.1:9090/routes")
  return routes and routes['routes'] or {}
end

function model.getOLSRHNA()
  local hna=fetch_json("http://127.0.0.1:9090/hna")
  return hna and hna['hna'] or {}
end

function model.getOLSRMid()
  local mid=fetch_json("http://127.0.0.1:9090/mid")
  return mid and mid['mid'] or {}
end

function model.getOLSRTopology()
  local topology=fetch_json("http://127.0.0.1:9090/topology")
  return topology and topology['topology'] or {}
end

function model.getOLSRInterfaceType(iface)
  local it=""
  if string.match(iface,"wlan") then
    it="RF"
  elseif string.match(iface,"eth") or string.match(iface, "dtdlink") then
    it="DTD"
  elseif string.match(iface,"tun") then
    it="TUN"
  elseif string.match(iface,"wg") then
    it="WIREGUARD"
  elseif string.match(iface,"^br0%.%d+$") then
    it="XLINK"
  end
  return it
end

function model.getCurrentNeighbors(RFinfo)
  local RFinfo = RFinfo or false
  local info={}
  local links=model.getOLSRLinks()  -- Get info for all current neighbors
  for k,v in pairs(links) do
    local host=nslookup(v['remoteIP'])
    if host then
      local mainip=iplookup(host)
      if mainip then
        info[mainip]={}

        if host~=nil then
          host = string.gsub(host,"mid%d+%.", "")
          host = string.gsub(host,"dtdlink%.", "")
          host = string.gsub(host,"xlink%d+%.", "")
          host = string.gsub(host,"%.local%.mesh$","")
          info[mainip]['hostname']=host
        else
          info[mainip]['hostname']=mainip
        end

        info[mainip]['olsrInterface']=v['olsrInterface']
        info[mainip]['linkType']= model.getOLSRInterfaceType(v['olsrInterface'])  -- RF or DTD or TUN or WIREGUARD
        info[mainip]['linkQuality']=v['linkQuality']
        info[mainip]['neighborLinkQuality']=v['neighborLinkQuality']

        -- additional info about each link
        info[mainip]['validityTime']=v['validityTime']
        info[mainip]['symmetryTime']=v['symmetryTime']
        info[mainip]['asymmetryTime']=v['asymmetryTime']
        info[mainip]['vtime']=v['vtime']
        info[mainip]['currentLinkStatus']=v['currentLinkStatus']
        info[mainip]['previousLinkStatus']=v['previousLinkStatus']
        info[mainip]['hysteresis']=v['hysteresis']
        info[mainip]['pending']=v['pending']
        info[mainip]['lostLinkTime']=v['lostLinkTime']
        info[mainip]['helloTime']=v['helloTime']
        info[mainip]['lastHelloTime']=v['lastHelloTime']
        info[mainip]['seqnoValid']=v['seqnoValid']
        info[mainip]['seqno']=v['seqno']
        info[mainip]['lossHelloInterval']=v['lossHelloInterval']
        info[mainip]['lossTime']=v['lossTime']
        info[mainip]['lossMultiplier']=v['lossMultiplier']
        info[mainip]['linkCost']=v['linkCost']

        if info[mainip]['linkType'] == "RF" and RFinfo then
          require("iwinfo")
          local radio = aredn.info.getMeshRadioDevice()
          local bandwidth = tonumber(aredn.info.getChannelBW(radio))
          local RFinterface=get_ifname('wifi')
          local arptable=capture("/bin/cat /proc/net/arp |grep "..RFinterface)
          local lines=arptable:splitNewLine()
          table.remove(lines, #lines) -- remove blank last line
          for k1,v1 in pairs(lines) do
            local field=v1:splitWhiteSpace()
            local arpip=field[1]
            local mac=field[4]
            mac=mac:upper()
            if mac and arpip == mainip then
              stnInfo=iwinfo['nl80211'].assoclist(RFinterface)[mac]
              if stnInfo~=nil then
                info[mainip]["signal"]=tonumber(stnInfo.signal)
                info[mainip]["noise"]=tonumber(stnInfo.noise)
                if stnInfo.tx_rate then
                  info[mainip]["tx_rate"]=adjust_rate(stnInfo.tx_rate/1000,bandwidth)
                end
                if stnInfo.rx_rate then
                  info[mainip]["rx_rate"]=adjust_rate(stnInfo.rx_rate/1000,bandwidth)
                end
                if stnInfo.expected_throughput then
                  info[mainip]["expected_throughput"]=adjust_rate(stnInfo.expected_throughput/1000,bandwidth)
                end
              end
            end
          end
        end
      end
    end
  end
  return info
end

function model.getHostAsLines(attempts)
  if not attempts then
    attempts = 1
  end
  for _ = 1, attempts
  do
    local f = io.open("/var/run/hosts_olsr")
    if f then
      return f:lines()
    end
    nixio.nanosleep(1, 0)
  end
  return string.gmatch("", ".")
end

function model.getServicesAsLines()
  local f = io.open("/var/run/services_olsr")
  if f then
    return f:lines()
  end
  return string.gmatch("", ".")
end

if not aredn then
  aredn = {}
end
aredn.olsr = model;

return model
