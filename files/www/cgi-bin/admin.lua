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
require("aredn.hardware")
require("aredn.http")
require("aredn.utils")
aredn.html = require("aredn.html")
require("uci")
aredn.info = require("aredn.info")
require("ubus")
require("luci.sys")

local html = aredn.html

local cursor = uci.cursor()
local conn = ubus.connect()

local fw_images = {}
local fw_version = ""
function firmware_list_gen()
    for line in io.lines("/etc/mesh-release")
    do
        fw_version = line:chomp()
        break
    end
    if nixio.fs.stat("/etc/web/firmware.list") then
        for line in io.lines("/etc/web/firmware.list")
        do
            local md5, fw, tag = line:match("")
            if tag and tag ~= "none" and (tag == "all" or fw_version:match(tag)) then
                fw_images[#fw_images + 1] = fw
                fw_md5[fw] = md5
            end
        end
    end
end

local tunnel_active = false
if nixio.fs.stat("/usr/sbin/vtund") then
    for line in io.liness("/etc/config/vtun")
    do
        if line:match("option enabled '1'") then
            tunnel_active = true
            break
        end
    end
end

function get_default_gw()
    -- a node with a wired default gw will route via this
    local p = io.popen("ip route list table 254")
    if p then
        for line in p:lines()
        do
            local gw = line:match("^default%svia%s([%d%.]+)")
            if gw then
                p:close()
                return gw
            end
        end
        p:close()
    end
    -- table 31 is populated by OLSR
    p = io.popen("ip route list table 31")
    if p then
        for line in p:lines()
        do
            local gw = line:match("^default%svia%s([%d%.]+)")
            if gw then
                p:close()
                return gw
            end
        end
        p:close()
    end
    return "none"
end

function reboot()
    local node = aredn.info.get_nvram("node")
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
        html.header(node .. " rebooting", true)
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

function word_wrap(len, lines)
    local output = ""
    for _, str in ipairs(lines)
    do
        while #str > len
        do
            local str1 = str:sub(1, len)
            local str2 = str:sub(len + 1)
            local m, x = str1:match("^(.*)%s(%S+)$")
            if m then
                output = output .. m .. "\n"
                str = x .. str2
            else
                output = output .. str1 .. "\n"
                str = str2
            end
        end
        output = output .. str .. "\n"
    end
    return output:sub(1, #output - 1)
end

-- read_postdata
local parms = {}
local firmfile = ""
if os.getenv("REQUEST_METHOD") == "POST" then
    require('luci.http')
    local request = luci.http.Request(luci.sys.getenv(),
      function()
        local v = io.read(1024)
        if not v then
            io.close()
        end
        return v
      end
    )
    -- only allow file uploading without active tunnels
    if not active_tunnel then
        local fp
        request:setfilehandler(
            function(meta, chunk, eof)
                if not fp then
                    if meta and meta.file then
                        firmfile = meta.file
                    end
                    nixio.fs.mkdir("/tmp/web/upload")
                    fp = io.open("/tmp/web/upload/file", "w")
                 end
                 if chunk then
                    fp:write(chunk)
                 end
                 if eof then
                    fp:close()
                 end
            end
        )
    end
    parms = request:formvalue()
end

if parms.button_reboot then
    reboot()
end
local node = aredn.info.get_nvram("node")
local tmpdir = "/tmp/web/admin"
nixio.fs.mkdir("/tmp/web")
nixio.fs.mkdir("/tmp/web/admin")

-- set the wget command options
local wget = "wget -U 'node: " .. node .. "' "

-- handle firmware updates
local fw_install = false
local patch_install = false
local fw_output = {}
local fw_images = {}
local fw_md5 = {}

function fwout(msg)
    fw_output[#fw_output + 1] = msg
end

local serverpaths = {}
local uciserverpath = cursor:get("aredn", "@downloads[0]", "firmwarepath")
if not uciserverpath then
    uciserverpath = ""
end
serverpaths[#serverpaths + 1] = uciserverpath

local hardwaretype = aredn.hardware.get_type()
local targettype = conn:call("system", "board", {}).release.target

-- handle TPLink and Mikrotik exception conditions
local mfg = aredn.hardware.get_manufacturer()
local mfgprefix = ""
if mfg:match("Ubiquiti") then
    mfgprefix = "ubnt"
elseif mfg:match("Mikrotik") then
    mfgprefix = "mikrotik"
elseif mfg:match("TP-Link") then
    mfgprefix = "cpe"
end

local hardwaretypev
if hardwaretype == "nanostation-m" then
    hardwaretypev = "nano-m" -- Nano XM
elseif hardwaretype == "nanostation-m-xw" then
    hardwaretypev = "nano-m-xw"  -- Nano XW
elseif hardwaretype == "rb-952ui-5ac2nd" then
    hardwaretypev = "rb-nor-flash-16M-ac"     -- hAP AC Lite
elseif hardwaretype:match("rb-911g-[25]hpnd") or hardwaretype:match("rb-912uag-[25]hpnd") then
    hardwaretypev = "nand-large"     -- Basebox 2/5 and QRT 2/5
elseif hardwaretype:match("rb-l[dfhg]+-[25]nd") or hardwaretype:match("rb-lhg-[25]hpnd")  then
    hardwaretypev = "rb-nor-flash-16M"     -- LHGs & LDFs
elseif mfgprefix == "cpe" then
    local hwmodel = aredn.hardware.get_board_id()
    if hwmodel:match("CPE210 v1%.[01]") then
        hardwaretypev = "210-220-v1"       -- v1.0/v1.1
    elseif hwmodel:match("CPE210 v2%.0") then
        hardwaretypev = "210-v2"           -- v2.0
    elseif hwmodel:match("CPE210 v3%.0") then
        hardwaretypev = "210-v3"           -- v3.0
    elseif hwmodel:match("CPE220 v2%.0") then
        hardwaretypev = "220-v2"           -- v3.0
    elseif hwmodel:match("CPE220 v3%.0") then
        hardwaretypev = "220-v3"           -- v3.0
    elseif hwmodel:match("CPE510 v2%.0") then
        hardwaretypev = "510-v2"           -- v2.0
    elseif hwmodel:match("CPE510 v3%.0") then
        hardwaretypev = "510-v3"           -- v3.0
    elseif hwmodel:match("CPE510") then
        hardwaretypev = "510-520-v1"       -- CPE510 V1.0/v1.1
    elseif hwmodel:match("CPE610 v2%.0") then
        hardwaretypev = "610-v2"      	    -- CPE610 V2.0
    elseif hwmodel:match("CPE610") then
        hardwaretypev = "610-v1"      	    -- CPE610 V1.0
    elseif hwmodel:match("WBS510 v2%.0") then
        mfgprefix="wbs"
        hardwaretypev = "510-v2"           -- WBS510 v2.0
    elseif hwmodel:match("WBS210 v1%.[012]") then
        mfgprefix="wbs"
        hardwaretypev = "210-v1"       -- WBS210 v1.0/v1.1 
    end
else
    hardwaretypev = hardwaretype
end

-- refresh fw
if parms.button_refresh_fw then
    nixio.fs.remove("/tmp/web/firmware.list")
    if get_default_gw() ~= "none" or uciserverpath:match("%.local%.mesh") then
        fwout("Downloading firmware list from " .. uciserverpath .. "...")
        local ok = false
        for _, serverpath in ipairs(serverpaths)
        do
            if os.execute(wget .. "-O /tmp/web/firmware.list " .. serverpath .. "/firmware." .. hardwaretype .. ".list >/dev/null 2>>" .. tmpdir .. "/wget.err") == 0 then
                ok = true
                break
            end
        end
        if ok then
            fwout("Done")
        else
            fwout(read_all(tmpdir .. "/wget.err"))
        end
        nixio.fs.remove(tmpdir .. "/wget.err")
    else
        fwout("Error: no route to Host")
    end
end

-- generate data structures
-- and set fw_version
firmware_list_gen()

-- upload fw
if parms.button_ul_fw and nixio.fs.stat("/tmp/web/upload/file") then
    os.execute("mv -f /tmp/web/upload/file " .. tmpdir .. "/firmware")
    if firmfile:match("sysupgrade%.bin$") then -- full firmware
        fw_install = true
        -- drop the page cache to take pressure off tmps when checking the firmware
        write_all("/proc/sys/vm/drop_caches", "3")
        -- check firmware header
        if os.execute("/usr/local/bin/firmwarecheck.sh " .. tmpdir .. "/firmware") ~= 0 then
            fwout("Firmware CANNOT be updated")
            fwout("firmware file is not valid")
            fw_install = false
            nixio.fs.remove(tmpdir .. "/firmware")
            if os.execute("/usr/local/bin/uploadctlservices restore") ~= 0 then
                fwout("Failed to restart all services, please reboot this node.")
            end
        end
    elseif firmfile:match("^patch%S+%.tgz$") then -- firmware patch
        patch_install = false
    else
        fwout("Firmware CANNOT be updated")
        fwout("the uploaded file is not recognized")
        nixio.fs.remove(tmpdir .. "/firmware")
        if os.execute("/usr/local/bin/uploadctlservices restore") ~= 0 then
            fwout("Failed to restart all services, please reboot this node.")
        end
    end
end

-- download fw
if parms.button_dw_fw and parms.dl_fw ~= "default" then
    if get_default_gw() ~= "none" or uciserverpath:match("%.local%.mesh") then
        nixio.fs.remove(tmpdir .. "/firmware")
        os.execute("/usr/local/bin/uploadctlservices update")
        local ok = false
        for _, serverpath in ipairs(serverpaths)
        do
            if os.execute(wget .. "-O " .. tmpdir .. "/firmware " .. serverpath .. "/" .. parms.dl_fw .. " >/dev/null 2>>" .. tmpdir .. "/wget.err") == 0 then
                ok = true
                break
            end
        end

        if parms.dl_fw:match("/sysupgrade%.bin$") then -- full firmware
            fw_install = true
            if not ok then
                fwout("Downloading firmware image...")
                fwout(read_all(tmpdir .. "/wget.err"))
            end
            nixio.fs.remove(tmpdir .. "/wget.err")
            -- check md5sum
            local fw = parms.dl_fw
            if os.execute("echo '" .. fw_md5[fw] .. "  firmware' | md5sum -cs") ~= 0 then
                fwout("Firmware CANNOT be updated")
                fwout("firmware file is not valid")
                fw_install = false
                nixio.fs.remove(tmpdir .. "/firmware")
                if os.execute("/usr/local/bin/uploadctlservices restore") ~= 0 then
                    fwout("Failed to restart all services, please reboot this node.")
                end
            end
        elseif parms.dl_fw:match("^patch%S+%.tgz$") then -- firmware patch
            patch_install = true
            if not ok then
                fwout("Downloading patch file...")
                fwout(read_all(tmpdir .. "/wget.err"))
            end
            nixio.fs.remove(tmpdir .. "/wget.err")
            -- check md5sum
            local fw = parms.dl_fw
            if os.execute("echo '" .. fw_md5[fw] .. "  firmware' | md5sum -cs") ~= 0 then
                fwout("Firmware CANNOT be updated")
                fwout("patch file is not valid")
                patch_install = false
                nixio.fs.remove(tmpdir .. "/firmware")
                if os.execute("/usr/local/bin/uploadctlservices restore") ~= 0 then
                    fwout("Failed to restart all services, please reboot this node.")
                end
            end
        else
            fwout("Firmware CANNOT be updated")
            fwout("the downloaded file is not recognized")
            nixio.fs.remove(tmpdir .. "/firmware")
            if os.execute("/usr/local/bin/uploadctlservices restore") ~= 0 then
                fwout("Failed to restart all services, please reboot this node.")
            end
        end
    else
        fwout("Error: no route to Host")
        nixio.fs.remove(tmpdir .. "/wget.err")
    end
end

-- install fw
if fw_install and nixio.fs.stat(tmpdir .. "/firmware") then
    http_header(true) -- no compression (gzip will be killed)
    html.header("FIRMWARE UPDATE IN PROGRESS", false)
    html.print("<meta http-equiv='refresh' content='180;URL=http://" .. node .. ".local.mesh:8080'>")
    html.print("</head>")
    html.print("<body><center>")
    html.print("<h2>The firmware is being updated.</h2>")
    html.print("<h1>DO NOT REMOVE POWER UNTIL UPDATE IS FINISHED</h1>")
    html.print("</center><br>")
    -- drop page cache to take pressure of tmps for the upgrade process
    write_all("/proc/sys/vm/drop_caches", "3")
    os.execute("/usr/local/bin/upgrade_kill_prep > /dev/null 2>&1")
    if parms.checkbox_keep_settings then
        local fin = io.open("/etc/arednsysupgrade.conf", "r")
        if fin then
            local fout = io.open("/tmp/sysupgradefilelist", "w")
            if fout then
                for line in fin:lines()
                do
                    if not line:match("^#") and nixio.fs.stat(line) then
                        fout:write(line .. "\n")
                    end
                end
                fout:close()
                fin:close()
                aredn.info.set_nvram("nodeupgraded", "1")
                if os.execute("tar -czf /tmp/arednsysupgradebackup.tgz -T /tmp/sysupgradefilelist") ~= 0 then
                    html.print([[
                        <center><h2>ERROR: Could not backup filesystem.</h2>
                        <h3>An error occured trying to backup the file system. Node will now reboot.
                        </center>
                    ]])
                    html.footer()
                    html.print("</body></html>")
                    http_footer()
                    aredn.info.set_nvram("nodeupgraded", "0")
                    luci.sys.reboot()
                else
                    html.print([[
                        <center><h2>Firmware will be written in the background.</h2>
                        <h3>If your computer is connected to the LAN of this node you may need to acquire<br>
                        a new IP address and reset any name service caches you may be using.</h3>
                        <h3>The node will reboot twice while the configuration is applied<br>
                        When the node has finished booting you should ensure your computer has<br>
                        received a new IP address and reconnect with<br>
                        <a href='http://]] .. node .. [[.local.mesh:8080/'>http://]] .. node .. [[.local.mesh:8080/</a><br>
                        (This page will automatically reload in 3 minutes)</h3>
                        </center></body></html>
                    ]])
                    http_footer()
                    nixio.fs.remove("/tmp/sysupgradefilelist")
                    os.execute("/usr/local/bin/spawn_sysupgrade " .. tmpdir .. "/firmware 2>&1 &")
                end
                os.exit()
            else
                fin:close()
            end
        end
        html.print([[
            <center><h2>ERROR: Failed to create backup.</h2>
            <h3>An error occured trying to backup the file system. Node will now reboot.
            </center>
        ]])
        html.footer()
        html.print("</body></html>")
        http_footer()
        luci.sys.reboot()
        os.exit()
    else
        html.print([[
            <center><h2>Firmware will be written in the background.</h2>
            <h3>If your computer is connected to the LAN of this node you may need to acquire<br>
            a new IP address and reset any name service caches you may be using.</h3>
            <h3>The node will reboot after the firmware has been written to flash memory<br>
            When the node has finished booting you should ensure your computer has<br>
            received a new IP address and reconnect with<br>
            <a href='http://localnode.local.mesh:8080/'>http://192.168.1.1:8080/</a><br>
            and continue setup of the node in firstboot state.<br>
            (This page will automatically reload in 3 minutes)</h3>
            </center></body></html>
        ]])
        http_footer()
        os.execute("/sbin/sysupgrade -n " .. tmpdir .. "/firmware 2>&1 &")
    end
    os.execute("killall uhttpd &")
    os.exit()
end

-- install patch
if patch_install and nixio.fs.stat(tmpdir .. "/firmware") then
    -- fix me
end

-- handle package actions
local pkg_output = {}
function pkgout(msg)
    pkg_output[#pkg_output + 1] = msg
end

local permpkg = {}
for line in io.lines("/etc/permpkg")
do
    if not line:match("^#") then
        permpkg[line] = true
    end
end

-- upload package
if parms.button_ul_pkg and nixio.fs.stat("/tmp/web/upload/file") then
    -- fix me
end

-- download package
local meshpkgs = capture("grep -q \".local.mesh\" /etc/opkg/distfeeds.conf"):chomp()
if parms.button_dl_pkg and parms.dl_pkg ~= "default" then
    -- fix me
end

-- refresh package list
if parms.button_refresh_pkg then
    if get_default_gw() ~= "none" or meshpkgs ~= "" then
        pkgout(capture("opkg update 2>&1"))
        os.execute("opkg list | grep -v '^ ' | cut -f1,3 -d' ' | gzip -c > /etc/opkg.list.gz")
    else
        pkgout("Error: no route to Host")
    end
end

-- remove package
if parms.button_rm_pkg and parms.rm_pkg ~= "default" and not permpkg[parms.rm_pkg] then
    -- fix me
end

-- generate data structures

local pkgs = {}
local pkgver = {}
local f = io.popen("opkg list_installed | cut -f1,3 -d' '")
if f then
    for line in f:lines()
    do
        local pkg, ver = line:match("(.+)%s(.+)")
        if ver then
            pkgs[#pkgs + 1] = pkg
            pkgver[pkg] = ver
        end
    end
    f:close()
end

local dl_pkgs = {}
local dlpkgver = {}
if nixio.fs.stat("/etc/opkg.list.gz") then
    local f = io.popen("zcat /etc/opkg.list.gz")
    if f then
        for line in f:lines()
        do
            local pkg, ver = line:match("(.+)%s(.+)")
            if ver and not (pkgver[pkg] and pkgver[pkg] == ver) then
                dl_pkgs[#pkgs + 1] = pkg
                dlpkgver[pkg] = ver
            end
        end
        f:close()
    end
end

-- handle ssh key actions

local key_output = {}
function keyout(msg)
    key_output[#key_output + 1] = msg
end

local keyfile = "/etc/dropbear/authorized_keys"

-- upload key
if parms.button_ul_key and nixio.fs.stat("/tmp/web/upload/file") then
    local count = 0
    for _ in io.lines(keyfile)
    do
        count = count + 1
    end
    os.execute("grep ^ssh- /tmp/web/upload/file >> " .. keyfile)
    local count = 0
    for _ in io.lines(keyfile)
    do
        count = count - 1
    end
    if count == 0 then
        keyout("Error: file does not appear to be an ssh key file")
        keyout("Authorized keys not changed.")
    else
        keyout("Key installed.")
    end
    nixio.fs.remove("/tmp/web/upload/file")
    if os.execute("/usr/local/bin/uploadctlservices restore") ~= 0 then
        keyout("Failed to restart all services, please reboot this node.")
    end
end

-- remove key
if parms.button_rm_key and parms.rm_key ~= "default" and nixio.fs.stat(keyfile) then
    local count = 0
    for _ in io.lines(keyfile)
    do
        count = count + 1
    end
    os.execute("grep -v '" .. parms.rm_key .. "' " .. keyfile .. " > " .. tmpdir .. "/keys")
    os.execute("mv -f " .. tmpdir .. "/keys " .. keyfile)
    for _ in io.lines(keyfile)
    do
        count = count - 1
    end
    if count == 0 then
        keyout("Error: authorized keys were not changed.")
    else
        keyout("Key " .. parms.rm_key .. " removed.")
    end
end

-- generate data structures
local keys = {}
local f = io.open(tmpdir .. "/newkeys")
if f then
    for line in io.lines(keyfile)
    do
        local type, key, who, extra = line:match("(%S+)%s+(%S+)%s+(%S+)(.*)")
        if not extra and who:match(".@.") and type:match("^ssh-") then
            keys[#keys + 1] = who
            f:write(type .. " " .. key .. " " .. who .. "\n")
        end
    end
    f:close()
end

-- sanitize the key file
if nixio.fs.stat(keyfile) and os.execute("diff " .. keyfile .. " " .. tmpdir .. "/newkeys >/dev/null 2>&1") then
    os.execute("mv -f " .. tmpdir .. "/newkeys " .. keyfile)
    keyout("Info: key file sanitized.")
end

remove_all("/tmp/web/upload")
remove_all(tmpdir)

-- generate the page

http_header()
html.header(node .. " administration", false)
html.print([[
    <script>
    function validateFirmwareFilename(elem){
        var hwmfg = mfgprefix;
        var hwtype = hardwaretypev;
        var searchstring = "";
        var efn = "";
        if(hwmfg != "cpe"){
            if (hwmfg == "wbs") {
                searchstring= ".*wbs" + hwtype + "-sysupgrade.bin$\";
                efn = "aredn-" .. fw_version .. "-" .. mfgprefix .. hardwaretypev .. "-sysupgrade.bin";
            } else {
                searchstring= ".*(-|_)" + hwtype + "-sysupgrade.bin$\";
                efn = "aredn-" .. fw_version .. "-" .. mfgprefix .. "-" .. hardwaretypev .. "-sysupgrade.bin";
            }
        } else {
            searchstring= ".*cpe" + hwtype + "-sysupgrade.bin$\";
            efn = "aredn-" .. fw_version .. "-" .. mfgprefix .. hardwaretypev .. "-sysupgrade.bin";
        }
        var re = new RegExp(searchstring,"g");   
        if(elem.value.match(re)){
            return true;
        }else{
            if (confirm('This filename is NOT appropriate for this device!\\n\\nThis device expects a file such as: ' + efn + ' \\n\\n\\nClick OK to continue if you are CERTAIN that the file is correct.')) {
                return true;
            } else {
                elem.value="";
                return false;
            }
        }
    }
    </script>
    </head>
    <body><center>    
]])
html.alert_banner()
html.print("<form method=post action=admin.lua enctype='multipart/form-data'><table width=790><tr><td>")
-- nav
html.print("<hr><table cellpadding=5 border=0 width=100%><tr>")
html.print("<td align=center width=15%><a href='status.lua'>Node Status</a></td>")
html.print("<td align=center width=15%><a href='setup.lua'>Basic Setup</a></td>")
html.print("<td align=center width=15%><a href='ports'>Port Forwarding,<br>DHCP, and Services</a></td>")
html.print("<td align=center width=15%><a href='vpn.lua'>Tunnel<br>Server</a></td>")
html.print("<td align=center width=15%><a href='vpnc.lua'>Tunnel<br>Client</a></td>")
html.print("<td align=center width=15% class=navbar_select><a href='admin.lua'>Administration</a></td>")
html.print("<td align=center width=15%><a href='advancedconfig.lua'>Advanced<br>Configuration</a></td>")
html.print("</tr></table><hr>")
html.print("</td></tr>")

html.print("<tr><td align=center><a href='/help.html#admin' target='_blank'>Help</a>&nbsp;&nbsp;")
html.print("<input type=submit name=button_reboot value=Reboot style='font-weight:bold' title='Immediately reboot this node'>")
html.print("</td></tr>")
html.print("<tr><td align=center>")
html.print("<table cellspacing=10>")

-- firmware

html.print("<tr><td align=center>")
html.print("<table cellspacing=10>")
html.print("<tr><th colspan=3>Firmware Update</th></tr>")

if #fw_output > 0 then
    html.print("<tr><td colspan=3 align=center><table><tr><td><b>")
    html.print("<pre>" .. word_wrap(80, fw_output) .. "</pre>")
    html.print("</b></td></tr></table></td></tr>")
end

html.print("<tr><td align=center colspan=3>current version: " .. fw_version .. "</td></tr>")
html.print("<tr><td align=center colspan=3>hardware type: (" .. targettype .. ") " .. mfgprefix .. " (" .. hardwaretype .. ")</td></tr>")
html.print("<tr>")
html.print("<td>Upload Firmware</td>")
html.print("<td><input type=file name=firmfile title='choose the firmware file to install from your hard drive' accept='.bin' onchange='validateFirmwareFilename(this)'></td>")
html.print("<td align=center><input type=submit name=button_ul_fw value=Upload title='install the firmware'")
if tunnel_active then
    html.print(" disabled><br><small>Disabled: Tunnels enabled</small>")
else
    html.print(">")
end
html.print("</td>")
html.print("</tr>")

html.print("<tr>")
html.print("<td>Download Firmware</td>")
html.print("<td><select name=dl_fw style='font-family:monospace'>")
html.print("<option value=default selected>- Select Firmware -</option>")
for _, fwi in ipairs(fw_images)
do
    html.print("<option value=" .. fwi .. ">" .. fwi .. "</option>")
end
html.print("</select>")
html.print("<input type=submit name=button_refresh_fw value=Refresh title='download the list of available firmware versions'>")
html.print("<td align=center><input type=submit name=button_dl_fw value=Download title='install the firmware'></td>")
html.print("<td align=right><input type=checkbox name=checkbox_keep_settings checked>Keep Settings</td>")
html.print("</tr>")

html.print("</table></td></tr>")
html.print("<tr><td colspan=3><hr></td></tr>")

-- packages

html.print("<tr><td align=center>")
html.print("<table cellspacing=10>")
html.print("<tr><th colspan=3>Package Management</th></tr>")

if #pkg_output > 0 then
    -- opkg can produce duplicate first lines, remove them here
    while pkg_output[2] and pkg_output[1] == pkg_output[2]
    do
        pkg_output:remove(1)
    end
    html.print("<tr><td colspan=3 align=center><table><tr><td><b><pre>")
    html.print(word_wrap(80, pkg_output))
    html.print("</pre></b></td></tr></table></td></tr>")
end

html.print("<tr>")
html.print("<td>Upload Package</td>")
html.print("<td><input type=file name=ul_pkg title='choose the .ipk file to install from your hard drive'> </td>")
html.print("<td align=center><input type=submit name=button_ul_pkg value=Upload title='install the package'")
if tunnel_active then
    html.print(" disabled><br><small>Disabled: Tunnels enabled</small>")
else
    html.print(">")
end
html.print("</td>")
html.print("</tr>")

html.print("<tr>")
html.print("<td>Download Package</td>")
html.print("<td><select name=dl_pkg style='font-family:monospace'>")
html.print("<option value=default selected>- Select Package -</option>")
for _, dlp in ipairs(dl_pkgs)
do
    html.print("<option value=" .. dlp .. ">" .. dlp .. " " .. dlpkgver[dlp] .. "</option>")
end
html.print("</select>")
html.print("<input type=submit name=button_refresh_pkg value=Refresh title='download the list of available packages (warning: this takes a lot of space)'>")
html.print("<td align=center><input type=submit name=button_dl_pkg value=Download title='install the package'></td>")
html.print("</tr>")

html.print("<tr>")
html.print("<td>Remove Package</td>")
html.print("<td><select name=rm_pkg style='font-family:monospace'>")
html.print("<option value=default selected>- Select Package -</option>")
for _, pkg in ipairs(pkgs)
do
    html.print("<option value=" .. pkg .. " " .. (permpkg[pkg] and "disabled" or "") .. ">" .. pkg .. " " .. pkgver[pkg] .. "</option>")
end
html.print("</select></td>")
html.print("<td align=center><input type=submit name=button_rm_pkg value=Remove title='remove the selected package'></td>")
html.print("</tr>")

html.print("</table></td></tr>")

html.print("<tr><td colspan=3><hr></td></tr>")

-- ssh keys
html.print("<tr><td align=center>")
html.print("<table cellspacing=10>")
html.print("<tr><th colspan=3>Authorized SSH Keys</th></tr>")

if #key_output > 0 then
    html.print("<tr><td colspan=3 align=center><table><tr><td><b><pre>")
    html.print(word_wrap(80, key_output))
    html.print("</pre></b></td></tr></table></td></tr>")
end

html.print("<tr>")
html.print("<td>Upload Key</td>")
html.print("<td><input type=file name=sshkey title='choose the id_rsa.pub file to install from your hard drive'></td>")
html.print("<td align=center><input type=submit name=button_ul_key value=Upload title='install the key'")
html.print("></td>")
html.print("</tr>")

html.print("<tr>")
html.print("<td>Remove Key</td>")
html.print("<td><select name=rm_key style='font-family:monospace'>")
html.print("<option value=default selected>- Select Key -</option>")
for _, key in ipairs(keys)
do
    html.print("<option value=" .. key .. ">" .. key .. "</option>")
end
html.print("</select>")
html.print("<td align=center><input type=submit name=button_rm_key value=Remove title='remove the selected key'></td>")
html.print("</tr>")

html.print("</table></td></tr>")

html.print("<tr><td colspan=3><hr></td></tr>")

html.print("<tr><th colspan=3>Support Data</th></tr>")
html.print("<tr><td colspan=3 align=center><a href=/cgi-bin/supporttool.lua>Download Support Data</a></td></tr>")

html.print("<tr><td colspan=3><hr></td></tr>")

html.print("</table>")
html.print("</td></tr>")
html.print("</table>")

html.print("</form>")
html.print("</center>")
html.footer()
html.print("</body>")
html.print("</html>")
http_footer()
