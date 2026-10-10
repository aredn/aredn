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
import * as uci from "uci";
import * as ubus from "ubus";
import * as nl80211 from "nl80211";
import * as rtnl from "rtnl";
import * as socket from "socket";
import * as babel from "aredn.babel";

let radioJson;
let boardJson;
const antennasCache = {};
const channelsCache = {};

export function getBoard()
{
    if (!boardJson) {
        const f = fs.open("/etc/board.json");
        if (!f) {
            return {};
        }
        boardJson = json(f.read("all"));
        f.close();
        // Collapse virtualized hardware into the three basic types
        if (index(lc(boardJson.model.id), "qemu-") === 0) {
            boardJson.model.id = "qemu";
            boardJson.model.name = "QEMU";
        }
        else if (index(lc(boardJson.model.id), "vmware") === 0) {
            boardJson.model.id = "vmware";
            boardJson.model.name = "VMware";
        }
        else if (index(lc(boardJson.model.id), "joyent") === 0) {
            boardJson.model.id = "bhyve";
            boardJson.model.name = "BHyVe";
        }
        else if (index(lc(boardJson.model.id), "virtualbox") !== -1) {
            boardJson.model.id = "virtualbox";
            boardJson.model.name = "VirtualBox";
        }
        else if (index(lc(boardJson.model.id), "vultr") !== -1) {
            boardJson.model.id = "vultr";
            boardJson.model.name = "Vultr";
        }
        else if (fs.access("/sys/class/dmi/id")) {
            boardJson.model.id = "pc";
            boardJson.model.name = "PC";
        }
    }
    return boardJson;
};

export function getBoardModel()
{
    const model = getBoard().model;
    if (model) {
        return model;
    }
    return { id: "unknown", name: "unknown" };
};

export function getBoardId()
{
    let name = "";
    const model = getBoardModel();
    if (index(model.name, "Ubiquiti") === 0) {
        name = fs.readfile("/sys/devices/pci0000:00/0000:00:00.0/subsystem_device");
        if (!name || name === "" || name === "0x0000") {
            const f = fs.open("/dev/mtd7");
            if (f) {
                f.seek(12);
                const d = f.read(2);
                f.close();
                name = sprintf("0x%02x%02x", ord(d, 0), ord(d, 1));
            }
        }
    }
    if (!name || name === "" || name === "0x0000") {
        name = model.name;
    }
    return trim(name);
};

export function getRadio()
{
    if (!radioJson) {
        const f = fs.open("/etc/radios.json");
        if (!f) {
            return {};
        }
        const radios = json(f.read("all"));
        f.close();
        const id = getBoardId();
        radioJson = radios[lc(id)];
        if (!radioJson) {
            radioJson = { name: "Unknown" };
        }
        else if (!radioJson.name) {
            radioJson.name = id;
        }
    }
    return radioJson;
};

export function getRadioName()
{
    return getRadio().name;
};

export function getRadioCount()
{
    const radio = getRadio();
    if (radio.wlan0 && !radio.wlan1) {
        return 1;
    }
    else {
        return length(fs.lsdir("/sys/class/ieee80211") || []);
    }
};

export function getRadioIntf(wifiIface)
{
    if (substr(wifiIface, 0, 4) !== "wlan") {
        return null;
    }
    const radio = getRadio();
    if (radio[wifiIface]) {
        return radio[wifiIface];
    }
    else {
        return radio;
    }
};

export function getPhyDevice(wifiiface)
{
    return replace(wifiiface, /^wlan/, "phy");
};

export function getRadioDevice(wifiiface)
{
    return replace(wifiiface, /^wlan/, "radio");
};

function isAX(dev)
{
    const driver = fs.basename(fs.realpath(`/sys/class/ieee80211/${getPhyDevice(dev)}/device/driver/module`));
    return driver === "mt7915e";
}

export function getRadioType(wifiIface)
{
    const iface = getRadioIntf(wifiIface);
    if (!iface) {
        return "none";
    }
    if (iface.band == "halow" || iface.band == "3ghz" || iface.band == "900mhz") {
        return iface.band;
    }
    if (isAX(getPhyDevice(wifiIface))) {
        return "ax";
    }
    if (match(lc(getRadioName()), /ac/)) {
        return "ac";
    }
    return "n";
};

export function getBoardNetworkInterfaceName(type)
{
    const board = getBoard();
    const network = board.network && board.network[type];
    if (network) {
        if (network.ifname) {
            return [ network.ifname ];
        }
        if (network.device) {
            return [ network.device ];
        }
        if (network.ports) {
            return network.ports;
        }
    }
    return null;
};

function getChannelFromRadioFrequency(radio, freq)
{
    if (radio.band === "halow") {
        return int((freq - 902.0) * 2);
    }
    if (radio.band === "3ghz") {
        return (freq - 3000) / 5;
    }
    if (freq < 256) {
        return freq;
    }
    if (freq < 927) {
        return (freq - 887) / 5;
    }
    if (freq === 2484) {
        return 14;
    }
    if (freq === 2407) {
        return 0;
    }
    if (freq < 2484) {
        return (freq - 2407) / 5;
    }
    if (freq < 6000) {
        return (freq - 5000) / 5;
    }
};

export function getChannelFromFrequency(wifiIface, freq)
{
    return getChannelFromRadioFrequency(getRadioIntf(wifiIface), freq);
};

// hostapd only accepts these as the lower channel of a 5 GHz HT40 pair
// (allowed_ht40_channel_pair(), IEEE 802.11n Annex J). VHT/HE 80 and 160 on
// 5 GHz also need a valid HT40 pair, so this limits those widths too.
const HT40_FIRST = {
    "36": true, "44": true, "52": true, "60": true, "100": true, "108": true,
    "116": true, "124": true, "132": true, "140": true, "149": true,
    "157": true, "165": true, "173": true, "184": true, "192": true
};

// Can freq be the primary of a width MHz channel?
//
// Kernel rules (cfg80211_chandef_valid/usable): the primary is one of the
// 20 MHz subchannels, and every subchannel exists, is enabled and does not
// carry the prohibiting flag. Alignment is only enforced on 6 GHz.
//
// hostapd rules, applied when ht40_rules is set (5 GHz): the 40 MHz half of
// the block that holds the primary must be an allowed HT40 pair, and the
// primary must allow HT40 in that direction (no_ht40_plus/no_ht40_minus).
function bondOK(fmap, freq, width, flag, ht40_rules)
{
    for (let start = freq - width + 10; start <= freq - 10; start += 20) {
        if (width == 40 || ht40_rules) {
            const pair_lo = start + int((freq - 10 - start) / 40) * 40 + 10;
            const pflag = (freq == pair_lo) ? "no_ht40_plus" : "no_ht40_minus";

            if ((fmap["" + freq][pflag]) || (ht40_rules && !HT40_FIRST[`${(pair_lo - 5000) / 5}`])) {
                continue;
            }
        }

        let ok = true;
        for (let f = start + 10; f < start + width; f += 20) {
            const c = fmap["" + f];
            if (!c || c.disabled || (flag && c[flag])) {
                ok = false;
                break;
            }
        }
        if (ok) {
            return true;
        }
    }
    return false;
}

function getWiFiChannels(wifiIface)
{
    const channels = [];
    const phy = getPhyDevice(wifiIface);

    // Setup special adjustment rules for radios which reports as one thing when they're really something else.
    const ax = isAX(phy);
    let freq_adjust = (f) => f;
    let freq_min = 0;
    let freq_max = 0x7FFFFFFF;
    const radio = getRadioIntf(wifiIface);
    if (radio.band === "3ghz") {
        freq_adjust = (f) => f - 2000;
        freq_min = 3380;
        freq_max = 3495;
    }
    else if (radio.band === "900mhz") {
        freq_adjust = (f) => f - 1520;
        freq_min = 907;
        freq_max = 922;
    }
    else if (ax) {
        freq_min = 2412; // Prevent -ve channels which AX doesn't support.
    }
    const exclude = radio.exclude_channels;

    for (let w in nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, nl80211.const.NLM_F_DUMP, { split_wiphy_dump: true })) {
        if (w.wiphy_name === phy) {
            for (let bi, band in w.wiphy_bands) {
                if (band?.freqs && bi != 2 && bi != 3 && bi != 4) { // Band index: 0 = 2.4 GHz, 1 = 5 GHz, 2 = 60 GHz, 3 = 6 GHz, 4 = S1G
                    // Hardware capabilities
                    const is5g = (bi == 1);
                    const ap = filter(band.iftype_data ?? [], i => i.iftypes?.ap)[0];
                    const he = ap?.he_cap_phy?.[0] ?? 0;
                    const ht40 = !!((band.ht_capa ?? 0) & 0x2) || !!(he & 0x6);
                    const vht80 = band.vht_capa != null || !!(he & 0x4);
                    const vht160 = (band.vht_capa != null && ((band.vht_capa >> 2) & 3)) || !!(he & 0x8);

                    const fmap = {};
                    for (let f in band.freqs) {
                        fmap["" + f.freq] = f;
                    }

                    for (let c in band.freqs) {
                        const freq = freq_adjust(c.freq);
                        if (!c.disabled && !c.no_20mhz && freq >= freq_min && freq <= freq_max) {
                            const number = getChannelFromRadioFrequency(radio, freq);
                            if (!exclude || index(exclude, number) === -1) {
                                const widths = ax ? [ 20 ] : [ 5, 10, 20 ];
                                if (ht40 && bondOK(fmap, freq, 40, null, is5g)) {
                                    push(widths, 40);
                                }
                                if (bi != 0) {
                                    if (vht80 && bondOK(fmap, freq, 80, "no_80mhz", is5g)) {
                                        push(widths, 80);
                                    }
                                    if (vht160 && bondOK(fmap, freq, 160, "no_160mhz", is5g)) {
                                        push(widths, 160);
                                    }
                                }
                                push(channels, { number: number, frequency: freq, label: number != freq ? `${number} (${freq})` : `${freq}`, widths: widths });
                            }
                        }
                    }
                }
            }
        }
    }
    return channels;
}

const halowChannels = [
    { label: "1 (902.5)",  number: 1,  frequency: 902.5, widths: [] },
    { label: "2 (903)",    number: 2,  frequency: 903.0, widths: [] },
    { label: "3 (903.5)",  number: 3,  frequency: 903.5, widths: [] },
    { label: "4 (904)",    number: 4,  frequency: 904.0, widths: [ 4 ] },
    { label: "5 (904.5)",  number: 5,  frequency: 904.5, widths: [ 1 ] },
    { label: "6 (905)",    number: 6,  frequency: 905.0, widths: [ 2 ] },
    { label: "7 (905.5)",  number: 7,  frequency: 905.5, widths: [ 1 ] },
    { label: "8 (906)",    number: 8,  frequency: 906.0, widths: [ 4 ] },
    { label: "9 (906.5)",  number: 9,  frequency: 906.5, widths: [ 1 ] },
    { label: "10 (907)",   number: 10, frequency: 907.0, widths: [ 2 ] },
    { label: "11 (907.5)", number: 11, frequency: 907.5, widths: [ 1 ] },
    { label: "12 (908)",   number: 12, frequency: 908.0, widths: [ 8 ] },
    { label: "13 (908.5)", number: 13, frequency: 908.5, widths: [ 1 ] },
    { label: "14 (909)",   number: 14, frequency: 909.0, widths: [ 2 ] },
    { label: "15 (909.5)", number: 15, frequency: 909.5, widths: [ 1 ] },
    { label: "16 (910)",   number: 16, frequency: 910.0, widths: [ 4 ] },
    { label: "17 (910.5)", number: 17, frequency: 910.5, widths: [ 1 ] },
    { label: "18 (911)",   number: 18, frequency: 911.0, widths: [ 2 ] },
    { label: "19 (911.5)", number: 19, frequency: 911.5, widths: [ 1 ] },
    { label: "20 (912)",   number: 20, frequency: 912.0, widths: [] },
    { label: "21 (912.5)", number: 21, frequency: 912.5, widths: [ 1 ] },
    { label: "22 (913)",   number: 22, frequency: 913.0, widths: [ 2 ] },
    { label: "23 (913.5)", number: 23, frequency: 913.5, widths: [ 1 ] },
    { label: "24 (914)",   number: 24, frequency: 914.0, widths: [ 4 ] },
    { label: "25 (914.5)", number: 25, frequency: 914.5, widths: [ 1 ] },
    { label: "26 (915)",   number: 26, frequency: 915.0, widths: [ 2 ] },
    { label: "27 (915.5)", number: 27, frequency: 915.5, widths: [ 1 ] },
    { label: "28 (916)",   number: 28, frequency: 916.0, widths: [ 8 ] },
    { label: "29 (916.5)", number: 29, frequency: 916.5, widths: [ 1 ] },
    { label: "30 (917)",   number: 30, frequency: 917.0, widths: [ 2 ] },
    { label: "31 (917.5)", number: 31, frequency: 917.5, widths: [ 1 ] },
    { label: "32 (918)",   number: 32, frequency: 918.0, widths: [ 4 ] },
    { label: "33 (918.5)", number: 33, frequency: 918.5, widths: [ 1 ] },
    { label: "34 (919)",   number: 34, frequency: 919.0, widths: [ 2 ] },
    { label: "35 (919.5)", number: 35, frequency: 919.5, widths: [ 1 ] },
    { label: "36 (920)",   number: 36, frequency: 920.0, widths: [] },
    { label: "37 (920.5)", number: 37, frequency: 920.5, widths: [ 1 ] },
    { label: "38 (921)",   number: 38, frequency: 921.0, widths: [ 2 ] },
    { label: "39 (921.5)", number: 39, frequency: 921.5, widths: [ 1 ] },
    { label: "40 (922)",   number: 40, frequency: 922.0, widths: [ 4 ] },
    { label: "41 (922.5)", number: 41, frequency: 922.5, widths: [ 1 ] },
    { label: "42 (923)",   number: 42, frequency: 923.0, widths: [ 2 ] },
    { label: "43 (923.5)", number: 43, frequency: 923.5, widths: [ 1 ] },
    { label: "44 (924)",   number: 44, frequency: 924.0, widths: [ 8 ] },
    { label: "45 (924.5)", number: 45, frequency: 924.5, widths: [ 1 ] },
    { label: "46 (925)",   number: 46, frequency: 925.0, widths: [ 2 ] },
    { label: "47 (925.5)", number: 47, frequency: 925.5, widths: [ 1 ] },
    { label: "48 (926)",   number: 48, frequency: 926.0, widths: [] },
    { label: "49 (926.5)", number: 49, frequency: 926.5, widths: [ 1 ] },
    { label: "50 (927)",   number: 50, frequency: 927.0, widths: [] },
    { label: "51 (927.5)", number: 51, frequency: 927.5, widths: [] }
];

function getHaLowChannels(wifiIface)
{
    return halowChannels;
}

export function getRfChannels(wifiIface)
{
    let channels = channelsCache[wifiIface];
    if (!channels) {
        const radio = getRadioIntf(wifiIface);
        if (radio.band == "halow") {
            channels = getHaLowChannels(wifiIface);
        }
        else {
            channels = getWiFiChannels(wifiIface);
        }
        channelsCache[wifiIface] = channels;
    }
    return channels;
};

export function getRfBandwidths(wifiIface)
{
    const radio = getRadioIntf(wifiIface);
    const phy = getPhyDevice(wifiIface);
    const invalid = {};
    let bw = [];
    if (radio.bandwidths) {
        bw = radio.bandwidths;
    }
    else {
        map(radio.exclude_bandwidths || [], v => invalid[v] = true);
        if (!isAX(phy)) {
            if (!invalid["5"]) {
                push(bw, 5);
            }
            if (!invalid["10"]) {
                push(bw, 10);
            }
        }
        if (!invalid["20"]) {
            push(bw, 20);
        }
    }
    if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath10k`) || fs.access(`/sys/kernel/debug/ieee80211/${phy}/mt76`)) {
        const board = getBoard();
        const bands = board.wlan[phy]?.info?.bands;
        if (bands) {
            const modes = (bands["2G"] || bands["5G"])?.modes;
            for (let i = 0; i < length(modes); i++) {
                const line = modes[i];
                if (index(line, "40") !== -1 && !invalid["40"]) {
                    push(bw, 40);
                }
                if (index(line, "80") !== -1 && !invalid["80"]) {
                    push(bw, 80);
                }
                if (index(line, "160") !== -1 && !invalid["160"]) {
                    push(bw, 160);
                }
            }
        }
    }
    return uniq(bw);
};

export function getDefaultChannel(wifiIface)
{
    const rfchannels = getRfChannels(wifiIface);
    const rfbandwidths = getRfBandwidths(wifiIface);
    let bw = 0;
    if (index(rfbandwidths, 10) !== -1) {
        bw = 10;
    }
    else if (index(rfbandwidths, 20) !== -1) {
        bw = 20;
    }
    else if (index(rfbandwidths, 5) !== -1) {
        bw = 5;
    }
    for (let i = 0; i < length(rfchannels); i++) {
        const c = rfchannels[i];
        if (c.frequency == 904.5) {
            return { channel: 5, bandwidth: 1, band: "HaLow" };
        }
        if (c.frequency == 912) {
            return { channel: 5, bandwidth: 5, band: "900MHz" };
        }
        if (c.frequency === 2397) {
            return { channel: -2, bandwidth: bw, band: "2.4GHz" };
        }
        if (c.frequency === 2412) {
            return { channel: 1, bandwidth: bw, band: "2.4GHz" };
        }
        if (c.frequency === 3420) {
            return { channel: 84, bandwidth: bw, band: "3GHz" };
        }
        if (c.frequency === 5745) {
            return { channel: 149, bandwidth: bw, band: "5GHz" };
        }
    }
    return null;
};

export function getAntennas(wifiIface)
{
    let ants = antennasCache[wifiIface];
    if (!ants) {
        const radio = getRadioIntf(wifiIface);
        if (radio && radio.antenna) {
            if (radio.antenna === "external") {
                const dchan = getDefaultChannel(wifiIface);
                if (dchan && dchan.band) {
                    const f = fs.open("/etc/antennas.json");
                    if (f) {
                        ants = json(f.read("all"));
                        f.close();
                        ants = ants[dchan.band];
                    }
                }
            }
            else {
                radio.antenna.builtin = true;
                ants = [ radio.antenna ];
            }
            antennasCache[wifiIface] = ants;
        }
    }
    return ants;
};

export function getAntennasAux(wifiIface)
{
    let ants = antennasCache["aux:" + wifiIface];
    if (!ants) {
        const radio = getRadioIntf(wifiIface);
        if (radio && radio.antenna_aux === "external") {
            const dchan = getDefaultChannel(wifiIface);
            if (dchan && dchan.band) {
                const f = fs.open("/etc/antennas.json");
                if (f) {
                    ants = json(f.read("all"));
                    f.close();
                    ants = ants[dchan.band];
                }
            }
            antennasCache["aux:" + wifiIface] = ants;
        }
    }
    return ants;
};

export function getAntennaInfo(wifiIface, antenna)
{
    const ants = getAntennas(wifiIface);
    if (ants) {
        if (length(ants) === 1) {
            return ants[0];
        }
        if (antenna) {
            for (let i = 0; i < length(ants); i++) {
                if (ants[i].model === antenna) {
                    return ants[i];
                }
            }
        }
    }
    return null;
};

export function getAntennaAuxInfo(wifiIface, antenna)
{
    const ants = getAntennasAux(wifiIface);
    if (ants) {
        if (length(ants) === 1) {
            return ants[0];
        }
        if (antenna) {
            for (let i = 0; i < length(ants); i++) {
                if (ants[i].model === antenna) {
                    return ants[i];
                }
            }
        }
    }
    return null;
};

export function getAntennaPolarization(wifiIface)
{
    if (getRadioType(wifiIface) !== "halow") {
        return null;
    }
    return uci.cursor("/etc/config.mesh").get("aredn", "@location[0]", "polarization") || "-";
};

export function getChannelFrequency(wifiIface, channel)
{
    const rfchans = getRfChannels(wifiIface);
    if (rfchans[0]) {
        for (let i = 0; i < length(rfchans); i++) {
            const c = rfchans[i];
            if (c.number == channel) {
                return c.frequency;
            }
        }
    }
    return null;
};

export function getChannelFrequencyRange(wifiIface, channel, bandwidth)
{
    const rfchans = getRfChannels(wifiIface);
    if (rfchans[0]) {
        for (let i = 0; i < length(rfchans); i++) {
            const c = rfchans[i];
            if (c.number == channel) {
                return (c.frequency - bandwidth / 2.0) + " - " + (c.frequency + bandwidth / 2.0) + " MHz";
            }
        }
    }
    return null;
};

export function getMaxTxPower(wifiIface, channel)
{
    const radio = getRadioIntf(wifiIface);
    if (radio) {
        const maxpower = radio.maxpower;
        const chanpower = radio.chanpower;
        if (channel && chanpower) {
            for (let k in chanpower) {
                if (channel <= k) {
                    return chanpower[k];
                }
            }
        }
        if (maxpower) {
            return maxpower;
        }
    }
    return 27;
};

export function getTxPowerOffset(wifiIface)
{
    const radio = getRadioIntf(wifiIface);
    if (radio && radio.pwroffset) {
        return radio.pwroffset;
    }
    const f = fs.popen(`/usr/bin/iwinfo ${wifiIface} info 2> /dev/null`);
    if (f) {
        for (;;) {
            const line = f.read("line");
            if (!line) {
                break;
            }
            if (index(line, "TX power offset: ") !== -1) {
                const pwroff = match(line, /TX power offset: (\d+)/);
                if (pwroff) {
                    f.close();
                    return int(pwroff[1]);
                }
                return 0;
            }
        }
        f.close();
    }
    return 0;
};

export function getRadioNoise(wifiIface)
{
    const survey = nl80211.request(nl80211.const.NL80211_CMD_GET_SURVEY, nl80211.const.NLM_F_DUMP, { dev: wifiIface }) || [];
    for (let i = 0; i < length(survey); i++) {
        if (survey[i].dev == wifiIface && survey[i].survey_info.noise) {
            return survey[i].survey_info.noise;
        }
    }
    if (getRadioType(wifiIface) === "halow") {
        const p = fs.popen(`/sbin/morse_cli -i ${wifiIface} stats 2>/dev/null | grep 'Noise (dBm)'`);
        if (p) {
            const m = match(p.read("all"), /: (-\d+)/);
            p.close();
            if (m) {
                return int(m[1]);
            }
        }
    }
    return -95;
};

export function getStations(wifiIface)
{
    const stations = [];
    const wlans = [ wifiIface, ...map(fs.glob(`/sys/class/net/${wifiIface}.sta*`), w => fs.basename(w)) ];
    for (let w = 0; w < length(wlans); w++) {
        const info = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: wlans[w] });
        if (type(info) === "array") {
            push(stations, ...info);
        }
    }
    return stations;
};

export function getStation(wifiIface, macAddress)
{
    return nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, 0, { dev: wifiIface, mac: macAddress });
};

export function getCurrentFrequency(wifiIface)
{
    switch (getRadioType(wifiIface)) {
        case "none":
            return null;
        case "halow":
            const p = fs.popen(`/sbin/morse_cli -i ${wifiIface} channel -j 2>/dev/null`);
            if (p) {
                const all = p.read("all");
                p.close();
                try {
                    return json(all).channel_frequency / 1000;
                }
                catch (_) {
                }
            }
            return null;
        default:
            const iface = nl80211.request(nl80211.const.NL80211_CMD_GET_INTERFACE, nl80211.const.NLM_F_DUMP, { dev: wifiIface });
            return iface?.[0]?.wiphy_freq;
    }
};

export function getMaxDistance(wifiIface)
{
    switch (getRadioType(wifiIface)) {
        case "none":
            return -1;
        case "halow":
            const p = fs.popen(`/sbin/morse_cli -i ${wifiIface} get ack_timeout_adjust 2>/dev/null`);
            if (p) {
                const ack = trim(p.read("all"));
                p.close();
                const iack = int(ack);
                if (ack == iack) {
                    return (iack - 300) / 0.0067;
                }
            }
            return 0;
        default:
            const info = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, 0, { wiphy: int(substr(getPhyDevice(wifiIface), 3)) });
            return info.wiphy_coverage_class * 450;
    }
};

export function setMaxDistance(wifiIface, distance)
{
    switch (getRadioType(wifiIface)) {
        case "none":
            return -1;
        case "halow":
            const ack = 300 + int(distance * 0.0067);
            system(`/sbin/morse_cli -i ${wifiIface} set ack_timeout_adjust ${ack} > /dev/null 2>&1`);
            return (ack - 300) / 0.0067;
        default:
            const coverage = min(255, int(distance / 450));
            system(`/usr/sbin/iw ${getPhyDevice(wifiIface)} set coverage ${coverage} > /dev/null 2>&1`);
            return coverage * 450;
    }
};

export function getHTMode(wifiIface, bandwidth, mode)
{
    const phy = getPhyDevice(wifiIface);
    let htmode = "NOHT";
    if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath9k`)) {
        htmode = "HT20";
    }
    else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath10k`)) {
        switch (bandwidth) {
            case 5:
            case 10:
            case 20:
                if (fs.access("/lib/firmware/ath10k/QCA9888") || fs.access("/lib/firmware/ath10k/QCA4019")) {
                    if (mode === "mesh") {
                        htmode = "NOHT";
                    }
                    else {
                        htmode = "HT20";
                    }
                }
                else {
                    htmode = "VHT20";
                }
                break;
            case 40:
            case 80:
            case 160:
                htmode = `VHT${bandwidth}`;
                break;
            default:
                htmode = "HT20";
                break;
        }
    }
    else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/mt76`)) {
        const prefix = isAX(phy) && mode !== "mesh" ? "HE" : "VHT";
        switch (bandwidth) {
            case 5:
            case 10:
            case 20:
            default:
                htmode = `${prefix}20`;
                break;
            case 40:
            case 80:
            case 160:
                htmode = `${prefix}${bandwidth}`;
                break;
        }
    }
    else if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/morse`)) {
        htmode = null;
    }
    return htmode;
};

export function getNetworkInterfaces()
{
    const ifs = rtnl.request(rtnl.const.RTM_GETLINK, rtnl.const.NLM_F_DUMP, {});
    rtnl.close();
    return ifs;
};

export function getNetworkInterfaceAddresses()
{
    const ifs = rtnl.request(rtnl.const.RTM_GETADDR, rtnl.const.NLM_F_DUMP, {});
    rtnl.close();
    return ifs;
};

export function getInterfaceMAC(dev)
{
    const ifs = getNetworkInterfaces();
    for (let i = 0; i < length(ifs); i++) {
        const iface = ifs[i];
        if (iface.dev == dev && iface.address) {
            return iface.address;
        }
    }
    // If wlan interface isn't configured, we won't find it using GETLINK, so we look at the /sys filesystem.
    if (match(dev, /^wlan/)) {
        const addr = trim(fs.readfile(`/sys/class/ieee80211/${getPhyDevice(dev)}/macaddress`));
        if (addr) {
            return addr;
        }
    }
    return "00:00:00:00:00:00";
};

const maxDistanceSupport = {};

export function supportsFeature(feature, arg1, arg2)
{
    switch (feature) {
        case "poe":
        {
            const board = getBoard();
            if (board.gpioswitch?.poe_passthrough?.pin) {
                return true;
            }
            const gpios = fs.lsdir("/sys/class/gpio/");
            for (let i = 0; i < length(gpios); i++) {
                if (match(gpios[i], /^enable-poe:/)) {
                    return true;
                }
            }
            return false;
        }
        case "usb-power":
        {
            const board = getBoard();
            if (board.gpioswitch?.usb_power_switch?.pin) {
                return true;
            }
            if (fs.access("/sys/class/gpio/usb-power")) {
                return true;
            }
            return false;
        }
        case "max-distance":
        {
            switch (getRadioType(arg1)) {
                case "none":
                    return false;
                case "halow":
                    return true;
                default:
                    if (!(arg1 in maxDistanceSupport)) {
                        const phy = getPhyDevice(arg1);
                        const info = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, 0, { wiphy: int(substr(phy, 3)) });
                        if (info && system(`/usr/sbin/iw ${phy} set coverage ${info.wiphy_coverage_class} > /dev/null 2>&1`) == 0) {
                            maxDistanceSupport[arg1] = true;
                        }
                        else {
                            maxDistanceSupport[arg1] = false;
                        }
                    }
                    return maxDistanceSupport[arg1];
            }
        }
        case "wifi-mode":
        {
            const modes = getRadioIntf(arg1)?.exclude_modes;
            return (!modes || index(modes, arg2) === -1);
        }
        case "hw-watchdog":
            return !!fs.access("/dev/watchdog") && !fs.access("/tmp/no-hw-watchdog");
        case "boot-efi":
            return !!fs.access("/sys/firmware/efi");
        case "xlink":
        case "supernode":
        case "videoproxy":
        default:
            const features = getRadio().features;
            if (features && index(features, feature) !== -1) {
                return true;
            }
            return false;
    }
};

const default1PortLayout = [ { k: "lan", d: "lan" } ];
const defaultAlt1PortLayout = [ { k: "eth0", d: "eth0" } ];
const default5PortLayout = [ { k: "wan", d: "port1" }, { k: "lan1", d: "port2" }, { k: "lan2", d: "port3" }, { k: "lan3", d: "port4" }, { k: "lan4", d: "port5" } ];
const default4PortLayout = [ { k: "wan", d: "port1" }, { k: "lan1", d: "port2" }, { k: "lan2", d: "port3" }, { k: "lan3", d: "port4" } ];
const default3PortLayout = [ { k: "lan2", d: "port1" }, { k: "lan1", d: "port2" }, { k: "wan", d: "port3" } ];
const openwrtone2PortLayout = [ { k: "eth1", d: "1G" }, { k: "eth0", d: "2.5G" } ];
const halowlink3PortLayout = [ { k: "usblan", d: "usb" }, { k: "lan", d: "lan" }, { k: "wan", d: "wan" } ];
const defaultNPortLayout = [];

export function getEthernetPorts()
{
    switch (getBoardModel().id) {
        case "mikrotik,hap-ac2":
        case "mikrotik,hap-ac3":
            return default5PortLayout;
        case "cudy,wr3000-v1":
            return default4PortLayout;
        case "cudy,wr3000e-v1":
        case "cudy,wr3000h-v1":
        case "cudy,wr3000p-v1":
        case "cudy,wr3000s-v1":
            return default5PortLayout;
        case "glinet,gl-a1300":
        case "glinet,gl-b1300":
        case "glinet,gl-mt1300":
            return default3PortLayout;
        case "openwrt,one":
        case "cudy,tr3000-v1":
            return openwrtone2PortLayout;
        case "morse,artini":
        case "morse,halowlink2":
            return halowlink3PortLayout;
        case "qemu":
        case "vmware":
        case "bhyve":
        case "virtualbox":
        case "pc":
        case "vultr":
            if (length(defaultNPortLayout) === 0) {
                const dir = fs.opendir("/sys/class/net");
                if (dir) {
                    const reEth = /^eth\d+$/;
                    for (;;) {
                        const file = dir.read();
                        if (!file) {
                            break;
                        }
                        if (match(file, reEth)) {
                            push(defaultNPortLayout, { k: file, d: file });
                        }
                    }
                    dir.close();
                    sort(defaultNPortLayout, (a, b) => a.d == b.d ? 0 : a.d < b.d ? -1 : 1);
                }
            }
            return defaultNPortLayout;
        default:
            // Unspecified devices which support xlinks need ports to expose this in the UI.
            // We will assume they only have one port to simplify things.
            if (supportsFeature("xlink")) {
                if (fs.access("/sys/class/net/lan")) {
                    return default1PortLayout;
                }
                if (fs.access("/sys/class/net/eth0")) {
                    return defaultAlt1PortLayout;
                }
            }
            return [];
    }
};

export function getEthernetPortInfo(port)
{
    const s = { active: false };
    if (fs.readfile(`/sys/class/net/${port}/carrier`, 1) === "1") {
        s.active = true;
    }
    return s;
};

export function getDefaultNetworkConfiguration()
{
    const c = {
        dtdlink: { vlan: 2, ports: {} },
        lan: { vlan: 0, ports: {} },
        wan: { vlan: 0, ports: {} }
    };
    const board = getBoard();
    const network = board.network || {};
    const reDev = /^([^\.]+)\.?(\d*)$/;
    for (let k in network) {
        const net = c[k];
        if (net) {
            const devices = split(network[k].device, " ");
            for (let i = 0; i < length(devices); i++) {
                const m = match(devices[i], reDev);
                if (m) {
                    net.ports[m[1]] = true;
                    if (m[2]) {
                        net.vlan = int(m[2]);
                    }
                }
            }
            const ports = network[k].ports || [];
            for (let i = 0; i < length(ports); i++) {
                const m = match(ports[i], reDev);
                if (m) {
                    net.ports[m[1]] = true;
                    if (m[2]) {
                        net.vlan = int(m[2]);
                    }
                }
            }
        }
    }
    return c;
};

export function getHardwareType()
{
    const model = getBoardModel();
    let targettype = ubus.connect().call("system", "board", {}).release.target;
    let hardwaretype = model.id;
    let m = match(hardwaretype, /,(.*)/);
    if (m) {
        hardwaretype = m[1];
    }
    const mfg = trim(model.name);
    let mfgprefix = "";
    if (match(mfg, /[Uu]biquiti/)) {
        mfgprefix = "ubnt";
    }
    else if (match(mfg, /[Mm]ikro[Tt]ik/)) {
        mfgprefix = "mikrotik";
        switch (hardwaretype) {
            case "hap-ac3":
            case "routerboard-911g-2hpnd-12s":
                // Exceptions
                break;
            default:
                const bv = fs.open("/sys/firmware/mikrotik/soft_config/bios_version");
                if (bv) {
                    const v = bv.read("all");
                    bv.close();
                    if (substr(v, 0, 2) === "7.") {
                        targettype += "-v7"
                    }
                }
                break;
        }
    }
    else if (match(mfg, /[Tt][Pp]-[Ll]ink/)) {
        mfgprefix = "cpe";
    }
    if (supportsFeature("boot-efi")) {
        targettype += "-efi";
    }
    return `(${targettype}) ${mfgprefix ? mfgprefix + " " : ""}(${hardwaretype})`;
};

export function getLinkLed()
{
    const led = getBoard().led;
    if (led) {
        if (led.rssilow && led.rssilow.sysfs) {
            return `/sys/class/leds/${led.rssilow.sysfs}`;
        }
        if (led.user && led.user.sysfs) {
            return `/sys/class/leds/${led.user.sysfs}`;
        }
    }
    return null;
};

const GPSD = "/usr/sbin/gpsd";
const GPS_TTYS = [
    "/dev/ttyACM0",
    "/dev/ttyUSB0"
];

export function GPSFind()
{
    if (fs.access(GPSD)) {
        for (let i = 0; i < length(GPS_TTYS); i++) {
            const tty = GPS_TTYS[i];
            if (fs.access(tty)) {
                return tty;
            }
        }
    }
    const neighbors = babel.getRoutableNeighbors();
    for (let i = 0; i < length(neighbors); i++) {
        const n = neighbors[i];
        if (n.interface === "br-dtdlink") {
            const ip = `${n.ipv6address}%${n.interface}`;
            const s = socket.connect(ip, 2947, null, 500);
            if (s) {
                if (s.send("\n") === 1) {
                    s.close();
                    return ip;
                }
                s.close();
            }
        }
    }
    return null;
};

export function GPSReadLLT(gps, maxlines)
{
    const info = {
        lat: null,
        lon: null,
        time: null
    };
    if (match(gps, /^\/dev\//)) {
        gps = "127.0.0.1";
    }
    const s = socket.connect(gps, 2947, null, 500);
    if (!s) {
        return null;
    }
    s.send('?WATCH={"enable":true,"json":true}\n');
    if (!maxlines) {
        maxlines = 10;
    }
    for (; maxlines > 0; maxlines--) {
        let str = "";
        let j = null;
        for (;;) {
            const c = s.recv(1);
            if (!c || !length(c)) {
                maxlines = 0;
                break;
            }
            if (c == "\n") {
                j = json(str);
                break;
            }
            str += c;
        }
        if (j && j.class == "TPV") {
            info.time = replace(replace(j.time, "T", " "), ".000Z", "");
            if (j.lat && j.lon) {
                info.lat = 1 * sprintf("%.5f", j.lat);
                info.lon = 1 * sprintf("%.5f", j.lon);
            }
            break;
        }
    }
    s.close();
    return info;
};

export function getTimeouts(type)
{
    const timeouts = getRadio().timeouts || {};
    switch (type) {
        case "reboot":
            return timeouts.reboot || [ 20, 120 ];
        case "upgrade":
            return timeouts.upgrade || [ 120, 300 ];
        default:
            return [ 20, 120 ];
    }
};
