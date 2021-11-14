
local link1led

function linkled()
    local link
    local board_type = utils.read_all("/tmp/sysinfo/hardware_type")[1]
    if board_type == "airouter" then
        link = "/sys/class/leds/ubnt:green:globe"
    elseif board_type == "gl-ar150" then
        link = "/sys/class/leds/gl-ar150:orange:wlan"
    elseif board_type == "gl-ar300m" then
        link = "/sys/class/leds/gl-ar300m:green:wlan"
    elseif board_type == "gl-usb150" then
        link = "/sys/class/leds/gl-usb150:green:wlan"
    elseif board_type == "gl-ar750" then
        link = "/sys/class/leds/gl-ar750:white:wlan5g"
    elseif board_type == "rb-912uag-5hpnd" or board_type == "rb-911g-5hpnd" then
        link = "/sys/class/leds/rb:green:led1"
    elseif board_type == "rb-lhg-5nd" or board_type == "rb-lhg-5hpnd" or board_type == "rb-lhg-5hpnd-xl" or board_type == "rb-ldf-5nd" then
        link = "/sys/class/leds/rb:green:rssi0"
    else
        link = "/sys/class/leds/*link1"
    end
    link1led = utils.system_run("readlink -f " .. link)[1]
    
    -- Reset leds
    utils.write_all(link1led .. "/trigger", "none")
    utils.write_all(link1led .. "/brightness", "0")

    while true
    do
        utils.wait_for_ticks(11)
        
        local nei = utils.fetch_json("http://127.0.0.1:9090/neighbors")
        if #nei.neighbors > 0 then
            utils.write_all(link1led .. "/brightness", "1")
        else
            utils.write_all(link1led .. "/brightness", "0")
        end
    end
end

return linkled
