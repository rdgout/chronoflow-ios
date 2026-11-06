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
            if command[-1] == 'test':
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
        return [c for c in self.commands if c[-1] == 'test']


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
            self.assertIn(f'PASS {alias} Debug-compare AppTests', output)


    def test_empty_results_never_report_a_pass(self):
        self.nodes = []
        status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 1)
        self.assertIn('no executed test cases', output)


    def test_inherited_record_flags_are_cleared_from_every_compare_and_build(self):
        with patch.dict(os.environ, {'SNAPSHOT_RECORD': '0', 'TEST_RUNNER_SNAPSHOT_RECORD': '1'}):
            status, output = self.execute(aliases=['se'])
        self.assertEqual(status, 0, output)
        for e in self.environments:
            self.assertNotIn('SNAPSHOT_RECORD', e)
            self.assertNotIn('TEST_RUNNER_SNAPSHOT_RECORD', e)



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





if __name__ == '__main__':
    unittest.main()
