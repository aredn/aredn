--[[

	Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
	Copyright (C) 2023 Tim Wilkinson
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

local ip = require("luci.ip")

local IW = "/usr/sbin/iw"
local ARPING = "/usr/sbin/arping"

local M = {}

local wifi
local phy
local chipset
local frequency
local ssid

local action_limits = {
    unresponsive_report = 3,
    unresponsive_trigger1 = 5,
    unresponsive_trigger2 = 10,
    zero_trigger1 = 10 * 60, -- 10 minutes
    zero_trigger2 = 30 * 60, -- 30 minutes
    default_scan = 3 -- 3am
}
-- Start action state assuming the node is active and no actions are pending
local action_state = {
    scan1 = true,
    scan2 = true,
    rejoin1 = true,
    rejoin2 = true
}
local unresponsive = {
    max = 0,
    ignore = 15,
    stations = {}
}
local station_count = {
    first_zero = 0,
    first_nonzero = 0,
    last_zero = 0,
    last_nonzero = 0,
    history = {},
    history_limit = 120 -- 2 hours
}
local default_scan_enabled = true

-- Detect Mikrotik AC which requires special handling
local mikrotik_ac = false
local boardid = aredn.hardware.get_board_id():lower()
if boardid:match("mikrotik") and boardid:match("ac") then
    mikrotik_ac = true
end

-- Various forms of network resets --

function M.reset_network(mode)
    nixio.syslog("notice", "reset_network: " .. mode)
    if mode == "rejoin" then
        -- Only observered on Mikrotik AC devices
        if mikrotik_ac then
            os.execute(IW .. " " .. wifi .. " ibss leave > /dev/null 2>&1")
            os.execute(IW .. " " .. wifi .. " ibss join " .. ssid .. " " .. frequency .. " fixed-freq > /dev/null 2>&1")
        else
            nixio.syslog("notice", "-- ignoring (mikrotik ac only)")
        end
    elseif mode == "scan-quick" then
        os.execute(IW .. " " .. wifi .. " scan freq " .. frequency .. " > /dev/null 2>&1")
    elseif mode == "scan-all" then
        os.execute(IW .. " " .. wifi .. " scan > /dev/null 2>&1")
        os.execute(IW .. " " .. wifi .. " scan passive > /dev/null 2>&1")
    else
        nixio.syslog("err", "-- unknown")
    end
end

-- Monitor stations and detect if they become unresponsive --

function M.monitor_unresponsive_stations()

    local old = unresponsive.stations
    unresponsive.stations = {}
    unresponsive.max = 0

    local now = nixio.sysinfo().uptime
    local arp = {}
    arptable(
        function (entry)
            if entry.Device == wifi and entry["Flags"] ~= "0x0" then
                local ipaddr = entry["IP address"]
                local mac = entry["HW address"]
                if mac and ipaddr then
                    arp[mac:upper()] = ipaddr
                end
            end
        end
    )
    for mac, _ in pairs(iwinfo.nl80211.assoclist(wifi))
    do
        local ipaddr = arp[mac:upper()]
        if ipaddr then
            unresponsive.stations[ipaddr] = -1
            local rt = ip.route(ipaddr)
            if rt and tostring(rt.gw) == ipaddr then
                unresponsive.stations[ipaddr] = 0
                -- The first ping is broadcast, the rest unicast
                for line in io.popen(ARPING .. " -w 5 -I " .. wifi .. " " .. ipaddr):lines()
                do
                    -- If we see exactly one response then broadcast works and unicast doesnt.
                    -- We neeed to force the station to reassociate
                    if line:match("^Received 1 response") then
                        local val = (old[ipaddr] or 0) + 1
                        unresponsive.stations[ipaddr] = val
                        if val < unresponsive.ignore then
                            if val > action_limits.unresponsive_report then
                                nixio.syslog("err", "Possible unresponsive node: " .. ipaddr .. " [" .. mac .. "]")
                            end
                            if val > unresponsive.max then
                                unresponsive.max = val
                            end
                        end
                        break
                    end
                end
            end
        end
    end
end

-- Monitor number of connected stations --

function M.monitor_station_count()
    local count = 0
    for mac, station in pairs(iwinfo.nl80211.assoclist(wifi))
    do
        count = count + 1
    end
    table.insert(station_count.history, 1, count)
    while #station_count.history > station_count.history_limit
    do
        station_count.history[#station_count.history] = nil
    end
    local now = nixio.sysinfo().uptime
    if count == 0 then
        station_count.last_zero = now
        if station_count.first_zero <= station_count.first_nonzero then
            station_count.first_zero = now
        end
    else
        station_count.last_nonzero = now
        if station_count.first_nonzero <= station_count.first_zero then
            station_count.first_nonzero = now
        end
    end
end

-- Take action depending on the monitor state

function M.run_actions()

    -- Once per day we do a wifi scan as a fallback for failed connections
    local time = os.date("*t")
    if time.hour == action_limits.default_scan then
        if default_scan_enabled then
            default_scan_enabled = false
            M.reset_network("scan-all")
        end
    else
        default_scan_enabled = true
    end

    -- No action if we have stations and they're responsive
    if station_count.last_nonzero > station_count.last_zero and unresponsive.max < action_limits.unresponsive_trigger1 then
        for k, _ in pairs(action_state)
        do
            action_state[k] = false
        end
        return
    end

    -- Otherwise ...

    -- If network stations falls to zero when it was previously non-zero
    if station_count.first_zero > station_count.first_nonzero then
        if not action_state.scan1 and station_count.last_zero - station_count.first_zero > action_limits.zero_trigger1 then
            M.reset_network("scan-quick")
            action_state.scan1 = true
            return
        elseif not action_state.scan2 and station_count.last_zero - station_count.first_zero > action_limits.zero_trigger2 then
            M.reset_network("scan-all")
            action_state.scan2 = true
            return
        end
    end

    -- We are failing to ping stations we are associated with
    if unresponsive.max >= action_limits.unresponsive_trigger1 and not action_state.rejoin1 then
        M.reset_network("rejoin")
        action_state.rejoin1 = true
        return
    elseif unresponsive.max >= action_limits.unresponsive_trigger2 and not action_state.rejoin2 then
        M.reset_network("rejoin")
        action_state.rejoin2 = true
        return
    end
end

function M.run_monitors()
    M.monitor_unresponsive_stations()
    M.monitor_station_count()
end

function M.save()
    local f = io.open("/tmp/wireless_monitor.info", "w")
    if f then
        f:write(luci.jsonc.stringify({
            now = nixio.sysinfo().uptime,
            unresponsive = unresponsive,
            station_count = station_count,
            action_state = action_state
        }, true))
        f:close()
    end
end

function M.start_monitor()
    if not string.match(get_ifname("wifi"), "^wlan") then
        exit_app()
        return
    end

    -- No stations when we start
    local now = nixio.sysinfo().uptime
    station_count.first_zero = now
    station_count.last_zero = now

    wait_for_ticks(math.max(1, 120 - nixio.sysinfo().uptime))

    -- Extract all the necessary wifi parameters
    wifi = get_ifname("wifi")
    phy = iwinfo.nl80211.phyname(wifi)
    frequency = iwinfo.nl80211.frequency(wifi)
    ssid = iwinfo.nl80211.ssid(wifi)
    if not (phy and frequency and ssid) then
        nixio.syslog("err", "Startup failed")
        exit_app()
        return
    end

    -- Select chipset
    if nixio.fs.stat("/sys/kernel/debug/ieee80211/" .. phy .. "/ath9k") then
        chipset = "ath9k"
    elseif nixio.fs.stat("/sys/kernel/debug/ieee80211/" .. phy .. "/ath10k") then
        chipset = "ath10k"
    else
        exit_app()
        return
    end

    nixio.syslog("notice", "Monitoring wireless chipset: " .. chipset)

    M.reset_network("rejoin")

    while true
    do
        M.run_monitors()
        M.run_actions()
        M.save()
        wait_for_ticks(60) -- 1 minute
    end
end

return M.start_monitor
