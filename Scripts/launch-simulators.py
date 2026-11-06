import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
REGULAR_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DUO_RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4"
MATRIX = {
    "se": ("iPhone SE (3rd gen)", "iPhone-SE-3rd-generation", REGULAR_RUNTIME),
    "17e": ("iPhone 17e", "iPhone-17e", REGULAR_RUNTIME),
    "17": ("iPhone 17", "iPhone-17", REGULAR_RUNTIME),
    "air": ("iPhone Air", "iPhone-Air", REGULAR_RUNTIME),
    "18pro": ("iPhone 18 Pro", "iPhone-18-Pro", REGULAR_RUNTIME),
    "18promax": ("iPhone 18 Pro Max", "iPhone-18-Pro-Max", REGULAR_RUNTIME),
    "duo": ("iPhone Duo", "iPhone-Duo", DUO_RUNTIME),
}
# Each suite has one scheduling policy. Fixed geometry fixtures are logic; running-window/scale assertions are matrix.
SUITES = {
    "AppTests": {
        "logic": ("LaunchArgumentLogicTests", "RasterPixelLogicTests", "ContentSizeCapLogicTests", "AppIconTests", "KeychainSessionStoreTests", "RootNavigationTests", "StubReadinessTests", "WelcomeSnapshotGuardTests"),
        "matrix": ("ContentSizeCapTests", "LaunchArgumentsTests", "LaunchConnectionTests", "LaunchFrameParityTests",
                   "LaunchHandOffTests", "LaunchPlaybackTests", "LaunchSceneTests", "LaunchStoryboardTests", "LaunchTestHostTests",
                   "MoonTargetWindowTests", "TimelineWindowTests", "WelcomeHandOverTests", "WelcomeSnapshotTests"),
        "release": ("ReleaseReadinessTests",),
    },
    "AppUITests": {
        "logic": ("ReadinessTests", "WelcomeLogicTests", "LaunchImageComparisonTests"),
        "matrix": ("WindowTests", "LaunchSceneTests", "WelcomeTests"),
    },
    "AppCoreTests": {"logic": ("CatalogTests", "CubicBezierTests", "LaunchCoordinatorTests", "LaunchIntroTests", "LaunchLifecycleTests",
                                 "LaunchReadinessTests", "LaunchSignpostsTests", "MoonAnchorStoreTests", "MoonTargetTests", "SessionStoreTests", "SmokeTests")},
    "DesignSystemTests": {"logic": ("ExactLineTextLayoutTests", "PrimitiveTests", "SmokeTests", "TypographyTests"),
                          "matrix": ("LaunchImagesTests",)},
    "LaunchTests": {"logic": ("FlightPathTests", "LaunchGlowTests", "LaunchLayoutTests", "LaunchRadialLayerTests", "LaunchSnapshotCoverageTests",
                              "LaunchSnapshotGeometryTests", "LaunchTimelineTests", "ReadyTimelineTests", "SmokeTests", "WelcomeTimelineTests"),
                    "matrix": ("LaunchSnapshotTests",)},
    "WelcomeTests": {"logic": ("SmokeTests",)},
    "PerfUITests": {"perf": ("LaunchPerfTests",)},
}
SNAPSHOTS = ("LaunchTests/LaunchSnapshotTests", "AppTests/WelcomeSnapshotTests", "AppTests/WelcomeSnapshotGuardTests")
XCODEBUILD_COMMON = ["xcodebuild", "-project", "ChronoFlow.xcodeproj", "-derivedDataPath", "build/DerivedData",
                     "-onlyUsePackageVersionsFromResolvedFile"]


@dataclass(frozen=True)
class Destination:
    alias: str
    udid: str
    state: str

    @property
    def flag(self):
        return "platform=iOS Simulator,id=" + self.udid

    @property
    def directory(self):
        return ROOT / "build/test-results" / self.alias


@dataclass
class Result:
    device: str
    suite: str
    passed: bool
    detail: str = ""


def environment(record=False):
    result = os.environ.copy()
    for key in ("SNAPSHOT_RECORD", "TEST_RUNNER_SNAPSHOT_RECORD"):
        result.pop(key, None)
    if record:
        result["TEST_RUNNER_SNAPSHOT_RECORD"] = "1"
    return result


def run(command, *, log=None, capture=False, record=False, check=True):
    print("+ " + shlex.join(map(str, command)), flush=True)
    kwargs = dict(cwd=ROOT, text=True, env=environment(record), check=check)
    if log is None:
        return subprocess.run(command, capture_output=capture, **kwargs)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as output:
        output.write("+ " + shlex.join(map(str, command)) + "\n")
        output.flush()
        return subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, **kwargs)


def resolve(alias, devices):
    _, device_type, runtime = MATRIX[alias]
    identifier = "com.apple.CoreSimulator.SimDeviceType." + device_type
    matches = [d for d in devices.get(runtime, []) if d.get("isAvailable") and d.get("deviceTypeIdentifier") == identifier]
    if not matches:
        raise RuntimeError("No available simulator: " + identifier + " on " + runtime)
    device = matches[0]
    return Destination(alias, device["udid"], device["state"])


def prepare(destination):
    log = destination.directory / "prepare.log"
    if destination.state != "Booted":
        run(["xcrun", "simctl", "boot", destination.udid], log=log)
    run(["xcrun", "simctl", "bootstatus", destination.udid, "-b"], log=log)
    installed = run(["xcrun", "simctl", "get_app_container", destination.udid, "net.chronoflow.app.native", "app"], capture=True, check=False)
    if installed.returncode == 0:
        run(["xcrun", "simctl", "uninstall", destination.udid, "net.chronoflow.app.native"], log=log)


def selectors(policy):
    return [f"{target}/{suite}" for target, groups in SUITES.items() for suite in groups.get(policy, ())]


def expand(only):
    known = set(selectors("logic") + selectors("matrix") + selectors("release"))
    result = []
    for item in only:
        matches = sorted(s for s in known if s == item or s.startswith(item + "/") or item.startswith(s + "/"))
        if not matches:
            raise ValueError("Unclassified test selector: " + item)
        result.extend([item] if item in known or any(item.startswith(s + "/") for s in known) else matches)
    return list(dict.fromkeys(result))


def selection(mode, alias, only=()):
    if only:
        return expand(only)
    if mode == "launch-snapshots":
        return ["LaunchTests"]
    if mode == "snapshots":
        return ["DesignSystemTests", "LaunchTests", "WelcomeTests", "AppTests/WelcomeSnapshotTests", "AppTests/WelcomeSnapshotGuardTests"]
    result = ["AppTests", "AppUITests", "AppCoreTests", "DesignSystemTests", "LaunchTests", "WelcomeTests"]
    if mode != "test": result.append("AppTests/ReleaseReadinessTests")
    return result


def configurations(selected):
    release = set(selectors("release"))
    groups = {"Debug": [], "Release": []}
    for suite in selected:
        groups["Release" if any(suite == s or suite.startswith(s + "/") for s in release) else "Debug"].append(suite)
    return {config: suites for config, suites in groups.items() if suites}


def build_command(configuration):
    scheme = "ChronoFlow" if configuration == "Debug" else "ReadinessRelease"
    return XCODEBUILD_COMMON + ["-scheme", scheme, "-configuration", configuration]


def build(configuration):
    return run(build_command(configuration) + ["-destination", "generic/platform=iOS Simulator"]
               + (["ENABLE_TESTABILITY=YES"] if configuration == "Release" else []) + ["build-for-testing"],
               log=ROOT / "build/test-results/build" / (configuration + ".log"))


def test_command(destination, configuration, selected, bundle):
    return build_command(configuration) + ["-destination", destination.flag, "-testLanguage", "en", "-testRegion", "US",
        "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1", "-resultBundlePath", str(bundle)] + [
        "-only-testing:" + suite for suite in selected] + ["test-without-building"]


def result_nodes(value, target=None):
    if isinstance(value, dict):
        kind = str(value.get("nodeType", ""))
        if "bundle" in kind.lower() or kind == "Test Target":
            name = str(value.get("name", "")).removesuffix(".xctest")
            target = name if name in SUITES else target
        if kind == "Test Case":
            identifier = str(value.get("nodeIdentifier", ""))
            qualified = next((s.split("/")[0] for s in selectors("logic") + selectors("matrix") + selectors("release")
                              if identifier.startswith(s + "/")), target)
            yield dict(value, target=qualified)
        for child in value.values():
            yield from result_nodes(child, target)
    elif isinstance(value, list):
        for child in value:
            yield from result_nodes(child, target)


def read_results(destination, label, selected, bundle, returncode, log):
    detail = ""
    try:
        report = run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle), "--compact"], capture=True)
        nodes = list(result_nodes(json.loads(report.stdout)))
        if not nodes:
            raise RuntimeError("xcresult contains no executed test cases")
        results = []
        for suite in selected:
            parts = suite.split("/")
            matches = [n for n in nodes if (len(parts) == 1 or parts[1] in str(n.get("nodeIdentifier", "")))
                       and (n.get("target") is None or n["target"] == parts[0])
                       and (len(parts) <= 2 or parts[2].removesuffix("()") in str(n.get("nodeIdentifier", "")))]
            failed = [str(n.get("nodeIdentifier", n.get("name"))) for n in matches if n.get("result") not in ("Passed", "Skipped", "Expected Failure")]
            passed = bool(matches) and not failed
            results.append(Result(destination.alias, label + " " + suite, passed,
                                  "; ".join(failed) if matches else "No tests matched; see " + str(log.relative_to(ROOT))))
        if returncode and all(r.passed for r in results):
            results.append(Result(destination.alias, label, False, f"xcodebuild exited {returncode}; see {log.relative_to(ROOT)}"))
        return results
    except (subprocess.CalledProcessError, OSError, ValueError, RuntimeError) as error:
        detail = str(error)
    failures = []
    if log.exists():
        content = log.read_text(errors="replace")
        failures = re.findall(r"Test Case '([^']+)' failed|[✘×] Test (.+?) (?:failed|recorded an issue)", content)
    names = [a or b for a, b in failures]
    return [Result(destination.alias, label + " " + suite, False,
                   "; ".join(names) or detail + "; see " + str(log.relative_to(ROOT))) for suite in selected]


def test_pass(destination, configuration, selected, label, record=False):
    bundle = destination.directory / (label + ".xcresult")
    log = destination.directory / (label + ".log")
    if bundle.exists():
        shutil.rmtree(bundle)
    log.unlink(missing_ok=True)
    try:
        completed = run(test_command(destination, configuration, selected, bundle), log=log, record=record, check=False)
        return read_results(destination, label, selected, bundle, completed.returncode, log)
    except (subprocess.CalledProcessError, OSError) as error:
        return [Result(destination.alias, label + " " + suite, False, str(error)) for suite in selected]


def recording_selection(selected, mode, recording):
    candidates = SNAPSHOTS if recording == "all" else SNAPSHOTS[:1] if recording == "launch" or mode == "launch-snapshots" else SNAPSHOTS[1:]
    return [c for c in candidates if any(c == s or c.startswith(s + "/") or s.startswith(c + "/") for s in selected)]


def test_device(destination, selected, mode, recording, ready):
    results = []
    try:
        prepare(destination)
    except (subprocess.CalledProcessError, OSError) as error:
        return [Result(destination.alias, suite, False, "Preparation: " + str(error)) for suite in selected]
    record_suites = recording_selection(selected, mode, recording) if recording else []
    if record_suites and ready.get("Debug"):
        results += test_pass(destination, "Debug", record_suites, "record", record=True)
    for configuration, suites in configurations(selected).items():
        if ready.get(configuration):
            results += test_pass(destination, configuration, suites, configuration + "-compare")
        else:
            results += [Result(destination.alias, s, False, configuration + " build unavailable") for s in suites]
    return results


def main(mode="welcome", aliases=None, only=(), concurrency=None, reuse_build=False, generate=True):
    started = time.monotonic()
    concurrency = int(concurrency if concurrency is not None else os.environ.get("SIM_CONCURRENCY", "4"))
    if not 1 <= concurrency <= 4:
        raise ValueError("SIM_CONCURRENCY must be an integer from 1 to 4")
    aliases = list(dict.fromkeys(aliases or MATRIX))
    if set(aliases) - MATRIX.keys():
        raise ValueError("Unknown device aliases: " + " ".join(sorted(set(aliases) - MATRIX.keys())))
    selections = {alias: selection(mode, alias, only) for alias in aliases}
    results = []
    if generate:
        run(["make", "generate"])
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"], capture=True).stdout)["devices"]
    destinations = []
    for alias in aliases:
        try:
            destinations.append(resolve(alias, devices))
        except (RuntimeError, KeyError) as error:
            results.append(Result(alias, "destination", False, str(error)))
    ready = {}
    for configuration in dict.fromkeys(c for alias in aliases for c in configurations(selections[alias])):
        try:
            if not reuse_build:
                build(configuration)
            ready[configuration] = True
        except (subprocess.CalledProcessError, OSError) as error:
            ready[configuration] = False
            results.append(Result("build", configuration, False, str(error)))
    recording = os.environ.get("SNAPSHOT_RECORD", "0")
    if recording not in ("0", "1", "launch", "all"):
        raise ValueError("SNAPSHOT_RECORD must be 0, 1, launch or all")
    with ThreadPoolExecutor(max_workers=min(concurrency, len(destinations) or 1)) as pool:
        futures = [pool.submit(test_device, d, selections[d.alias], mode, recording if recording != "0" else None, ready) for d in destinations]
        for future in futures:
            results.extend(future.result())
    print("\nSimulator results:", flush=True)
    for result in results:
        print(f"{'PASS' if result.passed else 'FAIL'} {result.device} {result.suite}" + (": " + result.detail if result.detail else ""), flush=True)
    print(f"Elapsed: {time.monotonic() - started:.1f}s; concurrency={concurrency}", flush=True)
    return int(any(not r.passed for r in results))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build once, then run classified suites in parallel on the D1c simulators.")
    parser.add_argument("--devices", nargs="+", choices=MATRIX, help="device aliases (default: all seven)")
    parser.add_argument("--no-generate", action="store_true")
    parser.add_argument("--mode", choices=("welcome", "test", "snapshots"), default="welcome")
    for flag in ("timeline", "scene", "snapshots", "readiness", "welcome"):
        parser.add_argument("--" + flag, action="store_true", help="compatibility matrix entry point; uses the suite classification")
    args = parser.parse_args()
    mode = "launch-snapshots" if args.snapshots and not args.scene else args.mode
    try:
        raise SystemExit(main(mode, args.devices, (), reuse_build=False, generate=not args.no_generate))
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError, RuntimeError) as error:
        parser.exit(1, str(error) + "\n")
