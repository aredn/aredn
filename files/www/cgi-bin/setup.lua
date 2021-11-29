#!/usr/bin/lua
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
	version

--]]

require("nixio")
require("aredn.http")
require("aredn.utils")
require("aredn.hardware")
require("uci")
require('luci.http')
require('luci.sys')
local html = require("aredn.html")
local aredn_info = require("aredn.info")

local errors = {}
local output = {}
local hidden = {}

-- helpers start

local rf_channel_map = {
    ["900"] = {},
    ["2400"] = {},
    ["3400"] = {},
    ["5500"] = {},
    ["5800ubntus"] = {}
}
for i = 4,7
do
    rf_channel_map["900"][i - 3] = { label = i .. " (" .. (887 + i * 5) .. ")", number = i, frequency = 887 + i * 5 }
end
for i = -2,11
do
    rf_channel_map["2400"][i + (i <= 0 and 2 or 1)] = { label = i .. " (" .. (2407 + i * 5) .. ")", number = i, frequency = 2407 + i * 5 }
end
for i = 76,99
do
    rf_channel_map["3400"][i - 75] = { label = i .. " (" .. (3000 + i * 5) .. ")", number = i, frequency = 3000 + i * 5 }
end
for i = 36,64,4
do
    rf_channel_map["5500"][(i - 32) / 4] = { label = i .. " (" .. (5000 + i * 5) .. ")", number = i, frequency = 5000 + i * 5 }
end
for i = 100,140,4
do
    rf_channel_map["5500"][(i - 64) / 4] = { label = i .. " (" .. (5000 + i * 5) .. ")", number = i, frequency = 5000 + i * 5 }
end
for i = 149,165,4
do
    rf_channel_map["5500"][(i - 69) / 4] = { label = i .. " (" .. (5000 + i * 5) .. ")", number = i, frequency = 5000 + i * 5 }
end
for i = 131,184
do
    rf_channel_map["5800ubntus"][i - 130] = { label = i .. " (" .. (5000 + i * 5) .. ")", number = i, frequency = 5000 + i * 5 }
end

function capture_and_match(cmd, pattern)
    local f = io.popen(cmd)
    if f then
        for line in f:lines()
        do
            local r = line:match(pattern)
            if r then
                return r
            end
        end
        f:close()
    end
end

function rf_channels_list(wifiintf)
    local channels = {}
    local rfband = aredn.hardware.get_rfband()
    if rfband and rf_channel_map[rfband] then
        return rf_channel_map[rfband]
    else
        local f = io.popen("iwinfo " .. wifiintf .. " freqlist")
        if f then
            for line in f:lines()
            do
                local freq, num = line:match("(%d+%.%d+) GHz %(Channel (%d+)%)")
                if freq and not line:match("restricted") then
                    freq = freq:gsub("%.", "")
                    num = num:gsub("^0+", "")
                    channels[#channels + 1] = {
                        label = num .. " (" .. freq .. ")",
                        number = tonumber(num),
                        frequency = freq
                    }
                end
            end
            f:close()
        end
    end
    return channels
end

function wifi_txpoweroffset(wifiintf)
    local doesiwoffset = capture_and_match("iwinfo " .. wifiintf .. " info", "TX power offset: (%d+)")
    if doesiwoffset then
        return tonumber(doesiwoffset)
    end
    return 0
end

function reboot()
    local node = aredn_info.get_nvram("node")
    if node == "" then
        node = "Node"
    end
    local lanip, _, lanmask = aredn.hardware.get_interface_ip4(aredn.hardware.get_iface_name("lan"))
    local browser = os.getenv("REMOTE_ADDR"):match("::ffff:([%d%.]+)")
    local fromlan = false
    local subnet_change = false
    if lanip then
        fromlan = validate_same_subnet(browser, lanip, lanmask)
        if fromlan then
            lanmask = ip_to_decimal(lanmask)
            local cfgip = cursor_get("network", "lan", "ipaddr")
            local cfgmask = ip_to_decimal(cursor_get("network", "lan", "netmask"))
            if lanmask ~= cfgmask or decimal_to_ip(nixio.bit.band(ip_to_decimal(ip), lanmask)) ~= nixio.bit.band(ip_to_decimal(cfgip), cfgmask) then
                subnet_change = true
            end
        end
    end
    http_header()
    if fromlan and subnet_change then
        html.header(node .. " rebooting", true);
        html.print("<body><center>")
        html.print("<h1>" .. node .. " is rebooting</h1><br>")
        html.print("<h3>The LAN subnet has changed. You will need to acquire a new DHCP lease<br>")
        html.print("and reset any name service caches you may be using.</h3><br>")
        html.print("<h3>When the node reboots you get your new DHCP lease and reconnect with<br>")
        html.print("<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>or<br>")
        html.print("<a href='http://" .. node .. ".local.mesh:8080/'>http://" .. node .. ".local.mesh:8080/</a></h3>")
    else
        html.header(node .. " rebooting", false)
        html.print("<meta http-equiv='refresh' content='60;url=/cgi-bin/status.lua'>")
        html.print("</head><body><center>")
        html.print("<h1>" .. node .. " is rebooting</h1><br>")
        html.print("<h3>Your browser should return to this node in 60 seconds.</br><br>")
        html.print("If something goes astray you can try to connect with<br><br>")
        html.print("<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>")
        if node ~= "Node" then
            html.print("or<br><a href='http://" .. node .. ".local.mesh:8080/'>http://" .. node .. ".local.mesh:8080/</a></h3>")
        end
    end
    html.print("</center></body></html>")
    http_footer()
    luci.sys.reboot()
    os.exit()
end

function err(str)
    errors[#errors + 1] = str
end

function out(str)
    output[#output + 1] = str
end

-- helper end

-- timezones
local tz_db_names = {}
for line in io.lines("/etc/zoneinfo")
do
    local name, _ = line:match("^(.*)\t")
    tz_db_names[#tz_db_names + 1] = { tz = name, name = name }
end

-- online ping
local pingOK = false
if capture_and_match("ping -W1 -c1 8.8.8.8", "1 packets received") then
    pingOK = true
end

local dmz_lan_ip = ""
local dmz_lan_mask = ""
local lan_gw = ""
local wan_ip = ""
local wan_mask = ""
local wan_gw = ""
local passwd1 = ""
local passwd2 = ""

local ctwo = { 1,2,3,4,5,6,7,8,9,10,11 }
local cfive = { 36,40,44,48,149,153,157,161,165 }

local wifiintf = aredn.hardware.get_iface_name("wifi")
local phy = iwinfo.nl80211.phyname(wifiintf)
local phycount = tonumber(capture("ls -1d /sys/class/ieee80211/* | wc -l"):chomp())

-- uci cursor
local cursora = uci:cursor()
local cursorb = uci:cursor("/etc/config.mesh")
function cursor_set(a, b, c, d)
    cursora:set(a, b, c, d)
    cursorb:set(a, b, c, d)
    cursora:commit(a)
    cursorb:commit(a)
end

function cursor_get(a, b, c)
    return cursora:get(a, b, c)
end

-- post_data
local parms = {}
local has_parms = false
if os.getenv("REQUEST_METHOD") == "POST" then
    local request = luci.http.Request(luci.sys.getenv(),
      function()
        local v = io.read(1024)
        if not v then
            io.close()
        end
        return v
      end
    )
    parms = request:formvalue()
    for _,_ in pairs(parms)
    do
        has_parms = true
        break
    end
end

if parms.button_uploaddata then
    -- fix me
end

if parms.button_default then
    local node = aredn_info.get_nvram("node")
    local mac2 = mac_to_ip(aredn.hardware.get_interface_mac(aredn.hardware.get_iface_name("wifi")), 0)
    local dtdmac = mac_to_ip(aredn.hardware.get_interface_mac(aredn.hardware.get_iface_name("lan")), 0)
    for line in io.lines("/etc/config.mesh/_setup.default")
    do
        if not (line:match("^%s*#") or line:match("^%s*$")) then
            line = line:gsub("<NODE>", node):gsub("<MAC2>", mac2):gsub("<DTDMAC>", dtdmac)
            local k, v = line:match("^([^%s]*)%s*=%s*(.*)%s*$")
            _G[k] = v
        end
    end
else
    for k, v in pairs(parms)
    do
        if k:match("^%w+") then
            v = v:gsub("^%s+", ""):gsub("%s+$", "")
            _G[k] = v
        end
    end
    if parms.button_reset or not has_parms then
        for line in io.lines("/etc/config.mesh/_setup")
        do
            if not (line:match("^%s*#") or line:match("^%s*$")) then
                local k, v = line:match("^([^%s]*)%s*=%s*(.*)%s*$")
                _G[k] = v
            end
        end
        local function h2s(hex)
            local s = ""
            for i = 1,#hex,2
            do
                s = s .. string.char(tonumber(hex:sub(i, i+1), 16))
            end
            return s
        end
        wifi2_key = h2s(wifi2_key)
        wifi2_ssid = h2s(wifi2_ssid)
        wifi3_key = h2s(wifi3_key)
        wifi3_ssid = h2s(wifi3_ssid)
    end
end

local nodetac
if parms.button_reset or parms.button_default or (not nodetac and not has_parms) then
    nodetac = aredn_info.get_nvram("node")
    tactical = aredn_info.get_nvram("tactical")
    if tactical ~= "" then
        nodetac = nodetac .. " / " .. tactical
    end
else
    nodetac = parms.nodetac
end

local d0 = { "lan_dhcp", "olsrd_bridge", "olsrd_gw", "wifi2_enable", "lan_dhcp_noroute", "wifi_enable", "wifi3_enable" }
for _, k in ipairs(d0)
do
    if not parms[k] then
        parms[k] = "0"
    end
end

-- lan is always static
local lan_proto = "static"

-- enforce direct mode settings
-- (formerly known as dmz mode)
dmz_mode = tonumber(dmz_mode)
if dmz_mode ~= 0 and dmz_mode < 2 then
    dmz_mode = 2
elseif dmz_mode > 5 then
    dmz_mode = 5
end

if dmz_mode ~= 0 then
    local ipshift = (ip_to_decimal(wifi_ip) * math.pow(2, dmz_mode)) % 0x1000000
    local a, b = decimal_to_ip(ipshift):match("(%d+%.%d+%.%d+%.)(%d+)")
    dmz_lan_ip = "1" .. a .. (tonumber(b) + 1)
    dmz_lan_mask = decimal_to_ip((0xffffffff * math.pow(2, dmz_mode)) % 0x100000000)
    local octet = dmz_lan_ip:match("%d+%.%d+%.%d+%.(%d+)")
    dmz_dhcp_start = octet + 1
    dmz_dhcp_end = dmz_dhcp_start + math.pow(2, dmz_mode) - 4;
    parms.dmz_lan_ip = dmz_lan_ip
    parms.dmz_lan_mask = dmz_lan_mask
    parms.dmz_dhcp_start = dmz_dhcp_start
    parms.dmz_dhcp_end = dmz_dhcp_end
end

parms.dhcp_limit = dhcp_end - dhcp_start + 1
parms.dmz_dhcp_limit = dmz_dhcp_end - dmz_dhcp_start + 1

-- get the active wifi settings on a fresh page load
if not parms.reload then
    wifi_txpower = tonumber(capture_and_match("iwinfo " .. wifiintf .. " info", "Tx%-Power: (%d+)"))
    local doesiwoffset = capture_and_match("iwinfo " .. wifiintf .. " info", "TX power offset: (%d+)")
    if doesiwoffset then
        wifi_txpower = wifi_txpower - tonumber(doesiwoffset)
    end
end

-- sanitize the active settings
if not wifi_txpower or tonumber(wifi_txpower) > aredn.hardware.wifi_maxpower(wifi_channel) then
    wifi_txpower = aredn.hardware.wifi_maxpower(wifi_channel)
end
if not wifi_power or wifi_power < 1 then
    wifi_power = 1
end
if not wifi_distance then
    wifi_distance = 0
end
if tostring(wifi_distance):match("%D") then
    wifi_distance = 0
end

-- stuff the sanitized data back into the parms tables
-- so they get saved correctly
parms.wifi_distance = wifi_distance
parms.wifi_txpower = wifi_txpower

-- apply the wifi settings
if (parms.button_apply or parms.button_save) and wifi_enable then
    if wifi_distance == 0 then
        os.execute("iw phy " .. phy .. " set distance auto")
    else
        os.execute("iw phy " .. phy .. " set distance " .. wifi_distance)
    end
    os.execute("iw dev " .. wifiintf .. " set tx power fixed " .. wifi_txpower .. "00")
end

if parms.button_upodatelocation then
    -- process gridsquare
    if parms.gridsquare then
        if parms.gridsquare:match("^[A-Z][A-Z]%d%d[a-z][a-z]$") then
            cursor_set("aredn", "@location[0]", "gridsquare", parms.gridsquare)
            out("Gridsquare updated.")
        else
            err("ERROR: Gridsquare format is: 2-uppercase letters, 2-digits, 2-lowercase letters. (AB12cd)")
        end
    else
        cursor_set("aredn", "@location[0]", "gridsquare", "")
        out("Gridsquare purged.")
    end

    -- process lat/lng
    if parms.latitude and parms.longitude then
        if parms.latitude:match("^[-+]?%d%d?%.%d+$") and parms.longitude:match("^[-+]?%d%d?%d?%.%d+$") then
            if tonumnber(parms.latitude) >= -90 and tonumber(parms.latitude) <= 90 and tonumber(parms.longitude) >= -180 and tonumber(parms.longitude) <= 180 then
                cursor_set("aredn", "@location[0]", "lat", parms.latitude)
                cursor_set("aredn", "@location[0]", "lon", parms.longitude)
                out("Lat/lon updated.")
            else
                err("ERROR: Lat/lon values must be between -90/90 and -180/180, respectively.")
            end
        else
            err("ERROR: Lat/lon format is decimal: (ex. 30.121456 or -95.911154).")
        end
    else
        cursor_set("aredn", "@location[0]", "lat", "")
        cursor_set("aredn", "@location[0]", "lon", "")
        out("Lat/lon purged.")
    end
end

-- retrieve location data
lat = cursor_get("aredn", "@location[0]", "lat")
if not lat then
    lat = ""
end
lon = cursor_get("aredn", "@location[0]", "lon")
if not lon then
    lon = ""
end
gridsquare = cursor_get("aredn", "@location[0]", "gridsquare")
if not gridsquare then
    gridsquare = ""
end

-- validate and save configuration
if parms.button_save then
    for _,zone in ipairs(tz_db_names)
    do
        if zone.tz == time_zone_name then
            parms.time_zone = zone.name
            break
        end
    end

    if not validate_netmask(wifi_mask) then
        err("invalid Mesh netmask")
    elseif not validate_ip_netmask(wifi_ip, wifi_mask) then
        err("invalid Mesh IP address")
    end

    if #wifi_ssid > 32 then
        err("invalid Mesh RF SSID")
    end

    if not is_channel_valid(wifi_channel) then -- fix me
        err("invalid Mesh RF channel")
    end
    if not is_wifi_chanbw_valid(wifi_chanbw, wifi_ssid) then
        err("Invalid Mesh RF channel width")
        wifi_chanbw = 20
    end

    local wifi_country_validated = false
    local countries = { "00","HX","AD","AE","AL","AM","AN","AR","AT","AU","AW","AZ","BA","BB","BD","BE","BG","BH","BL","BN","BO","BR","BY","BZ","CA","CH","CL","CN","CO","CR","CY","CZ","DE","DK","DO","DZ","EC","EE","EG","ES","FI","FR","GE","GB","GD","GR","GL","GT","GU","HN","HK","HR","HT","HU","ID","IE","IL","IN","IS","IR","IT","JM","JP","JO","KE","KH","KP","KR","KW","KZ","LB","LI","LK","LT","LU","LV","MC","MA","MO","MK","MT","MY","MX","NL","NO","NP","NZ","OM","PA","PE","PG","PH","PK","PL","PT","PR","QA","RO","RS","RU","RW","SA","SE","SG","SI","SK","SV","SY","TW","TH","TT","TN","TR","UA","US","UY","UZ","VE","VN","YE","ZA","ZW" }
    for _,country in ipairs(countries)
    do
        if country == wifi_country then
            wifi_country_validated = true
            break
        end
    end
    if not wifi_country_validated then
        wifi_country = "00"
        err("Invalid country")
    end

    if lan_proto == "static" then
        if validate_netmask(lan_mask) then
            err("invalid LAN netmask")
        elseif not lan_mask:match("^255%.255%.255%.") then
            err("LAN netmask must begin with 255.255.255")
        elseif not validate_ip_netmask(lan_ip, lan_mask) then
            err("invalid LAN IP address")
        else
            if lan_dhcp ~= "" then
                local start_addr = change_ip_address(lan_ip, dhcp_start)
                local end_addr = change_ip_address(lan_ip, dhcp_end)

                if not (validate_ip_netmask(start_addr, lan_mask) and validate_same_subnet(start_addr, lan_ip, lan_mask)) then
                    err("invalid DHCP start address")
                end
                if not (validate_ip_netmask(end_addr, lan_mask) and validate_same_subnet(end_addr, lan_ip, lan_mask)) then
                    err("invalid DHCP end address")
                end
                if dhcp_start > dhcp_end then
                    err("invalid DHCP start/end addresses")
                end
            end
            if lan_gw ~= "" and not (validate_ip_netmask(lan_gw, lan_mask) and validate_same_subnet(lan_ip, lan_gw, lan_mask)) then
                err("invalid LAN gateway")
            end
        end
    end

    if wan_proto == "static" then
        if not validate_netmask(wan_mask) then
            err("invalid WAN netmask")
        elseif validate_ip_netmask(wan_ip, wan_mask) then
            err("invalid WAN IP address")
        elseif not (validate_ip_netmask(wan_gw, wan_mask) and validate_same_subnet(wan_ip, wan_gw, wan_mask)) then
            err("invalid WAN gateway")
        end
    end

    if not validate_ip(wan_dns1) then
        err("invalid WAN DNS 1")
    end
    if wan_dns2 ~= '' and not validate_ip(wan_dns2) then
        err("invaliud WAN DNS 2")
    end

    if passwd1 ~= "" or passwd2 ~= "" then
        if passwd1 ~= passwd2 then
            err("passwords do not match")
        end
        if passwd1:match("#") then
            err("passwords cannot contain '#'")
        end
        if passwd1 == "hsmm" then
            err("password must be changed")
        end
    elseif nixio.fs.stat("/etc/config/unconfigured") then
        err("password must be changed during initial configuration")
    end

    if nodetac:match("/") then
        node, tactical = nodetac:match("^%s*([%w-]+)%s*/%s*([%w-])%s*$")
        if tactical == "" then
            err("invalid node/tactical name")
        end
    else
        node = nodetac
        tactical = ""
        if node == "" then
            err("you must set the node name")
        end 
    end
    if node ~= "" and node:match("[^%w-]") or node.match("_") then
        err("invalid node name")
    end
    if tactical:match("[^%w-]") or tactical.match("_") then
        err("invalid tactical name")
    end

    if not validate_fqdn(ntp_server) then
        err("invalid ntp server")
    end

    if wifi2_enable == "1" then
        if #wifi2_ssid > 32 then
            err("LAN Access Point SSID musr be 32 or less characters")
        end
        if #wifi2_key < 8 or #wifi2_key > 64 then
            err("LAN Access Point Password must be at least 8 characters, up to 64")
        end
        if wifi2_key:match("'") or wifi2_ssid:match("'") then
            err("The LAN Access Point password and ssid may not contain a single quote character")
        end
        if wifi2_channel < 30 and wifi2_hwmode == "11a" then
            err("Changed to 5GHz Mesh LAN AP, please review channel selection")
        end
        if wifi2_channel > 30 and wifi2_hwmode == "11g" then
            err("Changed to 2GHz Mesh LAN AP, please review channel slection")
        end
    end
    if wifi3_enable == "1" then
        if #wifi3_key < 8 or #wifi3_key > 64 then
            err("WAN Wifi Client Password must be between 8 and 64 characters")
        end
        if wifi3_key:match("'") or wifi3_ssid:match("'") then
            err("The WAN Wifi Client password and ssid may not contain a single quote character")
        end
    end

    if phycount > 1 and wifi_enable == "1" and wifi2_channel < 36 and wifi2_enable == "1" then
        err("Mesh RF and LAN Access Point can not both use the same wireless card, review LAN AP settings")
    end
    if phycount > 1 and wifi_enable == "0" and wifi2_hwmode == wifi3_hwmode then
        err("Some settings auto updated to avoid conflicts, please review and save one more time")
    end
    if wifi_enable == "1" and wifi2_enable == "1" and wifi3_enable == "1" then
        err("Can not enable Mesh RF, LAN AP, and WAN Wifi Client with only 2 wireless cards, WAN Wifi Client turned off")
        wifi2_enable = "0"
    end
    if phycount == 1 and wifi_enable == "1" and (wifi2_enable == "1" or wifi3_enable == "1") then
        err("Can not enable Mesh RF along with LAN AP or WAN Wifi Client. Only Mesh RF enabled now, please review settings.")
        wifi2_enable = "0"
        wifi3_enable = "0"
    end

    if #errors == 0 then
        parms.node = node
        parms.tactical = tactical
        if nixio.fs.stat("/etc/config/unconfigured") then
            os.remove("/etc/config/unconfigured")
        end
        local function s2h(str)
            local h = ""
            for i = 1,#str
            do
                h = h .. string.format("%02x", string.byte(str, i))
            end
            return h
        end
        parms.wifi2_key = s2h(wifi2_key)
        parms.wifi2_ssid = s2h(wifi2_ssid)
        parms.wifi3_key = s2h(wifi3_key)
        parms.wifi3_ssid = s2h(wifi3_ssid)

        -- save_setup
        local f = io.open("/etc/config.mesh/_setup", "w")
        if f then
            for k, v in parms
            do
                if k:match("^aprs_") or k:match("^dhcp_") or k:match("^dmz_") or k:match("^lan_") or k:match("^olsrd_") or k:match("^wan_") or k:match("^wifi_") or k:match("^wifi2_") or k:match("^wifi3_") or k:match("^dtdlink_") or k:match("^ntp_") or k:match("^time_") or k:match("^description_") then
                    f:write(k .. " = " .. v .. "\n")
                end
            end
            f:close()
        end
        aredn_info.set_nvram("node", parms.node);
        aredn_info.set_nvram("tactical", parms.tactical)
        aredn_info.set_nvram("config", parms.config)
        
        if not nixio.fs.stat("/tmp/web/save") then
            nixio.fs.mkdir("/tmp/web/save")
        end
        os.execute("/usr/local/bin/node-setup.lua -a " .. parms.config .. " > /tmp/web/save/node-setup.out")
        if nixio.fs.stat("/tmp/web/save/node-setup.out", "size") > 0 then
            err(read_all("/tmp/web/save/node-setup.out"))
        else
            remove_all("/tmp/web/save")
            -- set password
            if passwd1 ~= "" then
                local pw = passwd1.gsub("'", "\\'")
                local f = io.popen("{ echo '" .. pw .. "'; sleep 1; echo '" .. pw .. "'; } | passwd")
                f:read("*a")
                f:close()
            end 
            io.open("/tmp/reboot-required", "w"):close()
        end
        if nixio.fs.stat("/tmp/unconfigured") and #errors == 0 then
            reboot()
        end
    end
end

remove_all("/tmp/web/save")
if parms.button_reboot then
    reboot()
end

local desc = cursor_get("system", "@system[0]", "description")
if not desc then
    desc = ""
end
local maptiles = cursor_get("aredn", "@map[0]", "maptiles")
if not maptiles then
    maptiles = ""
end
local leafletcss = cursor_get("aredn", "@map[0]", "leafletcss")
if not leafletcss then
    leafletcss = ""
end
local leafletjs = cursor_get("aredn", "@map[0]", "leafletjs")
if not leafletjs then
    leafletjs = ""
end

-- generate page

http_header()
html.header(aredn_info.get_nvram("node") .. " setup", false)

html.print([[
 <script>

function loadCSS(url, callback) {
   var head = document.getElementsByTagName('head')[0];
   var stylesheet = document.createElement('link');
   stylesheet.rel = 'stylesheet';
   stylesheet.type = 'text/css';
   stylesheet.href = url;
   stylesheet.onload = callback;

   head.appendChild(stylesheet);
}  

function loadScript(url, callback) {
   var head = document.getElementsByTagName('head')[0];
   var script = document.createElement('script');
   script.type = 'text/javascript';
   script.src = url;
   script.onload = callback;

   head.appendChild(script);
}

var map;
var marker;

var leafletLoad = function() {
    map = L.map('map').setView([0.0, 0.0], 1);
    var dotIcon = L.icon({iconUrl: '/dot.png'});
]])
html.print("L.tileLayer('" .. maptiles .. "',")
html.print([[
    {
        maxZoom: 18,
        attribution: 'Map data &copy; <a href="http://openstreetmap.org">OpenStreetMap</a> contributors, ' +
            '<a href="http://creativecommons.org/licenses/by/3.0/">CC BY 3.0</a>, ' +
            'Imagery &copy;<a href="http://stamen.com">Stamen Design</a>',
        id: 'mapbox.streets'
    }).addTo(map);
]])

if lat and lon then
    html.print("marker= new L.marker([" .. lat .. "," .. lon .. "],{draggable: true, icon: dotIcon});")
    html.print("map.addLayer(marker);")
    html.print("map.setView([" .. lat .. "," .. lon .. "],13);")
    html.print("marker.on('drag', onMarkerDrag);")
else
    html.print("map.on('click', onMapClick);")
end

html.print([[
}

function onMapClick(e) {
    marker= new L.marker(e.latlng.wrap(),{draggable: true, icon: dotIcon});
    map.addLayer(marker);
    document.getElementsByName('latitude')[0].value=e.latlng.wrap().lat.toFixed(6).toString();
    document.getElementsByName('longitude')[0].value=e.latlng.wrap().lng.toFixed(6).toString();
    map.off('click', onMapClick);
    marker.on('drag', onMarkerDrag);
}

function onMarkerDrag(e) {
    var m = e.target;
    var p = m.getLatLng().wrap();
    document.getElementsByName('latitude')[0].value=p.lat.toFixed(6).toString();
    document.getElementsByName('longitude')[0].value=p.lng.toFixed(6).toString();
}
]])

if pingOK or (leafletcss:match("%.local%.mesh") and leafletjs:match("%.local%.mesh")) then
    html.print("window.onload = function (event) { loadCSS('" .. leafletcss .. "',function () { loadScript('" .. leafletjs  .."', leafletLoad); }); };")
end

html.print([[
function findLocation() {
    navigator.geolocation.getCurrentPosition(foundLocation, noLocation);
}

function foundLocation(position) {
    var jlat = position.coords.latitude;
    var jlon = position.coords.longitude;
    // update the fields
    document.getElementsByName('latitude')[0].value=jlat.toFixed(6).toString();
    document.getElementsByName('longitude')[0].value=jlon.toFixed(6).toString();

    // try to update the map if Javascript libs have been loaded
    if (typeof L != 'undefined') {
        var latlng = L.latLng(jlat, jlon);
        marker.setLatLng(latlng);
        map.setView(latlng,13);
    }
}

function noLocation() {
    alert('Could not find location.  Try pinning it on the map.');
}

function updDist(x) {
    var dvs= calcDistance(x);
    var xcm=dvs['miles'];
    var xc=dvs['meters'];
    var xck=dvs['kilometers'];

    var distBox = document.getElementById('dist');
    var dist_meters=document.getElementsByName('wifi_distance')[0];
    document.getElementsByName('wifi_distance_disp_miles')[0].value = xcm;
    document.getElementsByName('wifi_distance_disp_km')[0].value = xck;
    document.getElementsByName('wifi_distance_disp_meters')[0].value = xc;
    dist_meters.value = xc;

    // default of 0 means 'auto', so full range is always dist-norm
    distBox.className = 'dist-norm';
}

function calcDistance(x) {
    // x is in KILOMETERS
    var dvs = new Object();
    dvs['miles']=(x*0.621371192).toFixed(2);
    dvs['meters']=Math.ceil(x*1000);
    dvs['kilometers']=x;
    return dvs;
}

function doSubmit() {
    var desc_text = document.mainForm.description_node.value;
    var singleLine = desc_text.replace(new RegExp( "\\n", "g" ), " ");
    document.mainForm.description_node.value = singleLine;
    return true;
}

function toggleMap(toggleButton) {
    var mapdiv=document.getElementById('map');
    if(toggleButton.value=='hide') {
        // HIDE IT
        mapdiv.style.display='none';
        toggleButton.value='show';
        toggleButton.innerHTML='Show Map';
    } else {
        // SHOW IT
        mapdiv.style.display='block';
        toggleButton.value='hide';
        toggleButton.innerHTML='Hide Map';
    }
    // force the map to redraw
    if(typeof map !== 'undefined') map.invalidateSize();
    return false;
}

</script>
]])

html.print("</head>")
html.print("<body><center>")

html.alert_banner()

html.print("<form onSubmit='doSubmit();' name='mainForm' method=post action=/cgi-bin/setup.lua enctype='multipart/form-data'>\n")
html.print("<table width=790>")
html.print("<tr><td>")
-- navbar
html.print("<hr><table cellpadding=5 border=0 width=100%><tr>")
html.print("<td align=center width=15%><a href='status.lua'>Node Status</a></td>")
html.print("<td align=center width=15% class=navbar_select><a href='setup.lua'>Basic Setup</a></td>")
html.print("<td align=center width=15%><a href='ports'>Port Forwarding,<br>DHCP, and Services</a></td>")
html.print("<td align=center width=15%><a href='vpn.lua'>Tunnel<br>Server</a></td>")
html.print("<td align=center width=15%><a href='vpnc.lua'>Tunnel<br>Client</a></td>")
html.print("<td align=center width=15%><a href='admin.lua'>Administration</a></td>")
html.print("<td align=center width=15%><a href='advancedconfig.lua'>Advanced<br>Configuration</a></td>")
html.print("</tr></table><hr>")
html.print("</td></tr>")
-- control buttons
html.print([[<tr><td align=center>
<a href='/help.html#setup' target='_blank'>Help</a>
&nbsp;&nbsp;&nbsp;
<input type=submit name=button_save value='Save Changes' title='Store these settings'>&nbsp;
<input type=submit name=button_reset value='Reset Values' title='Revert to the last saved settings'>&nbsp;
<input type=submit name=button_default value='Default Values' title='Set all values to their default'>&nbsp;
<input type=submit name=button_reboot value=Reboot style='font-weight:bold' title='Immediately reboot this node'>
</td></tr>
<tr><td>&nbsp;</td></tr>]])

if #output > 0 then
    html.print("<tr><td align=center><table>")
    html.print("<tr><td><ul style='padding-left:0'>")
    for _,o in ipairs(output)
    do
        html.print("<li>" .. o .. "</li>")
    end
    html.print("</ul></td></tr></table>")
    html.print("</td></tr>")
end
if #errors > 0 then
    html.print("<tr><th>Configuration NOT saved!</th></tr>")
    html.print("<tr><td align=center><table>")
    html.print("<tr><td><ul style='padding-left:0'>")
    for _,e in ipairs(errors)
    do
        html.print("<li>" .. e .. "</li>")
    end
    html.print("</ul></td></tr></table>")
    html.print("</td></tr>")
elseif parms.button_save then
    html.print("<tr><td align=center>")
    html.print("<b>Configuration saved.</b><br><br>")
    html.print("</td></tr>")
end

if #errors == 0 and nixio.fs.stat("/tmp/reboot-required") then
    html.print("<tr><td align=center><h3>Reboot is required for changes to take effect</h3></td></tr>")
end

-- note name and type, password

html.print([[
<tr><td align=center>
<table cellpadding=5 border=0>
<tr>
<td>Node Name</td>
<td><input type=text name=nodetac value=']] .. nodetac .. [[' tabindex=1 size='50'></td>
<td align=right>Password</td>
<td><input type=password name=passwd1 value=']] .. passwd1 .. [[' size=8 tabindex=2></td>
]])
html.print([[
</tr>
<tr>
<td>Node Description (optional)</td>
<td><textarea rows='2' cols='60' wrap='soft' maxlength='210' id='node_description_entry' name='description_node' tabindex='4'>]] .. desc .. [[</textarea></td>
]])
hidden[#hidden + 1] = "<input type=hidden name=config value='mesh'>"
html.print([[
<td>Verify Password</td>
<td><input type=password name=passwd2 value=']] .. passwd2 .. [[' size=8 tabindex=3></td>
</tr>
</table>
</td></tr>
<tr><td><br>
<table cellpadding=5 border=1 width=100%><tr><td valign=top width=33%>
]])

-- mesh rf settings
html.print("<table width=100% style='border-collapse: collapse;'>")
if phycount > 1 then
    html.print("<tr><th colspan=2>Mesh RF (2GHz)</th></tr>")
else
    html.print("<tr><th colspan=2>Mesh RF</th></tr>")
end
hidden[#hidden + 1] = "<input type=hidden name=wifi_proto value='static'>"

-- add enable/disable

html.print("<tr><td>Enable</td><td><input type=checkbox name=wifi_enable value=1")
if wifi_enable then
    html.print(" checked")
end
html.print("></td></tr>")
html.print("<tr><td><nobr>IP Address</nobr></td><td><input type=text size=15 name=wifi_ip value='" .. wifi_ip .. "'></td></tr><tr><td>Netmask</td><td><input type=text size=15 name=wifi_mask value='" .. wifi_mask  .. "'></td></tr>")

-- reset wifi channel/bandwidth to default
if nixio.fs.stat("/etc/config/unconfigured") or parms.button_reset then
    local defaultwifi = aredn.hardware.get_default_channel()
    wifi_channel = defaultwifi.channel
    wifi_chanbw = defaultwifi.bandwidth
end

if wifi_enable then
    html.print("<tr><td>SSID</td><td><input type=text size=15 name=wifi_ssid value='" .. wifi_ssid .. "'>-" .. wifi_chanbw .. "-v3</td></tr>")
    hidden[#hidden + 1] = "<input type=hidden name=wifi_mode value='" .. wifi_mode .. "'>"
    html.print("<tr><td>Channel</td><td><select name=wifi_channel>")
    local rfchannels = rf_channels_list(wifiintf)
    table.sort(rfchannels, function(a, b) return a.number < b.number end)
    for _, chan in ipairs(rfchannels)
    do
        html.print("<option value='" .. chan.number .. "' ".. (chan.number == tonumber(wifi_channel) and " selected" or "") .. ">" .. chan.label .. "</option>")
    end
    html.print("</select></td></tr>")

    html.print("<tr><td>Channel Width</td><td><select name=wifi_chanbw>")
    html.print("<option value='20'".. (wifi_chanbw == "20" and " selected" or "") .. ">20 MHz</option>")
    html.print("<option value='10'".. (wifi_chanbw == "10" and " selected" or "") .. ">10 MHz</option>")
    html.print("<option value='5'".. (wifi_chanbw == "5" and " selected" or "") .. ">5 MHz</option>")
    html.print("</select></td></tr>")

    hidden[#hidden + 1] = "<input type=hidden name=wifi_country value='HX'>"

    html.print("<tr><td colspan=2 align=center><hr><small>Active Settings</small></td></tr>")
    html.print("<tr><td><nobr>Tx Power</nobr></td><td><select name=wifi_txpower>")
    local txpoweroffset = wifi_txpoweroffset(wifiintf)
    for i = aredn.hardware.wifi_maxpower(wifi_channel),1,-1
    do
        html.print("<option value='" .. i .. "'".. (i == tonumber(wifi_txpower) and " selected" or "") .. ">" .. (txpoweroffset + i) .. " dBm</option>") 
    end
    html.print("</select>&nbsp;&nbsp;<a href=\"/help.html#power\" target=\"_blank\"><img src=\"/qmark.png\"></a></td></tr>")
    html.print("<tr id='dist' class='dist-norm'><td>Distance to<br/>FARTHEST Neighbor<br/><h3>'0' is auto</h3></td>")

    local wifi_distance = math.floor(tonumber(wifi_distance))
    local wifi_distance_disp_km = math.floor(wifi_distance / 1000)
    local wifi_distance_disp_miles = string.format("%.2f", wifi_distance_disp_km * 0.621371192)
    html.print("<td><input disabled size=6 type=text name='wifi_distance_disp_miles' value='" .. wifi_distance_disp_miles .. "' title='Distance to the farthest neighbor'>&nbsp;mi<br />")
    html.print("<input disabled size=6 type=text size=4 name='wifi_distance_disp_km' value='" .. wifi_distance_disp_km .. "' title='Distance to the farthest neighbor'>&nbsp;km<br />")
    html.print("<input disabled size=6 type=text size=4 name='wifi_distance_disp_meters' value='" .. wifi_distance .."' title='Distance to the farthest neighbor'>&nbsp;m<br />")
    html.print("<input id='distance_slider' type='range' min='0' max='150' step='1' value='" .. wifi_distance_disp_km .."' oninput='updDist(this.value)' onchange='updDist(this.value)' /><br />")
    html.print("<input type='hidden' size='6' name='wifi_distance' value='" .. wifi_distance .. "' />")
    html.print("</td></tr>")

    html.print("<tr><td></td><td><input type=submit name=button_apply value=Apply title='Immediately use these active settings'></td></tr>")
else
    hidden[#hidden + 1] = "<input type=hidden name=wifi_ssid value='" .. wifi_ssid .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi_mode value='" .. wifi_mode .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi_txpower value='" .. wifi_txpower .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi_channel value='" .. wifi_channel .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi_chanbw value='" .. wifi_chanbw .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi_distance value='" .. wifi_distance .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi_country value='HX'>"
end

html.print("</table></td>")

-- lan settings

html.print([[
<td valign=top width=33%><table width=100%>
<tr><th colspan=2>LAN</th></tr>
<tr>
<td>LAN Mode</td>
<td><select name=dmz_mode onChange='form.submit()'">
]])
html.print("<option value='0'".. (dmz_mode == 0 and " selected" or "") .. ">NAT</option>")
html.print("<option value='2'".. (dmz_mode == 2 and " selected" or "") .. ">1 host Direct</option>")
html.print("<option value='3'".. (dmz_mode == 3 and " selected" or "") .. ">5 host Direct</option>")
html.print("<option value='4'".. (dmz_mode == 4 and " selected" or "") .. ">13 host Direct</option>")
html.print("<option value='5'".. (dmz_mode == 5 and " selected" or "") .. ">29 host Direct</option>")
html.print("</select></td></tr>")
hidden[#hidden + 1] = "<input type=hidden name=lan_proto value='static'>"

if dmz_mode ~= 0 then
    html.print("<tr><td><nobr>IP Address</nobr></td><td>" .. dmz_lan_ip .."</td></tr>")
    hidden[#hidden + 1] = "<input type=hidden name=dmz_lan_ip value='" .. dmz_lan_ip .. "'>"

    html.print("<tr><td>Netmask</td><td>" .. dmz_lan_mask .. "</td></tr>")
    hidden[#hidden + 1] = "<input type=hidden name=dmz_lan_mask value='" ..dmz_lan_mask .. "'>"

    html.print("<tr><td><nobr>DHCP Server</nobr></td><td><input type=checkbox name=lan_dhcp value=1" .. (lan_dhcp ~= 0 and " checked" or "") .. "></td></tr>")
    html.print("<tr><td><nobr>DHCP Start</nobr></td><td>" .. dmz_dhcp_start .. "</td></tr>")
    hidden[#hidden + 1] = "<input type=hidden name=dmz_dhcp_start value='" .. dmz_dhcp_start .. "'>"

    html.print("<tr><td><nobr>DHCP End</nobr></td><td>" .. dmz_dhcp_end .. "</td></tr>")

    hidden[#hidden + 1] = "<input type=hidden name=lan_ip     value='" .. lan_ip .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=lan_mask   value='" .. lan_mask .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=dhcp_start value='" .. dhcp_start .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=dhcp_end   value='" .. dhcp_end .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=lan_gw     value='" .. lan_gw .."'>"
else
    html.print("<tr><td><nobr>IP Address</nobr></td><td><input type=text size=15 name=lan_ip value='" .. lan_ip .. "'></td></tr>")
    html.print("<tr><td>Netmask</td><td><input type=text size=15 name=lan_mask value='" .. lan_mask .."'></td></tr>")
    if wan_proto == "disabled" then
        html.print("<tr><td>Gateway</td><td><input type=text size=15 name=lan_gw value='" .. lan_gw .. "' title='leave blank if not needed'></td></tr>")
    else
        hidden[#hidden + 1] = "<input type=hidden name=lan_gw     value='" .. lan_gw .. "'>"
    end
    html.print("<tr><td><nobr>DHCP Server</nobr></td><td><input type=checkbox name=lan_dhcp value=1" .. (lan_dhcp ~= "" and " checked" or "") .. "></td></tr>")
    html.print("<tr><td><nobr>DHCP Start</nobr></td><td><input type=text size=4 name=dhcp_start value='" .. dhcp_start .. "'></td></tr>")
    html.print("<tr><td><nobr>DHCP End</nobr></td><td><input type=text size=4 name=dhcp_end value='" .. dhcp_end .. "'></td></tr>")

    hidden[#hidden + 1] = "<input type=hidden name=dmz_lan_ip     value='" .. dmz_lan_ip .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=dmz_lan_mask   value='" .. dmz_lan_mask .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=dmz_dhcp_start value='" .. dmz_dhcp_start .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=dmz_dhcp_end   value='" .. dmz_dhcp_end .. "'>"
end

html.print("<tr><td colspan=2><hr></hr></td></tr>")

-- $M39model = `/usr/local/bin/get_model | grep -e "M[39]"`;
local M39model
if (phycount > 1 and (not wifi_enable or not wifi3_enable) or (phycount == 1 and not wifi_enabe and not wifi3_enable)) and not M39model then
    -- lan ap shows as an option
    -- determine hardware options and set band ahd channels accordingly
    if phycount == 1 then
        -- rc3 = -- system("iw phy phy0 info | grep -q '5180 MHz' > /dev/null");
        if rc3 ~= "" then
            wifi2_hwmode = "11g"
            if wifi2_channel > 14 then
                wifi2_channel = 1
            end
        else
            wifi2_hwmode = "11a"
            if wifi2_channel < 36 then
                wifi2_channel = 36
            end
            chan = cfive
        end
    else
        -- 2 band device
        if wifi_enable then
            wifi2_hwmode = "11a"
            if wifi2_channel < 36 then
                wifi2_channel = 36
            end
            chan = cfive
        else
            if not wifi2_enable and wifi3_enable and wifi3_hwmode == "11a" then
                wifi2_hwmode = "11g"
            end
            if not wifi2_enable and wifi3_enable and wifi3_hwmode == "11g" then
                wifi2_hwmode = "11a"
            end
            if wifi2_hwmode == "11a" then
                if wifi2_channel < 36 then
                    wifi2_channel = 36
                end
                chan = cfive
            else
                if wifi2_channel > 14 then
                    wifi2_channel = 1
                end
                chan = ctwo
            end
        end
    end
    html.print("<tr><th colspan=2>LAN Access Point</th></tr><tr><td>Enable</td><td><input type=checkbox name=wifi2_enable value=1" .. (wifi2_enable and " checked" or "") .. "></td></tr>")
    if phycount > 1 then
        html.print("<tr><td>AP band</td><td><select name=wifi2_hwmode>")
        if not wifi_enable then
            html.print("<option value='11g'".. (wifi2_hwmode == "11g" and " selected" or "") .. ">2GHz</option>")
        end
        html.print("<option value='11a'".. (wifi2_hwmode == "11a" and " selected" or "") .. ">5GHz</option>")
	    html.print("</select></td></tr>")
    else
        hidden[#hidden + 1] = "<input type=hidden name=wifi2_hwmode  value='" .. wifi2_hwmode .."'>"
    end
    html.print("<tr><td>SSID</td><td><input type=text size=15 name=wifi2_ssid value='" .. wifi2_ssid .."'></td></tr><tr><td>Channel</td><td><select name=wifi2_channel>")
    for i in 0,#chan
    do
        html.print("<option value='" .. chan[i] .. "'" .. (wifi2_channel == chan[i] and " selected" or "") .. ">" .. chan[i] .. "</option>")
    end
    html.print("</select></td></tr>")
    html.print("<tr><td>Encryption</td><td><select name=wifi2_encryption>")
    html.print("<option value='psk2'".. (wifi2_encryption == "psk2" and " selected" or "") .. ">WPA2 PSK</option>")
    html.print("<option value='psk'".. (wifi2_encryption == "psk" and " selected" or "") .. ">WPA PSK</option>")
    html.print("</select></td></tr><tr><td>Password</td><td><input type=password size=15 name=wifi2_key value='" .. wifi2_key .. "'></td></tr>")
else
    hidden[#hidden + 1] = "<input type=hidden name=wifi2_enable     value='" .. wifi2_enable .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi2_ssid       value='" .. wifi2_ssid .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi2_key        value='" .. wifi2_key .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi2_channel    value='" .. wifi2_channel .."'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi2_encryption value='" .. wifi2_encryption .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi2_hwmode     value='" .. wifi2_hwmode .."'>"
end

html.print("</table></td>")

-- wan settings
html.print("<td valign=top width=33%><table width=100%><tr><th colspan=2>WAN</th></tr><tr><td width=50%>Protocol</td><td><select name=wan_proto onChange='form.submit()'>")
html.print("<option value='static'".. (wan_proto == "static" and " selected" or "") .. ">Static</option>")
html.print("<option value='dhcp'".. (wan_proto == "dhcp" and " selected" or "") .. ">DHCP</option>")
html.print("<option value='disabled'".. (wan_proto == "disabled" and " selected" or "") .. ">disabled</option>")
html.print("</select></td></tr>")

if wan_proto == "static" then
    html.print("<tr><td><nobr>IP Address</nobr></td>")
    html.print("<td><input type=text size=15 name=wan_ip value='" .. wan_ip .."'></td></tr>")
    html.print("<tr><td>Netmask</td>")
    html.print("<td><input type=text size=15 name=wan_mask value='" .. wan_mask .. "'></td></tr>")
    html.print("<tr><td>Gateway</td>")
    html.print("<td><input type=text size=15 name=wan_gw value='" .. wan_gw .. "'></td></tr>")
else
    hidden[#hidden + 1] = "<input type=hidden name=wan_ip value='" .. wan_ip .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wan_mask value='" .. wan_mask .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wan_gw value='" .. wan_gw .."'>"
end

html.print("<tr><td><nobr>DNS 1</nobr></td><td><input type=text size=15 name=wan_dns1 value='" .. wan_dns1 .. "'></td></tr>")
html.print("<tr><td><nobr>DNS 2</nobr></td><td><input type=text size=15 name=wan_dns2 value='" .. wan_dns2 .. "'></td></tr>")

html.print("<tr><td colspan=2><hr></td></tr><tr><th colspan=2>Advanced WAN Access</th></tr>")
if wan_proto ~= "disabled" then
    html.print("<tr><td><nobr>Allow others to<br>use my WAN</td><td><input type=checkbox name=olsrd_gw value=1 title='Allow this node to provide internet access to other mesh users'" .. (olsrd_gw ~= "0" and " checked" or "") .. "></td></tr>")
else
    hidden[#hidden + 1] = "<input type=hidden name=olsrd_gw value='0'>"
end
html.print("<tr><td><nobr>Prevent LAN devices<br>from accessing WAN</td><td><input type=checkbox name=lan_dhcp_noroute value=1 title='Disable LAN devices to access the internet'" .. (lan_dhcp_noroute ~= "0" and " checked" or "") .. "></td></tr>")

-- wan wifi client
if (phycount > 1 and (not wifi_enable or not wifi2_enable)) or (phycount == 1 and not wifi_enable and not wifi2_enable) and not M390model then
    -- wifi client shows as an option
    -- determine hardware options and set band accordingly

    if phycount == 1 then
        -- $rc3 = system("iw phy phy0 info | grep -q '5180 MHz' > /dev/null");
        local rc3
        if rc3 ~= "" then
            wifi3_hwmode = "11g"
        else
            wifi3_hwmode = "11a"
        end
    else
        -- 2 band
        if wifi_enable then
            wifi3_hwmode = "11a"
        else
            if wifi2_hwmode == "11g" and wifi2_enable then
                wifi3_hwmode = "11a"
            end
            if wifi2_hwmode == "11a" and wifi2_enable then
                wifi3_hwmode = "11g"
            end
        end
    end

    html.print("<tr><td colspan=2><hr></td></tr><tr><th colspan=2>WAN Wifi Client</th></tr><tr><td>Enable</td><td><input type=checkbox name=wifi3_enable value=1" .. (wifi3_enable and " checked" or "") .. "></td></tr>")

    if not wifi_enable and not wifi2_enable and phycount > 1 then
        html.print("<tr><td>WAN Wifi Client band</td><td><select name=wifi3_hwmode>")
        html.print("<option value='11g'".. (wifi3_hwmode == "11g" and " selected" or "") .. ">2GHz</option>")
        html.print("<option value='11a'".. (wifi3_hwmode == "11a" and " selected" or "") .. ">5GHz</option>")
        html.print("</select></td></tr>")
    else
        hidden[#hidden + 1] = "<input type=hidden name=wifi3_hwmode value='" .. wifi3_hwmode .. "'>"
    end

    html.print("<tr><td>SSID</td><td><input type=text name=wifi3_ssid size=15 value='" .. wifi3_ssid .."'></select></td></tr>")
    html.print("<tr><td>Password</td><td><input type=password size=15 name=wifi3_key value='" .. wifi3_key .. "'></td></tr>")
else
    hidden[#hidden + 1] = "<input type=hidden name=wifi3_enable     value='" .. wifi3_enable .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi3_ssid       value='" .. wifi3_ssid .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi3_key        value='" .. wifi3_key .. "'>"
    hidden[#hidden + 1] = "<input type=hidden name=wifi3_hwmode     value='" .. wifi3_hwmode .. "'>"
end
-- end wan wifi client

html.print("</table></td></tr></table></td></tr></table><br></td></tr>")

-- optional settings
html.print("<tr><td align=center>")
html.print("<table cellpadding=5 border=0><tr><th colspan=4>Optional Settings</th></tr>")
html.print("<tr><td colspan=4><hr /></td></tr>")
html.print("<tr><td align=left>Latitude</td><td><input type=text name=latitude size=10 value='" .. lat .."' title='Latitude value (in decimal) (ie. 30.312354)' /></td>")
html.print("<td align='right' colspan='2'>")
html.print("<button type='button' id='findlocation' value='findloc' onClick='findLocation();'>Find Me!</button>&nbsp;")
html.print("<input type=submit name='button_updatelocation' value='Apply Location Settings' title='Immediately use these location settings'>")
html.print("&nbsp;<button type='button' id='hideshowmap' value='show' onClick='toggleMap(this);'>Show Map</button>&nbsp;")
if pingOK then
    html.print("<input type='submit' name='button_uploaddata' value='Upload data to AREDN Servers' />&nbsp;")
else
    html.print("<button disabled type='button' title='Only available if this node has internet access'>Upload data to AREDN Servers</button>&nbsp;")
end

html.print("</td><tr><td align=left>Longitude</td><td><input type=text name=longitude size=10 value='" .. lon .. "' title='Longitude value (in decimal) (ie. -95.334454)' /></td><td align=left>Grid Square</td><td align='left'><input type=text name=gridsquare maxlength=6 size=6 value='" .. gridsquare .. "' title='Gridsquare value (ie. AB12cd)' /></td></tr><tr><td colspan=4><div id='map' style='height: 200px; display: none;'></div></td></tr><tr><td colspan=4><hr /></td></tr>")
html.print("<tr><td>Timezone</td><td><select name=time_zone_name tabindex=10>")
for _,zone in ipairs(tz_db_names)
do
    html.print("<option value='" .. zone.tz .. "'".. (zone.tz == time_zone_name and " selected" or "") .. ">" .. zone.name .. "</option>")
end
html.print("</select></td><td align=left>NTP Server</td><td><input type=text name=ntp_server size=20 value='" .. ntp_server .. "'></td></table></td></tr></table>")

hidden[#hidden + 1] = "<input type=hidden name=reload value=1>"
hidden[#hidden + 1] = "<input type=hidden name=dtdlink_ip value='" .. dtdlink_ip .. "'>"

for _,hid in ipairs(hidden)
do
    html.print(hid)
end

html.print("</form></center>")
html.footer()
html.print("</body></html>")
http_footer()
