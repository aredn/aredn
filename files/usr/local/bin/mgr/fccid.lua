
function fccid()
    local id = string.format("ID: %s", utils.system_run("uname -n")[1])
    local wifiif = uci.cursor():get("network", "wifi", "ifname")
    local ip = utils.system_run("ip addr show " .. wifiif .. " | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/'")[1]
    local udp = socket.udp()
    udp:setoption("broadcast", true)
    udp:setsockname(ip, 4919)
    udp:setpeername("10.255.255.255", 4919)
    while true
    do
        if posix.sys.stat.stat("/etc/config/run-fccid") then
            udp:send(id)
        end
        wait_for_ticks(5 * 60) -- 5 minutes
    end
end

return fccid
