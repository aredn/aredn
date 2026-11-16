// Run with ucode -L /path/to/files/usr/share/ucode/*.uc tests/gps-lock.uc
const gpslock = require("aredn.gpslock");

let count = 0;
function check(value, message)
{
    if (!value) die(`FAIL: ${message}\n`);
    count++;
    print(`PASS: ${message}\n`);
}
const timestamp = "2026-10-23T20:00:00.000Z";
check(gpslock.classify({ class: "TPV", mode: 3, time: timestamp }).state === "locked", "3D receiver fix locks");
check(gpslock.classify({ class: "TPV", mode: 2, time: timestamp }).state === "locked", "2D receiver fix locks");
check(gpslock.classify({ class: "TPV", mode: 1, time: timestamp }).state === "pending", "time without a fix remains pending");
check(gpslock.classify({ class: "TPV", mode: 3 }).state === "pending", "fix without time remains pending");
check(gpslock.classify({ class: "TPV", mode: 3, status: 0, time: timestamp }).state === "pending", "explicit no-fix status cannot turn green");
check(gpslock.classify({ class: "TPV", mode: 3, status: 5, time: timestamp }).state === "pending", "dead reckoning is not satellite lock");
check(gpslock.classify({ class: "TPV", mode: 3, status: 8, time: timestamp }).state === "pending", "simulated fix is not satellite lock");
check(gpslock.classify({ class: "TPV", mode: "3", time: timestamp }).state === "pending", "malformed fix mode cannot turn green");
check(gpslock.classify({ class: "SKY" }).state === "error", "non-TPV data is rejected");
check(gpslock.classify(null).state === "error", "null receiver data is rejected");
check(gpslock.read(null).state === "error", "absent source is an error");

const fresh = { state: "locked", reason: "GPS locked (3D fix)", checked_uptime: 100 };
check(gpslock.validate(fresh, 130).state === "locked", "fresh lock is retained");
check(gpslock.validate(fresh, 191).state === "error", "stale lock turns red");
check(gpslock.validate(fresh, 99).state === "error", "future/reboot-invalid cache turns red");
check(gpslock.validate({ state: "locked", reason: "GPS locked" }, 130).state === "error", "cache without freshness is rejected");
check(gpslock.validate({ state: "unexpected", reason: "bad", checked_uptime: 100 }, 130).state === "error", "unknown state rejected");
check(gpslock.source("/dev/ttyACM0").kind === "local", "attached device is local");
const endpoint = "fe80::1234%br-dtdlink";
check(gpslock.source(endpoint).kind === "network", "DTD GPSD endpoint is network GPS");
check(gpslock.source(null).kind === "unknown", "missing source is unknown, not local");
check(gpslock.validate(fresh, 130).source.kind === "unknown", "legacy cache does not imply a local receiver");
fresh.source = { kind: "local", endpoint: endpoint };
check(gpslock.validate(fresh, 130).source.kind === "network", "connection endpoint determines source, not an inconsistent label");
const stale = gpslock.validate(fresh, 191);
check(stale.state === "error" && stale.source.kind === "network" && stale.source.endpoint === endpoint,
    "stale network fix turns red without losing provenance");
check(gpslock.classify({ class: "TPV", mode: 3, time: "2026-02-30T12:00:00Z" }).state === "pending",
    "invalid calendar dates cannot turn green");
check(gpslock.classify({ class: "TPV", mode: 3, time: "2026-11-14T12:00:00Z garbage" }).state === "pending",
    "malformed UTC timestamps cannot turn green");
check(gpslock.classify({ class: "TPV", mode: 3, time: "2028-02-29T12:00:00.123Z" }).state === "locked",
    "valid leap-day timestamps lock");
check(gpslock.validate({ state: "locked", reason: "GPS locked", checked_uptime: -1 }, 1).state === "error",
    "negative cache timestamps are invalid");
check(gpslock.current({ readfile: () => "not-json" }, 100).state === "error", "malformed cache turns red");
check(gpslock.current({ readfile: () => null }, 100).state === "pending", "missing startup cache is pending");
let renamed = false;
check(!gpslock.write({ state: "locked" }, {
    writefile: () => null, rename: () => { renamed = true; return true; }
}, 100) && !renamed, "failed cache write never replaces the previous cache");
let saved;
check(gpslock.write({ state: "pending" }, {
    writefile: (path, data) => { saved = json(data); return length(data); },
    rename: (from, to) => from === "/tmp/gps-lock.json.new" && to === "/tmp/gps-lock.json"
}, 100) && saved.checked_uptime === 100, "cache is timestamped and published by atomic rename");
print(`${count} GPS lock state/cache checks passed\n`);
