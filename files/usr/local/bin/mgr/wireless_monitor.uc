/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2025 Tim Wilkinson
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

import * as nl80211 from "nl80211";

const IW = "/usr/sbin/iw";
const PING6 = "/bin/ping6";

const device = radios.getMeshRadio();
if (!device) {
    return exitApp();
}
const wifi = device.iface;
let frequency;
let ssid;

const actionLimits = {
    unresponsiveReport: 3,
    unresponsiveTrigger1: 5,
    unresponsiveTrigger2: 10,
    zeroTrigger1: 10 * 60, // 10 minutes
    zeroTrigger2: 30 * 60 // 30 minutes
};
// Start action state assuming the node is active and no actions are pending
const actionState = {
    scan1: true,
    scan2: true,
    rejoin1: true,
    rejoin2: true
};
const unresponsive = {
    max: 0,
    ignore: 15,
    stations: []
};
const stationCount = {
    firstZero: 0,
    firstNonZero: 0,
    lastZero: 0,
    lastNonZero: 0,
    history: [],
    historyLimit: 120 // 2 hours
};
let defaultScanEnabled = true;

// Various forms of network resets

function resetNetwork(mode)
{
    log.syslog(log.LOG_NOTICE, `resetNetwork: ${mode}`);
    switch (mode) {
        case "rejoin":
            system(`${IW} ${wifi} ibss leave > /dev/null 2>&1`);
            system(`${IW} ${wifi} ibss join ${ssid} ${frequency} NOHT fixed-freq > /dev/null 2>&1`);
            break;
        case "scan-quick":
            system(`${IW} ${wifi} scan freq ${frequency} > /dev/null 2>&1`);
            break;
        case "scan-all":
            system(`${IW} ${wifi} scan > /dev/null 2>&1`);
            system(`${IW} ${wifi} scan passive > /dev/null 2>&1`);
            break;
        default:
            log.syslog(log.LOG_ERR, `-- unknown`);
            break;
    }
}

// Monitor stations and detect if they become unresponsive

function monitorUnresponsiveStations()
{
    const old = unresponsive.stations;
    unresponsive.stations = [];
    unresponsive.max = 0;

    const now = clock(true)[0];
    const stations = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: wifi });
    for (let i = 0; i < length(stations); i++) {
        const ipv6ll = network.mac2ipv6ll(stations[i].mac);
        if (system(`${PING6} -c 1 -W 2 -I ${wifi} ${ipv6ll} > /dev/null 2>&1`) == 0) {
            unresponsive.stations[ipv6ll] = 0;
        }
        else {
            if (!unresponsive.stations[ipv6ll]) {
                unresponsive.stations[ipv6ll] = 0;
            }
            const val = unresponsive.stations[ipv6ll] + 1;
            unresponsive.stations[ipv6ll] = val;
            if (val < unresponsive.ignore) {
                if (val > actionLimits.unresponsiveReport) {
                    log.syslog(log.LOG_ERR, `Possible unresponsive node: ${ipv6ll} [${stations[i].mac}]`);
                }
                if (val > unresponsive.max) {
                    unresponsive.max = val;
                }
            }
        }
    }
}

// Monitor number of connected stations

function monitorStationCount()
{
    const count = length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: wifi }));
    unshift(stationCount.history, count);
    if (length(stationCount.history) > stationCount.historyLimit) {
        stationCount.history = slice(stationCount.history, 0, stationCount.historyLimit);
    }
    const now = clock(true)[0];
    if (count == 0) {
        stationCount.lastZero = now;
        if (stationCount.firstZero <= stationCount.firstNonZero) {
            stationCount.firstZero = now;
        }
    }
    else {
        stationCount.lastNonZero = now;
        if (stationCount.firstNonZero <= stationCount.firstZero) {
            stationCount.firstNonZero = now;
        }
    }
}

// Take action depending on the monitor state

function runActions()
{
    const c = uci.cursor();
    if (c.get("aredn", "@wireless_watchdog[0]", "enable") == "1") {
        const m = match(c.get("aredn", "@wireless_watchdog[0]", "daily") || "", /([0-9][0-9]):([0-9][0-9])/);
        if (m) {
            const tm = localtime();
            const hours = int(m[1]);
            const mins = int(m[2]);
            let timediff = (tm.min + tm.hour * 60) - (mins + hours * 60);
            if (timediff < 0) {
                timediff = timediff + 24 * 60
            }
            if (timediff < 5) {
                if (defaultScanEnabled) {
                    defaultScanEnabled = false;
                    resetNetwork("scan-all");
                }
            }
            else {
                defaultScanEnabled = true;
            }
        }
    }

    // No action if we have stations and they're responsive
    if (stationCount.lastNonZero > stationCount.lastZero && unresponsive.max < actionLimits.unresponsiveTrigger1) {
        for (let k in actionState) {
            actionState[k] = false;
        }
        return;
    }

    // Otherwise

    // If network stations falls to zero when it was previously non-zero
    if (stationCount.firstZero > stationCount.firstNonZero) {
        if (!actionState.scan1 && stationCount.lastZero - stationCount.firstZero > actionLimits.zeroTrigger1) {
            resetNetwork("scan-quick");
            actionState.scan1 = true;
            return;
        }
        if (!actionState.scan2 && stationCount.lastZero - stationCount.firstZero > actionLimits.zeroTrigger2) {
            resetNetwork("scan-all");
            actionState.scan2 = true;
            return;
        }
    }

    // We are failing to ping stations we are associated with
    if (unresponsive.max >= actionLimits.unresponsiveTrigger1 && !actionState.rejoin1) {
        resetNetwork("rejoin");
        actionState.rejoin1 = true;
        return;
    }
    if (unresponsive.max >= actionLimits.unresponsiveTrigger2 && !actionState.rejoin2) {
        resetNetwork("rejoin");
        actionState.rejoin2 = true;
        return;
    }
}

function runMonitors()
{
    monitorUnresponsiveStations();
    monitorStationCount();
}

function save()
{
    fs.writefile("/tmp/wireless_monitor.info", sprintf("%.2J", {
        now: clock(true)[0],
        unresponsive: unresponsive,
        stationCount: stationCount,
        actionState: actionState
    }));
}

function main()
{
    runMonitors();
    runActions();
    save();
    return waitForTicks(60); // 1 minute
}

return waitForTicks(max(1, 120 - clock(true)[0]), function()
{
    // No station when we start
    const now = clock(true)[0];
    stationCount.firstNonZero = now;
    stationCount.firstZero = now;

    // Extract all the necessary wifi parameters
    let mode = null;
    const config = radios.getActiveConfiguration();
    for (let i = 0; i < length(config); i++) {
        const c = config[i];
        if (c.iface == wifi) {
            frequency = hardware.getChannelFrequency(wifi, c.mode.channel);
            ssid = c.mode.ssid;
            mode = c.mode.mode;
            break;
        }
    }
    const phy = hardware.getPhyDevice(wifi);

    if (!(phy && frequency && ssid)) {
        log.syslog(log.LOG_ERR, `Startup failed`);
        return exitApp();
    }
    if (mode != radios.RADIO_MESH) {
        log.syslog(log.LOG_NOTICE, `Only runs in adhoc mode`);
        return exitApp();
    }

    // Select chipset
    let chipset = null;
    if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath9k`)) {
        chipset = "ath9k";
    }
    else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath10k`)) {
        chipset = "ath10k";
    }
    else {
        log.syslog(log.LOG_NOTICE, `Unknown chipset`);
        return exitApp();
    }

    log.syslog(log.LOG_NOTICE, `Monitoring wireless chipset: ${chipset}`);

    return waitForTicks(0, main);
});
