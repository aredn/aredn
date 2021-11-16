
function clean_zombie()
    while true
    do
        clean()
        wait_for_ticks(60) -- 1 minute
    end
end

local zombies = { "iw" }

local log = utils.log.start("/tmp/zombie.log", 100)

function clean()
    for i, name in ipairs(zombies)
    do
        local pids = utils.split(utils.system_run("pidof " .. name)[1])
        for j, pid in ipairs(pids)
        do
            local zombie = false
            local ppid = nil
            for k, line in ipairs(utils.read_all("/proc/" .. pid .. "/status"))
            do
                -- Look for a zombie
                local m = string.match(line, "State:%s[ZT]")
                if m then
                    zombie = true
                end
                if zombie then
                    m = string.match(line, "PPid:%s([0-9]*)")
                    if m then
                        ppid = m
                        break
                    end
                end
            end
            if ppid and ppid ~= 1 then
                log:write("Killed " .. ppid)
                posix.signal.kill(ppid, posix.signal.SIGKILL)
            end
        end
    end
    log:flush()
end

return clean_zombie
