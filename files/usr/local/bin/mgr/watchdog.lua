
local watchdogfile = "/tmp/olsrd.watchdog"
local pidfile = "/var/run/olsrd.pid"
local logfile = "/tmp/olsrd.log"

function olsrd_restart()
    -- print "olsrd_restart"

    os.execute("/etc/init.d/olsrd restart")

    local lines = utils.read_all(logfile)
    lines[#lines + 1] = utils.uptime() .. " " .. os.date()
    local start = 1
    if #lines > 300 then
        start = #lines - 275
    end
    local f = io.open(logfile, "w")
    if f then
        for i = start, #lines
        do
            f:write(lines[i] .. "\n")
        end
        f:close()
    end
end

function watchdog()
    while true
    do
        wait_for_ticks(21)

        local pid = utils.read_all(pidfile)[1]
        if pid and posix.sys.stat.stat("/proc/" .. pid) then
            if posix.sys.stat.stat(watchdogfile) then
                os.remove(watchdogfile)
            else
                olsrd_restart()
            end
        else
            local pids = utils.split(utils.system_run("pidof olsrd")[1])
            if #pids == 1 then
                utils.write_all(pidfile, pids[1]);
            elseif #pids == 0 then
                olsrd_restart()
            end
        end

    end
end

return watchdog
