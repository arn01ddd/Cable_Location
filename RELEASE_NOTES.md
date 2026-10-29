Cable Location 2.2.0 introduces a completely redesigned native Mac workspace.

- A deep green connection sidebar and a bright workspace replace the old dashboard.
  Larger type, stronger contrast, and generous spacing make the app easier to read.
- The destination uses a high-contrast **Latitude, Longitude** format hint, visible
  keyboard focus, and inline validation. The input starts empty.
- A compact session summary shows duration, refresh interval, accepted updates,
  and recovery instructions. The window resizes, and long content scrolls.
- Single-device connections no longer need a picker. Multiple USB phones retain
  explicit selection. Command-R refreshes devices; Command-Return starts a valid session.
- Successful restoration clears previous errors. Updates older than five seconds
  stop displaying a live status. Unknown selections cannot enable device actions;
  empty or invalid coordinates still allow restoration.
- Native checks cover state transitions, action availability, timer behavior,
  coordinate cases, and text contrast. Backend tests also cover cancellation
  cleanup and failed restoration after cancellation.

Download **CableLocation-macOS-arm64.zip**, extract it, and open **Cable Location.app**.
Requires an Apple silicon Mac with macOS 14 or later and Python 3.10 or later.
First launch downloads the private Python backend. A SHA-256 checksum is included.
The app is ad-hoc signed; Apple Developer ID notarization is not included.

This release is built and checked on macOS, with five native interface previews.
No physical iPhone was available for this update. Verify simulated and restored
locations in Maps on your iPhone.
