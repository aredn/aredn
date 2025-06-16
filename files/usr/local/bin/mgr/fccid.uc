/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2022-2025 Tim Wilkinson
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

const c = uci.cursor();

if (c.get("aredn", "@beacon[0]", "enable") != "1") {
    return exitApp();
}
const name = configuration.getName();
if (!name) {
    return exitApp();
}
const radio = radios.getMeshRadio();
if (!radio) {
    return exitApp();
}

let id = `ID: ${name}`;
const lat = c.get("aredn", "@location[0]", "lat");
const lon = c.get("aredn", "@location[0]", "lon");
if (lat && lon) {
    id += ` LOCATION: ${lat},${lon}`;
}

const sock = socket.create(socket.AF_INET, socket.SOCK_DGRAM);
sock.setopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1);
sock.setopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, radio.iface);

return waitForTicks(0, () => {
    sock.send(id, 0, {
        address: "10.255.255.255",
        port: 4919
    });
    return waitForTicks(300);
});
