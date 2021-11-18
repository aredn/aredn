
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
    local css = nixio.fs.stat("/tmp/web/style.css", "type")
    if not (css and css == "lnk") then
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

function html.print(line)
    -- html output is defined in aredn.http
    -- this is a bit icky at the moment :-()
    if http_output then
        http_output.write(line .. "\n")
    else
        print(line)
    end
end

if not aredn then
    aredn = {}
end
aredn.html = html
return html
