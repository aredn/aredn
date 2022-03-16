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
    if not nixio.fs.stat("/tmp/web") then
        nixio.fs.mkdir("/tmp/web")
    end
    if not nixio.fs.readlink("/tmp/web/style.css") then
        nixio.fs.symlink("/www/aredn.css", "/tmp/web/style.css")
    end
    html.print("<link id='stylesheet_css' rel=StyleSheet href='/style.css?" .. os.time() .. "' type='text/css'>")
    if close then
        html.print("</head>")
    end
end

function html.footer()
    html.print "<div class=\"Page_Footer\"><hr><p class=\"PartOfAREDN\">Part of the AREDN&trade; Project. For more details please <a href=\"/about.html\" target=\"_blank\">see here</a></p></div>"
end

function html.alert_banner()
    local aredn_message = read_all("/tmp/aredn_message")
    local local_message = read_all("/tmp/local_message")

    html.print("<div class=\"TopBanner\">")
    html.print("<div class=\"LogoDiv\"><a href=\"http://localnode.local.mesh:8080\" title=\"Go to localnode\"><img src=\"/AREDN.png\" class=\"AREDNLogo\"></img></a></div>")

    local supported = aredn.hardware.supported()
    if supported == 0 then
        html.print("<div style=\"padding:5px;background-color:#FF4719;color:black;border:1px solid #ccc;width:600px;\"><a href=\"/cgi-bin/sysinfo\">!!!! UNSUPPORTED DEVICE !!!!</a></div>")
    elseif supported == -2 then
        html.print("<div style=\"padding:5px;background-color:yellow;color:black;border:1px solid #ccc;width:600px;\"><a href=\"/cgi-bin/sysinfo\"> !!!! THIS DEVICE IS STILL BEING TESTED !!!!</a></div>")
    elseif supported ~= 1 then
        html.print("<div style=\"padding:5px;background-color:yellow;color:black;border:1px solid #ccc;width:600px;\"><a href=\"/cgi-bin/sysinfo\">!!!! UNTESTED HARDWARE !!!!</a></div>")
    end

    if aredn_message and #aredn_message > 0 then
        html.print("<div style=\"padding:5px;background-color:#fff380;color:black;border:1px solid #ccc;width:600px;\"><strong>AREDN Alert(s):</strong><br /><div style=\"text-align:left;\">" .. aredn_message .. "</div></div>")
    end
    if local_message and #local_message > 0 then
        html.print("<div style=\"padding:5px;background-color:#fff380;color:black;border:1px solid #ccc;width:600px;\"><strong>Local Alert(s):</strong><br /><div style=\"text-align:left;\">" .. local_message .. "</div></div>")
    end

    html.print("</div>")
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

if not aredn then
    aredn = {}
end
aredn.html = html
return html
