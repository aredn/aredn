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

local function get_radio_json()
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

local function get_board_json()
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
    local radio = get_radio_json()[get_board_json().model.name]
    if radio then
        if radio.chanpower then
            for k, v in pairs(radio.chanpower)
            do
                if channel <= tonumber(k) then
                    return tonumber(v)
                end
            end
        elseif radio.maxpower then
            return tonumber(radio.maxpower)
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

function hardware.get_rfband()
    local radio = get_radio_json()[get_board_json().model.name]
    if radio then
        return radio.rfband
    else
        return nil
    end
end

function hardware.supported()
    local radio = get_radio_json()[get_board_json().model.name]
    if radio then
        return tonumber(radio.supported)
    else
        return 0
    end
end

function hardware.get_interface_ip4(intf)
    if intf then
        local f = io.popen("ifconfig " .. intf)
        for line in f:lines()
        do
            local ip, bcast, mask = line:match("inet addr:([%d%.]+)%s+Bcast:([%d%.]+)%s+Mask:([%d%.]+)")
            if ip then
                return ip, bcast, mask
            end
        end
        f:close()
    end
end

function hardware.get_interface_mac(intf)
    local mac = ""
    if intf then
        local f = io.popen("ifconfig " .. intf)
        for line in f:lines()
        do
            local m = line:match("HWaddr ([%w:]+)")
            if m then
                mac = m
                break
            end
        end
        f:close()
    end
    return mac
end

if not aredn then
    aredn = {}
end
aredn.hardware = hardware
return hardware
