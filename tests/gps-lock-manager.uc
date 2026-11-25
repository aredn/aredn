// Execute the complete native task with all clock/config/service writes mocked.
import * as fs from "fs";
import * as math from "math";
const task = loadfile(getenv("GPS_TASK") || "files/usr/local/mgr/gps.uc", { raw_mode: true });
const candidate = getenv("GPS_BASELINE") !== "1";
const legacy = getenv("GPS_LEGACY") === "1";
const networkMarker = legacy ? "gps" : "network gps";
let checks = 0;
function check(value, message) {
    if (!value) die(`FAIL: ${message}\n`);
    checks++;
    print(`PASS: ${message}\n`);
}
function fixture(endpoint, timeEnabled, locationEnabled, failure) {
    const f = { now: 1000, delay: 0, reads: 0, polls: 0, finds: 0, dates: 0,
        commands: [], cache: {}, markers: {}, endpoint,
        timeEnabled, locationEnabled, failure, fix: { time: "2026-11-14 12:34:56", lat: 1, lon: 2 } };
    const scope = {
        clock: () => [ f.now, 0 ], math,
        loadfile: () => () => ({ POLL_SECONDS: 30,
            read: () => { f.polls++; if (f.failure === "read") die("synthetic observer read failure"); return { state: "locked" }; },
            write: value => { if (f.failure === "write") die("synthetic observer write failure"); f.cache = value; return true; } }),
        hardware: {
            GPSFind: () => { f.finds++; return f.endpoint; },
            GPSReadLLT: () => { f.reads++; return f.fix; }
        },
        uci: { cursor: () => ({
            get: (name, section, option) => option === "gps_enable" ?
                ((section === "@time[0]" ? f.timeEnabled : f.locationEnabled) ? "1" : "0") :
                option === "lat" ? "1" : option === "lon" ? "2" : null
        }) },
        fs: {
            writefile: (path, value) => { f.markers[path] = value; },
            readfile: path => f.markers[path],
            unlink: path => { delete f.markers[path]; if (path === "/tmp/gps-lock.json") f.cache = null; }
        },
        system: command => { push(f.commands, command); if (index(command, "/bin/date") === 0) f.dates++; return 0; },
        waitForTicks: (ticks, next) => { f.delay = ticks; if (next) f.next = next; return f.next; }
    };
    f.next = call(task, scope, scope);
    f.step = () => { const next = call(f.next, scope, scope); if (next) f.next = next; };
    return f;
}

const f = fixture("fe80::1234%br-dtdlink", true, true);
check(f.delay === 60, "native 60-second startup delay retained");
f.step(); f.step();
check(f.reads === 1 && f.dates === 1 && f.markers["/tmp/timesync"] === networkMarker,
    "native network GPS time synchronization retained");
check(f.markers["/tmp/locsync"] === (legacy ? null : networkMarker), "installed native location-marker behavior retained");
if (candidate) {
    f.now += 30; f.step();
    check(f.polls === 2 && f.reads === 1 && f.dates === 1 && f.delay === 30,
        "30-second health refresh does not synchronize time/location");
    f.now = 1599; f.step();
    check(f.reads === 1 && f.dates === 1, "no synchronization before the 600-second deadline");
}
f.now = 1600; f.step();
check(f.reads === 2 && f.dates === 2, "native 600-second synchronization cadence retained");
f.fix = null;
f.now = 2200; f.step();
check(f.markers["/tmp/timesync"] === (legacy ? "gps" : null) && f.markers["/tmp/locsync"] === null,
    legacy ? "legacy failed-read marker behavior remains unchanged" : "#3020 clears only this GPS source's failed time and location markers");
f.markers["/tmp/timesync"] = "ntp";
f.markers["/tmp/locsync"] = "gps";
f.now = 2800; f.step();
check(f.markers["/tmp/timesync"] === "ntp" && f.markers["/tmp/locsync"] === "gps",
    "#3020 preserves synchronization markers owned by another source");

const local = fixture("/dev/ttyACM0", true, false);
local.step(); local.step();
check(local.markers["/tmp/timesync"] === "gps", "native local GPS time marker retained");
check(length(local.commands) === 3 && index(local.commands[0], "nft insert rule") === 0 &&
    local.commands[1] === "/etc/init.d/gpsd restart", "local GPS daemon setup unchanged");

const disabled = fixture("/dev/ttyACM0", false, false);
disabled.step(); disabled.step();
check(disabled.finds === 1 && disabled.reads === 1 && disabled.polls === 0 && disabled.dates === 0 && length(disabled.commands) === 2,
    "disabled options preserve native discovery/setup without adding health probes or clock writes");
disabled.now += 600; disabled.step();
check(disabled.reads === 2 && disabled.polls === 0 && disabled.dates === 0 && disabled.delay === 600,
    "disabled options retain the native task cadence without new observations");

if (candidate) {
    f.timeEnabled = false; f.locationEnabled = false;
    const previousReads = f.reads;
    const previousPolls = f.polls;
    f.now += 30; f.step();
    check(f.reads === previousReads && f.polls === previousPolls && f.cache === null,
        "disabling both GPS options stops health probes and clears the badge cache");
    check(f.delay === 570, "disabled health observation does not add 30-second native-task wakeups");
    const location = fixture("fe80::1234%br-dtdlink", false, true);
    location.step(); location.step();
    check(location.reads === 1 && location.polls === 0 && location.delay === 600 && location.dates === 0,
        "location-only GPS retains its 10-minute cadence with no badge probes or clock writes");
    const absent = fixture(null, true, false);
    absent.step();
    check(absent.cache.state === "error" && absent.cache.reason === "GPS source not found" && absent.delay === 600,
        "absent source becomes an error without changing native discovery retry timing");
    for (let failure in [ "read", "write" ]) {
        const failed = fixture("fe80::1234%br-dtdlink", true, true, failure);
        check(failed.delay === 60, `${failure} observer failure preserves native startup delay`);
        failed.step(); failed.step();
        check(failed.reads === 1 && failed.dates === 1 && failed.cache === null,
            `${failure} observer failure cannot interrupt native synchronization or retain a false health cache`);
        failed.now += 30; failed.step();
        check(failed.reads === 1 && failed.dates === 1,
            `${failure} observer failure does not cause an extra native synchronization`);
        failed.now = 1600; failed.step();
        check(failed.reads === 2 && failed.dates === 2,
            `${failure} observer failure preserves the 600-second native synchronization cadence`);
    }
    const absentFailure = fixture(null, true, false, "write");
    absentFailure.step();
    check(absentFailure.finds === 1 && absentFailure.delay === 600,
        "error-cache write failure cannot interrupt native source-discovery retry");
}
print(`${checks} GPS manager checks passed (isolated ${candidate ? "candidate" : "baseline"})\n`);
