import importlib.util
import json
import unittest
import sys

sys.dont_write_bytecode = True
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('plan_copy', ROOT / 'Tools/PlanCopyGen/generate.py')
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class PlanCopyGeneratorTests(unittest.TestCase):
    def test_plural_grammar(self):
        self.assertEqual(gen.forms('one|other'), ('plural', ['one', 'other']))
        self.assertEqual(gen.forms('{1} half|[2,*] cups')[0], 'coded')
        for value in ['one|two|three', '{1,2} invalid|[3,*] cups', '[1,4] invalid', '{x} invalid']:
            with self.assertRaises(ValueError): gen.forms(value)

    def test_all_fixture_copy_resolves(self):
        entries = {v['key']: v for v in json.loads((gen.DEST / 'Resources/PlanCopy.json').read_text())['entries']}
        def check(value):
            if isinstance(value, dict):
                if isinstance(value.get('key'), str) and isinstance(value.get('args'), list):
                    self.assertIn(value['key'], entries)
                    self.assertEqual(set(entries[value['key']]['languages']), {'en', 'nl'})
                for v in value.values(): check(v)
            elif isinstance(value, list):
                for v in value: check(v)
        for folder in ('plans', 'wizard'):
            for path in (ROOT / f'Packages/ChronoFlowKit/Tests/DataAccessTests/Fixtures/{folder}').glob('*.json'):
                check(json.loads(path.read_text()))

    def test_missing_dutch_fails(self):
        original = gen.show
        def missing(path):
            if path == 'lang/nl.json': return '{}'
            return original(path)
        gen.show = missing
        try:
            with self.assertRaisesRegex(ValueError, 'Missing English/Dutch'): gen.generate()
        finally: gen.show = original


    def test_every_catalog_case_has_both_languages(self):
        catalog = json.loads((gen.DEST / 'Resources/PlanCopy.xcstrings').read_text())
        for key, value in catalog['strings'].items():
            self.assertEqual(set(value['localizations']), {'en', 'nl'}, key)

    def test_missing_english_copy_map_key_fails(self):
        original = gen.show
        def missing(path):
            value = original(path)
            if path == 'lang/en.json':
                values = json.loads(value)
                values.pop('Keep lights dim until :untilUtc.')
                return json.dumps(values)
            return value
        gen.show = missing
        try:
            with self.assertRaisesRegex(ValueError, 'Missing English/Dutch'): gen.generate()
        finally: gen.show = original


if __name__ == '__main__': unittest.main()
