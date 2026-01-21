import * as fs from "fs";
import * as uci from "uci";

export function lookup()
{
    const cursor = uci.cursor();
    let request;
    let wifi;
    let location;
    let response;

    cursor.foreach("wireless", "wifi-iface", function(s)
    {
        printf("s: %s\n", s);
        switch (s.mode) {
            case "ap":
            case "sta":
                wifi=s.device;
                break;
            default:
                break;
        }
    });
    printf("Wifi: %s\n", wifi);

    let current_ap = null;
    let access_points = [];
    if (wifi) {
        const f = fs.popen(`/usr/bin/iwinfo ${wifi} scan`);
        let line;
        while (line = f.read("line")) {
            line = trim(line);

            if (match(line, /^Cell/)) {
                // New AP
                if (current_ap) {
                    // Store previously current AP
                    push(access_points, current_ap)
                }
                current_ap = {};
            }

            // Skip processing if we haven't found a Cell header yet
            if (!current_ap) continue;

            // Match Address
            let addr_match = match(line, /Address:\s*([A-Fa-f0-9:]+)/);
            if (addr_match) {
                current_ap.macAddress = addr_match[1];
            }

            // Match Signal
            let sig_match = match(line, /Signal:\s*([-0-9]+)/);
            if (sig_match) {
                current_ap.signalStrength = int(sig_match[1]);
            }
        }

        // Push the last AP
        if (current_ap) {
            push(access_points, current_ap);
        }

        // Generate the request string
        request = sprintf("%J\n", { wifiAccessPoints: access_points });
    }

    if (request) {
        const f = fs.popen(`/bin/uclient-fetch -q -O - --header='Content-Type: application/json' --post-data='${request}' 'https://api.beacondb.net/v1/geolocate?key=org.arednmesh.geolocation'`);
        if (f) {
            let line;
            while (line = f.read("line")) {
                let j = json(line);
                if (j) {
                    response = j;
                    printf("Got a response: %s\n", response);
                    break;
                }
            }
            f.close();
        }
    }

    if (response) {
        if (response.location && response.location.lat && response.location.lng && response.accuracy) {
            location = { lat: response.location.lat, lon: response.location.lng, eph: response.location.accuracy };
        }
    }
    return location;
};
