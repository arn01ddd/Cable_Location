"""Native app backend. stdout is newline-delimited JSON; USB sessions stay async."""
from __future__ import annotations

import argparse
import asyncio
from contextlib import AsyncExitStack
import json
import fcntl
import hashlib
import os
import signal
import sys
import tempfile
import time

from cable_location import backend_env, coordinate_pair, LocationError


def emit(event: str, **values):
    print(json.dumps(dict(event=event, **values)), flush=True)


async def cli(*args: str, timeout: float = 90) -> str:
    child = await asyncio.create_subprocess_exec(
        sys.executable, "-m", "pymobiledevice3", *args,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        env=backend_env(),
    )
    try:
        out, err = await asyncio.wait_for(child.communicate(), timeout)
        if child.returncode:
            raise LocationError((err or out).decode(errors="replace").strip() or
                                f"Device command failed ({child.returncode}).")
        if err:
            emit("log", message=err.decode(errors="replace").strip()[-4000:])
        return out.decode(errors="replace")
    finally:
        if child.returncode is None:
            child.terminate()
            try:
                await asyncio.wait_for(child.wait(), 3)
            except asyncio.TimeoutError:
                child.kill()
                await child.wait()


async def devices() -> list[str]:
    result = json.loads(await cli("usbmux", "list", "--usb", "--simple", timeout=20))
    if not isinstance(result, list) or any(not isinstance(d, str) for d in result):
        raise LocationError("Unexpected USB device response.")
    return list(dict.fromkeys(result))


async def require_usb(udid: str):
    if udid not in await devices():
        raise LocationError("Selected iPhone is not connected by USB. Reconnect and unlock it.")


async def prepare(udid: str):
    await require_usb(udid)
    emit("status", message="Unlock your iPhone and accept Trust if prompted…")
    await cli("lockdown", "pair", "--udid", udid)
    emit("status", message="Preparing developer support. First use may download files…")
    await cli("mounter", "auto-mount", "--udid", udid, timeout=900)


async def refresh_location(location, stop: asyncio.Event, lat: float, lon: float,
                           interval: float, report=emit):
    """Keep the asyncio USB transport running; acknowledge each completed refresh."""
    count = 0
    started = time.monotonic()
    while not stop.is_set():
        await asyncio.wait_for(location.set(lat, lon), timeout=12)
        count += 1
        report("applied", count=count, elapsed=time.monotonic() - started)
        try:
            await asyncio.wait_for(stop.wait(), timeout=interval)
        except asyncio.TimeoutError:
            pass


async def clear_location(location):
    await asyncio.wait_for(location.clear(), timeout=8)
    emit("restored", message="Clear command sent. Verify your real location in iPhone Maps.")


async def hold(udid: str, coordinates: str, interval: float, stop: asyncio.Event):
    from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel
    from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
    from pymobiledevice3.services.dvt.instruments.location_simulation import LocationSimulation

    lat, lon = coordinate_pair(coordinates)
    await prepare(udid)
    failures = 0
    try:
        while not stop.is_set():
            stack = AsyncExitStack()
            try:
                await require_usb(udid)
                emit("status", message="Connecting to iPhone location service…")
                rsd = await asyncio.wait_for(stack.enter_async_context(
                    UserspaceRsdTunnel(serial=udid, autopair=True, remotepairing_fallback=False)), 45)
                dvt = await asyncio.wait_for(stack.enter_async_context(DvtProvider(rsd)), 30)
                location = await asyncio.wait_for(stack.enter_async_context(LocationSimulation(dvt)), 15)
                try:
                    await refresh_location(location, stop, lat, lon, interval)
                finally:
                    if stop.is_set():
                        try:
                            await clear_location(location)
                        except Exception as exc:
                            emit("log", message=f"Session clear failed; will retry over a fresh connection: {exc}")
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                failures += 1
                emit("reconnecting", message=f"Connection interrupted; retrying in 3 seconds. {exc}", retries=failures)
            finally:
                try:
                    await asyncio.wait_for(stack.aclose(), 8)
                except Exception as exc:
                    emit("log", message=f"Connection cleanup: {exc}")
            if not stop.is_set():
                try:
                    await asyncio.wait_for(stop.wait(), 3)
                except asyncio.TimeoutError:
                    pass
    finally:
        # A separate clear also covers cancellation during connect or an interrupted tunnel.
        emit("status", message="Restoring real location…")
        try:
            await require_usb(udid)
            await cli("developer", "dvt", "simulate-location", "clear", "--udid", udid,
                      "--userspace", timeout=35)
            emit("restored", message="Clear command sent. Verify your real location in iPhone Maps.")
        except Exception as exc:
            emit("restore_failed", message=f"Restore not confirmed: {exc} Reconnect and click Restore, or restart the iPhone.")


async def main(args):
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        loop.add_signal_handler(sig, stop.set)
    if args.action == "list":
        emit("devices", devices=await devices())
        return
    if not args.udid:
        raise LocationError("Select a USB iPhone first.")
    if args.action == "clear":
        await require_usb(args.udid)
        await cli("developer", "dvt", "simulate-location", "clear", "--udid", args.udid,
                  "--userspace", timeout=45)
        emit("restored", message="Clear command sent. Verify your real location in iPhone Maps.")
        return
    coordinate_pair(args.coordinates)
    task = asyncio.create_task(hold(args.udid, args.coordinates, args.interval, stop))
    stopper = asyncio.create_task(stop.wait())
    try:
        done, _ = await asyncio.wait((task, stopper), return_when=asyncio.FIRST_COMPLETED)
        if task not in done:
            task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
    finally:
        stopper.cancel()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["list", "hold", "clear"])
    parser.add_argument("--udid")
    parser.add_argument("--coordinates", default="")
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()
    try:
        if not 0.25 <= args.interval <= 30:
            raise LocationError("Refresh interval must be between 0.25 and 30 seconds.")
        if args.action == "list":
            asyncio.run(main(args))
        else:
            # Share a lock across the native app, Terminal launcher, and other copies.
            key = hashlib.sha256((args.udid or "").encode()).hexdigest()[:24]
            path = os.path.join(tempfile.gettempdir(), f"cablelocation-{os.getuid()}-{key}.lock")
            fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w") as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise LocationError("Another Cable Location session is using this iPhone. Stop that session first.") from None
                asyncio.run(main(args))
    except Exception as exc:
        emit("error", message=str(exc) or type(exc).__name__)
        sys.exit(1)
