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

function ageText(seconds) {
    if (seconds < 60) return `${seconds}s ago`;
    if (seconds < 3600) return `${int(seconds / 60)}m ago`;
    if (seconds < 86400) return `${int(seconds / 3600)}h ago`;
    return `${int(seconds / 86400)}d ago`;
}

function classify(sync, gps, ntp, now, markerMtime) {
    sync = trim(sync || "");
    if (sync === "ntp") {
        const valid = type(ntp) === "object" && ntp.kind === "ntp" &&
            (ntp.mode === "oneshot" || ntp.mode === "daemon") &&
            type(ntp.checked_uptime) === "int" && ntp.checked_uptime >= 0 && ntp.checked_uptime <= now &&
            type(markerMtime) === "int" && ntp.marker_mtime === markerMtime &&
            (ntp.mode === "daemon" ? ntp.endpoint === null :
                (type(ntp.endpoint) === "string" && length(ntp.endpoint) > 0 && length(ntp.endpoint) <= 255));
        if (!valid) return { state: "pending", label: "STATUS UNKNOWN", source: "Source not recorded",
            note: "Last sync: NTP · Time and source not recorded",
            detail: "Last sync: NTP; source and time not recorded; current synchronization is unknown" };
        const daemon = ntp.mode === "daemon";
        const age = now - ntp.checked_uptime;
        const source = ntp.endpoint || "Selected peer not exposed by NTP daemon";
        const fresh = age <= (daemon ? 900 : 86400);
        if (daemon && (type(ntp.stratum) !== "int" || ntp.stratum < 1 || ntp.stratum >= 16))
            return { state: fresh ? "error" : "pending", label: fresh ? "UNSYNCED · NTP" : "STATUS UNKNOWN", source,
                note: `Last report: NTP unsynchronized · ${stamp(ntp.sync_epoch)} · ${ageText(age)}` +
                    (fresh ? "" : " · Status old"),
                detail: "NTP daemon last reported an unsynchronized stratum; the selected peer is not exposed" +
                    `; last report: ${stamp(ntp.sync_epoch)}; observation age: ${age} seconds` +
                    (fresh ? "" : "; status is old; current synchronization is unknown") };
        return { state: fresh ? "locked" : "pending", label: fresh ? "SYNCED · NTP" : "STATUS UNKNOWN", source,
            note: `Last sync: NTP · ${stamp(ntp.sync_epoch)} · ${ageText(age)}` + (fresh ? "" : " · Status old"),
            detail: "Last sync: NTP; " + (daemon ? `NTP daemon last reported synchronized at stratum ${ntp.stratum}` :
                "Last successful one-shot NTP synchronization") + `; ${stamp(ntp.sync_epoch)}; source: ${source}` +
                `; observation age: ${age} seconds` +
                (fresh ? "; this is synchronization evidence, not a continuous receiver lock" :
                    "; status is old; current synchronization is unknown") };
    }
    if (sync === "gps" || sync === "network gps" || (!sync && gps)) {
        if (!gps) return { state: "pending", label: "STATUS UNKNOWN", source: "Source not recorded",
            note: "Last sync: GPS · Time not recorded · Receiver health unavailable",
            detail: "Last sync: GPS; time not recorded; current GPS health is disabled or unavailable" };
        const state = gps.state === "unknown" ? "pending" : gps.state;
        return { state, label: gps.state === "unknown" ? "STATUS UNKNOWN" : state === "locked" ? "LOCKED · GPS" :
                state === "pending" ? "WAITING · GPS" : "ERROR · GPS",
            note: gps.reason,
            source: gpsSource(gps), detail: gps.reason + "; source: " + gpsSource(gps) +
                "; receiver lock does not certify PPS accuracy or continuous clock discipline" };
    }
    return { state: "pending", label: "STATUS UNKNOWN", source: sync || "Source not recorded",
        note: sync ? "Unrecognized time source: " + sync : "No NTP or GPS synchronization recorded",
        detail: sync ? "Time source not recognized: " + sync + "; current synchronization is unknown" :
            "No NTP or GPS synchronization is recorded; current synchronization is unknown" };
}

function current(gps, files, now) {
    files = files || fs;
    // One marker snapshot feeds both badges. GPS-only renders need no NTP I/O.
    const sync = trim(files.readfile(MARKER) || "");
    let ntp;
    let markerMtime;
    if (sync === "ntp") {
        try { ntp = json(files.readfile(STATUS)); } catch (e) { ntp = null; }
        markerMtime = files.stat(MARKER)?.mtime;
    }
    const result = classify(sync, gps, ntp, now === null ? clock(true)[0] : now, markerMtime);
    result.sync = sync;
    return result;
}

function record(mode, endpoint, stratum, files, now, wall) {
    files = files || fs;
    now = now === null ? clock(true)[0] : now;
    wall = wall === null ? time() : wall;
    if (mode !== "oneshot" && mode !== "daemon") return false;
    if (mode !== "daemon" && (type(endpoint) !== "string" || !length(endpoint))) return false;
    if (mode === "daemon" && endpoint !== null) return false;
    if (endpoint !== null && (type(endpoint) !== "string" || !length(endpoint) || length(endpoint) > 255 || match(endpoint, /[\r\n]/))) return false;
    const marker = files.stat(MARKER);
    if (!marker || trim(files.readfile(MARKER) || "") !== "ntp") return false;
    const status = { kind: "ntp", mode, endpoint, stratum: mode === "daemon" ? stratum : null,
        checked_uptime: now, sync_epoch: wall, marker_mtime: marker.mtime };
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
