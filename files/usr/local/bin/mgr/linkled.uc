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

const link = hardware.getLinkLed();
if (!link) {
    return exitApp();
}

let state = null;

function main()
{
    if (state === false) {
        state = true;
        fs.writefile(`${link}/brightness`, "1");
        return waitForTicks(3);
    }
    else if (length(babel.getNeighbors()) > 0) {
        state = null;
        fs.writefile(`${link}/brightness`, "1");
        return waitForTicks(10);
    }
    else {
        state = false;
        fs.writefile(`${link}/brightness`,"0");
        return waitForTicks(3);
    }
}

fs.writefile(`${link}/trigger"`, "none");
fs.writefile(`${link}/brightness`, "1");

return waitForTicks(120, main);
