// AI-assisted regression tests for AREDN issue #2963. No live node access.
import * as fs from "fs";
import * as board from "aredn.board";

const dir = ARGV[0];
const valid = { model: { id: "mikrotik,hap-ac3", name: "MikroTik hAP ac3" }, network: {}, wlan: {} };
const good = sprintf("%J\n", valid);
const results = [];
function check(name, ok) {
    push(results, { name: name, pass: !!ok });
    if (!ok) { warn(`FAIL: ${name}\n`); }
}
let zeros = "";
for (let i = 0; i < 1436; i++) { zeros += "\x00"; }
const invalid = [
    [ "reported_zero_filled", zeros ],
    [ "empty", "" ], [ "truncated", "{\"model\":" ],
    [ "null", "null" ], [ "array", "[]" ], [ "number", "1" ],
    [ "empty_object", "{}" ], [ "missing_name", '{"model":{"id":"test"}}' ],
    [ "invalid_wlan", '{"model":{"id":"test","name":"test"},"wlan":[]}' ],
    [ "invalid_radio_entry", '{"model":{"id":"test","name":"test"},"wlan":{"phy0":1}}' ]
];
for (let item in invalid) {
    fs.writefile(`${dir}/input.json`, item[1]);
    check(`reject_${item[0]}`, !!board.read(`${dir}/input.json`).error);
}
check("reject_missing", !!board.read(`${dir}/missing.json`).error);
fs.writefile(`${dir}/input.json`, good);
check("read_valid", board.read(`${dir}/input.json`).data.model.id === valid.model.id);
fs.writefile(`${dir}/input.json`, sprintf("%J", {model:valid.model}));
check("optional_network_and_wlan", !board.read(`${dir}/input.json`).error);

let detected = 0;
const options = {
    path: `${dir}/board.json`, identity: valid.model.id,
    lockfile: `${dir}/board.lock`, evidence: `${dir}/invalid.json`,
    detect: path => { detected++; return fs.writefile(path, good) === length(good); }
};
fs.writefile(options.path, good);
let result = board.recover(options);
check("healthy_is_read_only", result.status === "healthy" && detected === 0 &&
    !fs.stat(options.evidence) && fs.readfile(options.path) === good);
for (let item in [invalid[0], invalid[2]]) {
    fs.writefile(options.path, item[1]);
    result = board.recover(options);
    check(`recover_${item[0]}`, result.status === "recovered" &&
        !board.read(options.path).error && fs.readfile(options.evidence) === item[1]);
}
fs.unlink(options.path);
check("recover_missing", board.recover(options).status === "recovered");
const damaged = invalid[0][1];
for (let item in [
    ["detector_failure", {detect: () => false}],
    ["invalid_generated", {detect: path => { fs.writefile(path, "{}"); return true; }}],
    ["wrong_device", {identity: "different,board"}],
    ["commit_failure", {commit: () => ({status:"failed",error:"injected commit failure"})}]
]) {
    fs.writefile(options.path, damaged);
    result = board.recover({...options,...item[1]});
    check(`${item[0]}_preserves_original`, result.status === "failed" && fs.readfile(options.path) === damaged);
}
const held = fs.open(options.lockfile,"w");
held.lock("x");
detected = 0;
result = board.recover(options);
check("competing_update_is_not_overwritten", result.status === "failed" && detected === 0 && fs.readfile(options.path) === damaged);
held.close();
check("temporary_directories_cleaned", !length(fs.glob(`${dir}/.board-recovery-*`)));
printf("%J\n",results);
exit(length(filter(results, r => !r.pass)) ? 1 : 0);
