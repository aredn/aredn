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
import * as configuration from "aredn.configuration";
import * as hardware from "aredn.hardware";
import * as radios from "aredn.radios";

function parseMessages(nodename, msgs, text)
{
    if (text) {
        const t = split(text, "<strong>");
        for (let i = 0; i < length(t); i++) {
            const m = match(t[i], /&#8611; (.+):<\/strong>(.+)<p>/);
            if (m) {
                const label = m[1] !== nodename ? m[1] : "yournode";
                if (!msgs[label]) {
                    msgs[label] = [];
                }
                push(msgs[label], trim(m[2]));
            }
        }
    }
}

export function getMessages()
{
    const nodename = lc(configuration.getName());
    const msgs = {};
    if (fs.access("/etc/cron.boot/reinstall-packages") && fs.access("/etc/package_store/catalog.json")) {
        msgs.system = [ "Packages are being reinstalled in the background. This can take a few minutes." ];
    }
    parseMessages(nodename, msgs, fs.readfile("/tmp/aredn_message"));
    parseMessages(nodename, msgs, fs.readfile("/tmp/local_message"));
    const d = fs.opendir("/tmp/other_messages/");
    if (d) {
        for (let entry = d.read(); entry; entry = d.read()) {
            if (entry !== "." && entry !== "..") {
                parseMessages(nodename, msgs, fs.readfile(`/tmp/other_messages/${entry}`));
            }
        }
        d.close();
    }
    return msgs;
};

export function getToDos()
{
    const cursor = uci.cursor();
    const todos = [];
    if (hardware.isLowMemNode()) {
        push(todos, "AREDN® is migrating to a new routing protocol called Babel. Unfortunately this node is too old to support this. We recommend you upgrade the hardware in the near future.");
    }
    else {
        let legacy = false;
        const cursor = uci.cursor("/etc/config.mesh");
        if (cursor.get("vtun", "@client[0]")) {
            legacy = true;
        }
        else {
            cursor.foreach("vtun", "server", s => {
                if (index(s.netip, ":") === -1) {
                    legacy = true;
                }
            });
        }
        if (legacy) {
            push(todos, "AREDN® is migrating to a new routing protocol called Babel. Unfortuntely this protocol cannot support old legacy tunnels. We recommend migrating these tunnels to Wireguard.");
        }
    }
    if (!cursor.get("aredn", "@location[0]", "lat") || !cursor.get("aredn", "@location[0]", "lon")) {
        push(todos, "Set the latitude and longitude");
    }
    if (configuration.getSettingAsString("time_zone_name", "Not Set") === "Not Set") {
        push(todos, "Set the timzeone");
    }
    if (hardware.getRadioCount() > 0) {
        const wlan = cursor.get("network", "wifi", "device");
        const ants = hardware.getAntennas(wlan);
        const ant = cursor.get("aredn", "@location[0]", "antenna");
        if (length(ants) > 1 && !ant) {
            push(todos, "Select an antenna");
        }
        else if (ant || length(ants) === 1) {
            if (!cursor.get("aredn", "@location[0]", "azimuth")) {
                const ainfo = hardware.getAntennaInfo(wlan, ant || ants[0]);
                if (ainfo?.beamwidth !== 360) {
                    push(todos, "Set antenna azimuth");
                }
            }
        }
    }
    return todos;
};
