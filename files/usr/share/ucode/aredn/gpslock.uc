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

// GPS lock badge support, added by mathisono (2026).
import * as fs from "fs";
import * as socket from "socket";

const STATUS = "/tmp/gps-lock.json";
const POLL_SECONDS = 30;

// These states describe receiver lock, not PPS accuracy or clock discipline.
function classify(tpv)
{
    if (type(tpv) !== "object" || tpv.class !== "TPV") {
        return { state: "error", reason: "Invalid GPS receiver data" };
    }
    if ((tpv.mode !== 2 && tpv.mode !== 3) || tpv.status === 0 ||
        tpv.status === 5 || tpv.status === 8) {
        return { state: "pending", reason: "Waiting for GPS satellite lock" };
    }
    if (type(tpv.time) !== "string" || !match(tpv.time, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)) {
        return { state: "pending", reason: "Waiting for GPS time" };
    }
    return { state: "locked", reason: tpv.mode === 3 ? "GPS locked (3D fix)" : "GPS locked (2D fix)" };
};

function read(gps)
{
    if (!gps) {
        return { state: "error", reason: "GPS source not found" };
    }
    const host = match(gps, /^\/dev\//) ? "127.0.0.1" : gps;
    const s = socket.connect(host, 2947, null, 500);
    if (!s) {
        return { state: "error", reason: "GPS receiver connection failed" };
    }
    let result = { state: "error", reason: "GPS receiver did not provide current data" };
    try {
        s.setopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, { tv_sec: 1, tv_usec: 0 });
        const command = '?WATCH={"enable":true,"json":true}\n';
        if (s.send(command) !== length(command)) {
            result = { state: "error", reason: "GPS receiver request failed" };
        }
        else {
            // Bound both total time and data. Do not block the manager waiting
            // indefinitely for a silent, disconnected or malformed receiver.
            const started = clock(true);
            let buffer = "";
            let total = 0;
            while (total < 65536) {
                const now = clock(true);
                const elapsed = (now[0] - started[0]) * 1000 + (now[1] - started[1]) / 1000000;
                const remaining = int(1500 - elapsed);
                if (remaining <= 0) break;
                const ready = socket.poll(remaining, [ s, socket.POLLIN | socket.POLLERR | socket.POLLHUP ]);
                if (!length(ready)) break;
                const chunk = s.recv(4096, socket.MSG_DONTWAIT);
                if (!chunk) break;
                total += length(chunk);
                buffer += chunk;
                const lines = split(buffer, "\n");
                buffer = pop(lines);
                let done = false;
                for (let line in lines) {
                    if (!length(trim(line))) continue;
                    const j = json(line);
                    if (j.class === "ERROR") {
                        result = { state: "error", reason: "GPS receiver reported an error" };
                        done = true;
                        break;
                    }
                    if (j.class === "DEVICES" && type(j.devices) === "array" && !length(j.devices)) {
                        result = { state: "error", reason: "GPS receiver has no device" };
                        done = true;
                        break;
                    }
                    if (j.class === "TPV") {
                        result = classify(j);
                        done = true;
                        break;
                    }
                }
                if (done) break;
            }
        }
    }
    catch (e) {
        result = { state: "error", reason: "Invalid GPS receiver response" };
    }
    s.close();
    return result;
};

function write(status)
{
    status.checked_uptime = clock(true)[0];
    fs.writefile(STATUS + ".new", sprintf("%J", status));
    fs.rename(STATUS + ".new", STATUS);
};

function validate(status, now)
{
    if (type(status) !== "object" || type(status.checked_uptime) !== "int" ||
        type(status.reason) !== "string" ||
        (status.state !== "locked" && status.state !== "pending" && status.state !== "error")) {
        return { state: "error", reason: "Invalid GPS status" };
    }
    if (now - status.checked_uptime > 3 * POLL_SECONDS || status.checked_uptime > now) {
        return { state: "error", reason: "GPS status is stale" };
    }
    return status;
};

function current()
{
    const text = fs.readfile(STATUS);
    if (text === null) {
        return { state: "pending", reason: "Waiting for GPS status" };
    }
    try {
        return validate(json(text), clock(true)[0]);
    }
    catch (e) {
        return { state: "error", reason: "Invalid GPS status" };
    }
};

// Dynamic task/template loading uses require(), whose script result is the API.
return { POLL_SECONDS, classify, read, write, validate, current };
