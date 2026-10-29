import asyncio
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import worker


class RefreshTests(unittest.IsolatedAsyncioTestCase):
    async def test_cancelled_session_cleans_tunnel_and_reports_final_restore_result(self):
        for restore_fails in (False, True):
            with self.subTest(restore_fails=restore_fails):
                entered = asyncio.Event()
                stop = asyncio.Event()
                closed = []
                events = []
                location = AsyncMock()

                async def pending_update(*args):
                    entered.set()
                    await asyncio.Event().wait()

                location.set.side_effect = pending_update

                class Context:
                    def __init__(self, name, value):
                        self.name, self.value = name, value
                    async def __aenter__(self):
                        return self.value
                    async def __aexit__(self, *args):
                        closed.append(self.name)

                modules = {
                    "pymobiledevice3.remote.userspace_tunnel": SimpleNamespace(
                        UserspaceRsdTunnel=lambda **kw: Context("tunnel", object())),
                    "pymobiledevice3.services.dvt.instruments.dvt_provider": SimpleNamespace(
                        DvtProvider=lambda rsd: Context("dvt", object())),
                    "pymobiledevice3.services.dvt.instruments.location_simulation": SimpleNamespace(
                        LocationSimulation=lambda dvt: Context("location", location)),
                }
                clear = AsyncMock(side_effect=ConnectionError("disconnected") if restore_fails else None)
                with patch.dict(sys.modules, modules), patch.object(worker, "prepare", new=AsyncMock()), \
                        patch.object(worker, "require_usb", new=AsyncMock()), \
                        patch.object(worker, "cli", new=clear), \
                        patch.object(worker, "emit", side_effect=lambda event, **kw: events.append(event)):
                    task = asyncio.create_task(worker.hold("phone", "0, 0", 1, stop))
                    await asyncio.wait_for(entered.wait(), timeout=1)
                    stop.set()
                    task.cancel()
                    with self.assertRaises(asyncio.CancelledError):
                        await asyncio.wait_for(task, timeout=1)
                self.assertEqual(closed, ["location", "dvt", "tunnel"])
                clear.assert_awaited_once()
                self.assertEqual(events[-1], "restore_failed" if restore_fails else "restored")

    async def test_refresh_repeats_without_blocking_transport_event_loop(self):
        stop = asyncio.Event()
        ticks = []
        reports = []

        class Location:
            calls = []
            async def set(self, lat, lon):
                self.calls.append((lat, lon))
                await asyncio.sleep(0)
                if len(self.calls) == 12:
                    stop.set()

        async def transport():
            while not stop.is_set():
                ticks.append(1)
                await asyncio.sleep(0.001)

        location = Location()
        await asyncio.gather(worker.refresh_location(location, stop,
                             1.3291521175946346, 103.7764896710236, 0.005,
                             lambda event, **values: reports.append((event, values))), transport())
        self.assertEqual(len(location.calls), 12)
        self.assertGreater(len(ticks), 12)
        self.assertEqual(reports[-1][1]["count"], 12)
        self.assertTrue(all(c == (1.3291521175946346, 103.7764896710236) for c in location.calls))

    async def test_stop_interrupts_long_refresh_interval(self):
        stop = asyncio.Event()
        location = AsyncMock()
        async def request_stop():
            await asyncio.sleep(0.01)
            stop.set()
        with patch.object(worker, "emit"):
            await asyncio.wait_for(asyncio.gather(
                worker.refresh_location(location, stop, -33.86, -151.2, 30, lambda *a, **k: None),
                request_stop()), timeout=1)
        location.set.assert_awaited_once_with(-33.86, -151.2)

    async def test_set_error_propagates_to_reconnection_controller(self):
        location = AsyncMock()
        location.set.side_effect = ConnectionError("USB disconnected")
        with self.assertRaises(ConnectionError):
            await worker.refresh_location(location, asyncio.Event(), 1, 2, 1)

    async def test_clear_failure_does_not_claim_restoration(self):
        location = AsyncMock()
        location.clear.side_effect = ConnectionError("USB disconnected")
        with patch.object(worker, "emit") as emit:
            with self.assertRaises(ConnectionError):
                await worker.clear_location(location)
        emit.assert_not_called()

    async def test_connection_failure_reopens_session_and_restores_on_stop(self):
        stop = asyncio.Event()
        seen = []

        class Context:
            def __init__(self, name, value):
                self.name, self.value = name, value
            async def __aenter__(self):
                seen.append("open " + self.name)
                return self.value
            async def __aexit__(self, *args):
                seen.append("close " + self.name)

        class Location:
            count = 0
            async def set(self, *args):
                self.count += 1
                if self.count == 1:
                    raise ConnectionError("USB interrupted")
                stop.set()
            async def clear(self):
                seen.append("clear")

        location = Location()
        modules = {
            "pymobiledevice3.remote.userspace_tunnel": SimpleNamespace(
                UserspaceRsdTunnel=lambda **kw: Context("tunnel", object())),
            "pymobiledevice3.services.dvt.instruments.dvt_provider": SimpleNamespace(
                DvtProvider=lambda rsd: Context("dvt", object())),
            "pymobiledevice3.services.dvt.instruments.location_simulation": SimpleNamespace(
                LocationSimulation=lambda dvt: Context("location", location)),
        }
        events = []
        with patch.dict(sys.modules, modules), patch.object(worker, "prepare", new=AsyncMock()), \
                patch.object(worker, "require_usb", new=AsyncMock()), \
                patch.object(worker, "cli", new=AsyncMock()), \
                patch.object(worker, "emit", side_effect=lambda event, **kw: events.append(event)):
            await asyncio.wait_for(worker.hold("phone", "1, 2", 0.25, stop), timeout=6)
        self.assertEqual(seen.count("open tunnel"), 2)
        self.assertEqual(seen.count("close tunnel"), 2)
        self.assertIn("clear", seen)
        self.assertIn("reconnecting", events)
        self.assertEqual(events[-1], "restored")


if __name__ == "__main__":
    unittest.main()

