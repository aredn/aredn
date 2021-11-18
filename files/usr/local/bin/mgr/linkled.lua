
local link1led

function linkled()
    local link = aredn.hardware.get_link_led()
    
    -- Reset leds
    write_all(link .. "/trigger", "none")
    write_all(link .. "/brightness", "0")

    while true
    do
        local nei = fetch_json("http://127.0.0.1:9090/neighbors")
        if nei and #nei.neighbors > 0 then
            write_all(link .. "/brightness", "1")
        else
            write_all(link .. "/brightness", "0")
        end
        wait_for_ticks(11)
    end
end

return linkled
