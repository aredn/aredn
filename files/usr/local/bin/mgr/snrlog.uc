/*
 * Part of AREDN® -- Used for creating Amateur Radio Emergency Data Networks
 * Copyright (C) 2021,2025 Tim Wilkinson
 * Copyright (C) 2019 Darryl Quinn
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

const device = radios.getMeshRadio();
if (!device) {
    return exitApp();
}
const wifi = device.iface;
const bwAdjust = uci.cursor().get("wireless", replace(wifi, "^wlan", "radio"), "chanbw") / 20 / 1000;

const TMPDIR = "/tmp/snrlog/";
const DEFNOISE = -95;
const MAXLINES = 2880; // 2 days worth
const AGETIME = 43200; // 12 hours

fs.mkdir(TMPDIR);

function main()
{
    const now = clock()[0];
    const tm = localtime();

    // Remove any data file which are too old
    const d = fs.opendir(TMPDIR);
    if (d) {
        for (let f = d.read(); f; f = d.read()) {
            if (f !== "." && f !== "..") {
                const path = `${TMPDIR}${f}`;
                const info = fs.stat(path);
                if (info && info.mtime + AGETIME < now) {
                    fs.unlink(path);
                }
            }
        }
        d.close();
    }

    // Get the noise floor
    let noise = DEFNOISE;
    const survey = nl80211.request(nl80211.const.NL80211_CMD_GET_SURVEY, nl80211.const.NLM_F_DUMP, { dev: wifi });
    for (let i = 0; i < length(survey); i++) {
        if (survey[i].dev == wifi && survey[i].survey_info.noise) {
            noise = survey[i].survey_info.noise;
            break;
        }
    }

    // Get all the stations
    const stations = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: wifi });
    for (let i = 0; i < length(stations); i++) {
        const s = stations[i];
        const datafile = `${TMPDIR}${s.mac}`;
        const lines = [];
        let f = fs.open(datafile);
        if (f) {
            for (let line = f.read("line"); length(line); line = f.read("line")) {
                push(lines, line);
            }
            f.close();
        }
        push(lines, `${sprintf("%02d/%02d/%d %02d:%02d:%02d", tm.mon, tm.mday, tm.year, tm.hour, tm.min, tm.sec)},${s.sta_info.signal},${noise},${s.sta_info.tx_bitrate.mcs},${s.sta_info.tx_bitrate.bitrate * bwAdjust},${s.sta_info.rx_bitrate.mcs},${s.sta_info.rx_bitrate.bitrate * bwAdjust}\n`);
        while (length(lines) > MAXLINES) {
            shift(lines);
        }
        f = fs.open(datafile, "w");
        if (f) {
            for (let i = 0; i < length(lines); i++) {
                fs.write(lines[i]);
            }
            f.close();
        }
    }
}

return waitForTicks(60, main);
