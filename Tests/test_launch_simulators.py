import contextlib
import io
import json
import os
from pathlib import Path
import re
import runpy
import signal
import sys
import subprocess
import threading
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
(ROOT / 'build').mkdir(exist_ok=True)
runner = SimpleNamespace(**runpy.run_path(str(ROOT / 'Scripts/launch-simulators.py')))
PHASE9_HOSTED = (
    'AppTests/AccountStorageLifecycleTests', 'AppTests/SessionLifecycleTests',
    'AppTests/KeychainSessionStoreTests', 'AppTests/DataSourceBuildSettingTests',
    'AppTests/DataSourceFactoryHostedTests', 'AppTests/SyncLifecycleTests',
    'AppTests/AccountWipeTests', 'AppTests/SessionReadinessTests',
    'AppTests/LaunchConnectionTests', 'AppTests/ReleaseReadinessTests',
)

AUTH_HOSTED = (
    'AppTests/AuthControlTests', 'AppTests/AuthLayoutTests', 'AppTests/AuthSnapshotGuardTests',
    'AppTests/AuthSnapshotTests', 'AppTests/TwoFactorControlTests', 'AppTests/TwoFactorLayoutTests',
    'AppTests/TwoFactorSnapshotTests', 'AppTests/ForgotPasswordControlTests', 'AppTests/ForgotPasswordLayoutTests', 'AppTests/ForgotPasswordSnapshotTests',
)
AUTH_UI = (
    'AppUITests/SignInTests', 'AppUITests/SignInKeyboardTests', 'AppUITests/TwoFactorTests',
    'AppUITests/TwoFactorKeyboardTests', 'AppUITests/ForgotPasswordTests', 'AppUITests/ForgotPasswordKeyboardTests', 'AppUITests/AuthSessionTests', 'AppUITests/AuthAuditTests',
)
AUTH_SNAPSHOTS = ('AppTests/AuthSnapshotTests', 'AppTests/TwoFactorSnapshotTests', 'AppTests/ForgotPasswordSnapshotTests')


def discovered_suites(directory):
    suites = set()
    for file in directory.glob('*.swift'):
        source = file.read_text()
        spans = []
        for match in re.finditer(r'\b(?:struct|class|extension)\s+(\w+)[^{\n]*\{', source):
            start = match.end()
            depth, end = 1, start
            while depth and end < len(source):
                depth += (source[end] == '{') - (source[end] == '}')
                end += 1
            body = source[start:end]
            if ('XCTestCase' in match.group() and re.search(r'func test\w+\(', body)) or '@Test' in body:
                suites.add(match[1])
                spans.append((start, end))
        for test in re.finditer(r'@Test\b', source):
            if not any(start <= test.start() < end for start, end in spans):
                raise AssertionError(f'{file}: top-level tests need a named, classified suite')
    return suites


class TimeoutTests(unittest.TestCase):
    @contextlib.contextmanager
    def output_schedule(self, steps, stream=False):
        now = [0]
        steps = iter(steps)
        process = Mock(returncode=0)
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            log = Path(directory) / 'test.log'
            progress = log.with_suffix('.jsonl') if stream else log
            if stream:
                progress.touch()

            def communicate(timeout=None):
                if process.returncode:
                    return None, None
                step = next(steps, None)
                if step is None:
                    return None, None
                now[0], content = step
                if content:
                    with progress.open('ab') as output:
                        output.write(content)
                else:
                    os.utime(progress, None)
                raise subprocess.TimeoutExpired('test', timeout)

            def terminate(process, signum):
                process.returncode = -signum

            process.communicate.side_effect = communicate
            with patch.object(runner.subprocess, 'Popen', return_value=contextlib.nullcontext(process)), \
                 patch.object(runner.time, 'monotonic', side_effect=lambda: now[0]), \
                 patch.dict(runner.run.__globals__, signal_group=Mock(side_effect=terminate)):
                yield log, now

    def test_growing_log_can_run_past_old_wall_clock_limit(self):
        with self.output_schedule([(second, b'progress\n') for second in range(300, 1801, 300)]) as (log, now):
            completed = runner.run(['test'], log=log, timeout=3600, idle_timeout=600)
            self.assertEqual(completed.returncode, 0)
            self.assertEqual(now[0], 1800)
            self.assertNotIn('timed out', log.read_text())

    def test_inactivity_deadline_restarts_on_growth_but_not_timestamp_changes(self):
        with self.output_schedule([(500, b'progress\n'), (1000, b''), (1101, b'')]) as (log, _):
            with self.assertRaises(runner.TestRunTimeout) as raised:
                runner.run(['test'], log=log, timeout=3600, idle_timeout=600)
            self.assertEqual(raised.exception.detail, 'Test run timed out after 600s of log inactivity')
            self.assertIn(raised.exception.detail + '; terminated process group', log.read_text())

    def test_result_stream_growth_counts_as_progress_with_buffered_stdout(self):
        with self.output_schedule([(second, b'{"testFinished":true}\n') for second in range(300, 1801, 300)], stream=True) as (log, now):
            completed = runner.run(['test'], log=log, timeout=3600, idle_timeout=600,
                                   activity_paths=(log.with_suffix('.jsonl'),))
            self.assertEqual(completed.returncode, 0)
            self.assertEqual(now[0], 1800)
            self.assertNotIn('testFinished', log.read_text())

    def test_result_stream_timestamps_do_not_hide_a_stall(self):
        with self.output_schedule([(500, b'event'), (1000, b''), (1101, b'')], stream=True) as (log, _):
            with self.assertRaises(runner.TestRunTimeout):
                runner.run(['test'], log=log, timeout=3600, idle_timeout=600,
                           activity_paths=(log.with_suffix('.jsonl'),))

    def test_growing_log_still_hits_overall_cap(self):
        with self.output_schedule([(second, b'progress\n') for second in range(300, 3601, 300)]) as (log, _):
            with self.assertRaises(runner.TestRunTimeout) as raised:
                runner.run(['test'], log=log, timeout=3600, idle_timeout=600)
            self.assertEqual(raised.exception.detail, 'Test run timed out after 3600s overall')
            self.assertIn(raised.exception.detail + '; terminated process group', log.read_text())

    def test_run_timeout_kills_process_group_and_keeps_log(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            log = Path(directory) / 'timeout.log'
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.run(['python3', '-c', 'import time; time.sleep(30)'], log=log, timeout=0.1)
            self.assertIn('Test run timed out after 0.1s overall', log.read_text())

    def test_inactivity_kills_descendants_that_ignore_termination_and_keeps_output(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            scratch = Path(directory)
            log = scratch / 'timeout.log'
            child = scratch / 'child.py'
            child.write_text("""import os
from pathlib import Path
import signal
import sys
import time
root = Path(sys.argv[1])
if os.fork() == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    (root / 'child.pid').write_text(str(os.getpid()))
    while True:
        (root / 'heartbeat').write_text(str(time.monotonic()))
        time.sleep(0.02)
while not (root / 'heartbeat').exists():
    time.sleep(0.01)
print('ready', file=sys.stderr, flush=True)
while True:
    time.sleep(30)
""")
            try:
                with self.assertRaises(runner.TestRunTimeout) as raised:
                    runner.run([sys.executable, str(child), str(scratch)], log=log, timeout=10, idle_timeout=0.5)
                self.assertIn('of log inactivity', raised.exception.detail)
                self.assertIn('\nready\n', log.read_text())
                self.assertIn('terminated process group', log.read_text())
                heartbeat = (scratch / 'heartbeat').read_text()
                time.sleep(0.15)
                self.assertEqual(heartbeat, (scratch / 'heartbeat').read_text())
            finally:
                pid = scratch / 'child.pid'
                if pid.exists():
                    try:
                        os.kill(int(pid.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_test_pass_uses_default_limits_and_environment_overrides(self):
        for overrides, expected in [({}, (3600, 600)), ({'TEST_RUN_TIMEOUT': '900'}, (900, 600)),
                                    ({'TEST_RUN_IDLE_TIMEOUT': '45'}, (3600, 45))]:
            with self.subTest(overrides=overrides), tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
                execute = Mock(return_value=subprocess.CompletedProcess('test', 0))
                with patch.dict(os.environ, overrides, clear=True), \
                     patch.dict(runner.test_pass.__globals__, ROOT=Path(directory), run=execute, read_results=Mock(return_value=[])):
                    runner.test_pass(runner.Destination('17e', 'test', 'Booted'), 'Debug', ['AppTests/AuthControlTests'], 'Debug-compare')
                self.assertEqual((execute.call_args.kwargs['timeout'], execute.call_args.kwargs['idle_timeout']), expected)

    def test_test_pass_rejects_invalid_timeout_overrides(self):
        for key in ('TEST_RUN_TIMEOUT', 'TEST_RUN_IDLE_TIMEOUT'):
            for value in ('0', '-1', 'nan', 'inf', 'invalid'):
                with self.subTest(key=key, value=value), tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory, \
                     patch.dict(os.environ, {key: value}, clear=True), \
                     patch.dict(runner.test_pass.__globals__, ROOT=Path(directory), run=Mock()) as namespace:
                    with self.assertRaises(ValueError):
                        runner.test_pass(runner.Destination('17e', 'test', 'Booted'), 'Debug', ['AppTests/AuthControlTests'], 'Debug-compare')
                    namespace['run'].assert_not_called()

    def test_make_duo_preserves_its_overall_cap_and_override(self):
        for value, expected in [('', '600'), ('900', '900')]:
            with self.subTest(value=value):
                command = subprocess.check_output(['make', '-n', 'duo', 'TEST_RUN_TIMEOUT=' + value], cwd=ROOT, text=True)
                self.assertIn('TEST_RUN_TIMEOUT=' + expected + ' ', command)

    def test_interrupts_forward_to_worker_process_groups_and_exit_promptly(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum), tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
                scratch = Path(directory)
                child = scratch / 'child.py'
                child.write_text("""import os
from pathlib import Path
import signal
import subprocess
import sys
import time
root, name = Path(sys.argv[1]), sys.argv[2]
def interrupted(signum, frame):
    (root / (name + '.signal')).write_text(str(signum))
for signum in (signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, interrupted)
if not name.endswith('-grandchild'):
    subprocess.Popen([sys.executable, __file__, str(root), name + '-grandchild'])
(root / (name + '.pid')).write_text(str(os.getpid()))
while True:
    (root / (name + '.heartbeat')).write_text(str(time.monotonic()))
    time.sleep(0.05)
""")
                driver = scratch / 'driver.py'
                driver.write_text("""from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import runpy
import sys
runner = runpy.run_path(sys.argv[1])
scratch = Path(sys.argv[2])
with runner['forward_run_signals']():
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(runner['run'], [sys.executable, str(scratch / 'child.py'), str(scratch), str(i)],
                               log=scratch / (str(i) + '.log'), timeout=30, idle_timeout=10) for i in range(2)]
        for future in futures:
            future.result()
""")
                with subprocess.Popen([sys.executable, str(driver), str(ROOT / 'Scripts/launch-simulators.py'), str(scratch)],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as process:
                    try:
                        deadline = time.monotonic() + 5
                        while len(list(scratch.glob('*.pid'))) < 4 and time.monotonic() < deadline:
                            time.sleep(0.01)
                        self.assertEqual(len(list(scratch.glob('*.pid'))), 4)
                        started = time.monotonic()
                        process.send_signal(signum)
                        output, _ = process.communicate(timeout=4)
                        self.assertEqual(process.returncode, 128 + signum, output)
                        self.assertLess(time.monotonic() - started, 4)
                        self.assertEqual(len(list(scratch.glob('*.signal'))), 4)
                        self.assertTrue(all(p.read_text() == str(signum) for p in scratch.glob('*.signal')))
                        heartbeats = {p: p.read_text() for p in scratch.glob('*.heartbeat')}
                        self.assertEqual(len(heartbeats), 4)
                        time.sleep(0.15)
                        self.assertEqual(heartbeats, {p: p.read_text() for p in heartbeats})
                    finally:
                        if process.poll() is None:
                            process.kill()
                        for pid in scratch.glob('*.pid'):
                            try:
                                os.kill(int(pid.read_text()), signal.SIGKILL)
                            except ProcessLookupError:
                                pass

    def test_timeout_marks_selection_failed_and_skips_later_passes(self):
        destination = runner.Destination('duo', 'test', 'Booted')
        selected = ['AppUITests/SignInTests', 'AppUITests/AuthSessionTests', 'AppTests/ReleaseReadinessTests']
        namespace = runner.test_pass.__globals__
        for inactive in (False, True):
            execute = Mock(side_effect=runner.TestRunTimeout('test', 0.1, inactive=inactive))
            with self.subTest(inactive=inactive), tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory, \
                 patch.dict(namespace, ROOT=Path(directory), prepare=lambda _: None, run=execute):
                results = runner.test_device(destination, selected, 'runtime', None, {'Debug': True, 'Release': True}, workers=2)
            self.assertEqual(len(results), 3)
            self.assertTrue(all(not r.passed for r in results))
            self.assertIn('of log inactivity' if inactive else 'overall', results[0].detail)
            self.assertTrue(all(r.detail == 'Not run after timeout' for r in results[1:]))
            execute.assert_called_once()


class ClassificationTests(unittest.TestCase):
    def test_discovery_rejects_stale_helper_classes_as_well_as_missing_suites(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            path = Path(directory)
            (path / 'Example.swift').write_text('class OldTests: XCTestCase { }\nclass NewTests: XCTestCase { func testExample() {} }')
            self.assertEqual(discovered_suites(path), {'NewTests'})
            self.assertNotEqual(discovered_suites(path), {'OldTests', 'NewTests'})
            self.assertNotEqual(discovered_suites(path), set())

    def test_every_target_and_suite_is_classified_exactly_once(self):
        self.assertNotRegex(Path(__file__).read_text(), r"self\.fail\s*=")
        package = (ROOT / 'Packages/ChronoFlowKit/Package.swift').read_text()
        targets = set(re.findall(r'\.testTarget\(\s*name: "(\w+)"', package))
        project = (ROOT / 'project.yml').read_text()
        targets.update(re.findall(r'^  (\w+):\n    type: bundle\.(?:unit-test|ui-testing)', project, re.M))
        self.assertEqual(targets, set(runner.SUITES))
        for target in targets:
            directory = ROOT / target if (ROOT / target).exists() else ROOT / 'Packages/ChronoFlowKit/Tests' / target
            entries = [s for suites in runner.SUITES[target].values() for s in suites]
            self.assertEqual(len(entries), len(set(entries)), target)
            self.assertEqual(set(entries), discovered_suites(directory), target)

    def test_logic_runs_once_and_matrix_runs_on_every_requested_device(self):
        logic = runner.selectors('logic') + runner.selectors('release')
        matrix = set(runner.selectors('matrix'))
        for aliases in [list(runner.MATRIX), ['se', 'duo'], ['duo']]:
            selections, order = runner.schedule('welcome', aliases)
            for alias in aliases:
                self.assertTrue(matrix <= set(selections[alias]))
            for suite in logic:
                self.assertEqual(sum(selections[a].count(suite) for a in aliases), 1, suite)
            costs = [runner.estimated_seconds(a, selections[a], {}) for a in order]
            self.assertEqual(costs, sorted(costs, reverse=True))

    def test_auth_host_logic_profiles_and_serial_appearance_are_in_check(self):
        host = set(runner.selectors('host'))
        self.assertTrue(any(s.startswith('AuthTests/') for s in host))
        logic = {'DesignSystemTests/AuthBoardContrastTests', 'AppTests/AuthControlTests', 'AppTests/AuthLayoutTests',
                 'AppUITests/SignInTests', 'AppUITests/AuthAuditTests'}
        self.assertTrue(logic <= set(runner.selectors('logic')))
        self.assertIn('AppTests/AuthSnapshotTests', runner.selectors('profiles'))
        self.assertIn('AppTests/AuthSnapshotTests', runner.SNAPSHOTS)
        selected = runner.selection('check', '17e')
        for suite in logic | {'AppTests/AuthSnapshotTests'}:
            self.assertEqual(selected.count(suite), 1, suite)
        self.assertFalse(set(selected) & host)
        self.assertIn('AppUITests/AuthAuditTests', runner.SERIAL_TESTS)
        self.assertEqual(runner.recording_selection(['AppTests/AuthSnapshotTests'], 'welcome', '1'),
                         ['AppTests/AuthSnapshotTests'])

    def test_reset_signup_verify_recovery_suites_are_registered_without_default_matrix_or_network(self):
        for screen in ['ResetPassword', 'SignUp', 'VerifyEmail']:
            self.assertIn(f'AuthTests/{screen}ModelTests', runner.selectors('host'))
            for suffix in ['ControlTests', 'LayoutTests']:
                suite = f'AppTests/{screen}{suffix}'
                self.assertIn(suite, runner.selectors('logic'))
                self.assertEqual(runner.selection('check', '17e').count(suite), 1)
            snapshot = f'AppTests/{screen}SnapshotTests'
            self.assertIn(snapshot, runner.SNAPSHOTS)
            self.assertEqual(runner.recording_selection([snapshot], 'check', '1'), [snapshot])
            self.assertIn(f'AppUITests/{screen}Tests', runner.selectors('logic'))
        self.assertIn('AppUITests/AccountRecoveryTests', runner.selectors('logic'))
        self.assertIn('AppTests/AuthUniversalLinkTests', runner.selectors('logic'))
        self.assertIn('AppUITests/AuthAuditTests', runner.SERIAL_TESTS)
        source = (ROOT / 'App/Session/AppServices.swift').read_text()
        self.assertIn('testing: testing || authTestRequested', source)
        self.assertIn('AuthUITestConfiguration(environment: environment)', source)

    def test_two_factor_suites_run_at_their_registered_tiers_and_record_only_on_17e(self):
        self.assertIn('AuthTests/TwoFactorModelTests', runner.selectors('host'))
        for suite in ['AppTests/TwoFactorControlTests', 'AppTests/TwoFactorLayoutTests', 'AppUITests/TwoFactorTests']:
            self.assertIn(suite, runner.selectors('logic'))
            self.assertEqual(runner.selection('check', '17e').count(suite), 1)
        keyboard = 'AppUITests/TwoFactorKeyboardTests'
        self.assertIn(keyboard, runner.selectors('matrix'))
        self.assertEqual(runner.selection('check', '17e').count(keyboard), 1)
        snapshot = 'AppTests/TwoFactorSnapshotTests'
        self.assertIn(snapshot, runner.selectors('profiles'))
        self.assertIn(snapshot, runner.SNAPSHOTS)
        self.assertEqual(runner.selection('check', '17e').count(snapshot), 1)
        self.assertEqual(runner.recording_selection([snapshot], 'check', '1'), [snapshot])
        self.assertEqual(runner.recording_selection([snapshot], 'check', 'launch'), [])
        for alias in ['se', 'duo']:
            self.assertEqual(runner.selection('check', alias, only=[keyboard]), [keyboard])

    def test_forgot_suites_register_at_their_tiers_and_record_only_on_17e(self):
        self.assertIn('AuthTests/ForgotPasswordModelTests', runner.selectors('host'))
        for suite in ['AppTests/ForgotPasswordControlTests', 'AppTests/ForgotPasswordLayoutTests', 'AppUITests/ForgotPasswordTests']:
            self.assertIn(suite, runner.selectors('logic'))
            self.assertEqual(runner.selection('check', '17e').count(suite), 1)
        keyboard = 'AppUITests/ForgotPasswordKeyboardTests'
        self.assertIn(keyboard, runner.selectors('matrix'))
        self.assertEqual(runner.selection('check', '17e').count(keyboard), 1)
        snapshot = 'AppTests/ForgotPasswordSnapshotTests'
        self.assertIn(snapshot, runner.selectors('profiles'))
        self.assertIn(snapshot, runner.SNAPSHOTS)
        self.assertEqual(runner.selection('check', '17e').count(snapshot), 1)
        self.assertEqual(runner.recording_selection([snapshot], 'check', '1'), [snapshot])
        self.assertEqual(runner.recording_selection([snapshot], 'check', 'launch'), [])
        for alias in ['se', 'duo']:
            self.assertEqual(runner.selection('check', alias, only=[keyboard]), [keyboard])

    def test_auth_acceptance_tiers_include_all_suites_once_and_project_discovers_ui_sources(self):
        for suite in AUTH_HOSTED + AUTH_UI:
            self.assertEqual(runner.selection('check', '17e').count(suite), 1, suite)
        self.assertEqual(runner.selection('runtime', 'duo'), list(runner.RUNTIME_SMOKE))
        for suite in AUTH_UI:
            if suite not in ('AppUITests/AuthSessionTests', 'AppUITests/AuthAuditTests'):
                self.assertEqual(runner.selection('runtime', 'duo').count(suite), 1, suite)
        self.assertFalse(set(AUTH_HOSTED) & set(runner.selection('runtime', 'duo')))
        self.assertIn('AuthTests/AuthSnapshotCaptureTests', runner.selectors('host'))
        for suite in AUTH_SNAPSHOTS + ('AppTests/AuthSnapshotGuardTests',):
            self.assertIn(suite, runner.selection('snapshots', '17e'))
        project = (ROOT / 'project.yml').read_text()
        ui = project.split('  AppUITests:\n')[1].split('  PerfUITests:\n')[0]
        self.assertIn('- path: AppUITests\n', ui)
        self.assertIn('- path: Packages/ChronoFlowKit/Sources/DataAccess/Mock/MockScenarioValues.swift', ui)
        self.assertNotIn('excludes:', ui)
        for suite in ['AppUITests/AuthSessionTests', 'AppUITests/AuthAuditTests']:
            self.assertIn(suite, runner.SERIAL_TESTS)

    def test_store_and_core_logic_run_on_host_by_default(self):
        host = set(runner.selectors('host'))
        self.assertTrue(any(s.startswith('LocalStoreTests/') for s in host))
        self.assertTrue(any(s.startswith('AppCoreTests/') for s in host))
        self.assertTrue(any(s.startswith('DataAccessTests/') for s in host))
        self.assertTrue(any(s.startswith('SyncTests/') for s in host))
        for alias in runner.MATRIX:
            self.assertFalse(set(runner.selection('check', alias)) & host)
        makefile = (ROOT / 'Makefile').read_text()
        self.assertIn('host-tests: package-tests token-tests asset-tests launch-resources-check', makefile)
        self.assertIn('package-tests:\n\tsh Scripts/swiftpm.sh test ChronoFlowKit', makefile)
        self.assertIn('exec sh "$(dirname "$0")/swiftpm.sh" test ChronoFlowKit "$@"',
                      (ROOT / 'Scripts/host-tests.sh').read_text())

    def test_check_keeps_every_phase9_hosted_suite_in_its_configuration(self):
        selected = runner.selection('check', '17e')
        configurations = runner.configurations(selected)
        for suite in PHASE9_HOSTED:
            self.assertEqual(selected.count(suite), 1, suite)
            configuration = 'Release' if suite.endswith('/ReleaseReadinessTests') else 'Debug'
            self.assertIn(suite, configurations[configuration])
            self.assertNotIn(suite, runner.selectors('profiles') + runner.selectors('reference'))
        self.assertTrue(set(PHASE9_HOSTED[:8]) <= set(runner.selectors('logic')))

    def test_perf_configuration_is_explicit_and_ordinary_release_restores_native(self):
        project = (ROOT / 'project.yml').read_text()
        self.assertIn('Perf:\n          CHRONOFLOW_READINESS: signed-out', project)
        self.assertIn('CHRONOFLOW_READINESS = native', (ROOT / 'Config/Base.xcconfig').read_text())
        perf = project.split('\n  Perf:\n    build:')[1]
        self.assertEqual(perf.count('config: Perf'), 3)
        self.assertIn('--devices 17e --mode perf', (ROOT / 'Makefile').read_text())
        for suite in ('AppCoreTests/SignOutTests', 'AppCoreTests/StoredDataReadinessTests',
                      'SyncTests/SyncTriggerTests', 'SyncTests/SessionSyncReadinessTests', 'SyncTests/SessionWipeTests', 'LocalStoreTests/AccountWiperTests', 'LocalStoreTests/AccountReadinessTests'):
            self.assertIn(suite, runner.selectors('host'))

    def test_target_and_method_selection_is_explicit_and_validated(self):
        self.assertEqual(runner.expand(['AppTests/WelcomeSnapshotTests/frozenIntro']), ['AppTests/WelcomeSnapshotTests/frozenIntro'])
        self.assertIn('AppTests/WelcomeSnapshotTests', runner.expand(['AppTests']))
        self.assertEqual(runner.expand(['PerfUITests']), sorted(runner.selectors('perf')))
        for selector in ['Unknown', 'PerfUITests/NewTests', 'AppTests/NewTests']:
            with self.assertRaises(ValueError): runner.expand([selector])
        self.assertEqual(runner.selection('welcome', 'duo', ['AppUITests/ReadinessTests']), ['AppUITests/ReadinessTests'])

    def test_result_nodes_keep_same_named_suites_in_their_own_targets(self):
        value = {'testNodes': [
            {'nodeType': 'Unit test bundle', 'name': 'AppTests', 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': 'LaunchSceneTests/testExample()', 'result': 'Passed'}]},
            {'nodeType': 'UI test bundle', 'name': 'AppUITests', 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': 'LaunchSceneTests/testExample()', 'result': 'Failed'}]},
        ]}
        self.assertEqual([n['target'] for n in runner.result_nodes(value)], ['AppTests', 'AppUITests'])

    def test_ui_suite_named_like_package_target_matches_unqualified_and_qualified_identifiers(self):
        method = 'testDutchAX5TextCanScrollToBothActions()'
        for identifier in ['WelcomeTests/' + method, 'AppUITests/WelcomeTests/' + method]:
            value = {'testNodes': [
                {'nodeType': 'UI test bundle', 'name': 'AppUITests', 'children': [
                    {'nodeType': 'Test Case', 'nodeIdentifier': identifier, 'result': 'Passed'},
                    {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeLogicTests/testSignIn()', 'result': 'Passed'},
                    {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeEnglishAccessibilityTests/testAudit()', 'result': 'Passed'}]},
                {'nodeType': 'Unit test bundle', 'name': 'WelcomeTests', 'children': [
                    {'nodeType': 'Test Case', 'nodeIdentifier': 'SmokeTests/testSmoke()', 'result': 'Passed'}]},
            ]}
            nodes = list(runner.result_nodes(value))
            for selector in ['AppUITests/WelcomeTests', 'AppUITests/WelcomeTests/' + method]:
                matches = runner.matching_nodes(nodes, selector)
                self.assertEqual(len(matches), 1, identifier)
                self.assertEqual(matches[0]['nodeIdentifier'], identifier)
            self.assertEqual(runner.matching_nodes(nodes, 'WelcomeTests/WelcomeTests'), [])
            self.assertEqual(len(runner.matching_nodes(nodes, 'WelcomeTests/SmokeTests')), 1)

    def test_release_only_configuration_is_isolated(self):
        result = runner.configurations(['AppTests/ReleaseReadinessTests', 'AppUITests/WelcomeTests'])
        self.assertEqual(result, {'Debug': ['AppUITests/WelcomeTests'], 'Release': ['AppTests/ReleaseReadinessTests']})
        project = (ROOT / 'project.yml').read_text()
        scheme = project.split('\n  ReadinessRelease:\n')[1].split('\n  Perf:\n')[0]
        self.assertIn('targets: [AppTests]', scheme)
        self.assertNotIn('ENABLE_TESTABILITY', project)

    def test_release_readiness_and_perf_build_for_the_simulator_without_signing_overrides(self):
        project = (ROOT / 'project.yml').read_text()
        self.assertIn('"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": ""', project)
        self.assertIn('"DEVELOPMENT_TEAM[sdk=iphonesimulator*]": ""', project)
        self.assertIn('"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "-"', project)
        for configuration, scheme in [('Release', 'ReadinessRelease'), ('Perf', 'Perf')]:
            with self.subTest(configuration=configuration), patch.dict(runner.build.__globals__, run=Mock(return_value=True)):
                run = runner.build.__globals__['run']
                self.assertTrue(runner.build(configuration))
                command = run.call_args.args[0]
                self.assertEqual(command[command.index('-scheme') + 1], scheme)
                self.assertEqual(command[command.index('-configuration') + 1], configuration)
                self.assertEqual(command[command.index('-destination') + 1], 'generic/platform=iOS Simulator')
                self.assertEqual(command[-1], 'build-for-testing')
                self.assertEqual('ENABLE_TESTABILITY=YES' in command, configuration == 'Release')
                self.assertFalse(any(c.startswith(('CODE_SIGN', 'DEVELOPMENT_TEAM=')) for c in command))

    def test_tiers_never_select_the_matrix_in_any_default_flow(self):
        for target in ['quick', 'check']:
            command = subprocess.check_output(['make', '-n', target], cwd=ROOT, text=True)
            self.assertNotIn('--matrix', command)
            self.assertNotIn('--devices duo', command)
            self.assertIn('test ChronoFlowKit', command)
            self.assertIn('test TokenGen', command)
            self.assertIn('test AssetGen', command)
            self.assertEqual(command.count('test ChronoFlowKit'), 1)
            if target == 'quick':
                self.assertNotIn('launch-simulators.py --', command)
                self.assertNotIn('xcodebuild', command)
            else:
                self.assertEqual(command.count('--devices 17e'), 1)
        self.assertIn('--matrix', subprocess.check_output(['make', '-n', 'matrix'], cwd=ROOT, text=True))
        self.assertEqual((ROOT / 'Scripts/ci.sh').read_text().strip().splitlines()[-1], 'exec make generate check')

    def test_make_check_runs_combined_pass_and_individual_targets_share_runner(self):
        makefile = (ROOT / 'Makefile').read_text()
        self.assertIn('check: quick generators-check simulator-check', makefile)
        self.assertNotIn('test snapshots', makefile.split('check:')[-1])
        self.assertIn("--devices $(DEVICES) --only $(foreach selector,$(ONLY),'$(selector)')", makefile)
        self.assertIn('--devices duo', makefile)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.devices = {runner.REGULAR_RUNTIME: [], runner.DUO_RUNTIME: []}
        for index, (_, device_type, runtime) in enumerate(runner.MATRIX.values()):
            self.devices[runtime].append(dict(deviceTypeIdentifier='com.apple.CoreSimulator.SimDeviceType.' + device_type,
                                              isAvailable=True, state='Booted', udid=f'device-{index}'))
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT / "build", prefix="runner-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.scratch = Path(self.temporary.name)
        self.commands = []
        self.environments = []
        self.selected = {}
        self.command_failure = lambda command: False
        self.result_fail = None
        self.nodes = None
        self.enumerated = [runner.INTRO_ORDER_TEST]

    def execute(self, **kwargs):
        if "fail" in self.__dict__:
            raise AssertionError("Command fixture must not shadow unittest.TestCase.fail")
        def fake_run(command, **options):
            self.assertEqual(options['cwd'], self.scratch)
            self.commands.append(command)
            self.environments.append(options['env'])
            status = 65 if self.command_failure(command) else 0
            if status and options.get('check'):
                raise subprocess.CalledProcessError(status, command)
            if command[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                return subprocess.CompletedProcess(command, status, json.dumps({'devices': self.devices}))
            if '-enumerate-tests' in command:
                listing = Path(command[command.index('-test-enumeration-output-path') + 1])
                listing.parent.mkdir(parents=True, exist_ok=True)
                listing.write_text('\n'.join(self.enumerated))
                return subprocess.CompletedProcess(command, status, '')
            if command[-1] == 'test-without-building':
                self.selected[command[command.index('-resultBundlePath') + 1]] = [v.split(':', 1)[1] for v in command if v.startswith('-only-testing:')]
            if command[:4] == ['xcrun', 'xcresulttool', 'get', 'test-results']:
                bundle = command[command.index('--path') + 1]
                nodes = self.nodes if self.nodes is not None else [
                    {'nodeType': 'Test Case', 'nodeIdentifier': s if s.count('/') == 2 else s + '/testExample()', 'durationInSeconds': 2.25, 'result': 'Failed' if s == self.result_fail else 'Passed'}
                    for s in self.selected[bundle]]
                return subprocess.CompletedProcess(command, status, json.dumps({'testNodes': [{'children': nodes}]}))
            return subprocess.CompletedProcess(command, status, '')
        def fake_popen(command, **options):
            completed = fake_run(command, **options)
            process = Mock(returncode=completed.returncode, communicate=Mock(return_value=(None, None)))
            return contextlib.nullcontext(process)
        output = io.StringIO()
        with patch.dict(runner.main.__globals__, ROOT=self.scratch, TIMINGS_PATH=self.scratch / 'build/test-results/timings.json', machine_resources=lambda: (14, 36 * 1024**3)), patch.object(runner.subprocess, 'run', side_effect=fake_run), patch.object(runner.subprocess, 'Popen', side_effect=fake_popen), contextlib.redirect_stdout(output):
            kwargs.setdefault("mode", "matrix")
            result = runner.main(**kwargs)
        return result, output.getvalue()

    def commands_for_tests(self):
        return [c for c in self.commands if c[-1] == 'test-without-building' and '-enumerate-tests' not in c]

    def test_builds_debug_and_release_once_without_clean_or_reboot(self):
        status, output = self.execute()
        self.assertEqual(status, 0, output)
        builds = [c for c in self.commands if c[-1] == 'build-for-testing']
        self.assertEqual(len(builds), 2)
        self.assertEqual([c[c.index('-configuration') + 1] for c in builds], ['Debug', 'Release'])
        self.assertIn('ENABLE_TESTABILITY=YES', builds[1])
        self.assertEqual(len(self.commands_for_tests()), 9)
        self.assertFalse(any('clean' in c or 'shutdown' in c or 'erase' in c or 'boot' in c for c in self.commands))
        self.assertEqual(sum('uninstall' in c for c in self.commands), 7)
        self.assertNotIn(['make', 'check'], self.commands)
        self.assertNotIn(['make', 'duo'], self.commands)
        for c in self.commands_for_tests():
            self.assertIn('-parallel-testing-enabled', c)
            self.assertEqual(c[c.index('-testLanguage') + 1], 'en')
            self.assertEqual(c[c.index('-testRegion') + 1], 'US')
            self.assertEqual(c[c.index('-maximum-concurrent-test-simulator-destinations') + 1], '1')

    def test_default_gate_uses_only_17e_and_serializes_device_appearance(self):
        status, output = self.execute(mode='check')
        self.assertEqual(status, 0, output)
        commands = self.commands_for_tests()
        self.assertEqual({c[c.index('-destination') + 1] for c in commands}, {'platform=iOS Simulator,id=device-1'})
        self.assertEqual(sum('uninstall' in c for c in self.commands), 1)
        self.assertEqual(len(commands), 3)
        serial = next(c for c in commands if c[c.index('-resultBundlePath') + 1].endswith('Debug-serial.xcresult'))
        for selector in runner.SERIAL_TESTS:
            self.assertIn('-only-testing:' + selector, serial)
        self.assertEqual(serial[serial.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertTrue(any('-only-testing:AppTests/LaunchSnapshotTests' in c for c in commands))
        self.assertFalse(any('-only-testing:AppCoreTests/LaunchCoordinatorTests' in c for c in commands))

    def test_check_executes_all_phase9_hosted_suites_once_on_17e(self):
        status, output = self.execute(mode='check')
        self.assertEqual(status, 0, output)
        for suite in PHASE9_HOSTED:
            matches = [c for c in self.commands_for_tests() if '-only-testing:' + suite in c]
            self.assertEqual(len(matches), 1, suite)
            command = matches[0]
            self.assertEqual(command[command.index('-destination') + 1],
                             'platform=iOS Simulator,id=device-1')
            configuration = 'Release' if suite.endswith('/ReleaseReadinessTests') else 'Debug'
            self.assertEqual(command[command.index('-configuration') + 1], configuration)
            self.assertNotIn('-skip-testing:' + suite, command)
            self.assertIn('PASS 17e ', output)
            self.assertIn(' ' + suite, output)

    def test_snapshot_record_one_records_both_screens_once_on_17e(self):
        with patch.dict(os.environ, SNAPSHOT_RECORD='1'):
            status, output = self.execute(mode='snapshots')
        self.assertEqual(status, 0, output)
        recorded = [c for c,e in zip(self.commands,self.environments) if e.get('TEST_RUNNER_SNAPSHOT_RECORD')]
        self.assertEqual(len(recorded), 1)
        for selector in runner.SNAPSHOTS[:2]:
            self.assertIn('-only-testing:' + selector, recorded[0])
        self.assertEqual(recorded[0][recorded[0].index('-parallel-testing-worker-count') + 1], '1')
        self.assertNotIn('-only-testing:RenderTests/WelcomeRenderingTests', recorded[0])
        self.assertNotIn('-only-testing:AppTests/WelcomeSnapshotGuardTests', recorded[0])

    def test_auth_check_executes_all_suites_once_and_keeps_failures_visible(self):
        status, output = self.execute(mode='check')
        self.assertEqual(status, 0, output)
        for suite in AUTH_HOSTED + AUTH_UI:
            commands = [c for c in self.commands_for_tests() if '-only-testing:' + suite in c]
            self.assertEqual(len(commands), 1, suite)
            self.assertIn('platform=iOS Simulator,id=device-1', commands[0])
            self.assertIn(' ' + suite, output)
        for suite in AUTH_HOSTED + AUTH_UI:
            with self.subTest(suite=suite):
                self.result_fail = suite
                status, output = self.execute(mode='check')
                self.assertEqual(status, 1, output)
                self.assertRegex(output, r'FAIL 17e Debug-(?:compare|serial) ' + re.escape(suite))
                self.assertIn('PASS 17e Release-compare AppTests/ReleaseReadinessTests', output)
        self.result_fail = None

    def test_trip_snapshots_record_then_compare_without_leaking_record_flags(self):
        suite = 'AppTests/TripPageSnapshotTests'
        with patch.dict(os.environ, SNAPSHOT_RECORD='1'):
            status, output = self.execute(aliases=['17e'], only=[suite])
        self.assertEqual(status, 0, output)
        passes = [(c, e) for c, e in zip(self.commands, self.environments)
                  if '-only-testing:' + suite in c and c[-1] == 'test-without-building']
        self.assertEqual(len(passes), 2)
        self.assertEqual(passes[0][1].get('TEST_RUNNER_SNAPSHOT_RECORD'), '1')
        self.assertNotIn('TEST_RUNNER_SNAPSHOT_RECORD', passes[1][1])
        for command, environment in passes:
            self.assertEqual([v for v in command if v.startswith('-only-testing:')],
                             ['-only-testing:' + suite])
            self.assertNotIn('SNAPSHOT_RECORD', environment)

    def test_auth_skipped_expected_failure_or_missing_execution_cannot_pass(self):
        for suite in AUTH_HOSTED + AUTH_UI:
            for result in ['Skipped', 'Expected Failure', 'Failed', None]:
                with self.subTest(suite=suite, result=result):
                    self.nodes = [] if result is None else [
                        {'nodeType': 'Test Case', 'nodeIdentifier': suite + '/testExample()', 'result': result}]
                    status, output = self.execute(aliases=['17e'], only=[suite])
                    self.assertEqual(status, 1, output)
                    self.assertIn('FAIL 17e ', output)
        self.nodes = None

    def test_auth_recording_is_opt_in_17e_only_and_never_reaches_guards_ui_or_release(self):
        for record in ['0', '1', 'all', 'launch']:
            self.commands.clear()
            self.environments.clear()
            with patch.dict(os.environ, {'SNAPSHOT_RECORD': record, 'TEST_RUNNER_SNAPSHOT_RECORD': '1'}):
                status, output = self.execute(mode='check', aliases=['17e', 'duo'],
                    only=list(AUTH_HOSTED + AUTH_UI) + ['AppTests/ReleaseReadinessTests'])
            self.assertEqual(status, 0, output)
            recorded = [c for c, e in zip(self.commands, self.environments) if e.get('TEST_RUNNER_SNAPSHOT_RECORD')]
            self.assertEqual(len(recorded), int(record in ['1', 'all']))
            for command in recorded:
                self.assertIn('platform=iOS Simulator,id=device-1', command)
                self.assertEqual([v for v in command if v.startswith('-only-testing:')],
                                 ['-only-testing:' + suite for suite in AUTH_SNAPSHOTS])
                self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
            for suite in AUTH_UI + ('AppTests/AuthSnapshotGuardTests', 'AppTests/ReleaseReadinessTests'):
                for c, env in zip(self.commands, self.environments):
                    if '-only-testing:' + suite in c:
                        self.assertNotIn('TEST_RUNNER_SNAPSHOT_RECORD', env)

    def test_auth_record_failure_still_runs_compare_audit_and_release(self):
        self.command_failure = lambda c: c[-1] == 'test-without-building' and any('record.xcresult' in a for a in c)
        with patch.dict(os.environ, SNAPSHOT_RECORD='1'):
            status, output = self.execute(mode='check')
        self.assertEqual(status, 1, output)
        self.assertIn('xcodebuild exited 65', output)
        for suite in AUTH_HOSTED + AUTH_UI:
            self.assertTrue(any('-only-testing:' + suite in c and not any('record.xcresult' in a for a in c)
                                for c in self.commands_for_tests()), suite)
        self.assertIn('PASS 17e Release-compare AppTests/ReleaseReadinessTests', output)

    def test_resolves_aliases_by_type_and_runtime_never_name(self):
        self.devices[runner.REGULAR_RUNTIME].insert(0, dict(self.devices[runner.DUO_RUNTIME][0], udid='wrong-runtime'))
        status, output = self.execute(aliases=['se', 'duo'])
        self.assertEqual(status, 0, output)
        self.assertEqual({c[c.index('-destination') + 1] for c in self.commands_for_tests()}, {'platform=iOS Simulator,id=device-0', 'platform=iOS Simulator,id=device-6'})
        self.devices[runner.DUO_RUNTIME].clear()
        status, output = self.execute(aliases=['duo'])
        self.assertEqual(status, 1)
        self.assertIn('No available simulator', output)

    def test_shutdown_boots_once_and_missing_app_skips_uninstall(self):
        self.devices[runner.REGULAR_RUNTIME][0]['state'] = 'Shutdown'
        self.command_failure = lambda c: 'get_app_container' in c
        status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 0, output)
        self.assertEqual(sum(c[:3] == ['xcrun', 'simctl', 'boot'] for c in self.commands), 1)
        self.assertFalse(any('uninstall' in c for c in self.commands))

    def test_software_keyboard_is_enabled_after_boot_before_every_ui_run(self):
        for mode, aliases, only, reuse in [
            ('check', ['17e'], (), False),
            ('runtime', ['duo'], (), False),
            ('check', ['se', 'duo'], ['AppUITests/TwoFactorKeyboardTests'], True),
            ('check', ['se', 'duo'], ['AppUITests/ForgotPasswordTests', 'AppUITests/ForgotPasswordKeyboardTests'], True),
            ('matrix', list(runner.MATRIX), (), False),
        ]:
            for state in ('Shutdown', 'Booted'):
                with self.subTest(mode=mode, aliases=aliases, state=state):
                    self.commands.clear()
                    for devices in self.devices.values():
                        for device in devices:
                            device['state'] = state
                    status, output = self.execute(mode=mode, aliases=aliases, only=only, reuse_build=reuse)
                    self.assertEqual(status, 0, output)
                    for alias in aliases:
                        destination = runner.resolve(alias, self.devices)
                        write = ['xcrun', 'simctl', 'spawn', destination.udid, 'defaults', 'write',
                                 'com.apple.keyboard.preferences', 'AutomaticMinimizationEnabled', '-bool', 'false']
                        self.assertEqual(self.commands.count(write), 1)
                        ready = self.commands.index(['xcrun', 'simctl', 'bootstatus', destination.udid, '-b'])
                        configured = self.commands.index(write)
                        self.assertLess(ready, configured)
                        boot = ['xcrun', 'simctl', 'boot', destination.udid]
                        if state == 'Shutdown':
                            self.assertLess(self.commands.index(boot), ready)
                        else:
                            self.assertNotIn(boot, self.commands)
                        tests = [c for c in self.commands_for_tests() if destination.flag in c]
                        self.assertTrue(tests)
                        for command in tests:
                            self.assertLess(configured, self.commands.index(command))
                    self.assertFalse(any(c[0] == 'defaults' for c in self.commands))

    def test_keyboard_preference_failure_stops_ui_tests_for_that_device(self):
        self.command_failure = lambda c: 'AutomaticMinimizationEnabled' in c
        status, output = self.execute(aliases=['se'], only=['AppUITests/TwoFactorKeyboardTests'])
        self.assertEqual(status, 1, output)
        self.assertIn('Preparation:', output)
        self.assertEqual(self.commands_for_tests(), [])

    def test_perf_uses_shared_preparation_and_keeps_its_scheme_and_configuration(self):
        status, output = self.execute(mode='perf', aliases=['17e'])
        self.assertEqual(status, 0, output)
        builds = [c for c in self.commands if c[-1] == 'build-for-testing']
        self.assertEqual(len(builds), 1)
        tests = self.commands_for_tests()
        self.assertEqual(len(tests), 1)
        for command in builds + tests:
            self.assertEqual(command[command.index('-scheme') + 1], 'Perf')
            self.assertEqual(command[command.index('-configuration') + 1], 'Perf')
            self.assertNotIn('ENABLE_TESTABILITY=YES', command)
        self.assertIn('-only-testing:PerfUITests/LaunchPerfTests', tests[0])
        write = next(c for c in self.commands if 'AutomaticMinimizationEnabled' in c)
        self.assertEqual(write[3], 'device-1')
        self.assertLess(self.commands.index(write), self.commands.index(tests[0]))
        self.assertIn('PASS 17e Perf-compare PerfUITests/LaunchPerfTests', output)

    def test_per_device_result_paths_and_suite_summaries(self):
        status, output = self.execute()
        self.assertEqual(status, 0, output)
        paths = [c[c.index('-resultBundlePath') + 1] for c in self.commands_for_tests()]
        self.assertEqual(len(paths), len(set(paths)))
        for alias in runner.MATRIX:
            expected = f'build/test-results/{alias}/Debug-compare.xcresult'
            self.assertTrue(any(p.endswith(expected) for p in paths))
            self.assertIn(f'PASS {alias} Debug-compare AppTests/DeviceGeometrySmokeTests', output)

    def test_passed_ui_suite_with_package_target_name_is_reported_and_timed(self):
        self.nodes = [{'nodeType': 'UI test bundle', 'name': 'AppUITests', 'children': [
            {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeTests/testDutchAX5TextCanScrollToBothActions()',
             'nodeIdentifierURL': 'test://com.apple.xcode/ChronoFlow/AppUITests/WelcomeTests/testDutchAX5TextCanScrollToBothActions',
             'durationInSeconds': 8.557, 'result': 'Passed'},
            {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeEnglishAccessibilityTests/testAudit()', 'result': 'Passed'},
        ]}]
        status, output = self.execute(aliases=['17e'], only=['AppUITests/WelcomeTests'])
        self.assertEqual(status, 0, output)
        self.assertIn('PASS 17e Debug-compare AppUITests/WelcomeTests', output)
        timings = json.loads((self.scratch / 'build/test-results/timings.json').read_text())
        self.assertEqual(timings['devices']['17e']['suites']['AppUITests/WelcomeTests'], 8.557)

    def test_successful_run_learns_numeric_xcresult_durations(self):
        status, output = self.execute(aliases=['se'], only=['AppUITests/WelcomeTests'])
        self.assertEqual(status, 0, output)
        path = self.scratch / 'build/test-results/timings.json'
        sample = json.loads(path.read_text())['devices']['se']
        self.assertEqual(sample['suites']['AppUITests/WelcomeTests'], 2.25)
        self.assertEqual(sample['tests'], {'AppUITests/WelcomeTests/testExample()': 2.25})
        self.assertGreater(sample['wall'], 0)
        self.assertEqual(sample['selection'], ['AppUITests/WelcomeTests'])

    def test_failing_test_names_and_nonzero_status_continue_other_devices(self):
        self.result_fail = 'AppUITests/WelcomeTests'
        self.command_failure = lambda c: c[-1] == 'test-without-building' and 'platform=iOS Simulator,id=device-0' in c
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn('FAIL se Debug-compare AppUITests/WelcomeTests: AppUITests/WelcomeTests/testExample()', output)
        self.assertRegex(output, r'PASS \w+ Release-compare AppTests/ReleaseReadinessTests')
        self.assertIn('PASS duo Debug-compare AppTests/DeviceGeometrySmokeTests', output)

    def test_failed_case_durations_are_kept_without_turning_failures_into_passes(self):
        self.result_fail = 'AppUITests/WelcomeTests'
        status, output = self.execute(aliases=['17e'], only=['AppUITests/WelcomeTests', 'AppUITests/WelcomeLogicTests'])
        self.assertEqual(status, 1, output)
        self.assertIn('FAIL 17e Debug-compare AppUITests/WelcomeTests', output)
        timings = json.loads((self.scratch / 'build/test-results/timings.json').read_text())
        suites = timings['devices']['17e']['suites']
        self.assertEqual(suites['AppUITests/WelcomeTests'], 2.25)
        self.assertEqual(suites['AppUITests/WelcomeLogicTests'], 2.25)

    def test_empty_results_never_report_a_pass(self):
        self.nodes = []
        status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 1)
        self.assertIn('no executed test cases', output)

    def test_build_failure_still_attempts_other_configuration(self):
        self.command_failure = lambda c: c[-1] == 'build-for-testing' and 'ChronoFlow' in c
        status, output = self.execute(aliases=['17e'])
        self.assertEqual(status, 1)
        self.assertIn('Debug build unavailable', output)
        self.assertIn('PASS 17e Release-compare', output)
        self.assertEqual(len(self.commands_for_tests()), 1)

    def test_inherited_record_flags_are_cleared_from_every_compare_and_build(self):
        with patch.dict(os.environ, {'SNAPSHOT_RECORD': '0', 'TEST_RUNNER_SNAPSHOT_RECORD': '1'}):
            status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 0, output)
        for e in self.environments:
            self.assertNotIn('SNAPSHOT_RECORD', e)
            self.assertNotIn('TEST_RUNNER_SNAPSHOT_RECORD', e)

    def test_matrix_profiles_and_system_references_run_once_on_17e(self):
        selections, _ = runner.schedule('matrix', list(runner.MATRIX))
        for suite in runner.selectors('profiles') + runner.selectors('reference'):
            self.assertEqual([alias for alias in selections if suite in selections[alias]], ['17e'])
        self.assertEqual(set(runner.selectors('profiles') + runner.selectors('reference')) & set(runner.selection('runtime', 'duo')), {'AppUITests/LaunchToWelcomeTests'})

    def test_lpt_is_only_used_for_an_explicit_matrix(self):
        selections, order = runner.schedule('check', ['se', '17e', 'duo'])
        self.assertEqual(order, ['se', '17e', 'duo'])
        selections, order = runner.schedule('matrix', ['se', '17e', 'duo'], only=['AppTests/RootNavigationTests'])
        self.assertEqual(order, ['se', '17e', 'duo'])
        self.assertTrue(all(s == ['AppTests/RootNavigationTests'] for s in selections.values()))

    def test_check_executes_auth_logic_profiles_and_serial_audit_once(self):
        status, output = self.execute(aliases=['17e'], mode='check')
        self.assertEqual(status, 0, output)
        commands = self.commands_for_tests()
        for suite in ['DesignSystemTests/AuthBoardContrastTests', 'AppTests/AuthControlTests', 'AppTests/AuthLayoutTests',
                      'AppTests/AuthSnapshotTests', 'AppUITests/SignInTests', 'AppUITests/AuthAuditTests']:
            matches = [c for c in commands if '-only-testing:' + suite in c]
            self.assertEqual(len(matches), 1, suite)
            self.assertIn('-configuration', matches[0])
            self.assertEqual(matches[0][matches[0].index('-configuration') + 1], 'Debug')
            if suite == 'AppUITests/AuthAuditTests':
                self.assertEqual(matches[0][matches[0].index('-parallel-testing-enabled') + 1], 'NO')

    def test_record_modes_are_isolated_and_paths_cannot_collide(self):
        for mode, expected in [('1', set(runner.SNAPSHOTS[1:])), ('launch', set(runner.SNAPSHOTS[:1])), ('all', set(runner.SNAPSHOTS))]:
            self.setUp()
            with patch.dict(os.environ, {'SNAPSHOT_RECORD': mode, 'TEST_RUNNER_SNAPSHOT_RECORD': '1'}):
                status, output = self.execute(aliases=['17e', 'duo'])
            self.assertEqual(status, 0, output)
            recorded = []
            for c, e in zip(self.commands, self.environments):
                self.assertNotIn('SNAPSHOT_RECORD', e)
                if e.get('TEST_RUNNER_SNAPSHOT_RECORD'):
                    self.assertEqual(c[-1], 'test-without-building')
                    self.assertEqual(c[c.index('-parallel-testing-enabled') + 1], 'NO')
                    self.assertEqual(c[c.index('-parallel-testing-worker-count') + 1], '1')
                    self.assertTrue(c[c.index('-resultBundlePath') + 1].endswith('/record.xcresult'))
                    actual = {x.split(':',1)[1] for x in c if x.startswith('-only-testing:')}
                    self.assertTrue(actual <= expected)
                    self.assertIn('AppTests/LaunchSnapshotTests' if mode == 'launch' else 'AppTests/WelcomeSnapshotTests', actual)
                    if mode == 'all': self.assertIn('AppTests/LaunchSnapshotTests', actual)
                    recorded.append(c[c.index('-destination') + 1])
            self.assertEqual(len(recorded), 1)
            self.assertEqual(recorded, ["platform=iOS Simulator,id=device-1"])

    def test_targeted_reuses_builds_and_keeps_explicit_logic_on_requested_device(self):
        status, output = self.execute(aliases=['se', 'duo', 'se'], only=['AppUITests/ReadinessTests'], reuse_build=True, generate=False)
        self.assertEqual(status, 0, output)
        self.assertFalse(any(c[-1] == 'build-for-testing' or c == ['make', 'generate'] for c in self.commands))
        self.assertEqual(len(self.commands_for_tests()), 2)
        for c in self.commands_for_tests(): self.assertIn('-only-testing:AppUITests/ReadinessTests', c)

    def test_concurrency_is_bounded_and_configurable(self):
        active = maximum = 0
        lock = threading.Lock()
        original = runner.main.__globals__['test_device']
        def worker(*args, **kwargs):
            nonlocal active, maximum
            with lock:
                active += 1
                maximum = max(maximum, active)
            time.sleep(0.025)
            result = original(*args, **kwargs)
            with lock: active -= 1
            return result
        for limit in [1, 2, 4, 7]:
            maximum = 0
            with patch.dict(runner.main.__globals__, test_device=worker), patch.dict(os.environ, SIM_CONCURRENCY=str(limit), TEST_WORKERS="1"):
                status, output = self.execute()
            self.assertEqual(status, 0, output)
            self.assertEqual(maximum, limit)
        for value in [0, -1, 8, 'invalid']:
            with self.assertRaises(ValueError): self.execute(concurrency=value)

    def test_parallel_pass_excludes_global_method_then_runs_it_serially(self):
        original = runner.split_passes
        method = 'AppUITests/WelcomeTests/testSystemAppearance'
        def split(configuration, selected, workers):
            return original(configuration, selected, workers, serial=[method])
        with patch.dict(runner.main.__globals__, split_passes=split):
            status, output = self.execute(aliases=['17e'], only=['AppUITests/WelcomeTests'])
        self.assertEqual(status, 0, output)
        commands = self.commands_for_tests()
        self.assertEqual(len(commands), 2)
        self.assertIn('-skip-testing:' + method, commands[0])
        self.assertEqual(commands[0][commands[0].index('-parallel-testing-enabled') + 1], 'YES')
        self.assertIn('-only-testing:' + method, commands[1])
        self.assertEqual(commands[1][commands[1].index('-parallel-testing-enabled') + 1], 'NO')

    def test_full_auth_audit_is_opt_in_and_forwarded_to_the_test_runner(self):
        for value in ['', '0', '1']:
            with patch.dict(os.environ, {'AUTH_AUDIT_FULL': value, 'TEST_RUNNER_AUTH_AUDIT_FULL': 'stale'}):
                self.commands.clear()
                self.environments.clear()
                status, output = self.execute(aliases=['17e'], only=['AppUITests/AuthAuditTests'], reuse_build=True)
            self.assertEqual(status, 0, output)
            environments = [env for command, env in zip(self.commands, self.environments)
                            if command in self.commands_for_tests()]
            self.assertTrue(environments)
            self.assertTrue(all(env.get('TEST_RUNNER_AUTH_AUDIT_FULL') == ('1' if value == '1' else None)
                                for env in environments))

    def test_intro_order_regression_uses_two_processes_and_separate_results(self):
        with patch.dict(os.environ, {'SNAPSHOT_RECORD': 'all', 'TEST_RUNNER_CF_INTRO_ORDER': 'invalid'}):
            status, output = self.execute(aliases=['se'], intro_order_check=True, reuse_build=True)
        self.assertEqual(status, 0, output)
        tests = self.commands_for_tests()
        self.assertEqual(len(tests), 2)
        enumeration = [c for c in self.commands if '-enumerate-tests' in c]
        self.assertEqual(len(enumeration), 1)
        self.assertIn('-test-enumeration-style', enumeration[0])
        for command in tests:
            self.assertIn('-only-testing:' + runner.INTRO_ORDER_TEST, command)
            self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'NO')
        environments = [e for c, e in zip(self.commands, self.environments) if c[-1] == 'test-without-building' and '-enumerate-tests' not in c]
        self.assertEqual([e.get('TEST_RUNNER_CF_INTRO_ORDER') for e in environments], ['fresh', 'warm'])
        self.assertTrue(all('TEST_RUNNER_SNAPSHOT_RECORD' not in e for e in environments))
        paths = [c[c.index('-resultBundlePath') + 1] for c in tests]
        self.assertNotEqual(*paths)

    def test_intro_enumeration_missing_identifier_stops_before_empty_execution(self):
        self.enumerated = ['AppTests/WelcomeSnapshotTests/frozenIntroOrderIndependenceExtra()']
        status, output = self.execute(aliases=['se'], intro_order_check=True, reuse_build=True)
        self.assertEqual(status, 1)
        self.assertIn('identifier absent from enumeration', output)
        self.assertEqual(self.commands_for_tests(), [])

    def test_skipped_intro_is_a_failure_and_still_attempts_warm_process(self):
        self.nodes = [{'nodeType': 'Test Case', 'nodeIdentifier': runner.INTRO_ORDER_TEST, 'result': 'Skipped'}]
        status, output = self.execute(aliases=['se'], intro_order_check=True, reuse_build=True)
        self.assertEqual(status, 1)
        self.assertIn('Diagnostic did not execute and pass', output)
        self.assertEqual(len(self.commands_for_tests()), 2)

    def test_exact_method_and_target_matching_rejects_prefix_collisions(self):
        nodes = list(runner.result_nodes({'testNodes': [
            {'nodeType': 'Unit test bundle', 'name': 'AppTests', 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeSnapshotTests/frozenIntroOrderIndependence()', 'result': 'Passed'},
                {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeSnapshotTests/frozenIntroOrderIndependenceExtra()', 'result': 'Passed'},
                {'nodeType': 'Test Case', 'nodeIdentifier': 'OtherWelcomeSnapshotTests/frozenIntroOrderIndependence()', 'result': 'Passed'}]},
            {'nodeType': 'UI test bundle', 'name': 'AppUITests', 'children': [
                {'nodeType': 'Test Case', 'nodeIdentifier': 'WelcomeSnapshotTests/frozenIntroOrderIndependence()', 'result': 'Failed'}]},
        ]}))
        matches = runner.matching_nodes(nodes, runner.INTRO_ORDER_TEST)
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0]['target'], 'AppTests')



class SchedulerTests(unittest.TestCase):
    def test_lpt_assigns_long_logic_first_to_earliest_finish(self):
        timings = {"devices": {a: {"matrix_wall": wall, "suites": {
            "AppUITests/ReadinessTests": 100, "AppUITests/WelcomeLogicTests": 50,
        }} for a, wall in [("se", 10), ("duo", 15)]}}
        selected, order = runner.schedule('welcome', ['se', 'duo'], timings=timings)
        self.assertIn('AppUITests/ReadinessTests', selected['se'])
        self.assertIn('AppUITests/WelcomeLogicTests', selected['duo'])
        self.assertEqual(order[0], 'se')

    def test_measured_suite_duration_and_static_fallback(self):
        timings = {'devices': {'se': {'suites': {'AppUITests/ReadinessTests': 25}}}}
        self.assertEqual(runner.suite_seconds('AppUITests/ReadinessTests', 'se', timings), 25)
        self.assertEqual(runner.suite_seconds('AppUITests/ReadinessTests', 'duo', timings), 25)
        self.assertEqual(runner.suite_seconds('AppUITests/ReadinessTests', 'se', {}), 75)
        self.assertEqual(runner.suite_seconds('New/Suite', 'se', {}), 1)
        for value in ['nan', 'inf', -1, None, 'bad']:
            self.assertIsNone(runner.positive_seconds(value))

    def test_auto_concurrency_respects_cores_available_memory_and_seven_cap(self):
        with patch.dict(os.environ, SIM_CONCURRENCY=''):
            self.assertEqual(runner.concurrency_limit(resources=(14, 36 * 1024**3)), 7)
            self.assertEqual(runner.concurrency_limit(resources=(8, 36 * 1024**3)), 4)
            self.assertEqual(runner.concurrency_limit(resources=(14, 5 * 1024**3)), 3)
            self.assertEqual(runner.concurrency_limit(resources=(1, 1)), 1)
            self.assertEqual(runner.concurrency_limit(resources=(14, 0)), 2)
        with patch.dict(os.environ, SIM_CONCURRENCY='6'):
            self.assertEqual(runner.concurrency_limit(resources=(2, 1)), 6)

    def test_available_memory_probe_counts_only_free_reclaimable_pages(self):
        report = 'Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 2.\nPages inactive: 3.\nPages speculative: 4.\nPages wired down: 999.'
        with patch.object(runner.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, report)):
            self.assertEqual(runner.machine_resources()[1], 9 * 16384)
        with patch.object(runner.subprocess, 'run', side_effect=OSError):
            self.assertEqual(runner.machine_resources()[1], 0)

    def test_clone_log_timings_resolve_exact_suites_and_include_failed_work(self):
        content = """+ xcodebuild -only-testing:AppUITests/WelcomeTests -only-testing:AppUITests/WelcomeLogicTests -only-testing:AppTests/WelcomeSnapshotTests -only-testing:RenderTests/WelcomeRenderingTests
Test case 'WelcomeTests.testDutchAX5TextCanScrollToBothActions()' passed on 'Clone 2 of iPhone 17e - AppUITests-Runner (23904)' (8.557 seconds)
Test case 'WelcomeLogicTests.testSignIn()' passed on 'Clone 2 of iPhone 17e - AppUITests-Runner (23904)' (7.155 seconds)
Test case 'WelcomeSnapshotTests/finalWelcome()' failed on 'Clone 1 of iPhone 17e - ChronoFlow (23428)' (34.192 seconds)
Test case 'WelcomeRenderingTests/frozenIntroPixelsStayFixedAcrossClockAndRenderPasses()' passed on 'Clone 1 of iPhone 17e - ChronoFlow (23428)' (84.536 seconds)
335.593 elapsed -- Testing started completed.
"""
        value = runner.log_timings(content)
        self.assertEqual(value['suites'], {
            'AppUITests/WelcomeTests': 8.557, 'AppUITests/WelcomeLogicTests': 7.155,
            'AppTests/WelcomeSnapshotTests': 34.192, 'RenderTests/WelcomeRenderingTests': 84.536})
        self.assertEqual(value['tests']['AppUITests/WelcomeTests/testDutchAX5TextCanScrollToBothActions()'], 8.557)
        self.assertEqual(value['wall'], 335.593)

    def test_bootstrap_log_durations_and_persistence(self):
        content = """+ xcodebuild -only-testing:AppTests/WelcomeSnapshotTests -only-testing:AppUITests/WelcomeTests
Test Suite 'AppTests.xctest' started
✔ Suite WelcomeSnapshotTests passed after 21.3 seconds.
Test Case '-[AppUITests.WelcomeTests testA]' passed (2.500 seconds).
Test Case '-[AppUITests.WelcomeTests testB]' passed (3.000 seconds).
30.5 elapsed -- Testing started completed.
"""
        value = runner.log_timings(content)
        self.assertEqual(value['suites'], {'AppTests/WelcomeSnapshotTests': 21.3, 'AppUITests/WelcomeTests': 5.5})
        self.assertEqual(value['wall'], 30.5)
        self.assertEqual(value['tests']['AppUITests/WelcomeTests/testA'], 2.5)
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            root = Path(directory)
            (root / 'se').mkdir()
            (root / 'se/Debug-compare.log').write_text(content)
            data = runner.bootstrap_timings({'version': 1, 'devices': {}}, root)
            path = root / 'timings.json'
            runner.save_timings(data, path)
            self.assertEqual(runner.load_timings(path), data)
            path.write_text('{bad')
            self.assertEqual(runner.load_timings(path), {'version': 1, 'devices': {}})

    def test_modes_filter_before_balancing_and_targeting_keeps_explicit_repetition(self):
        for mode in ['test', 'snapshots', 'launch-snapshots']:
            selected, _ = runner.schedule(mode, ['se', 'duo'])
            expected = {s for alias in ['se', 'duo'] for s in runner.selection(mode, alias)}
            self.assertEqual(set(s for values in selected.values() for s in values), expected)
        selected, _ = runner.schedule('welcome', ['se', 'duo'], ['AppUITests/ReadinessTests'])
        self.assertEqual(selected, {a: ['AppUITests/ReadinessTests'] for a in ['se', 'duo']})


class ParallelTests(unittest.TestCase):
    def test_method_and_suite_serial_split_preserves_all_selectors(self):
        selected = ['AppTests/WelcomeSnapshotTests', 'AppUITests/WelcomeTests', 'AppUITests/LaunchToWelcomeTests']
        serial = ['AppUITests/WelcomeTests/testSystemAppearance', 'AppUITests/LaunchToWelcomeTests']
        parts = runner.split_passes('Debug', selected, 2, serial=serial)
        self.assertEqual(parts[0].selected, tuple(selected[:2]))
        self.assertEqual(parts[0].skipped, (serial[0],))
        self.assertEqual(parts[0].workers, 2)
        self.assertEqual(parts[1].selected, tuple(serial))
        self.assertEqual(parts[1].workers, 1)
        self.assertEqual(parts[1].suffix, 'serial')
        for configuration, workers in [('Release', 2), ('Debug', 1)]:
            parts = runner.split_passes(configuration, selected, workers, serial=serial)
            self.assertEqual(len(parts), 1)
            self.assertEqual(parts[0].workers, 1)
            self.assertEqual(parts[0].selected, tuple(selected))

    def test_command_enables_workers_and_excludes_serial_methods(self):
        destination = runner.Destination('duo', 'test-device', 'Booted')
        command = runner.test_command(destination, 'Debug', ['AppTests/WelcomeSnapshotTests'], Path('result'), 2, ['AppTests/Example/testGlobal'], Path('events.jsonl'))
        self.assertEqual(command[command.index('-parallel-testing-enabled') + 1], 'YES')
        self.assertEqual(command[command.index('-parallel-testing-worker-count') + 1], '2')
        self.assertIn('-skip-testing:AppTests/Example/testGlobal', command)
        self.assertEqual(command[command.index('-resultStreamPath') + 1], 'events.jsonl')
        self.assertEqual(command[command.index('-test-timeouts-enabled') + 1], 'YES')
        self.assertEqual(command[command.index('-default-test-execution-time-allowance') + 1], '600')
        self.assertEqual(command[command.index('-maximum-test-execution-time-allowance') + 1], '600')
        project = (ROOT / 'project.yml').read_text()
        for target in ['AppTests', 'AppUITests']:
            self.assertIn('- name: ' + target + '\n          parallelizable: true', project)

    def test_heavy_matrix_and_single_device_workers_can_be_disabled(self):
        selected = ['AppUITests/WelcomeTests']
        with patch.dict(os.environ, TEST_WORKERS='2'):
            self.assertEqual(runner.workers_for('se', selected, {}, True), 2)
            self.assertEqual(runner.workers_for('se', runner.selectors('matrix'), {}), 1)
            self.assertEqual(runner.workers_for('duo', runner.selectors('matrix'), {}), 2)
            self.assertEqual(runner.workers_for('duo', ['AppCoreTests/CubicBezierTests'], {}, True), 1)
        with patch.dict(os.environ, TEST_WORKERS='1'):
            self.assertEqual(runner.workers_for('duo', selected, {}, True), 1)
        with patch.dict(os.environ, TEST_WORKERS='5'):
            with self.assertRaises(ValueError): runner.workers_for('duo', selected, {})

    def test_device_appearance_helper_is_used_only_by_registered_serial_callers(self):
        for path in (ROOT / 'AppUITests').glob('*.swift'):
            if 'DeviceAppearance.set' in path.read_text():
                for suite in discovered_suites(path.parent):
                    if re.search(r'class\s+' + suite + r'\b', path.read_text()):
                        self.assertIn('AppUITests/' + suite, runner.SERIAL_TESTS)
        for suite in runner.SERIAL_TESTS:
            parts = runner.split_passes('Debug', [suite], 2)
            self.assertEqual(len(parts), 1)
            self.assertEqual(parts[0].workers, 1)
            self.assertEqual(parts[0].suffix, 'serial')

    def test_global_mutations_require_serial_registration(self):
        for target in ['AppTests', 'AppUITests']:
            for file in (ROOT / target).glob('*.swift'):
                source = file.read_text()
                if re.search(r'XCUIDevice\.shared|UIPasteboard\.general|setContentSizeCategory', source):
                    for suite in discovered_suites(file.parent):
                        if re.search(r'(?:class|struct)\s+' + suite + r'\b', source):
                            self.assertIn(target + '/' + suite, runner.SERIAL_TESTS, file)
        self.assertNotIn('"-AppleInterfaceStyle"', (ROOT / 'AppUITests/LaunchSceneTests.swift').read_text())
        self.assertIn('DeviceAppearance.set', (ROOT / 'AppUITests/LaunchSceneTests.swift').read_text())
        self.assertIn('AppUITests/LaunchToWelcomeTests', runner.SERIAL_TESTS)
        self.assertIn('"-AppleInterfaceStyle"', (ROOT / 'AppUITests/WelcomeTests.swift').read_text())
        self.assertIn('@Suite(.serialized)', (ROOT / 'AppTests/WelcomeSnapshotTests.swift').read_text())

    def test_worker_budget_restores_slots_after_failure_and_bounds_clones(self):
        budget = runner.WorkerBudget(3)
        active = maximum = 0
        lock = threading.Lock()
        def job():
            nonlocal active, maximum
            with budget.claim(2):
                with lock:
                    active += 2
                    maximum = max(maximum, active)
                time.sleep(0.01)
                with lock: active -= 2
        with runner.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda _: job(), range(4)))
        self.assertEqual(maximum, 2)
        with self.assertRaises(RuntimeError):
            with budget.claim(3): raise RuntimeError('test')
        self.assertEqual(budget.available, 3)


class ProfileTests(unittest.TestCase):
    def test_profiles_have_one_model_and_one_unique_output_namespace_per_alias(self):
        catalog = json.loads((ROOT / 'Packages/ChronoFlowKit/Tests/SnapshotSupport/profiles.json').read_text())
        aliases = [device['alias'] for device in catalog['devices'].values()]
        self.assertEqual(set(aliases), set(runner.MATRIX))
        self.assertEqual(len(aliases), len(set(aliases)))
        for device in catalog['devices'].values():
            profile = catalog['profiles'][device['profile']]
            self.assertIn('large', profile['dynamicType'])
            self.assertIn('xxLarge', profile['dynamicType'])
            self.assertTrue(profile['introTimes'])
            self.assertTrue(profile['launchFrames'])

    def test_new_baseline_inventory_is_complete_after_recording(self):
        catalog = json.loads((ROOT / 'Packages/ChronoFlowKit/Tests/SnapshotSupport/profiles.json').read_text())
        for screen in ['Welcome', 'Launch', 'Auth', 'TwoFactor', 'ForgotPassword']:
            expected = set()
            auth_states = {
                'Auth': ['none', 'credentials', 'locked', 'server'],
                'TwoFactor': [f'{mode}-{state}' for mode in ['code', 'recovery']
                              for state in ['none', 'fieldError', 'attempts', 'server']],
                'ForgotPassword': ['form-none', 'form-fieldError', 'form-attempts', 'form-server', 'form-offline', 'sent-none'],
            }
            for device in catalog['devices'].values():
                profile = catalog['profiles'][device['profile']]
                name = f"{device['alias']}-{device['width']}x{device['height']}-{device['scale']}x"
                for style in ['light', 'dark']:
                    for language in ['en', 'nl']:
                        if screen in auth_states:
                            if device['alias'] not in ['17e', 'se', 'duo']:
                                continue
                            categories = ['large'] + (['xxLarge'] if (device['alias'], style, language) == ('17e', 'light', 'en') else [])
                            expected.update(f'{name}-{style}-{language}-{category}-{state}.png'
                                            for category in categories for state in auth_states[screen])
                        elif screen == 'Welcome':
                            for kind, variants in [('finalWelcome', profile['dynamicType']), ('frozenIntro', profile['introTimes'])]:
                                expected.update(f'{kind}.{name}-{style}-{language}-{variant}.png' for variant in variants)
                        else:
                            expected.update(f'sampledSplashFrames.{name}-{style}-{language}-{category}-{frame}.png'
                                            for category in ['large', 'xxLarge'] for frame in profile['launchFrames'])
            directory = ROOT / 'AppTests/__Snapshots__' / ({'Auth': 'Auth', 'TwoFactor': 'Auth/TwoFactor', 'ForgotPassword': 'Auth/Forgot'}.get(screen, f'{screen}SnapshotTests'))
            actual = {p.name for p in directory.glob('*.png')}
            # A wholly unrecorded suite is pending orchestrator work; partial recordings must fail.
            if actual:
                self.assertEqual(actual, expected, screen)
            self.assertEqual(len(expected), {'Welcome': 320, 'Launch': 472, 'Auth': 52, 'TwoFactor': 104, 'ForgotPassword': 78}[screen])


if __name__ == '__main__':
    unittest.main()
