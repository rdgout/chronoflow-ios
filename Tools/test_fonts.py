import hashlib
import io
import json
from pathlib import Path
import runpy
import unittest
import tempfile
from unittest.mock import patch
import urllib.error
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / 'Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Fonts'
download = runpy.run_path(str(ROOT / 'Tools/generate_fonts.py'))['download']


class FontTests(unittest.TestCase):
    def test_all_cuts_names_hashes_and_dutch_coverage(self):
        manifest = json.loads((FONT_DIR / 'manifest.json').read_text())
        self.assertEqual(len(manifest['faces']), 10)
        cuts = set()
        for face in manifest['faces']:
            path = FONT_DIR / face['file']
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), face['sha256'])
            font = TTFont(path)
            self.assertNotIn('fvar', font)
            self.assertEqual(font['name'].getDebugName(6), face['postScriptName'])
            self.assertEqual(font['OS/2'].usWeightClass, face['weight'])
            self.assertTrue(all(ord(c) in font.getBestCmap() for c in 'ChronoFlowëïéèÉáóúü'))
            cuts.add((face['family'], face['weight'], face['opsz']))
        self.assertEqual(cuts, {('Figtree', w, None) for w in [400, 500, 600, 700]} | {('Fraunces', w, o) for w in [400, 500] for o in [20, 32, 48]})

    def test_licenses(self):
        for family in ['Fraunces', 'Figtree']:
            self.assertIn('SIL OPEN FONT LICENSE', (FONT_DIR / f'{family}-OFL.txt').read_text())


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.root_patch = patch.dict(download.__globals__, ROOT=self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.cache = self.root / 'build/FontSources/figtree-source.ttf'
        self.cache.parent.mkdir(parents=True)
        self.data = b'verified upstream source'
        self.expected_hash = hashlib.sha256(self.data).hexdigest()

    def test_valid_cache_needs_no_network(self):
        self.cache.write_bytes(self.data)
        with patch('urllib.request.urlopen') as fetch:
            self.assertEqual(download('Figtree', 'source.ttf', self.expected_hash), self.cache)
            fetch.assert_not_called()

    def test_corrupt_cache_is_replaced_by_a_verified_download(self):
        self.cache.write_bytes(b'truncated')
        with patch('urllib.request.urlopen', return_value=io.BytesIO(self.data)) as fetch:
            self.assertEqual(download('Figtree', 'source.ttf', self.expected_hash), self.cache)
            fetch.assert_called_once()
        self.assertEqual(self.cache.read_bytes(), self.data)
        self.assertEqual(list(self.cache.parent.iterdir()), [self.cache])

    def test_bad_download_is_discarded_and_can_be_retried(self):
        self.cache.write_bytes(b'corrupt cache')
        with patch('urllib.request.urlopen', return_value=io.BytesIO(b'bad download')):
            with self.assertRaisesRegex(RuntimeError, 'Source hash mismatch'):
                download('Figtree', 'source.ttf', self.expected_hash)
        self.assertEqual(list(self.cache.parent.iterdir()), [])
        with patch('urllib.request.urlopen', return_value=io.BytesIO(self.data)):
            download('Figtree', 'source.ttf', self.expected_hash)
        self.assertEqual(self.cache.read_bytes(), self.data)

    def test_network_failure_leaves_no_partial_cache(self):
        with patch('urllib.request.urlopen', side_effect=urllib.error.URLError('interrupted')):
            with self.assertRaises(urllib.error.URLError):
                download('Figtree', 'source.ttf', self.expected_hash)
        self.assertEqual(list(self.cache.parent.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
