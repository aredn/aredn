# GPS lock and clock-source status in the time area

This firmware GUI/status change makes receiver health and clock-source evidence
visible without treating them as the same thing.

| Indicator | Source line | Evidence |
|---|---|---|
| `LOCKED · GPS` | Selected LOCAL/NETWORK receiver endpoint | Fresh receiver fix with valid UTC time |
| `WAITING · GPS` | Selected endpoint, or explicitly unknown | Discovery, no satellite fix, or no valid receiver time |
| `ERROR · GPS` | Selected endpoint where known | Missing source, failed connection/data, or stale health cache |
| `SYNCED · NTP` | Actual successful one-shot target, or unknown daemon peer | Matching recent native synchronization evidence |
| `LAST SYNC · NTP` | Historical target, or source not recorded | Old evidence or only the native synchronization marker |
| `UNSYNCED · NTP` | Peer unknown when not exposed | Native daemon callback reports an unsynchronized stratum |

GPS lock is receiver health, not proof of PPS accuracy or continuous clock
discipline. NTP evidence describes an observed native synchronization, not a GPS
lock. A pool hostname is the successful command target; no resolved IP is
invented. A configured server list is not evidence of the server actually used.
Standard BusyBox callbacks expose stratum, not the selected peer.

When NTP last synchronized the clock and a selected GPS receiver also has health
data, a separate badge reports that receiver's lock. With no selected GPS source,
working NTP does not produce an unrelated GPS alarm.

## Controlled-render examples

These screenshots use native-template fixtures, not live receiver measurements.

![GPS locked, selected network receiver](images/time-status/gps-locked.png)
![GPS waiting for a fix or valid time](images/time-status/gps-waiting.png)
![NTP synchronized, successful native command target](images/time-status/ntp-synced.png)

## Display support

- The existing GPS manager publishes a bounded health observation every 30 seconds
  while GPS Time is enabled. Receiver provenance comes from its selected local
  device or network endpoint, never a remote server's TPV device path.
- The native clock/location synchronization body and ten-minute cadence are
  retained, including native synchronization-marker ownership and cleanup.
- The page reads RAM caches only. It performs no GPSD/NTP connection, discovery,
  USB scan, or package query. It reuses the existing authenticated HTMX refresh
  and time-settings interaction; public read-only views require reload.
- GPS health expires after 90 seconds. Discovery retries retain the native
  ten-minute interval; the display can therefore report stale data between retries.
- Native successful NTP paths gain best-effort metadata annotations. Annotation
  failure does not change the native synchronization result. The observer does
  not set the clock, select a peer, or enable a daemon.
- NTP metadata uses writer-specific temporary files and atomic rename. Marker
  mtime and monotonic timestamps reject mismatched/future records. One-shot
  evidence becomes historical after 24 hours; daemon evidence after 15 minutes.
- Source text and tooltips are escaped. Explicit state words support all themes;
  long source endpoints wrap.

There is no USB-detection hook, installation prompt, package/dependency/release
change, driver change, or replacement synchronization algorithm in this patch.

## Isolated validation

```sh
python3 tests/gps-lock-run.py \
  --ucode /path/to/ucode --ucode-library /path/to/modules \
  --playwright-module /path/to/playwright-core
python3 tests/ntp-annotations.py
```

The default baseline is pinned to firmware revision
`3a7fdab83897ae2f9aebd42e052fe78ecac34a66`; both runners accept
`--baseline-ref` for explicit rebasing. Clock/config/service writes are mocked.
Loopback GPSD fixtures use private ephemeral ports, and browser requests are
intercepted. Tests exercise real repository templates, themes, and HTMX resources.
These checks do not qualify physical receiver faults, reboots, or a firmware build.
