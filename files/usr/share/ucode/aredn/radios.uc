/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2024,2025 Tim Wilkinson
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

import * as fs from "fs";
import * as hardware from "aredn.hardware";
import * as configuration from "aredn.configuration";
import * as timezones from "aredn.timezones";
import * as uci from "uci";
import * as struct from "struct";

export const RADIO_OFF = "off";
export const RADIO_MESH = "mesh";
export const RADIO_MESHPTMP = "meshap";
export const RADIO_MESHPTP = "meshptp";
export const RADIO_MESHSTA = "meshsta";
export const RADIO_LAN = "lan";
export const RADIO_WAN = "wan";

let radioCache = null;

const DFS_REGIONS = [ 'unset', 'FCC', 'ETSI', 'JP' ];
const RULE_FLAGS = [
    [ 0x01, "NO_OFDM" ],
    [ 0x02, "NO_OUTDOOR" ],
    [ 0x04, "DFS" ],
    [ 0x08, "NO_IR" ],
    [ 0x10, "AUTO_BW" ]
];
const RULE_VALID = {
    "-4":  { "20": true },
    "-3":  { "20": true },
    "-2":  { "20": true },
    "-1":  { "20": true },
    "1":   { "20": true, "40": true },
    "2":   { "20": true, "40": true },
    "3":   { "20": true, "40": true },
    "4":   { "20": true, "40": true },
    "5":   { "20": true, "40": true },
    "6":   { "20": true, "40": true },
    "7":   { "20": true, "40": true },
    "8":   { "20": true, "40": true },
    "9":   { "20": true, "40": true },
    "10":  { "20": true },
    "11":  { "20": true },
    "12":  { "20": true },
    "13":  { "20": true },
    "14":  { "20": true },
    "36":  { "20": true, "40": true, "80": true, "160": true },
    "40":  { "20": true },
    "44":  { "20": true, "40": true },
    "48":  { "20": true },
    "52":  { "20": true, "40": true, "80": true },
    "56":  { "20": true },
    "60":  { "20": true, "40": true },
    "64":  { "20": true },
    "100": { "20": true, "40": true, "80": true, "160": true },
    "104": { "20": true },
    "108": { "20": true, "40": true },
    "112": { "20": true },
    "116": { "20": true, "40": true, "80": true },
    "120": { "20": true },
    "124": { "20": true, "40": true },
    "128": { "20": true },
    "132": { "20": true, "40": true, "80": true },
    "136": { "20": true },
    "140": { "20": true, "40": true },
    "144": { "20": true },
    "149": { "20": true, "40": true, "80": true, "160": true },
    "153": { "20": true },
    "157": { "20": true, "40": true },
    "161": { "20": true },
    "165": { "20": true, "40": true, "80": true },
    "169": { "20": true },
    "173": { "20": true, "40": true },
    "177": { "20": true }
};

function regdbCountry(alpha2)
{
    const db = fs.readfile("/lib/firmware/regulatory.db");
    if (!db) {
        return null;
    }
    // Check header
    const hdr = struct.unpack('>II', db, 0);
    if (hdr[0] != 0x52474442 || hdr[1] != 20) {
        return null;
    }

    // find the country entry
    let coll_off = null;
    for (let off = 8; off + 4 <= length(db); off += 4) {
        const c = struct.unpack('>2sH', db, off);
        if (!c || c[1] == 0) {
            break;
        }
        if (c[0] == alpha2) {
            coll_off = c[1] << 2;
            break;
        }
    }
    if (coll_off == null) {
        return null;
    }

    // collection header: len, n_rules, dfsRegion; rule pointers follow at ALIGN(len, 2)
    const coll = struct.unpack('>BBB', db, coll_off);
    if (!coll) {
        return null;
    }

    const ptrs = coll_off + ((coll[0] + 1) & ~1);
    const rules = [];
    for (let i = 0; i < coll[1]; i++) {
        const p = struct.unpack('>H', db, ptrs + i * 2);
        const r = p ? struct.unpack('>BBHIII', db, p[0] << 2) : null;
        if (!r || r[0] < 16) {
            return null;
        }
        const rule = {
            startKHz: r[3],
            endKHz: r[4],
            maxBwKHz: r[5],
            maxEIRP: int((r[2] + 50.0) / 100.0)
        };
        for (let fl in RULE_FLAGS) {
            if (r[1] & fl[0]) {
                rule[fl[1]] = true;
            }
        }
        if (r[0] >= 18) {
            rule.cacTimeout = struct.unpack('>H', db, (p[0] << 2) + 16)[0];
        }
        push(rules, rule);
    }
    return { alpha2: alpha2, dfsRegion: DFS_REGIONS[coll[2]] ?? `unknown(${coll[2]})`, rules: rules };
}

export function classifyChannels(channels, zonename)
{
    const regd = regdbCountry(timezones.lookupTimezone(zonename).code);
    const rules = sort(regd.rules, (a, b) => a.startKHz - b.startKHz);
    const validate = (channels[0].frequency > 2300 && channels[0].frequency < 2600) || channels[0].frequency > 5170;

    const out = [];
    for (let ch in channels) {
        const classification = {};
        for (let w in ch.widths) {
            if (validate && !RULE_VALID[`${ch.number}`]?.[`${w}`]) {
                continue;
            }
            const lo = 1000 * (ch.frequency - (w < 20 ? w / 2.0 : 10)); // kHz
            const hi = 1000 * (ch.frequency + (w < 20 ? w / 2.0 : w - 10));

            // walk the sorted rules, extending coverage from lo towards hi
            const used = [];
            let pos = lo;
            for (let r in rules) {
                if (r.startKHz <= pos && r.endKHz > pos) {
                    push(used, r);
                    pos = r.endKHz;
                    if (pos >= hi) {
                        break;
                    }
                }
            }
            if (pos < hi) {
                continue;
            }

            if (length(filter(used, r => r.AUTO_BW)) !== length(used) && (length(used) > 1 || w * 1000 > used[0].maxBwKHz)) {
                continue;
            }

            let maxEIRP = null;
            const flags = {};
            for (let r in used) {
                for (let fl in RULE_FLAGS) {
                    if (r[fl[1]]) {
                        flags[fl[1]] = true;
                    }
                }
                if (maxEIRP == null || r.maxEIRP < maxEIRP) {
                    maxEIRP = r.maxEIRP;
                }
            }
            classification[w] = { maxEIRP: maxEIRP, ...flags };
        }
        push(out, { ...ch, classification: classification });
    }
    return out;
};

export function getCommonConfiguration()
{
    if (radioCache) {
        return json(radioCache);
    }
    const radio = [];
    const nrradios = hardware.getRadioCount();
    for (let i = 0; i < nrradios; i++) {
        const iface = `wlan${i}`;
        if (hardware.getRadioIntf(iface).disabled) {
            push(radio, { disabled: true });
        }
        else {
            push(radio, {
                iface: iface,
                mode: null,
                ant: null,
                antaux: null,
                def: hardware.getDefaultChannel(iface),
                bws: hardware.getRfBandwidths(iface),
                channels: classifyChannels(hardware.getRfChannels(iface)),
                ants: hardware.getAntennas(iface),
                antsaux: hardware.getAntennasAux(iface),
                txpoweroffset: hardware.getTxPowerOffset(iface),
                txmaxpower: hardware.getMaxTxPower(iface),
                macaddress: hardware.getInterfaceMAC(iface),
                maxdistance: 80550
            });
        }
    }
    radioCache = sprintf("%J", radio);
    return radio;
};

export function getActiveConfiguration()
{
    const cursor = uci.cursor();
    const radio = getCommonConfiguration();
    const nrradios = length(radio);
    if (nrradios > 0) {
        let mdevice1;
        let mdevice2;
        let ldevice1;
        let ldevice2;
        let wdevice;

        for (let i = 0; i < nrradios; i++) {
            radio[i].mode = { mode: RADIO_OFF };
        }

        const mmode1 = {
            mode: RADIO_MESH,
            channel: 0,
            bandwidth: 10,
            ssid: "-"
        };
        const mmode2 = {
            mode: RADIO_MESH,
            channel: 0,
            bandwidth: 10,
            ssid: "-"
        };
        const lmode1 = {
            mode: RADIO_LAN,
            channel: 0,
            ssid: "-"
        };
        const lmode2 = {
            mode: RADIO_LAN,
            channel: 0,
            ssid: "-"
        };
        const wmode = {
            mode: RADIO_WAN,
            ssid: "-"
        };

        cursor.foreach("wireless", "wifi-iface", function(s)
        {
            if (substr(s.network, 0, 4) === "wifi" && (s.mode == "ap" || s.mode == "sta" || s.mode == "adhoc")) {
                if (!mdevice1) {
                    mdevice1 = s.device;
                    mmode1.ssid = s.ssid;
                    switch (s.mode) {
                    case "ap":
                        mmode1.mode = s.macfilter === "allow" ? RADIO_MESHPTP : RADIO_MESHPTMP;
                        break;
                    case "sta":
                        mmode1.mode = RADIO_MESHSTA;
                        break;
                    case "adhoc":
                        mmode1.mode = RADIO_MESH;
                        break;
                    }
                }
                else {
                    mdevice2 = s.device;
                    mmode2.ssid = s.ssid;
                    switch (s.mode) {
                    case "ap":
                        mmode2.mode = s.macfilter === "allow" ? RADIO_MESHPTP : RADIO_MESHPTMP;
                        break;
                    case "sta":
                        mmode2.mode = RADIO_MESHSTA;
                        break;
                    case "adhoc":
                        mmode2.mode = RADIO_MESH;
                        break;
                    }
                }
            }
            if (s.network === "lan" && s.mode === "ap") {
                if (!ldevice1) {
                    ldevice1 = s.device;
                    lmode1.ssid = s.ssid;
                }
                else {
                    ldevice2 = s.device;
                    lmode2.ssid = s.ssid;
                }
            }
            if (s.network === "wan" && s.mode === "sta") {
                wdevice = s.device;
                wmode.ssid = s.ssid;
            }
        });
        cursor.foreach("wireless", "wifi-device", function(s)
        {
            if (s[".name"] === mdevice1) {
                mmode1.channel = int(s.channel);
                mmode1.bandwidth = int(s.chanbw);
                mmode1.txpower = int(s.txpower);
            }
            if (s[".name"] === mdevice2) {
                mmode2.channel = int(s.channel);
                mmode2.bandwidth = int(s.chanbw);
                mmode2.txpower = int(s.txpower);
            }
            if (s[".name"] === ldevice1) {
                lmode1.channel = int(s.channel);
            }
            if (s[".name"] === ldevice2) {
                lmode2.channel = int(s.channel);
            }
        });

        if (mdevice1) {
            const idx = int(substr(mdevice1, 5));
            radio[idx].mode = mmode1;
        }
        if (mdevice2) {
            const idx = int(substr(mdevice2, 5));
            radio[idx].mode = mmode2;
        }
        if (ldevice1) {
            const idx = int(substr(ldevice1, 5));
            radio[idx].mode = lmode1;
        }
        if (ldevice2) {
            const idx = int(substr(ldevice2, 5));
            radio[idx].mode = lmode2;
        }
        if (wdevice) {
            const idx = int(substr(wdevice, 5));
            radio[idx].mode = wmode;
        }
    }
    return radio;
};

export function getConfiguration()
{
    const cursor = uci.cursor("/etc/config.mesh");
    const radio = getCommonConfiguration();
    const nrradios = length(radio);
    if (nrradios >= 1) {
        const mode = configuration.getSettingAsString("radio0_mode");
        radio[0].mode = {
            mode: mode,
            channel: configuration.getSettingAsInt("radio0_channel"),
            channels: configuration.getSettingAsList("radio0_channels"),
            bandwidth: configuration.getSettingAsInt("radio0_bandwidth"),
            ssid: configuration.getSettingAsString("radio0_ssid"),
            txpower: configuration.getSettingAsInt("radio0_txpower"),
            key: configuration.getSettingAsString("radio0_key"),
            encryption: configuration.getSettingAsString("radio0_encryption"),
            distance: configuration.getSettingAsString("radio0_distance")
        };
        radio[0].ant = hardware.getAntennaInfo(radio[0].iface, cursor.get("aredn", "@location[0]", "antenna"));
        radio[0].antaux = hardware.getAntennaAuxInfo(radio[0].iface, cursor.get("aredn", "@location[0]", "antenna_aux"));
    }
    if (nrradios >= 2) {
        const mode = configuration.getSettingAsString("radio1_mode");
        radio[1].mode = {
            mode: mode,
            channel: configuration.getSettingAsInt("radio1_channel"),
            channels: configuration.getSettingAsList("radio1_channels"),
            bandwidth: configuration.getSettingAsInt("radio1_bandwidth"),
            ssid: configuration.getSettingAsString("radio1_ssid"),
            txpower: configuration.getSettingAsInt("radio1_txpower"),
            key: configuration.getSettingAsString("radio1_key"),
            encryption: configuration.getSettingAsString("radio1_encryption"),
            distance: configuration.getSettingAsString("radio1_distance")
        };
    }
    return radio;
};

export function getMeshRadios()
{
    const config = getActiveConfiguration();
    const radios = [];
    for (let i = 0; i < length(config); i++) {
        switch (config[i].mode.mode) {
            case RADIO_MESH:
                push(radios, { mode: config[i].mode.mode, iface: config[i].iface, main: config[i].iface });
                break;
            case RADIO_MESHPTP:
            case RADIO_MESHPTMP:
            case RADIO_MESHSTA:
                const bridge = fs.basename(fs.readlink(`/sys/class/net/${config[i].iface}/master`));
                push(radios, { mode: config[i].mode.mode, iface: config[i].iface, main: bridge });
                break;
            default:
                break;
        }
    }
    return radios;
};
