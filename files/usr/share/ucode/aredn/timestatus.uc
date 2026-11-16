/* Time-area source/status display by mathisono (2026), GPL-3.0-or-later.
 * Observes native synchronization; does not set the clock or select peers. */
import * as fs from "fs";

const STATUS = "/tmp/time-sync-status.json";
const MARKER = "/tmp/timesync";

function stamp(epoch) {
    if (type(epoch) !== "int" || epoch <= 0) return "time not recorded";
    const t = gmtime(epoch);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d UTC", t.year, t.mon, t.mday, t.hour, t.min, t.sec);
}

function gpsSource(gps) {
    const source = gps?.source;
    const kind = source?.kind === "local" ? "LOCAL" : source?.kind === "network" ? "NETWORK" : "SOURCE UNKNOWN";
    return kind + (source?.endpoint ? " · " + source.endpoint : "");
}

function classify(sync, gps, ntp, now, markerMtime) {
    sync = trim(sync || "");
    if (sync === "ntp") {
        const valid = type(ntp) === "object" && ntp.kind === "ntp" &&
            (ntp.mode === "oneshot" || ntp.mode === "seed" || ntp.mode === "daemon") &&
            type(ntp.checked_uptime) === "int" && ntp.checked_uptime >= 0 && ntp.checked_uptime <= now &&
            type(markerMtime) === "int" && ntp.marker_mtime === markerMtime &&
            ((ntp.mode === "daemon" && ntp.endpoint === null) ||
                (type(ntp.endpoint) === "string" && length(ntp.endpoint) > 0 && length(ntp.endpoint) <= 255));
        if (!valid) return { state: "pending", label: "LAST SYNC · NTP", source: "Source not recorded",
            detail: "The native marker records a previous NTP synchronization; its server and age are not established" };
        const daemon = ntp.mode === "daemon";
        const age = now - ntp.checked_uptime;
        const source = ntp.endpoint || "Selected peer not exposed by NTP daemon";
        if (daemon && (type(ntp.stratum) !== "int" || ntp.stratum < 1 || ntp.stratum >= 16))
            return { state: "error", label: "UNSYNCED · NTP", source,
                detail: "NTP daemon reported an unsynchronized stratum; the selected peer is not exposed" };
        const fresh = age <= (daemon ? 900 : 86400);
        return { state: fresh ? "locked" : "pending", label: fresh ? "SYNCED · NTP" : "LAST SYNC · NTP", source,
            detail: (daemon ? `NTP daemon last reported synchronized at stratum ${ntp.stratum}` :
                "Last successful one-shot NTP synchronization") + `; ${stamp(ntp.sync_epoch)}; source: ${source}` +
                (fresh ? "; this is synchronization evidence, not a continuous receiver lock" : "; status is old") };
    }
    if (sync === "gps" || sync === "network gps" || (!sync && gps)) {
        if (!gps) return { state: "pending", label: "LAST SYNC · GPS", source: "Source not recorded",
            detail: "Previous GPS clock synchronization; live GPS health is disabled or unavailable" };
        const state = gps.state;
        return { state, label: state === "locked" ? "LOCKED · GPS" : state === "pending" ? "WAITING · GPS" : "ERROR · GPS",
            source: gpsSource(gps), detail: gps.reason + "; source: " + gpsSource(gps) +
                "; receiver lock does not certify PPS accuracy or continuous clock discipline" };
    }
    return { state: sync ? "pending" : "error", label: sync ? "TIME SOURCE UNKNOWN" : "NOT SYNCHRONIZED",
        source: sync || "Awaiting NTP or GPS", detail: "No supported current time-source evidence is available" };
}

function current(gps, files, now) {
    files = files || fs;
    let ntp;
    try { ntp = json(files.readfile(STATUS)); } catch (e) { ntp = null; }
    return classify(files.readfile(MARKER), gps, ntp, now === null ? clock(true)[0] : now, files.stat(MARKER)?.mtime);
}

function record(mode, endpoint, stratum, files, now, wall) {
    files = files || fs;
    now = now === null ? clock(true)[0] : now;
    wall = wall === null ? time() : wall;
    if (mode !== "oneshot" && mode !== "seed" && mode !== "daemon") return false;
    if (mode !== "daemon" && (type(endpoint) !== "string" || !length(endpoint))) return false;
    if (endpoint !== null && (type(endpoint) !== "string" || !length(endpoint) || length(endpoint) > 255 || match(endpoint, /[\r\n]/))) return false;
    const marker = files.stat(MARKER);
    if (!marker || trim(files.readfile(MARKER) || "") !== "ntp") return false;
    if (mode === "seed" && (type(marker.mtime) !== "int" || marker.mtime > wall || wall - marker.mtime > now)) return false;
    const status = { kind: "ntp", mode, endpoint, stratum: mode === "daemon" ? stratum : null,
        checked_uptime: mode === "seed" ? now - (wall - marker.mtime) : now,
        sync_epoch: mode === "seed" ? marker.mtime : wall, marker_mtime: marker.mtime };
    // Native callbacks can overlap. Each process publishes from its own file.
    const pid = files.readlink("/proc/self");
    if (type(pid) !== "string" || !match(pid, /^\d+$/)) return false;
    const pending = STATUS + "." + pid + ".new";
    const data = sprintf("%J", status);
    if (files.writefile(pending, data) !== length(data)) {
        files.unlink(pending);
        return false;
    }
    const ok = files.rename(pending, STATUS);
    if (!ok) files.unlink(pending);
    return ok;
}

return { STATUS, classify, current, record, gpsSource };
