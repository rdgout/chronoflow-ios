import argparse
import json
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
XCODEBUILD = [
    "xcodebuild", "-project", "ChronoFlow.xcodeproj", "-derivedDataPath", "build/DerivedData",
    "-onlyUsePackageVersionsFromResolvedFile", "-scheme", "ChronoFlow",
]


def run(command, *, check=True, capture_output=False):
    print("+ " + shlex.join(command), flush=True)
    return subprocess.run(command, cwd=ROOT, check=check, capture_output=capture_output, text=True)


def test_device(device_type, runtime, devices, timeline=False):
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
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    installed = run(
        ["xcrun", "simctl", "get_app_container", udid, "net.chronoflow.app.native", "app"],
        check=False, capture_output=True,
    )
    if installed.returncode == 0:
        run(["xcrun", "simctl", "uninstall", udid, "net.chronoflow.app.native"])
    run(["xcrun", "simctl", "shutdown", udid])
    run(["xcrun", "simctl", "boot", udid])
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])
    run(XCODEBUILD + [
        "-destination", "platform=iOS Simulator,id=" + udid,
        "-only-testing:AppTests", "-only-testing:AppUITests/WindowTests", "-only-testing:DesignSystemTests",
    ] + (["-only-testing:AppCoreTests", "-only-testing:LaunchTests"] if timeline else []) + ["test"])


def main(timeline=False):
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
        phase = "3a" if timeline else "2"
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
    for label, device_type, runtime in MATRIX:
        print("\nTesting " + label + " on " + runtime, flush=True)
        record(label, lambda: test_device(device_type, runtime, devices, timeline))
    record("make check", lambda: run(["make", "check"]))
    record("make duo", lambda: run(["make", "duo"]))
    return report()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeline", action="store_true", help="also run the Phase 3a pure timeline suites on each device")
    raise SystemExit(main(timeline=parser.parse_args().timeline))
