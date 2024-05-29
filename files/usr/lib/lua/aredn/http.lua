#!/usr/bin/lua
--[[

  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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
local h = require("socket.http")
local json = require("luci.jsonc")

function fetch_json(url)
  resp, status_code, headers, status_message=h.request(url)
  if status_code==200 then
    local j=json.parse(resp)
    return j
  end
end

http_output = nil

function http_header(disable_compression)
   print "Content-type: text/html\r"
   print "Cache-Control: no-store\r"
   print("Access-Control-Allow-Origin: *\r")
   if not disable_compression then
     local encoding = os.getenv("HTTP_ACCEPT_ENCODING")
     if encoding and encoding:match("gzip") then
      print "Content-Encoding: gzip\r"
      http_output = io.popen("gzip", "w")
    end
   end
   print "\r"
   io.flush()
end

function http_footer()
  if http_output then
    http_output:close()
    http_output = nil
  else
    io.flush()
  end
end

function json_header()
   print("Content-type: application/json\r")
   print("Cache-Control: no-store\r")
   print("Access-Control-Allow-Origin: *\r")
   print("\n")
end

-- Written by RiciLake -- START
-- The author places the code into the public domain, renouncing all rights and responsibilities.
-- Replace + with space and %xx with the corresponding character.

local function cgidecode(str)
  return (str:gsub('+', ' '):gsub("%%(%x%x)", function(xx) return string.char(tonumber(xx, 16)) end))
end

function parsecgi(str)
  local rv = {}
  for pair in str:gmatch"[^&]+" do
    local key, val = pair:match"([^=]*)=(.*)"
    if key then rv[cgidecode(key)] = cgidecode(val) end
  end
  return rv
end
-- Written by RiciLake -- END

function encode_uri_component(str)
  return str:gsub(" ", "%%20"):gsub("%+", "%%2B"):gsub("=", "%%3D")
end
