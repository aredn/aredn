# Current HUB-5 UI — November 25, 2026

The preferred **two-column Time status layout** is now the default on desktop
and mobile, following [the review comment](https://github.com/aredn/aredn/pull/3032#issuecomment-7169585156).
The former three-column render is retained separately as a comparison.

These screenshots use fresh authenticated native HTTP and served CSS captured
from HUB-5 / AREDN 4.26.10.0 at **18:21 UTC**, rendered unchanged in a fully
intercepted offline browser replay. They are **not direct live-browser captures
or simulated receiver states**. Browser policy blocked the local SSH tunnel.

All twelve installed GUI/native-source hashes matched GUI source revision
`7f8caefaac4b245d56e9f5b0f1f815c5cf55a138`. On HUB-5, only the admin stylesheet changed; native
synchronization, settings, source selection and cadence remain unchanged.

- [Compact status](hub5-status-20261125.png): uppercase PST in the normal clock
  style; source/receiver details remain in hover text.
- [Time popup](hub5-time-popup-20261125.png): the implemented **two-column desktop**
  details section at the bottom of the existing settings popup.

Badge wording, colored text versus bubbles, lowercase status subtitle labels,
and whether to show unknown status remain separate open design questions.
