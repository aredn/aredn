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
local ping_state = {}

-- Set of daemons to monitor
local default_daemons = "olsrd dnsmasq telnetd dropbear uhttpd"
if uci.cursor():get("vtun", "server_0", "host") or uci.cursor():get("vtun", "client_0", "name") then
    default_daemons = default_daemons .. " vtund"
end

function W.get_config(verbose)
    local c = uci.cursor()

    local addresses = c:get("aredn", "@watchdog[0]", "ping_addresses") or ""
    local new_ping_state = {}
    for address in addresses:gmatch("(%S+)") do
        if address:match("^%d+%.%d+%.%d+%.%d+$") then
            if verbose then
                nixio.syslog("debug", "pinging " .. address)                
            end
            local idx = #new_ping_state + 1
            new_ping_state[idx] = { address = address, success = true }
            if not ping_state[idx] or ping_state[idx].address ~= address then
                ping_state = new_ping_state
            end
        end
    end
    if #ping_state ~= #new_ping_state then
        ping_state = new_ping_state
    end

    local daemons = {}
    local mydaemons = c:get("aredn", "@watchdog[0]", "daemons") or default_daemons
    for daemon in mydaemons:gmatch("(%S+)") do
        if verbose then
            nixio.syslog("debug", "monitor " .. daemon)
        end
        daemons[#daemons + 1] = daemon
    end

    local daily = c:get("aredn", "@watchdog[0]", "daily")
    if daily then
        local h, m = daily:match("%d%d:%d%d")
        if h then
            daily = 60 * tonumber(h) + tonumber(m)
        else
            h = daily:match("%d%d?")
            if h then
                daily = 60 * tonumber(h)
            else
                daily = -1
            end
        end
    else
        daily = -1
    end

    return {
        pings = ping_state,
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

    local ping_index = 0

    while true
    do
        local now = os.time()
        local success = true

        -- Update config
        config = W.get_config()

        -- Reboot a device daily at a given time if configured.
        -- To avoid rebooting at the wrong time we will only do this if the node has been running
        -- for > 1 hour, and the time has been set by ntp of gps
        if config.daily ~= -1 and nixio.sysinfo().uptime >= 3600 and nixio.fs.stat("/tmp/timesync") then
            local time = os.date("*t")
            local timediff = (time.min + time.hour * 60) - daily
            if timediff < 0 then
                timediff = timediff + 24 * 60
            end
            if timediff < 5 then
                nixio.syslog("notice", "reboot")
                os.execute(REBOOT .. " >/dev/null 2>&1")
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
            -- We cycle over them one per iteration so as not to consume too much time
            if #config.pings > 0 then
                ping_index = ping_index + 1
                if ping_index > #config.pings then
                    ping_index = 1
                end
                local target = config.pings[ping_index]

                if os.execute(PING .. " -c 1 -A -q -W " .. ping_timeout .. " " .. target.address .. " > /dev/null 2>&1") == 0 then
                    target.success = true
                else
                    target.success = false
                    nixio.syslog("err", "ping " .. address .. " failed")
                end
                
                -- All targets have to fail for this whole test to fail
                success = false
                for _, target in ipairs(config.pings)
                do
                    if target.success then
                        success = true
                        break
                    end
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
