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
import * as resolv from "resolv";

export function hasInternet()
{
    const p = fs.popen("exec /bin/ping -W1 -c1 8.8.8.8");
    if (p) {
        const d = p.read("all");
        p.close();
        if (index(d, "1 packets received") !== -1) {
            return true;
        }
    }
    return false;
};

export function getIPAddressFromHostname(hostname)
{
    const p = fs.popen(`exec /usr/bin/nslookup ${hostname}`);
    if (p) {
        const d = p.read("all");
        p.close();
        const i = match(d, /Address: ([0-9.]+)/);
        if (i) {
            return i[1];
        }
    }
    return null;
};

export function netmaskToCIDR(mask)
{
    const m = iptoarr(mask);
    let cidr = 32;
    for (let i = 3; i >= 0; i--) {
        switch (m[i]) {
            default:
            case 255:
                return cidr - 0;
            case 254:
                return cidr - 1;
            case 252:
                return cidr - 2;
            case 248:
                return cidr - 3;
            case 240:
                return cidr - 4;
            case 224:
                return cidr - 5;
            case 192:
                return cidr - 6;
            case 128:
                return cidr - 7;
            case 0:
                cidr -= 8;
                break;
        }
    }
    return 0;
};

export function CIDRToNetmask(cidr)
{
    const v = (0xFF00 >> (cidr % 8)) & 0xFF;
    switch (int(cidr / 8)) {
        case 0:
            return `${v}.0.0.0`;
        case 1:
            return `255.${v}.0.0`;
        case 2:
            return `255.255.${v}.0`;
        case 3:
            return `255.255.255.${v}`;
        default:
            return "255.255.255.255";
    }
};

export function nslookup(aorh)
{
    const r = resolv.query([aorh]);
    if (r) {
        for (let k in r) {
            const v = r[k];
            if (v.PTR) {
                return v.PTR[0];
            }
            if (v.A) {
                return v.A[0];
            }
        }
    }
    return null;
};
