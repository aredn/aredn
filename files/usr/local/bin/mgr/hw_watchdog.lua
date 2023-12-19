--[[

	Part of AREDN -- Used for creating Amateur Radio Emergency Data Networks
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

local PING = "/bin/ping"
local PIDOF = "/bin/pidof"
local REBOOT = "/sbin/reboot"

local W = {}

-- Configuration limits and defaults
local config_limits = {
    startup_delay = { 600, 600, 3600 },
    ping_count = { 1, 3, 10 },
    ping_timeout = { 1, 5, 10 },
    tick = { 60, 60, 600 },
    failures = { 2, 3, 25 },
    daily = { -1, -1, 23 }
}

-- Set of daemons to monitor
local default_daemons = "olsrd dnsmasq telnetd dropbear uhttpd"
if uci.cursor():get("vtun", "server_0", "host") or uci.cursor():get("vtun", "client_0", "name") then
    default_daemons = default_daemons .. " vtund"
end

function W.get_config()
    local c = uci.cursor()

    if c:get("aredn", "@watchdog[0]", "enable") ~= "1" then
        return nil
    end

    local ping_addresses = {}
    local addresses = c:get("aredn", "@watchdog[0]", "ping_addresses") or ""
    for address in addresses:gmatch("(%S+)") do
        if address:match("^%d+%.%d+%.%d+%.%d+$") then
            mainlog:write("pinging " .. address)
            ping_addresses[#ping_addresses + 1] = address
        end
    end
    local daemons = {}
    local mydaemons = c:get("aredn", "@watchdog[0]", "daemons") or default_daemons
    for daemon in mydaemons:gmatch("(%S+)") do
        mainlog:write("monitor " .. daemon)
        daemons[#daemons + 1] = daemon
    end
    local config = {
        ping_addresses = ping_addresses,
        daemons = daemons
    }
    for k, v in pairs(config_limits)
    do
        local val = tonumber(c:get("aredn", "@watchdog[0]", k) or nil)
        if not val then
            config[k] = v[2]
        elseif val < v[1] then
            config[k] = v[1]
        elseif val > v[3] then
            config[k] = v[3]
        else
            config[k] = val
        end
    end
    return config
end

function W.start()
    local config = W.get_config()
    if not config then
        exit_app()
        return
    end

    -- Dont start monitoring too soon. Let the system settle down.
    wait_for_ticks(math.max(1, config.startup_delay - nixio.sysinfo().uptime))

    local ub = ubus.connect()
    ub:call("system", "watchdog", { magicclose = true })
    ub:call("system", "watchdog", { stop = true })

    local wd = io.open("/dev/watchdog", "w")
    if not wd then
        mainlog:write("Watchdog failed to start: Cannot open /dev/watchdog\n")
        ub:call("system", "watchdog", { stop = false })
        exit_app()
        return
    end

    -- Make sure we have enough tick time for any pings
    local total_ping_time = 30 + (config.ping_timeout + config.ping_count) * #config.ping_addresses
    if total_ping_time > config.tick then
        config.tick = math.ceil(total_ping_time / 60) * 60
        mainlog:write("adjusted tick to " .. config.tick)
    end

    -- The reboot timeout seem to be 3-5x the timeout value
    -- We make sure it's at least 5 minutes
    ub:call("system", "watchdog", { timeout = math.ceil(math.max(300, config.tick * config.failures) / 3) })

    local daily_reboot_armed = false

    while true
    do
        local now = os.time()
        local success = true

        -- Reboot a device daily at a given time if configured. To avoid rebooting over and
        -- over we must have just seen the previous hour
        if config.daily ~= -1 then
            local time = os.date("*t")
            if time.min >= (60 - config.tick * 3) and (time.hour + 1) % 24 == config.daily then
                daily_reboot_armed = true
            elseif daily_reboot_armed and time.hour == config.daily then
                mainlog:write("reboot")
                os.execute(REBOOT .. " >/dev/null 2>&1")
                daily_reboot_armed = false
            else
                daily_reboot_armed = false
            end
        end

        for _ = 1, 1
        do
            -- Check various daemons are running
            for _, daemon in ipairs(config.daemons)
            do
                if os.execute(PIDOF .. " " .. daemon .. " > /dev/null ") ~= 0 then
                    mainlog:write("pidof " .. daemon .. " failed")
                    success = false
                    break
                end
            end
            if not success then
                break
            end

            -- Check we can reach any of the ping addresses
            if #config.ping_addresses > 0 then
                success = false
                for _, address in ipairs(config.ping_addresses)
                do
                    if os.execute(PING .. " -c " .. config.ping_count .. " -A -q -W " .. config.ping_timeout .. " " .. address .. " > /dev/null 2>&1") == 0 then
                        success = true
                        break
                    else
                        mainlog:write("ping " .. address .. " failed")
                    end
                end
                if not success then
                    break
                end
            end

        end
        if success then
            wd:write("V")
        else
            mainlog:write("failed")
        end

        wait_for_ticks(math.max(1, config.tick - (os.time() - now)))
    end
end

return W.start
