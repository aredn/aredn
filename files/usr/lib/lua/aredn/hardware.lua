--[[

  Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
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

require("aredn.utils")
require('uci')
local json = require("luci.jsonc")

local hardware = {}

local radio_json = nil
local board_json = nil
local channels_cache = {}
local antennas_cache = {}

function hardware.get_board()
    if not board_json then
        local f = io.open("/etc/board.json")
        if not f then
            return {}
        end
        board_json = json.parse(f:read("*a"))
        f:close()
        -- Collapse virtualized hardware into the two basic types
        if board_json.model.id:match("^qemu%-") then
            board_json.model.id = "qemu"
            board_json.model.name = "QEMU"
        elseif board_json.model.id:lower():match("^vmware") then
            board_json.model.id = "vmware"
            board_json.model.name = "VMware"
        end
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
        radio_json = radios[hardware.get_board_id():lower()]
        if radio_json and not radio_json.name then
            radio_json.name = hardware.get_board_id()
        end
    end
    return radio_json
end

function hardware.get_radio_count()
    local radio = hardware.get_radio()
    if radio and radio.wlan0 then
        if radio.wlan1 then
            return 2
        else
            return 1
        end
    else
        local count = 0
        if nixio.fs.stat("/sys/class/ieee80211") then
            for file in nixio.fs.dir("/sys/class/ieee80211")
            do
                count = count + 1
            end
        end
        return count
    end
end

function hardware.get_radio_intf(wifiintf)
    local radio = hardware.get_radio()
    if radio and radio[wifiintf] then
        return radio[wifiintf]
    else
        return radio
    end
end

function hardware.wifi_maxpower(wifiintf, channel)
    local radio = hardware.get_radio_intf(wifiintf)
    if radio then
        local maxpower = radio.maxpower
        local chanpower = radio.chanpower
        if chanpower then
            for k, v in pairs(chanpower)
            do
                if channel <= tonumber(k) then
                    return tonumber(v)
                end
            end
        end
        maxpower = tonumber(maxpower)
        if maxpower then
            return maxpower
        end
    end
    return 27 -- default
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
    local radio = hardware.get_radio_intf(wifiintf)
    if radio then
        local pwroffset = tonumber(radio.pwroffset)
        if pwroffset then
            return pwroffset
        end
    end
    return 0 -- default
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
    local board = hardware.get_board()
    if board and board.gpioswitch and board.gpioswitch.poe_passthrough and board.gpioswitch.poe_passthrough.pin then
        return true
    end
    -- Handle typo in various config files
    if board and board.gpioswitch and board.gpioswitch.poe_passtrough and board.gpioswitch.poe_passtrough.pin then
        return true
    end
    local _, count = nixio.fs.glob("/sys/class/gpio/enable-poe:*")
    if count > 0 then
        return true
    end
    return false
end

function hardware.has_usb()
    local board = hardware.get_board()
    if board and board.gpioswitch and board.gpioswitch.usb_power_switch and board.gpioswitch.usb_power_switch.pin then
        return true
    end
    local _, count = nixio.fs.glob("/sys/class/gpio/usb-power")
    if count > 0 then
        return true
    end
    return false
end

function hardware.has_wifi()
    if nixio.fs.stat("/sys/kernel/debug/ieee80211/phy0") then
        return true
    else
        return false
    end
end

function hardware.get_rfbandwidths(wifiintf)
    local radio = hardware.get_radio_intf(wifiintf)
    if radio and radio.bandwidths then
        return radio.bandwidths
    end
    return { 5, 10, 20 }
end

function hardware.get_default_channel(wifiintf)
    for _, channel in ipairs(hardware.get_rfchannels(wifiintf))
    do
        if channel.frequency == 912 then
            return { channel = 5, bandwidth = 5, band = "900MHz" }
        end
        local bws = {}
        for _, v in ipairs(hardware.get_rfbandwidths(wifiintf))
        do
            bws[v] = v
        end
        local bw = bws[10] or bws[20] or bws[5] or 0
        if channel.frequency == 2397 then
            return { channel = -2, bandwidth = bw, band = "2.4GHz" }
        end
        if channel.frequency == 2412 then
            return { channel = 1, bandwidth = bw, band = "2.4GHz" }
        end
        if channel.frequency == 3420 then
            return { channel = 84, bandwidth = bw, band = "3GHz" }
        end
        if channel.frequency == 5745 then
            return { channel = 149, bandwidth = bw, band = "5GHz" }
        end
    end
    return nil
end

function hardware.get_rfchannels(wifiintf)
    local channels = channels_cache[wifiintf]
    if not channels then
        channels = {}
        local f = io.popen("iwinfo " .. wifiintf .. " freqlist")
        if f then
            local freq_adjust = 0
            local freq_min = 0
            local freq_max = 0x7FFFFFFF
            if wifiintf == "wlan0" then
                local radio = hardware.get_radio()
                if radio then
                    if radio.name:match("M9") then
                        freq_adjust = -1520;
                        freq_min = 907
                        freq_max = 922
                    elseif radio.name:match("M3") then
                        freq_adjust = -2000;
                        freq_min = 3380
                        freq_max = 3495
                    end
                end
            end
            for line in f:lines()
            do
                local freq, num = line:match("(%d+%.%d+) GHz %(Band: .*, Channel (%-?%d+)%)")
                if freq and not line:match("restricted") and not line:match("disabled") then
                    freq = tonumber("" .. freq:gsub("%.", "")) + freq_adjust
                    if freq >= freq_min and freq <= freq_max then
                        num = tonumber("" .. num:gsub("^0+", ""))
                        channels[#channels + 1] = {
                            label = freq_adjust == 0 and (num .. " (" .. freq .. ")") or (freq),
                            number = num,
                            frequency = freq
                        }
                    end
                end
            end
            f:close()
            channels_cache[wifiintf] = channels
        end
    end
    return channels
end

function hardware.get_antennas(wifiintf)
    local ants = antennas_cache[wifiintf]
    if not ants then
        local radio = hardware.get_radio_intf(wifiintf)
        if radio and radio.antenna then
            if radio.antenna == "external" then
                local dchan = hardware.get_default_channel(wifiintf)
                if dchan and dchan.band then
                    local f = io.open("/etc/antennas.json")
                    if f then
                        ants = json.parse(f:read("*a"))
                        f:close()
                        ants = ants[dchan.band]
                    end
                end
            else
                radio.antenna.builtin = true
                ants = { radio.antenna }
            end
        end
        antennas_cache[wifiintf] = ants
    end
    return ants
end

function hardware.get_antennas_aux(wifiintf)
    local ants = antennas_cache["aux:" .. wifiintf]
    if not ants then
        local radio = hardware.get_radio_intf(wifiintf)
        if radio and radio.antenna_aux == "external" then
            local dchan = hardware.get_default_channel(wifiintf)
            if dchan and dchan.band then
                local f = io.open("/etc/antennas.json")
                if f then
                    ants = json.parse(f:read("*a"))
                    f:close()
                    ants = ants[dchan.band]
                end
            end
        end
        antennas_cache["aux:" .. wifiintf] = ants
    end
    return ants
end

function hardware.get_current_antenna(wifiintf)
    local ants = hardware.get_antennas(wifiintf)
    if ants then
        if #ants == 1 then
            return ants[1]
        end
        local antenna = uci.cursor():get("aredn", "@location[0]", "antenna")
        if antenna then
            for _, ant in ipairs(ants)
            do
                if ant.model == antenna then
                    return ant
                end
            end
        end
    end
    return nil
end

function hardware.get_current_antenna_aux(wifiintf)
    local ants = hardware.get_antennas_aux(wifiintf)
    if ants then
        if #ants == 1 then
            return ants[1]
        end
        local antenna = uci.cursor():get("aredn", "@location[0]", "antenna_aux")
        if antenna then
            for _, ant in ipairs(ants)
            do
                if ant.model == antenna then
                    return ant
                end
            end
        end
    end
    return nil
end

function hardware.supported()
    return hardware.get_radio() and true or false
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
