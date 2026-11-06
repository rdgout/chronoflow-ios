import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
runner = SimpleNamespace(**runpy.run_path(str(ROOT / "Scripts/launch-simulators.py")))


class LaunchSimulatorsTests(unittest.TestCase):
    def setUp(self):
        self.devices = {runner.REGULAR_RUNTIME: [], runner.DUO_RUNTIME: []}
        for index, (_, device_type, runtime) in enumerate(runner.MATRIX):
            self.devices[runtime].append({
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType." + device_type,
                "isAvailable": True,
                "state": "Shutdown",
                "udid": "device-" + str(index),
            })
        self.commands = []
        self.environments = []
        self.failure = lambda command: False
        self.installed = True

    def execute(self, timeline=False, scene=False, snapshots=False):
        output = io.StringIO()
        states = {d["udid"]: d["state"] for devices in self.devices.values() for d in devices}

        def fake_run(command, **kwargs):
            self.assertEqual(kwargs["cwd"], ROOT)
            self.commands.append(command)
            self.environments.append(kwargs.get("env", {}))
            if self.failure(command):
                raise subprocess.CalledProcessError(65, command)
            if command[:3] == ["xcrun", "simctl", "boot"]:
                if states[command[3]] == "Booted":
                    raise subprocess.CalledProcessError(149, command)
                states[command[3]] = "Booted"
            if command[:3] == ["xcrun", "simctl", "shutdown"]:
                states[command[3]] = "Shutdown"
            if command == ["xcrun", "simctl", "list", "devices", "-j"]:
                return subprocess.CompletedProcess(command, 0, json.dumps({"devices": self.devices}))
            status = 1 if "get_app_container" in command and not self.installed else 0
            return subprocess.CompletedProcess(command, status, "")

        with patch.object(runner.subprocess, "run", side_effect=fake_run), contextlib.redirect_stdout(output):
            status = runner.main(timeline=timeline, scene=scene, snapshots=snapshots)
        return status, output.getvalue()

    def test_all_devices_use_type_and_runtime_and_clear_the_launch_cache(self):
        wrong_runtime = dict(self.devices[runner.DUO_RUNTIME][0], udid="wrong-runtime")
        self.devices[runner.REGULAR_RUNTIME].insert(0, wrong_runtime)
        unavailable = dict(self.devices[runner.REGULAR_RUNTIME][1], udid="unavailable", isAvailable=False)
        self.devices[runner.REGULAR_RUNTIME].insert(0, unavailable)
        duplicate = dict(self.devices[runner.DUO_RUNTIME][0], udid="duplicate")
        self.devices[runner.DUO_RUNTIME].append(duplicate)
        status, output = self.execute()
        self.assertEqual(status, 0)
        for index, (label, _, _) in enumerate(runner.MATRIX):
            udid = "device-" + str(index)
            self.assertIn("PASS " + label + "\n", output)
            command = runner.XCODEBUILD + [
                "-destination", "platform=iOS Simulator,id=" + udid,
                "-only-testing:AppTests", "-only-testing:AppUITests/WindowTests", "-only-testing:DesignSystemTests", "test",
            ]
            restart = [
                ["xcrun", "simctl", "uninstall", udid, "net.chronoflow.app.native"],
                ["xcrun", "simctl", "shutdown", udid],
                ["xcrun", "simctl", "boot", udid],
                ["xcrun", "simctl", "bootstatus", udid, "-b"],
                command,
            ]
            start = self.commands.index(restart[0])
            self.assertEqual(self.commands[start:start + len(restart)], restart)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])
        self.assertNotIn("wrong-runtime", str(self.commands))
        self.assertNotIn("unavailable", str(self.commands))
        self.assertNotIn("duplicate", str(self.commands))

    def test_first_device_failure_still_tests_and_reports_every_device(self):
        self.failure = lambda command: command[0] == "xcodebuild" and command[-1] == "test" and "platform=iOS Simulator,id=device-0" in command
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone SE (3rd gen):", output)
        for label, _, _ in runner.MATRIX[1:]:
            self.assertIn("PASS " + label + "\n", output)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_missing_device_is_reported_and_later_devices_run(self):
        self.devices[runner.REGULAR_RUNTIME].pop(0)
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone SE (3rd gen): No available simulator:", output)
        self.assertIn("PASS iPhone Duo\n", output)

    def test_preparation_failure_continues_to_next_device(self):
        self.failure = lambda command: command == ["xcrun", "simctl", "bootstatus", "device-0", "-b"]
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone SE (3rd gen):", output)
        self.assertIn("PASS iPhone 17e\n", output)
        self.assertIn("PASS iPhone Duo\n", output)

    def test_booted_device_with_no_app_still_restarts_without_uninstall(self):
        self.devices[runner.REGULAR_RUNTIME][0]["state"] = "Booted"
        self.installed = False
        status, _ = self.execute()
        self.assertEqual(status, 0)
        self.assertFalse(any("uninstall" in command for command in self.commands))
        self.assertEqual(self.commands.count(["xcrun", "simctl", "boot", "device-0"]), 1)

    def test_clean_and_final_check_failures_are_aggregated(self):
        self.failure = lambda command: command[-1] in ["clean", "check", "duo"]
        status, output = self.execute()
        self.assertEqual(status, 1)
        for label in ["clean build folder", "make check", "make duo"]:
            self.assertIn("FAIL " + label + ":", output)
        for label, _, _ in runner.MATRIX:
            self.assertIn("PASS " + label + "\n", output)

    def test_generation_failure_stops_before_simulators(self):
        self.failure = lambda command: command == ["make", "generate"]
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn("FAIL make generate:", output)
        self.assertEqual(self.commands, [["make", "generate"]])

    def test_listing_failure_reports_all_devices_and_runs_final_checks(self):
        self.failure = lambda command: command == ["xcrun", "simctl", "list", "devices", "-j"]
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn("FAIL list simulators:", output)
        for label, _, _ in runner.MATRIX:
            self.assertIn("FAIL " + label + ": No available simulator:", output)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_timeline_runs_core_and_launch_suites_on_every_device(self):
        status, output = self.execute(timeline=True)
        self.assertEqual(status, 0)
        self.assertIn("Phase 3a simulator results:", output)
        tests = [command for command in self.commands if command[0] == "xcodebuild" and command[-1] == "test"]
        self.assertEqual(len(tests), 7)
        for command in tests:
            for suite in ["AppTests", "AppUITests/WindowTests", "DesignSystemTests", "AppCoreTests", "LaunchTests"]:
                self.assertIn("-only-testing:" + suite, command)
        self.assertIn("platform=iOS Simulator,id=device-6", tests[-1])
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_timeline_continues_after_failure_and_runs_both_final_checks(self):
        self.failure = lambda command: command[-1] == "check" or (
            command[0] == "xcodebuild" and command[-1] == "test" and "platform=iOS Simulator,id=device-0" in command
        )
        status, output = self.execute(timeline=True)
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone SE (3rd gen):", output)
        self.assertIn("PASS iPhone Duo\n", output)
        self.assertIn("FAIL make check:", output)
        self.assertIn("PASS make duo\n", output)

    def test_timeline_missing_duo_does_not_use_the_regular_runtime(self):
        self.devices[runner.REGULAR_RUNTIME].append(self.devices[runner.DUO_RUNTIME].pop())
        status, output = self.execute(timeline=True)
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone Duo: No available simulator:", output)
        self.assertNotIn("platform=iOS Simulator,id=device-6", str(self.commands))
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_scene_runs_presentation_and_ui_suites_on_all_seven_devices(self):
        status, output = self.execute(scene=True)
        self.assertEqual(status, 0)
        self.assertIn("Phase 3b simulator results:", output)
        tests = [c for c in self.commands if c[0] == "xcodebuild" and c[-1] == "test"]
        self.assertEqual(len(tests), 7)
        for command in tests:
            for suite in ["AppTests", "AppUITests/WindowTests", "AppUITests/LaunchSceneTests", "DesignSystemTests", "AppCoreTests", "LaunchTests"]:
                self.assertIn("-only-testing:" + suite, command)
        self.assertIn("platform=iOS Simulator,id=device-6", tests[-1])
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_scene_failure_continues_to_duo_and_both_final_commands(self):
        self.failure = lambda c: c[-1] == "check" or (c[0] == "xcodebuild" and c[-1] == "test" and "platform=iOS Simulator,id=device-0" in c)
        status, output = self.execute(scene=True)
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone SE (3rd gen):", output)
        self.assertIn("PASS iPhone Duo", output)
        self.assertIn("FAIL make check:", output)
        self.assertIn("PASS make duo", output)

    def test_scene_requires_duos_own_runtime(self):
        self.devices[runner.REGULAR_RUNTIME].append(self.devices[runner.DUO_RUNTIME].pop())
        status, output = self.execute(scene=True)
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone Duo: No available simulator:", output)
        self.assertNotIn("platform=iOS Simulator,id=device-6", str(self.commands))


    def test_snapshots_compare_by_default_even_with_an_inherited_test_runner_record_flag(self):
        with patch.dict(os.environ, {"SNAPSHOT_RECORD": "0", "TEST_RUNNER_SNAPSHOT_RECORD": "1"}):
            status, output = self.execute(snapshots=True)
        self.assertEqual(status, 0)
        tests = [(c, e) for c, e in zip(self.commands, self.environments) if c[0] == "xcodebuild" and c[-1] == "test"]
        self.assertEqual(len(tests), 7)
        for index, (command, environment) in enumerate(tests):
            self.assertIn("platform=iOS Simulator,id=device-" + str(index), command)
            self.assertIn("-only-testing:LaunchTests", command)
            self.assertEqual(command[command.index("-testLanguage") + 1], "en")
            self.assertEqual(command[command.index("-testRegion") + 1], "US")
            self.assertNotIn("SNAPSHOT_RECORD", environment)
            self.assertNotIn("TEST_RUNNER_SNAPSHOT_RECORD", environment)
        self.assertNotIn(" record", output)
        for label, _, _ in runner.MATRIX:
            self.assertIn("PASS " + label + " compare\n", output)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_snapshot_scene_mode_compares_snapshots_and_runs_hosted_and_ui_fixes_on_every_device(self):
        with patch.dict(os.environ, {"SNAPSHOT_RECORD": "1"}):
            status, output = self.execute(snapshots=True, scene=True)
        self.assertEqual(status, 0)
        tests = [c for c in self.commands if c[0] == "xcodebuild" and c[-1] == "test"]
        self.assertEqual(len(tests), 14)
        for index, command in enumerate(tests):
            self.assertIn("-only-testing:LaunchTests", command)
            for suite in ["AppTests", "AppUITests/WindowTests", "AppUITests/LaunchSceneTests"]:
                self.assertEqual("-only-testing:" + suite in command, index >= 7)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_snapshots_record_all_devices_before_comparing_and_clear_record_environment(self):
        with patch.dict(os.environ, {"SNAPSHOT_RECORD": "1", "TEST_RUNNER_SNAPSHOT_RECORD": "1"}):
            status, output = self.execute(snapshots=True)
        self.assertEqual(status, 0)
        self.assertIn("Phase 3c simulator results:", output)
        tests = [(c, e) for c, e in zip(self.commands, self.environments) if c[0] == "xcodebuild" and c[-1] == "test"]
        self.assertEqual(len(tests), 14)
        for index, (command, environment) in enumerate(tests):
            self.assertIn("platform=iOS Simulator,id=device-" + str(index % 7), command)
            self.assertIn("-only-testing:LaunchTests", command)
            self.assertIn("-testLanguage", command)
            self.assertNotIn("SNAPSHOT_RECORD", environment)
            self.assertEqual(environment.get("TEST_RUNNER_SNAPSHOT_RECORD"), "1" if index < 7 else None)
        for command, environment in zip(self.commands, self.environments):
            if command[0] != "xcodebuild" or command[-1] != "test":
                self.assertNotIn("TEST_RUNNER_SNAPSHOT_RECORD", environment)
        for label, _, _ in runner.MATRIX:
            self.assertIn("PASS " + label + " record\n", output)
            self.assertIn("PASS " + label + " compare\n", output)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_snapshot_record_failure_still_compares_every_device_and_runs_final_checks(self):
        self.failure = lambda c: c[0] == "xcodebuild" and c[-1] == "test" and "platform=iOS Simulator,id=device-0" in c
        with patch.dict(os.environ, {"SNAPSHOT_RECORD": "1"}):
            status, output = self.execute(snapshots=True)
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone SE (3rd gen) record:", output)
        self.assertIn("FAIL iPhone SE (3rd gen) compare:", output)
        self.assertIn("PASS iPhone Duo record\n", output)
        self.assertIn("PASS iPhone Duo compare\n", output)
        self.assertEqual(self.commands[-2:], [["make", "check"], ["make", "duo"]])

    def test_snapshot_passes_require_duos_own_runtime(self):
        self.devices[runner.REGULAR_RUNTIME].append(self.devices[runner.DUO_RUNTIME].pop())
        status, output = self.execute(snapshots=True)
        self.assertEqual(status, 1)
        self.assertIn("FAIL iPhone Duo compare: No available simulator:", output)
        self.assertNotIn("platform=iOS Simulator,id=device-6", str(self.commands))


if __name__ == "__main__":
    unittest.main()
