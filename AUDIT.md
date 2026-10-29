# Release audit: 2.2.0

Scope: native interface, destination validation, device selection, session
presentation, restoration and cancellation, keyboard access, text contrast,
dependency advisories, and release packaging.

## Findings addressed

- Small, subdued text and a large decorative graphic made the old interface hard
  to scan. The redesign uses 12–17 point body/control text, a 36 point title,
  clear labels, and a compact session summary.
- Native placeholder styling reduced contrast even with a custom prompt color.
  The generic format hint now uses the checked secondary text color. It leaves
  the input empty and does not duplicate the field's accessibility label.
- Successful restoration could leave the interface styled as failed. A restored
  event now clears that state, including after a failed restoration attempt.
- A live badge could persist after updates stopped. After five seconds without
  an update, the interface displays a waiting state and cable/unlock guidance.
- Per-operation restoration flags could outlive their operation. They are reset
  at launch; failed process launches also remove their pipe callbacks.
- Device actions now require membership in the detected USB device list.
  Restore remains available when the destination is empty or invalid.
- The fixed window did not adapt to long messages. The new window resizes with
  a 940 × 740 minimum; the workspace and expanded Diagnostics scroll.
  Reduced-motion preference disables the Diagnostics animation.

## Verification

- Sixteen Python tests pass, including coordinate validation, USB-only discovery,
  inherited route rejection, asynchronous refresh, reconnection, process cleanup,
  and cancellation with both successful and failed restoration.
- Sixty native assertions cover 35 shared coordinate cases, worker messages split
  across reads, device selection, disabled actions, stale/live/restoring states,
  restoration error recovery, and a frozen last-session timer.
- Native checks require at least 4.5:1 contrast for ten normal-text color pairs,
  including placeholder, sidebar, warning, input error, and disabled-button text.
  Token checks do not replace a full accessibility conformance review.
- Native renders cover empty, ready, active, error/diagnostics, and minimum-size
  layouts. Ready, error, and minimum-size renders were reviewed before release;
  final renders and checks are retained as GitHub Actions artifacts.
- Publication requires dependency advisory scanning, Python tests, launcher
  syntax, native compilation/checks, preview rendering, signature verification,
  and ZIP checksum verification.

Buttons and inputs have accessibility labels or visible text. Device refresh
and starting support keyboard shortcuts. Input focus has a visible border;
status meaning uses text as well as color. Coordinates are passed as subprocess
arguments without shell interpolation. The redesign adds no network services,
coordinate storage, or dependency changes.

## Limits

Automated device services are mocks. No physical iPhone is attached here, so
this audit does not establish what a particular iOS app reports. Verify the
blue dot and restoration in iPhone Maps. The app remains ad-hoc signed without
Apple Developer ID notarization. Unplugging, closing the lid, crashing, or
force quitting can interrupt restoration.
