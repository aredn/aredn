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
  end
  return res
end


function module:GET()
  local res={}
  msg="SetupOptional:GET()"
  res['msg']=msg
  res['success']=true
  return res
end

function module:POST()
  local res={}
  msg="SetupOptional:POST()"
  res['msg']=msg
  res['success']=true
  return res
end

function module:PUT()
  local res={}
  msg="unsupported method"
  res['msg']=msg
  res['success']=false
  return res
end

function module:DELETE()
  local res={}
  msg="unsupported method"
  res['msg']=msg
  res['success']=false
  return res
end

return module