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
    // Sub-GHz HaLow (802.11ah) and older Ubiquiti M900
    "902.5": { "1": true },   // ch 1
    "903":   { "2": true },   // ch 2
    "903.5": { "1": true },   // ch 3
    "904.5": { "1": true },   // ch 5
    "905":   { "2": true },   // ch 6
    "905.5": { "1": true },   // ch 7
    "906":   { "4": true },   // ch 8
    "906.5": { "1": true },   // ch 9
    "907":   { "2": true, "5": true, "10": true, "20": true },   // ch 10 / 4
    "907.5": { "1": true },   // ch 11
    "908":   { "8": true },   // ch 12
    "908.5": { "1": true },   // ch 13
    "909":   { "2": true },   // ch 14
    "909.5": { "1": true },   // ch 15
    "910":   { "4": true },   // ch 16
    "910.5": { "1": true },   // ch 17
    "911":   { "2": true },   // ch 18
    "911.5": { "1": true },   // ch 19
    "912":   { "16": true, "5": true, "10": true, "20": true },  // ch 20 / 5
    "912.5": { "1": true },   // ch 21
    "913":   { "2": true },   // ch 22
    "913.5": { "1": true },   // ch 23
    "914":   { "4": true },   // ch 24
    "914.5": { "1": true },   // ch 25
    "915":   { "2": true },   // ch 26
    "915.5": { "1": true },   // ch 27
    "916":   { "8": true },   // ch 28
    "916.5": { "1": true },   // ch 29
    "917":   { "2": true, "5": true, "10": true, "20": true },   // ch 30 / 6
    "917.5": { "1": true },   // ch 31
    "918":   { "4": true },   // ch 32
    "918.5": { "1": true },   // ch 33
    "919":   { "2": true },   // ch 34
    "919.5": { "1": true },   // ch 35
    "920":   { "16": true },  // ch 36
    "920.5": { "1": true },   // ch 37
    "921":   { "2": true },   // ch 38
    "921.5": { "1": true },   // ch 39
    "922":   { "4": true, "5": true, "10": true, "20": true },   // ch 40 / 7
    "922.5": { "1": true },   // ch 41
    "923":   { "2": true },   // ch 42
    "923.5": { "1": true },   // ch 43
    "924":   { "8": true },   // ch 44
    "924.5": { "1": true },   // ch 45
    "925":   { "2": true },   // ch 46
    "925.5": { "1": true },   // ch 47
    "926":   { "4": true },   // ch 48
    "926.5": { "1": true },   // ch 49
    "927":   { "2": true },   // ch 50
    "927.5": { "1": true },   // ch 51
    // 2.4 GHz
    "2387": { "20": true },              // ch -4
    "2392": { "20": true },              // ch -3
    "2397": { "20": true },              // ch -2
    "2402": { "20": true },              // ch -1
    "2412": { "20": true, "40": true },  // ch 1
    "2417": { "20": true, "40": true },  // ch 2
    "2422": { "20": true, "40": true },  // ch 3
    "2427": { "20": true, "40": true },  // ch 4
    "2432": { "20": true, "40": true },  // ch 5
    "2437": { "20": true, "40": true },  // ch 6
    "2442": { "20": true, "40": true },  // ch 7
    "2447": { "20": true, "40": true },  // ch 8
    "2452": { "20": true, "40": true },  // ch 9
    "2457": { "20": true },              // ch 10
    "2462": { "20": true },              // ch 11
    "2467": { "20": true },              // ch 12
    "2472": { "20": true },              // ch 13
    "2484": { "20": true },              // ch 14
    // 5 GHz
    "5180": { "20": true, "40": true, "80": true, "160": true },  // ch 36
    "5185": {},                                                   // ch 37
    "5190": {},                                                   // ch 38
    "5195": {},                                                   // ch 39
    "5200": { "20": true },                                       // ch 40
    "5205": {},                                                   // ch 41
    "5210": {},                                                   // ch 42
    "5215": {},                                                   // ch 43
    "5220": { "20": true, "40": true },                           // ch 44
    "5225": {},                                                   // ch 45
    "5230": {},                                                   // ch 46
    "5235": {},                                                   // ch 47
    "5240": { "20": true },                                       // ch 48
    "5245": {},                                                   // ch 49
    "5250": {},                                                   // ch 50
    "5255": {},                                                   // ch 51
    "5260": { "20": true, "40": true, "80": true },               // ch 52
    "5265": {},                                                   // ch 53
    "5270": {},                                                   // ch 54
    "5275": {},                                                   // ch 55
    "5280": { "20": true },                                       // ch 56
    "5285": {},                                                   // ch 57
    "5290": {},                                                   // ch 58
    "5295": {},                                                   // ch 59
    "5300": { "20": true, "40": true },                           // ch 60
    "5305": {},                                                   // ch 61
    "5310": {},                                                   // ch 62
    "5315": {},                                                   // ch 63
    "5320": { "20": true },                                       // ch 64
    "5325": {},                                                   // ch 65
    "5330": {},                                                   // ch 66
    "5335": {},                                                   // ch 67
    "5340": {},                                                   // ch 68
    "5345": {},                                                   // ch 69
    "5350": {},                                                   // ch 70
    "5355": {},                                                   // ch 71
    "5360": {},                                                   // ch 72
    "5365": {},                                                   // ch 73
    "5370": {},                                                   // ch 74
    "5375": {},                                                   // ch 75
    "5380": {},                                                   // ch 76
    "5385": {},                                                   // ch 77
    "5390": {},                                                   // ch 78
    "5395": {},                                                   // ch 79
    "5400": {},                                                   // ch 80
    "5405": {},                                                   // ch 81
    "5410": {},                                                   // ch 82
    "5415": {},                                                   // ch 83
    "5420": {},                                                   // ch 84
    "5425": {},                                                   // ch 85
    "5430": {},                                                   // ch 86
    "5435": {},                                                   // ch 87
    "5440": {},                                                   // ch 88
    "5445": {},                                                   // ch 89
    "5450": {},                                                   // ch 90
    "5455": {},                                                   // ch 91
    "5460": {},                                                   // ch 92
    "5465": {},                                                   // ch 93
    "5470": {},                                                   // ch 94
    "5475": {},                                                   // ch 95
    "5480": {},                                                   // ch 96
    "5485": {},                                                   // ch 97
    "5490": {},                                                   // ch 98
    "5495": {},                                                   // ch 99
    "5500": { "20": true, "40": true, "80": true, "160": true },  // ch 100
    "5505": {},                                                   // ch 101
    "5510": {},                                                   // ch 102
    "5515": {},                                                   // ch 103
    "5520": { "20": true },                                       // ch 104
    "5525": {},                                                   // ch 105
    "5530": {},                                                   // ch 106
    "5535": {},                                                   // ch 107
    "5540": { "20": true, "40": true },                           // ch 108
    "5545": {},                                                   // ch 109
    "5550": {},                                                   // ch 110
    "5555": {},                                                   // ch 111
    "5560": { "20": true },                                       // ch 112
    "5565": {},                                                   // ch 113
    "5570": {},                                                   // ch 114
    "5575": {},                                                   // ch 115
    "5580": { "20": true, "40": true, "80": true },               // ch 116
    "5585": {},                                                   // ch 117
    "5590": {},                                                   // ch 118
    "5595": {},                                                   // ch 119
    "5600": { "20": true },                                       // ch 120
    "5605": {},                                                   // ch 121
    "5610": {},                                                   // ch 122
    "5615": {},                                                   // ch 123
    "5620": { "20": true, "40": true },                           // ch 124
    "5625": {},                                                   // ch 125
    "5630": {},                                                   // ch 126
    "5635": {},                                                   // ch 127
    "5640": { "20": true },                                       // ch 128
    "5645": {},                                                   // ch 129
    "5650": {},                                                   // ch 130
    "5655": {},                                                   // ch 131
    "5660": { "20": true, "40": true, "80": true },               // ch 132
    "5665": {},                                                   // ch 133
    "5670": {},                                                   // ch 134
    "5675": {},                                                   // ch 135
    "5680": { "20": true },                                       // ch 136
    "5685": {},                                                   // ch 137
    "5690": {},                                                   // ch 138
    "5695": {},                                                   // ch 139
    "5700": { "20": true, "40": true },                           // ch 140
    "5705": {},                                                   // ch 141
    "5710": {},                                                   // ch 142
    "5715": {},                                                   // ch 143
    "5720": { "20": true },                                       // ch 144
    "5725": {},                                                   // ch 145
    "5730": {},                                                   // ch 146
    "5735": {},                                                   // ch 147
    "5740": {},                                                   // ch 148
    "5745": { "20": true, "40": true, "80": true, "160": true },  // ch 149
    "5750": {},                                                   // ch 150
    "5755": {},                                                   // ch 151
    "5760": {},                                                   // ch 152
    "5765": { "20": true },                                       // ch 153
    "5770": {},                                                   // ch 154
    "5775": {},                                                   // ch 155
    "5780": {},                                                   // ch 156
    "5785": { "20": true, "40": true },                           // ch 157
    "5790": {},                                                   // ch 158
    "5795": {},                                                   // ch 159
    "5800": {},                                                   // ch 160
    "5805": { "20": true },                                       // ch 161
    "5810": {},                                                   // ch 162
    "5815": {},                                                   // ch 163
    "5820": {},                                                   // ch 164
    "5825": { "20": true, "40": true, "80": true },               // ch 165
    "5830": {},                                                   // ch 166
    "5835": {},                                                   // ch 167
    "5840": {},                                                   // ch 168
    "5845": { "20": true },                                       // ch 169
    "5850": {},                                                   // ch 170
    "5855": {},                                                   // ch 171
    "5860": {},                                                   // ch 172
    "5865": { "20": true, "40": true },                           // ch 173
    "5870": {},                                                   // ch 174
    "5875": {},                                                   // ch 175
    "5880": {},                                                   // ch 176
    "5885": { "20": true },                                       // ch 177
    "5890": {},                                                   // ch 178
    "5895": {},                                                   // ch 179
    "5900": {},                                                   // ch 180
    "5905": {},                                                   // ch 181
    "5910": {},                                                   // ch 182
    "5915": {},                                                   // ch 183
    "5920": {}                                                    // ch 184
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

    const out = [];
    for (let ch in channels) {
        const classification = {};
        for (let w in ch.widths) {
            const rvalid = RULE_VALID[`${ch.frequency}`];
            if (rvalid && !rvalid[`${w}`]) {
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
