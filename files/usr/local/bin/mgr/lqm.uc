/*
 * Part of AREDN®; // Used for creating Amateur Radio Emergency Data Networks
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

const refresh_timeout_base = 12 * 60; // refresh high cost data every 12 minutes
const refresh_timeout_range = 5 * 60; // to 12 + 5 minutes
const refresh_retry_timeout = 5 * 60;
const lastseen_timeout = 24 * 60 * 60; // age out nodes we've not seen for 24 hours
const snr_run_avg = 0.4; // snr running average
const tx_quality_run_avg = 0.4; // tx quality running average
const ping_timeout = 1.0; // timeout before ping gives a qualtiy penalty
const ping_time_run_avg = 0.4; // ping time runnng average
const bitrate_run_avg = 0.4; // rx/tx running average
const noise_run_avg = 0.8; // noise running average
const dtd_distance = 50; // distance (meters) after which nodes connected with DtD links are considered different sites
const connect_timeout = 5; // timeout (seconds) when fetching information from other nodes
const default_short_retries = 20; // More link-level retries helps overall tcp performance (factory default is 7)
const default_long_retries = 20; // (factory default is 4)
const default_max_distance = 80550; // 50.1 miles
const rts_threshold = 1; // RTS setting when hidden nodes are detected
const ping_penalty = 5; // Cost of a failed ping to measure of a link's quality
const lastup_margin = 120; // Seconds before link is considered down

const IW = "/usr/sbin/iw";
const UFETCH = "/bin/uclient-fetch";
const PING6 = "/bin/ping6";

// Get all the radios currently running in a mesh-family mode. Captured once at
// startup, same as the single-radio lookup this replaces - a live radio
// reconfiguration already requires an LQM restart to be picked up.
const meshRadios = radios.getMeshRadios();
const radioState = map(meshRadios, function(d) {
    return {
        iface: d.iface,
        mode: d.mode,
        phy: hardware.getPhyDevice(d.iface),
        radio: hardware.getRadioDevice(d.iface),
        devtype: hardware.getRadioType(d.iface),
        noise: -95,
        lastDistance: -1,
        lastReadDistance: -1,
        distance: -1
    };
});

function findRadioState(iface)
{
    for (let i = 0; i < length(radioState); i++) {
        if (radioState[i].iface == iface) {
            return radioState[i];
        }
    }
    return null;
}

let config = {};

function maxDistanceFor(radio)
{
    const cm = uci.cursor("/etc/config.mesh");
    const max_distance = cm.get("setup", "globals", `${radio}_distance`) || default_max_distance;
    return max_distance > 0 ? max_distance : default_max_distance;
}

function updateConfig()
{
    const c = uci.cursor();
    config = {
        user_blocks: c.get("aredn", "@lqm[0]", "user_blocks")
    };
}

function refreshTimeout()
{
    return refresh_timeout_base + (refresh_timeout_range * math.rand() / 0x7fffffff);
}

function calcDistance(lat1, lon1, lat2, lon2)
{
    const r2 = 12742000; // diameter earth (meters)
    const p = 0.017453292519943295; // Math.PI / 180
    const v = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
    return int(r2 * math.atan2(math.sqrt(v), math.sqrt(1 - v)));
}

function floor(v)
{
    return int(v);
}

function round(v)
{
    return int(v + 0.5);
}

function ceil(v)
{
    const v2 = int(v);
    return v === v2 ? v2 : v2 + 1;
}

function canonicalHostname(hostname)
{
    return lc(replace(replace(replace(replace(replace(replace(hostname, /^dtdlink\./, ""), /^xlink\d+\./, ""), /^xlink\d+\./, ""), /^lan\./, ""), /^supernode\./, ""), /\.local\.mesh$/, ""));
}

function iwSet(phy, cmd)
{
    if (phy) {
        system(`${IW} ${phy} set ${cmd} > /dev/null 2>&1`);
    }
}

const myhostname = canonicalHostname(configuration.getName());
// All of our own mesh network addresses (the primary "wifi" network, plus any
// additional "wifiN" networks when more than one radio is mesh) so none of
// them can ever be mistaken for a hidden node.
const myips = {};
uci.cursor().foreach("network", "interface", function(s) {
    if (s.ipaddr && (s[".name"] == "wifi" || match(s[".name"], /^wifi[0-9]+$/))) {
        myips[s.ipaddr] = true;
    }
});
const mylanip = uci.cursor().get("network", "lan", "ipaddr");
const issupernode = uci.cursor().get("aredn", "@supernode[0]", "enable") == "1";

// Clear old data
fs.writefile("/tmp/lqm.info", '{"trackers":{},"hidden_nodes":[]}');

function updateAllowList(wlan, radio)
{
    const f = `/var/run/hostapd-${wlan}.maclist`;
    const o = fs.readfile(f);
    if (o === null) {
        return false;
    }
    let n = "";
    const peer = uci.cursor("/etc/config.mesh").get("setup", "globals", `${radio}_peer`);
    if (peer) {
        n = `${peer}\n`;
    }
    if (o == n) {
        return false;
    }
    fs.writefile(f, n);
    system("/usr/bin/killall -HUP hostapd");
    return true;
}

function updateDenyList(wlan, trackers)
{
    const f = `/var/run/hostapd-${wlan}.maclist`;
    const o = fs.readfile(f);
    if (o === null) {
        return false;
    }
    let n = "";
    for (let mac in trackers) {
        if (trackers[mac].user_blocks) {
            n += `${mac}\n`;
        }
    }
    if (o == n) {
        return false;
    }
    fs.writefile(f, n);
    system("/usr/bin/killall -HUP hostapd");
    return true;
}

function reachToLQ(reach)
{
    reach = hex(reach);
    let count = 0;
    for (let i = 0; i < 16; i++) {
        if (reach & 1) {
            count++;
        }
        reach >>= 1;
    }
    return ceil(100 * count / 16);
}

let xlinks = {};

function deviceToType(device)
{
    if (device == "br-dtdlink") {
        return "DtD";
    }
    else if (device === "br-wifi" || match(device, /^wlan/)) {
        return "RF";
    }
    else if (match(device, /^wg/)) {
        return "Wireguard";
    }
    else if (xlinks[device]) {
        return "Xlink";
    }
    else {
        return null;
    }
}

function main()
{
    const trackers = {};
    let rfLinks = {};
    let hiddenNodes = {};
    let now = 0;
    let previousnow = 0;
    const start = clock(true)[0];

    updateConfig();

    // Reset each radio's per-tick tracking state fresh on every (re)start.
    for (let i = 0; i < length(radioState); i++) {
        const rs = radioState[i];
        rs.noise = -95;
        rs.lastDistance = -1;
        rs.lastReadDistance = -1;
        rs.distance = -1;

        const max_distance = maxDistanceFor(rs.radio);

        // We dont know any distances yet
        switch (rs.devtype) {
            case "halow":
            case "ax":
            case "ac":
                rs.lastDistance = max_distance;
                if (hardware.supportsFeature("max-distance", rs.iface)) {
                    rs.lastReadDistance = hardware.setMaxDistance(rs.iface, rs.lastDistance);
                }
                break;
            case "n":
                iwSet(rs.phy, "distance auto");
                break;
            default:
                break;
        }
        // Or any hidden nodes
        iwSet(rs.phy, "rts off");
        // Set the default retries
        iwSet(rs.phy, `retry short ${default_short_retries} long ${default_long_retries}`);
        // Setup mac filters
        if (rs.mode == "meshptp") {
            // In PtP mode we allow a single mac address
            updateAllowList(rs.iface, rs.radio);
        }
        else {
            // Clear the deny list
            updateDenyList(rs.iface, {});
        }
    }

    // This file allows the main loop to restart
    fs.unlink("/tmp/lqm.reset");

    // Main loop
    function tick()
    {
        now = clock(true)[0];

        updateConfig();

        const cursor = uci.cursor();
        const cursorm = uci.cursor("/etc/config.mesh");
        let refresh = false;

        const lat = cursor.get("aredn", "@location[0]", "lat") ? 1 * cursor.get("aredn", "@location[0]", "lat") : null;
        const lon = cursor.get("aredn", "@location[0]", "lon") ? 1 * cursor.get("aredn", "@location[0]", "lon") : null;

        // Update xlinks
        xlinks = {};
        cursorm.foreach("xlink", "interface", section => {
            if (section.ifname) {
                xlinks[section.ifname] = true;
            }
        });

        // Find our neighbors
        const p = fs.popen("echo dump-neighbors | /usr/bin/socat -T 30 -t 30 UNIX-CLIENT:/var/run/babel.sock - 2>/dev/null");
        if (p) {
            for (let line = p.read("line"); length(line); line = p.read("line")) {
                const m = match(line, /^add.*address ([^ \t]+) if ([^ \t]+) reach ([^ \t]+) .* rxcost ([^ \t]+) txcost ([^ \t]+)/);
                if (m) {
                    const type = deviceToType(m[2]);
                    const mac = network.ipv6ll2mac(m[1]);
                    let track = trackers[mac];
                    if (!track && type) {
                        track = {
                            lastseen: now,
                            lastup: now,
                            type: type,
                            device: m[2],
                            mac: mac,
                            ipv6ll: m[1],
                            refresh: 0,
                            avg_lq: 100
                        };
                        if (type === "RF") {
                            track.mode = findRadioState(m[2])?.mode;
                        }
                        trackers[mac] = track;
                    }
                    if (track) {
                        track.lq = reachToLQ(m[3]);
                        track.rxcost = int(m[4]);
                        track.txcost = int(m[5]);
                        const rtt = match(line, /rtt ([^ \t]+)/);
                        if (rtt) {
                            track.rtt = int(rtt[1]);
                        }
                        track.avg_lq = min(100, 0.9 * track.avg_lq + 0.1 * track.lq);
                    }
                }
            }
            p.close();
        }

        // Update stats for tunnels and xlinks
        const activeDevices = {};
        const istats = rtnl.request(rtnl.const.RTM_GETLINK, rtnl.const.NLM_F_DUMP, {});
        for (let i = 0; i < length(istats); i++) {
            const stat = istats[i];
            const type = deviceToType(stat.dev);
            if (type === "Wireguard" || type == "Xlink") {
                for (let mac in trackers) {
                    const t = trackers[mac];
                    if (t.device == stat.dev) {
                        t.tx_packets = stat.stats64.tx_packets;
                        t.tx_fail = stat.stats64.tx_errors;
                        break;
                    }
                }
            }
            if (stat.dev) {
                activeDevices[stat.dev] = true;
            }
        }

        // Remove any trackers for devices which no longer exist
        for (let mac in trackers) {
            const track = trackers[mac];
            const device = track.device;
            if (device && !activeDevices[device]) {
                delete trackers[mac];
            }
        }

        // Update stats for radios, one radio at a time so each contributes its own
        // noise floor and bitrate scaling to its own neighbors' trackers.
        for (let i = 0; i < length(radioState); i++) {
            const rs = radioState[i];

            // If the channel bandwidth is less than 20, we need to adjust what we report as the values.
            // NOTE. THE nl80211 api report bitrates x10 so we need to reduce this by 10 here.
            const chanbw = int(cursor.get("wireless", rs.radio, "chanbw") || "20");
            const channelBwScale = (rs.devtype === "halow" ? 1 : min(20, chanbw)) / 200.0;

            const cnoise = hardware.getRadioNoise(rs.iface);
            if (cnoise < -70) {
                rs.noise = round(rs.noise * noise_run_avg + cnoise * (1 - noise_run_avg));
            }
            const stations = nl80211.request(nl80211.const.NL80211_CMD_GET_STATION, nl80211.const.NLM_F_DUMP, { dev: rs.iface });
            for (let j = 0; j < length(stations); j++) {
                const station = stations[j];
                const track = trackers[station.mac];
                if (track) {
                    track.signal = station.sta_info.signal;
                    track.tx_packets = station.sta_info.tx_packets;
                    track.tx_retries = station.sta_info.tx_retries;
                    track.tx_fail = station.sta_info.tx_failed;
                    if (station.sta_info.tx_bitrate) {
                        track.tx_bitrate = station.sta_info.tx_bitrate.bitrate * channelBwScale;
                    }
                    if (station.sta_info.rx_bitrate) {
                        track.rx_bitrate = station.sta_info.rx_bitrate.bitrate * channelBwScale;
                    }
                    if (track.snr !== null) {
                        track.snr = max(0, round(track.snr * snr_run_avg + (track.signal - rs.noise) * (1 - snr_run_avg)));
                    }
                    else {
                        track.snr = max(0, track.signal - rs.noise);
                    }
                    track.connected_time = station.sta_info.connected_time;
                }
            }
        }

        // Update running averages
        for (let mac in trackers) {
            const track = trackers[mac];
            if (track.tx_packets) {
                if (track.last_tx_packets === null) {
                    track.avg_tx_packets = 0;
                }
                else {
                    track.avg_tx_packets = track.avg_tx_packets * tx_quality_run_avg + max(0, track.tx_packets - track.last_tx_packets) * (1 - tx_quality_run_avg);
                }
                track.last_tx_packets = track.tx_packets;
            }
            if (track.tx_retries) {
                if (track.last_tx_retries === null) {
                    track.avg_tx_retries = 0;
                }
                else {
                    track.avg_tx_retries = track.avg_tx_retries * tx_quality_run_avg + max(0, track.tx_retries - track.last_tx_retries) * (1 - tx_quality_run_avg);
                }
                track.last_tx_retries = track.tx_retries;
            }
            if (track.tx_fail) {
                if (track.last_tx_fail === null) {
                    track.avg_tx_fail = 0;
                }
                else {
                    track.avg_tx_fail = track.avg_tx_fail * tx_quality_run_avg + max(0, track.tx_fail - track.last_tx_fail) * (1 - tx_quality_run_avg);
                }
                track.last_tx_fail = track.tx_fail;
            }
            if (track.tx_bitrate) {
                if (track.avg_tx_bitrate === null) {
                    track.avg_tx_bitrate = track.avg_tx_bitrate;
                }
                else {
                    track.avg_tx_bitrate = track.avg_tx_bitrate * bitrate_run_avg + track.tx_bitrate * (1 - bitrate_run_avg);
                }
            }
            if (track.rx_bitrate) {
                if (track.avg_rx_bitrate === null) {
                    track.avg_rx_bitrate = track.avg_rx_bitrate
                }
                else {
                    track.avg_rx_bitrate = track.avg_rx_bitrate * bitrate_run_avg + track.rx_bitrate * (1 - bitrate_run_avg);
                }
            }
            if (track.avg_tx_packets && track.avg_tx_packets > 0) {
                const bad = max(track.avg_tx_fail || 0, track.avg_tx_retries || 0);
                track.tx_quality = 100 * (1 - min(1, bad / track.avg_tx_packets));
            }
        }

        // Because the following operations can take a while, we need to do them
        // asynchronously and allow the uloop to do other things. This makes the
        // rest of this messy - sorry.
        let updateTrackingState;
        let finish;

        // Max RF distance, per radio
        for (let i = 0; i < length(radioState); i++) {
            radioState[i].distance = -1;
        }
        const ip2tracker = {};

        // Refresh remote attributes periodically as this is expensive
        // We dont do it the very first time so we can populate the LQM state with a new node quickly
        const trackerlist = values(trackers);
        let tidx = -1;
        function remoteRefresh()
        {
            if (++tidx >= length(trackerlist)) {
                // Move to next operations
                tidx = -1;
                return waitForTicks(0, updateTrackingState);
            }

            const track = trackerlist[tidx];
            if (track.refresh === 0) {
                refresh = true;
                track.refresh = now;
            }
            else if (now > track.refresh && track.ipv6ll) {
                const p = fs.popen(`${UFETCH} -T ${connect_timeout} "http://[${track.ipv6ll}%${track.device}]:8080/cgi-bin/sysinfo.json?lqm=1" -O - 2> /dev/null`);
                if (p) {
                    let info = null;
                    try {
                        info = json(p.read("all"));
                    }
                    catch (_) {
                    }
                    p.close();
                    if (!info) {
                        // Failed to fetch information. Set time for retry and invalidate any information
                        // considered stale
                        track.refresh = now + refresh_retry_timeout;
                        track.rev_lq = null;
                        track.rev_snr = null;
                        track.rev_ping_success_time = null;
                        track.rev_ping_quality = null;
                        track.rev_quality = null;
                    }
                    else {
                        track.refresh = now + refreshTimeout();
                        track.rev_lastseen = now;

                        track.hostname = canonicalHostname(info.node);
                        track.canonical_ip = network.getIPAddressFromHostname(track.hostname);
                        if (track.type === "Wireguard") {
                            const address = cursor.get("network", track.device, "addresses")[0];
                            const m = match(address, /^(\d+\.\d+\.\d+\.)(\d+)$/);
                            if (match(track.device, /^wgs/)) {
                                track.ip = `${m[1]}${int(m[2]) - 1}`;
                            }
                            else {
                                track.ip = `${m[1]}${int(m[2]) + 1}`
                            }
                        }
                        else {
                            for (let i = 0; i < length(info.interfaces); i++) {
                                const iface = info.interfaces[i];
                                if (iface.mac && lc(iface.mac) === track.mac && iface.ip) {
                                    track.ip = iface.ip;
                                    break;
                                }
                            }
                        }

                        // Update the distance to the remote node
                        if ("lat" in info) {
                            track.lat = 1 * info.lat;
                        }
                        if ("lon" in info) {
                            track.lon = 1 * info.lon;
                        }
                        if ("lat" in track && "lon" in track && lat != null && lon != null) {
                            track.distance = calcDistance(lat, lon, track.lat, track.lon);
                            if (track.type === "DtD" && track.distance < dtd_distance) {
                                track.localarea = true;
                            }
                            else {
                                track.localarea = false;
                            }
                        }

                        // Keep some useful info
                        if (info.node_details) {
                            track.model = info.node_details.model;
                            track.firmware_version = info.node_details.firmware_version;
                        }

                        if (info.lqm && info.lqm.info && info.lqm.info.trackers) {
                            const rtrackers = info.lqm.info.trackers;
                            for (let mac in rtrackers) {
                                const rtrack = rtrackers[mac];
                                if (myhostname == canonicalHostname(rtrack.hostname)) {
                                    track.rev_lq = rtrack.lq;
                                    track.rev_ping_success_time = rtrack.ping_success_time;
                                    track.rev_ping_quality = rtrack.ping_quality;
                                    track.rev_quality = rtrack.quality;
                                    break;
                                }
                            }

                            if (track.type == "RF") {
                                rfLinks[track.mac] = {};
                                for (let mac in rtrackers) {
                                    const rtrack = rtrackers[mac];
                                    if (rtrack.type === "RF" || !rtrack.type) {
                                        const rhostname = canonicalHostname(rtrack.hostname);
                                        if (rtrack.ip && rtrack.routable) {
                                            rfLinks[track.mac][rtrack.ip] = {
                                                ip: rtrack.ip,
                                                hostname: rhostname,
                                            };
                                            if (track.lat && rtrack.lon && lat && lon) {
                                                rfLinks[track.mac][rtrack.ip].distance = calcDistance(lat, lon, 1 * rtrack.lat, 1 * rtrack.lon);
                                            }
                                        }
                                        if (myhostname == rhostname) {
                                            track.rev_snr = (track.rev_snr && rtrack.snr) ? round(snr_run_avg * track.rev_snr + (1 - snr_run_avg) * rtrack.snr) : rtrack.snr;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        
            // Do the next iteration async
            return waitForTicks(0, remoteRefresh);
        }

        const hostRoutes = babel.getHostRoutes();
        const superRoute = babel.getSupernodeRoute();

        // Update link tracking state
        updateTrackingState = function _updateTrackingState()
        {
            if (++tidx >= length(trackerlist)) {
                // Finish up
                return waitForTicks(0, finish);
            }
    
            const track = trackerlist[tidx];
            
            // Clear route counter
            track.babel_route_count = 0;
            track.babel_metric = null;
            track.routable = false;

            if (track.ip || track.canonical_ip) {
                ip2tracker[track.ip || track.canonical_ip] = track;
            }

            // Refresh user blocks
            track.user_blocks = false;
            const blocks = split(config.user_blocks, ",");
            for (let i = 0; i < length(blocks); i++) {
                const block = blocks[i];
                if (track.mac == lc(replace(replace(block, /[ \t]/, ""), "-", ":"))) {
                    track.user_blocks = true;
                    break;
                }
            }

            // Include babel info for this link
            track.babel_config = {
                hello_interval: int(cursor.get("babel", "default", "hello_interval")),
                update_interval: int(cursor.get("babel", "default", "update_interval"))
            };
            if (track.type === "Wireguard") {
                track.babel_config.rxcost = int(cursor.get("wireguard", "@network[0]", "cost") || cursor.get("babel", "tunnel", "rxcost") || 300);
            }
            else if (track.type === "Xlink") {
                track.babel_config.rxcost = int(cursor.get("babel", "xlink", "rxcost"));
            }
            else {
                track.babel_config.rxcost = int(cursor.get("babel", "default", "rxcost"));
            }

            // Ping addresses and penalize quality for excessively slow links
            if (track.ipv6ll && !track.user_blocks) {
                let ptime = null;
                const p = fs.popen(`${PING6} -c 1 -W ${round(ping_timeout)} -I ${track.device} ${track.ipv6ll}`);
                if (p) {
                    for (let line = p.read("line"); length(line); line = p.read("line")) {
                        const m = match(trim(line), /^64 bytes from .* time=([^ \t]+) ms$/);
                        if (m) {
                            ptime = m[1] / 1000;
                        }
                    }
                    p.close();
                }

                track.ping_quality = track.ping_quality ? track.ping_quality + 1 : 100;
                if (ptime === null) {
                    track.ping_quality = track.ping_quality - ping_penalty;
                }
                else {
                    track.ping_success_time = track.ping_success_time ? (track.ping_success_time * ping_time_run_avg + ptime * (1 - ping_time_run_avg)) : ptime;
                }
                track.ping_quality = max(0, min(100, track.ping_quality));
                if (ptime !== null) {
                    if (track.lastseen + lastup_margin < previousnow) {
                        track.lastup = now;
                    }
                    track.lastseen = now
                }
            }
            else {
                track.ping_quality = null;
                track.ping_success_time = null;
            }

            // Calculate overall link quality
            if (track.tx_quality) {
                if (track.ping_quality) {
                    track.quality = round((track.tx_quality + track.ping_quality) / 2);
                }
                else {
                    track.quality = round(track.tx_quality);
                }
            }
            else if (track.ping_quality) {
                track.quality = round(track.ping_quality);
            }
            else {
                track.quality = nil;
            }

            // Calculate the max RF distance as we go, per radio
            if (track.type == "RF" && track.lastseen >= now) {
                const rs = findRadioState(track.device);
                if (rs) {
                    if (track.distance === null) {
                        rs.distance = maxDistanceFor(rs.radio);
                    }
                    else if (!track.user_blocks && track.distance > rs.distance) {
                        rs.distance = track.distance;
                    }
                }
            }

            // Do the next iteration async
            return waitForTicks(0, updateTrackingState);
        };

        finish = function _finish()
        {
            // Pull in the routing table to see how many node routes are associated with each tracker.
            total_route_count = 0;
            for (let i = 0; i < length(hostRoutes); i++) {
                const r = hostRoutes[i];
                const t = ip2tracker[r.gateway];
                if (t) {
                    t.routable = true;
                    t.babel_route_count++;
                    if (t.babel_metric === null || r.metric < t.babel_metric) {
                        t.babel_metric = r.metric;
                    }
                    total_route_count++;
                }
            }
            if (superRoute) {
                const t = ip2tracker[superRoute.gateway];
                if (t) {
                    t.routable = true;
                    t.babel_route_count++;
                    if (t.babel_metric === null || superRoute.metric < t.babel_metric) {
                        t.babel_metric = superRoute.metric;
                    }
                    total_route_count++;
                }
            }

            // Remove any trackers which are too old or if they disconnect when first seen
            for (let mac in trackers) {
                const track = trackers[mac];
                // *DONT* remove any user blocked trackers. If we block these devices at a low level (via
                // the deny list for example) then we never see them again at this level and we loose the ability
                // to unblock them without a reboot.
                if (!track.user_blocks) {
                    if ((now > track.lastseen + lastseen_timeout) || (track.rev_lastseen && now > track.rev_lastseen + lastseen_timeout)) {
                        delete trackers[mac];
                    }
                }
            }

            for (let i = 0; i < length(radioState); i++) {
                const rs = radioState[i];
                if (rs.mode == "meshptp") {
                    // In PtP mode we allow a single mac address.
                    // Update this every time in case the file gets overwritten (which happens when
                    // hostapd gets restarted)
                    updateAllowList(rs.iface, rs.radio);
                }
                else {
                    // Update denied mac list
                    updateDenyList(rs.iface, trackers);
                }

                // Update this radio's distance
                const max_distance = maxDistanceFor(rs.radio);
                if (rs.distance < 0) {
                    rs.distance = max_distance;
                }
                else {
                    rs.distance = min(rs.distance, max_distance);
                }
                if (hardware.supportsFeature("max-distance", rs.iface)) {
                    if (rs.distance != rs.lastDistance || rs.lastReadDistance != hardware.getMaxDistance(rs.iface)) {
                        rs.lastDistance = rs.distance;
                        rs.lastReadDistance = hardware.setMaxDistance(rs.iface, rs.distance);
                    }
                }
            }

            // Set the RTS/CTS state depending on whether everyone can see everyone.
            // This is computed once across all radios (a node hidden from one radio's
            // neighbors is treated the same as hidden from any other) and then applied
            // to every mesh radio.
            // Build a list of all the nodes our neighbors can see
            const theres = {};
            for (let mac in rfLinks) {
                const track = trackers[mac];
                if (track && !track.user_blocks && track.routable) {
                    const rfneighbor = rfLinks[mac];
                    for (let nip in rfneighbor) {
                        theres[nip] = rfneighbor[nip];
                    }
                }
            }
            // Remove all the nodes we can see from this set
            for (let mac in trackers) {
                const track = trackers[mac];
                if (track.ip) {
                    delete theres[track.ip];
                }
            }
            // Including ourself
            for (let ip in myips) {
                delete theres[ip];
            }
            delete theres[mylanip];

            // If there are any nodes left, then our neighbors can see hidden nodes we cant. Enable RTS/CTS
            const hidden = values(theres);
            if ((length(hidden) == 0) != (length(hiddenNodes) == 0)) {
                for (let i = 0; i < length(radioState); i++) {
                    if (length(hidden) > 0) {
                        iwSet(radioState[i].phy, `rts ${rts_threshold}`);
                    }
                    else {
                        iwSet(radioState[i].phy, "rts off");
                    }
                }
            }
            hiddenNodes = hidden;

            // Save this for the UI. "distance" is kept as a single scalar for
            // backward compatibility (no consumer reads per-radio detail) - the
            // max across all mesh radios, identical to today's value when there's
            // only one.
            let maxDistance = -1;
            for (let i = 0; i < length(radioState); i++) {
                if (radioState[i].distance > maxDistance) {
                    maxDistance = radioState[i].distance;
                }
            }
            fs.writefile("/tmp/lqm.info", sprintf("%.2J", {
                start: start,
                now: now,
                trackers: trackers,
                distance: maxDistance,
                hidden_nodes: hiddenNodes,
                total_route_count: total_route_count
            }));
            if (fs.access("/tmp/lqm.reset")) {
                fs.unlink("/tmp/lqm.reset");
                return waitForTicks(0, main);
            }

            // Last time we ran
            previousnow = now;

            // Done until the next iteration
            return waitForTicks(refresh ? 1 : 30, tick);
        };

        return waitForTicks(0, remoteRefresh);
    }

    return waitForTicks(0, tick);
}

return waitForTicks(max(0, 30 - clock(true)[0]), main);
