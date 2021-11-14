
datfile = "/tmp/rssi.dat"
logfile = "/tmp/rssi.log"

function rssi_monitor()
    while true
    do
        if not string.match(uci.cursor():get("network", "wifi", "ifname"), "^eth.") and utils.uptime() > 119 then
            run_monitor()
        end
        utils.wait_for_ticks(60) -- 1 minute
    end
end

function run_monitor()

end

return rssi_monitor
