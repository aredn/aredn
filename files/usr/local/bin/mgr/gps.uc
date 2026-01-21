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

const CONFIG0 = "/etc/config.mesh/gpsd";
const CONFIG1 = "/etc/config/gpsd";
const CHANGEMARGIN = 0.0001;

let gps;

function main()
{
    const c = uci.cursor();
    let j = hardware.GPSReadLLT(gps);

    // Fall back to WiFi-based geolocation if gpsd didn't work out
    if (!j) {
        j = wifi_geolocation.lookup();
    }

    // Update time and date
    if (c.get("aredn", "@time[0]", "gps_enable") == "1" && j && j.time) {
        system(`/bin/date -u -s '${j.time}' > /dev/null 2>&1`);
        fs.writefile("/tmp/timesync", "gps");
    }

    // Set location if significantly changed
    if (c.get("aredn", "@location[0]", "gps_enable") == "1" && j && j.lat && j.lon) {
        const clat = 1 * c.get("aredn", "@location[0]", "lat");
        const clon = 1 * c.get("aredn", "@location[0]", "lon");
        if (math.abs(clat - j.lat) > CHANGEMARGIN || math.abs(clon - j.lon) > CHANGEMARGIN) {
            // Calculate gridsquare from lat/lon
            const alat = j.lat + 90;
            const flat = 65 + int(alat / 10);
            const slat = int(alat % 10);
            const ulat = 97 + int((alat - int(alat)) * 60 / 2.5);

            const alon = j.lon + 180;
            const flon = 65 + int(alon / 20);
            const slon = int((alon / 2) % 10);
            const ulon = 97 + int((alon - 2 * int(alon / 2)) * 60 / 5);

            const gridsquare = sprintf("%c%c%d%d%c%c", flon, flat, slon, slat, ulon, ulat);

            // Update location information
            c.set("aredn", "@location[0]", "lat", j.lat);
            c.set("aredn", "@location[0]", "lon", j.lon);
            c.set("aredn", "@location[0]", "gridsquare", gridsquare);
            c.set("aredn", "@location[0]", "source", "gps");
            c.commit("aredn");
            const cm = uci.cursor("/etc/config.mesh");
            cm.set("aredn", "@location[0]", "lat", j.lat);
            cm.set("aredn", "@location[0]", "lon", j.lon);
            cm.set("aredn", "@location[0]", "gridsquare", gridsquare);
            cm.set("aredn", "@location[0]", "source", "gps");
            cm.commit("aredn");
        }
    }

    return waitForTicks(600); // 10 minutes
}

function find()
{
    gps = hardware.GPSFind();
    if (gps) {
        // Create the GPSD daemon if device is local,
        // otherwise we get the GPS info from another node on our local network
        if (match(gps, /^\/dev\//)) {
            const config = `config gpsd 'core'
option enabled '1'
option device '${gps}'
option port '2947'
option listen_globally '1'
`;
            fs.writefile(CONFIG0, config);
            fs.writefile(CONFIG1, config);
            system("nft insert rule inet fw4 input_dtdlink tcp dport 2947 accept comment \"gpsd\" 2> /dev/null");
            system("/etc/init.d/gpsd restart");
        }
        return main;
    }
    else if (uci.cursor().get("aredn", "@location[0]", "wifi_enable") == "1") {
	return main;
    }
    else {
        return waitForTicks(600); // 10 minutes
    }
}

return waitForTicks(60, find);
