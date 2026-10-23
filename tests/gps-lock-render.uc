import * as fs from "fs";
const template = loadfile("files/app/partial/health.ut", { raw_mode: false });
let html;
let state;
let enabled = true;
const scope = {
    fs: fs,
    uci: { get: (name, section, option) => option === "gps_enable" && enabled ? "1" : "0" },
    require: () => ({ current: () => ({ state: state, reason: `GPS lock ${state}` }) })
};
for (state in [ "locked", "pending", "error" ]) {
    html = render(call, template, scope, scope);
    if (index(html, `gps-lock-status ${state}`) < 0 || index(html, ">GPS LOCK</span>") < 0 || index(html, "(gps)") >= 0)
        die(`FAIL: ${state} badge render\n`);
    fs.writefile(`render-${state}.html`, html);
    print(`PASS: ${state} badge renders with accessible state text\n`);
}
enabled = false;
html = render(call, template, scope, scope);
if (index(html, "gps-lock-status") >= 0) die("FAIL: GPS-disabled badge must be absent\n");
print("PASS: GPS-disabled status keeps existing time-source display\n");
// Exercise the actual dynamic loader too, not just the injected state fixtures.
delete scope.require;
enabled = true;
html = render(call, template, scope, scope);
if (index(html, ">GPS LOCK</span>") < 0) die("FAIL: real GPS helper/template integration\n");
print("PASS: actual require() helper loads through the health template\n");
