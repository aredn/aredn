
function rssi_monitor()
    while true
    do
        if not string.match(uci.cursor():get("network", "wifi", "ifname"), "^eth.") and utils.uptime() > 119 then
            run_monitor()
        end
        wait_for_ticks(60) -- 1 minute
    end
end

local datfile = "/tmp/rssi.dat"
local logfile = "/tmp/rssi.log"
local MAXLINE = 200

local wifiiface
local phy

if not file_exists(datfile) then
    io.open(datfile, "w+"):close()
end
if not file_exists(logfile) then
    io.open(logfile, "w+"):close()
end

utils.log_start(logfile, MAXLINES)

function run_monitor()

    local now = luci.sys.uptime()

    wifiiface = aredn_info.getMeshRadioDevice()

    -- find physical device for wifiiface
    local phy = "phy0"
    for i, line in ipairs(utils.system_run("/usr/bin/iwinfo " .. wifiiface .. " info"))
    do
        local mphy = string.match(line, "PHY name: (.*)")
        if mphy then
            phy = mphy
            break
        end
    end

    -- load history
    local rssi_hist = {}
    for line in io.lines(datfile) do
        local mac, ave_h, sd_h, num, last = string.match(line, "([0-9a-fA-F:]*)|(.*)|(.*)|(.*)|(.*)")
        rssi_hist[mac] = {
            ave_h = ave_h,
            sd_h = sd_h,
            num = tonumber(num),
            last = last
        }
    end

    local ofdm_level
    for i, line in ipairs(utils.read_all("/sys/kernel/debug/ieee80211/" .. phy .. "/ath9k/ani"))
    do
        ofdm_level = tonumber(string.match(line, "OFDM LEVEL: (.*)"))
        if not ofdm_level then
            break
        end
    end
    local amac = nil

    -- avoid node going deaf while trying to obtain 'normal' statistics of neighbor strength
    -- in first few minutes after boot
    if now > 119 and now < 750 then
        utils.system_run("/usr/sbin/iw " .. wifiiface .. " scan freq " .. aredn_info.getFreq() .. " passive")
    end

    local rssi = get_rssi()
    for mac, info in pairs(rssi)
    do
        local rssih = rssi_hist[mac]
        if rssih and now - rssih[mac].last < 3600 then
            local hit = 0
            local sdh3 = math.floor(rssih.sd_h * 3 + 0.5)
            if math.abs(rssih.ave_h - info.Hrssi) > sdh3 then
                hit = hit + 1
            end
            if rssih.num > 9 and ofdm_level <= 3 and hit > 0 then
                -- overly attenuated chain suspected
                utils.log(string.format("Attenuated Suspect %s [%d] %f %f", mac, info.Hrssi, rssih.ave_h, rssih.sd_h))
                if not amac or rssi[amac] < info.Hrssi then
                    amac = mac
                end
            else
                -- update statistics
                local ave_h = (rssih.ave_h * rssih.num + info.Hrssi) / (rssih.num + 1)
                local sd_h = math.sqrt(((rssih.num - 1) * rssih.sd_h * rssih.sd_h + (info.Hrssi - ave_h) * (info.Hrssi - rssih.ave_h)) / rssih.num)
                rssih.ave_h = ave_h
                rssih.sd_h = sd_h
                rssih.last = now
                if rssih.num < 60 then
                    rssih.num = rssih.num + 1
                end
            end
        else
            rssi_hist[mac] = {
                ave_h = info.Hrssi,
                sd_h = 0,
                num = 1,
                last = now
            }
        end
    end

    if amac then
        -- reset
        utils.system_run("/usr/sbin/iw " .. wifiiface .. " scan freq " .. aredn_info.getFreq() .. " passive")
        wait_for_ticks(5)
        -- update time
        now = luci.sys.uptime()

        local beforeh = rssi[amac].Hrssi
        local arssi = get_rssi()

        utils.log(string.format("before %s [%d]", beforeh))
        utils.log(string.format("after  %s [%d]", arssi[amac].Hrssi))

        if math.abs(beforeh - arssi[amac].Hrssi) <= 2 then
            -- false positive if within 2dB after reset
            utils.log(string.format("%s Possible valid data point, adding to statistics", amac))
            local rssih = rssi_hist[amac]
            local ave_h = (rssih.ave_h * rssih.num + beforeh) / (rssih.num + 1)
            local sd_h = math.sqrt(((rssih.num - 1) * rssih.sd_h * rssih.sd_h + (beforeh - ave_h) * (beforeh - rssih.ave_h)) / rssih.num)
            rssih.ave_h = ave_h
            rssih.sd_h = sd_h
            rssih.last = now
            if rssih.num < 60 then
                rssih.num = rssih.num + 1
            end
        end
    end

    local f = io.open(datfile, "w")
    if f then
        for mac, hist in pairs(rssi_hist)
        do
            io:write(string.format("%s|%f|%f|%d|%s\n", mac, hist.ave_h, hist.sd_h, hist.num, hist.last))
        end
        f:close()
    end

    utils.log_end()
end

function get_rssi()
    local rssi = {}
    local stations = iwinfo.nl80211.assoclist(wifiiface)
    for mac, station in pairs(stations)
    do
        if station.signal ~= 0 then
            if station.signal < -95 then
                rssi[mac] = { Hrssi = -96 }
            else
                rssi[mac] = { Hrssi = station.signal }
            end
        end
    end
    return rssi
end

return rssi_monitor
