--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2019 Darryl Quinn
    Copyright (C) 2021 Tim Wilkinson
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

	Additional use restrictions exist on the AREDN® trademark and logo.
		See AREDNLicense.txt for more info.

	Attributions to the AREDN® Project must be retained in the source code.
	If importing this code into a new or existing project attribution
	to the AREDN® project must be added to the source code.

	You must not misrepresent the origin of the material contained within.

	Modified versions must be modified to attribute to the original source
	and be marked in reasonable ways as differentiate it from the original
	version

--]]

function snrlog()
    while true
    do
        run_snrlog()
        wait_for_ticks(60) -- 1 minute
    end
end

local MAXLINES = 2880 -- 2 days worth
local AGETIME = 43200
local INACTIVETIMEOUT = 10000
local tmpdir = "/tmp/snrlog"
local lastdat = "/tmp/snr.dat"
local autolog = "/tmp/AutoDistReset.log"
local defnoise = -95
local cursor = uci.cursor()

-- create tmp dir if needed
nixio.fs.mkdir(tmpdir)

function run_snrlog()

    -- get system uptime
    local now = nixio.sysinfo().uptime

    -- get wifi interface name
    local wifiiface = get_ifname("wifi")

    -- if Mesh RF is turned off do nothing
    if wifiiface == string.match(wifiiface, 'eth.*') then
        return
    end

    -- get radio noise floor
    local nf = iwinfo.nl80211.noise(wifiiface)
    if not nf or nf < -110 or nf > -50 then
        nf = defnoise
    end

    -- get all stations
    local stations = iwinfo.nl80211.assoclist(wifiiface)

    -- load up arpcache
    local arpcache = {}
    arptable(function(a)
        arpcache[a["HW address"]:upper()] = a
    end)

    -- get the current bandwidth setting
    local radio = "radio0"
    cursor:foreach("wireless", "wifi-iface",
        function(i)
            if i.mode == "adhoc" then
                radio = i.device
            end
        end
    )
    local bandwidth = cursor:get("wireless", radio, "chanbw")

    -- load the lasttime table
    local lasttime = {}
    local nulledout = {}
    if nixio.fs.stat(lastdat) then
        for line in io.lines(lastdat) do
            local mac, last, nulled = string.match(line, "(.*)|(.*)|(.*)")
            lasttime[mac] = last
            nulledout[mac] = nulled
        end
    end

    -- iterate over all the stations and log neighbors
    local trigger_auto_distance = false
    local snrdatcache = {}
    for mstation in pairs(stations) do
        local mac = mstation:upper()

        snrdatcache[mac] = now

        -- find current data file
        local efn = nil
        for fn in nixio.fs.glob(tmpdir.."/"..mac.."-*") do
            efn = fn
            break
        end

        -- improve existing filename if we can
        local datafile = tmpdir.."/"..mac.."-"
        local arp = arpcache[mac]
        if arp then
            local ip = arp["IP address"]
            local hostname = nslookup(ip)
            if hostname then
                datafile = datafile..hostname:lower()
            elseif ip then
                datafile = datafile..ip
            end
        end
        -- rename if necessary
        if efn and efn ~= datafile then
            nixio.fs.rename(efn, datafile)
        end

        -- check if auto-distance reset is required (new node)
        -- note and run auto distancing right at the end
        if efn == nil or now - lasttime[mac] > 100 then
            trigger_auto_distance = true
        end

        local signal = stations[mac].signal or ""
        local update = true;
        if lasttime[mac] and stations[mac].inactive >= INACTIVETIMEOUT then
            -- beacons expired
            if nulledout[mac] == "true" then
                -- No need to double log inactive null's
                update = false
            end
            signal = "null"
        end

        if signal == 0 then
            if nulledout[mac] == nil then
                -- First time we have seen this show up
                -- but it is at 0 wont be logged but will
                -- end up in snrcache
                nulledout[mac] = "true"
            end
            update = false
        end

        -- log neighbor data to datafile
        if update then
            -- trim datafile
            file_trim(datafile, MAXLINES)
            local f, err = assert(io.open(datafile, "a"),"Cannot open file ("..datafile..") for appending!")
            if f then
                local noise = stations[mac].noise or ""
                local tx_mcs = stations[mac].tx_mcs or -1
                local tx_rate = adjust_rate((stations[mac].tx_rate) / 1000, bandwidth)
                local rx_mcs = stations[mac].rx_mcs or -1
                local rx_rate = adjust_rate((stations[mac].rx_rate) / 1000, bandwidth)
                f:write(string.format("%s,%s,%s,%s,%s,%s,%s\n", os.date("%m/%d/%Y %H:%M:%S",os.time()), signal, noise, tx_mcs, tx_rate, rx_mcs, rx_rate))
                f:close()
            else
                print(err)
            end
            if signal == "null" then
                nulledout[mac] = "true"
            else
                nulledout[mac] = "false"
            end
            lasttime[mac] = now
        end
    end

    -- update snr.dat
    for mac, last in pairs(lasttime) do
        if now - last < AGETIME then
            -- If not a neighbor and wasn't previously nulled out, write a null
            if not snrdatcache[mac] and nulledout[mac] == "false" then
                -- find the log file name
                for logdatafile in nixio.fs.glob(tmpdir.."/"..mac.."*") do                    
                    -- Write a null to the log file
                    local f, err = assert(io.open(logdatafile, "a"),"Cannot open file ("..logdatafile..") for appending!")
                    if f then
                        f:write(string.format("%s,%s,%s,%s,%s,%s,%s\n", os.date("%m/%d/%Y %H:%M:%S", os.time()), 'null', nf, '0', '0', '0', '0'))
                        f:close()
                        nulledout[mac] = "true"
                    else
                        -- Don't log the null into SNRLog cause we were not successful
                        -- Though the assert() above should cause this too.
                        nulledout[mac] = "false"
                    end
                    break
                end
            end
            -- keep it
            snrdatcache[mac] = snrdatcache[mac] or last
        else
            -- find the file and purge it
            for maclist in nixio.fs.glob(tmpdir.."/"..mac.."*") do
                os.remove(maclist)
                break
            end
        end
    end

    -- re-write snr.dat file
    local f, err = assert(io.open(lastdat,"w+"),"Cannot overwrite "..lastdat)
    for mac, last in pairs(snrdatcache) do
        f:write(string.format("%s|%s|%s\n", mac, last, nulledout[mac]))
    end
    f:close()

    -- trigger auto distancing if necessary
    if trigger_auto_distance and cursor:get("aredn", "@lqm[0]", "enable") ~= "1" then
        reset_auto_distance()
        file_trim(autolog, MAXLINES)
        f, err = assert(io.open(autolog, "a"),"Cannot open file (autolog) to write!")
        if f then
            f:write(now .. "\n")
            f:close()
        end
    end

end

return snrlog
