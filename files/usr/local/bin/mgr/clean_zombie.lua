
function clean_zombie()
    while true
    do
        clean()
        wait_for_ticks(60) -- 1 minute
    end
end

local zombies = { "iw" }

local log = aredn.log.open("/tmp/zombie.log", 12000)

function clean()
    for i, name in ipairs(zombies)
    do
        local pids = capture("pidof " .. name):splitWhiteSpace()
        for j, pid in ipairs(pids)
        do
            local zombie = false
            local ppid = nil
            local all = read_all("/proc/" .. pid .. "/status")
            if all then
                for k, line in ipairs(all:splitNewLine())
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
                    nixio.kill(ppid, 9)
                end
            end
        end
    end
    log:flush()
end

return clean_zombie
