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

const meters_to_miles = 0.000621371;
const meters_to_km = 0.001;
let metric = null;

function isMetric()
{
    if (metric === null) {
        const lang = request?.env?.HTTP_ACCEPT_LANGUAGE || "en-US";
        if (index(lang, "-US") !== -1 || index(lang, "-GB") !== -1) {
            metric = false;
        }
        else {
            metric = true;
        }
    }
    return metric;
};

export function distanceUnit()
{
    return isMetric() ? "km" : "miles";
};

export function meters2distance(meters)
{
    if (isMetric()) {
        return meters * meters_to_km;
    }
    else {
        return meters * meters_to_miles;
    }
};

export function distance2meters(distance)
{
    if (isMetric()) {
        return distance / meters_to_km;
    }
    else {
        return distance / meters_to_miles;
    }
};
