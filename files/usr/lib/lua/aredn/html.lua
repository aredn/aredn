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

require("nixio")

local html = {}

function html.header(title, close)
    html.print("<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">")
    html.print("<html>")
    html.print("<head>")
    html.print("<title>" .. title .. "</title>")
    html.print("<meta http-equiv='expires' content='0'>")
    html.print("<meta http-equiv='cache-control' content='no-cache'>")
    html.print("<meta http-equiv='pragma' content='no-cache'>")
    html.print("<meta name='robots' content='noindex'>")

    -- set up the style sheet
    local link = nixio.fs.readlink("/tmp/web/style.css")
    if not link then
        if not nixio.fs.stat("/tmp/web") then
            nixio.fs.mkdir("/tmp/web")
        end
        link = "/www/aredn.css"
        nixio.fs.symlink(link, "/tmp/web/style.css")
    end
    html.print("<link id='stylesheet_css' rel=StyleSheet href='/style.css?_=" .. link .. "' type='text/css'>")
    if close then
        html.print("</head>")
    end
end

function html.footer()
    html.print "<div class=\"Page_Footer\"><hr><p class=\"PartOfAREDN\">Part of the AREDN&trade; Project. For more details please <a href=\"/about.html\" target=\"_blank\">see here</a></p></div>"
end

function html.alert_banner()
    html.print("<div class=\"TopBanner\">")
    html.print("<div class=\"LogoDiv\"><a href=\"http://localnode.local.mesh:8080\" title=\"Go to localnode\"><img src=\"/AREDN.png\" class=\"AREDNLogo\"></img></a></div>")
    if not aredn.hardware.supported() then
        html.print("<center><div style=\"padding:5px;background-color:#FF4719;color:black;border:1px solid #ccc;width:600px;\"><a href=\"/cgi-bin/sysinfo\">!!!! UNSUPPORTED DEVICE !!!!</a></div></center>")
    end
    html.print("</div>")
end

function html.msg_banner()
    html.print("<div class=\"TopBanner\">")
    local aredn_message = read_all("/tmp/aredn_message")
    local local_message = read_all("/tmp/local_message")
    if aredn_message and #aredn_message > 0 then
        html.print("<div style=\"padding:5px;background-color:#fff380;color:black;border:1px solid #ccc;width:600px;\"><strong>AREDN Messages:</strong><br /><div style=\"text-align:left;\">" .. aredn_message .. "</div></div>")
    end
    if local_message and #local_message > 0 then
        html.print("<div style=\"padding:5px;background-color:#fff380;color:black;border:1px solid #ccc;width:600px;\"><strong>Local Messages:</strong><br /><div style=\"text-align:left;\">" .. local_message .. "</div></div>")
    end
    html.print("</div>")
end

function html.navbar_user(selected)
    local opath = package.path
    package.path = '/www/cgi-bin/?;' .. package.path
    local order = {}
    local navs = {}
    for file in nixio.fs.dir("/www/cgi-bin/nav/user")
    do
        order[#order + 1] = file
        navs[file] = require("nav.user." .. file)
    end
    table.sort(order)
    html.print("<nobr>")
    html.print("<a href='/help.html' target='_blank'>Help</a>")
    html.print("&nbsp;&nbsp;<input type=button name=refresh value=Refresh title='Refresh this page' onclick='window.location.reload()'>")
    for _, key in ipairs(order)
    do
        local nav = navs[key]
        if nav then
            html.print("&nbsp;&nbsp;<button type=button onClick='window.location=\"" .. nav.href .. "\"' title='" .. (nav.title or "") .. "'>" .. nav.display .. "</button>")
        end
    end
    html.print("&nbsp;&nbsp;<select name=\"css\" size=\"1\" onChange=\"form.submit()\" >")
    html.print("<option>Select a theme</option>")
    for file in nixio.fs.glob("/www/*.css")
    do
        if file ~= "/www/style.css" then
            file = file:match("/www/(.*).css")
            html.print("<option value=\"" .. file .. ".css\">" .. file .. "</option>")
        end
    end
    html.print("</select>")
    html.print("</nobr>")
    package.path = opath
end

function html.navbar_admin(selected)
    local opath = package.path
    package.path = '/www/cgi-bin/?;' .. package.path
    local order = {}
    local navs = {}
    for file in nixio.fs.dir("/www/cgi-bin/nav/admin")
    do
        order[#order + 1] = file
        navs[file] = require("nav.admin." .. file)
    end
    table.sort(order)
    html.print("<table cellpadding=5 border=0 align=center width='" .. (#order * 120) .. "px'><tr><td colspan=100%><hr></td></tr><tr>")
    local width = math.floor(100 / #order) .. "%"
    for _, key in ipairs(order)
    do
        local nav = navs[key]
        if nav then
            html.print("<td align=center width=" .. width .. (nav.href == selected and " class='navbar_select'" or "") .. "><a href='" .. nav.href .. "'>" .. nav.display .. "</a></td>")
        end
    end
    html.print("</tr><tr><td colspan=100%><hr></td></tr></table>")
    package.path = opath
end

function html.print(line)
    -- html output is defined in aredn.http
    -- this is a bit icky at the moment :-()
    if http_output then
        http_output:write(line .. "\n")
    else
        print(line)
    end
end

function html.write(str)
    if http_output then
        http_output:write(str)
    else
        io.write(str)
    end
end

if not aredn then
    aredn = {}
end
aredn.html = html
return html
