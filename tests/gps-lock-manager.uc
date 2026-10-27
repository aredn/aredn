import * as fs from "fs";
let now = 1000;
let next;
let delay;
let reads = 0;
let polls = 0;
let sets = 0;
let enabled = true;
const scope = {
    clock: () => [ now, 0 ],
    loadfile: () => () => ({ POLL_SECONDS: 30, read: () => { polls++; return { state: "locked" }; }, write: () => {} }),
    hardware: {
        GPSFind: () => "test-network-source",
        GPSReadLLT: () => { reads++; return { time: "2026-10-23 20:00:00" }; }
    },
    uci: { cursor: () => ({ get: (name, section, option) => section === "@time[0]" && enabled ? "1" : "0" }) },
    fs: { writefile: () => {} },
    system: () => { sets++; return 0; },
    waitForTicks: (ticks, fn) => { delay = ticks; if (fn) next = fn; return next; }
};
function check(value, message) {
    if (!value) die(`FAIL: ${message}\n`);
    print(`PASS: ${message}\n`);
}
function step() {
    const result = call(next, scope, scope);
    if (result) next = result;
}
const task = loadfile("files/usr/local/mgr/gps.uc", { raw_mode: true });
next = call(task, scope, scope);
check(delay === 60, "original startup delay retained");
step(); // discover
step(); // initial sync
check(sets === 1 && reads === 1 && polls === 1, "initial sync and status read");
now += 30;
step();
check(polls === 2 && sets === 1 && reads === 1 && delay === 30, "health refresh does not set clock");
now += 569;
step();
check(sets === 1 && reads === 1, "clock is not updated before 600 seconds");
now++;
step();
check(sets === 2 && reads === 2, "original 600-second sync cadence retained");
enabled = false;
const prior = polls;
now += 30;
step();
check(polls === prior, "no added health polling when GPS time is disabled");
print("6 GPS manager checks passed (mock clock and hardware; no node changes)\n");
