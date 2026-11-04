Cable Location 2.3.0 is a redesigned dark workspace with a map and saved places.

**New**
- Interactive dark map: click to drop a pin and see the destination before you start.
- Saved places: star a destination (⌘S), name it, and reuse it from the sidebar.
- Recent destinations: the last five started locations, one click to reuse.
- Paste Google Maps, Apple Maps, and `geo:` links, or N/S/E/W notation; they are
  converted to decimal coordinates automatically (⇧⌘V pastes from the clipboard).
- The last destination is remembered between launches.
- Live session indicator with a pulsing green status and a "last update" tile.
- Copy button for Diagnostics, ⌘. to stop and restore, hover feedback on controls.

**Redesign**
- Graphite near-black theme with sky-blue actions, green live state, amber warnings.
- Reorganised sidebar: device card, saved and recent places, collapsible setup checklist.
- Session tiles for duration, accepted updates, and last update.

**Fixes**
- The bundle build number now follows the release version, so macOS treats each
  release as a distinct update (it was fixed at 6).

Release verification includes 16 backend tests, 139 native assertions (map-link
parsing, place persistence, 30 text contrast pairs), five native UI previews, a
dependency advisory audit, and signature/checksum checks.

Download **CableLocation-macOS-arm64.zip**, extract it, and open **Cable Location.app**.
Requires an Apple silicon Mac with macOS 14 or later and Python 3.10 or later.
First launch downloads the private Python backend. The app is ad-hoc signed
without Apple Developer ID notarization. Saved places stay on your Mac.

No physical iPhone was available for this update. Verify location and restoration
in Maps on your iPhone.
