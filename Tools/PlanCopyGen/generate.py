#!/usr/bin/env python3
"""Generate the scoped plan/review catalog from the read-only pinned backend."""
import argparse
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
WEB = ROOT.parent / 'chronoflow-new'
PIN = 'afd80dc0'
DEST = ROOT / 'Packages/ChronoFlowKit/Sources/PlanCore'
ARG = re.compile(r':([A-Za-z][A-Za-z0-9_]*)')
SCOPES = ('app/Planner/', 'app/Planning/', 'app/Actions/Trips/', 'app/Actions/Api/PresentMobileReview.php', 'app/Actions/Api/ReviewMobileTrip.php', 'app/Actions/Api/ReviewGuestTrip.php',
          'app/Http/Requests/Plan/', 'app/Http/Requests/Trips/', 'app/Http/Requests/Api/V1/TripJourneyRequest.php', 'app/Http/Requests/Api/V1/ReviewTripRequest.php',
          'app/Http/Requests/Api/V1/EditReviewTripRequest.php', 'app/Http/Requests/Api/V1/GuestReviewTripRequest.php',
          'app/Http/Requests/Api/V1/SaveTripRequest.php', 'app/Http/Requests/Api/V1/UpdateTripRequest.php', 'app/Http/Responses/Api/ApiValidationMessages.php',
          'app/Http/Responses/TripValidationResponse.php', 'app/Http/Responses/WizardValidationResponse.php')


def show(path):
    return subprocess.check_output(['git', '-C', str(WEB), 'show', f'{PIN}:{path}']).decode()


def forms(value):
    parts = [p.strip() for p in value.split('|')]
    qualified = any(p.startswith(('{', '[')) for p in parts)
    if qualified:
        result = []
        for p in parts:
            m = re.fullmatch(r'\{(-?\d+)\}\s*(.*)|\[(-?\d+),\*\]\s*(.*)', p, re.S)
            if not m:
                raise ValueError(f'Unsupported plural: {value}')
            result.append((m[1] or m[3], m[2] if m[1] is not None else m[4], m[1] is not None))
        return 'coded', result
    if len(parts) > 2 or any(re.search(r'^[\[\{]', p) for p in parts):
        raise ValueError(f'Unsupported plural: {value}')
    return ('plural' if len(parts) == 2 else 'single'), parts


def generate():
    en, nl = (json.loads(show(f'lang/{lang}.json')) for lang in ('en', 'nl'))
    paths = subprocess.check_output(['git', '-C', str(WEB), 'ls-tree', '-r', '--name-only', PIN]).decode().splitlines()
    source = '\n'.join(show(p) for p in paths if p.endswith('.php') and p.startswith(SCOPES))
    source = re.sub(r'/\*.*?\*/|^\s*//[^\n]*', '', source, flags=re.S | re.M)
    # Intersect complete PHP literals, including keys not exercised by the fixture corpus.
    literals = {m[2].replace("\\'", "'").replace('\\"', '"') for m in re.finditer(r"(['\"])((?:\\.|(?!\1).)*?)\1", source, re.S)}
    required = set()
    for path, start, end in [
        ('app/Planning/Copy/CopyKeyMap.php', 'return self::$entries ??= [', '\n        ];'),
        ('app/Planning/Copy/PresenterLine.php', 'public function sentence()', 'public function placeholders()'),
        ('app/Planning/ReviewSummaryLine.php', 'public const string NO_SHIFT', '/** @return'),
    ]:
        fragment = show(path).split(start, 1)[1].split(end, 1)[0]
        for match in re.finditer(r"(['\"])((?:\\.|(?!\1).)*?)\1", fragment, re.S):
            value = match[2].replace("\\'", "'").replace('\\"', '"')
            if ' ' in value and not value.startswith('some|'): required.add(value)
    support = json.loads((pathlib.Path(__file__).parent / 'support-keys.json').read_text())
    units = json.loads((pathlib.Path(__file__).parent / 'format-units.json').read_text())
    for key, values in units.items():
        en[key], nl[key] = values['en'], values['nl']
    keys = (set(en) & literals) | set(support) | set(units)
    fixture_keys = set()
    def walk(value):
        if isinstance(value, dict):
            if isinstance(value.get('key'), str) and isinstance(value.get('args'), list):
                fixture_keys.add(value['key'])
            for v in value.values(): walk(v)
        elif isinstance(value, list):
            for v in value: walk(v)
    for folder in ('plans', 'wizard'):
        for p in (ROOT / f'Packages/ChronoFlowKit/Tests/DataAccessTests/Fixtures/{folder}').glob('*.json'):
            walk(json.loads(p.read_text()))
    keys |= fixture_keys | required
    missing = sorted(k for k in keys if not en.get(k) or not nl.get(k))
    if missing:
        raise ValueError('Missing English/Dutch keys:\n' + '\n'.join(missing))
    strings, entries = {}, []
    def unit(value): return {'stringUnit': {'state': 'translated', 'value': value}}
    for key in sorted(keys):
        names = list(dict.fromkeys(ARG.findall(en[key]) + ARG.findall(key)))
        for name in ARG.findall(nl[key]):
            if name not in names: raise ValueError(f'Unknown Dutch argument {name}: {key}')
        def fmt(value):
            return ARG.sub(lambda m: f'%{names.index(m[1])+1}$@', value.replace('%', '%%'))
        localizations, runtime = {}, {}
        for lang, values in (('en', en), ('nl', nl)):
            kind, variants = forms(values[key])
            if kind == 'coded':
                cases = []
                for i, (bound, text, exact) in enumerate(variants):
                    cases.append({'bound': int(bound), 'exact': exact, 'format': fmt(text)})
                runtime[lang] = {'kind': kind, 'cases': cases}
            else:
                localizations[lang] = (unit(fmt(variants[0])) if kind == 'single' else
                    {'variations': {'plural': dict(zip(('one', 'other'), (unit(fmt(v).replace(f'%{names.index("count")+1}$@', f'%{names.index("count")+1}$lld')) for v in variants)))}})
                runtime[lang] = {'kind': kind, 'formats': [fmt(v) for v in variants]}
        if all(v['kind'] == 'coded' for v in runtime.values()):
            bounds = sorted({c['bound'] for v in runtime.values() for c in v['cases']} |
                            {c['bound'] + 1 for v in runtime.values() for c in v['cases'] if c['exact']})
            for bound in bounds:
                localized = {}
                for lang, translation in runtime.items():
                    case = next((c for c in translation['cases'] if
                                 (bound == c['bound'] if c['exact'] else bound >= c['bound'])), None)
                    if case is None: raise ValueError(f'Uncovered coded case {bound}: {key}')
                    localized[lang] = unit(case['format'])
                strings[f'{key}#case.{bound}'] = {'extractionState': 'manual', 'localizations': localized}
        if localizations: strings[key] = {'extractionState': 'manual', 'localizations': localizations}
        entries.append({'key': key, 'arguments': names, 'languages': runtime})
    for entry in strings.values(): entry['generatesSymbol'] = False
    catalog = {'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}
    # Runtime table is derived from the same catalog formats: explicit language selection works on host too.
    runtime = {'entries': entries}
    report = f'# Plan copy source\n\nBackend `{PIN}`, read with git show. {len(keys)} keys; missing Dutch: 0.\n\nScope: PHP literals in Planner, Planning, trip/review actions and requests, explicit formatter/label keys, and every CopyLine in the S1–S6 and wizard fixtures.\n\nSix duration-unit templates absent from the backend are the exact RN formatter en/nl values in `format-units.json`, preserving `intl-cases.ts`.\n\nThe runtime JSON uses the catalog positional formats and coded range cases; loading is explicit on a worker, never a static initializer.\n'
    return {'Resources/PlanCopy.xcstrings': json.dumps(catalog, ensure_ascii=False, indent=2)+'\n',
            'Resources/PlanCopy.json': json.dumps(runtime, ensure_ascii=False, indent=2)+'\n',
            'Resources/SOURCE.md': report}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path, content in generate().items():
        target = DEST / path
        if args.check:
            if not target.exists() or target.read_text() != content:
                raise ValueError(f'Stale generated output: {target}')
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)


if __name__ == '__main__':
    main()
