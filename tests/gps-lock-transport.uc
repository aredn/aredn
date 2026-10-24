// Use synthetic GPSD responses without opening a port or altering live telemetry.
let response;
let connected = true;
const connection = {
    setopt: () => true,
    send: (command) => length(command),
    recv: () => response,
    close: () => true
};
const scope = {
    socket: {
        connect: () => connected ? connection : null,
        poll: () => [ connection ],
        POLLIN: 1, POLLERR: 8, POLLHUP: 16
    }
};
const helper = require("aredn.gpslock");
function check(gps, message, expectedState, expectedSource, description) {
    response = sprintf("%J\n", message);
    const result = helper.read(gps, scope.socket);
    if (result.state !== expectedState || result.source.kind !== expectedSource || result.source.endpoint !== gps)
        die(`FAIL: ${description}: ${sprintf("%J", result)}\n`);
    print(`PASS: ${description}\n`);
}
const remote = "fe80::1234%br-dtdlink";
const tpv = { class: "TPV", mode: 3, time: "2026-10-23T22:00:00.000Z", device: "/dev/ttyACM0" };
check(remote, tpv, "locked", "network", "remote server's device path does not imply local GPS");
check("/dev/ttyACM0", tpv, "locked", "local", "attached receiver fix retains local provenance");
tpv.mode = 1;
check(remote, tpv, "pending", "network", "remote loss of lock stays explicitly network");
check(remote, { class: "DEVICES", devices: [] }, "error", "network", "remote receiver removal turns red and retains server");
connected = false;
check(remote, null, "error", "network", "network disconnection turns red and retains server");
print("5 GPS transport/source checks passed (mock socket; no node changes)\n");
