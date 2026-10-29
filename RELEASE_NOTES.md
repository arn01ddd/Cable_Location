Cable Location 2.1.1 replaces the destination field's numeric example with
**Latitude, Longitude**. Enter coordinates in decimal degrees, latitude first;
use a minus sign for south or west. The field starts empty.

- Native and backend validation now agree on malformed separators, parentheses,
  decimal syntax, and coordinate bounds. Both check the same 35 input cases.
- Builds use a project-local cache instead of a machine-specific directory.
- The Terminal documentation now uses latitude before longitude.
- Release packaging runs Python tests, native validation, a dependency advisory
  audit, and signature verification before publishing an app ZIP and SHA-256 checksum.

Download **CableLocation-macOS-arm64.zip**, extract it, and open **Cable Location.app**.
Requires an Apple silicon Mac with macOS 14 or later and Python 3.10 or later.
First launch downloads the private Python backend. The app is ad-hoc signed;
Apple Developer ID signing and notarization are not included.

Automated checks use simulated device services. This release has not been tested
with a physical iPhone; verify location and restoration in iPhone Maps.
