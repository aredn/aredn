#!/usr/bin/env python3
"""Run native update-clock branches with private filesystem and fake NTP peers."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, default=ROOT / "files/etc/cron.daily/update-clock")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--baseline-ref", default="3a7fdab83897ae2f9aebd42e052fe78ecac34a66")
    args = parser.parse_args()
    baseline = args.baseline.read_text() if args.baseline else subprocess.check_output(
        ["git", "show", f"{args.baseline_ref}:files/etc/cron.daily/update-clock"], cwd=ROOT, text=True)
    cases = [
        ("configured", {}, "ntp", "oneshot ntp-good.example"),
        ("advertised", {"MOCK_FALLBACK": "1"}, "ntp", "oneshot fallback-good.example"),
        ("daemon", {"MOCK_DAEMON": "1"}, "ntp", "daemon 2"),
        ("daemon-unsync", {"MOCK_DAEMON": "1", "MOCK_STRATUM": "16"}, "ntp", "oneshot ntp-good.example"),
        ("all-failed", {"MOCK_ALL_FAIL": "1"}, None, ""),
        ("recorder-failed", {"MOCK_RECORD_FAIL": "1"}, "ntp", "oneshot ntp-good.example"),
    ]
    for label, source in [("baseline", baseline), ("candidate", args.candidate.read_text())]:
        for name, settings, expected_marker, expected_record in cases:
            with tempfile.TemporaryDirectory(prefix="time-ui-ntp-") as temporary:
                temp = Path(temporary)
                bins = temp / "bin"
                bins.mkdir()
                scripts = {
                    "pidof": '#!/bin/sh\n[ "$MOCK_DAEMON" = 1 ] && { echo 123; exit 0; }; exit 1\n',
                    "uci": '#!/bin/sh\n[ "$MOCK_FALLBACK" = 1 ] || echo "ntp-bad.example ntp-good.example"\nexit 0\n',
                    "ntpd": '#!/bin/sh\nfor ntp_test_arg do :; done\n[ "$MOCK_ALL_FAIL" = 1 ] && exit 1\ncase "$ntp_test_arg" in ntp-good.example|fallback-good.example) exit 0;; *) exit 1;; esac\n',
                    "logger": '#!/bin/sh\nexit 0\n',
                    "recorder": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_RECORD"\n[ "$MOCK_RECORD_FAIL" = 1 ] && exit 7\nexit 0\n',
                }
                for executable, body in scripts.items():
                    path = bins / executable
                    path.write_text(body)
                    path.chmod(0o755)
                marker = temp / "timesync"
                marker.write_text("gps")
                stratum = temp / "ntp-stratum"
                stratum.write_text(settings.get("MOCK_STRATUM", "2"))
                services = temp / "services"
                services.mkdir()
                (services / "test").write_text("ntp://fallback-good.example:123\n")
                adapted = source.replace("/tmp/timesync", str(marker)).replace("/var/state/ntp-stratum", str(stratum))
                adapted = adapted.replace("/var/run/arednlink/services", str(services))
                adapted = adapted.replace("/usr/local/bin/aredn-time-status", str(bins / "recorder"))
                script = temp / "update-clock"
                script.write_text(adapted)
                record = temp / "record"
                env = dict(os.environ, PATH=str(bins) + ":" + os.defpath, MOCK_RECORD=str(record))
                env.update(settings)
                result = subprocess.run(["sh", str(script)], env=env, capture_output=True, timeout=5)
                assert result.returncode == (1 if name == "all-failed" else 0), (label, name, result.stderr)
                assert (marker.read_text() if marker.exists() else None) == expected_marker, (label, name)
                observed = record.read_text().strip() if record.exists() else ""
                assert observed == (expected_record if label == "candidate" else ""), (label, name, observed)
                print(f"PASS: {label} {name}: native result preserved; actual successful source annotation correct")


if __name__ == "__main__":
    main()
