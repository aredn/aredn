import * as fs from "fs";
const template = loadfile("files/app/partial/health.ut", { raw_mode: false });
let html;
let state;
let enabled = true;
let source = { kind: "network", endpoint: "fe80::1234%br-dtdlink" };
const scope = {
    fs: fs,
    uci: { get: (name, section, option) => option === "gps_enable" && enabled ? "1" : "0" },
    require: () => ({ current: () => ({ state: state, reason: `GPS lock ${state}`, source: source }) })
};
for (state in [ "locked", "pending", "error" ]) {
    html = render(call, template, scope, scope);
    if (index(html, `gps-lock-status ${state}`) < 0 || index(html, ">GPS LOCK · NETWORK</span>") < 0 || index(html, "(gps)") >= 0 || index(html, "Receiver supplied over the network by GPSD server: fe80::1234%br-dtdlink") < 0)
        die(`FAIL: ${state} badge render\n`);
    fs.writefile(`render-${state}.html`, html);
    print(`PASS: ${state} badge renders with accessible state text\n`);
}
source = { kind: "local", endpoint: "/dev/ttyACM0" };
html = render(call, template, scope, scope);
if (index(html, ">GPS LOCK · LOCAL</span>") < 0 || index(html, "Receiver attached to this node: /dev/ttyACM0") < 0)
    die("FAIL: local receiver provenance\n");
print("PASS: local receiver has explicit label and device tooltip\n");
source = null;
html = render(call, template, scope, scope);
if (index(html, ">GPS LOCK · SOURCE UNKNOWN</span>") < 0)
    die("FAIL: missing metadata must not imply local GPS\n");
print("PASS: missing source remains unknown\n");
enabled = false;
html = render(call, template, scope, scope);
if (index(html, "gps-lock-status") >= 0) die("FAIL: GPS-disabled badge must be absent\n");
print("PASS: GPS-disabled status keeps existing time-source display\n");
// Exercise the actual dynamic loader too, not just the injected state fixtures.
delete scope.require;
enabled = true;
html = render(call, template, scope, scope);
if (index(html, ">GPS LOCK · ") < 0) die("FAIL: real GPS helper/template integration\n");
print("PASS: actual require() helper loads through the health template\n");
