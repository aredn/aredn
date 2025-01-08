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

export function getLinks()
{
    const f = fs.popen("exec /bin/uclient-fetch http://127.0.0.1:9090/links -O - 2> /dev/null");
    try {
        const links = json(f.read("all")).links;
        f.close();
        return links;
    }
    catch (_) {
        f.close();
        return [];
    }
};

export function getRoutes()
{
    const f = fs.popen("exec /bin/uclient-fetch http://127.0.0.1:9090/routes -O - 2> /dev/null");
    try {
        const routes = json(f.read("all")).routes;
        f.close();
        return routes;
    }
    catch (_) {
        f.close();
        return [];
    }
};

export function getHNAs()
{
    const f = fs.popen("exec /bin/uclient-fetch http://127.0.0.1:9090/hna -O - 2> /dev/null");
    try {
        const hna = json(f.read("all")).hna;
        f.close();
        return hna;
    }
    catch (_) {
        f.close();
        return [];
    }
};

export function getMids()
{
    const f = fs.popen("exec /bin/uclient-fetch http://127.0.0.1:9090/mid -O - 2> /dev/null");
    try {
        const mid = json(f.read("all")).mid;
        f.close();
        return mid;
    }
    catch (_) {
        f.close();
        return [];
    }
};
