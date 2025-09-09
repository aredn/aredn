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
import * as babel from "aredn.babel";

const BAD_COST = 65535;
const MIN_LQ = 50;

function ping(n)
{
    let success = false;
    const p = fs.popen(`/bin/ping6 -c 1 -W 5 -I ${n.interface} ${n.ipv6address}`);
    if (p) {
        for (let line = p.read("line"); length(line); line = p.read("line")) {
            const m = match(trim(line), /^64 bytes from /);
            if (m) {
                success = true;
            }
        }
        p.close();
    }
    return success;
}

function main()
{
    // Look at our neighbors and if we find any which we are receiving hellos from but we are not
    // syncing with yet can successfully ping, reset babel.
    let reset = false;
    const neighbors = babel.getNeighbors();
    for (let i = 0; i < length(neighbors); i++) {
        const n = neighbors[i];
        if (n.cost === BAD_COST && n.lq >= MIN_LQ && ping(n)) {
            reset = true;
            break;
        }
    }

    if (reset) {
        log.syslog(log.LOG_ERR, "Hard restarting babel to reset sequence number");
        system("/usr/local/bin/restart-services --force --ignore-reboot babel-hard > /dev/null 2>&1", 20000);
        return waitForTicks(60 * 60); // 1 hour
    }
    else {
        return waitForTicks(60); // 1 minute
    }
}

return waitForTicks(max(1, 120 - clock(true)[0]), main);
