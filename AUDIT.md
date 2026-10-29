# Release audit: 2.1.1

Scope: destination input, native/backend validation, process invocation, USB
selection, session cleanup, dependency pinning, and macOS release packaging.

## Findings addressed

- The destination placeholder showed a particular location. It now reads
  `Latitude, Longitude`, with a decimal-degrees tooltip and an empty initial value.
  Validation errors also use format instructions instead of example locations.
- Swift discarded empty comma-separated components, accepting inputs such as
  `1,,2` that Python rejected. Both parsers now require exactly two decimal
  coordinates, matching parentheses, finite values, and geographic bounds.
  A shared 35-case fixture runs in Python and the native executable.
- The build cache referenced a directory outside the checkout and could fail on
  a clean Mac. It now uses `.build` within the project.
- The Terminal example reversed latitude and longitude. Documentation now agrees
  with the app and backend.
- Generated Python bytecode was tracked. Remove it and ignore future build output.

## Checks and limits

All 15 Python tests passed in the Linux workspace, including the shared input
fixture, USB-only discovery, rejection of inherited remote routing, refresh-loop
responsiveness, reconnection, process cleanup, and restoration failure reporting.
The process controller passes argument arrays to subprocesses rather than
interpolating coordinates into a shell command. The dependency is version-pinned.

The release workflow additionally requires a macOS Apple silicon build, native
validation against the shared fixture, launcher syntax checks, a dependency
advisory scan, and verification of the ad-hoc app signature before publication.
Actions are pinned to commit SHAs; only the publishing job receives repository
write access. The ZIP includes a SHA-256 checksum.

There is no physical iPhone attached to this environment. Automated mocks do not
establish that iOS or a particular app honors the simulated position. New hardware
verification and Apple Developer ID notarization are outside this release's
verified results. Closing the lid, force quitting, or unplugging can interrupt
restoration; the interface already reports failed clear commands and asks the
user to verify the real location in Maps.
