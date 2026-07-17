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

function runScripts(scripts)
{
    const dir = fs.opendir(scripts);
    if (dir) {
        for (;;) {
            const entry = dir.read();
            if (!entry) {
                break;
            }
            if (match(entry, /^[a-zA-Z0-9_\.\-]+$/)) {
                const path = `${scripts}/${entry}`;
                const stat = fs.stat(path);
                if (stat.type === "file" && (stat.perm.user_exec || stat.perm.group_exec || stat.perm.other_exec)) {
                    system(`(cd /tmp; ${path} 2>&1 | logger -p daemon.debug -t ${entry})&`);
                }
            }
        }
        dir.close();
    }
}

let hours = 0;
let days = 0;

function main()
{
    const start = time();
    hours--;
    if (hours <= 0) {
        days--;
        if (days <= 0) {
            runScripts("/etc/cron.weekly");
            days = 7;
        }
        runScripts("/etc/cron.daily");
        hours = 24;
    }
    runScripts("/etc/cron.hourly");

    // Allowing for possible clock changes and time taken to run tasks, wait for no more than an hour
    return waitForTicks(min(3600, max(0, 3600 - (time() - start))))
}

runScripts("/etc/cron.boot");
return waitForTicks(120, main); // Initial wait before starting up period tasks
