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
value = status.classify("ntp", null, ntp, 86501, 123);
check(value.state === "pending" && value.label === "LAST SYNC · NTP" && value.source === ntp.endpoint,
    "old NTP success retains its historical source without green status");
check(status.classify("ntp", null, ntp, 99, 123).source === "Source not recorded", "future/reboot-invalid NTP cache does not certify a source");
check(status.classify("ntp", null, ntp, 130, 124).source === "Source not recorded", "newer native marker invalidates an older source record");
check(status.classify("ntp", null, null, 130, 123).state === "pending", "historical marker alone is not confirmed current synchronization");
ntp.endpoint=null;
check(status.classify("ntp", null, ntp, 130, 123).state === "pending", "one-shot evidence without its actual server cannot turn green");
ntp.mode = "daemon"; ntp.endpoint = null; ntp.stratum = 2;
value = status.classify("ntp", null, ntp, 130, 123);
check(value.state === "locked" && index(value.source, "not exposed") >= 0, "daemon evidence never substitutes configured peers for its unknown selected peer");
ntp.stratum = 16;
check(status.classify("ntp", null, ntp, 130, 123).state === "error", "unsynchronized daemon stratum turns red");
ntp.stratum = 2;
check(status.classify("ntp", null, ntp, 1001, 123).state === "pending", "daemon evidence expires after its callback freshness window");
const gps = { state: "locked", reason: "GPS locked (3D fix)", source: { kind: "network", endpoint: "fe80::1234%br-dtdlink" } };
value = status.classify("gps", gps, null, 130, 123);
check(value.label === "LOCKED · GPS" && index(value.source, "NETWORK") === 0, "old gps marker can display known network provenance from selected connection");
gps.state = "pending";
check(status.classify("network gps", gps, null, 130, 123).label === "WAITING · GPS", "GPS no-fix does not read LOCKED");
gps.state = "error";
check(status.classify("gps", gps, null, 130, 123).state === "error", "historical GPS marker never overrides current receiver errors");
check(status.classify("gps", null, null, 130, 123).label === "LAST SYNC · GPS", "GPS disabled retains only historical synchronization evidence");
check(status.classify("", null, null, 130, 123).state === "error", "no synchronization evidence is explicit");
check(status.classify("manual", null, null, 130, 123).label === "TIME SOURCE UNKNOWN", "unrecognized native source is not relabeled NTP or GPS");

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
check(status.record("seed", "aredn.pool.ntp.org", null, files, 1000, 1794693134) && saved.checked_uptime === 900,
    "verified-log seed preserves actual marker age rather than deployment time");
check(!status.record("seed", "aredn.pool.ntp.org", null, files, 10, 1794693134), "seed older than this boot is rejected");
check(!status.record("seed", "aredn.pool.ntp.org", null, files, 1000, 1794693033), "future native marker cannot seed a sync");
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
print(`${count} time status/source checks passed\n`);
