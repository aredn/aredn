
function fccid()
    local id = string.format("ID: %s", shell_capture("uname -n"))
    local ip = aredn_info.getInterfaceIPAddress("wifi")
    local udp = socket.udp()
    udp:setoption("broadcast", true)
    udp:setsockname(ip, 4919)
    udp:setpeername("10.255.255.255", 4919)
    while true
    do
        if nixio.fs.stat("/etc/config/run-fccid") then
            udp:send(id)
        end
        wait_for_ticks(5 * 60) -- 5 minutes
    end
end

return fccid
