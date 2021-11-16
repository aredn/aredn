#!/usr/bin/lua
--[[

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
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
local aredn_info = require("aredn.info")
require("aredn.utils")

-- -------------------------------------
-- -- Public API is attached to table
-- -------------------------------------
local module = {}

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
    res['msg']=msg
    res['success']=false
  end
  return res
end

function module:GET()
  local res={}
  local data={}
  data['nodename']=aredn_info.getNodeName()
  data['description']=aredn_info.getNodeDescription()
  -- data['password']="WE CANNOT RETRIEVE THE PASSWORD"

  -- MESHRF
  -- enabled, ip, mask, distance, power, channel, bw
  data['ssid_full'] = aredn_info.getSSID()
  data['ssid_prefix'] = data['ssid_full']:split("-")[1]



  res['data']=data
  res['errors'] = {}
  res['success']=true
  return res
end

function module:POST()
  local res={}
  local errors = {}
  local e = {}
  
  -- STORE DATA --
  -- node name (to uci)
  local nodename = self.req['content']['data']['nodename']
  e = module:save_nodename(nodename)
  if next(e)~=nil then table.insert(errors, e) end
  
  -- node description
  local description = self.req['content']['data']['description']
  e = module:save_description(description)
  if next(e)~=nil then table.insert(errors, e) end
  
  -- password
  local passwd = self.req['content']['data']['password']
  e = module:save_password(passwd)
  if next(e)~=nil then table.insert(errors, e) end
  
  -- -- UCI commit
  if #errors==0 then
    rc = os.execute("uci -q -c /etc/local/uci/ commit")
    if (rc ~= 0) then
      e = {}
      e.name="setup_basic"
      e.msg="uci commit error: " .. rc
      table.insert(errors, e)
    end
  end

  res['errors'] = errors
  res['success']= (#errors==0 and true or false)
  if res['success'] then res['restart'] = true end
  return res
end

function module:save_nodename(nodename)
  local e = {}
  if (nodename == "") then
    e.name = "nodename"
    e.msg = "field cannot be empty"
  else
    local rc = os.execute("uci -q -c /etc/local/uci/ set hsmmmesh.settings.node='" .. nodename .. "'")
    if (rc ~= 0) then
      e.name="nodename"
      e.msg="error setting uci value"
    end
  end
  return e
end

function module:save_description(description)
  local e = {}
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