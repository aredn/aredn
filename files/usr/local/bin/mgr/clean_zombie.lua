
function clean_zombie()
    while true
    do
        clean()
        wait_for_ticks(60) -- 1 minute
    end
end

local zombies = { "iw" }

utils.log_start("/tmp/zombie.log", 100)

function clean()

    for i, name in ipairs(zombies)
    do
        local pids = utils.split(utils.system_run("pidof " .. name)[1])
        for j, pid in ipairs(pids)
        do
            local zombie = false
            local ppid
            for k, line in ipairs(utils.read_all("/proc/" .. pid .. "/status"))
            do
                -- Look for a zombie
                local m = string.match(line, "State:%sZ")
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
            if not ppid then
                posix.signal.kill(ppid, posix.signal.SIGKILL)
                utils.log("Killed " .. ppid)
            end
        end
    end

    utils.log_end()
end

return clean_zombie
