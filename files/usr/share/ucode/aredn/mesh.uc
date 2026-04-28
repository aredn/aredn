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

const reTitle = /^##(.+)##/;
const reHosts = /^([0-9\.]+)[ \t]+([^ \.]+)$/;

export function getNodeList()
{
    const nodes = [];
    const hash = {};
    const d = fs.opendir("/var/run/arednlink/hosts");
    if (d) {
        for (let name = d.read(); name; name = d.read()) {
            if (name == "." || name == "..") {
                continue;
            }
            const f = fs.open(`/var/run/arednlink/hosts/${name}`);
            if (f) {
                let ip = null;
                for (let line = f.read("line"); length(line); line = f.read("line")) {
                    line = trim(line);
                    let m = match(line, reTitle);
                    if (m) {
                        ip = m[1];
                    }
                    else {
                        m = match(line, reHosts);
                        if (m && m[1] == ip) {
                            const n = m[2];
                            const ln = lc(n);
                            push(nodes, ln);
                            hash[ln] = n;
                        }
                    }
                }
                f.close();
            }
        }
        d.close();
    }
    sort(nodes);
    return map(nodes, n => hash[n]);
};

export function getNodeCounts()
{
    let bnodes = 0;
    let bdevices = 0;
    let bservices = 0;
    let d = fs.opendir("/var/run/arednlink/hosts");
    if (d) {
        const reD = /\t[^\.]+$/;
        const reS = /^[a-z]/;
        for (let entry = d.read(); entry; entry = d.read()) {
            if (entry !== "." && entry !== "..") {
                let f = fs.open(`/var/run/arednlink/hosts/${entry}`);
                if (f) {
                    for (let l = f.read("line"); l; l = f.read("line")) {
                        if (match(l, reTitle)) {
                            bnodes++;
                        }
                        else if (match(l, reD)) {
                            bdevices++;
                        }
                    }
                    f.close();
                }
                f = fs.open(`/var/run/arednlink/services/${entry}`);
                if (f) {
                    for (let l = f.read("line"); l; l = f.read("line")) {
                        if (match(l, reS)) {
                            bservices++;
                        }
                    }
                    f.close();
                }
            }
        }
        d.close();
    }
    return {
        babel: {
            nodes: bnodes,
            devices: bdevices,
            services: bservices
        }
    };
};
