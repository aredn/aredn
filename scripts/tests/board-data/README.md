# Board-data recovery regression tests

AI-assisted AREDN work for https://github.com/aredn/aredn/issues/2963.

## Design

- `aredn.board` checks JSON syntax, board identity, and the object shape of network/radio metadata. It does not manufacture hardware defaults.
- `board-data` runs once at boot, before the normal boot service runs Wi-Fi detection. Healthy metadata is a no-op. Invalid data is preserved in `/tmp/aredn-board-data-invalid.json`; generation runs against a private candidate, with a ten-second detector timeout. Candidates must match `/tmp/sysinfo/board_name`. Installation is by same-filesystem rename after validation. A nonblocking lock prevents overlapping recovery attempts.
- There is no last-good snapshot fallback across firmware versions: regeneration on the same device avoids restoring stale port/radio layouts. No UCI settings or running network/radio services are changed by the recovery helper.
- The UI uses the existing administrator credentials/cookie handling for an asset-independent diagnostic page. Both anonymous and authenticated configuration requests receive HTTP 503 while metadata is invalid. Login is a bounded POST, not a password in a URL. A missing password database fails closed.
- `getBoard()` reports invalid metadata explicitly rather than silently returning an empty board. The web startup path detects that condition before radio preload.
- The writer follow-up replaces the initial `/bin/sync` barriers with checked `file.sync()` and `dir.sync()` operations, supplied by the small pinned-ucode patch. `fs.flush()` alone is only `fflush()` and is not a durability barrier.

The support-data collector includes the preserved invalid file. It has the same privacy properties as the board metadata already present in support archives.

## Writer contract and audit

All identified board-data writers in AREDN `8c028e99` and its pinned OpenWrt
v25.12.5 sources now use `aredn.board.write()` (through the shell helper where
needed). The original source of the zero-filled file is **not** established.

| Path | Protection |
| --- | --- |
| AREDN recovery | Shared lock; device-identity check; validated durable commit |
| `board_detect` | Unique private staging; valid existing file is a no-op; final lock/recheck avoids overwriting concurrent recovery |
| `board_config_flush` / all `board.d` generators | Checked JSON producer and common writer; abort even if the caller ends with `exit 0` |
| preinit `82_config_generate` | Checked installation replaces cross-filesystem `mv`; no configuration generation after failure |
| `wifi-detect.uc` | Lock covers read/detect/write; invalid input/netlink failure preserves the previous file; caller/hotplug propagate failure |

Board scripts receive a private `CFG` from `board_detect`, so intermediate
updates cannot race with the live Wi-Fi/recovery transaction. The realtek
`99_fwenv-store-ethaddr` script reads board metadata; it writes bootloader
environment variables, not the board file. Support-data copies are not live
board writers. Arbitrary third-party scripts and manual shell writes are not
covered by this source audit.

The writer validates data, stages it on the destination filesystem, checks the
byte count and file fsync/close, parses it back, renames it, then fsyncs the parent
directory. Pre-rename failures preserve the original file. A post-rename directory
sync failure is reported with `installed: true`: the new valid bytes are visible,
but durability was not confirmed. No silent success or unsafe rollback is used.
Unchanged valid data does not cause a storage write. Locks are nonblocking;
callers report contention rather than overwriting each other. An interrupted
process may leave a private staging directory; it cannot expose partial live
metadata. Actual power-loss guarantees depend on the filesystem/storage stack.

## Native and handler checks

Requires Python 3 and a host ucode matching the firmware's language/runtime, with the fs module:

```sh
UCODE=/path/to/ucode UCODE_FS_PATH=/path/to/patched/modules python3 scripts/tests/board-data/run.py
```

The fixture reproduces the exact 1,436-zero-byte board file reported in #2963, verified by SHA-256; it contains no node-specific data. Cases include malformed/missing data, healthy no-op, wrong-device candidates, detector and synchronization failures, and competing recovery attempts.

The complete `root.ut` and fallback template execute in host ucode. The harness replaces import bindings and the absolute template path, not the handler logic. File, UCI, radio, HTTP, and password-verifier dependencies are mocked. Real passwords, real radios, and real configuration are never used. In particular, the password verifier is a deterministic test double; these tests exercise authentication dispatch/cookie boundaries, not the system crypt implementation.

## Writer and fault-injection checks

Build the fs module from pinned ucode `85922056ef7abeace3cca3ab28bc1ac2d88e31b1`
with the inner `003-add-fsync.patch` installed by AREDN patch 763. This also fixes
the runtime's previously unchecked `fclose()`/`closedir()` return values so the
documented close-failure result can be checked by the writer. Use its module
directory as `UCODE_FS_PATH`; the runtime and module must have matching ABIs.
Alternatively use an OpenWrt host ucode build with that package patch applied.
The tests deliberately fail if the new sync methods are missing.

```sh
UCODE=/path/to/ucode UCODE_FS_PATH=/path/to/patched/modules \
  OPENWRT_TREE=/path/to/openwrt-v25.12.5 \
  python3 scripts/tests/board-data/writers.py
```

Requires Linux, a C compiler, and a git checkout containing OpenWrt commit
`f0a60eee2fe051741c643ea6118718aae1ef17fb`. The checkout is read only: exact
sources are obtained with `git show` and patch 764 is applied in a temporary
fixture. The detector, shell flush, preinit promotion and Wi-Fi writer bodies
execute with only external paths/data producers replaced. The original detector
is a negative control: it retains the 1,436-byte zero-filled file.

`faults.c` injects short writes/ENOSPC, close errors, file/directory fsync errors,
one EINTR, rename failure, and a
process exit before rename. Tests check both return values and destination
contents, cross-process lock contention, cleanup, unchanged-file behavior and
consumer failure propagation. These are controlled host failures, **not** a
physical power-cut or flash-controller simulation. The module is loaded only
into test subprocesses.

## Browser check

Requires Node.js, Playwright and a compatible Chromium installation:

```sh
UCODE=/path/to/ucode UCODE_FS_PATH=/path/to/patched/modules node scripts/tests/board-data/browser.cjs
```

Optional `PLAYWRIGHT_MODULE` selects an installed module; `CHROMIUM_PATH` selects an existing browser binary. Every browser request is intercepted and dispatched to the full ucode fixture. There are no external requests, real node requests, or live configuration changes. Tests use ordinary form input, incorrect/correct credentials (including space and plus characters), cookie-based reload, and a blocked configuration PUT. No HTMX or other asset is required by this deliberately self-contained fallback.

## Remaining qualification

These fixtures do not establish physical hAP ac3 recovery, full firmware-image build success, real uhttpd/procd lifecycle behavior, or power-loss durability. Before merge, validate boot ordering and native board detection on a lab node, compare configuration/routing/radio state before and after recovery, and confirm the normal UI is restored following recovery and web-server restart. Do not simulate corruption or power cuts on an operational node.
