# Cable Location 2.4.0

A native Apple silicon Mac app for simulating a cable-connected iPhone's location.

Download the app ZIP from [GitHub Releases](https://github.com/arn01ddd/Cable_Location/releases/latest).
Release changes are in [RELEASE_NOTES.md](RELEASE_NOTES.md); audit scope and limits
are in [AUDIT.md](AUDIT.md).

## Open the app

Release 2.4.0 is self-contained: Python, the iPhone support library
(`pymobiledevice3`), and Apple's developer disk images are inside the app. Nothing
else needs to be installed: no Python, Homebrew, or Xcode.

**You need:** an Apple silicon Mac (M1 or newer) with macOS 14 or later, an iPhone
with a passcode, a USB cable that carries data, and internet access when a session
starts (Apple signs the developer disk image for each iPhone).

1. Download **CableLocation-macOS-arm64.zip** from the latest release, double-click it,
   and drag **Cable Location.app** into **Applications**.
2. Open the app. The first time, macOS blocks it because it is not notarized: open
   **System Settings → Privacy & Security**, click **Open Anyway** next to Cable
   Location, and confirm. This is needed once.
3. Connect the iPhone by USB, unlock it, and tap **Trust**.
4. Click **Refresh** and select your USB iPhone if more than one is attached.
5. Choose a destination: click the map to drop a pin, pick a saved or recent place
   in the sidebar, or paste coordinates or a Google/Apple Maps link into the field.
   Use decimal degrees, latitude first, with a minus sign for south or west.
6. Click **Start Location**. Keep the cable connected and the Mac lid open. If
   Developer Mode is off, the app makes its switch appear on the iPhone and says so:
   turn on **Settings → Privacy & Security → Developer Mode**, let the iPhone
   restart, tap **Turn On**, then click Start Location again.
7. Click **Stop & Restore** when finished. Verify the real location in iPhone Maps.

If the app says to move it to Applications, macOS is running it from a hidden
read-only copy; drag it into Applications and open it again.

Commas, whitespace, parentheses, and negative coordinates are accepted, as are
hemisphere notation (`33.8568° S, 151.2153° E`), `geo:` URIs, and Google Maps or
Apple Maps links that contain coordinates. Links and map clicks are converted to
canonical decimal degrees rounded to six places (about 10 cm). Latitude must be
within −90…90 and longitude within −180…180. Typed coordinates keep their precision.

## Saved and recent places

Click the star beside the field (Command-S) to name and save the current
destination. Saved places appear in the sidebar; right-click one to copy or remove
it. The last five started destinations appear under **Recent** and can be cleared.
Places, recents, and the last destination are stored only in this Mac's user
preferences for the app (`local.cablelocation.mac`) and are never uploaded.

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
reconnection activity and can be copied for troubleshooting.

## Restore real location

Use **Stop & Restore** while running, or **Restore Real Location** afterward.
If the cable disconnected, reconnect and unlock the iPhone, then click Restore.
The app reports a failed clear command instead of claiming restoration succeeded.
Restart the iPhone if restoration still fails. A force quit or a crash may prevent
cleanup. Do not run other location tools against the same phone simultaneously.

## Setup troubleshooting

- If macOS blocks the app after downloading the ZIP, use **System Settings →
  Privacy & Security → Open Anyway**. It is ad-hoc signed and not notarized with an
  Apple Developer account.
- If setup reports damaged iPhone support, download and extract the ZIP again.
- If no device appears, unlock it, check that Finder sees it, and try another
  data-capable cable or port.
- If the Developer Mode switch is missing, click Start Location once with the iPhone
  unlocked; the app reveals it. Complete the iPhone restart and confirmation.
- If the target app ignores the position, check Maps, grant location permission,
  and reopen that app. This changes simulated GPS, not IP address or account region.

## Terminal alternative

**Launch.command** remains available and uses the same persistent worker:

```sh
./Launch.command list
./Launch.command set '<latitude>, <longitude>'
./Launch.command set -- <latitude> <longitude>
./Launch.command clear
```

Press **Control-C** to stop and request restoration in Terminal.
Replace the angle-bracket labels with decimal coordinate values. Use the `--`
form when passing separate negative values. If the source launcher is not
executable, run it with `zsh Launch.command`.

## Source and verification

- `NativeApp/CableLocationApp.swift`: native app lifecycle and process controller.
- `NativeApp/Interface.swift`: SwiftUI workspace, map, saved places, and design tokens.
- `NativeApp/NativeChecks.swift`: native state/contrast checks and preview renderer.
- `NativeApp/bootstrap.sh`: checks the bundled runtime (or prepares a venv for source builds).
- `worker.py`: async USB session, one-second refresh, reconnect, and restoration.
- `cable_location.py`: Terminal interface and shared coordinate validation.
- `build_app.py`: rebuild the Apple silicon app with Xcode Command Line Tools, embedding a
  pinned standalone Python, `pymobiledevice3`, and the developer disk images.
- `tests/`: coordinate, refresh, cleanup, and controller tests.

Run tests with `python3 -m unittest discover -s tests` and rebuild with
`python3 build_app.py`. The app targets Apple silicon Macs running macOS 14 or
newer. The iOS 27 path uses `pymobiledevice3==11.40.2`.

Upstream references:
[location-service API](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/dvt/instruments/location_simulation.py),
[async USB tunnel](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/userspace_tunnel.py),
[iOS developer support](https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/cli-recipes.md).

## Previous hardware verification (2.1)

The native interface was opened and tested with the connected USB iPhone. It
accepted 75 consecutive coordinate refreshes over more than a minute, followed by
successful completion of the clear commands. This verifies the service connection;
the blue dot in iPhone Maps was not inspected. Fourteen automated tests passed,
including an event-loop responsiveness test and recovery after a simulated USB
connection failure. Native coordinate-validation checks also passed.

## Interface

Version 2.3.0 is a redesigned graphite dark workspace. A sidebar holds the device
card, saved and recent places, and a collapsible setup checklist. The main column
shows a dark map with the destination pin, the destination field with paste and
save buttons, session tiles (duration, accepted updates, last update), and
Diagnostics. A pulsing green status marks a live session; amber marks attention.
Map clicks and destination changes are locked while a session runs.

Keyboard shortcuts: Command-Return start, Command-Period stop and restore,
Command-R refresh devices, Shift-Command-V paste coordinates or a map link,
Command-S save the place.

The cable-pin vector mark is in `Brand/Logo.svg`; the generated app icon is in
`Brand/AppIcon.png`. Render five native interface states without a phone (map
tiles are replaced by a grid in offscreen renders):

```sh
'Cable Location.app/Contents/MacOS/CableLocation' --render-previews .build/previews
```

## Release verification (2.4.0)

Twenty-two Python tests cover coordinate validation, session control, cleanup,
Developer Mode detection, and bundled disk-image seeding. 139 native assertions
cover coordinates, map links, saved places, UI states, and contrast. The release
workflow builds on an Apple silicon Mac, checks that the bundled runtime works with
no Python on `PATH` and an empty home folder, audits dependency advisories, and
verifies the signature and ZIP checksum. This update has not been tested with a
physical iPhone or on a Mac that has never run Cable Location.
