#!/usr/bin/env python3
"""Build the native Apple silicon app using installed Xcode Command Line Tools."""
from pathlib import Path
import plistlib
import hashlib
import os
import shutil
import subprocess
import struct
import tarfile
import tempfile

# Relocatable CPython from astral-sh/python-build-standalone, pinned by version and checksum.
PYTHON_URL = ("https://github.com/astral-sh/python-build-standalone/releases/download/20261013/"
              "cpython-3.14.8%2B20261013-aarch64-apple-darwin-install_only_stripped.tar.gz")
PYTHON_SHA256 = "994adadc202c5df0b4570192cc9a70e3f2c131e512f4a125c56efa8562f44b28"
# Unused parts of the standard distribution (GUI toolkit, tests, IDE, headers).
PRUNE = ("lib/python3.14/test", "lib/python3.14/idlelib", "lib/python3.14/tkinter",
         "lib/python3.14/turtledemo", "lib/python3.14/ensurepip", "lib/itcl*", "lib/tcl*",
         "lib/tk*", "lib/thread*", "lib/libtcl*", "lib/libtk*", "lib/pkgconfig",
         "lib/python3.14/lib-dynload/_tkinter*", "lib/python3.14/config-*", "share", "include")

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
cache = root / ".build"
cache.mkdir(parents=True, exist_ok=True)


def bundle_python():
    """Embed Python, pymobiledevice3, and the developer disk images, so nothing is downloaded."""
    archive = cache / PYTHON_URL.rsplit("/", 1)[1].replace("%2B", "+")
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != PYTHON_SHA256:
        print("Downloading standalone Python…")
        partial = archive.with_suffix(".part")
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                        "--proto", "=https", "-o", str(partial), PYTHON_URL], check=True)
        data = partial.read_bytes()
        partial.unlink()
        if hashlib.sha256(data).hexdigest() != PYTHON_SHA256:
            raise SystemExit("Standalone Python checksum mismatch")
        archive.write_bytes(data)
    target = resources / "python"
    shutil.rmtree(target, ignore_errors=True)
    with tarfile.open(archive) as tar:
        tar.extractall(resources, filter="data")
    python = target / "bin/python3"
    env = dict(os.environ, PIP_DISABLE_PIP_VERSION_CHECK="1", PIP_NO_CACHE_DIR="1")
    env.pop("PYTHONPATH", None)
    subprocess.run([str(python), "-I", "-m", "pip", "install", "--quiet", "--only-binary", ":all:",
                    "--no-compile", "-r", str(root / "requirements.txt")], check=True, env=env)
    images = resources / "ddi"
    shutil.rmtree(images, ignore_errors=True)
    with tempfile.TemporaryDirectory() as home:
        # pymobiledevice3's own fetchers write a verified cache under $HOME; copy that cache.
        subprocess.run([str(python), "-I", "-c", (
            "from pymobiledevice3.services.cryptexd import fetch_cryptex_ddi;"
            "from pymobiledevice3.services.mobile_image_mounter import fetch_personalized_ddi;"
            "fetch_cryptex_ddi(); fetch_personalized_ddi()")], check=True, env=dict(env, HOME=home))
        found = list(Path(home).rglob("Xcode_iOS_DDI_*"))
        if {f.name for f in found} != {"Xcode_iOS_DDI_Cryptex", "Xcode_iOS_DDI_Personalized"}:
            raise SystemExit(f"Developer disk images missing: {found}")
        for folder in found:
            shutil.copytree(folder, images / folder.name)
    subprocess.run([str(python), "-I", "-m", "pip", "uninstall", "--quiet", "-y", "pip"], check=True, env=env)
    for pattern in PRUNE:
        for path in target.glob(pattern):
            shutil.rmtree(path) if path.is_dir() else path.unlink()
    for path in [*target.rglob("__pycache__"), *target.glob("bin/*")]:
        if path.name not in ("python", "python3", "python3.14"):
            shutil.rmtree(path) if path.is_dir() else path.unlink()
    subprocess.run([str(python), "-I", "-m", "compileall", "-q", "-j", "0",
                    "--invalidation-mode", "unchecked-hash", str(target / "lib")], check=True, env=env)
    for path in target.rglob("*"):
        if path.is_file() and path.suffix in (".so", ".dylib") or path.parent.name == "bin" and path.is_file():
            # Sign each embedded binary so the bundle seal covers valid code signatures.
            subprocess.run(["codesign", "--force", "--sign", "-", str(path)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([str(python), "-I", "-c", "import pymobiledevice3, importlib.metadata as m;"
                    "assert m.version('pymobiledevice3') == '11.40.2'"], check=True, env=env)


if os.environ.get("CABLE_LOCATION_SKIP_PYTHON") != "1" or not (resources / "python/bin/python3").exists():
    bundle_python()
# Precompiled backend bytecode means Python never writes into the signed bundle at run time.
subprocess.run([str(resources / "python/bin/python3"), "-I", "-m", "compileall", "-q",
                "--invalidation-mode", "unchecked-hash", str(resources / "backend")], check=True)
plist = {
    "CFBundleExecutable": "CableLocation",
    "CFBundleIdentifier": "local.cablelocation.mac",
    "CFBundleName": "Cable Location",
    "CFBundleDisplayName": "Cable Location",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": app_version,
    "CFBundleVersion": app_version,
    "LSMinimumSystemVersion": "14.0",
    "NSHighResolutionCapable": True,
    "NSHumanReadableCopyright": "Cable Location",
    "CFBundleIconFile": "AppIcon",
}
with (contents / "Info.plist").open("wb") as f:
    plistlib.dump(plist, f)
subprocess.run([
    "xcrun", "swiftc", "-swift-version", "5", "-O", "-parse-as-library",
    "-target", "arm64-apple-macosx14.0", "-module-cache-path", str(cache),
    str(root / "NativeApp/CableLocationApp.swift"), str(root / "NativeApp/Interface.swift"),
    str(root / "NativeApp/NativeChecks.swift"), "-framework", "MapKit", "-o", str(binary / "CableLocation"),
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
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
subprocess.run([str(binary / "CableLocation"), "--self-test", "--coordinate-cases",
                str(root / "tests/coordinate_cases.json")], check=True)
print(f"Built {app}")

