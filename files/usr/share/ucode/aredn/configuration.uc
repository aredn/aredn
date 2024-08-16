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

import * as fs from "fs";
import * as uci from "uci";
import * as math from "math";
import * as network from "aredn.network";

let cursor;
let setup;
let setupKeys;
let setupChanged = false;
let firmwareVersion = null;

const currentConfig = "/tmp/config.current";
const modalConfig = "/tmp/config.modal";
const configDirs = [
    "/etc",
    "/etc/config.mesh",
    "/etc/local",
    "/etc/local/uci",
    "/etc/aredn_include",
    "/etc/dropbear",
    "/tmp"
];
const configFiles = [
    "/etc/config.mesh/_setup",
    "/etc/config.mesh/_setup.dhcp.dmz",
    "/etc/config.mesh/_setup.dhcp.nat",
    "/etc/config.mesh/_setup.dhcpoptions.dmz",
    "/etc/config.mesh/_setup.dhcpoptions.nat",
    "/etc/config.mesh/_setup.dhcptags.dmz",
    "/etc/config.mesh/_setup.dhcptags.nat",
    "/etc/config.mesh/_setup.ports.dmz",
    "/etc/config.mesh/_setup.ports.nat",
    "/etc/config.mesh/_setup.services.dmz",
    "/etc/config.mesh/_setup.services.nat",
    "/etc/config.mesh/aliases.dmz",
    "/etc/config.mesh/aliases.nat",
    "/etc/config.mesh/aredn",
    "/etc/config.mesh/dhcp",
    "/etc/config.mesh/dropbear",
    "/etc/config.mesh/firewall",
    "/etc/config.mesh/firewall.user",
    "/etc/config.mesh/network",
    "/etc/config.mesh/olsrd",
    "/etc/config.mesh/snmpd",
    "/etc/config.mesh/system",
    "/etc/config.mesh/uhttpd",
    "/etc/config.mesh/vtun",
    "/etc/config.mesh/wireguard",
    "/etc/config.mesh/xlink",
    "/etc/local/uci/hsmmmesh",
    "/etc/aredn_include/dtdlink.network.user",
    "/etc/aredn_include/lan.network.user",
    "/etc/aredn_include/wan.network.user",
    "/etc/dropbear/authorized_keys",
    "/tmp/newpassword"
];

function initCursor()
{
    if (!cursor) {
        cursor = uci.cursor("/etc/local/uci");
    }
};

function initSetup()
{
    if (!setup) {
        setup = {};
        setupKeys = [];
        const f = fs.open("/etc/config.mesh/_setup");
        if (f) {
            for (;;) {
                const line = f.read("line");
                if (!length(line)) {
                    break;
                }
                const kv = split(line, " =");
                if (length(kv) === 2) {
                    setup[kv[0]] = trim(kv[1]);
                    push(setupKeys, kv[0]);
                }
            }
            f.close();
        }
    }
};

export function reset()
{
    setup = null;
    cursor = null;
};

export function getSettingAsString(key, def)
{
    initSetup();
    return setup[key] || def;
};

export function getSettingAsInt(key, def)
{
    initSetup();
    const v = int(setup[key]);
    if (type(v) === "int") {
        return v;
    }
    return def;
};

export function setSetting(key, value, def)
{
    initSetup();
    const old = setup[key];
    setup[key] = `${value || def || ""}`;
    if (old !== setup[key]) {
        setupChanged = true;
        return true;
    }
    return false;
};

export function saveSettings()
{
    if (setupChanged) {
        const f = fs.open("/etc/config.mesh/_setup", "w");
        if (f) {
            for (let i = 0; i < length(setupKeys); i++) {
                const k = setupKeys[i];
                f.write(`${k} = ${setup[k] || ""}\n`);
            }
            f.close();
            setupChanged = false;
        }
    }
};

export function getName()
{
    initCursor();
    return cursor.get("hsmmmesh", "settings", "node");
};

export function setName(name)
{
    initCursor();
    cursor.set("hsmmmesh", "settings", "node", name);
    cursor.commit("hsmmmesh");
};

export function getFirmwareVersion()
{
    if (firmwareVersion === null) {
        firmwareVersion = trim(fs.readfile("/etc/mesh-release"));
    }
    return firmwareVersion;
};

export function setUpgrade(v)
{
    initCursor();
    cursor.set("hsmmmesh", "settings", "nodeupgraded", v);
    cursor.commit("hsmmmesh");
};

export function setPassword(passwd)
{
    fs.writefile("/tmp/newpassword", passwd);
};

export function isPasswordChanged()
{
    return fs.access("/tmp/newpassword") ? true : false;
};

export function getDHCP(mode)
{
    initSetup();
    if (mode === "nat" || (!mode && setup.dmz_mode === "0")) {
        const root = replace(setup.lan_ip, /\d+$/, "");
        return {
            enabled: setup.lan_dhcp ? true : false,
            mode: 0,
            start: `${root}${setup.dhcp_start}`,
            end: `${root}${setup.dhcp_end}`,
            gateway: setup.lan_ip,
            mask: setup.lan_mask,
            cidr: network.netmaskToCIDR(setup.lan_mask),
            leases: "/tmp/dhcp.leases",
            reservations: "/etc/config.mesh/_setup.dhcp.nat",
            services: "/etc/config.mesh/_setup.services.nat",
            ports: "/etc/config.mesh/_setup.ports.nat",
            dhcptags: "/etc/config.mesh/_setup.dhcptags.nat",
            dhcpoptions: "/etc/config.mesh/_setup.dhcpoptions.nat",
            aliases: "/etc/config.mesh/aliases.nat"
        };
    }
    else if (setup.dmz_mode === "1") {
        const root = replace(setup.lan_ip, /\d+$/, "");
        return {
            enabled: setup.lan_dhcp ? true : false,
            mode: 1,
            start: `${root}${setup.dhcp_start}`,
            end: `${root}${setup.dhcp_end}`,
            gateway: setup.lan_ip,
            mask: setup.lan_mask,
            cidr: network.netmaskToCIDR(setup.lan_mask),
            leases: "/tmp/dhcp.leases",
            reservations: "/etc/config.mesh/_setup.dhcp.dmz",
            services: "/etc/config.mesh/_setup.services.dmz",
            ports: "/etc/config.mesh/_setup.ports.dmz",
            dhcptags: "/etc/config.mesh/_setup.dhcptags.dmz",
            dhcpoptions: "/etc/config.mesh/_setup.dhcpoptions.dmz",
            aliases: "/etc/config.mesh/aliases.dmz"
        };
    }
    else {
        const root = replace(setup.dmz_lan_ip, /\d+$/, "");
        return {
            enabled: setup.lan_dhcp ? true : false,
            mode: int(setup.dmz_mode),
            start: `${root}${setup.dmz_dhcp_start}`,
            end: `${root}${setup.dmz_dhcp_end}`,
            gateway: setup.dmz_lan_ip,
            mask: setup.dmz_lan_mask,
            cidr: network.netmaskToCIDR(setup.dmz_lan_mask),
            leases: "/tmp/dhcp.leases",
            reservations: "/etc/config.mesh/_setup.dhcp.dmz",
            services: "/etc/config.mesh/_setup.services.dmz",
            ports: "/etc/config.mesh/_setup.ports.dmz",
            dhcptags: "/etc/config.mesh/_setup.dhcptags.dmz",
            dhcpoptions: "/etc/config.mesh/_setup.dhcpoptions.dmz",
            aliases: "/etc/config.mesh/aliases.dmz"
        };
    }
};

function copyConfig(configRoot)
{
    fs.mkdir(configRoot);
    for (let i = 0; i < length(configDirs); i++) {
        fs.mkdir(`${configRoot}${configDirs[i]}`);
    }
    for (let i = 0; i < length(configFiles); i++) {
        const entry = configFiles[i];
        if (fs.access(entry)) {
            fs.writefile(`${configRoot}${entry}`, fs.readfile(entry));
        }
    }
};

function removeConfig(configRoot)
{
    for (let i = 0; i < length(configFiles); i++) {
        fs.unlink(`${configRoot}${configFiles[i]}`);
    }
    for (let i = length(configDirs) - 1; i >= 0; i--) {
        fs.rmdir(`${configRoot}${configDirs[i]}`);
    }
    fs.rmdir(configRoot);
};

function revertConfig(configRoot)
{
    if (fs.access(`${configRoot}/etc/config.mesh/_setup`)) {
        for (let i = 0; i < length(configFiles); i++) {
            const to = configFiles[i];
            const from = `${configRoot}${to}`;
            if (fs.access(from)) {
                fs.writefile(to, fs.readfile(from));
                fs.unlink(from);
            }
            else {
                fs.unlink(to);
            }
        }
        for (let i = length(configDirs) - 1; i >= 0; i--) {
            fs.rmdir(`${configRoot}${configDirs[i]}`);
        }
        fs.rmdir(currentConfig);
    }
};

export function prepareChanges()
{
    if (!fs.access(`${currentConfig}/etc/config.mesh/_setup`)) {
        copyConfig(currentConfig);
    }
};

export function prepareModalChanges()
{
    if (fs.access(`${modalConfig}/etc/config.mesh/_setup`)) {
        removeConfig(modalConfig);
    }
    copyConfig(modalConfig);
};

function fileChanges(from, to)
{
    let count = 0;
    const p = fs.popen(`exec /usr/bin/diff -NBbdiU0 ${from} ${to}`);
    if (p) {
        for (;;) {
            const l = rtrim(p.read("line"));
            if (!l) {
                break;
            }
            if (index(l, "@@") === 0) {
                const v = match(l, /^@@ [+-]\d+,?(\d*) [+-]\d+,?(\d*) @@$/);
                if (v) {
                    count += max(math.abs(int(v[1] === "" ? 1 : v[1])), math.abs(int(v[2] === "" ? 1 : v[2])));
                }
            }
        }
        p.close();
    }
    return count;
};

export function commitChanges()
{
    const status = {};
    if (fs.access(`${currentConfig}/etc/config.mesh/_setup`)) {
        if (fileChanges(`${currentConfig}/etc/local/uci/hsmmmesh`, "/etc/local/uci/hsmmmesh") > 0) {
            fs.mkdir("/tmp/reboot-required");
            fs.writefile("/tmp/reboot-required/reboot", "");
        }
        removeConfig(modalConfig);
        removeConfig(currentConfig);
        if (fs.access("/tmp/newpassword")) {
            const pw = fs.readfile("/tmp/newpassword");
            system(`{ echo '${pw}'; sleep 1; echo '${pw}'; } | passwd > /dev/null 2>&1`);
            fs.unlink("/tmp/newpassword");
        }
        const n = fs.popen("exec /usr/local/bin/node-setup");
        if (n) {
            status.setup = n.read("all");
            n.close();
            const c = fs.popen("exec /usr/local/bin/restart-services.sh");
            if (c) {
                status.restart = c.read("all");
                c.close();
            }
        }
    }
    return status;
};

export function revertChanges()
{
    revertConfig(currentConfig);
};

export function revertModalChanges()
{
    revertConfig(modalConfig);
};

export function countChanges()
{
    let count = 0;
    if (fs.access(`${currentConfig}/etc/config.mesh/_setup`)) {
        for (let i = 0; i < length(configFiles); i++) {
            count += fileChanges(`${currentConfig}${configFiles[i]}`, configFiles[i]);
        }
    }
    return count;
};
