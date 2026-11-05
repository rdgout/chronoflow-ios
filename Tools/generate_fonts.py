import hashlib
import json
from pathlib import Path
import sys
import tempfile
import urllib.parse
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
COMMIT = '24ddc1f324cac5d9f5aedca126d298f56e3f1640'
FAMILIES = {
    'Figtree': ('Figtree[wght].ttf', '26ad3db9b31ff7dde67a91ff515d022d2f495cd506590699cf264f0bfe6fb714'),
    'Fraunces': ('Fraunces[SOFT,WONK,opsz,wght].ttf', '177ff6c0f14e5550a3c624247cd1189611d4eb65d000b14944c63d967958abbb'),
}
LICENSE_HASHES = {
    'Figtree': '140d37233e7f3ce7313798befa9600893bcceaf41a55fa0fa5ad52f7f657a268',
    'Fraunces': 'bdf4c22802eaf804f998195871c6b8938aac2ac14b2d78a8bd66a6f1eced833b',
}
FONT_DIR = ROOT / 'Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Fonts'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def download(family, filename, expected_hash):
    cache = ROOT / 'build/FontSources' / f'{family.lower()}-{filename}'
    if cache.exists():
        if digest(cache.read_bytes()) == expected_hash:
            return cache
        cache.unlink()
    cache.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        url = f'https://raw.githubusercontent.com/google/fonts/{COMMIT}/ofl/{family.lower()}/{urllib.parse.quote(filename)}'
        with tempfile.NamedTemporaryFile(dir=cache.parent, prefix=f'.{cache.name}.', delete=False) as output:
            temporary = Path(output.name)
            with urllib.request.urlopen(url, timeout=30) as response:
                output.write(response.read())
        if digest(temporary.read_bytes()) != expected_hash:
            raise RuntimeError(f'Source hash mismatch: {family}/{filename}; download discarded, retry when the network is reliable')
        temporary.replace(cache)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return cache


def generate(check=False):
    import io
    outputs = {}
    faces = []
    sources = {}
    for family, (filename, expected_hash) in FAMILIES.items():
        path = download(family, filename, expected_hash)
        sources[filename] = digest(path.read_bytes())
        outputs[f'{family}-OFL.txt'] = download(family, 'OFL.txt', LICENSE_HASHES[family]).read_bytes()
        original = TTFont(path, recalcTimestamp=False)
        axes = {a.axisTag: (a.minValue, a.defaultValue, a.maxValue) for a in original['fvar'].axes}
        if family == 'Fraunces':
            if 'opsz' not in axes or not axes['opsz'][0] <= 20 < 32 < 48 <= axes['opsz'][2]:
                raise RuntimeError('Fraunces lacks the opsz axis or cannot produce opsz 20/32/48; stop for plan review')
            if axes['SOFT'][1] != 0 or axes['WONK'][1] != 1:
                raise RuntimeError('Fraunces defaults differ from the verified web build: SOFT 0 / WONK 1')
        for weight in ([400, 500, 600, 700] if family == 'Figtree' else [400, 500]):
            for optical in ([None] if family == 'Figtree' else [20, 32, 48]):
                cuts = {'wght': weight}
                if optical is not None:
                    cuts.update(opsz=optical, SOFT=0, WONK=1)
                font = instantiateVariableFont(original, cuts, inplace=False)
                font.recalcTimestamp = False
                ps = f'CF{family}-{weight}' + (f'-Opsz{optical}' if optical else '')
                family_name = f'CF {family}' + (f' Opsz {optical}' if optical else '')
                style = {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold'}[weight]
                # Optical cuts need distinct names so CoreText cannot substitute another cut.
                for name_id, value in {1: family_name, 2: style, 3: ps, 4: f'{family_name} {style}', 6: ps, 16: family_name, 17: style}.items():
                    font['name'].removeNames(nameID=name_id)
                    font['name'].setName(value, name_id, 3, 1, 0x409)
                assert 'fvar' not in font
                font['head'].modified = original['head'].modified
                out = io.BytesIO()
                font.save(out)
                data = out.getvalue()
                outputs[ps + '.ttf'] = data
                faces.append(dict(file=ps + '.ttf', postScriptName=ps, family=family, weight=weight, opsz=optical, sha256=digest(data)))
    manifest = dict(googleFontsCommit=COMMIT, sources=sources, fonttools='4.60.1', brotli='1.1.0', faces=faces)
    outputs['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    outputs['SOURCE.md'] = f'''# Font sources

Google Fonts commit [`{COMMIT}`](https://github.com/google/fonts/tree/{COMMIT}), fetched 2026-11-05. Both families are OFL licensed; their licenses are included separately. Full upstream TTF character sets are retained (including English and Dutch).

Regenerate with `make fonts`; verify with `sh Tools/fonts.sh --check`. fonttools 4.60.1 and brotli 1.1.0 are pinned in a repo-local venv. Source and output SHA-256 hashes, face names and axis cuts are in `manifest.json`. No variable axes remain in the output.

The first run (including `make check` and `Scripts/ci.sh` on a clean clone) needs network access to PyPI for those tools and to `raw.githubusercontent.com` for the pinned TTFs and OFL licenses. The ignored `build/fonttools-venv`, `build/pip-cache` and `build/FontSources` hold the local tools and sources; warmed tools and verified sources can be reused offline. Every cached source and license is checksum-verified before use. A corrupt cache entry is removed and fetched again; downloads are verified in temporary files before atomic replacement, so a failed fetch cannot poison later runs. License hashes are pinned in `Tools/generate_fonts.py`.

Fraunces source version 1.000 [b76b70a41] has opsz 9–144 (default 9), wght 100–900 (default 900), SOFT 0–100 (default 0), WONK 0–1 (default 1). Cuts pin SOFT=0 and WONK=1. The web's `@fontsource-variable/fraunces/files/fraunces-latin-opsz-normal.woff2` has the same version and retains opsz/wght only. Its outlines for A–Z, a–z, the wordmark and ëïéè were compared at opsz 20/32/48 and weight 400: exact matches to the Google source with SOFT=0 / WONK=1. No synthetic bold or optical-size substitution is used.

Figtree cuts: weights 400/500/600/700. Fraunces cuts: weights 400/500 × opsz 20/32/48. Unique CF-prefixed PostScript/family names keep the optical cuts distinct; original copyright/license records are preserved. Registration belongs after the overlay flush (Phase 3b), through `FontRegistry.register()`.
'''.encode()
    for filename, data in outputs.items():
        target = FONT_DIR / filename
        if check:
            if not target.exists() or target.read_bytes() != data:
                raise RuntimeError(f'Stale font output: {target.relative_to(ROOT)}')
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    generate_metrics(check)
    print(f'Fonts: {len(faces)} static faces {"verified" if check else "written"}; Fraunces opsz 20/32/48, SOFT 0, WONK 1.')


def generate_metrics(check):
    import re
    import subprocess
    source = json.loads((ROOT / '_design/canvas/ds/chronoflow/tokens.json').read_text())
    styles = {s['name']: s for group in source['type']['groups'] for s in group['styles']}
    board = (ROOT / '_design/canvas/SplashScreen.dc.html').read_text()
    word = re.search(r"word: '([^']+)'", board).group(1)
    styles['splash-wordmark'] = dict(fontSize=re.search(r'font-size: ([0-9]+px)', word).group(1), lineHeight=re.search(r'line-height: ([0-9]+px)', word).group(1), letterSpacing=re.search(r'letter-spacing: (-?[0-9.]+em)', word).group(1))
    styles['button'] = dict(fontSize=styles['body-lg']['fontSize'], lineHeight=None)
    swift = '// Generated by Tools/fonts.sh from tokens.json and SplashScreen. Do not edit.\nnonisolated struct TypeMetrics { let size: Double; let lineHeight: Double?; let tracking: Double\n'
    for name in ['splash-wordmark', 'body', 'section-title', 'eyebrow', 'hero', 'body-lg', 'button']:
        style = styles[name]
        size = float(style['fontSize'].removesuffix('px'))
        line = style['lineHeight']
        line = float(line.removesuffix('px')) if isinstance(line, str) else (line * size if line else None)
        tracking = float(style.get('letterSpacing', '0em').removesuffix('em')) * size
        camel = name.split('-')[0] + ''.join(w.title() for w in name.split('-')[1:])
        swift += f'static var {camel}: TypeMetrics {{ TypeMetrics(size: {size}, lineHeight: {line if line else "nil"}, tracking: {tracking}) }}\n'
    swift += '}\n'
    result = subprocess.run(['/usr/bin/xcrun', 'swift', 'format', 'format', '--configuration', str(ROOT / '.swift-format'), '-'], input=swift.encode(), capture_output=True, check=True).stdout
    target = ROOT / 'Packages/ChronoFlowKit/Sources/DesignSystem/TypeMetrics.generated.swift'
    if check:
        if target.read_bytes() != result:
            raise RuntimeError('Stale typography metrics')
    else:
        target.write_bytes(result)


if __name__ == '__main__':
    generate('--check' in sys.argv)
