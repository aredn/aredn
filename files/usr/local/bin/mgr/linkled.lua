
local link1led

function linkled()
    local link = hardware.get_link_led()
    
    -- Reset leds
    utils.write_all(link1led .. "/trigger", "none")
    utils.write_all(link1led .. "/brightness", "0")

    while true
    do
        local nei = utils.fetch_json("http://127.0.0.1:9090/neighbors")
        if nei and #nei.neighbors > 0 then
            utils.write_all(link1led .. "/brightness", "1")
        else
            utils.write_all(link1led .. "/brightness", "0")
        end
        wait_for_ticks(11)
    end
end

return linkled
