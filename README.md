# Cable Location 2.1

A native Apple silicon Mac app for simulating a cable-connected iPhone's location.

## Open the app

Double-click **Cable Location.app** in this folder. Your existing private Python
environment is reused when available. If you move the app elsewhere, its first
launch creates a private runtime in `~/Library/Application Support/Cable Location/`.
Python 3.10 or newer must be installed on the Mac; first setup needs internet.

1. Connect the iPhone using a data-capable USB-C cable, unlock it, and trust the Mac.
2. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone.
3. Click **Refresh** and select your USB iPhone if more than one is attached.
4. Paste a coordinate pair into the single field, for example:
   `29.9792458, 31.134094`.
5. Click **Start Location**. Keep the cable connected and the Mac lid open.
6. Click **Stop & Restore** when finished. Verify the real location in iPhone Maps.

Commas, whitespace, parentheses, and negative coordinates are accepted. Latitude
must be within −90…90 and longitude within −180…180. Decimal precision is retained
up to the underlying double-precision location API.

## Sustained sessions

There is no session duration limit. The app keeps an asynchronous USB tunnel and
location-service connection open, reapplies your coordinates every second, and
retries interrupted connections every three seconds after cleanup. It prevents
idle Mac sleep during a session. Closing the Mac lid or losing power can still
interrupt USB access. Quit normally to request restoration before exiting.

The earlier Terminal version invoked a backend command that waits synchronously
after setting the location. That wait can block the asyncio-based USB transport.
Version 2 replaces that command with a nonblocking refresh loop. This is a likely
explanation for the short-lived location; other apps and iOS can also affect it.

The timer, accepted refresh count, and last-update age show the service activity.
They do not read the phone's actual position. Check the blue dot in **Maps on the
iPhone** to verify what an app sees. The app's Diagnostics panel shows errors and
reconnection activity without storing a coordinate history.

## Restore real location

Use **Stop & Restore** while running, or **Restore Real Location** afterward.
If the cable disconnected, reconnect and unlock the iPhone, then click Restore.
The app reports a failed clear command instead of claiming restoration succeeded.
Restart the iPhone if restoration still fails. A force quit or a crash may prevent
cleanup. Do not run other location tools against the same phone simultaneously.

## Setup troubleshooting

- If Python is missing, install the macOS universal installer from
  [python.org](https://www.python.org/downloads/macos/), then reopen the app.
- If setup fails while building a package, install Apple's Command Line Tools
  with `xcode-select --install`, then click **Retry setup**.
- If macOS blocks this locally built, ad-hoc-signed app after downloading a ZIP,
  use Finder's Open action or **System Settings → Privacy & Security → Open Anyway**
  for this app. It is not notarized with an Apple Developer account.
- If no device appears, unlock it, check that Finder sees it, and try another
  data-capable cable or port.
- If Developer Mode is missing, connect the phone to Xcode's Devices and Simulators
  window first. Complete the iPhone restart and Developer Mode confirmation.
- If the target app ignores the position, check Maps, grant location permission,
  and reopen that app. This changes simulated GPS, not IP address or account region.

## Terminal alternative

**Launch.command** remains available and uses the same persistent worker:

```sh
./Launch.command list
./Launch.command set 'long, lat'
./Launch.command set -- -xx xx
./Launch.command clear
```

Press **Control-C** to stop and request restoration in Terminal.

## Source and verification

- `NativeApp/CableLocationApp.swift`: native SwiftUI interface and process controller.
- `NativeApp/bootstrap.sh`: private Python runtime preparation.
- `worker.py`: async USB session, one-second refresh, reconnect, and restoration.
- `cable_location.py`: Terminal interface and shared coordinate validation.
- `build_app.py`: rebuild the Apple silicon app using Xcode Command Line Tools.
- `tests/`: coordinate, refresh, cleanup, and controller tests.

Run tests with `python3 -m unittest discover -s tests` and rebuild with
`python3 build_app.py`. The app targets Apple silicon Macs running macOS 14 or
newer. The iOS 27 path uses `pymobiledevice3==11.40.2`.

Upstream references:
[location-service API](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/dvt/instruments/location_simulation.py),
[async USB tunnel](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/userspace_tunnel.py),
[iOS developer support](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/cli-recipes.md).

## Verification on this Mac

The native interface was opened and tested with the connected USB iPhone. It
accepted 75 consecutive coordinate refreshes over more than a minute, followed by
successful completion of the clear commands. This verifies the service connection;
the blue dot in iPhone Maps was not inspected. Fourteen automated tests passed,
including an event-loop responsiveness test and recovery after a simulated USB
connection failure. Native coordinate-validation checks also passed.

## Visual identity

Version 2.1 adds a midnight blue and mint interface, a custom cable-pin logo,
and a separate session monitor. The vector mark is in `Brand/Logo.svg`; the
1024-pixel app icon is in `Brand/AppIcon.png`. Both are generated from editable
code, with matching marks in the app header and session display.
