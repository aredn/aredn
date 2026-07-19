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

const devices = radios.getMeshRadios();
if (length(devices) === 0) {
    return exitApp();
}

const actionLimits = {
    unresponsiveReport: 3,
    unresponsiveTrigger1: 5,
    unresponsiveTrigger2: 10,
    zeroTrigger1: 5 * 60, // 5 minutes
    zeroTrigger2: 15 * 60 // 15 minutes
};
let defaultScanEnabled = true;

// Various forms of network resets

function resetNetwork(device, op)
{
    log.syslog(log.LOG_NOTICE, `resetNetwork: ${device.chipset} ${device.mode} ${op}`);
    switch (device.chipset) {
        case "ath9k":
        case "ath10k":
            switch (mode) {
                case "mesh":
                    switch (op) {
                        case "unresponsive":
                            system(`${IW} ${device.iface} ibss leave > /dev/null 2>&1`);
                            system(`${IW} ${device.iface} ibss join ${device.ssid} ${device.frequency} NOHT fixed-freq > /dev/null 2>&1`);
                            break;
                        case "zero-soft":
                            system(`${IW} ${device.iface} scan freq ${device.frequency} > /dev/null 2>&1`);
                            break;
                        case "zero-hard":
                        case "daily-restart":
                            system(`${IW} ${device.iface} scan > /dev/null 2>&1`);
                            system(`${IW} ${device.iface} scan passive > /dev/null 2>&1`);
                            break;
                        case "restart":
                            const idx = replace(device.iface, /^wlan/, "");
                            system(`${IFDOWN} wifi${idx}; ${IFUP} wifi${idx}`);
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
                const idx = replace(device.iface, /^wlan/, "");
                system(`${IFDOWN} wifi${idx}; ${IFUP} wifi${idx}`);
            }
            break;
        case "mt76":
            log.syslog(log.LOG_NOTICE, `-- ignored`);
            break;
        default:
            break;
    }
}

// Monitor stations and detect if they become unresponsive

function monitorUnresponsiveStations(device)
{
    device.unresponsive.max = 0;
    const nstations = {};

    const stations = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: device.iface }) ?? [];
    for (let i = 0; i < length(stations); i++) {
        const ipv6ll = network.mac2ipv6ll(stations[i].mac);
        const dev = replace(device.iface, /^wlan/, "br-wifi");
        if (system(`${PING6} -c 1 -W 2 -I ${device.iface} ${ipv6ll} > /dev/null 2>&1`) == 0 || system(`${PING6} -c 1 -W 2 -I ${dev} ${ipv6ll} > /dev/null 2>&1`) == 0) {
            nstations[ipv6ll] = 0;
        }
        else {
            const val = (device.unresponsive.stations[ipv6ll] || 0) + 1;
            nstations[ipv6ll] = val;
            if (val < device.unresponsive.ignore) {
                if (val > actionLimits.unresponsiveReport) {
                    log.syslog(log.LOG_ERR, `Possible unresponsive node: ${ipv6ll} [${stations[i].mac}]`);
                }
                if (val > device.unresponsive.max) {
                    device.unresponsive.max = val;
                }
            }
        }
    }
    device.unresponsive.stations = nstations;
}

// Monitor number of connected stations

function monitorStationCount(device)
{
    const count = length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: device.iface }) ?? []);
    const now = clock(true)[0];
    if (count == 0) {
        device.stationCount.lastZero = now;
        if (device.stationCount.firstZero <= device.stationCount.firstNonZero) {
            device.stationCount.firstZero = now;
        }
    }
    else {
        device.stationCount.lastNonZero = now;
        if (device.stationCount.firstNonZero <= device.stationCount.firstZero) {
            device.stationCount.firstNonZero = now;
        }
    }
}

// Take action depending on the monitor state

function runCommonActions()
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
                    map(devices, device => resetNetwork(device, "daily-restart"));
                }
            }
            else {
                defaultScanEnabled = true;
            }
        }
    }
}

function runActions(device)
{
    // No action if we have stations and they're responsive
    if (device.stationCount.lastNonZero > device.stationCount.lastZero && device.unresponsive.max < actionLimits.unresponsiveTrigger1) {
        for (let k in device.actionState) {
            device.actionState[k] = false;
        }
        return;
    }

    // Otherwise

    // If network stations falls to zero when it was previously non-zero
    if (device.stationCount.firstZero > device.stationCount.firstNonZero) {
        if (!device.actionState.zero1 && device.stationCount.lastZero - device.stationCount.firstZero > actionLimits.zeroTrigger1) {
            resetNetwork(device, "zero-soft");
            device.actionState.zero1 = true;
            return;
        }
        if (!device.actionState.zero2 && device.stationCount.lastZero - device.stationCount.firstZero > actionLimits.zeroTrigger2) {
            resetNetwork(device, "zero-hard");
            device.actionState.zero2 = true;
            return;
        }
    }

    // We are failing to ping stations we are associated with
    if (device.unresponsive.max >= actionLimits.unresponsiveTrigger1 && !device.actionState.unresponsive1) {
        resetNetwork(device, "unresponsive");
        device.actionState.unresponsive1 = true;
        return;
    }
    if (device.unresponsive.max >= actionLimits.unresponsiveTrigger2 && !device.actionState.unresponsive2) {
        resetNetwork(device, "unresponsive");
        device.actionState.unresponsive2 = true;
        return;
    }
}

function save()
{
    fs.writefile("/tmp/wireless_monitor.json", sprintf("%.2J", {
        now: clock(true)[0],
        unresponsive: map(devices, device => device.unresponsive),
        stationCount: map(devices, device => device.stationCount),
        actionState: map(devices, device => device.actionState)
    }));
}

function main()
{
    map(devices, device => monitorUnresponsiveStations(device));
    map(devices, device => monitorStationCount(device));
    runCommonActions();
    map(devices, device => runActions(device));
    save();
    return waitForTicks(60); // 1 minute
}

return waitForTicks(max(1, 180 - clock(true)[0]), function()
{
    // No station when we start
    const now = clock(true)[0];

    map(devices, device => {
        // Extract all the necessary wifi parameters
        const config = radios.getActiveConfiguration();
        for (let i = 0; i < length(config); i++) {
            const c = config[i];
            if (c.iface == device.iface) {
                device.frequency = hardware.getChannelFrequency(device.iface, c.mode.channel);
                device.ssid = c.mode.ssid;
                break;
            }
        }

        const phy = hardware.getPhyDevice(device.iface);

        // Sometimes the chipset is "missing" and the only solution is to reboot
        // Not just a 'mesh' mode thing so check early.
        if (hardware.getRadioType(device.iface) === "halow" && !fs.access(`/sys/kernel/debug/ieee80211/${phy}/morse`)) {
            log.syslog(log.LOG_ERR, `Halow startup failed - rebooting`);
            system("/sbin/reboot");
            return exitApp();
        }

        if (!(phy && device.frequency && device.ssid)) {
            log.syslog(log.LOG_ERR, `Startup failed`);
            return exitApp();
        }

        // Select chipset
        if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath9k`)) {
            device.chipset = "ath9k";
        }
        else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath10k`)) {
            device.chipset = "ath10k";
        }
        else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/morse`)) {
            device.chipset = "morse";
        }
        else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/mt76`)) {
            device.chipset = "mt76";
        }
        else {
            log.syslog(log.LOG_NOTICE, `Unknown chipset - ignoring`);
            device.chipset = "ignore";
        }

        log.syslog(log.LOG_NOTICE, `Monitoring wireless chipset: ${device.chipset}`);

        // Sometimes the halow radio is there but not hearing anything. Restart it to be safe.
        if (hardware.getRadioType(device.iface) === "halow" && !length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: device.iface }))) {
            resetNetwork(device, "restart");
        }

        // Mikrotik devices sometime startup deaf, so handle that
        if (device.chipset === "ath10k" && index(hardware.getBoardModel().id, "mikrotik") === 0 && !length(nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: device.iface }))) {
            resetNetwork(device, "zero-hard");
        }

        // Setup the monitor stats for the device.
        device.actionState = {
            zero1: true,
            zero2: true,
            unresponsive1: true,
            unresponsive2: true
        };
        device.unresponsive = {
            max: 0,
            ignore: 15,
            stations: {}
        };
        device.stationCount = {
            firstZero: now,
            firstNonZero: now,
            lastZero: 0,
            lastNonZero: 0
        };
    });

    return waitForTicks(0, main);
});
