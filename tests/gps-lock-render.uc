// Exact current-main or DEV-1 health template, real GPS/NTP cache validators.
import * as fs from "fs";
const gpslock = require("aredn.gpslock");
const timestatus = require("aredn.timestatus");
const output = getenv("GPS_OUTPUT");
const root = getenv("TIME_ROOT") || "files";
const template = loadfile(root + "/app/partial/health.ut", { raw_mode: false });
const style = fs.readfile(root + "/app/resource/css/user.css");
const theme = fs.readfile(root + "/app/resource/css/themes/light.css");
let enabled = true;
let sync = "network gps";
let cached;
let ntp;
let now = 1000;
let checks = 0;
let markerReads = 0;
function check(value, message) { if (!value) die(`FAIL: ${message}\n`); checks++; print(`PASS: ${message}\n`); }
const files = {
    readfile: path => { if (path === "/tmp/timesync") { markerReads++; return sync; }
        return path === timestatus.STATUS && ntp ? sprintf("%J", ntp) : null; },
    stat: () => ({mtime: 123})
};
const scope = {
    fs: {
        readfile: path => path === "/proc/uptime" ? "90061 0" : path === "/proc/loadavg" ? "0.01 0.02 0.03 1/10 1" :
            path === "/proc/meminfo" ? "MemAvailable: 128000 kB\nMemTotal: 256000 kB\n" :
            path === "/tmp/timesync" ? (markerReads++, sync) : null,
        popen: command => ({ read: () => index(command, "date") >= 0 ? "UTC\n" :
            "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/root 10000 1000 9000 10% /\n", close: () => {} })
    },
    localtime: () => ({ hour: 12, min: 34 }),
    uci: { get: (name, section, option) => option === "gps_enable" && enabled ? "1" : "0" },
    require: name => name === "aredn.gpslock" ? {
        current: () => gpslock.current({ readfile: () => cached ? sprintf("%J", cached) : null }, now)
    } : {current: gps => timestatus.current(gps, files, now)}
};
const network = { endpoint: "fe80::1234%br-dtdlink" };
const fresh = {state: "locked", reason: "GPS locked (3D fix)", checked_uptime:1000, source:network};
const cases = [
    {name:"gps-locked", state:"locked", label:"LOCKED · GPS", cache:fresh, sync:"network gps", source:"NETWORK · fe80::1234%br-dtdlink",
        details:["GPS locked (3D fix)"],
        description:"Green — GPS locked. Current 2D/3D satellite fix with valid UTC time. The selected source is a network GPS receiver, not a USB receiver attached to this node."},
    {name:"gps-waiting", state:"pending", label:"WAITING · GPS", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        details:["Waiting for GPS satellite lock"],
        cache:{state:"pending", reason:"Waiting for GPS satellite lock", checked_uptime:1000, source:network},
        description:"Yellow — Waiting for GPS. Source discovery, satellite lock or valid GPS time is still pending. A previous GPS sync is not evidence of a current receiver lock."},
    {name:"gps-error", state:"error", label:"ERROR · GPS", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        cache:{state:"error", reason:"GPS receiver connection failed", checked_uptime:1000, source:network},
        details:["GPS receiver connection failed"],
        description:"Red — A fresh GPS receiver connection failure. The visible detail line explains the fault, and the selected source remains identified."},
    {name:"gps-stale", state:"pending", label:"STATUS UNKNOWN", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        cache:{state:"locked", reason:"GPS locked (3D fix)", checked_uptime:800, source:network},
        details:["stale", "last report: GPS locked", "200 seconds"],
        description:"Yellow — Current receiver health is unknown. The visible detail line retains the previous fix and the age of the expired observation; it is neither a current lock nor a receiver fault."},
    {name:"gps-error-old", state:"pending", label:"STATUS UNKNOWN", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        cache:{state:"error", reason:"GPS receiver connection failed", checked_uptime:800, source:network},
        details:["stale", "last report: GPS receiver connection failed", "200 seconds"],
        description:"Yellow — An expired receiver failure remains historical in the detail line, not a current red fault."},
    {name:"gps-future", state:"pending", label:"STATUS UNKNOWN", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        cache:{state:"locked", reason:"GPS locked (3D fix)", checked_uptime:1001, source:network},
        details:["timestamp is in the future"],
        description:"Yellow — A future or reboot-invalid receiver observation cannot establish current receiver health."},
    {name:"gps-invalid", state:"pending", label:"STATUS UNKNOWN", sync:"gps", source:"SOURCE UNKNOWN", cache:{},
        details:["Invalid GPS status"],
        description:"Yellow — Invalid observation metadata is not evidence that the physical receiver has failed."},
    {name:"gps-last-sync", state:"pending", label:"STATUS UNKNOWN", sync:"gps", enabled:false, source:"Source not recorded",
        details:["Last sync: GPS", "Time not recorded", "Receiver health unavailable"],
        description:"Yellow — Only previous GPS synchronization is recorded. The visible detail line explains that current receiver health and the last-sync time are unavailable."},
    {name:"gps-startup", state:"pending", label:"WAITING · GPS", sync:"", source:"SOURCE UNKNOWN",
        details:["Waiting for GPS status"],
        description:"Yellow — GPS observation startup is still pending; no lock or fault has been observed."},
    {name:"ntp-synced", state:"locked", label:"SYNCED · NTP", sync:"ntp", enabled:false, source:"aredn.pool.ntp.org",
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "UTC", "1m ago"],
        description:"Green — NTP synchronized. Source is the actual server used by the last successful native update, not a configured-server guess. One-shot synchronization is not a continuous GPS-style lock."},
    {name:"ntp-last-sync", state:"pending", label:"STATUS UNKNOWN", sync:"ntp", enabled:false, source:"Source not recorded",
        details:["Last sync: NTP", "Time and source not recorded"],
        description:"Yellow — Current status is unknown. The visible detail line preserves the old NTP marker without inventing a server, timestamp, or current synchronization."},
    {name:"ntp-success-old", state:"pending", label:"STATUS UNKNOWN", sync:"ntp", enabled:false, source:"aredn.pool.ntp.org", now:90000,
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "UTC", "1d ago", "Status old"],
        description:"Yellow — Last successful NTP synchronization is historical. The target, timestamp and age remain visible without claiming current synchronization."},
    {name:"ntp-unsynced", state:"error", label:"UNSYNCED · NTP", sync:"ntp", enabled:false, source:"Selected peer not exposed by NTP daemon",
        ntp:{kind:"ntp",mode:"daemon",endpoint:null,stratum:16,checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last report: NTP unsynchronized", "UTC", "1m ago"],
        description:"Red — NTP daemon unsynchronized. Stratum 16 is not synchronized. BusyBox does not expose its selected peer through the native callback, so that source remains explicitly unknown."},
    {name:"ntp-status-old", state:"pending", label:"STATUS UNKNOWN", sync:"ntp", enabled:false, source:"Selected peer not exposed by NTP daemon",
        ntp:{kind:"ntp",mode:"daemon",endpoint:null,stratum:16,checked_uptime:0,sync_epoch:1794693034,marker_mtime:123},
        details:["Last report: NTP unsynchronized", "16m ago", "Status old"],
        description:"Yellow — The daemon previously reported unsynchronized, but that report is now too old to certify its current state. This is not a current red alarm or a claimed successful synchronization."},
    {name:"ntp-peer-unknown", state:"pending", label:"STATUS UNKNOWN", sync:"ntp", enabled:false, source:"Source not recorded",
        ntp:{kind:"ntp",mode:"daemon",endpoint:"guessed-peer.example",stratum:2,checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "Time and source not recorded"],
        description:"Yellow — Inconsistent daemon source metadata is not trusted. A peer that the native callback never exposed cannot be presented as the actual successful server."},
    {name:"ntp-and-gps", state:"locked", label:"SYNCED · NTP", sync:"ntp", cache:fresh, source:"aredn.pool.ntp.org",
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "UTC"], gpsLabel:"GPS LOCK · NETWORK", gpsState:"locked", gpsDetails:["GPS locked (3D fix)", "fe80::1234%br-dtdlink"],
        description:"NTP last set the clock while a network GPS receiver is currently locked. Both facts are shown separately: GPS receiver lock does not establish which source last synchronized the system clock."},
    {name:"ntp-and-gps-stale", state:"locked", label:"SYNCED · NTP", sync:"ntp", source:"aredn.pool.ntp.org",
        cache:{state:"locked",reason:"GPS locked (3D fix)",checked_uptime:800,source:network},
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "UTC"], gpsLabel:"GPS UNKNOWN · NETWORK", gpsState:"pending", gpsDetails:["stale", "200 seconds"],
        description:"NTP synchronization remains independent of expired GPS data. The receiver badge says UNKNOWN, with observation age shown in a visible detail line."},
    {name:"ntp-and-gps-error", state:"locked", label:"SYNCED · NTP", sync:"ntp", source:"aredn.pool.ntp.org",
        cache:{state:"error",reason:"GPS receiver connection failed",checked_uptime:1000,source:network},
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "UTC"], gpsLabel:"GPS ERROR · NETWORK", gpsState:"error", gpsDetails:["GPS receiver connection failed"],
        description:"NTP synchronized while the selected GPS receiver has a fresh connection failure. The two observations remain separate."},
    {name:"ntp-and-gps-wait", state:"locked", label:"SYNCED · NTP", sync:"ntp", source:"aredn.pool.ntp.org",
        cache:{state:"pending",reason:"Waiting for GPS time",checked_uptime:1000,source:network},
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        details:["Last sync: NTP", "UTC"], gpsLabel:"GPS WAIT · NETWORK", gpsState:"pending", gpsDetails:["Waiting for GPS time"],
        description:"NTP synchronized while the selected receiver waits for valid GPS time. The receiver is not represented as locked."},
    {name:"no-sync", state:"pending", label:"STATUS UNKNOWN", sync:"", enabled:false, source:"Source not recorded",
        details:["No NTP or GPS synchronization recorded"],
        description:"Yellow — No synchronization evidence is recorded. The visible detail line makes this different from a known current failure."},
    {name:"source-unrecognized", state:"pending", label:"STATUS UNKNOWN", sync:"manual", enabled:false, source:"manual",
        details:["Unrecognized time source: manual"],
        description:"Yellow — An unrecognized recorded source remains visible in the detail line; it is not guessed to be NTP or GPS."},
    {name:"gps-unknown", state:"locked", label:"LOCKED · GPS", sync:"gps", source:"SOURCE UNKNOWN",
        cache:{state:"locked",reason:"GPS locked (3D fix)",checked_uptime:1000},
        details:["GPS locked (3D fix)"],
        description:"A valid receiver fix without source metadata remains SOURCE UNKNOWN. It is never silently labeled a local USB GPS."}
];
const healthTag = match(fs.readfile(root + "/app/partial/general.ut"), /<div id="health"[^>]*>/)[0];
function document(html, name, description) {
    return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AREDN time area — ${name}</title><style>${theme}\n${style}\nbody{overflow:auto;height:auto;padding:24px}article{max-width:720px;margin:auto;padding:24px;background:var(--default-bg-color);border:1px solid var(--hr-color);border-radius:8px}h1{font-size:22px;margin:0 0 8px}.fixture-note{font-size:13px;color:var(--subtitle-fg-color)}.caption{font-size:15px;line-height:1.55;border-top:1px solid var(--hr-color);padding-top:16px}#health{max-width:100%}</style></head><body class="authenticated"><article><h1>AREDN · Time and source</h1><div class="fixture-note">Controlled render fixture · not a physical receiver test</div><div id="general" class="section">${healthTag}${html}</div></div><p class="caption">${description}</p><div id="ctrl-modal"></div></article></body></html>`;
}
for (let test in cases) {
    enabled = test.enabled !== false; sync = test.sync; cached = test.cache; ntp = test.ntp; now = test.now || 1000;
    markerReads = 0;
    const html = render(call,template,scope,scope);
    check(index(html, `time-sync-status ${test.state}`) >= 0 && index(html, test.label) >= 0,
        `${test.name}: exact health template renders the correct state/label`);
    check(index(html, "Source: " + test.source) >= 0, `${test.name}: source is explicit`);
    check(index(html, 'class="time-sync-detail"') >= 0 && index(html, test.details[0]) >= 0,
        `${test.name}: diagnostic detail line is rendered`);
    check(markerReads === 1, `${test.name}: both badges share one native-marker snapshot`);
    fs.writefile(`${output}/${test.name}.html`,document(html,test.name,test.description));
    fs.writefile(`${output}/${test.name}-partial.html`,html);
}
enabled = true; sync = "gps"; ntp = null; now = 1000;
cached = {state:"locked",reason:"GPS locked (3D fix)",checked_uptime:1000,source:{endpoint:"/dev/ttyACM0"}};
let html=render(call,template,scope,scope);
check(index(html,"LOCAL · /dev/ttyACM0")>=0,"local GPS source is explicit");
cached.source.endpoint='remote"><script>evil()</script>';
html=render(call,template,scope,scope);
check(index(html,"<script>evil")<0 && index(html,"&quot;&gt;&lt;script&gt;")>=0,"GPS source and tooltip HTML are escaped");
enabled=false; sync="ntp"; ntp={kind:"ntp",mode:"oneshot",endpoint:'server"><script>evil()</script>',checked_uptime:900,marker_mtime:123};
html=render(call,template,scope,scope);
check(index(html,"<script>evil")<0 && index(html,"&quot;&gt;&lt;script&gt;")>=0,"NTP source and tooltip HTML are escaped");
sync='manual"><script>evil()</script>';
html=render(call,template,scope,scope);
check(index(html,"<script>evil")<0 && index(html,'<div class="time-sync-detail">Unrecognized time source: manual&quot;&gt;&lt;script&gt;')>=0,
    "visible detail-line text is HTML escaped");
sync="ntp";
check(index(html,"gps-lock-status")<0,"GPS-disabled time display still has NTP status without GPS probes");
enabled=true; cached={state:"error",reason:"GPS source not found",checked_uptime:1000};
html=render(call,template,scope,scope);
check(index(html,"gps-lock-status")<0 && index(html,"SYNCED · NTP")>=0,"working NTP is not accompanied by a GPS alarm when no GPS source was selected");
delete scope.require;
html=render(call,template,scope,scope);
check(index(html,"time-sync-status")>=0,"actual dynamic time-status helper loads through the exact template");
fs.writefile(`${output}/render-cases.json`,sprintf("%J",cases));
print(`${checks} time-area integrated render checks passed\n`);
