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
print(`${count} GPS lock state checks passed\n`);
