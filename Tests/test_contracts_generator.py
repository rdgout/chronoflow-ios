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


if __name__ == '__main__':
    unittest.main()
