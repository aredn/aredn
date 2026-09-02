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

let last_hosts = null;
let last_services = null;

function main()
{
    const cm = uci.cursor("/etc/config.mesh");
    const ip = cm.get("setup", "globals", "wifi_ip");
    const info = services.get(true);
    let update = false;
    let hosts = "";

    for (let i = 0; i < length(info.names); i++) {
        hosts += `${ip}\t${info.names[i]}\n`;
    }
    for (let i = 0; i < length(info.hosts); i++) {
        const host = info.hosts[i];
        if (host.prop) {
            hosts += `${host.ip}\t${host.host}\n`;
        }
    }
    // Update the hosts if they changed
    if (hosts != last_hosts) {
        last_hosts = hosts;
        update = true;
        fs.writefile("/etc/arednlink/hosts", hosts);
    }
    // Update the services if they changed
    const services = length(info.services) == 0 ? "" : `${join("\n", info.services)}\n`;
    if (services != last_services) {
        last_services = services;
        update = true;
        fs.writefile("/etc/arednlink/services", services);
    }
    if (update) {
        system("/usr/local/bin/arednlink-update");
    }

    return waitForTicks(300); // 5 minutes
}

services.resetValidation();

return waitForTicks(max(1, 120 - clock(true)[0]), main);
