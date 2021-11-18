--[[

  Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
  Copyright (C) 2021 Tim Wilkinson
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

local json = require("luci.jsonc")

local hardware = {}

local radio_json = nil
local board_json = nil

function get_radio_json()
    if not radio_json then
        local f = io.open("/etc/radios.json")
        if not f then
            return {}
        end
        radio_json = json.parse(f:read("*a"))
        f:close()
    end
    return radio_json
end

function get_board_json()
    if not board_json then
        local f = io.open("/etc/board.json")
        if not f then
            return {}
        end
        board_json = json.parse(f:read("*a"))
        f:close()
    end
    return board_json
end

function hardware.wifi_maxpower(channel)
    local board = get_radio_json()[name]
    if board then
        if board.chanpower then
            for k, v in pairs(board.chanpower)
            do
                if channel <= tonumber(k) then
                    return tonumber(v)
                end
            end
        elseif board.maxpower then
            return tonumber(board.maxpower)
        end
    end
    return 27 -- if all else fails
end


function hardware.get_board_type()
    return get_board_json().model.id
end

function hardware.get_iface_name(name)
    return get_board_json().network[name].ifname
end

function hardware.get_link_led()
    return "/sys/class/leds/" .. get_board_json().led.rssilow.sysfs
end

function get_interface_mac(intf)
    local mac = ""
    if intf then
        for i, line in ipairs(utils.system_run("ifconfig " .. intf))
        do
            local m = line:match("HWaddr ([%w:]+)")
            if m then
                mac = m
                break
            end
        end
    end
    return mac
end

return hardware
