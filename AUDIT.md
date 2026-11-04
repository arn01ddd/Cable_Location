# Release audit: 2.4.0

Scope: redesigned dark interface, map destination picker, saved and recent places,
map-link parsing, contrast, persistence, session regressions, dependency
advisories, and Mac release packaging.

## Findings addressed

- 2.4.0 embeds a relocatable CPython 3.14.8 (python-build-standalone 20261013, pinned
  by SHA-256), `pymobiledevice3==11.40.2` installed from binary wheels only, and the
  Cryptex and Personalized developer disk images (build checked against
  pymobiledevice3's `LATEST_DDI_BUILD_ID`). Unused Tcl/Tk, tests, IDLE, pip, and
  headers are removed. All embedded binaries are ad-hoc signed and bytecode is
  precompiled, so nothing is written into the signed bundle at run time.
- The bundled runtime clears the download quarantine flag from the app's own files
  after the user approves opening it, so macOS does not block the embedded helper.
  A translocated (read-only, unmoved) copy is detected and the user is told to move it.
- Bundled disk images are copied into pymobiledevice3's cache (payloads first,
  manifest last) only when the cached build differs; failures fall back to download.
- Developer Mode is checked before mounting; when off, the switch is revealed via
  AMFI and the user gets exact instructions instead of a mount error.
- `CFBundleVersion` was hard-coded to `6` for every release, so macOS could not
  distinguish builds. It now follows `VERSION`.
- The README stated that no coordinate history is stored. Recents and saved places
  are now stored locally in the app's user preferences; the README and release
  notes describe what is stored and that it never leaves the Mac.
- Map links and hemisphere notation are converted to canonical decimal degrees in
  the app before reaching the backend, so the backend's strict validator and the
  shared 35-case fixture are unchanged. Every extracted value is re-checked
  against the same validator.
- Out-of-range map clicks, invalid saves, and destination changes during a session
  are rejected. Corrupt stored preferences are ignored rather than crashing.
- Native checks and previews use isolated preference domains so tests never read
  or overwrite a user's saved places.
- The local Command Line Tools cannot expand SwiftUI's `@State` macro; view state
  uses observable objects so the app still builds without full Xcode.

## Verification

- Twenty-two backend tests (coordinate validation, USB-only discovery, refresh,
  reconnection, cancellation, restoration failure, Developer Mode detection,
  bundled disk-image seeding) pass.
- 139 native assertions: 35 shared coordinate cases, 17 extraction cases (Google
  `@`/`!3d!4d`/`q=`/`query=`, Apple `ll=`/`coordinate=`, `geo:`, N/S/E/W, invalid
  links), saved/recent persistence and limits, clipboard paste, live/stale state,
  action availability, restoration recovery, session timing, and contrast.
- Normal text pairs (30) reach 4.5:1; control boundaries, focus, and invalid-input
  boundaries reach 3:1. This is not a complete accessibility conformance review.
- Five native previews (empty, ready, active, error, compact) were reviewed.
- `pip-audit --strict` reports no known vulnerabilities in `pymobiledevice3==11.40.2`.

## Observations not changed

- On a normal stop the worker sends the clear command over the live session and
  then again through the CLI, so Diagnostics can show "Clear command sent" twice.
  This redundancy is deliberate defensive cleanup and was left as is.

## Limits

No physical iPhone is attached; device services are mocked. The map needs internet
for tiles. Verify simulated and restored locations in iPhone Maps. The app is
ad-hoc signed without notarization. A disconnected cable, closed lid, crash, or
force quit may interrupt restoration.
