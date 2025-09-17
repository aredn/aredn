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

import * as hardware from "aredn.hardware";
import * as configuration from "aredn.configuration";
import * as uci from "uci";

export const RADIO_OFF = "off";
export const RADIO_MESH = "mesh";
export const RADIO_MESHPTMP = "meshap";
export const RADIO_MESHPTP = "meshptp";
export const RADIO_MESHSTA = "meshsta";
export const RADIO_LAN = "lan";
export const RADIO_WAN = "wan";

export function getCommonConfiguration()
{
    const radio = [];
    const nrradios = hardware.getRadioCount();
    for (let i = 0; i < nrradios; i++) {
        const iface = `wlan${i}`;
        if (!hardware.getRadioIntf(iface).disabled) {
            const r = {
                iface: iface,
                mode: null,
                ant: null,
                antaux: null,
                def: hardware.getDefaultChannel(iface),
                bws: hardware.getRfBandwidths(iface),
                channels: {},
                ants: hardware.getAntennas(iface),
                antsaux: hardware.getAntennasAux(iface),
                txpoweroffset: hardware.getTxPowerOffset(iface),
                txmaxpower: hardware.getMaxTxPower(iface),
                macaddress: hardware.getInterfaceMAC(iface),
                maxdistance: 80550,
                managedOOB: [ -4, -3, -2, -1, 0 ]
            };
            // Calculate which channels are available at which bandwidths
            const avail = {
                // WiFi
                "40": [ 36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157, 165, 173 ],
                "80": [ 36, 44, 52, 60, 100, 108, 116, 124, 132, 140, 149, 157, 165, 173 ],
                // Halow
                "1": [ 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37, 39, 41, 43, 45, 47, 49 ],
                "2": [ 6, 10, 14, 18, 22, 26, 30, 34, 38, 42, 46 ],
                "4": [ 4, 8, 16, 24, 32, 40, 48 ],
                "8": [ 12, 28, 44 ]
            };
            const channels = hardware.getRfChannels(iface);
            for (let b = 0; b < length(r.bws); b++) {
                const bw = `${r.bws[b]}`;
                switch (bw) {
                    case "5":
                    case "10":
                    case "20":
                        r.channels[bw] = channels;
                        break;
                    case "1":
                    case "2":
                    case "4":
                    case "8":
                    case "40":
                    case "80":
                    {

                        r.channels[bw] = [];
                        for (let j = 0; j < length(channels); j++) {
                            if (index(avail[bw], channels[j].number) !== -1) {
                                push(r.channels[bw], channels[j]);
                            }
                        }
                        break;
                    }
                    default:
                        break;
                }
            }
            push(radio, r);
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

        for (let i = 0; i < nrradios; i++) {
            radio[i].mode = { mode: RADIO_OFF };
        }

        const mmode = {
            mode: RADIO_MESH,
            channel: 0,
            bandwidth: 10,
            ssid: "-"
        };
        const lmode = {
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
            if (s.network === "wifi") {
                switch (s.mode) {
                    case "ap":
                        mmode.mode = s.macfilter === "allow" ? RADIO_MESHPTP : RADIO_MESHPTMP;
                        mdevice = s.device;
                        mmode.ssid = s.ssid;
                        break;
                    case "sta":
                        mmode.mode = RADIO_MESHSTA;
                        mdevice = s.device;
                        mmode.ssid = s.ssid;
                        break;
                    case "adhoc":
                        mmode.mode = RADIO_MESH;
                        mdevice = s.device;
                        mmode.ssid = s.ssid;
                        break;
                    default:
                        break;
                }
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
                mmode.txpower = int(s.txpower);
            }
            if (s[".name"] === ldevice) {
                lmode.channel = int(s.channel);
            }
        });

        if (mdevice) {
            const idx = int(substr(mdevice, 5));
            radio[idx].mode = mmode;
        }
        if (ldevice) {
            const idx = int(substr(ldevice, 5));
            radio[idx].mode = lmode;
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

export function getMeshRadio()
{
    const config = getActiveConfiguration();
    for (let i = 0; i < length(config); i++) {
        switch (config[i].mode.mode) {
            case RADIO_MESH:
            case RADIO_MESHPTP:
            case RADIO_MESHPTMP:
            case RADIO_MESHSTA:
                return { mode: config[i].mode.mode, iface: config[i].iface };
            default:
                break;
        }
    }
    return null;
};
