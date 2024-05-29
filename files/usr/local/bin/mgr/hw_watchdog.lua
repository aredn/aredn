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

local PING = "/bin/ping"
local PIDOF = "/bin/pidof"
local REBOOT = "/sbin/reboot"

local W = {}

local tick = 20
local ping_timeout = 3
local startup_delay = 600

-- Set of daemons to monitor
local default_daemons = "olsrd dnsmasq telnetd dropbear uhttpd"
if uci.cursor():get("vtun", "server_0", "host") or uci.cursor():get("vtun", "client_0", "name") then
    default_daemons = default_daemons .. " vtund"
end

function W.get_config(verbose)
    local c = uci.cursor()

    local ping_addresses = {}
    local addresses = c:get("aredn", "@watchdog[0]", "ping_addresses") or ""
    for address in addresses:gmatch("(%S+)") do
        if address:match("^%d+%.%d+%.%d+%.%d+$") then
            if verbose then
                nixio.syslog("debug", "pinging " .. address)
            end
            ping_addresses[#ping_addresses + 1] = address
        end
    end

    local daemons = {}
    local mydaemons = c:get("aredn", "@watchdog[0]", "daemons") or default_daemons
    for daemon in mydaemons:gmatch("(%S+)") do
        if verbose then
            nixio.syslog("debug", "monitor " .. daemon)
        end
        daemons[#daemons + 1] = daemon
    end

    local daily = tonumber(c:get("aredn", "@watchdog[0]", "daily") or nil) or -1

    return {
        ping_addresses = ping_addresses,
        daemons = daemons,
        daily = daily
    }
end

function W.start()
    if uci.cursor():get("aredn", "@watchdog[0]", "enable") ~= "1" then
        exit_app()
        return
    end

    local ub = ubus.connect()
    local config = W.get_config(true)

    ub:call("system", "watchdog", { frequency = 1 })
    ub:call("system", "watchdog", { timeout = 60 })

    -- Dont start monitoring too soon. Let the system settle down.
    wait_for_ticks(math.max(0, startup_delay - nixio.sysinfo().uptime))

    ub:call("system", "watchdog", { magicclose = true })
    ub:call("system", "watchdog", { stop = true })

    local wd = io.open("/dev/watchdog", "w")
    if not wd then
        nixio.syslog("err", "Watchdog failed to start: Cannot open /dev/watchdog\n")
        ub:call("system", "watchdog", { stop = false })
        exit_app()
        return
    end

    local daily_reboot_armed = false

    while true
    do
        local now = os.time()
        local success = true

        -- Update config
        config = W.get_config()

        -- Reboot a device daily at a given time if configured. To avoid rebooting over and
        -- over we must have just seen the previous hour
        if config.daily ~= -1 then
            local time = os.date("*t")
            if time.min >= 55 and (time.hour + 1) % 24 == config.daily then
                daily_reboot_armed = true
            elseif daily_reboot_armed and time.hour == config.daily then
                nixio.syslog("notice", "reboot")
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
                    nixio.syslog("err", "pidof " .. daemon .. " failed")
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
                    if os.execute(PING .. " -c 1 -A -q -W " .. ping_timeout .. " " .. address .. " > /dev/null 2>&1") == 0 then
                        success = true
                        break
                    else
                        nixio.syslog("err", "ping " .. address .. " failed")
                    end
                end
                if not success then
                    break
                end
            end

        end
        if success then
            wd:write("1")
            wd:flush()
        else
            nixio.syslog("err", "failed")
        end

        wait_for_ticks(math.max(0, tick - (os.time() - now)))
    end
end

return W.start
