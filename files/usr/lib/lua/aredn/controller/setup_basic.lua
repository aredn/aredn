#!/usr/bin/lua
--[[

  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2021 Darryl Quinn
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
require("aredn.info")
require("aredn.hardware")
require("aredn.utils")

-- -------------------------------------
-- -- Public API is attached to table
-- -------------------------------------
local module = {}

-- Class constructor (NEW method)
function module:new(req)
  self.req = req
  return self
end

-- Class methods
function module:process()
  local res={}
  
  if self.req['method']=="GET" then
    res = module:GET()
  elseif self.req['method']=="POST" then
    res = module:POST()
  else
    msg="unsupported http method: " .. self.req['method']
    res.msg=msg
    res.success = false
  end
  return res
end

function module:GET()
  local res={}
  local data={}
  data.basic = {}
  data.basic.nodename = aredn.info.getNodeName()
  data.basic.description = aredn.info.getNodeDescription()
  -- password :: "WE CANNOT RETRIEVE THE PASSWORD"

  -- MESHRF
  radio = aredn.info.getMeshRadioDevice()
  data.meshrf = {}
  data.meshrf.ssid_full = aredn.info.getSSID()
  data.meshrf.ssid_prefix = data['meshrf']['ssid_full']:split("-")[1]
  data.meshrf.enabled = aredn.info.isMeshRadioEnabled(radio)
  data.meshrf.ip = aredn.info.getInterfaceIPAddress("wifi")
  data.meshrf.netmask = aredn.info.getInterfaceNetmask("wifi")
  data.meshrf.distance = aredn.info.getMeshRadioDistance(radio)
  data.meshrf.bw = aredn.info.getChannelBW(radio)
  data.meshrf.channel = aredn.info.getChannel(radio)
  data.meshrf.power = aredn.info.getTXPower(radio)
  data.meshrf.maxpower = aredn.hardware.wifi_maxpower(radio, data['meshrf']['channel'])
  

  -- LAN
  data.lan = {}
  data.lan.mode = aredn.info.getLANMode()
  data.lan.dhcp = aredn.info.isLANDHCPEnabled()
  data.lan.ip = aredn.info.getInterfaceIPAddress("lan")
  data.lan.netmask = aredn.info.getInterfaceNetmask("lan")
  -- dhcp_start
  -- dhcp_end

  -- LANAP
  data.lanap = {}

  -- WAN
  data.wan = {}

  -- WAN Advanced
  data.wanadv = {}
  data.wanadv.meshgw = aredn.info.isMeshGatewayEnabled()

  -- WAN Wifi Client
  data.wanclient = {}

  res.data=data
  res.errors = {}
  res.success = true
  return res
end

function module:POST()
  local res={}
  local errors = {}
  local e = {}
  
  -- STORE DATA --
  -- node name (to uci)
  local nodename = self.req.content.data.nodename
  local description = self.req.content.data.description
  local passwd = self.req.content.data.password

  local cursor = uci.cursor()

  -- PERFORM any CROSS-VALUE validation
  -- (ie. if 2Ghz radio is configured for MESH, don't allow 2Ghz radio for AP Client, etc)


  e = module:save_nodename(nodename)
  if next(e)~=nil then table.insert(errors, e) end
  
  e = module:save_description(description)
  if next(e)~=nil then table.insert(errors, e) end
  
  -- password
  e = module:save_password(passwd)
  if next(e)~=nil then table.insert(errors, e) end
  
  -- -- UCI commit
  if #errors==0 then
    -- TODO: change to optimal commit
    -- cursor:commit("hsmmmesh")
    -- cursor:commit("system")
    rc = os.execute("uci -q -c /etc/local/uci/ commit")
    if (rc ~= 0) then
      e = {}
      e.name="setup_basic"
      e.msg="uci commit error: " .. rc
      table.insert(errors, e)
    end
  end

  res.errors = errors
  res.success = (#errors==0 and true or false)
  if res.success then res.restart = true end
  return res
end

-- ---------------
-- SAVE FUNCTIONS
-- ---------------
function module:save_nodename(nodename)
  local e = {}
  -- validations
  if (nodename == "") then
    e.name = "nodename"
    e.msg = "field cannot be empty"
  else
    -- local cursor = uci.cursor()
    cursor:set("hsmmmesh", "settings", "node", nodename)
    
    -- local rc = os.execute("uci -q -c /etc/local/uci/ set hsmmmesh.settings.node='" .. nodename .. "'")
    --if (rc ~= 0) then
    --  e.name="nodename"
    --  e.msg="error setting uci value"
    --end
  end
  return e
end

function module:save_description(description)
  local e = {}
  -- validations
  local rc = os.execute("uci -q set system.@system[0].description='" .. description .. "'")
  if (rc ~= 0) then
    e.name="description"
    e.msg="error setting uci value " .. rc
  end
  return e
end

function module:save_password(password)
  local e = {}
  local rc = nil
  -- validations
  if password then
    rc = os.execute("/usr/local/bin/setpasswd '"  .. password .. "' >/dev/null 2>&1")
  end
  if (rc ~= 0) then
    e.name="password"
    e.msg="error setting password " .. rc
  end
  return e
end


return module
