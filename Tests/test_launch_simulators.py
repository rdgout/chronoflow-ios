import contextlib
import io
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
runner = SimpleNamespace(**runpy.run_path(str(ROOT / 'Scripts/launch-simulators.py')))


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
            if 'XCTestCase' in match.group() or '@Test' in body:
                suites.add(match[1])
                spans.append((start, end))
        for test in re.finditer(r'@Test\b', source):
            if not any(start <= test.start() < end for start, end in spans):
                raise AssertionError(f'{file}: top-level tests need a named, classified suite')
    return suites


class ClassificationTests(unittest.TestCase):
    def test_every_target_and_suite_is_classified_exactly_once(self):
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

    def test_logic_runs_only_on_17e_matrix_runs_on_all_seven(self):
        logic = set(runner.selectors('logic'))
        matrix = set(runner.selectors('matrix'))
        for alias in runner.MATRIX:
            actual = set(runner.selection('welcome', alias))
            self.assertTrue(matrix <= actual)
            self.assertEqual(actual & logic, logic if alias == '17e' else set())
            self.assertEqual(actual & set(runner.selectors('release')), set(runner.selectors('release')) if alias == '17e' else set())
            self.assertFalse(actual & set(runner.selectors('perf')))

    def test_store_and_core_logic_run_on_host_by_default(self):
        host = set(runner.selectors('host'))
        self.assertTrue(any(s.startswith('LocalStoreTests/') for s in host))
        self.assertTrue(any(s.startswith('AppCoreTests/') for s in host))
        self.assertTrue(any(s.startswith('DataAccessTests/') for s in host))
        self.assertTrue(any(s.startswith('SyncTests/') for s in host))
        for alias in runner.MATRIX:
            self.assertFalse(set(runner.selection('welcome', alias)) & host)
        makefile = (ROOT / 'Makefile').read_text()
        self.assertIn('host-tests:\n\tsh Scripts/host-tests.sh', makefile)
        for suite in ('SessionLifecycleTests', 'AccountStorageLifecycleTests', 'KeychainSessionStoreTests'):
            self.assertIn('AppTests/' + suite, runner.selection('welcome', '17e'))

    def test_target_and_method_selection_is_explicit_and_validated(self):
        self.assertEqual(runner.expand(['AppTests/WelcomeSnapshotTests/frozenIntro']), ['AppTests/WelcomeSnapshotTests/frozenIntro'])
        self.assertIn('AppTests/WelcomeSnapshotTests', runner.expand(['AppTests']))
        for selector in ['Unknown', 'PerfUITests', 'AppTests/NewTests']:
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

    def test_release_only_configuration_is_isolated(self):
        result = runner.configurations(['AppTests/ReleaseReadinessTests', 'AppUITests/WelcomeTests'])
        self.assertEqual(result, {'Debug': ['AppUITests/WelcomeTests'], 'Release': ['AppTests/ReleaseReadinessTests']})
        project = (ROOT / 'project.yml').read_text()
        scheme = project.split('\n  ReadinessRelease:\n')[1].split('\n  Perf:\n')[0]
        self.assertIn('targets: [AppTests]', scheme)
        self.assertNotIn('ENABLE_TESTABILITY', project)

    def test_make_check_runs_combined_pass_and_individual_targets_share_runner(self):
        makefile = (ROOT / 'Makefile').read_text()
        self.assertIn('check: lint generators-check launch-resources-check host-tests simulator-check', makefile)
        self.assertNotIn('test snapshots', makefile.split('check:')[-1])
        self.assertIn('--devices $(DEVICES) --only $(ONLY)', makefile)
        self.assertIn('--devices duo', makefile)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.devices = {runner.REGULAR_RUNTIME: [], runner.DUO_RUNTIME: []}
        for index, (_, device_type, runtime) in enumerate(runner.MATRIX.values()):
            self.devices[runtime].append(dict(deviceTypeIdentifier='com.apple.CoreSimulator.SimDeviceType.' + device_type,
                                              isAvailable=True, state='Booted', udid=f'device-{index}'))
        self.commands = []
        self.environments = []
        self.selected = {}
        self.fail = lambda command: False
        self.result_fail = None
        self.nodes = None

    def execute(self, **kwargs):
        def fake_run(command, **options):
            self.assertEqual(options['cwd'], ROOT)
            self.commands.append(command)
            self.environments.append(options['env'])
            status = 65 if self.fail(command) else 0
            if status and options.get('check'):
                raise subprocess.CalledProcessError(status, command)
            if command[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                return subprocess.CompletedProcess(command, status, json.dumps({'devices': self.devices}))
            if command[-1] == 'test-without-building':
                self.selected[command[command.index('-resultBundlePath') + 1]] = [v.split(':', 1)[1] for v in command if v.startswith('-only-testing:')]
            if command[:4] == ['xcrun', 'xcresulttool', 'get', 'test-results']:
                bundle = command[command.index('--path') + 1]
                nodes = self.nodes if self.nodes is not None else [
                    {'nodeType': 'Test Case', 'nodeIdentifier': s + '/testExample()', 'result': 'Failed' if s == self.result_fail else 'Passed'}
                    for s in self.selected[bundle]]
                return subprocess.CompletedProcess(command, status, json.dumps({'testNodes': [{'children': nodes}]}))
            return subprocess.CompletedProcess(command, status, '')
        output = io.StringIO()
        with patch.object(runner.subprocess, 'run', side_effect=fake_run), contextlib.redirect_stdout(output):
            result = runner.main(**kwargs)
        return result, output.getvalue()

    def commands_for_tests(self):
        return [c for c in self.commands if c[-1] == 'test-without-building']

    def test_builds_debug_and_release_once_without_clean_or_reboot(self):
        status, output = self.execute()
        self.assertEqual(status, 0, output)
        builds = [c for c in self.commands if c[-1] == 'build-for-testing']
        self.assertEqual(len(builds), 2)
        self.assertEqual([c[c.index('-configuration') + 1] for c in builds], ['Debug', 'Release'])
        self.assertIn('ENABLE_TESTABILITY=YES', builds[1])
        self.assertEqual(len(self.commands_for_tests()), 8)
        self.assertFalse(any('clean' in c or 'shutdown' in c or 'erase' in c or 'boot' in c for c in self.commands))
        self.assertEqual(sum('uninstall' in c for c in self.commands), 7)
        self.assertNotIn(['make', 'check'], self.commands)
        self.assertNotIn(['make', 'duo'], self.commands)
        for c in self.commands_for_tests():
            self.assertIn('-parallel-testing-enabled', c)
            self.assertEqual(c[c.index('-testLanguage') + 1], 'en')
            self.assertEqual(c[c.index('-testRegion') + 1], 'US')
            self.assertEqual(c[c.index('-maximum-concurrent-test-simulator-destinations') + 1], '1')

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
        self.fail = lambda c: 'get_app_container' in c
        status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 0, output)
        self.assertEqual(sum(c[:3] == ['xcrun', 'simctl', 'boot'] for c in self.commands), 1)
        self.assertFalse(any('uninstall' in c for c in self.commands))

    def test_per_device_result_paths_and_suite_summaries(self):
        status, output = self.execute()
        self.assertEqual(status, 0, output)
        paths = [c[c.index('-resultBundlePath') + 1] for c in self.commands_for_tests()]
        self.assertEqual(len(paths), len(set(paths)))
        for alias in runner.MATRIX:
            expected = f'build/test-results/{alias}/Debug-compare.xcresult'
            self.assertTrue(any(p.endswith(expected) for p in paths))
            self.assertIn(f'PASS {alias} Debug-compare AppTests/WelcomeSnapshotTests', output)

    def test_failing_test_names_and_nonzero_status_continue_other_devices(self):
        self.result_fail = 'AppUITests/WelcomeTests'
        self.fail = lambda c: c[-1] == 'test-without-building' and 'platform=iOS Simulator,id=device-0' in c
        status, output = self.execute()
        self.assertEqual(status, 1)
        self.assertIn('FAIL se Debug-compare AppUITests/WelcomeTests: AppUITests/WelcomeTests/testExample()', output)
        self.assertIn('PASS 17e Release-compare', output)
        self.assertIn('PASS duo Debug-compare AppTests/WelcomeSnapshotTests', output)

    def test_empty_results_never_report_a_pass(self):
        self.nodes = []
        status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 1)
        self.assertIn('no executed test cases', output)

    def test_build_failure_still_attempts_other_configuration(self):
        self.fail = lambda c: c[-1] == 'build-for-testing' and 'ChronoFlow' in c
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
                    self.assertTrue(c[c.index('-resultBundlePath') + 1].endswith('/record.xcresult'))
                    actual = {x.split(':',1)[1] for x in c if x.startswith('-only-testing:')}
                    self.assertEqual(actual, expected - ({'AppTests/WelcomeSnapshotGuardTests'} if 'platform=iOS Simulator,id=device-6' in c else set()))
                    recorded.append(c[c.index('-destination') + 1])
            self.assertEqual(len(recorded), 2)
            self.assertEqual(len(set(recorded)), 2)

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
        def worker(*args):
            nonlocal active, maximum
            with lock:
                active += 1
                maximum = max(maximum, active)
            time.sleep(0.025)
            result = original(*args)
            with lock: active -= 1
            return result
        for limit in [1, 2, 4]:
            maximum = 0
            with patch.dict(runner.main.__globals__, test_device=worker), patch.dict(os.environ, SIM_CONCURRENCY=str(limit)):
                status, output = self.execute()
            self.assertEqual(status, 0, output)
            self.assertEqual(maximum, limit)
        for value in [0, -1, 5, 'invalid']:
            with self.assertRaises(ValueError): self.execute(concurrency=value)

    def test_intro_order_regression_uses_two_processes_and_separate_results(self):
        with patch.dict(os.environ, {'SNAPSHOT_RECORD': 'all', 'TEST_RUNNER_CF_INTRO_ORDER': 'invalid'}):
            status, output = self.execute(aliases=['se'], intro_order_check=True, reuse_build=True)
        self.assertEqual(status, 0, output)
        tests = self.commands_for_tests()
        self.assertEqual(len(tests), 2)
        environments = [e for c, e in zip(self.commands, self.environments) if c[-1] == 'test-without-building']
        self.assertEqual([e.get('TEST_RUNNER_CF_INTRO_ORDER') for e in environments], ['fresh', 'warm'])
        self.assertTrue(all('TEST_RUNNER_SNAPSHOT_RECORD' not in e for e in environments))
        paths = [c[c.index('-resultBundlePath') + 1] for c in tests]
        self.assertNotEqual(*paths)


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

    def test_welcome_baselines_exactly_match_device_profiles(self):
        catalog = json.loads((ROOT / 'Packages/ChronoFlowKit/Tests/SnapshotSupport/profiles.json').read_text())
        directory = ROOT / 'AppTests/__Snapshots__/WelcomeSnapshotTests'
        expected = set()
        for model, device in catalog['devices'].items():
            for kind, variants in [('finalWelcome', ['large', 'xxLarge']), ('frozenIntro', catalog['profiles'][device['profile']]['introTimes'])]:
                for style in ['light', 'dark']:
                    for language in ['en', 'nl']:
                        for variant in variants:
                            expected.add((kind, model, style, language, str(variant)))
        actual = set()
        for image in directory.glob('*.png'):
            match = re.fullmatch(r'(finalWelcome|frozenIntro)\.(iPhone\d+,\d+)-\d+x\d+-[23]x-(light|dark)-(en|nl)-(.+)\.png', image.name)
            self.assertIsNotNone(match, image.name)
            actual.add(match.groups())
        self.assertEqual(actual, expected)


if __name__ == '__main__':
    unittest.main()
