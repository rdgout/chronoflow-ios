import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess


ROOT = Path(__file__).resolve().parents[1]
REGULAR_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DUO_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4"
MATRIX = [
    ("iPhone SE (3rd gen)", "iPhone-SE-3rd-generation", REGULAR_RUNTIME),
    ("iPhone 17e", "iPhone-17e", REGULAR_RUNTIME),
    ("iPhone 17", "iPhone-17", REGULAR_RUNTIME),
    ("iPhone Air", "iPhone-Air", REGULAR_RUNTIME),
    ("iPhone 18 Pro", "iPhone-18-Pro", REGULAR_RUNTIME),
    ("iPhone 18 Pro Max", "iPhone-18-Pro-Max", REGULAR_RUNTIME),
    ("iPhone Duo", "iPhone-Duo", DUO_RUNTIME),
]
XCODEBUILD_COMMON = [
    "xcodebuild", "-project", "ChronoFlow.xcodeproj", "-derivedDataPath", "build/DerivedData",
    "-onlyUsePackageVersionsFromResolvedFile",
]
XCODEBUILD = XCODEBUILD_COMMON + ["-scheme", "ChronoFlow"]


def run(command, *, check=True, capture_output=False, snapshot_record=False):
    print("+ " + shlex.join(command), flush=True)
    environment = os.environ.copy()
    environment.pop("SNAPSHOT_RECORD", None)
    environment.pop("TEST_RUNNER_SNAPSHOT_RECORD", None)
    if snapshot_record:
        environment["TEST_RUNNER_SNAPSHOT_RECORD"] = "1"
    return subprocess.run(command, cwd=ROOT, check=check, capture_output=capture_output, text=True, env=environment)


def test_device(device_type, runtime, devices, timeline=False, scene=False, snapshots=False, snapshot_record=False, readiness=False, welcome=False):
    identifier = "com.apple.CoreSimulator.SimDeviceType." + device_type
    device = next(
        (d for d in devices.get(runtime, []) if d.get("isAvailable") and d.get("deviceTypeIdentifier") == identifier),
        None,
    )
    if device is None:
        raise RuntimeError("No available simulator: " + identifier + " on " + runtime)
    udid = device["udid"]
    if device["state"] == "Shutdown":
        run(["xcrun", "simctl", "boot", udid])
        device["state"] = "Booted"
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    installed = run(
        ["xcrun", "simctl", "get_app_container", udid, "net.chronoflow.app.native", "app"],
        check=False, capture_output=True,
    )
    if installed.returncode == 0:
        run(["xcrun", "simctl", "uninstall", udid, "net.chronoflow.app.native"])
    run(["xcrun", "simctl", "shutdown", udid])
    device["state"] = "Shutdown"
    run(["xcrun", "simctl", "boot", udid])
    device["state"] = "Booted"
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    if welcome and snapshot_record:
        run(XCODEBUILD + [
            "-destination", "platform=iOS Simulator,id=" + udid,
            "-testLanguage", "en", "-testRegion", "US", "-only-testing:AppTests/WelcomeSnapshotTests", "-only-testing:AppTests/WelcomeSnapshotGuardTests", "test",
        ], snapshot_record=True)
        return
    if readiness or welcome:
        destination = [
            "-destination", "platform=iOS Simulator,id=" + udid,
            "-testLanguage", "en", "-testRegion", "US",
        ]
        passes = [
            ("Debug", XCODEBUILD, ["-only-testing:AppTests", "-only-testing:AppCoreTests", "-only-testing:LaunchTests",
                       "-only-testing:DesignSystemTests", "-only-testing:AppUITests/WindowTests",
                       "-only-testing:AppUITests/LaunchSceneTests", "-only-testing:AppUITests/ReadinessTests"]),
            ("Release", XCODEBUILD_COMMON + ["-scheme", "ReadinessRelease"],
             ["ENABLE_TESTABILITY=YES", "-only-testing:AppTests/ReleaseReadinessTests"]),
        ]
        if welcome:
            passes[0][2].extend(["-only-testing:WelcomeTests", "-only-testing:AppUITests/WelcomeTests"])
        errors = []
        for configuration, command, suites in passes:
            try:
                run(command + destination + ["-configuration", configuration] + suites + ["test"])
            except (subprocess.CalledProcessError, OSError) as error:
                errors.append(configuration + ": " + str(error))
        if errors:
            raise RuntimeError("; ".join(errors))
        return
    if snapshots:
        run(XCODEBUILD + [
            "-destination", "platform=iOS Simulator,id=" + udid,
            "-testLanguage", "en", "-testRegion", "US", "-only-testing:LaunchTests",
        ] + (["-only-testing:AppTests", "-only-testing:AppUITests/WindowTests", "-only-testing:AppUITests/LaunchSceneTests"] if scene and not snapshot_record else []) + ["test"], snapshot_record=snapshot_record)
        return
    run(XCODEBUILD + [
        "-destination", "platform=iOS Simulator,id=" + udid,
        "-testLanguage", "en", "-testRegion", "US",
        "-only-testing:AppTests", "-only-testing:AppUITests/WindowTests", "-only-testing:DesignSystemTests",
    ] + (["-only-testing:AppCoreTests", "-only-testing:LaunchTests"] if timeline or scene else []) + (["-only-testing:AppUITests/LaunchSceneTests"] if scene else []) + ["test"])


def main(timeline=False, scene=False, snapshots=False, readiness=False, welcome=False):
    results = []

    def record(label, action):
        try:
            action()
        except (subprocess.CalledProcessError, OSError, ValueError, KeyError, RuntimeError) as error:
            results.append((label, False, str(error)))
            return False
        results.append((label, True, ""))
        return True

    def report():
        phase = "5" if welcome else "4" if readiness else "3c" if snapshots else "3b" if scene else "3a" if timeline else "2"
        print(f"\nPhase {phase} simulator results:", flush=True)
        for label, passed, detail in results:
            print(f"{'PASS' if passed else 'FAIL'} {label}" + (": " + detail if detail else ""), flush=True)
        return int(any(not passed for _, passed, _ in results))

    if not record("make generate", lambda: run(["make", "generate"])):
        return report()
    record("clean build folder", lambda: run(XCODEBUILD + [
        "-destination", "platform=iOS Simulator,name=iPhone 17e,OS=27.2", "clean",
    ]))
    devices = {}

    def discover():
        devices.update(json.loads(run(["xcrun", "simctl", "list", "devices", "-j"], capture_output=True).stdout)["devices"])

    record("list simulators", discover)
    passes = [("compare", False)] if snapshots or welcome else [("", False)]
    if (snapshots or welcome) and os.environ.get("SNAPSHOT_RECORD") == "1":
        passes.insert(0, ("record", True))
    for pass_name, snapshot_record in passes:
        for label, device_type, runtime in MATRIX:
            result_label = f"{label} {pass_name}" if pass_name else label
            print("\nTesting " + result_label + " on " + runtime, flush=True)
            record(result_label, lambda: test_device(
                device_type, runtime, devices, timeline, scene, snapshots, snapshot_record, readiness, welcome,
            ))
    record("make check", lambda: run(["make", "check"]))
    record("make duo", lambda: run(["make", "duo"]))
    return report()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeline", action="store_true", help="also run the Phase 3a pure timeline suites on each device")
    parser.add_argument("--scene", action="store_true", help="also run Phase 3b scene presentation and UI suites on each device")
    parser.add_argument("--snapshots", action="store_true", help="compare Phase 3c snapshots on every D1c device (SNAPSHOT_RECORD=1 records first)")
    parser.add_argument("--readiness", action="store_true", help="run Phase 4 hand-off, readiness and existing scene suites on every D1c device")
    parser.add_argument("--welcome", action="store_true", help="compare Phase 5 Welcome and intro snapshots plus hosted/UI checks on every D1c device (SNAPSHOT_RECORD=1 records Welcome only first)")
    args = parser.parse_args()
    if args.welcome and (args.readiness or args.snapshots):
        parser.error("--welcome includes its own snapshot and readiness comparison suites")
    if args.readiness and args.snapshots:
        parser.error("--readiness and --snapshots run separate comparison suites")
    raise SystemExit(main(timeline=args.timeline, scene=args.scene, snapshots=args.snapshots, readiness=args.readiness, welcome=args.welcome))
