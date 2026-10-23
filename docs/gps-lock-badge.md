# GPS LOCK status badge

This change replaces the plain `(gps)` time-source suffix with a firmware-style
`GPS LOCK` badge when **GPS Time** is enabled. The time-zone label remains, e.g.
`utc GPS LOCK · LOCAL` or `utc GPS LOCK · NETWORK`. Nodes with GPS Time disabled retain their existing display.
An NTP time-source suffix remains visible if NTP most recently set the clock;
receiver lock is not a claim that GPS is currently disciplining the system clock.

## Local versus network GPS

AREDN's existing discovery first checks local `/dev/ttyACM0` and `/dev/ttyUSB0`,
then GPSD servers on DTD neighbors. A node without a plugged-in GPS can therefore
receive a valid fix from another node, including one running an older firmware
version. GPSD interoperability does not require the server to run this UI patch.

The badge explicitly identifies **LOCAL** versus **NETWORK**. Its tooltip and
accessible label contain the selected device/server endpoint. Source is derived
from the connection chosen by AREDN, never from the TPV `device` field: a remote
GPSD server can legitimately report its own `/dev/ttyACM0`. Source metadata is
retained through loss of fix, connection failure, and stale-cache errors. Missing
or legacy source metadata displays **SOURCE UNKNOWN**, never an assumed local GPS.

On dev1, a live check confirmed no local receiver devices and a network 3D fix
from HUB5's GPSD server. HUB5 runs 4.26.7.0 with a USB GPS receiver. The initial
badge correctly reported the fix but omitted its network origin; the explicit
source label corrects that ambiguity. This does not change receiver selection,
clock synchronization, location settings, or HUB5's firmware.

## States

| State | Default color | Meaning |
|---|---|---|
| Locked | Green | A current GPSD TPV message reports a 2D/3D fix and GPS time. |
| Pending | Yellow | Initial discovery, no satellite fix yet, or waiting for time. |
| Error | Red | Source/connection/data error, missing receiver, or stale health data. |

Explicit no-fix, dead-reckoning-only and simulated GPSD statuses cannot turn the
badge green. A tooltip and accessible label describe the state. Positive/error
colors use the firmware badge's theme variables, including its accessibility
theme overrides. Pending uses dark text on a yellow background.

The old `/tmp/timesync` marker is historical and is **not** evidence of current
lock. GPS receiver health is refreshed every 30 seconds by the existing GPS
manager task and published atomically in RAM at `/tmp/gps-lock.json`. The status
page already refreshes every 30 seconds. Data older than 90 seconds, invalid
data, or data with a future monotonic timestamp turns red. Startup retains the
existing 60-second GPS discovery delay and shows pending while starting.

Connection/read operations are bounded; the status page itself only reads the
cached state. Existing GPS discovery, clock/location update operations and their
10-minute interval are retained. No extra health probes are made when GPS Time
is disabled. GPS lock does not certify PPS accuracy or survey-grade positioning.

## Changed files

- `files/usr/share/ucode/aredn/gpslock.uc`: receiver state, bounded reading,
  atomic cache, freshness validation; script returning its helper API.
- `files/usr/local/mgr/gps.uc`: health polling alongside the original sync logic.
  The helper uses `loadfile()` so GPS-only reloads do not reuse outdated modules.
- `files/app/partial/health.ut`: cached state and accessible badge markup.
- `files/app/resource/css/user.css`: badge styling matching firmware status.

## Checks

From the repository root on a system with AREDN's ucode modules:

```sh
ucode -L "$PWD/files/usr/share/ucode/*.uc" tests/gps-lock.uc
ucode -L "$PWD/files/usr/share/ucode/*.uc" tests/gps-lock-transport.uc
ucode -L "$PWD/files/usr/share/ucode/*.uc" tests/gps-lock-manager.uc
ucode -L "$PWD/files/usr/share/ucode/*.uc" tests/gps-lock-render.uc
```

The renderer check uses Linux `/proc` data and writes `render-*.html` fixtures
to the current directory; the manager checks mock hardware and clock-setting
operations. It does not alter node time or configuration. Receiver-state tests
exercise no-fix, bad data, stale data, and malformed/future caches. The template
check also exercises the **real dynamic helper loading path**, not only mocks.

An initial dev1 deployment exposed a mismatch between static ucode module exports
and the dynamic `require()` interface used by tasks/templates. It was rolled
back, corrected, and covered by the real-loader regression check before reapply.

The dev1 test patch is not an APK or a firmware release and will be overwritten
by a firmware upgrade. The isolated source branch and backup preserve the change
for review and future integration.
