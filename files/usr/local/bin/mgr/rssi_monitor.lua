--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2021 Tim Wilkinson
	Original Perl Copyright (C) 2015 Joe Ayers  ae6xe@arrl.net
	See Contributors file for additional contributors

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation version 3 of the License.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.

	Additional Terms:

	Additional use restrictions exist on the AREDN(TM) trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version

--]]

function rssi_monitor()
    while true
    do
        if not string.match(get_ifname("wifi"), "^eth.") and nixio.sysinfo().uptime > 119 then
            run_monitor()
        end
        wait_for_ticks(60) -- 1 minute
    end
end

local datfile = "/tmp/rssi.dat"
local logfile = "/tmp/rssi.log"

if not file_exists(datfile) then
    io.open(datfile, "w+"):close()
end
if not file_exists(logfile) then
    io.open(logfile, "w+"):close()
end

local wifiiface = get_ifname("wifi")

local multiple_ant = false
if read_all("sys/kernel/debug/ieee80211/" .. iwinfo.nl80211.phyname(wifiiface) .. "/ath9k/tx_chainmask"):chomp() ~= "1" then
    multiple_ant = true
end

local log = aredn.log.open(logfile, 16000)

function run_monitor()

    local now = nixio.sysinfo().uptime

    -- load history
    local rssi_hist = {}
    for line in io.lines(datfile) do
        local mac, ave_h, sd_h, ave_v, sd_v, num, last = string.match(line, "([0-9a-fA-F:]*)|(.*)|(.*)|(.*)|(.*)|(.*)|(.*)")
        rssi_hist[mac] = {
            ave_h = ave_h,
            sd_h = sd_h,
            ave_v = ave_v,
            sd_v = sd_v,
            num = tonumber(num),
            last = last
        }
    end

    local ofdm_level = 0
    for i, line in ipairs(read_all("/sys/kernel/debug/ieee80211/" .. iwinfo.nl80211.phyname(wifiiface) .. "/ath9k/ani"):splitNewLine())
    do
        ofdm_level = tonumber(string.match(line, "OFDM LEVEL: (.*)"))
        if ofdm_level then
            break
        end
    end
    local amac = nil

    -- avoid node going deaf while trying to obtain 'normal' statistics of neighbor strength
    -- in first few minutes after boot
    if now > 119 and now < 750 then
        os.execute("/usr/sbin/iw " .. wifiiface .. " scan freq " .. aredn_info.getFreq() .. " passive")
    end

    local rssi = get_rssi(wifiiface)
    for mac, info in pairs(rssi)
    do
        local rssih = rssi_hist[mac]
        if rssih and now - rssih.last < 3600 then
            local hit = 0
            local sdh3 = math.floor(rssih.sd_h * 3 + 0.5)
            if math.abs(rssih.ave_h - info.Hrssi) > sdh3 then
                hit = hit + 1
            end
            local sdv3 = math.floor(rssih.sd_v * 3 + 0.5)
            if math.abs(rssih.ave_v - info.Vrssi) > sdv3 and multiple_ant then
                hit = hit + 1
            end
            if rssih.num > 9 and ofdm_level <= 3 and hit > 0 then
                -- overly attenuated chain suspected
                local msg = string.format("Attenuated Suspect %s [%d] %f %f", mac, info.Hrssi, rssih.ave_h, rssih.sd_h)
                if multiple_ant then
                    msg = msg .. string.format(" [%d] %f %f", info.Vrssi, rssih.ave_v, rssih.sd_v)
                end
                if not amac or rssi[amac].Hrssi < info.Hrssi then
                    amac = mac
                end
                log:write(msg)
            else
                -- update statistics
                local ave_h = (rssih.ave_h * rssih.num + info.Hrssi) / (rssih.num + 1)
                local sd_h = math.sqrt(((rssih.num - 1) * rssih.sd_h * rssih.sd_h + (info.Hrssi - ave_h) * (info.Hrssi - rssih.ave_h)) / rssih.num)
                rssih.ave_h = ave_h
                rssih.sd_h = sd_h
                local ave_v = (rssih.ave_v * rssih.num + info.Vrssi) / (rssih.num + 1)
                local sd_v = math.sqrt(((rssih.num - 1) * rssih.sd_v * rssih.sd_v + (info.Vrssi - ave_v) * (info.Vrssi - rssih.ave_v)) / rssih.num)
                rssih.ave_v = ave_v
                rssih.sd_v = sd_v
                rssih.last = now
                if rssih.num < 60 then
                    rssih.num = rssih.num + 1
                end
            end
        else
            rssi_hist[mac] = {
                ave_h = info.Hrssi,
                sd_h = 0,
                ave_v = info.Vrssi,
                sd_v = 0,
                num = 1,
                last = now
            }
        end
    end

    if amac then
        -- reset
        os.execute("/usr/sbin/iw " .. wifiiface .. " scan freq " .. aredn_info.getFreq() .. " passive")
        wait_for_ticks(5)
        -- update time
        now = nixio.sysinfo().uptime

        local beforeh = rssi[amac].Hrssi
        local beforev = rssi[amac].Vrssi
        local arssi = get_rssi(wifiiface)

        if multiple_ant then
            log:write(string.format("before %s [%d] [%d]", amac, beforeh, beforev))
            log:write(string.format("after  %s [%d] [%d]", amac, arssi[amac].Hrssi, arssi[amac].Vrssi))
        else
            log:write(string.format("before %s [%d]", amac, beforeh))
            log:write(string.format("after  %s [%d]", amac, arssi[amac].Hrssi))
        end

        if math.abs(beforeh - arssi[amac].Hrssi) <= 2 and math.abs(beforev - arssi[amac].Vrssi) <= 2 then
            -- false positive if within 2dB after reset
            log:write(string.format("%s Possible valid data point, adding to statistics", amac))
            local rssih = rssi_hist[amac]
            local ave_h = (rssih.ave_h * rssih.num + beforeh) / (rssih.num + 1)
            local sd_h = math.sqrt(((rssih.num - 1) * rssih.sd_h * rssih.sd_h + (beforeh - ave_h) * (beforeh - rssih.ave_h)) / rssih.num)
            rssih.ave_h = ave_h
            rssih.sd_h = sd_h
            local ave_v = (rssih.ave_v * rssih.num + beforeh) / (rssih.num + 1)
            local sd_v = math.sqrt(((rssih.num - 1) * rssih.sd_v * rssih.sd_v + (beforeh - ave_v) * (beforeh - rssih.ave_v)) / rssih.num)
            rssih.ave_v = ave_v
            rssih.sd_v = sd_v
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
            f:write(string.format("%s|%f|%f|%f|%f|%d|%s\n", mac, hist.ave_h, hist.sd_h, hist.ave_v, hist.sd_v, hist.num, hist.last))
        end
        f:close()
    end

    log:flush()
end

function get_rssi(wifiiface)
    if not multiple_ant then
        -- easy way
        local rssi = {}
        local stations = iwinfo.nl80211.assoclist(wifiiface)
        for mac, station in pairs(stations)
        do
            if station.signal ~= 0 then
                if station.signal < -95 then
                    rssi[mac] = { Hrssi = -96, Vrssi = -96 }
                else
                    rssi[mac] = { Hrssi = station.signal, Vrssi = station.signal }
                end
            end
        end
        return rssi
    else
        -- hard way
        local rssi = {}
        local f = io.popen("/usr/sbin/iw " .. wifiiface .. " station dump 2>&1")
        if f then
            local mac
            for line in f:lines()
            do
                local m = line:match("Station (%S+) %(on " .. wifiiface)
                if m then
                    mac = m
                end
                local h, v = line:match("signal:.*%[(.+),%s(.+)%]")
                if mac and v then
                    h = tonumber(h)
                    v = tonumber(v)
                    rssi[mac] = { Hrssi = h < -95 and -95 or h, Vrssi = v < -95 and -95 or v }
                    mac = nil
                end
            end
            f:close()
        end
        return rssi
    end
end

return rssi_monitor
