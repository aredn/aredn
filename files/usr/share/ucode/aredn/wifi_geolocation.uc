import * as fs from "fs";
import * as uci from "uci";
import * as configuration from "aredn.configuration";

export function lookup()
{
    const cursor = uci.cursor();
    let request;
    let wifi;
    let location;
    let response;

    log.syslog(log.LOG_DEBUG, `Looking for wifi interfaces`);
    cursor.foreach("wireless", "wifi-iface", function(s)
    {
        switch (s.mode) {
            case "ap":
            case "sta":
                wifi=s.device;
                break;
            default:
                break;
        }
    });
    log.syslog(log.LOG_DEBUG, `Found ${wifi}`);

    let current_ap = null;
    let access_points = [];
    if (wifi) {

        // Bring interface down to scan
        log.syslog(log.LOG_NOTICE, `Bringing ${wifi} down`);
        system(`/sbin/wifi down ${wifi}`);

        // Make sure interface is actually down before initiating scan
        while (system(`/usr/bin/iwinfo ${wifi} info | grep -q 'Mode: Unknown'`) != 0) {
            log.syslog(log.LOG_DEBUG, `Waiting for ${wifi} to be down`);
            sleep(1000);
        }

        // Scan interface
        log.syslog(log.LOG_INFO, `Scanning ${wifi}`);
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

        f.close();

        // Push the last AP
        if (current_ap) {
            push(access_points, current_ap);
        }

        // Bring interface back up
        log.syslog(log.LOG_NOTICE, `Bringing ${wifi} up`);
        system(`/sbin/wifi up ${wifi}`);

        // Generate the request string
        request = sprintf("%J\n", { wifiAccessPoints: access_points });
    }

    if (request) {
        const ua = sprintf("%s/%s", 'AREDN', configuration.getFirmwareVersion());
        const f = fs.popen(`/bin/uclient-fetch -O - --header='Content-Type: application/json' --post-data='${request}' 'https://api.beacondb.net/v1/geolocate?key=${ua}'`);
        if (f) {
            let line;
            while (line = f.read("line")) {
                let j = json(line);
                if (j) {
                    response = j;
                    break;
                }
            }
            f.close();
        }
    }

    if (response) {
	log.syslog(log.LOG_DEBUG, `beacondb response: ${response}`);
        if (response.location && response.location.lat && response.location.lng && response.accuracy) {
            location = { lat: response.location.lat, lon: response.location.lng, eph: response.accuracy };
        }
    }
    return location;
};
