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
aredn.olsr = require("aredn.olsr")
require("iwinfo")

local html = aredn.html

local node = aredn.info.get_nvram("node")
if node == "" then
    node = "NOCALL"
end
local tactical = aredn.info.get_nvram("tactical")
local config = aredn.info.get_nvram("config")
if config == "" or nixio.fs.stat("/etc/config.mesh", "type") ~= "dir" then
    config = "not set"
end
local wifiif = aredn.hardware.get_iface_name("wifi")
local my_ip = aredn.hardware.get_interface_ip4(wifiif)
local phy = iwinfo.nl80211.phyname(wifiif)

local chanbw -- fix me

-- post data

if not nixio.fs.stat("/tmp/web") then
    nixio.fs.mkdir("/tmp/web")
end

--

local cursor = uci.cursor()
local node_desc = cursor:get("system", "@system[0]", "description")
local lat_lon = "<strong>Location Not Available</strong>"
local lat = cursor:get("aredn", "@location[0]", "lat")
local lon = cursor:get("aredn", "@location[0]", "lon")
if lat ~= "" and lon ~= "" then
    lat_lon = string.format("<center><strong>Location: </strong> %s %s</center>", lat, lon)
end

local routes = {}
local links = {}
local neighbor = {}
local wangateway = {}
local ipalias = {}
local localhosts = {}
local dtd = {}
local midcount = {}
local hosts = {}
local services = {}
local history = {}

local olsr_total = 0
local olsr_nodes = 0
for i, node in ipairs(aredn.olsr.getOLSRRoutes())
do
    olsr_total = olsr_total + 1
    if node.genmask ~= 32 then
        olsr_nodes = olsr_nodes + 1
    end
    if node.etx <= 50 then
        routes[node.destination] = { etx = node.etx }
    end
end

-- load up arpcache
local arpcache = {}
arptable(function(a)
    arpcache[a["IP address"]] = a
end)

local prefix = "/sys/kernel/debug/ieee80211/" .. phy .. "/netdev:" .. wifiif .. "/stations/"
for i, node in ipairs(aredn.olsr.getOLSRLinks())
do
    links[node.remoteIP] = { lq = node.linkQuality, nlq = node.neighborLinkQuality, mbps = 0 }
    neighbor[node.remoteIP] = true
    local mac = arpcache[node.remoteIP]
    --[[ if mac then
        local f = io.open(prefix .. mac .. "/rc_stats_csv", "r")
        if f then
            for line in f:lines()
            do
                -- 802.11b/n
                local mbps = line:match("")
                if mbps then
                elseif line:match("^A") then
                    -- 802.11a/b/g
                end
            end
            links[node.remoteIP].mbps = --
            f:close()
        end
    end
    --]]
end

-- discard
arpcache = nil

for i, node in ipairs(aredn.olsr.getOLSRHNA())
do
    if node.destination == "0.0.0.0" then
        wangateway[node.gateway] = true
    end
end

for i, node in ipairs(aredn.olsr.getOLSRMid())
do
    local ip = node.main.ipAddress
    for _, alias in ipairs(node.aliases)
    do
        local aip = alias.ipAddress
        ipalias[aip] = ip
        neighbor[aip] = true
        if links[aip] then
            neighbor[ip] = true
        end
    end
end

-- load the local hosts file
for line in io.lines("/etc/hosts")
do
    if line:match("^10%.") then
        local ip, name = line:match("([%d%.]+)%s+(%S+)")
        if name then
            local name9 = name:sub(1, 9)
            if name9 ~= "localhost" and name9 ~= "localnode" then
                local name7 = name:sub(1, 7)
                if name7 ~= "localap" and name7 ~= "dtdlink" then
                    if not name:match("%.") then
                        name = name .. ".local.mesh"
                    end
                    local tac = line:match("[%d%.]+%s+%S+%s+(%S)")
                    if not tac then
                        tac = ""
                    end
                    if not localhosts[my_ip] then
                        localhosts[my_ip] = { hosts = {}, noprops = {}, aliases = {} }
                    end
                    local host = localhosts[my_ip]
                    if ip == my_ip then
                        host.tactical = tac
                        host.name = name
                    else
                        host.hosts[#host.hosts + 1] = name
                    end
                    if tac == "#NOPROP" then
                        host.noprops[#host.noprops + 1] = name
                    end
                    if tac == "#ALIAS" then
                        host.aliases[#host.aliases + 1] = name
                    end
                end
            end
        end
    end
end

-- load the olsr hosts file
for line in io.lines("/var/run/hosts_olsr")
do
    local ip, name, originator = line:match("^([%d%.]+)%s+(%S+)%s+%S+%s+(%S+)")
    if ip and originator and originator ~= "myself" and (routes[ip] or routes[originator]) then
        local etx = routes[ip]
        if not etx then
            etx = routes[originator]
        end
        etx = etx.etx
        if not name:match("%.") or name:match("^mid%.[^%.]*$") then
            name = name .. ".local.mesh"
        end
        if ip == originator then
            if not hosts[originator] then
                hosts[originator] = { hosts = {} }
            end
            local host = hosts[originator]
            if host.name then
                host.tactical = name
            else
                host.name = name
                host.etx = etx
            end
        elseif name:match("^dtdlink%.") then
            dtd[originator] = true
            if links[ip] then
                links[ip].dtd = true
            end
        elseif name:match("^mid%d+%.") then
            if not midcount[originator] then
                midcount[originator] = 1
            else
                midcount[originator] = midcount[originator] + 1
            end
            if links[ip] then
                links[ip].tun = true
            end
        else
            if not hosts[originator] then
                hosts[originator] = { hosts = {} }
            end
            local host = hosts[originator]
            host.hosts[#host.hosts + 1] = name
        end
    end
end

-- discard
routes = nil

for line in io.lines("/var/run/services_olsr")
do
    if line:match("^%w") then
        local url, name = line:match("^(.*)|.*|(.*)$")
        if name then
            local protocol, host, port, path = url:match("^([%w][%w%+%-%.]+)%://(.+):(%d+)/(.*)")
            if path then
                local name, originator = name:match("(.*)%s*#(.*)")
                if originator == " my own service" or (hosts[originator] and hosts[originator].name) then
                    if not host:match("%.") then
                        host = host .. ".local.mesh"
                    end
                    if not services[host] then
                        services[host] = {}
                    end
                    if not services[host][name] then
                        if port ~= "0" then
                            services[host][name] = "<a href='" .. protocol .. "://" .. host .. ":" .. port .. "/" .. path .. "' target='_blank'>" .. name .. "</a>"
                        else
                            services[host][name] = name
                        end
                    end
                end
            end
        end
    end
end

-- load the node history
for line in io.lines("/tmp/node.history")
do
    local ip, age = line:match("^(.*) (.*)")
    if age then
        local host = line:match("^.* .* (.*)")
        if not host then
            host = ""
        else
            host = host:gsub("/", " / ")
        end
        history[ip] = { age = age, host = host }
    end
end

http_header()
html.header(node .. " mesh status", false)
local automesh = nixio.fs.stat("/tmp/web/automesh");
if automesh then
    html.print("<meta http-equiv='refresh' content='10;url=/cgi-bin/mesh.lua'>")
end
html.print("</head>")

html.print("<body><form method=post action=/cgi-bin/mesh enctype='multipart/form-data'>")
html.print("<input type=hidden name=reload value=1>")
html.print("<center>")

html.alert_banner()

html.print("<h1>" .. node .. " mesh status</h1>")

html.print(lat_lon)
if node_desc ~= "" then
    html.print("<table id='node_description_display'><tr><td>" .. node_desc .. "</td></tr></table>")
end
html.print("<hr><nobr>")

if authmesh then
    html.print("<input type=submit name=stop value=Stop title='Abort continuous status'>")
else
    html.print("<input type=submit name=refresh value=Refresh title='Refresh this page'>")
    html.print("&nbsp;&nbsp;")
    html.print("<input type=submit name=auto value=Auto title='Automatic page refresh'>")
end

html.print("&nbsp;&nbsp;")
html.print("<button type=button onClick='window.location=\"status\"' title='Return to the status page'>Quit</button>")

html.print("</nobr><br><br>")

if not next(localhosts) and not next(links) then
    html.print("No other nodes are available.")
    html.print("</center></form>")
    html.footer()
    html.print("</body></html>")
    os.exit(0)
end

html.print("<table><tr><td valign=top><table>")

-- show local hosts

html.print("<tr><th colspan=4 align=left><nobr>Local Hosts</nobr></th><th align=left>Services</th></tr>")
html.print("<tr><td colspan=5><hr></td></tr>")

if next(localhosts) then
    local rows = {}
    for ip, host in pairs(localhosts)
    do
        local localpart = host.name:match("(.*)%.")
        local tactical = ""
        if host.tactical ~= "" then
            tactical = " / " .. host.tactical
        end
        local row = "<tr><td valign=top><nobr>" .. localpart .. tactical .. "</nobr>"
        if wangateway[ip] then
            row = row .. " &nbsp; <small>(wan)</small>"
        end
        row = row .. "</td><td colspan=3>&nbsp;</td><td>"
        if services[host.name] then
            for n, v in pairs(services[host.name])
            do
                row = row .. "<nobr>" .. v .. "</nobr><br>"
            end
        end
        row = row .. "</td></tr>"
        -- add locally advertised dmz hosts
        for i, dmzhost in ipairs(host.hosts)
        do
            local nopropd = false
            local aliased = false
            for _, v in ipairs(host.noprops)
            do
                if v == dmzhost then
                    nopropd = true;
                    break
                end
            end
            for _, v in ipairs(host.aliases)
            do
                if v == dmzhost then
                    aliased = true;
                    break
                end
            end
            local localpart = dmzhost:match("(.*)%.local%.mesh")
            if not nopropd and not aliased then
                row = row .. "<tr><td valign=top><nobr>&nbsp;<img src='/dot.png'>" .. localpart .. "</nobr></td>"
            elseif aliased then
                row = row .. "<tr><td class=aliased-hosts valign=top title='Aliased Host'><nobr>&nbsp;<img src='/dot.png'>" .. localpart .. "</nobr></td>"
            else
                row = row .. "<tr><td class=hidden-hosts valign=top title='Non Propagated Host'><nobr>&nbsp;<img src='/dot.png'>" .. localpart .."</nobr></td>"
            end
            if services[dmzhost] then
                for n, v in pairs(services[dmzhost])
                do
                    row = row .. "<nobr>" .. v .. "</nobr><br>"
                end
            end
            row = row .. "</td></tr>"
        end
        rows[#rows + 1] = { key = host.name, row = row }
    end
    table.sort(rows, function(a,b) return a.key < b.key end)
    for _, row in ipairs(rows)
    do
        html.print(row.row)
    end
    -- discard
    rows = nil
else
    html.print("<tr><td>none</td></tr>")
end

-- show remote nodes

html.print("<tr><td>&nbsp;</td></tr>")
html.print("<tr><th align=left><nobr>Remote Nodes</nobr></th><th>&nbsp;&nbsp;</th><th>ETX</th><th>&nbsp;&nbsp;</th><th align=left>Services</th></tr>")
html.print("<tr><td colspan=5><hr></td></tr>")

local rows = {}
for ip, host in pairs(hosts)
do
    if not neighbor[ip] and host.name then
        local localpart = host.name:match("(.*)%.local%.mesh")
        local tactical = ""
        if host.tactical then
            tactical = " / " .. host.tactical
        end
        local etx = string.format("%.2f", host.etx)
        local row = "<tr><td valign=top><nobr><a href='http://" .. host.name .. ":8080/'>" .. localpart .. tactical .. "</a>"
        local nodeiface
        local mycount = 0
        if midcount[ip] then
            mycount = midcount[ip]
        end
        if dtd[ip] then
            mycount = mycount - 1
        end
        if hosts[ip].tactical then
            mycount = mycount - 1
        end
        if mycount > 0 then
            nodeiface = "tun*" .. mycount
        end
        if wangateway[ip] then
            if nodeiface then
                nodeiface = nodeiface .. ",wan"
            else
                nodeiface = "wan"
            end
        end
        if nodeiface then
            row = row .. " &nbsp; <small>(" .. nodeiface .. ")</small>"
        end
        row = row .. "</nobr></td><td></td><td align=right valign=top>" .. etx .. "</td><td></td><td>"
        if services[host.name] then
            for _, v in pairs(services[host.name])
            do
                row = row .. "<nobr>" .. v .. "</nobr><br>"
            end
        end
        row = row .. "</td></tr>"
        -- add locally advertised dmz hosts
        for _, dmzhost in ipairs(host.hosts)
        do
            local localpart = dmzhost:match("(.*)%.local%.mesh")
            row = row .. "<tr><td valign=top><nobr>&nbsp;<img src='/dot.png'>" .. localpart .. "</nobr></td>"
	        row = row .. "<td colspan=3></td><td>"
            if services[dmzhost] then
                for _, v in pairs(services[dmzhost])
                do
                    row = row .. "<nobr>" .. v .. "</nobr><br>"
                end
            end
            row = row .. "</td></tr>"
        end
        rows[#rows + 1] = { key = host.etx, row = row }
    end
end

if #rows > 0 then
    table.sort(rows, function(a,b) return a.key < b.key end)
    for _, row in ipairs(rows)
    do
        html.print(row.row)
    end
    -- discard
    rows = nil
else
    html.print("<tr><td>none</td></tr>")
end

-- discard
neighbor = nil

html.print("</table></td><td width=20>&nbsp;</td><td valign=top><table>")

-- show current neighbors

html.print("<tr><th align=left><nobr>Current Neighbors</nobr></th><th>&nbsp;&nbsp;</th><th>LQ</th><th>NLQ</th><th>TxMbps</th><th>&nbsp;&nbsp;</th><th align=left>Services</th></tr>")
html.print("<tr><td colspan=7><hr></td></tr>")

local rows = {}
local neighservices = {}
for ip, link in pairs(links)
do
    local ipmain = ipalias[ip]
    if not ipmain then
        ipmain = ip
    end
    local name = ipmain
    local localpart = ipmain
    local tactical = ""
    local host = hosts[ipmain]
    if host then
        if host.name then
            name = host.name
            localpart = name:match("(.*)%.local%.mesh")
            if not localpart then
                localpart = name
            end
        end
        if host.tactical then
            tactical = " / " .. host.tactical
        end
    end
    if rows[name] then
        name = name .. " " -- avoid collision 2 links to same host {rf, dtd}
    end
    local no_space_host = name:match("(.*%S)%s*$")
    local row = "<tr><td valign=top><nobr><a href='http://" .. no_space_host .. ":8080/'>" .. localpart .. tactical .. "</a>"
    local nodeiface
    if ipmain ~= ip then
        if links[ip].dtd then
            nodeiface = "dtd"
        elseif links[ip].tun then
            nodeiface = "tun"
        else
            nodeiface = "?"
        end
    end
    if wangateway[ip] or wangateway[ipmain] then
        if nodeiface then
            nodeiface = nodeiface .. ",wan"
        else
            nodeiface = "wan"
        end
    end
    if nodeiface then
        row = row .. " &nbsp; <small>(" .. nodeiface .. ")</small>"
    end
    row = row .. string.format("</nobr></td><td></td><td align=right valign=top>%.0f%%</td><td align=right valign=top>%.0f%%</td><td align=right valign=top>%s</td><td></td><td>\n", 100 * link.lq, 100 * link.nlq, link.mbps)

    if not neighservices[name] then
        neighservices[name] = true
        if services[name] then
            for _, v in pairs(services[name])
            do
                row = row .. "<nobr>" .. v .. "</nobr><br>"
            end
        end
        row = row .. "</td></tr>"
        -- add advertised dmz hosts
        for _, dmzhost in ipairs(host.hosts)
        do
            local localpart = dmzhost:match("(.*)%.local%.mesh")
            row = row .. "<tr><td valign=top><nobr>&nbsp;<img src='/dot.png'>" .. localpart .. "</nobr></td>"
	        row = row .. "<td colspan=5></td><td>"
            if services[dmzhost] then
                for _, v in pairs(services[dmzhost])
                do
                    row = row .. v .. "<br>"
                end
            end
            row = row .. "</td></tr>"
        end
    end

    rows[#rows + 1] = { key = name, row = row }
end
if #rows > 0 then
    table.sort(rows, function(a,b) return a.key < b.key end)
    for _, row in ipairs(rows)
    do
        html.print(row.row)
    end
    -- discard
    rows = nil
else
    html.print("<tr><td>none</td></tr>")
end

-- show previous neighbors

html.print("<tr><td>&nbsp;</td></tr>")
html.print("<tr><th colspan=6 align=left><nobr>Previous Neighbors</nobr></th><th align=left>When</th></tr>")
html.print("<tr><td colspan=7><hr></td></tr>")

--

-- footer

html.print("<tr><td>&nbsp;</td></tr>")
html.print("<tr><th align='left'>OLSR Entries</th></tr>")
html.print("<tr><td colspan=7><hr></td></tr>")
html.print("<tr><td>Total</td><td>&nbsp;</td><td align='right'>" .. olsr_total .. "</td></tr>")
html.print("<tr><td>Nodes</td><td>&nbsp;</td><td align='right'>" .. olsr_nodes .. "</td></tr>")
html.print("</table></td></tr></table>")

--  end
html.print("</center>")
html.print("</form>")

html.footer();
html.print("</body>")
html.print("</html>")
