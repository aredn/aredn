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
let checks = 0;
function check(value, message) { if (!value) die(`FAIL: ${message}\n`); checks++; print(`PASS: ${message}\n`); }
const files = {
    readfile: path => path === "/tmp/timesync" ? sync : path === timestatus.STATUS && ntp ? sprintf("%J", ntp) : null,
    stat: () => ({mtime: 123})
};
const scope = {
    fs: {
        readfile: path => path === "/proc/uptime" ? "90061 0" : path === "/proc/loadavg" ? "0.01 0.02 0.03 1/10 1" :
            path === "/proc/meminfo" ? "MemAvailable: 128000 kB\nMemTotal: 256000 kB\n" : path === "/tmp/timesync" ? sync : null,
        popen: command => ({ read: () => index(command, "date") >= 0 ? "UTC\n" :
            "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/root 10000 1000 9000 10% /\n", close: () => {} })
    },
    localtime: () => ({ hour: 12, min: 34 }),
    uci: { get: (name, section, option) => option === "gps_enable" && enabled ? "1" : "0" },
    require: name => name === "aredn.gpslock" ? {
        current: () => gpslock.current({ readfile: () => sprintf("%J", cached) }, 1000)
    } : {current: gps => timestatus.current(gps, files, 1000)}
};
const network = { endpoint: "fe80::1234%br-dtdlink" };
const fresh = {state: "locked", reason: "GPS locked (3D fix)", checked_uptime:1000, source:network};
const cases = [
    {name:"gps-locked", state:"locked", label:"LOCKED · GPS", cache:fresh, sync:"network gps", source:"NETWORK · fe80::1234%br-dtdlink",
        description:"Green — GPS locked. Current 2D/3D satellite fix with valid UTC time. The selected source is a network GPS receiver, not a USB receiver attached to this node."},
    {name:"gps-waiting", state:"pending", label:"WAITING · GPS", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        cache:{state:"pending", reason:"Waiting for GPS satellite lock", checked_uptime:1000, source:network},
        description:"Yellow — Waiting for GPS. Source discovery, satellite lock or valid GPS time is still pending. A previous GPS sync is not evidence of a current receiver lock."},
    {name:"gps-error", state:"error", label:"ERROR · GPS", sync:"gps", source:"NETWORK · fe80::1234%br-dtdlink",
        cache:{state:"locked", reason:"GPS locked (3D fix)", checked_uptime:800, source:network},
        description:"Red — GPS error. This example has health data older than 90 seconds; missing receivers and connection/data failures also turn red. The selected source remains identified."},
    {name:"ntp-synced", state:"locked", label:"SYNCED · NTP", sync:"ntp", enabled:false, source:"aredn.pool.ntp.org",
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        description:"Green — NTP synchronized. Source is the actual server used by the last successful native update, not a configured-server guess. One-shot synchronization is not a continuous GPS-style lock."},
    {name:"ntp-last-sync", state:"pending", label:"LAST SYNC · NTP", sync:"ntp", enabled:false, source:"Source not recorded",
        description:"Yellow — NTP last sync only. The old native marker says NTP, but no matching server/time record exists. The UI does not invent a server or claim a current lock."},
    {name:"ntp-unsynced", state:"error", label:"UNSYNCED · NTP", sync:"ntp", enabled:false, source:"Selected peer not exposed by NTP daemon",
        ntp:{kind:"ntp",mode:"daemon",endpoint:null,stratum:16,checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        description:"Red — NTP daemon unsynchronized. Stratum 16 is not synchronized. BusyBox does not expose its selected peer through the native callback, so that source remains explicitly unknown."},
    {name:"ntp-and-gps", state:"locked", label:"SYNCED · NTP", sync:"ntp", cache:fresh, source:"aredn.pool.ntp.org",
        ntp:{kind:"ntp",mode:"oneshot",endpoint:"aredn.pool.ntp.org",checked_uptime:900,sync_epoch:1794693034,marker_mtime:123},
        description:"NTP last set the clock while a network GPS receiver is currently locked. Both facts are shown separately: GPS receiver lock does not establish which source last synchronized the system clock."},
    {name:"gps-unknown", state:"locked", label:"LOCKED · GPS", sync:"gps", source:"SOURCE UNKNOWN",
        cache:{state:"locked",reason:"GPS locked (3D fix)",checked_uptime:1000},
        description:"A valid receiver fix without source metadata remains SOURCE UNKNOWN. It is never silently labeled a local USB GPS."}
];
const healthTag = match(fs.readfile(root + "/app/partial/general.ut"), /<div id="health"[^>]*>/)[0];
function document(html, name, description) {
    return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AREDN time area — ${name}</title><style>${theme}\n${style}\nbody{overflow:auto;height:auto;padding:24px}article{max-width:720px;margin:auto;padding:24px;background:var(--default-bg-color);border:1px solid var(--hr-color);border-radius:8px}h1{font-size:22px;margin:0 0 8px}.fixture-note{font-size:13px;color:var(--subtitle-fg-color)}.caption{font-size:15px;line-height:1.55;border-top:1px solid var(--hr-color);padding-top:16px}#health{max-width:100%}</style></head><body class="authenticated"><article><h1>AREDN · Time and source</h1><div class="fixture-note">Controlled render fixture · not a physical receiver test</div><div id="general" class="section">${healthTag}${html}</div></div><p class="caption">${description}</p><div id="ctrl-modal"></div></article></body></html>`;
}
for (let test in cases) {
    enabled = test.enabled !== false; sync = test.sync; cached = test.cache; ntp = test.ntp;
    const html = render(call,template,scope,scope);
    check(index(html, `time-sync-status ${test.state}`) >= 0 && index(html, test.label) >= 0,
        `${test.name}: exact health template renders the correct state/label`);
    check(index(html, "Source: " + test.source) >= 0, `${test.name}: source is explicit`);
    fs.writefile(`${output}/${test.name}.html`,document(html,test.name,test.description));
    fs.writefile(`${output}/${test.name}-partial.html`,html);
}
enabled = true; sync = "gps"; ntp = null;
cached = {state:"locked",reason:"GPS locked (3D fix)",checked_uptime:1000,source:{endpoint:"/dev/ttyACM0"}};
let html=render(call,template,scope,scope);
check(index(html,"LOCAL · /dev/ttyACM0")>=0,"local GPS source is explicit");
cached.source.endpoint='remote"><script>evil()</script>';
html=render(call,template,scope,scope);
check(index(html,"<script>evil")<0 && index(html,"&quot;&gt;&lt;script&gt;")>=0,"GPS source and tooltip HTML are escaped");
enabled=false; sync="ntp"; ntp={kind:"ntp",mode:"oneshot",endpoint:'server"><script>evil()</script>',checked_uptime:900,marker_mtime:123};
html=render(call,template,scope,scope);
check(index(html,"<script>evil")<0 && index(html,"&quot;&gt;&lt;script&gt;")>=0,"NTP source and tooltip HTML are escaped");
check(index(html,"gps-lock-status")<0,"GPS-disabled time display still has NTP status without GPS probes");
enabled=true; cached={state:"error",reason:"GPS source not found",checked_uptime:1000};
html=render(call,template,scope,scope);
check(index(html,"gps-lock-status")<0 && index(html,"SYNCED · NTP")>=0,"working NTP is not accompanied by a GPS alarm when no GPS source was selected");
delete scope.require;
html=render(call,template,scope,scope);
check(index(html,"time-sync-status")>=0,"actual dynamic time-status helper loads through the exact template");
fs.writefile(`${output}/render-cases.json`,sprintf("%J",cases));
print(`${checks} time-area integrated render checks passed\n`);
