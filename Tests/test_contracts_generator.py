import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = runpy.run_path(str(ROOT / 'Tools/contracts-gen/generate.py'))


class ContractsGeneratorTests(unittest.TestCase):
    def test_formatting_is_independent_of_working_directory(self):
        check_output = subprocess.check_output

        def source_or_formatter(command, **kwargs):
            if command[0] == 'git':
                if command[-1].endswith('/Data/Api/index.ts'):
                    return ''.join(f'export type {name} = {{\nreadonly value: string,\n}};\n'
                                   for name in GENERATOR['ROOT_TYPES'])
                return ''
            return check_output(command, **kwargs)

        previous = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as directory, patch.object(
                    GENERATOR['subprocess'], 'check_output', side_effect=source_or_formatter):
                outside = Path(directory)
                (outside / '.swift-format').write_text('{"indentation":{"spaces":2},"lineLength":40}')
                os.chdir(ROOT)
                expected = GENERATOR['generate'](ROOT)
                os.chdir(outside)
                actual = GENERATOR['generate'](ROOT)
                self.assertIn('    public var value: String', expected)
                self.assertEqual(actual, expected)
        finally:
            os.chdir(previous)

    def test_wizard_records_request_keys_and_fractional_bounds(self):
        check_output = subprocess.check_output

        def source_or_formatter(command, **kwargs):
            if command[0] == 'git':
                if not command[-1].endswith('/Data/Api/index.ts'):
                    return ''
                definitions = {name: '{\nreadonly value: string,\n}' for name in GENERATOR['ROOT_TYPES']}
                definitions.update({
                    'ApiTripInput': '{\nreadonly trip_end_kind: string,\nreadonly seat_lie_flat: boolean,\n}',
                    'ApiTripReview': '{\nreadonly shape: ApiReviewPromptShape,\nreadonly answer: Record<string, boolean | number | string | null>,\n}',
                    'ApiReviewPromptShape': '{\nreadonly min: number | null,\nreadonly max: number | null,\n}',
                    'ApiTripInputSnapshot': '{\nreadonly airports: Record<string, ApiAirportSuggestion>,\n}',
                    'ApiAirportSuggestion': '{\nreadonly timezone: string,\n}',
                })
                return ''.join(f'export type {name} = {body};\n' for name, body in definitions.items())
            return check_output(command, **kwargs)

        with patch.object(GENERATOR['subprocess'], 'check_output', side_effect=source_or_formatter):
            result = GENERATOR['generate'](ROOT)
        self.assertIn('case tripEndKind = "trip_end_kind"', result)
        self.assertIn('case seatLieFlat = "seat_lie_flat"', result)
        self.assertIn('public var min: Double?', result)
        self.assertIn('public var max: Double?', result)
        self.assertIn('public var answer: [String: JSONValue]', result)
        self.assertIn('public var airports: [String: ApiAirportSuggestion]', result)

    def test_request_graph_encodes_nulls_but_omits_optional_keys(self):
        check_output = subprocess.check_output

        def source_or_formatter(command, **kwargs):
            if command[0] == 'git':
                if not command[-1].endswith('/Data/Api/index.ts'):
                    return ''
                definitions = {name: '{\nreadonly value: string,\n}' for name in GENERATOR['ROOT_TYPES']}
                definitions.update({
                    'ApiTripInput': '{\nreadonly child: RequestChild,\n}',
                    'RequestChild': ('{\nreadonly required: string | null,\n'
                                     'readonly optional?: string,\nreadonly optional_nullable?: string | null,\n}'),
                    'ApiTripReview': '{\nreadonly response: string | null,\n}',
                })
                return ''.join(f'export type {name} = {body};\n' for name, body in definitions.items())
            return check_output(command, **kwargs)

        with patch.object(GENERATOR['subprocess'], 'check_output', side_effect=source_or_formatter):
            result = GENERATOR['generate'](ROOT)
        self.assertIn('try container.encode(required, forKey: .required)', result)
        self.assertIn('try container.encodeIfPresent(optional, forKey: .optional)', result)
        self.assertIn('try container.encodeIfPresent(optionalNullable, forKey: .optionalNullable)', result)
        self.assertNotIn('try container.encode(response,', result)


if __name__ == '__main__':
    unittest.main()
