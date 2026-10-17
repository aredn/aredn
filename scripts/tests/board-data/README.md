# Board-data recovery regression tests

AI-assisted AREDN work for https://github.com/aredn/aredn/issues/2963.

## Design

- `aredn.board` checks JSON syntax, board identity, and the object shape of network/radio metadata. It does not manufacture hardware defaults.
- `board-data` runs once at boot, before the normal boot service runs Wi-Fi detection. Healthy metadata is a no-op. Invalid data is preserved in `/tmp/aredn-board-data-invalid.json`; generation runs against a private candidate, with a ten-second detector timeout. Candidates must match `/tmp/sysinfo/board_name`. Installation is by same-filesystem rename after validation. A nonblocking lock prevents overlapping recovery attempts.
- There is no last-good snapshot fallback across firmware versions: regeneration on the same device avoids restoring stale port/radio layouts. No UCI settings or running network/radio services are changed by the recovery helper.
- The UI uses the existing administrator credentials/cookie handling for an asset-independent diagnostic page. Both anonymous and authenticated configuration requests receive HTTP 503 while metadata is invalid. Login is a bounded POST, not a password in a URL. A missing password database fails closed.
- `getBoard()` reports invalid metadata explicitly rather than silently returning an empty board. The web startup path detects that condition before radio preload.
- The initial recovery implementation uses `/bin/sync` barriers, since the pinned ucode `fs.flush()` is only `fflush()`. Per-file/per-directory durability and other writers are a separate follow-up.

The support-data collector includes the preserved invalid file. It has the same privacy properties as the board metadata already present in support archives.

## Native and handler checks

Requires Python 3 and a host ucode matching the firmware's language/runtime, with the fs module:

```sh
UCODE=/path/to/ucode python3 scripts/tests/board-data/run.py
```

The fixture reproduces the exact 1,436-zero-byte board file reported in #2963, verified by SHA-256; it contains no node-specific data. Cases include malformed/missing data, healthy no-op, wrong-device candidates, detector and synchronization failures, and competing recovery attempts.

The complete `root.ut` and fallback template execute in host ucode. The harness replaces import bindings and the absolute template path, not the handler logic. File, UCI, radio, HTTP, and password-verifier dependencies are mocked. Real passwords, real radios, and real configuration are never used. In particular, the password verifier is a deterministic test double; these tests exercise authentication dispatch/cookie boundaries, not the system crypt implementation.

## Browser check

Requires Node.js, Playwright and a compatible Chromium installation:

```sh
UCODE=/path/to/ucode node scripts/tests/board-data/browser.cjs
```

Optional `PLAYWRIGHT_MODULE` selects an installed module; `CHROMIUM_PATH` selects an existing browser binary. Every browser request is intercepted and dispatched to the full ucode fixture. There are no external requests, real node requests, or live configuration changes. Tests use ordinary form input, incorrect/correct credentials (including space and plus characters), cookie-based reload, and a blocked configuration PUT. No HTMX or other asset is required by this deliberately self-contained fallback.

## Remaining qualification

These fixtures do not establish physical hAP ac3 recovery, full firmware-image build success, real uhttpd/procd lifecycle behavior, or power-loss durability. Before merge, validate boot ordering and native board detection on a lab node, compare configuration/routing/radio state before and after recovery, and confirm the normal UI is restored following recovery and web-server restart. Do not simulate corruption or power cuts on an operational node.
