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

import * as hardware from "aredn.hardware";

export const debug = false;

export const application = "/app";
export let preload = true;
export let compress = true;
export let resourcehash = true;
export let authenable = true;
export let forceauth = false;
export let forcemobile = false;
// Do not enable.
// This can causes nodes to hang when the network restarts and the WAN is unavailable.
// Why? Unknown.
export let uilock = false;

if (hardware.isLowMemNode()) {
    preload = false;
}
if (debug) {
    preload = false;
    compress = false;
    resourcehash = false;
    authenable = false;
}
if (forceauth) {
    authenable = false;
}
