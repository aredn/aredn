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

export function getNodeList()
{
    const re = /^10.+\tdtdlink\.(.+)\.local\.mesh\t#.+$/;
    const nodes = [];
    const f = fs.open("/var/run/hosts_olsr");
    if (!f) {
        return nodes;
    }
    const hash = {};
    for (let l = f.read("line"); length(l); l = f.read("line")) {
        const m = match(l, re);
        if (m) {
            const n = m[1];
            const ln = lc(n);
            push(nodes, ln);
            hash[ln] = n;
        }
    }
    f.close();
    sort(nodes);
    return map(nodes, n => hash[n]);
};

export function getNodeCounts()
{
    let onodes = 0;
    let odevices = 0;
    let oservices = 0;
    let f = fs.open("/var/run/hosts_olsr");
    if (f) {
        const re = /\t(lan|mid\d+|xlink\d+)\./;
        for (let l = f.read("line"); length(l); l = f.read("line")) {
            if (substr(l, 0, 3) == "10.") {
                if (index(l, "\tdtdlink.") !== -1) {
                    onodes++;
                }
                else if (!match(l, re)) {
                    odevices++;
                }
            }
        }
        f.close();
    }
    f = fs.open("/var/run/services_olsr");
    if (f) {
        for (let l = f.read("line"); length(l); l = f.read("line")) {
            const c = substr(l, 0, 1);
            if (c !== "#" && c !== "\n") {
                oservices++;
            }
        }
        f.close();
    }
    let bnodes = 0;
    let bdevices = 0;
    let bservices = 0;
    let d = fs.opendir("/var/run/arednlink/hosts");
    if (d) {
        for (let entry = d.read(); entry; entry = d.read()) {
            if (entry !== "." && entry !== "..") {
                bnodes++;
                let f = fs.open(`/var/run/arednlink/hosts/${entry}`);
                if (f) {
                    const re = /\t[^\.]+$/;
                    for (let l = f.read("line"); l; l = f.read("line")) {
                        if (match(l, re)) {
                            bdevices++;
                        }
                    }
                    f.close();
                }
                f = fs.open(`/var/run/arednlink/services/${entry}`);
                if (f) {
                    while(f.read("line")) {
                        bservices++;
                    }
                    f.close();
                }
            }
        }
        d.close();
    }
    return {
        olsr: {
            nodes: onodes,
            devices: odevices,
            services: oservices
        },
        babel: {
            nodes: bnodes,
            devices: bdevices,
            services: bservices
        }
    };
};
