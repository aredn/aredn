/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2026 Tim Wilkinson
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

const WAN_TABLE = 28;
const WAN_IFACE = "br-wan";

const c = uci.cursor();

const mesh_to_local_wan = c.get("aredn", "@wan[0]", "mesh_to_local_wan");
const addresses = [];
const mon1 = c.get("aredn", "@wan[0]", "monitor1");
const mon2 = c.get("aredn", "@wan[0]", "monitor2");
if (mon1) {
    push(addresses, mon1);
}
if (mon2) {
    push(addresses, mon2);
}
if (length(addresses) === 0 || mesh_to_local_wan != "1") {
    return exitApp();
}

let last_gw = null;

function isInternetReachable(iface, addrs)
{
    let success = false;
    for (let i = 0; !success && i < length(addrs); i++) {
        const p = fs.popen(`/bin/ping -c 1 -W 5 -I ${iface} ${addrs[i]}`);
        if (p) {
            for (let line = p.read("line"); length(line); line = p.read("line")) {
                const m = match(trim(line), /^64 bytes from /);
                if (m) {
                    success = true;
                }
            }
            p.close();
        }
    }
    return success;
}

function isInterfaceUp(iface)
{
    let valid = false;
    const p = fs.popen(`/sbin/ip -o -4 addr show dev ${iface}`);
    if (p) {
        valid = p.read("all") != "";
        p.close();
    }
    return valid;
}

function isGwFound(iface, table)
{
    let found = false;
    p = fs.popen(`/sbin/ip route show table ${table} 2>/dev/null`);
    if (p) {
        for (let line = p.read("line"); length(line); line = p.read("line")) {
            const m = match(trim(line), regexp(`default via ([0-9\.]+) dev ${iface}`));
            if (m) {
                found = true;
                last_gw = m[1];
            }
        }
        p.close();
    }
    return found;
}

function main()
{
    if (isInterfaceUp(WAN_IFACE)) {
        const reachable = isInternetReachable(WAN_IFACE, addresses);
        const found = isGwFound(WAN_IFACE, WAN_TABLE);
        if (last_gw) {
            if (reachable && !found) {
                system(`/sbin/ip route add default via ${last_gw} dev ${WAN_IFACE} table ${WAN_TABLE} > /dev/null 2>&1`);
                log.syslog(log.LOG_INFO, "WAN network reachable");
            }
            else if (!reachable && found) {
                system(`/sbin/ip route del default via ${last_gw} dev ${WAN_IFACE} table ${WAN_TABLE} > /dev/null 2>&1`);
                log.syslog(log.LOG_INFO, "WAN network unreachable");
            }
        }
    }

    return waitForTicks(60); // 1 minute
}

return waitForTicks(max(1, 120 - clock(true)[0]), main);
