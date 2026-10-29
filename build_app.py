#!/usr/bin/env python3
"""Build the native Apple silicon app using installed Xcode Command Line Tools."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import struct

root = Path(__file__).resolve().parent
app_version = (root / "VERSION").read_text().strip()
app = root / "Cable Location.app"
contents = app / "Contents"
binary = contents / "MacOS"
resources = contents / "Resources"
binary.mkdir(parents=True, exist_ok=True)
(resources / "backend").mkdir(parents=True, exist_ok=True)
shutil.rmtree(resources / "backend/__pycache__", ignore_errors=True)
for name in ("worker.py", "cable_location.py", "requirements.txt"):
    shutil.copy2(root / name, resources / "backend" / name)
shutil.copy2(root / "NativeApp/bootstrap.sh", resources / "bootstrap.sh")
plist = {
    "CFBundleExecutable": "CableLocation",
    "CFBundleIdentifier": "local.cablelocation.mac",
    "CFBundleName": "Cable Location",
    "CFBundleDisplayName": "Cable Location",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": app_version,
    "CFBundleVersion": "5",
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
    "NSHumanReadableCopyright": "Cable Location",
    "CFBundleIconFile": "AppIcon",
}
with (contents / "Info.plist").open("wb") as f:
    plistlib.dump(plist, f)
cache = root / ".build"
cache.mkdir(parents=True, exist_ok=True)
subprocess.run([
    "xcrun", "swiftc", "-swift-version", "5", "-O", "-parse-as-library",
    "-target", "arm64-apple-macosx14.0", "-module-cache-path", str(cache),
    str(root / "NativeApp/CableLocationApp.swift"), str(root / "NativeApp/Interface.swift"),
    str(root / "NativeApp/NativeChecks.swift"), "-o", str(binary / "CableLocation"),
], check=True)
iconset = cache / "AppIcon.iconset"
iconmaker = cache / "make_icon"
subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(cache),
                str(root / "NativeApp/make_icon.swift"), "-o", str(iconmaker)], check=True)
subprocess.run([str(iconmaker), str(iconset)], check=True)
shutil.copy2(iconset / "icon_512x512@2x.png", root / "Brand/AppIcon.png")
chunks = []
for kind, name in ((b"ic07", "icon_128x128.png"), (b"ic08", "icon_256x256.png"),
                   (b"ic09", "icon_512x512.png"), (b"ic10", "icon_512x512@2x.png")):
    png = (iconset / name).read_bytes()
    chunks.append(kind + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
(resources / "AppIcon.icns").write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
subprocess.run([str(binary / "CableLocation"), "--self-test", "--coordinate-cases",
                str(root / "tests/coordinate_cases.json")], check=True)
print(f"Built {app}")

