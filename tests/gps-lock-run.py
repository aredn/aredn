#!/usr/bin/env python3
"""Isolated GPS badge checks; no real GPSD, services, clock or node changes."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def run(args, env=None):
    result = subprocess.run(args, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    if result.returncode:
        raise RuntimeError(f"{args[0]} exited {result.returncode}:\n{result.stdout}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ucode", default="ucode")
    parser.add_argument("--ucode-library", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "results/gps-status")
    parser.add_argument("--baseline-ref", default="3a7fdab83897ae2f9aebd42e052fe78ecac34a66")
    parser.add_argument("--playwright-module")
    parser.add_argument("--chromium", default="/usr/bin/chromium")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GPS_OUTPUT=str(output))
    native = [args.ucode]
    if args.ucode_library:
        native += ["-L", str(args.ucode_library.resolve() / "*.so")]
    native += ["-L", str(ROOT / "files/usr/share/ucode/*.uc")]
    summary = {}
    baseline = output / "baseline-gps.uc"
    baseline.write_text(run(["git", "show", f"{args.baseline_ref}:files/usr/local/mgr/gps.uc"]))
    cases = [("baseline-manager", "gps-lock-manager", dict(env, GPS_TASK=str(baseline), GPS_BASELINE="1"))]
    cases += [(name, name, env) for name in ("gps-lock", "gps-lock-transport", "gps-lock-manager", "time-status", "gps-lock-render")]
    for label, name, test_env in cases:
        log = run(native + [str(ROOT / "tests" / f"{name}.uc")], env=test_env)
        (output / f"{label}.log").write_text(log)
        count = sum(line.startswith("PASS:") for line in log.splitlines())
        assert count > 0, log
        summary[label] = {"checks_passed": count}
        print(f"PASS: {label}: {count} native checks")

    # Real native socket operations against private ephemeral loopback peers.
    # The wrapper changes only the port, leaving native framing/timeouts intact.
    probe = '''import * as socket from "socket";
const transport = {
    connect: (host, port, unused, timeout) => socket.connect(host, int(getenv("GPS_TEST_PORT")), null, timeout),
    poll: socket.poll, POLLIN: socket.POLLIN, POLLERR: socket.POLLERR, POLLHUP: socket.POLLHUP,
    SOL_SOCKET: socket.SOL_SOCKET, SO_SNDTIMEO: socket.SO_SNDTIMEO, MSG_DONTWAIT: socket.MSG_DONTWAIT
};
print(sprintf("%J", require("aredn.gpslock").read(getenv("GPS_TEST_SOURCE"), transport)));'''
    socket_cases = [
        (b'{"class":"VERSION"}\n{"class":"TPV","mode":3,"time":"2026-11-14T12:34:56Z","device":"/dev/ttyACM0"}\n', "locked", "/dev/ttyACM0"),
        (b'{"class":"TPV","mode":2,"time":"2026-11-14T12:34:56Z","device":"/dev/ttyACM0"}\n', "locked", "127.0.0.1"),
        (b'{"class":"TPV","mode":1}\n', "pending", "/dev/ttyACM0"),
        (b'{"class":"DEVICES","devices":[]}\n', "error", "/dev/ttyACM0"),
        (b'not-json\n', "error", "/dev/ttyACM0"),
        (b'', "error", "/dev/ttyACM0"),
        (None, "error", "/dev/ttyACM0"),
    ]
    socket_results = []
    for response, expected, source in socket_cases:
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(5)
            failures = []

            def serve():
                try:
                    connection, _ = listener.accept()
                    with connection:
                        connection.recv(4096)
                        if response is None:
                            time.sleep(1.8)
                        elif response:
                            split = len(response) // 2
                            connection.sendall(response[:split])
                            time.sleep(0.01)
                            connection.sendall(response[split:])
                except Exception as exc:
                    failures.append(str(exc))

            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            started = time.monotonic()
            value = json.loads(run(native + ["-e", probe], env=dict(env,
                GPS_TEST_PORT=str(listener.getsockname()[1]), GPS_TEST_SOURCE=source)))
            elapsed = time.monotonic() - started
            assert value["state"] == expected, value
            assert value["source"]["kind"] == ("local" if source.startswith("/dev/") else "network"), value
            assert elapsed < 2.5, elapsed
            thread.join(timeout=3)
            assert not thread.is_alive() and not failures, failures
            socket_results.append({"expected": expected, "source": value["source"]["kind"],
                                   "elapsed_seconds": round(elapsed, 3), "passed": True})
    summary["loopback_transport"] = {"cases_passed": len(socket_results), "cases": socket_results}
    print(f"PASS: {len(socket_results)} real native-socket GPSD fixtures")
    for name in ("user.css", "admin.css"):
        shutil.copy(ROOT / "files/app/resource/css" / name, output / name)
    shutil.copytree(ROOT / "files/app/resource/css/themes", output / "themes", dirs_exist_ok=True)
    (output / "htmx.min.js").write_bytes(gzip.decompress((ROOT / "files/app/resource/js/htmx.min.js.gz").read_bytes()))
    browser_env = dict(env, CHROMIUM=args.chromium)
    if args.playwright_module:
        browser_env["PLAYWRIGHT_MODULE"] = args.playwright_module
    browser_log = run(["node", str(ROOT / "tests/gps-lock-browser.cjs")], env=browser_env)
    (output / "browser.log").write_text(browser_log)
    print(browser_log.strip())
    summary["browser"] = json.loads((output / "browser-summary.json").read_text())
    run(["git", "diff", "--check"])
    paths = ["files/usr/local/mgr/gps.uc", "files/usr/share/ucode/aredn/gpslock.uc", "files/usr/share/ucode/aredn/timestatus.uc",
             "files/app/partial/health.ut", "files/app/resource/css/user.css", "files/etc/cron.daily/update-clock",
             "files/etc/hotplug.d/ntp/20-time-status", "files/usr/local/bin/aredn-time-status"]
    summary["provenance"] = {"base_commit": args.baseline_ref,
        "checkout_head": run(["git", "rev-parse", "HEAD"]).strip(),
        "source_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths},
        "physical_receiver_test": False, "live_node_changes": False, "firmware_build": False}
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
