/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2024 Tim Wilkinson
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

import * as hardware from "aredn.hardware";
import * as configuration from "aredn.configuration";
import * as uci from "uci";

export const RADIO_OFF = 0;
export const RADIO_MESH = 1;
export const RADIO_LAN = 2;
export const RADIO_WAN = 3;

export function getCommonConfiguration()
{
    const radio = [];
    const nrradios = hardware.getRadioCount();
    for (let i = 0; i < nrradios; i++) {
        const iface = `wlan${i}`;
        if (!hardware.getRadioIntf(iface).disabled) {
            push(radio, {
                iface: iface,
                mode: 0,
                modes: [],
                ant: null,
                antaux: null,
                def: hardware.getDefaultChannel(iface),
                bws: hardware.getRfBandwidths(iface),
                channels: hardware.getRfChannels(iface),
                ants: hardware.getAntennas(iface),
                antsaux: hardware.getAntennasAux(iface),
                txpoweroffset: hardware.getTxPowerOffset(iface),
                txmaxpower: hardware.getMaxTxPower(iface)
            });
        }
    }
    return radio;
};

export function getActiveConfiguration()
{
    const cursor = uci.cursor();
    const radio = getCommonConfiguration();
    const nrradios = length(radio);
    if (nrradios > 0) {
        let mdevice;
        let ldevice;
        let wdevice;

        const mmode = {
            channel: 0,
            bandwidth: 10,
            ssid: "-",
            txpower: configuration.getSettingAsInt("wifi_txpower")
        };
        const lmode = {
            channel: 0,
            ssid: "-"
        };
        const wmode = {
            ssid: "-"
        };

        cursor.foreach("wireless", "wifi-iface", function(s)
        {
            if (s.network === "wifi" && s.mode === "adhoc") {
                mdevice = s.device;
                mmode.ssid = s.ssid;
            }
            if (s.network === "lan" && s.mode === "ap") {
                ldevice = s.device;
                lmode.ssid = s.ssid;
            }
            if (s.network === "wan" && s.mode === "sta") {
                wdevice = s.device;
                wmode.ssid = s.ssid;
            }
        });
        cursor.foreach("wireless", "wifi-device", function(s)
        {
            if (s[".name"] === mdevice) {
                mmode.channel = int(s.channel);
                mmode.bandwidth = int(s.chanbw);
            }
            if (s[".name"] === ldevice) {
                lmode.channel = int(s.channel);
            }
        });

        if (mdevice) {
            const idx = int(substr(mdevice, 5));
            radio[idx].mode = RADIO_MESH;
            radio[idx].modes = [ null, mmode, null, null ];
        }
        if (ldevice) {
            const idx = int(substr(ldevice, 5));
            radio[idx].mode = RADIO_LAN;
            radio[idx].modes = [ null, null, lmode, null ];
        }
        if (wdevice) {
            const idx = int(substr(wdevice, 5));
            radio[idx].mode = RADIO_WAN;
            radio[idx].modes = [ null, null, null, wmode ];
        }
    }
    return radio;
};

export function getConfiguration()
{
    const cursor = uci.cursor("/etc/config.mesh");
    const radio = getCommonConfiguration();
    const nrradios = length(radio);
    if (nrradios > 0) {
        const modes = [ null, {
            channel: configuration.getSettingAsInt("wifi_channel"),
            bandwidth: configuration.getSettingAsInt("wifi_chanbw", 10),
            ssid: configuration.getSettingAsString("wifi_ssid", "AREDN"),
            txpower: configuration.getSettingAsInt("wifi_txpower", 27)
        },
        {
            channel: configuration.getSettingAsInt("wifi2_channel"),
            encryption: configuration.getSettingAsString("wifi2_encryption", "psk2"),
            key: configuration.getSettingAsString("wifi2_key", ""),
            ssid: configuration.getSettingAsString("wifi2_ssid", "")
        },
        {
            key: configuration.getSettingAsString("wifi3_key", ""),
            ssid: configuration.getSettingAsString("wifi3_ssid", "")
        }];
        for (let i = 0; i < nrradios; i++) {
            radio[i].modes = modes;
        }

        radio[0].ant = hardware.getAntennaInfo(radio[0].iface, cursor.get("aredn", "@location[0]", "antenna"));
        radio[0].antaux = hardware.getAntennaAuxInfo(radio[0].iface, cursor.get("aredn", "@location[0]", "antenna_aux"));

        const wifi_enable = configuration.getSettingAsInt("wifi_enable", 0);
        const wifi2_enable = configuration.getSettingAsInt("wifi2_enable", 0);
        const wifi3_enable = configuration.getSettingAsInt("wifi3_enable", 0);
        if (nrradios === 1) {
            if (wifi_enable) {
                radio[0].mode = 1;
            }
            else if (wifi2_enable) {
                radio[0].mode = 2;
            }
            else if (wifi3_enable) {
                radio[0].mode = 3;
            }
        }
        else if (wifi_enable) {
            const wifi_iface = configuration.getSettingAsString("wifi_intf", "wlan0");
            if (wifi_iface === "wlan0") {
                radio[0].mode = 1;
                if (wifi2_enable) {
                    radio[1].mode = 2;
                }
                else if (wifi3_enable) {
                    radio[1].mode = 3;
                }
            }
            else {
                radio[1].mode = 1;
                if (wifi2_enable) {
                    radio[0].mode = 2;
                }
                else if (wifi3_enable) {
                    radio[0].mode = 3;
                }
            }
        }
        else if (wifi2_enable) {
            const wifi2_hwmode = configuration.getSettingAsString("wifi2_hwmode", "11a");
            if ((wifi2_hwmode === "11a" && radio[0].def.band === "5GHz") || (wifi2_hwmode === "11g" && radio[0].def.band === "2.4GHz")) {
                radio[0].mode = 2;
                if (wifi3_enable) {
                    radio[1].mode = 3;
                }
            }
            else {
                radio[1].mode = 2;
                if (wifi3_enable) {
                    radio[0].mode = 3;
                }
            }
        }
        else if (wifi3_enable) {
            const wifi3_hwmode = configuration.getSettingAsString("wifi3_hwmode", "11a");
            if ((wifi3_hwmode === "11a" && radio[0].def.band === "5GHz") || (wifi3_hwmode === "11g" && radio[0].def.band === "2.4GHz")) {
                radio[0].mode = 3;
            }
            else {
                radio[1].mode = 3;
            }
        }
    }
    return radio;
};
