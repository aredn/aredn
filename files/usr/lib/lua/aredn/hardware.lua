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

require("aredn.utils")
require('uci')
local json = require("luci.jsonc")

local hardware = {}

local radio_json = nil
local board_json = nil

function hardware.get_board()
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

function hardware.get_radio()
    if not radio_json then
        local f = io.open("/etc/radios.json")
        if not f then
            return {}
        end
        local radios = json.parse(f:read("*a"))
        f:close()
        radio_json = radios[hardware.get_board_id()]
    end
    return radio_json
end

function hardware.wifi_maxpower(channel)
    local radio = hardware.get_radio()
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

function hardware.wifi_poweroffset(wifiintf)
    local doesiwoffset = nil
    local f = io.popen("iwinfo " .. wifiintf .. " info")
    if f then
        for line in f:lines()
        do
            doesiwoffset = tonumber(line:match("TX power offset: (%d+)"))
            if doesiwoffset then
                f:close()
                return doesiwoffset
            end
        end
        f:close()
    end
    local radio = hardware.get_radio()
    if radio and tonumber(radio.pwroffset) then
         return tonumber(radio.pwroffset)
    end
    return 0 -- if all else fails
end

function hardware.get_board_id()
    local name = ""
    if hardware.get_board().model.name:match("^(%S*)") == "Ubiquiti" then
        name = read_all("/sys/devices/pci0000:00/0000:00:00.0/subsystem_device")
        if not name or name == "" or name == "0x0000" then
            name = "0x" .. capture([[dd if=/dev/mtd7 bs=1 skip=12 count=2 2>/dev/null | hexdump -v -n 4 -e '1/1 "%02x"']])
        end
    end
    if not name or name == "" or name == "0x0000" then
        name = hardware.get_board().model.name
    end
    return name:chomp()
end

function hardware.get_board_type()
    return hardware.get_board().model.id
end

function hardware.get_board_network_ifname(type)
    local network = hardware.get_board().network[type]
    if network then
        if network.ifname then
            return network.ifname
        end
        if network.device then
            return network.device
        end
        if network.ports then
            return table.concat(network.ports, " ")
        end
    end
    return ""
end

function hardware.get_type()
    local id = hardware.get_board().model.id
    local type = id:match(",(.*)")
    if type then
        return type
    end
    return id
end

function hardware.get_manufacturer()
    local name = hardware.get_board().model.name
    local man = name:match("(%S*)%s")
    if man then
        return man
    end
    return name
end

function hardware.get_iface_name(name)
    local cursor = uci.cursor()
    local type = cursor:get("network", name, "type")
    if type and type == "bridge" then
        return "br-" .. name
    end
    local intfname = cursor:get("network", name, "ifname")
    if intfname then
        return intfname:match("^(%S+)")
    end
    local device = cursor:get("network", name, "device")
    if device then
        return device
    end
    -- Now we guess
    if name == "lan" then
        return "eth0"
    end
    if name == "wan" then
        return "eth0.1"
    end
    if name == "wifi" then
        return "wlan0"
    end
    if name == "dtdlink" then
        return "eth0.2"
    end
    -- Maybe the board knows
    return hardware.get_board().network[name].ifname:match("^(%S+)")
end

function hardware.get_bridge_iface_names(name)
    local cursor = uci.cursor()
    local intfnames = cursor:get("network", name, "ifname")
    if intfnames then
        return intfnames
    end
    -- Now we guess
    if name == "lan" then
        return "eth0"
    end
    if name == "wan" then
        return "eth0.1"
    end
    if name == "wifi" then
        return "wlan0"
    end
    if name == "dtdlink" then
        return "eth0.2"
    end
    -- Maybe the board knows
    return hardware.get_board().network[name].ifname
end

function hardware.get_link_led()
    local err, result = xpcall(
        function()
            local led = hardware.get_board().led
            if led then
                if led.rssilow and led.rssilow.sysfs then
                    return "/sys/class/leds/" .. led.rssilow.sysfs
                end
                if led.user and led.user.sysfs then
                    return "/sys/class/leds/" .. led.user.sysfs
                end
            end
            return nil
        end,
        function()
            return nil
        end
    )
    return result
end

function hardware.has_poe()
    local err, result = xpcall(
        function() return hardware.get_board().gpioswitch.poe_passthrough.pin or true end,
        function() return false end
    )
    return result
end

function hardware.has_usb()
    local err, result = xpcall(
        function() return hardware.get_board().gpioswitch.usb_power_switch.pin or true end,
        function() return false end
    )
    return result
end

function hardware.get_rfband()
    local radio = hardware.get_radio()
    if radio then
        return radio.rfband
    else
        return nil
    end
end

function hardware.get_rfbandwidths()
    local radio = hardware.get_radio()
    if radio.rfbandwidths then
        return radio.rfbandwidths
    else
        return { 5, 10, 20 }
    end
end

function hardware.get_default_channel()
    local radio = hardware.get_radio()
    if radio.rfband == "900" then
        return { channel = 5, bandwidth = 5 }
    end
    local w = {}
    for _, width in ipairs(hardware.get_rfbandwidths())
    do
        w[width] = true
    end
    local width = w[10] and 10 or w[5] and 5 or 20
    if radio.rfband == "2400" then
        return { channel = -2, bandwidth = width }
    elseif radio.rfband == "3400" then
        return { channel = 84, bandwidth = width }
    elseif radio.rfband == "5800ubntus" then
        return { channel = 149, bandwidth = width }
    else
        return nil
    end
end

function hardware.supported()
    local radio = hardware.get_radio()
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
                f:close()
                return ip, bcast, mask
            end
        end
        f:close()
    end
end

function hardware.get_interface_mac(intf)
    local mac = ""
    if intf then
        local f = io.popen("ifconfig " .. intf .. " 2>/dev/null")
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
