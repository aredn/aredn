// Executes the complete root template with mocked device dependencies.
// Only imports and /app template paths are redirected by the Python runner.
import * as realfs from "fs";
import * as realboard from "aredn.board";
const input = json(realfs.readfile(ARGV[0]));
const calls = { radio: 0, configuration: 0, recv: 0, assets: 0 };
let offset = 0;
let output = "";
const shadow = "root:$1$fixture$accepted:0:0:0:0:0:0";
function asset(path, value) {
    if (index(path, "/app/") === 0) {
        calls.assets++;
        if (input.assetsUnavailable) { return null; }
    }
    return value;
}
const fakefs = {
    readfile: path => asset(path, ""), writefile: path => asset(path, true),
    symlink: (target, path) => asset(path, true), readlink: path => asset(path, "themes/light.css"),
    access: path => asset(path, false), unlink: path => asset(path, true), lsdir: path => asset(path, []),
    opendir: path => asset(path, {read: () => null, close: () => true}),
    open: path => {
        if (path !== "/etc/shadow") { die(`Unexpected file read: ${path}`); }
        if (input.missingShadow) { return null; }
        let read = false;
        return { read: () => { if (read) { return null; } read = true; return shadow; }, close: () => true };
    },
    popen: command => index(command, "/usr/bin/md5sum ") === 0 ?
        asset("/app/resource/fixture", {read: () => "0123456789abcdef  fixture\n", close: () => true}) : ({
        read: () => index(command, "'correct password+'")==length(command)-length("'correct password+'") ? "$1$fixture$accepted" : "$1$fixture$rejected",
        close: () => true
    })
};
const cursor = {
    get: () => null,
    set: () => { calls.configuration++; die("Unexpected config write"); },
    commit: () => { calls.configuration++; die("Unexpected config commit"); }
};
const fixture = {
    config: {application:"/app",preload:true,resourcehash:input.resourcehash,forceauth:false,authenable:true},
    board: {read: () => realboard.read(input.board)},
    fs: fakefs,
    log: {openlog: () => null},
    radios: {getCommonConfiguration: () => { calls.radio++; }},
    uci: {cursor: () => cursor},
    configuration: {shellEscape: s => "'"+s+"'", isConfigured: () => true},
    uhttpd: {
        send: (...args) => { output += join("",args); },
        recv: size => { calls.recv++; const part=substr(input.body || "",offset,size); offset+=length(part); return part; },
        urldecode: value => replace(value, /%[0-9a-fA-F]{2}/g, m => sprintf("%c", hex(substr(m, 1))))
    },
    math:{},ubus:{},zlib:{},lucihttp:{},nl80211:{},rtnl:{},hardware:{},lqm:{},network:{},units:{},messages:{},mesh:{},babel:{},constants:{}
};
const scope = {fixture:fixture, uhttpd:fixture.uhttpd, input:input};
render(input.template, scope);
printf("%J\n", {response:output,calls:calls});
