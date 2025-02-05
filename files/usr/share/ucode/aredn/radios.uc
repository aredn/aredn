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
export const RADIO_MESHAP = "meshap";
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
            push(radio, {
                iface: iface,
                mode: null,
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
            mode: RADIO_MESH,
            channel: 0,
            bandwidth: 10,
            ssid: "-",
            txpower: configuration.getSettingAsInt("wifi_txpower")
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
                        mmode.mode = RADIO_MESHAP;
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
            }
            if (s[".name"] === ldevice) {
                lmode.channel = int(s.channel);
            }
        });

        if (mdevice) {
            const idx = int(substr(mdevice, 5));
            radio[idx].mode = mmode;
        }
        else if (ldevice) {
            const idx = int(substr(ldevice, 5));
            radio[idx].mode = lmode;
        }
        else if (wdevice) {
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
            encryption: configuration.getSettingAsString("radio0_encryption")
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
            encryption: configuration.getSettingAsString("radio1_encryption")
        };
    }
    return radio;
};
