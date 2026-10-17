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

// Board-data validation and bounded recovery. AI-assisted AREDN contribution.
import * as fs from "fs";

const MAX_SIZE = 1024 * 1024;

export function validate(data)
{
    if (type(data) !== "object" || type(data.model) !== "object" ||
        type(data.model.id) !== "string" || !length(trim(data.model.id)) ||
        type(data.model.name) !== "string" || !length(trim(data.model.name))) {
        return "Board identity is missing or invalid";
    }
    for (let key in [ "network", "wlan" ]) {
        if (data[key] !== null && type(data[key]) !== "object") {
            return "Board network or radio metadata is invalid";
        }
        for (let name in data[key] || {}) {
            if (type(data[key][name]) !== "object") {
                return "Board network or radio entry is invalid";
            }
        }
    }
    return null;
};

export function read(path)
{
    path = path || "/etc/board.json";
    const stat = fs.stat(path);
    if (!stat || stat.type !== "file") {
        return { error: "Board metadata is missing or unreadable" };
    }
    if (!stat.size || stat.size > MAX_SIZE) {
        return { error: "Board metadata has an invalid size" };
    }
    const text = fs.readfile(path);
    if (text === null) {
        return { error: "Board metadata could not be read" };
    }
    let data;
    try {
        data = json(text);
    }
    catch (_) {
        return { error: "Board metadata is not valid JSON" };
    }
    const error = validate(data);
    return error ? { error: error } : { data: data };
};

// All read-modify-write users must hold this lock until write() completes.
export function acquire(path, lockfile)
{
    path = path || "/etc/board.json";
    lockfile = lockfile || (path === "/etc/board.json" ? "/var/lock/aredn-board-data.lock" : `${path}.lock`);
    fs.mkdir(fs.dirname(lockfile), 0755);
    const handle = fs.open(lockfile, "we", 0600);
    if (!handle) {
        return null;
    }
    if (!handle.lock("xn")) {
        handle.close();
        return null;
    }
    return handle;
};

// Caller holds acquire(path). Never open the destination for truncation.
export function write(path, data)
{
    const error = validate(data);
    if (error) {
        return { status: "failed", installed: false, error: error };
    }
    const text = sprintf("%.J\n", data);
    const current = read(path);
    if (!current.error && sprintf("%.J\n", current.data) === text) {
        return { status: "unchanged", installed: false };
    }
    let directory;
    let file;
    let parent;
    let installed = false;
    let result;
    try {
        directory = fs.mkdtemp(`${fs.dirname(path)}/.board-write-XXXXXX`);
        if (!directory) {
            die("Could not create board-data staging directory");
        }
        const candidate = `${directory}/board.json`;
        file = fs.open(candidate, "wxe", 0644);
        if (!file) {
            die("Could not create board-data candidate");
        }
        const written = file.write(text);
        const synced = written === length(text) && file.sync();
        const closed = file.close();
        file = null;
        if (written !== length(text) || !synced || !closed) {
            die("Could not write and synchronize board-data candidate");
        }
        const checked = read(candidate);
        if (checked.error || sprintf("%.J\n", checked.data) !== text) {
            die("Board-data candidate failed readback validation");
        }
        if (!fs.rename(candidate, path)) {
            die("Could not replace board metadata");
        }
        installed = true;
        if (fs.rmdir(directory)) {
            directory = null;
        }
        parent = fs.opendir(fs.dirname(path));
        if (!parent) {
            die("Board data installed but parent directory could not be opened");
        }
        const durable = parent.sync();
        const closedParent = parent.close();
        parent = null;
        if (!durable || !closedParent) {
            die("Board data installed but directory synchronization failed");
        }
        result = { status: "written", installed: true };
    }
    catch (e) {
        result = { status: "failed", installed: installed, error: e.message };
    }
    if (file) { file.close(); }
    if (parent) { parent.close(); }
    if (directory) {
        fs.unlink(`${directory}/board.json`);
        fs.rmdir(directory);
    }
    return result;
};

// No network/UCI changes, service restarts, or recovery from a different device.
// Options let isolated tests use temporary files and a synthetic detector.
export function recover(options)
{
    options = options || {};
    const path = options.path || "/etc/board.json";
    if (!read(path).error) {
        return { status: "healthy" };
    }
    const identity = options.identity || trim(fs.readfile("/tmp/sysinfo/board_name") || "");
    if (!identity) {
        return { status: "failed", error: "Current board identity is unavailable" };
    }
    const lock = acquire(path, options.lockfile);
    if (!lock) {
        return { status: "failed", error: "Could not acquire board-data update lock" };
    }
    let directory;
    let result;
    try {
        if (!read(path).error) {
            result = { status: "healthy" };
        }
        else {
            const stat = fs.stat(path);
            if (stat) {
                if (stat.type !== "file" || stat.size > MAX_SIZE) {
                    die("Refusing to replace an unexpected board-data file");
                }
                const contents = fs.readfile(path);
                const evidence = fs.open(options.evidence || "/tmp/aredn-board-data-invalid.json", "we", 0600);
                if (contents === null || !evidence) {
                    die("Could not preserve invalid board metadata");
                }
                const written = evidence.write(contents);
                const closed = evidence.close();
                if (written !== length(contents) || !closed) {
                    die("Could not preserve invalid board metadata");
                }
            }
            directory = fs.mkdtemp(`${fs.dirname(path)}/.board-recovery-XXXXXX`);
            if (!directory) {
                die("Could not create board-data recovery directory");
            }
            const candidate = `${directory}/board.json`;
            const detected = options.detect ? options.detect(candidate) :
                system([ "/bin/board_detect", candidate ], 10000) === 0;
            if (!detected) {
                die("Board detection failed or timed out");
            }
            const generated = read(candidate);
            if (generated.error || generated.data.model.id !== identity) {
                die("Generated board metadata is invalid or belongs to a different board");
            }
            const committed = options.commit ? options.commit(path, generated.data) : write(path, generated.data);
            if (committed.status === "failed") {
                die(committed.error);
            }
            result = { status: "recovered" };
        }
    }
    catch (e) {
        result = { status: "failed", error: e.message };
    }
    if (directory) {
        fs.unlink(`${directory}/board.json`);
        fs.unlink(`${directory}/.board.json.tmp`);
        fs.unlink(`${directory}/board.json.lock`);
        fs.rmdir(directory);
    }
    lock.close();
    return result;
};
