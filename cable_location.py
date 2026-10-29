#!/usr/bin/env python3
"""USB location simulation for a trusted, Developer Mode-enabled iPhone."""
from __future__ import annotations

import argparse
import contextlib
import fcntl
from importlib.metadata import PackageNotFoundError, version
import json
import math
import os
import re
from pathlib import Path
import signal
import subprocess
import sys

BACKEND_VERSION = "11.40.2"
BASE = Path(__file__).resolve().parent


class LocationError(Exception):
    pass


def coordinate(value: str, limit: float) -> float:
    if not re.fullmatch(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", value):
        raise LocationError("Enter a coordinate in decimal degrees.")
    try:
        number = float(value)
    except ValueError:
        raise LocationError("Enter a coordinate in decimal degrees.") from None
    if not math.isfinite(number) or not -limit <= number <= limit:
        raise LocationError(f"Coordinate must be between {-limit:g} and {limit:g}.")
    return number


def coordinate_pair(value: str) -> tuple[float, float]:
    cleaned = value.strip()
    if cleaned.startswith("(") and cleaned.endswith(")"):
        cleaned = cleaned[1:-1].strip()
    parts = ([part.strip() for part in cleaned.split(",")] if "," in cleaned
             else cleaned.split())
    if len(parts) != 2:
        raise LocationError("Enter latitude, longitude in decimal degrees.")
    return coordinate(parts[0], 90), coordinate(parts[1], 180)


def backend_env() -> dict[str, str]:
    # Ignore inherited routing flags: this tool only targets local USB devices.
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("PYMOBILEDEVICE3_") and k != "USBMUXD_SOCKET_ADDRESS"}
    env.update(NO_COLOR="1", PYTHONUNBUFFERED="1",
               PYMOBILEDEVICE3_DEFAULT_FALLBACK="userspace")
    return env


def command(*args: str) -> list[str]:
    return [sys.executable, "-m", "pymobiledevice3", *args]


def run(*args: str, capture: bool = False, timeout: int = 90) -> str:
    try:
        result = subprocess.run(command(*args), env=backend_env(), text=True,
                                capture_output=capture, timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        raise LocationError("Device command timed out. Unlock the iPhone and reconnect the cable.") from None
    if result.returncode:
        details = ((result.stderr or result.stdout or "").strip() if capture else "")
        raise LocationError(f"Device command failed (exit {result.returncode}). {details}")
    return result.stdout if capture else ""


def usb_devices() -> list[str]:
    raw = run("usbmux", "list", "--usb", "--simple", capture=True, timeout=20)
    try:
        devices = json.loads(raw)
    except json.JSONDecodeError:
        raise LocationError("Unexpected device-list response from the backend.") from None
    if not isinstance(devices, list) or any(not isinstance(d, str) for d in devices):
        raise LocationError("Unexpected device-list format from the backend.")
    return list(dict.fromkeys(devices))


def select_device(requested: str | None) -> str:
    devices = usb_devices()
    if requested:
        if requested not in devices:
            raise LocationError("The selected iPhone is not connected by USB.")
        return requested
    if not devices:
        raise LocationError("No USB iPhone found. Connect a data-capable cable and unlock the phone.")
    if len(devices) == 1:
        return devices[0]
    if not sys.stdin.isatty():
        raise LocationError("Several devices connected; choose one using --udid.")
    for index, udid in enumerate(devices, 1):
        print(f"  {index}. {udid}")
    try:
        choice = int(input("Select iPhone number: "))
        if not 1 <= choice <= len(devices):
            raise ValueError
        return devices[choice - 1]
    except ValueError:
        raise LocationError("Invalid device number.") from None


def prepare(udid: str) -> None:
    select_device(udid)
    print("Unlock your iPhone and accept Trust This Computer if prompted.", flush=True)
    run("lockdown", "pair", "--udid", udid)
    print("Preparing Apple developer support. First use may download an image.", flush=True)
    run("mounter", "auto-mount", "--udid", udid, timeout=900)


def restore(udid: str) -> None:
    select_device(udid)
    run("developer", "dvt", "simulate-location", "clear", "--udid", udid, "--userspace")
    print("iPhone accepted the clear command. Check Maps for the real location.", flush=True)


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    # The backend runs in its own group so a terminal Ctrl-C reaches our cleanup first.
    for sig, seconds in ((signal.SIGINT, 4), (signal.SIGTERM, 3), (signal.SIGKILL, 3)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=seconds)
            return
        except subprocess.TimeoutExpired:
            continue
    raise LocationError("Backend did not stop; restart the iPhone to reset location.")


@contextlib.contextmanager
def uninterrupted_cleanup():
    signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)
    previous = {sig: signal.signal(sig, signal.SIG_IGN) for sig in signals}
    try:
        yield
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def simulate(udid: str, latitude: float, longitude: float) -> None:
    print(f"Requesting location {latitude:g}, {longitude:g}.", flush=True)
    print("Keep the cable connected. Check the blue dot in Maps on your iPhone.\n"
          "Press Control-C here to stop and request real-location restoration.\n"
          "A running process alone does not confirm the phone's reported location.", flush=True)
    process = subprocess.Popen(
        [sys.executable, str(BASE / "worker.py"), "hold", "--udid", udid,
         "--coordinates", f"{latitude}, {longitude}"],
        env=backend_env(), start_new_session=True,
    )
    try:
        code = process.wait()
        if code:
            raise LocationError(f"Location simulation exited with status {code}.")
    except KeyboardInterrupt:
        print("\nStopping simulation…", flush=True)
    finally:
        with uninterrupted_cleanup():
            try:
                stop_process(process)
            finally:
                print("Requesting real-location restoration…", flush=True)
                try:
                    restore(udid)
                except LocationError as exc:
                    print(f"RESTORATION NOT CONFIRMED: {exc}\n"
                          "Reconnect and use Restore real location. If it still fails, restart the iPhone.",
                          file=sys.stderr, flush=True)
                    raise LocationError("Could not confirm location restoration.") from exc


def check_backend() -> None:
    try:
        installed = version("pymobiledevice3")
    except PackageNotFoundError:
        raise LocationError("Dependency missing. Open Launch.command to install it.") from None
    if installed != BACKEND_VERSION:
        raise LocationError(f"Expected pymobiledevice3 {BACKEND_VERSION}, found {installed}. "
                            "Open Launch.command to repair the environment.")


def menu() -> None:
    print("\nCABLE LOCATION · iPhone USB location simulation\n"
          "Before starting: connect USB, unlock, trust this Mac, and enable\n"
          "Settings → Privacy & Security → Developer Mode (restart if asked).\n")
    while True:
        print("\n1  Set location\n2  Restore real location\n3  List USB devices\n4  Prepare developer support\nQ  Quit")
        choice = input("Choose: ").strip().lower()
        try:
            if choice == "q":
                return
            if choice == "3":
                devices = usb_devices()
                print("\n".join(devices) or "No USB device found.")
            elif choice == "1":
                lat, lon = coordinate_pair(input("Paste latitude, longitude: "))
                simulate(select_device(None), lat, lon)
            elif choice in {"2", "4"}:
                udid = select_device(None)
                if choice == "2":
                    restore(udid)
                else:
                    prepare(udid)
            else:
                print("Choose 1, 2, 3, 4, or Q.")
        except (LocationError, KeyboardInterrupt) as exc:
            print(f"\n{exc or 'Cancelled.'}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", help="Target an explicitly selected USB iPhone")
    sub = parser.add_subparsers(dest="action")
    sub.add_parser("list", help="List USB device IDs")
    sub.add_parser("prepare", help="Pair and prepare Apple developer support")
    sub.add_parser("clear", help="Request restoration of real location")
    setter = sub.add_parser("set", help="Hold a coordinate until Control-C, then clear")
    setter.add_argument("latitude")
    setter.add_argument("longitude", nargs="?")
    args = parser.parse_args()
    try:
        check_backend()
        # One controller per installation prevents competing sessions.
        with (BASE / ".session.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise LocationError("Cable Location is already running. Use its open Terminal window.") from None
            if args.action is None:
                menu()
            elif args.action == "list":
                print(json.dumps(usb_devices(), indent=2))
            else:
                # Reject bad coordinates before touching a device.
                if args.action == "set":
                    if args.longitude is None:
                        lat, lon = coordinate_pair(args.latitude)
                    else:
                        lat = coordinate(args.latitude, 90)
                        lon = coordinate(args.longitude, 180)
                udid = select_device(args.udid)
                if args.action == "prepare":
                    prepare(udid)
                elif args.action == "clear":
                    restore(udid)
                else:
                    simulate(udid, lat, lon)
        return 0
    except LocationError as exc:
        print(f"\nError: {exc}", file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nClosed.")
        return 130


def interrupted(signum, frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    sys.exit(main())

