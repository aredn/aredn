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
        if (index(boardJson.model.id, "qemu-") === 0) {
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
    }
    return boardJson;
};

export function getBoardModel()
{
    const model = getBoard().model;
    if (model) {
        return model;
    }
    switch (ubus.connect().call("system", "board", {}).release.target) {
        case "x86/64":
            return { id: "pc", name: "pc" };
        default:
            return { id: "unknown", name: "unknown" };
    }
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

function getRadio()
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
}

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

export function getRadioType(wifiIface)
{
    const iface = getRadioIntf(wifiIface);
    if (!iface) {
        return "none";
    }
    else if (iface.band == "halow") {
        return "halow";
    }
    else {
        return "wifi";
    }
};

export function getPhyDevice(iface)
{
    return replace(replace(iface, /^wlan/, "phy"), /^radio/, "phy");
};

export function getWlanDevice(iface)
{
    return replace(replace(iface, /^phy/, "wlan"), /^radio/, "wlan");
};

export function getRadioDevice(iface)
{
    return replace(replace(iface, /^phy/, "radio"), /^wlan/, "radio");
};

export function getChannelFromFrequency(wifiIface, freq)
{
    const radio = getRadioIntf(wifiIface);
    if (radio.band === "halow") {
        return int((freq - 902.0) * 2);
    }
    if (freq < 256) {
        return freq;
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
    if (freq < 5000) {
        return (freq - 3000) / 5;
    }
    if (freq < 5380) {
        return (freq - 5000) / 5;
    }
    if (freq < 5500) {
        return freq - 2000;
    }
    if (freq < 6000) {
        return (freq - 5000) / 5;
    }
};

function getWiFiChannels(wifiIface)
{
    const channels = [];
    const info = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, 0, { wiphy: int(substr(wifiIface, 4)) });
    if (!info) {
        return [];
    }
    let best = { band: 0, count: 0 };
    for (let i = 0; i < length(info.wiphy_bands); i++) {
        const f = info.wiphy_bands[i]?.freqs;
        let count = 0;
        for (let j = 0; j < length(f); j++) {
            if (!f[j].disabled) {
                count++;
            }
        }
        if (count > best.count) {
            best.band = i;
            best.count = count;
        }
    }
    const freqs = info.wiphy_bands[best.band].freqs;
    let freq_adjust = (f) => f.freq;
    let freq_min = 0;
    let freq_max = 0x7FFFFFFF;
    if (wifiIface === "wlan0") {
        const radioname = getRadioName();
        if (index(radioname, "M9") !== -1) {
            freq_adjust = (f) => f.freq - 1520;
            freq_min = 907;
            freq_max = 922;
        }
        else if (index(radioname, "M3") !== -1) {
            freq_adjust = (f) => f.freq - 2000;
            freq_min = 3380;
            freq_max = 3495;
        }
    }
    for (let i = 0; i < length(freqs); i++) {
        const f = freqs[i];
        const freq = freq_adjust(f);
        if (freq >= freq_min && freq <= freq_max) {
            const num = getChannelFromFrequency(wifiIface, freq);
            push(channels, {
                label: num != freq ? num + " (" + freq + ")" : "" + freq,
                number: num,
                frequency: freq
            });
        }
    }
    sort(channels, (a, b) => a.frequency - b.frequency);
    return channels;
}

function getHaLowChannels(wifiIface)
{
    const channels = [];
    const p = fs.popen(`/usr/bin/iwinfo ${getPhyDevice(wifiIface)} freqlist`);
    if (p) {
        for (let line = p.read("line"); length(line); line = p.read("line")) {
            const m = match(line, /([0-9\.]+) MHz .* Channel ([0-9]+)/);
            if (m) {
                push(channels, {
                    label: `${m[2]} (${1.0 * m[1]})`,
                    number: int(m[2]),
                    frequency: 1.0 * m[1]
                });
            }
        }
        p.close();
    }
    return channels;
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
    const invalid = {};
    let bw = [];
    if (radio.bandwidths) {
        bw = radio.bandwidths;
    }
    else {
        map(radio.exclude_bandwidths || [], v => invalid[v] = true);
        if (!invalid["5"]) {
            push(bw, 5);
        }
        if (!invalid["10"]) {
            push(bw, 10);
        }
        if (!invalid["20"]) {
            push(bw, 20);
        }
    }
    const phy = replace(wifiIface, "wlan", "phy");
    if (fs.access(`/sys/kernel/debug/ieee80211/${phy}/ath10k`) || fs.access(`/sys/kernel/debug/ieee80211/${phy}/mt76`)) {
        const f = fs.popen(`/usr/bin/iwinfo ${phy} htmodelist 2> /dev/null`);
        if (f) {
            let line = f.read("line");
            if (line) {
                if (index(line, "HT40") !== -1 && !invalid["40"]) {
                    push(bw, 40);
                }
                if (index(line, "VHT80") !== -1 && !invalid["80"]) {
                    push(bw, 80);
                }
            }
            while (line) {
                line = f.read("line");
            }
            f.close();
        }
    }
    return bw;
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

export function getChannelFrequency(wifiIface, channel)
{
    const rfchans = getRfChannels(wifiIface);
    if (rfchans[0]) {
        for (let i = 0; i < length(rfchans); i++) {
            const c = rfchans[i];
            if (c.number === channel) {
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
    // Fallback for hardware which doesn't support the survey api (e.g. HaLow)
    const p = fs.popen(`/usr/bin/iwinfo ${wifiIface} info | /bin/grep Noise`);
    if (p) {
        const m = match(p.read("all"), /Noise: (-\d+) dBm/);
        p.close();
        if (m) {
            return int(m[1]);
        }
    }
    return -95;
};

export function getMaxDistance(wifiIface)
{
    switch (getRadioType(wifiIface)) {
        case "none":
            return -1;
        case "halow":
            const p = fs.popen("/sbin/morse_cli get ack_timeout_adjust");
            if (p) {
                const ack = int(p.read("line"));
                p.close();
                return ack * 150;
            }
            return -1;
        default:
            const info = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, 0, { wiphy: int(substr(wifiIface, 4)) });
            return info.wiphy_coverage_class * 450;
    }
};

export function setMaxDistance(wifiIface, distance)
{
    switch (getRadioType(wifiIface)) {
        case "none":
            break;
        case "halow":
            const ack = max(2, 2 * int(distance / 300));
            system(`/sbin/morse_cli set ack_timeout_adjust ${ack} > /dev/null 2>&1`);
            break;
        default:
            const coverage = min(255, int(distance / 450));
            system(`/usr/sbin/iw ${getPhyDevice(wifiIface)} set coverage ${coverage} > /dev/null 2>&1`);
            break;
    }
};

function supportsMaxDistance(wifiIface)
{
    switch (getRadioType(wifiIface)) {
        case "none":
            return false;
        case "halow":
            return true;
        default:
            const info = nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, 0, { wiphy: int(substr(wifiIface, 4)) });
            if (info) {
                if (system(`/usr/sbin/iw ${getPhyDevice(wifiIface)} set coverage ${info.wiphy_coverage_class} > /dev/null 2>&1`) == 0) {
                    return true;
                }
            }
            return false;
    }
}

function supportsMode(wifiIface, mode)
{
    const modes = getRadioIntf(wifiIface)?.exclude_modes;
    return (!modes || index(modes, mode) === -1);
}

export function getInterfaceMAC(dev)
{
    const ifs = rtnl.request(rtnl.const.RTM_GETLINK, rtnl.const.NLM_F_DUMP, {});
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

function supportsXLink()
{
    switch (getBoardModel().id) {
        case "mikrotik,hap-ac2":
        case "mikrotik,hap-ac3":
        case "mikrotik,sxtsq-5-ac":
        case "glinet,gl-b1300":
        case "openwrt,one":
        case "qemu":
        case "vmware":
        case "bhyve":
        case "pc":
            return true;
        default:
            return false;
    }
}

const default1PortLayout = [ { k: "lan", d: "lan" } ];
const default5PortLayout = [ { k: "wan", d: "port1" }, { k: "lan1", d: "port2" }, { k: "lan2", d: "port3" }, { k: "lan3", d: "port4" }, { k: "lan4", d: "port5" } ];
const default3PortLayout = [ { k: "lan2", d: "port1" }, { k: "lan1", d: "port2" }, { k: "wan", d: "port3" } ];
const openwrtone2PortLayout = [ { k: "eth1", d: "1G" }, { k: "eth0", d: "2.5G" } ];
const defaultNPortLayout = [];

export function getEthernetPorts()
{
    switch (getBoardModel().id) {
        case "mikrotik,hap-ac2":
        case "mikrotik,hap-ac3":
            return default5PortLayout;
        case "glinet,gl-b1300":
            return default3PortLayout;
        case "openwrt,one":
            return openwrtone2PortLayout;
        case "mikrotik,sxtsq-5-ac":
            return default1PortLayout;
        case "qemu":
        case "vmware":
        case "bhyve":
        case "pc":
            if (length(defaultNPortLayout) === 0) {
                const dir = fs.opendir("/sys/class/net");
                if (dir) {
                    for (;;) {
                        const file = dir.read();
                        if (!file) {
                            break;
                        }
                        if (match(file, /^eth\d+$/)) {
                            push(defaultNPortLayout, { k: file, d: file });
                        }
                    }
                    dir.close();
                    sort(defaultNPortLayout, (a, b) => a.d == b.d ? 0 : a.d < b.d ? -1 : 1);
                }
            }
            return defaultNPortLayout;
        default:
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
    for (let k in network) {
        const net = c[k];
        if (net) {
            const devices = split(network[k].device, " ");
            for (let i = 0; i < length(devices); i++) {
                const m = match(devices[i], /^([^\.]+)\.?(\d*)$/);
                if (m) {
                    net.ports[m[1]] = true;
                    if (m[2]) {
                        net.vlan = int(m[2]);
                    }
                }
            }
            const ports = network[k].ports || [];
            for (let i = 0; i < length(ports); i++) {
                net.ports[ports[i]] = true;
            }
        }
    }
    return c;
};

function hasPOE()
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

function hasUSBPower()
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
                // Exception: hAP ac3 doesn't need this
                break;
            default:
                const bv = fs.open("/sys/firmware/mikrotik/soft_config/bios_version");
                if (bv) {
                    const v = bv.read("all");
                    bv.close();
                    if (substr(v, 2) === "7.") {
                        targettype += "-v7"
                    }
                }
                break;
        }
    }
    else if (match(mfg, /[Tt][Pp]-[Ll]ink/)) {
        mfgprefix = "cpe";
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

export function supportsFeature(feature, arg1, arg2)
{
    switch (feature) {
        case "poe":
            return hasPOE();
        case "usb-power":
            return hasUSBPower();
        case "xlink":
            return supportsXLink();
        case "max-distance":
            return supportsMaxDistance(arg1);
        case "wifi-mode":
            return supportsMode(arg1, arg2);
        case "hw-watchdog":
            return fs.access("/dev/watchdog") ? true : false;
        case "videoproxy":
            switch (getBoardModel().id) {
                case "mikrotik,hap-ac3":
                case "openwrt,one":
                case "qemu":
                case "vmware":
                case "bhyve":
                case "pc":
                    return true;
                default:
                    return false;
            }
        default:
            return false;
    }
};
