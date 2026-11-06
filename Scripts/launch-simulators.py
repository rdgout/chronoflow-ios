import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import shlex
import statistics
import shutil
import subprocess
import time
import threading


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
SUITES = {'AppTests': {'logic': ('AuthControlTests', 'LaunchArgumentLogicTests',
                        'RasterPixelLogicTests',
                        'ContentSizeCapLogicTests',
                        'AppIconTests',
                        'KeychainSessionStoreTests',
                        'RootNavigationTests',
                        'StubReadinessTests',
                        'WelcomeSnapshotGuardTests',
                        'WelcomeAuditPolicyTests',
                        'AccountStorageLifecycleTests',
                        'DataSourceBuildSettingTests',
                        'DataSourceFactoryHostedTests',
                        'SessionLifecycleTests',
                        'SyncLifecycleTests',
                        'AccountWipeTests',
                        'SessionReadinessTests'),
              'matrix': ('ContentSizeCapTests',
                         'LaunchArgumentsTests',
                         'LaunchConnectionTests',
                         'LaunchHandOffTests',
                         'LaunchPlaybackTests',
                         'LaunchSceneTests',
                         'LaunchTestHostTests',
                         'DeviceGeometrySmokeTests',
                         'WelcomeHandOverTests',
                         'LaunchImageMutationTests',
                         'SnapshotContainerTests'),
              'profiles': ('LaunchSnapshotTests', 'WelcomeSnapshotTests'),
              'reference': ('LaunchFrameParityTests', 'LaunchStoryboardTests'),
              'release': ('ReleaseReadinessTests',)},
 'RenderTests': {'profiles': ('WelcomeRenderingTests',)},
 'AppUITests': {'logic': ('ReadinessTests', 'WelcomeLogicTests'),
                'reference': ('LaunchToWelcomeTests', 'LaunchSceneTests', 'LaunchSceneDarkTests'),
                'matrix': ('WelcomeTests', 'WelcomeEnglishAccessibilityTests', 'WelcomeDutchAccessibilityTests')},
 'AppCoreTests': {'host': ('CatalogTests',
                           'CubicBezierTests',
                           'LaunchCoordinatorTests',
                           'LaunchIntroTests',
                           'LaunchLifecycleTests',
                           'LaunchReadinessTests',
                           'LaunchSignpostsTests',
                           'MoonAnchorStoreTests',
                           'MoonTargetTests',
                           'SessionStoreTests',
                           'SessionControllerTests',
                           'SignOutTests',
                           'StoredDataReadinessTests',
                           'DeviceIdentityTests',
                           'SmokeTests')},
 'DesignSystemTests': {'logic': ('ExactLineTextLayoutTests', 'PrimitiveTests', 'SmokeTests', 'TypographyTests'),
                       'matrix': ('LaunchImagesTests',)},
 'LaunchTests': {'logic': ('FlightPathTests',
                           'LaunchGlowTests',
                           'LaunchLayoutTests',
                           'DeviceGeometryTests',
                           'LaunchRadialLayerTests',
                           'LaunchSnapshotCoverageTests',
                           'SnapshotReferenceTests',
                           'SnapshotProfileTests',
                           'LaunchSnapshotGeometryTests',
                           'LaunchTimelineTests',
                           'ReadyTimelineTests',
                           'SmokeTests',
                           'WelcomeTimelineTests')},
 'AuthTests': {'host': ('AuthFormModelTests', 'AuthFailureMappingTests', 'AuthCatalogTests', 'AuthLayoutTests')},
 'WelcomeTests': {'logic': ('SmokeTests', 'WelcomeGeometryTests')},
 'ToolingTests': {'host': ('LaunchImageComparisonTests', 'UIWaitTests')},
 'PerfUITests': {'perf': ('LaunchPerfTests',)},
 'DataAccessTests': {'host': ('ContractsTests',
                              'DataSourceSelectionTests',
                              'APIClientTests',
                              'APICookieTests',
                              'APIDataSourceTests',
                              'MockAuthTests',
                              'MockAccountTripsTests',
                              'MockPersistenceTests',
                              'DataSourceParityTests')},
 'SyncTests': {'host': ('LocalMutationsTests',
                        'OutboxFlusherTests',
                        'FullPullTests',
                        'PendingProtectionTests',
                        'PlanRetentionTests',
                        'CheckOffReconcilerTests',
                        'SyncEngineTests',
                        'DataSourceIntegrationTests',
                        'SyncTriggerTests',
                        'SessionSyncReadinessTests',
                        'SessionWipeTests')},
 'LocalStoreTests': {'host': ('SchemaV1Tests',
                              'AccountDatabaseTests',
                              'RecordsTests',
                              'RepositoryObservationTests',
                              'SessionAccountDatabaseTests',
                              'AccountWiperTests',
                              'AccountReadinessTests')}}
SNAPSHOTS = ("AppTests/LaunchSnapshotTests", "AppTests/WelcomeSnapshotTests", "AppTests/WelcomeSnapshotGuardTests", "RenderTests/WelcomeRenderingTests")
XCODEBUILD_COMMON = ["xcodebuild", "-project", "ChronoFlow.xcodeproj", "-derivedDataPath", "build/DerivedData",
                     "-onlyUsePackageVersionsFromResolvedFile"]

# Device-wide mutations must be registered here; launch/window-scoped traits are clone-safe.
SERIAL_TESTS = ("AppUITests/LaunchSceneTests", "AppUITests/LaunchSceneDarkTests", "AppUITests/LaunchToWelcomeTests")
PARALLEL_TARGETS = {"AppTests", "AppUITests", "RenderTests"}


@dataclass(frozen=True)
class TestPass:
    selected: tuple
    skipped: tuple = ()
    workers: int = 1
    suffix: str = "compare"


def split_passes(configuration, selected, workers, serial=SERIAL_TESTS):
    if configuration != "Debug" or workers == 1:
        return [TestPass(tuple(selected))]
    parallel, isolated, skipped = [], [], []
    for selector in selected:
        if any(selector == item or selector.startswith(item + "/") for item in serial):
            isolated.append(selector)
        else:
            parallel.append(selector)
            children = [item for item in serial if item.startswith(selector + "/")]
            isolated.extend(children)
            skipped.extend(children)
    passes = [TestPass(tuple(parallel), tuple(skipped), workers)] if parallel else []
    if isolated:
        passes.append(TestPass(tuple(dict.fromkeys(isolated)), suffix="serial"))
    return passes


class WorkerBudget:
    def __init__(self, slots):
        self.available = slots
        self.condition = threading.Condition()

    @contextmanager
    def claim(self, count):
        with self.condition:
            self.condition.wait_for(lambda: self.available >= count)
            self.available -= count
        try:
            yield
        finally:
            with self.condition:
                self.available += count
                self.condition.notify_all()


def budgeted_device(budget, workers, *args):
    with budget.claim(workers):
        return test_device(*args, workers=workers)


def workers_for(alias, selected, timings, single_device=False):
    override = os.environ.get("TEST_WORKERS", "2")
    count = int(override)
    if not 1 <= count <= 4:
        raise ValueError("TEST_WORKERS must be an integer from 1 to 4")
    eligible = any(s.split("/")[0] in PARALLEL_TARGETS for s in selected)
    return count if eligible and (single_device or max(STATIC_MATRIX_WALL[alias], estimated_seconds(alias, selected, timings)) >= 400) else 1

INTRO_ORDER_TEST = "AppTests/WelcomeSnapshotTests/frozenIntroOrderIndependence()"

TIMINGS_PATH = ROOT / "build/test-results/timings.json"
STATIC_MATRIX_WALL = dict(se=271, **{"17e": 490, "17": 328, "air": 341, "18pro": 328, "18promax": 525, "duo": 483})
STATIC_SUITE_SECONDS = {
    "AppUITests/ReadinessTests": 75, "AppUITests/WelcomeLogicTests": 15,
    "AppUITests/WelcomeTests": 110, "AppUITests/LaunchSceneTests": 55,
    "AppUITests/LaunchToWelcomeTests": 12, "AppTests/WelcomeSnapshotTests": 180,
    "AppTests/LaunchFrameParityTests": 16, "AppTests/LaunchSceneTests": 12,
    "AppTests/LaunchPlaybackTests": 10, "AppTests/LaunchStoryboardTests": 6,
    "DesignSystemTests/ExactLineTextLayoutTests": 8,
}


def positive_seconds(value):
    try:
        number = float(str(value).removesuffix("s"))
        return number if math.isfinite(number) and number >= 0 else None
    except (TypeError, ValueError):
        return None


def machine_resources():
    cores = os.cpu_count() or 2
    available = 0
    try:
        report = subprocess.run(["vm_stat"], capture_output=True, text=True, check=True).stdout
        page_size = int(re.search(r"page size of (\d+) bytes", report)[1])
        available = sum(int(re.search(r"Pages " + kind + r":\s+(\d+)", report)[1])
                        for kind in ("free", "inactive", "speculative")) * page_size
    except (OSError, subprocess.CalledProcessError, TypeError, ValueError):
        pass
    return cores, available


def concurrency_limit(override=None, resources=None):
    if override is None:
        override = os.environ.get("SIM_CONCURRENCY")
    if override not in (None, ""):
        number = int(override)
        if not 1 <= number <= 7:
            raise ValueError("SIM_CONCURRENCY must be an integer from 1 to 7")
        return number
    cores, available = resources if resources is not None else machine_resources()
    # Reserve 2 GiB for the host/build, then budget 1 GiB per simulator destination.
    memory_slots = max(1, (available - 2 * 1024**3) // 1024**3) if available else 2
    return min(7, max(1, cores // 2), memory_slots)


def load_timings(path=None):
    path = path or TIMINGS_PATH
    try:
        value = json.loads(path.read_text())
        if value.get("version") == 1 and isinstance(value.get("devices"), dict):
            return value
    except (OSError, ValueError, AttributeError):
        pass
    return {"version": 1, "devices": {}}


def save_timings(timings, path=None):
    path = path or TIMINGS_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(timings, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def log_timings(content):
    target = None
    suites, tests = {}, {}
    selected = re.findall(r"-only-testing:([^\s'\"]+)", content.splitlines()[0] if content else "")
    for line in content.splitlines():
        bundle = re.search(r"Test Suite '([\w]+)\.xctest' started", line)
        if bundle:
            target = bundle[1]
        case = re.search(r"Test Case '-\[(\w+)\.(\w+) ([^]]+)\]' passed \(([\d.]+) seconds\)", line)
        if case:
            name = case[1] + "/" + case[2]
            duration = float(case[4])
            suites[name] = suites.get(name, 0) + duration
            tests[name + "/" + case[3]] = duration
        clone = re.search(r"Test case '([^']+)' (?:passed|failed) on '[^']+ - ([^']+?) \(\d+\)' \(([\d.]+) seconds\)", line)
        if clone:
            path = clone[1].replace('.', '/', 1).split('/')
            process = clone[2]
            candidates = {s.split('/')[0] + '/' + path[0] for s in selected
                          if len(s.split('/')) >= 2 and s.split('/')[1] == path[0]}
            if process.endswith('-Runner'):
                candidates = {s for s in candidates if s.startswith(process.removesuffix('-Runner') + '/')}
            if len(path) == 2 and len(candidates) == 1:
                name = candidates.pop()
                duration = float(clone[3])
                suites[name] = suites.get(name, 0) + duration
                tests[name + '/' + path[1]] = duration
        swift = re.search(r"[✔✓] Suite (\w+) passed after ([\d.]+) seconds", line)
        if swift:
            name = f"{target}/{swift[1]}"
            if name in selected:
                suites[name] = float(swift[2])
    wall = re.findall(r"([\d.]+) elapsed -- Testing started completed", content)
    return dict(suites=suites, tests=tests, wall=float(wall[-1]) if wall else 0, selection=list(dict.fromkeys(selected)))


def bootstrap_timings(timings, directory=None):
    directory = directory or ROOT / "build/test-results"
    for alias in MATRIX:
        if alias in timings["devices"]:
            continue
        log = directory / alias / "Debug-compare.log"
        if log.exists():
            sample = log_timings(log.read_text(errors="replace"))
            if sample["suites"]:
                if set(selectors("matrix")) <= set(sample["selection"]) and sample["wall"]:
                    logic = sum(t for s, t in sample["suites"].items() if s in selectors("logic"))
                    sample["matrix_wall"] = max(1, sample["wall"] - logic)
                timings["devices"][alias] = sample
    return timings


def suite_seconds(suite, alias, timings):
    devices = timings.get("devices", {})
    own = positive_seconds(devices.get(alias, {}).get("suites", {}).get(suite))
    if own is not None:
        return own
    samples = [positive_seconds(d.get("suites", {}).get(suite)) for d in devices.values()]
    samples = [s for s in samples if s is not None]
    return statistics.median(samples) if samples else STATIC_SUITE_SECONDS.get(suite, 1)


def estimated_seconds(alias, selected, timings):
    matrix = set(selectors("matrix"))
    if matrix <= set(selected):
        measured = positive_seconds(timings.get("devices", {}).get(alias, {}).get("matrix_wall"))
        return (measured or STATIC_MATRIX_WALL[alias]) + sum(suite_seconds(s, alias, timings) for s in selected if s not in matrix)
    return 20 + sum(suite_seconds(s, alias, timings) for s in selected)


def schedule(mode, aliases, only=(), timings=None):
    timings = timings or {"devices": {}}
    if only:
        return {a: expand(only) for a in aliases}, list(aliases)
    if mode not in ("matrix", "welcome"):
        return {a: selection(mode, a) for a in aliases}, list(aliases)
    else:
        selections = {a: selection(mode, a, include_logic=False) for a in aliases}
        logic = selection(mode, aliases[0], include_matrix=False)
        # LPT places each once-only suite on the destination with the earliest predicted finish.
        for suite in sorted(logic, key=lambda s: (-max(suite_seconds(s, a, timings) for a in aliases), s)):
            alias = min(aliases, key=lambda a: (estimated_seconds(a, selections[a], timings) + suite_seconds(suite, a, timings), aliases.index(a)))
            selections[alias].append(suite)
    if "17e" in aliases:
        selections["17e"] += selectors("profiles") + selectors("reference")
    order = sorted(aliases, key=lambda a: (-estimated_seconds(a, selections[a], timings), aliases.index(a)))
    return selections, order


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


def environment(record=False, intro_order=None):
    result = os.environ.copy()
    for key in ("SNAPSHOT_RECORD", "TEST_RUNNER_SNAPSHOT_RECORD", "CF_INTRO_ORDER", "TEST_RUNNER_CF_INTRO_ORDER"):
        result.pop(key, None)
    if record:
        result["TEST_RUNNER_SNAPSHOT_RECORD"] = "1"
    if intro_order:
        result["TEST_RUNNER_CF_INTRO_ORDER"] = intro_order
    return result


def run(command, *, log=None, capture=False, record=False, check=True, intro_order=None):
    print("+ " + shlex.join(map(str, command)), flush=True)
    kwargs = dict(cwd=ROOT, text=True, env=environment(record, intro_order), check=check)
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
    known = set(selectors("logic") + selectors("matrix") + selectors("release") + selectors("profiles") + selectors("reference"))
    result = []
    for item in only:
        matches = sorted(s for s in known if s == item or s.startswith(item + "/") or item.startswith(s + "/"))
        if not matches:
            raise ValueError("Unclassified test selector: " + item)
        result.extend([item] if item in known or any(item.startswith(s + "/") for s in known) else matches)
    return list(dict.fromkeys(result))


IOS_METHODS = (
    "DesignSystemTests/LaunchImagesTests",
    "DesignSystemTests/TypographyTests/uiFontsUseTheExactFacesAndKeepTheSplashFixed()",
    "DesignSystemTests/ExactLineTextLayoutTests/scaledHeadlinePitchAndGlyphsFitNaturalLabels()",
    "DesignSystemTests/ExactLineTextLayoutTests/glyphCanvasDetectsClippingOutsideTheLineBox()",
)


def selection(mode, alias, only=(), include_logic=True, include_matrix=True):
    if only:
        return expand(only)
    if mode == "snapshots":
        return list(SNAPSHOTS) + ["AppTests/SnapshotContainerTests"]
    if mode in ("check", "test", "runtime"):
        result = [s for policy in ("logic", "matrix") for s in selectors(policy)
                  if s.startswith(("AppTests/", "AppUITests/"))]
        result += list(IOS_METHODS)
        if alias == "17e":
            result += selectors("reference")
        if mode == "check":
            result += selectors("profiles")
        if mode != "test":
            result += selectors("release")
        return list(dict.fromkeys(result))
    result = selectors("matrix") if include_matrix else []
    if include_logic:
        result += selectors("logic") + selectors("release")
    if mode == "launch-snapshots":
        return [SNAPSHOTS[0]]
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


def test_command(destination, configuration, selected, bundle, workers=1, skipped=()):
    return build_command(configuration) + ["-destination", destination.flag, "-testLanguage", "en", "-testRegion", "US",
        "-parallel-testing-enabled", "YES" if workers > 1 else "NO",
        "-parallel-testing-worker-count", str(workers),
        "-maximum-concurrent-test-simulator-destinations", "1", "-resultBundlePath", str(bundle)] + [
        "-only-testing:" + suite for suite in selected] + ["-skip-testing:" + suite for suite in skipped] + ["test-without-building"]


def result_nodes(value, target=None):
    if isinstance(value, dict):
        kind = str(value.get("nodeType", ""))
        if "bundle" in kind.lower() or kind == "Test Target":
            name = str(value.get("name", "")).removesuffix(".xctest")
            target = name if name in SUITES else target
        if kind == "Test Case":
            identifier = str(value.get("nodeIdentifier", ""))
            qualified = next((s.split("/")[0] for s in selectors("logic") + selectors("matrix") + selectors("release") + selectors("profiles")
                              if identifier.startswith(s + "/")), target)
            yield dict(value, target=qualified)
        for child in value.values():
            yield from result_nodes(child, target)
    elif isinstance(value, list):
        for child in value:
            yield from result_nodes(child, target)


def matching_nodes(nodes, selector):
    requested = selector.split("/")
    matches = []
    for node in nodes:
        path = str(node.get("nodeIdentifier", "")).split("/")
        target = node.get("target")
        if len(path) >= 3 and path[0] in SUITES:
            target = path.pop(0)
        if target != requested[0] or not path or path[0] != requested[1]:
            continue
        if len(requested) > 2 and (len(path) < 2 or path[1].removesuffix("()") != requested[2].removesuffix("()")):
            continue
        matches.append(node)
    return matches


def enumerate_intro_test(destination):
    directory = destination.directory
    listing = directory / "intro-tests.txt"
    listing.unlink(missing_ok=True)
    command = build_command("Debug") + [
        "-destination", destination.flag, "-testLanguage", "en", "-testRegion", "US",
        "-parallel-testing-enabled", "NO", "-only-testing:AppTests/WelcomeSnapshotTests",
        "-enumerate-tests", "-test-enumeration-style", "flat", "-test-enumeration-format", "text",
        "-test-enumeration-output-path", str(listing), "test-without-building",
    ]
    run(command, log=directory / "intro-enumeration.log", intro_order="fresh")
    identifiers = listing.read_text().splitlines()
    if INTRO_ORDER_TEST not in {line.strip() for line in identifiers}:
        raise RuntimeError("Intro test identifier absent from enumeration: " + INTRO_ORDER_TEST + "; see " + str(listing))


def read_results(destination, label, selected, bundle, returncode, log, timing=None, require_executed=False):
    detail = ""
    try:
        report = run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle), "--compact"], capture=True)
        nodes = list(result_nodes(json.loads(report.stdout)))
        if not nodes:
            raise RuntimeError("xcresult contains no executed test cases")
        results = []
        if timing is not None:
            for suite in selected:
                matches = matching_nodes(nodes, suite)
                executed = [n for n in matches if n.get("result") in ("Passed", "Failed", "Expected Failure")]
                durations = [positive_seconds(n.get("durationInSeconds", n.get("duration"))) for n in executed]
                if durations and all(d is not None for d in durations):
                    timing.setdefault("suites", {})[suite] = sum(durations)
                    for node, duration in zip(executed, durations):
                        identifier = str(node.get("nodeIdentifier"))
                        target = suite.split("/")[0]
                        if not identifier.startswith(target + "/"):
                            identifier = target + "/" + identifier
                        timing.setdefault("tests", {})[identifier] = duration
        for suite in selected:
            matches = matching_nodes(nodes, suite)
            failed = [str(n.get("nodeIdentifier", n.get("name"))) for n in matches if n.get("result") not in ("Passed", "Skipped", "Expected Failure")]
            passed = bool(matches) and not failed
            if require_executed and not any(n.get("result") == "Passed" for n in matches):
                passed = False
                failed.append("Diagnostic did not execute and pass")
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


def test_pass(destination, configuration, selected, label, record=False, intro_order=None, timing=None, workers=1, skipped=()):
    bundle = destination.directory / (label + ".xcresult")
    log = destination.directory / (label + ".log")
    if bundle.exists():
        shutil.rmtree(bundle)
    log.unlink(missing_ok=True)
    try:
        completed = run(test_command(destination, configuration, selected, bundle, workers, skipped), log=log, record=record, check=False, intro_order=intro_order)
        return read_results(destination, label, selected, bundle, completed.returncode, log, timing, require_executed=intro_order is not None)
    except (subprocess.CalledProcessError, OSError) as error:
        return [Result(destination.alias, label + " " + suite, False, str(error)) for suite in selected]


def recording_selection(selected, mode, recording):
    candidates = SNAPSHOTS[:2] if recording == "all" or (recording == "1" and mode == "snapshots") else SNAPSHOTS[:1] if recording == "launch" or mode == "launch-snapshots" else SNAPSHOTS[1:2]
    return [s for s in selected if any(s == c or s.startswith(c + "/") for c in candidates)]


def test_device(destination, selected, mode, recording, ready, intro_order_check=False, timing=None, workers=1):
    started = time.monotonic()
    results = []
    try:
        prepare(destination)
    except (subprocess.CalledProcessError, OSError) as error:
        return [Result(destination.alias, suite, False, "Preparation: " + str(error)) for suite in selected]
    if intro_order_check:
        if not ready.get("Debug"):
            return [Result(destination.alias, s, False, "Debug build unavailable") for s in selected]
        try:
            enumerate_intro_test(destination)
        except (subprocess.CalledProcessError, OSError, RuntimeError) as error:
            return [Result(destination.alias, "intro enumeration", False, str(error))]
        for order in ("fresh", "warm"):
            results += test_pass(destination, "Debug", selected, "order-" + order, intro_order=order)
        return results
    record_suites = recording_selection(selected, mode, recording) if recording and destination.alias == "17e" else []
    if record_suites and ready.get("Debug"):
        results += test_pass(destination, "Debug", record_suites, "record", record=True)
    for configuration, suites in configurations(selected).items():
        if ready.get(configuration):
            for part in split_passes(configuration, suites, workers):
                results += test_pass(destination, configuration, part.selected, configuration + "-" + part.suffix,
                                     timing=timing, workers=part.workers, skipped=part.skipped)
        else:
            results += [Result(destination.alias, s, False, configuration + " build unavailable") for s in suites]
    if timing is not None and all(r.passed for r in results):
        timing["wall"] = time.monotonic() - started
        timing["selection"] = selected
        if set(selectors("matrix")) <= set(selected):
            logic = sum(timing.get("suites", {}).get(s, suite_seconds(s, destination.alias, {}))
                        for s in selected if s not in selectors("matrix"))
            timing["matrix_wall"] = max(1, timing["wall"] - logic)
    return results


def main(mode="check", aliases=None, only=(), concurrency=None, reuse_build=False, generate=True, intro_order_check=False):
    started = time.monotonic()
    resources = machine_resources()
    concurrency = concurrency_limit(concurrency, resources)
    print(f"Host: {resources[0]} logical cores, {resources[1] / 1024**3:.1f} GiB available; destination limit={concurrency}", flush=True)
    aliases = list(dict.fromkeys(aliases or (MATRIX if mode in ("matrix", "welcome") else ["17e"])))
    if set(aliases) - MATRIX.keys():
        raise ValueError("Unknown device aliases: " + " ".join(sorted(set(aliases) - MATRIX.keys())))
    if intro_order_check:
        only = [INTRO_ORDER_TEST]
    timings = bootstrap_timings(load_timings())
    selections, order = schedule(mode, aliases, only, timings)
    print("Schedule (longest first): " + ", ".join(f"{a} ~{estimated_seconds(a, selections[a], timings):.0f}s" for a in order), flush=True)
    workers = {a: workers_for(a, selections[a], timings, len(aliases) == 1) for a in aliases}
    results = []
    if generate:
        run(["make", "generate"])
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"], capture=True).stdout)["devices"]
    destinations = []
    for alias in order:
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
    budget = WorkerBudget(max(concurrency, max(workers.values())))
    observations = {d.alias: {} for d in destinations}
    with ThreadPoolExecutor(max_workers=min(concurrency, len(destinations) or 1)) as pool:
        futures = [pool.submit(budgeted_device, budget, workers[d.alias], d, selections[d.alias], mode, recording if recording != "0" else None, ready, intro_order_check, observations[d.alias]) for d in destinations]
        for future in futures:
            results.extend(future.result())
    for alias, observation in observations.items():
        if observation:
            previous = timings["devices"].setdefault(alias, {})
            for key in ("suites", "tests"):
                previous.setdefault(key, {}).update(observation.pop(key, {}))
            previous.update(observation)
    save_timings(timings)
    print("\nSimulator results:", flush=True)
    for result in results:
        print(f"{'PASS' if result.passed else 'FAIL'} {result.device} {result.suite}" + (": " + result.detail if result.detail else ""), flush=True)
    print(f"Elapsed: {time.monotonic() - started:.1f}s; concurrency={concurrency}", flush=True)
    return int(any(not r.passed for r in results))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build once, then run classified suites in parallel on the D1c simulators.")
    parser.add_argument("--devices", nargs="+", choices=MATRIX, help="device aliases (default: 17e; --matrix explicitly requests all seven)")
    parser.add_argument("--only", nargs="+", help="target[/suite[/test]] selectors; targeted runs execute these on every requested device")
    parser.add_argument("--reuse-build", action="store_true", help="reuse the last build-for-testing products; rebuild after source/project changes")
    parser.add_argument("--intro-order-check", action="store_true", help="compare the 2700 ms frame in fresh and warmed test processes; never overwrite baselines")
    parser.add_argument("--no-generate", action="store_true")
    parser.add_argument("--mode", choices=("check", "test", "snapshots", "runtime"), default="check")
    parser.add_argument("--matrix", action="store_true", help="explicitly request the seven-device matrix")
    for flag in ("timeline", "scene", "snapshots", "readiness", "welcome"):
        parser.add_argument("--" + flag, action="store_true", help="compatibility matrix entry point; uses the suite classification")
    args = parser.parse_args()
    matrix_requested = args.matrix or args.timeline or args.scene or args.readiness or args.welcome
    mode = "launch-snapshots" if args.snapshots and not args.scene else "matrix" if matrix_requested else args.mode
    try:
        raise SystemExit(main(mode, args.devices, args.only or (), reuse_build=args.reuse_build, generate=not args.no_generate, intro_order_check=args.intro_order_check))
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError, RuntimeError) as error:
        parser.exit(1, str(error) + "\n")
