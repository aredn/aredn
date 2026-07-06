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
const IFUP = "/sbin/ifup";
const IFDOWN = "/sbin/ifdown";

const actionLimits = {
    unresponsiveReport: 3,
    unresponsiveTrigger1: 5,
    unresponsiveTrigger2: 10,
    zeroTrigger1: 5 * 60, // 5 minutes
    zeroTrigger2: 15 * 60 // 15 minutes
};

// One state block per mesh radio. Captured once at startup, same as the
// single-radio lookup this replaces - a live radio reconfiguration already
// requires a wireless_monitor restart to be picked up.
const radioState = [];
const meshRadios = radios.getMeshRadios();
for (let i = 0; i < length(meshRadios); i++) {
    push(radioState, {
        iface: meshRadios[i].iface,
        network: length(radioState) == 0 ? "wifi" : `wifi${length(radioState)}`,
        frequency: null,
        ssid: null,
        mode: null,
        chipset: null,
        defaultScanEnabled: true,
        // Start action state assuming the node is active and no actions are pending
        actionState: {
            zero1: true,
            zero2: true,
            unresponsive1: true,
            unresponsive2: true
        },
        unresponsive: {
            max: 0,
            ignore: 15,
            stations: {}
        },
        stationCount: {
            firstZero: 0,
            firstNonZero: 0,
            lastZero: 0,
            lastNonZero: 0
        }
    });
}
if (length(radioState) == 0) {
    return exitApp();
}

// Various forms of network resets

function resetNetwork(rs, op)
{
    log.syslog(log.LOG_NOTICE, `resetNetwork: ${rs.iface} ${rs.chipset} ${rs.mode} ${op}`);
    switch (rs.chipset) {
        case "ath9k":
        case "ath10k":
            switch (rs.mode) {
                case "mesh":
                    switch (op) {
                        case "unresponsive":
                            system(`${IW} ${rs.iface} ibss leave > /dev/null 2>&1`);
                            system(`${IW} ${rs.iface} ibss join ${rs.ssid} ${rs.frequency} NOHT fixed-freq > /dev/null 2>&1`);
                            break;
                        case "zero-soft":
                            system(`${IW} ${rs.iface} scan freq ${rs.frequency} > /dev/null 2>&1`);
                            break;
                        case "zero-hard":
                        case "daily-restart":
                            system(`${IW} ${rs.iface} scan > /dev/null 2>&1`);
                            system(`${IW} ${rs.iface} scan passive > /dev/null 2>&1`);
                            break;
                        case "restart":
                            system(`${IFDOWN} ${rs.network}; ${IFUP} ${rs.network}`);
                            break;
                        default:
                            log.syslog(log.LOG_ERR, `-- unknown`);
                            break;
                    }
                    break;
                default:
                    break;
            }
            break;
        case "morse":
            if (op === "restart") {
                system(`${IFDOWN} ${rs.network}; ${IFUP} ${rs.network}`);
            }
            break;
        case "mt76":
            log.syslog(log.LOG_NOTICE, `-- ignored`);
            break;
        default:
            log.syslog(log.LOG_ERR, `-- unknown chipset '${rs.chipset}`);
            break;
    }
}

// Monitor stations and detect if they become unresponsive

function monitorUnresponsiveStations(rs)
{
    rs.unresponsive.max = 0;
    const nstations = {};

    const stations = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: rs.iface }) ?? [];
    for (let i = 0; i < length(stations); i++) {
        const ipv6ll = network.mac2ipv6ll(stations[i].mac);
        if (system(`${PING6} -c 1 -W 2 -I ${rs.iface} ${ipv6ll} > /dev/null 2>&1`) == 0) {
            nstations[ipv6ll] = 0;
        }
        else {
            const val = (rs.unresponsive.stations[ipv6ll] || 0) + 1;
            nstations[ipv6ll] = val;
            if (val < rs.unresponsive.ignore) {
                if (val > actionLimits.unresponsiveReport) {
                    log.syslog(log.LOG_ERR, `Possible unresponsive node: ${ipv6ll} [${stations[i].mac}] on ${rs.iface}`);
                }
                if (val > rs.unresponsive.max) {
                    rs.unresponsive.max = val;
                }
            }
        }
    }
    rs.unresponsive.stations = nstations;
}

// Monitor number of connected stations

function monitorStationCount(rs)
{
    const count = length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: rs.iface }) ?? []);
    const now = clock(true)[0];
    if (count == 0) {
        rs.stationCount.lastZero = now;
        if (rs.stationCount.firstZero <= rs.stationCount.firstNonZero) {
            rs.stationCount.firstZero = now;
        }
    }
    else {
        rs.stationCount.lastNonZero = now;
        if (rs.stationCount.firstNonZero <= rs.stationCount.firstZero) {
            rs.stationCount.firstNonZero = now;
        }
    }
}

// Take action depending on the monitor state

function runActions(rs)
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
                if (rs.defaultScanEnabled) {
                    rs.defaultScanEnabled = false;
                    resetNetwork(rs, "daily-restart");
                }
            }
            else {
                rs.defaultScanEnabled = true;
            }
        }
    }

    // No action if we have stations and they're responsive
    if (rs.stationCount.lastNonZero > rs.stationCount.lastZero && rs.unresponsive.max < actionLimits.unresponsiveTrigger1) {
        for (let k in rs.actionState) {
            rs.actionState[k] = false;
        }
        return;
    }

    // Otherwise

    // If network stations falls to zero when it was previously non-zero
    if (rs.stationCount.firstZero > rs.stationCount.firstNonZero) {
        if (!rs.actionState.zero1 && rs.stationCount.lastZero - rs.stationCount.firstZero > actionLimits.zeroTrigger1) {
            resetNetwork(rs, "zero-soft");
            rs.actionState.zero1 = true;
            return;
        }
        if (!rs.actionState.zero2 && rs.stationCount.lastZero - rs.stationCount.firstZero > actionLimits.zeroTrigger2) {
            resetNetwork(rs, "zero-hard");
            rs.actionState.zero2 = true;
            return;
        }
    }

    // We are failing to ping stations we are associated with
    if (rs.unresponsive.max >= actionLimits.unresponsiveTrigger1 && !rs.actionState.unresponsive1) {
        resetNetwork(rs, "unresponsive");
        rs.actionState.unresponsive1 = true;
        return;
    }
    if (rs.unresponsive.max >= actionLimits.unresponsiveTrigger2 && !rs.actionState.unresponsive2) {
        resetNetwork(rs, "unresponsive");
        rs.actionState.unresponsive2 = true;
        return;
    }
}

function runMonitors(rs)
{
    monitorUnresponsiveStations(rs);
    monitorStationCount(rs);
}

function save()
{
    const perRadio = {};
    for (let i = 0; i < length(radioState); i++) {
        const rs = radioState[i];
        perRadio[rs.iface] = {
            unresponsive: rs.unresponsive,
            stationCount: rs.stationCount,
            actionState: rs.actionState
        };
    }
    fs.writefile("/tmp/wireless_monitor.json", sprintf("%.2J", {
        now: clock(true)[0],
        radios: perRadio
    }));
}

function main()
{
    for (let i = 0; i < length(radioState); i++) {
        const rs = radioState[i];
        if (!rs.chipset) {
            continue;
        }
        runMonitors(rs);
        runActions(rs);
    }
    save();
    return waitForTicks(60); // 1 minute
}

return waitForTicks(max(1, 180 - clock(true)[0]), function()
{
    const now = clock(true)[0];
    const config = radios.getActiveConfiguration();
    let anyReady = false;

    for (let ri = 0; ri < length(radioState); ri++) {
        const rs = radioState[ri];

        // No station when we start
        rs.stationCount.firstNonZero = now;
        rs.stationCount.firstZero = now;

        // Extract all the necessary wifi parameters
        for (let i = 0; i < length(config); i++) {
            const c = config[i];
            if (c.iface == rs.iface) {
                rs.frequency = hardware.getChannelFrequency(rs.iface, c.mode.channel);
                rs.ssid = c.mode.ssid;
                rs.mode = c.mode.mode;
                break;
            }
        }

        const phy = hardware.getPhyDevice(rs.iface);

        // Sometimes the chipset is "missing" and the only solution is to reboot
        // Not just a 'mesh' mode thing so check early. This affects the whole
        // device, so it stays an unconditional reboot regardless of other radios.
        if (hardware.getRadioType(rs.iface) === "halow" && !fs.access(`/sys/kernel/debug/ieee80211/${phy}/morse`)) {
            log.syslog(log.LOG_ERR, `Halow startup failed - rebooting`);
            system("/sbin/reboot");
            return exitApp();
        }

        if (!(phy && rs.frequency && rs.ssid)) {
            log.syslog(log.LOG_ERR, `Startup failed for ${rs.iface}`);
            continue;
        }

        // Select chipset
        if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath9k`)) {
            rs.chipset = "ath9k";
        }
        else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath10k`)) {
            rs.chipset = "ath10k";
        }
        else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/morse`)) {
            rs.chipset = "morse";
        }
        else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/mt76`)) {
            rs.chipset = "mt76";
        }
        else {
            log.syslog(log.LOG_NOTICE, `Unknown chipset for ${rs.iface}`);
            continue;
        }

        log.syslog(log.LOG_NOTICE, `Monitoring wireless chipset: ${rs.chipset} (${rs.iface})`);
        anyReady = true;

        // Sometimes the halow radio is there but not hearing anything. Restart it to be safe.
        if (hardware.getRadioType(rs.iface) === "halow" && !length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: rs.iface }))) {
            resetNetwork(rs, "restart");
        }

        // Mikrotik devices sometime startup deaf, so handle that
        if (rs.chipset === "ath10k" && index(hardware.getBoardModel().id, "mikrotik") === 0 && !length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: rs.iface }))) {
            resetNetwork(rs, "zero-hard");
        }
    }

    if (!anyReady) {
        return exitApp();
    }

    return waitForTicks(0, main);
});
