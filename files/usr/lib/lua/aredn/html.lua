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
    html.print "<div class=\"Page_Footer\"><hr><p class=\"PartOfAREDN\">Part of the AREDN&#174; Project. For more details please <a href=\"/about.html\" target=\"_blank\">see here</a></p></div>"
end

function html.alert_banner()
    html.print("<div class=\"TopBanner\">")
    html.print("<div class=\"LogoDiv\"><a href=\"http://localnode.local.mesh:8080\" title=\"Go to localnode\"><img src=\"/AREDN.png\" class=\"AREDNLogo\"></img></a></div>")
    if not aredn.hardware.supported() then
        html.print("<center><div style=\"padding:5px;background-color:#FF4719;color:black;border:1px solid #ccc;width:600px;\"><a href=\"/cgi-bin/sysinfo\">!!!! UNSUPPORTED DEVICE !!!!</a></div></center>")
    end
    local f = io.open("/etc/cron.boot/reinstall-packages")
    if f then
        f:close()
        f = io.open("/etc/package_store/catalog.json")
        if f then
            f:close()
            html.print("<center><div style=\"padding:5px;color:black;border:1px solid #ccc;width:650px;\">Packages are being reinstalled in the background. This can take a few minutes.</div></center>")
        end
    end
    html.print("</div>")
end

function html.msg_banner()
    html.print("<div class=\"TopBanner\">")
    local aredn_message = read_all("/tmp/aredn_message")
    local local_message = read_all("/tmp/local_message")
    if aredn_message and #aredn_message > 0 then
        html.print("<div style=\"padding:5px;background-color:#fff380;color:black;border:1px solid #ccc;width:700px;\"><strong>AREDN Messages:</strong><br /><div style=\"text-align:left;\">" .. aredn_message .. "</div></div>")
    end
    if local_message and #local_message > 0 then
        html.print("<div style=\"padding:5px;background-color:#fff380;color:black;border:1px solid #ccc;width:700px;\"><strong>Local Messages:</strong><br /><div style=\"text-align:left;\">" .. local_message .. "</div></div>")
    end
    html.print("</div>")
end

function html.navbar_user(selected, config_mode)
    local order = {}
    local navs = {}
    if config_mode then
        _G.config_mode = config_mode
    end
    for file in nixio.fs.dir("/usr/lib/lua/aredn/nav/user")
    do
        order[#order + 1] = file
        navs[file] = require("aredn.nav.user." .. file:match("^(.*)%.lua$"))
    end
    table.sort(order)
    html.print("<nobr>")
    html.print("<a href='/help.html' target='_blank'>Help</a>")
    html.print("&nbsp;&nbsp;<input type=button name=refresh value=Refresh title='Refresh this page' onclick='window.location.reload()'>")
    for _, key in ipairs(order)
    do
        local nav = navs[key]
        if type(nav) == "table" then
            html.print("&nbsp;&nbsp;<button type=button onClick='window.location=\"" .. nav.href .. "\"' title='" .. (nav.hint or "") .. "' " .. (nav.enable == false and "disabled" or "") .. ">" .. nav.display .. "</button>")
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
end

function html.navbar_admin(selected)
    local order = {}
    local navs = {}
    for file in nixio.fs.dir("/usr/lib/lua/aredn/nav/admin")
    do
        order[#order + 1] = file
        navs[file] = require("aredn.nav.admin." .. file:match("^(.*)%.lua$"))
    end
    table.sort(order)
    html.print("<table cellpadding=5 border=0 align=center width='" .. (#order * 120) .. "px'><tr><td colspan=100%><hr></td></tr><tr>")
    local width = math.floor(100 / #order) .. "%"
    for _, key in ipairs(order)
    do
        local nav = navs[key]
        if type(nav) == "table" then
            html.print("<td align=center width=" .. width .. (nav.href == selected and " class='navbar_select'" or "") .. ">")
            if nav.enable == false then
                html.print(nav.display .. "</td>")
            else
                html.print("<a href='" .. nav.href .. "'>" .. nav.display .. "</a></td>")
            end
        end
    end
    html.print("</tr><tr><td colspan=100%><hr></td></tr></table>")
end

function html.wait_for_reboot(delay, countdown, address)
    if address then
        address = [["http://]] .. address .. [[/cgi-bin/status"]]
    else
        address = [[window.origin + "/cgi-bin/status"]]
    end
    html.print([[
<script>
    const TIMEOUT = 5000;
    function reload() {
        const start = Date.now();
        const req = new XMLHttpRequest();
        req.open('GET', ]] .. address .. [[);
        req.onreadystatechange = function() {
            if (req.readyState === 4) {
                if (req.status === 200) {
                    window.location = ]] .. address .. [[;
                }
                else {
                    const time = Date.now() - start;
                    setTimeout(reload, time > TIMEOUT ? 0 : TIMEOUT - time);
                }
            }
        }
        req.timeout = TIMEOUT;
        try {
            req.send(null);
        }
        catch (_) {
        }
    }
    const start = Date.now()
    function cdown() {
        const div = document.getElementById("countdown");
        if (div) {
            let t = Math.round(]] .. countdown .. [[ - (Date.now() - start) / 1000);
            div.innerHTML = t <= 0 ? "..." : new Date(1000 * t).toISOString().substring(14, 19);
            const cdp = document.getElementById("cdprogress");
            if (cdp) {
                if (t < 0)
                    cdp.removeAttribute("value");
                else
                    cdp.setAttribute("value", cdp.getAttribute("max") - t);
            }
        }
    }
    setInterval(cdown, 1000);
    setTimeout(reload, ]] .. delay .. [[ * 1000);
</script>
    ]])
end

function html.reboot()
    require("aredn.info")
    require("aredn.hardware")
    require("aredn.http")
    require("uci")

    local node = aredn.info.get_nvram("node")
    if node == "" then
        node = "Node"
    end
    local lanip, _, lanmask = aredn.hardware.get_interface_ip4(aredn.hardware.get_iface_name("lan"))
    local browser = os.getenv("REMOTE_ADDR")
    local browser6 = browser:match("::ffff:([%d%.]+)")
    if browser6 then
        browser = browser6
    end
    local fromlan = false
    local subnet_change = false
    if lanip then
        fromlan = validate_same_subnet(browser, lanip, lanmask)
        if fromlan then
            lanmask = ip_to_decimal(lanmask)
            local cursor = uci.cursor()
            local cfgip = cursor:get("network", "lan", "ipaddr")
            local cfgmask = ip_to_decimal(cursor:get("network", "lan", "netmask"))
            if lanmask ~= cfgmask or nixio.bit.band(ip_to_decimal(lanip), lanmask) ~= nixio.bit.band(ip_to_decimal(cfgip), cfgmask) then
                subnet_change = true
            end
        end
    end
    http_header()
    if fromlan and subnet_change then
        html.header(node .. " rebooting", false);
        local cursor = uci.cursor()
        local wifiip = cursor:get("network", "wifi", "ipaddr")
        if not wifiip then
            wifiip = "localnode.local.mesh"
        end
        html.wait_for_reboot(20, 120, wifiip)
        html.print("</head><body><center>")
        html.print("<h1>" .. node .. " is rebooting</h1><br>")
        html.print("<h3>The LAN subnet has changed. You will need to acquire a new DHCP lease<br>")
        html.print("and reset any name service caches you may be using.</h3><br>")
        html.print("<h3>When the node reboots you get your new DHCP lease and reconnect with<br>")
        html.print("<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>or<br>")
        html.print("<a href='http://" .. node .. ".local.mesh:8080/'>http://" .. node .. ".local.mesh:8080/</a></h3>")
    else
        html.header(node .. " rebooting", false)
        html.wait_for_reboot(20, 120)
        html.print("</head><body><center>")
        html.print("<h1>" .. node .. " is rebooting</h1><br>")
        html.print("<h3>Your browser should return to this node after it has rebooted.</br><br>")
        html.print("If something goes astray you can try to connect with<br><br>")
        html.print("<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>")
        if node ~= "Node" then
            html.print("or<br><a href='http://" .. node .. ".local.mesh:8080/'>http://" .. node .. ".local.mesh:8080/</a></h3>")
        end
    end
    html.print("<br><h3><label for='cdprogress'>Rebooting: </label><progress id='cdprogress' max='120'/></h3>")
    html.print("<h1>Time Remaining: <span id='countdown'/></h1>")
    html.print("</center></body></html>")
    http_footer()
    os.execute("reboot >/dev/null 2>&1")
    os.exit()
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
