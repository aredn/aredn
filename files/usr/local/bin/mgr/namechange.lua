
function namechange()

    local count = 0
    while true
    do
        if not nixio.fs.stat("/tmp/namechange") and count < 12 then
            count = count + 1
            wait_for_ticks(5)
        else
            os.remove("/tmp/namechange")
            do_namechange()
            count = 0
        end
    end

end

if not file_exists("/tmp/node.history") then
    io.open("/tmp/node.history", "w+"):close()
end

function do_namechange()
    -- Do nothing if olsrd is not running
    if shell_capture("pidof olsrd") == "" then
        return
    end

    local uptime = aredn_info.getUptime()

    local hosts = {}
    local history = {}

    -- Load the hosts file
    for line in io.lines("/var/run/hosts_olsr")
    do
        local v = line:splitWhiteSpace()
        local ip = v[1]
        local name = v[2]
        local originator = v[4]
        local mid = v[5]
        if ip and string.match(ip, "^%d") and originator and originator ~= "myself" and (ip == originator or mid == "(mid") then
            if hosts[ip] then
                hosts[ip] = hosts[ip] .. "/" .. name
            else
                hosts[ip] = name
            end
        end
    end

    -- Find the current neighbors
    local links = fetch_json("http://127.0.0.1:9090/links")
    if #links.links == 0 then
        return
    end
    for i, link in ipairs(links.links)
    do
        history[link.remoteIP] = { age = uptime, name = hosts[link.remoteIP] or "" }
    end

    -- load the strip the current history
    for line in io.lines("/tmp/node.history")
    do
        local v = line:splitWhiteSpace()
        local ip = v[1]
        local age = 0
        if v[2] then
            age = math.floor(v[2])
        end
        local name = v[3]
        if age and not history[ip] and uptime - age < 86400 then
            history[ip] = { age = age, name = name or "" }
        end
    end

    -- write the new history
    local f = io.open("/tmp/node.history", "w")
    if f then
        for k,v in pairs(history)
        do
            f:write(string.format("%s %d %s\n", k, v.age, v.name))
        end
        f:close()
    end

end

return namechange
