const status = require("aredn.timestatus");
let count = 0;
function check(value, message) { if (!value) die(`FAIL: ${message}\n`); count++; print(`PASS: ${message}\n`); }
const ntp = { kind: "ntp", mode: "oneshot", endpoint: "aredn.pool.ntp.org", checked_uptime: 100,
    sync_epoch: 1794693034, marker_mtime: 123 };
let value = status.classify("ntp", null, ntp, 130, 123);
check(value.state === "locked" && value.label === "SYNCED · NTP" && value.source === ntp.endpoint,
    "confirmed one-shot sync shows NTP and the actually used server");
check(index(value.detail, "one-shot") >= 0 && index(value.detail, "not a continuous receiver lock") >= 0,
    "one-shot synchronization is not presented as a continuous lock");
check(value.sourceDisplay === ntp.endpoint && index(value.note, "IP not recorded") < 0,
    "successful hostname target is a valid source without a missing-IP warning");
for (let endpoint in ["192.0.2.123", "2001:db8::123", "fe80::123%br-dtdlink"]) {
    ntp.endpoint = endpoint;
    value = status.classify("ntp", null, ntp, 130, 123);
    check(value.sourceDisplay === endpoint && index(value.note, "IP not recorded") < 0,
        `successful numeric NTP target displays its recorded address: ${endpoint}`);
}
ntp.endpoint = "ntp.example:123";
check(status.classify("ntp", null, ntp, 130, 123).sourceDisplay === ntp.endpoint,
    "hostname endpoint is displayed unchanged without resolving an IP");
ntp.endpoint = "aredn.pool.ntp.org";
value = status.classify("ntp", null, ntp, 86501, 123);
check(value.state === "pending" && value.label === "STATUS UNKNOWN" && value.sourceDisplay === ntp.endpoint,
    "old NTP success retains its historical source without green status");
check(index(value.note, "Last sync: NTP") >= 0 && index(value.note, "UTC") >= 0 &&
    index(value.note, "1d ago") >= 0 && index(value.note, "Status old") >= 0,
    "historical NTP source, timestamp and age remain available for the visible detail line");
check(status.classify("ntp", null, ntp, 99, 123).source === "Source not recorded", "future/reboot-invalid NTP cache does not certify a source");
check(status.classify("ntp", null, ntp, 130, 124).source === "Source not recorded", "newer native marker invalidates an older source record");
check(status.classify("ntp", null, null, 130, 123).state === "pending", "historical marker alone is not confirmed current synchronization");
check(index(status.classify("ntp", null, null, 130, 123).note, "Time and source not recorded") >= 0,
    "marker-only synchronization explains missing details without inventing a timestamp");
ntp.endpoint=null;
check(status.classify("ntp", null, ntp, 130, 123).state === "pending", "one-shot evidence without its actual server cannot turn green");
ntp.mode = "daemon"; ntp.endpoint = null; ntp.stratum = 2;
value = status.classify("ntp", null, ntp, 130, 123);
check(value.state === "locked" && index(value.source, "not exposed") >= 0, "daemon evidence never substitutes configured peers for its unknown selected peer");
check(value.sourceDisplay === "Unknown" && index(value.note, "Source not recorded") >= 0,
    "daemon source remains unknown when the callback exposes neither IP nor hostname");
ntp.stratum = 16;
check(status.classify("ntp", null, ntp, 130, 123).label === "UNSYNCED · NTP", "fresh unsynchronized daemon stratum remains explicit");
value = status.classify("ntp", null, ntp, 1001, 123);
check(value.state === "pending" && value.label === "STATUS UNKNOWN" && index(value.note, "unsynchronized") >= 0 &&
    index(value.note, "Status old") >= 0 && index(value.note, "Last sync") < 0,
    "expired daemon error is historical, not a current fault or a claimed successful sync");
ntp.stratum = 2;
check(status.classify("ntp", null, ntp, 1001, 123).state === "pending", "daemon evidence expires after its callback freshness window");
ntp.endpoint = "guessed-peer.example";
check(status.classify("ntp", null, ntp, 130, 123).source === "Source not recorded",
    "daemon metadata cannot certify a peer that the native callback does not expose");
ntp.endpoint = null;
const gps = { state: "locked", reason: "GPS locked (3D fix)", source: { kind: "network", endpoint: "fe80::1234%br-dtdlink" } };
value = status.classify("gps", gps, null, 130, 123);
check(value.label === "LOCKED · GPS" && index(value.source, "NETWORK") === 0, "old gps marker can display known network provenance from selected connection");
check(value.sourceDisplay === "GPS" && index(value.note, "NETWORK · fe80::1234%br-dtdlink") === 0,
    "GPS source type is explicit while receiver endpoint remains in the visible detail line");
gps.state = "pending";
check(status.classify("network gps", gps, null, 130, 123).label === "WAITING · GPS", "GPS no-fix does not read LOCKED");
gps.state = "error";
check(status.classify("gps", gps, null, 130, 123).state === "error", "historical GPS marker never overrides current receiver errors");
value = status.classify("gps", null, null, 130, 123);
check(value.label === "STATUS UNKNOWN" && index(value.note, "Last sync: GPS") >= 0,
    "GPS disabled retains historical synchronization in the visible detail line");
value = status.classify("", null, null, 130, 123);
check(value.state === "pending" && value.label === "STATUS UNKNOWN" && index(value.note, "No NTP or GPS synchronization recorded") >= 0,
    "absence of synchronization evidence is unknown with an explicit detail, not a current fault");
value = status.classify("manual", null, null, 130, 123);
check(value.label === "STATUS UNKNOWN" && value.source === "manual" && index(value.note, "Unrecognized time source: manual") >= 0,
    "unrecognized native source is explained without relabeling it NTP or GPS");
gps.state = "unknown"; gps.reason = "GPS status is stale";
value = status.classify("gps", gps, null, 130, 123);
check(value.state === "pending" && value.label === "STATUS UNKNOWN" && index(value.note, "stale") >= 0,
    "unavailable GPS observation maps to unknown without erasing its diagnostic");

let marker = "ntp";
let renamed = false;
let saved;
let path;
const files = {
    readfile: () => marker, stat: () => ({ mtime: 1794693034 }), readlink: () => "123",
    writefile: (name, data) => { path = name; saved = json(data); return length(data); },
    rename: () => { renamed = true; return true; }, unlink: () => {}
};
check(status.record("oneshot", "aredn.pool.ntp.org", null, files, 1000, 1794693134) && renamed &&
    saved.endpoint === "aredn.pool.ntp.org" && saved.checked_uptime === 1000 && index(path, ".123.new") >= 0,
    "successful source recorder uses process-specific atomic publication");
check(!status.record("seed", "aredn.pool.ntp.org", null, files, 1000, 1794693134),
    "unused manual seed mode is not part of the native observer API");
check(!status.record("daemon", "guessed-peer.example", 2, files, 1000, 1794693134),
    "daemon recorder rejects an invented selected peer");
marker = "gps"; renamed = false;
check(!status.record("oneshot", "example.org", null, files, 1000, 1794693134) && !renamed,
    "recorder never fabricates an NTP marker or replaces GPS ownership");
marker = "ntp";
check(!status.record("oneshot", "evil\nname", null, files, 1000, 1794693134), "line-breaking source metadata is rejected");
check(!status.record("oneshot", null, null, files, 1000, 1794693134), "recorder requires an actual server for one-shot NTP");
files.writefile = () => 1;
check(!status.record("oneshot", "example.org", null, files, 1000, 1794693134), "short cache writes are not published");
check(status.current(null, {readfile: path => path === status.STATUS ? "bad-json" : "ntp", stat: () => ({mtime:123})}, 130).state === "pending",
    "malformed NTP cache degrades to unknown-source historical state");
let reads = [];
let stats = 0;
value = status.current(gps, {
    readfile: path => { push(reads, path); return "network gps"; },
    stat: () => { stats++; return {mtime:123}; }
}, 130);
check(value.sync === "network gps" && length(reads) === 1 && reads[0] === "/tmp/timesync" && stats === 0,
    "GPS-only rendering reads one marker snapshot and no NTP metadata or stat");
reads = []; stats = 0;
value = status.current(null, {
    readfile: path => { push(reads, path); return path === "/tmp/timesync" ? "ntp" : null; },
    stat: () => { stats++; return {mtime:123}; }
}, 130);
check(value.sync === "ntp" && length(reads) === 2 && stats === 1,
    "NTP rendering reads the marker only once and shares its identity with both badges");
print(`${count} time status/source checks passed\n`);
