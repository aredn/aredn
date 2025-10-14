/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2023-2025 Tim Wilkinson
 * See Contributors file for additional contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation version 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Additional Terms:
 *
 * Additional use restrictions exist on the AREDN® trademark and logo.
 * See AREDNLicense.txt for more info.
 *
 * Attributions to the AREDN® Project must be retained in the source code.
 * If importing this code into a new or existing project attribution
 * to the AREDN® project must be added to the source code.
 *
 * You must not misrepresent the origin of the material contained within.
 *
 * Modified versions must be modified to attribute to the original source
 * and be marked in reasonable ways as differentiate it from the original
 * version
 */

const PING = "/bin/ping";
const PIDOF = "/bin/pidof";
const REBOOT = "/sbin/reboot";

const WATCHDOG_IOCTL_BASE = ord("W");
const WDIOC_SETTIMEOUT = 6;
const WDIOC_GETTIMEOUT = 7;

let tick = 60;
const pingTimeout = 3;
const startupDelay = 600;
const maxLastPing = 300;
const minWatchdogTimeout = 15;

// Set of daemons to monitor
const defaultDaemons = "dnsmasq telnetd dropbear uhttpd babeld";

let wd = null;
let pingState = [];
let pingIndex = 0;

if (uci.cursor().get("aredn", "@watchdog[0]", "enable") != "1") {
    return exitApp();
}
if (!fs.access("/dev/watchdog")) {
    return exitApp();
}

function getConfig(verbose)
{
    const c = uci.cursor();

    const addresses = split(c.get("aredn", "@watchdog[0]", "ping_addresses") || "", " ");
    const newPingState = [];
    for (let i = 0; i < length(addresses); i++) {
        const address = addresses[i];
        if (match(address, /^\d+\.\d+\.\d+\.\d+$/)) {
            if (verbose) {
                log.syslog(log.LOG_DEBUG, `pinging ${address}`);
            }
            const ps = pingState[length(newPingState)];
            push(newPingState, { address: address, last: 0 });
            if (ps && ps.address != address) {
                pingState = newPingState;
            }
        }
    }
    if (length(pingState) != length(newPingState)) {
        pingState = newPingState;
    }

    const daemons = split(c.get("aredn", "@watchdog[0]", "daemons") || defaultDaemons, " ");
    if (verbose) {
        for (let i = 0; i < length(daemons); i++) {
            log.syslog(log.LOG_DEBUG, `monitor ${daemons[i]}`);
        }
    }

    let daily = c.get("aredn", "@watchdog[0]", "daily");
    if (daily) {
        let m = match(daily, /^(\d\d):(\d\d)$/);
        if (m) {
            daily = 60 * int(m[1]) + int(m[2]);
        }
        else {
            m = match(daily, /^(\d\d?)$/);
            if (m) {
                daily = 60 * int(m[1]);
            }
            else {
                daily = -1;
            }
        }
    }
    else {
        daily = -1;
    }

    return {
        pings: pingState,
        daemons: daemons,
        daily: daily
    };
}

function main()
{
    const now = clock(true)[0];
    let success = true;
    const config = getConfig();

    // Reboot a device daily at a given time if configured.
    // To avoid rebooting at the wrong time we will only do this if the node has been running
    // for > 1 hour, and the time has been set by ntp of gps
    if (config.daily != -1 && now >= 3600 && fs.access("/tmp/timesync")) {
        const tm = localtime();
        let timediff = (tm.min + tm.hour * 60) - config.daily;
        if (timediff < 0) {
            timediff += 24 * 60;
        }
        if (timediff < 5) {
            log.syslog(log.LOG_NOTICE, "reboot");
            system(`${REBOOT} > /dev/null 2>&1`);
            return exitApp();
        }
    }

    // Check various daemons are running
    for (let i = 0; i < length(config.daemons); i++) {
        const daemon = config.daemons[i];
        if (system(`${PIDOF} ${daemon} > /dev/null`) != 0) {
            log.syslog(log.LOG_ERR, `pidof ${daemon} failed`);
            success = false;
            break;
        }
    }

    if (success && length(config.pings)) {
        // Check we can reach any of the ping addresses
        // We cycle over them one per iteration so as not to consume too much time
        pingIndex++;
        if (pingIndex >= length(config.pings)) {
            pingIndex = 0;
        }
        const target = config.pings[pingIndex];

        if (system(`${PING} -c 1 -A -q -W ${pingTimeout} ${target.address} > /dev/null 2>&1`) == 0) {
            target.last = now;
        }
        else {
            log.syslog(log.LOG_ERR, `ping ${target.address} failed ${target.last == 0 ? " (always)" : ""}`);
        }

        let good = 0;
        let bad = 0;
        for (let i = 0; i < length(config.pings); i++) {
            const target = config.pings[i];
            // Ignore pings which have never succeeded
            if (target.last != 0) {
                if (target.last + maxLastPing < now) {
                    bad++;
                }
                else {
                    good++;
                }
            }
        }
        // We fail if we have no good pings and at least one bad ping
        if (good == 0 && bad > 0) {
            success = false;
        }
    }
    
    if (success) {
        wd.write("1");
        wd.flush();
    }
    else {
        log.syslog(log.LOG_ERR, "failed");
    }

    return waitForTicks(max(0, tick - (clock(true)[0] - now)));
}

// Gracefully shutdown the watchdog
onShutdown(() => {
    log.syslog(log.LOG_DEBUG, `disabling watchdog`);
    if (wd) {
        wd.write("V");
        wd.flush();
        wd.close();
    }
});

// Dont start monitoring too soon. Let the system settle down.
return waitForTicks(max(0, startupDelay - clock(true)[0]), function() {
    const ub = ubus.connect();
    ub.call("system", "watchdog", { magicclose: true });
    ub.call("system", "watchdog", { stop: true });
    wd = fs.open("/dev/watchdog", "w");
    if (!wd) {
        log.syslog(log.LOG_ERR, "Watchdog failed to start: Cannot open /dev/watchdog");
        ub.call("system", "watchdog", { stop: false });
        return exitApp();
    }

    // We cannot reliably set the timeout so we are forced to work with whatever the default value is.
    // If the value is too small we disable the watchdog.
    const gettime = struct.unpack("I", wd.ioctl(fs.IOC_DIR_READ, WATCHDOG_IOCTL_BASE, WDIOC_GETTIMEOUT, 4))[0];
    tick = min(tick, int(gettime / 2));
    if (tick < minWatchdogTimeout) {
        log.syslog(log.LOG_ERROR, `tick ${tick} < ${minWatchdogTimeout}, disabling watchdog`);
        wd.write("V");
        wd.flush();
        wd.close();
        return exitApp();
    }
    log.syslog(log.LOG_DEBUG, `tick set to ${tick}`);

    return main;
});
