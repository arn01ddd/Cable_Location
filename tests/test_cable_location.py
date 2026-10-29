import os
import json
from pathlib import Path
import signal
import subprocess
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cable_location as app


class CableLocationTests(unittest.TestCase):
    def test_shared_native_and_backend_coordinate_cases(self):
        cases = json.loads(Path(__file__).with_name("coordinate_cases.json").read_text())
        for case in cases:
            with self.subTest(input=case["input"]):
                if case["valid"]:
                    app.coordinate_pair(case["input"])
                else:
                    with self.assertRaises(app.LocationError):
                        app.coordinate_pair(case["input"])

    def test_coordinate_bounds_and_nonfinite(self):
        self.assertEqual(app.coordinate("-90", 90), -90)
        self.assertEqual(app.coordinate("180", 180), 180)
        for value in ("nan", "inf", "-inf", "90.0001", "1;echo test", ""):
            with self.subTest(value=value), self.assertRaises(app.LocationError):
                app.coordinate(value, 90)

    def test_pasted_coordinate_pair(self):
        self.assertEqual(app.coordinate_pair("1.3291521175946346, 103.7764896710236"),
                         (1.3291521175946346, 103.7764896710236))
        self.assertEqual(app.coordinate_pair(" (-33.86, -151.2) "), (-33.86, -151.2))
        for value in ("nan, 2", "91, 2", "1, 181", "1,2,3", "1,,2", "one, two"):
            with self.subTest(value=value), self.assertRaises(app.LocationError):
                app.coordinate_pair(value)

    def test_inherited_remote_routes_are_removed(self):
        with patch.dict(os.environ, {"PYMOBILEDEVICE3_TUNNEL": "remote",
                                    "PYMOBILEDEVICE3_UDID": "wrong",
                                    "USBMUXD_SOCKET_ADDRESS": "remote:123"}):
            env = app.backend_env()
        self.assertNotIn("PYMOBILEDEVICE3_TUNNEL", env)
        self.assertNotIn("PYMOBILEDEVICE3_UDID", env)
        self.assertNotIn("USBMUXD_SOCKET_ADDRESS", env)
        self.assertEqual(env["PYMOBILEDEVICE3_DEFAULT_FALLBACK"], "userspace")

    @patch.object(app, "run", return_value='["usb-phone", "usb-phone"]')
    def test_usb_only_discovery(self, run):
        self.assertEqual(app.usb_devices(), ["usb-phone"])
        self.assertEqual(run.call_args.args, ("usbmux", "list", "--usb", "--simple"))

    @patch.object(app, "usb_devices", return_value=["other"])
    def test_disconnected_target_is_rejected(self, _):
        with self.assertRaises(app.LocationError):
            app.select_device("missing")

    def simulate_with_exit(self, outcome):
        process = MagicMock()
        if isinstance(outcome, BaseException):
            process.wait.side_effect = outcome
        else:
            process.wait.return_value = outcome
        with patch.object(app, "prepare"), patch.object(app.subprocess, "Popen", return_value=process) as popen, \
                patch.object(app, "stop_process") as stop, patch.object(app, "restore") as restore:
            try:
                app.simulate("phone", -33.86, -151.2)
            except app.LocationError:
                if not isinstance(outcome, int) or outcome == 0:
                    raise
            stop.assert_called_once_with(process)
            restore.assert_called_once_with("phone")
            argv = popen.call_args.args[0]
            self.assertEqual(argv[-2:], ["--coordinates", "-33.86, -151.2"])
            self.assertTrue(argv[1].endswith("worker.py"))
            self.assertTrue(popen.call_args.kwargs["start_new_session"])

    def test_restore_after_interrupt(self):
        self.simulate_with_exit(KeyboardInterrupt())

    def test_restore_after_backend_failure(self):
        self.simulate_with_exit(1)

    def test_restore_failure_is_an_error(self):
        process = MagicMock()
        process.wait.return_value = 0
        with patch.object(app, "prepare"), patch.object(app.subprocess, "Popen", return_value=process), \
                patch.object(app, "stop_process"), \
                patch.object(app, "restore", side_effect=app.LocationError("unplugged")):
            with self.assertRaisesRegex(app.LocationError, "Could not confirm"):
                app.simulate("phone", 1, 2)

    @patch.object(app.os, "killpg")
    def test_stuck_child_is_escalated_and_reaped(self, killpg):
        process = MagicMock(pid=12345)
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("backend", 4),
                                    subprocess.TimeoutExpired("backend", 3), 0]
        app.stop_process(process)
        self.assertEqual([call.args[1] for call in killpg.call_args_list],
                         [signal.SIGINT, signal.SIGTERM, signal.SIGKILL])


if __name__ == "__main__":
    unittest.main()

