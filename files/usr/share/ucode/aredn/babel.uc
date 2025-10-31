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

import * as fs from "fs";
import * as socket from "socket";

export const MANAGER = { path: "/var/run/babel.sock" };
export const LINK = { path: "/var/run/arednlink.sock" };
export const ROUTING_TABLE = 20;
export const ROUTING_TABLE_SUPERNODE = 21;
export const ROUTING_TABLE_DEFAULT = 22;

function reach2lq(r)
{
    r = hex(r);
    let count = 0;
    for (let i = 1; i < 0x10000; i = i << 1) {
        if (r & i) {
            count++;
        }
    }
    return int(0.5 + 100 * count / 16);
}

export function getInterfaces()
{
    const c = socket.connect(MANAGER);
    if (!c) {
        return null;
    }
    c.send("dump-interfaces\nquit\n");
    let d = "";
    for (;;) {
        const v = c.recv();
        if (!v || v === "") {
            break;
        }
        d += v;
    }
    c.close();
    d = split(d, "\n");
    // add interface br-dtdlink up true ipv6 fe80::5c:7dff:feb0:e28d ipv4 10.156.103.63
    const interfaces = /interface ([^ ]+) .+ ipv6 ([^ ]+) ipv4 ([^ ]+)/;
    const r = [];
    for (let i = 0; i < length(d); i++) {
        const m = match(d[i], interfaces);
        if (m) {
            push(r, {
                interface: m[1],
                ipv6address: m[2],
                ipv4address: m[3]
            });
        }
    }
    return r;
};

function getBabelData(cmd)
{
    const c = socket.connect(MANAGER);
    if (!c) {
        return null;
    }
    c.send(`${cmd}\nquit\n`);
    let d = "";
    for (;;) {
        const v = c.recv();
        if (!v || v === "") {
            break;
        }
        d += v;
    }
    c.close();
    return split(d, "\n");
}

function getXNeighbors(cmd)
{
    const d = getBabelData(cmd);
    // add neighbour 7ff812d8a020 address fe80::2f:d5ff:fec4:3ca3 if br-dtdlink reach ffff ureach 0000 rxcost 96 txcost 96 cost 96
    const neighbor = /address ([^ ]+) if ([^ ]+) reach ([^ ]+) .+ rxcost ([^ ]+) txcost ([^ ]+).* cost (.+)/;
    const n = [];
    for (let i = 0; i < length(d); i++) {
        const m = match(d[i], neighbor);
        if (m) {
            push(n, {
                interface: m[2],
                ipv6address: m[1],
                lq: reach2lq(m[3]),
                rxcost: int(m[4]),
                txcost: int(m[5]),
                cost: int(m[6])
            });
        }
    }
    return n;
}

export function getNeighbors()
{
    return getXNeighbors("dump-neighbors");
};

export function getRoutableNeighbors()
{
    return getXNeighbors("dump-routable-neighbors");
};

export function getInstalledRoutes(table)
{
    const d = getBabelData("dump-installed-routes");
    const route = /^add route .+ prefix ([^ /]+).+installed yes.+ metric ([^ ]+).+nexthop ([^ ]+) table ([0-9]+).+if (.+)$/;
    const r = [];
    for (let i = 0; i < length(d); i++) {
        const m = match(d[i], route);
        if (m && (m[4] == table || (table == ROUTING_TABLE && m[4] == 0)) && m[2] !== "65535" && index(m[1], ".") !== -1) {
            push(r, {
                dst: m[1],
                gateway: m[3],
                oif: m[5],
                metric: int(m[2]),
                table: table
            });
        }
    }
    return r;
};

export function getHostRoutes()
{
    return getInstalledRoutes(ROUTING_TABLE);
};

export function getSupernodeRoute()
{
    const all = getInstalledRoutes(ROUTING_TABLE_SUPERNODE);
    for (let i = 0; i < length(all); i++) {
        if (all[i].dst == "10.0.0.0/8") {
            return all[i];
        }
    }
    return null;
};

export function getDefaultRoute()
{
    const all = getInstalledRoutes(ROUTING_TABLE_DEFAULT);
    for (let i = 0; i < length(all); i++) {
        if (all[i].dst == "0.0.0.0/0") {
            return all[i];
        }
    }
    return null;
};

export function uploadNames(namefile)
{
    const c = socket.connect(LINK);
    if (!c) {
        return false;
    }
    c.send(`upload-names ${namefile}\nquit\n`);
    let d = "";
    for (;;) {
        const v = c.recv();
        if (!v || v === "") {
            break;
        }
        d += v;
    }
    c.close();
    return index(d, "ok") === -1 ? false : true;
};

export function uploadServices(servicefile)
{
    const c = socket.connect(LINK);
    if (!c) {
        return false;
    }
    c.send(`upload-services ${servicefile}\nquit\n`);
    let d = "";
    for (;;) {
        const v = c.recv();
        if (!v || v === "") {
            break;
        }
        d += v;
    }
    c.close();
    return index(d, "ok") === -1 ? false : true;
};
