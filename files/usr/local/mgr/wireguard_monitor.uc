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

const IDLE_LIMIT = 150; // seconds without a handshake before we re-resolve

let active = false;
uci.cursor().foreach("network", "interface", i => {
    if (index(i[".name"], "wgs") !== 0 || i.disabled !== "0") {
        active = true;
    }
});
if (!active) {
    return exitApp();
}

return function()
{
    const now = time();

    const cursor = uci.cursor();
    cursor.foreach("network", "interface", i => {
        const iface = i[".name"];
        if (index(iface, "wgs") !== 0 || i.disabled !== "0") {
            return;
        }

        // One peer per wgs interface, in a section typed wireguard_<iface>
        const peer = cursor.get_all("network", `wireguard_${iface}`);

        // Only peers with an endpoint and keepalive
        if (!peer?.public_key || !peer.endpoint_host || !peer.endpoint_port || !peer.persistent_keepalive) {
            return;
        }

        const p = fs.popen(`/usr/bin/wg show ${iface} latest-handshakes`);
        if (!p) {
            return;
        }
        const f = split(trim(p.read("line")), "\t");
        p.close();

        const idle = now - int(f[1]);
        if (idle < IDLE_LIMIT) {
            return;
        }
        const endpoint = `${peer.endpoint_host}:${peer.endpoint_port}`;
        log.syslog(log.LOG_INFO, `${iface} endpoint ${endpoint} is not responding for ${idle} seconds, resetting`);
        system([ "/usr/bin/wg", "set", iface, "listen-port", "0", "peer", peer.public_key, "endpoint", endpoint ]);
    });

    return waitForTicks(60); // wait 1 minute
};
