import hashlib
import json
from pathlib import Path
import unittest
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
FONT_DIR = ROOT / 'Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Fonts'


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


if __name__ == '__main__':
    unittest.main()
