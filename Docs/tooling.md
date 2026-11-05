# Tooling and verification — 5 November 2026

Toolchain: Xcode 27.2 (27B52), Apple Swift 6.4.2, XcodeGen 2.46.0 at `/opt/homebrew/bin/xcodegen`.
The app and package use Swift 6 language mode and an iOS 17.0 deployment target. UI modules default to
MainActor; AppCore is nonisolated.

## Commands

Run `Scripts/ci.sh` from a checkout to generate the ignored Xcode project and run `make check`.
`make check` runs strict formatting lint, generator freshness and host tests, AppCore tests and the app
window UI test, then the DesignSystem, Launch and Welcome suites. DesignSystem includes four approved
primitive image baselines; launch snapshots arrive in Phase 3c.

After XcodeGen runs, `make generate` copies the committed `Packages/ChronoFlowKit/Package.resolved`
to `ChronoFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, where Xcode reads
the project's package pins. Xcode ignores the nested package's lockfile when building the project.
All Makefile Xcode builds pass `-onlyUsePackageVersionsFromResolvedFile` so dependency drift fails
instead of silently resolving new versions. Regenerate after updating the committed lockfile.

All Makefile Xcode builds use `build/DerivedData`. The default destination is
`platform=iOS Simulator,name=iPhone 17e,OS=27.2`. Run the Duo window/UI check after `make generate`:

```sh
make duo
```

`make duo` uses Python 3 and `Scripts/duo-destination.py` to read `xcrun simctl list devices -j`.
It selects the first available device with type `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`
under runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`, then passes its resolved UDID
as the destination for `AppUITests/WindowTests`. No UDID is stored in the repo. If no matching device
is available, it exits with an explanation before running xcodebuild.

Duo runs on its own iOS 27.2 runtime (build 24B91016s). The regular iOS 27.2 runtime (24B8117)
has no Duo device type, so `platform=iOS Simulator,name=iPhone Duo,OS=27.2` fails to match.
Use the resolved device destination even though both runtimes report iOS 27.2. Xcodebuild logs a
harmless `IDESchemeActionDeviceRecord ... invalidDigitCount(91016)` line for the Duo runtime's beta
build number; it does not prevent the window checks from passing.

The `Perf` scheme uses Release. Phase 0 supplies only a launch metric smoke test; the comparison harness
belongs to Phase 7. `make tokens fonts assets` regenerates the committed Phase 1 outputs;
`make generators-check` verifies them and runs their host tests (details below).
Signing uses `Config/Base.xcconfig` with an optional `#include? "Local.xcconfig"`. Copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` for device runs.
Simulator signing is disabled independently of that setting.

## Phase 0 verified results

The orchestrator ran the following outside the implementation sandbox on 5 November 2026 with
Xcode 27.2:

- `make generate && make check`: passed (`TEST SUCCEEDED`). Strict formatting lint, AppCore tests,
  `AppUITests/WindowTests` on iPhone 17e / iOS 27.2, and the DesignSystem, Launch and Welcome suites
  all passed. This verifies XcodeGen output through a complete build and app launch.
- `AppUITests/WindowTests` on iPhone Duo / its iPhone19-4 iOS 27.2 runtime, selected by device ID:
  passed. The window frame equals the app frame, and the window screenshot size equals the screen
  screenshot size. Two Duo simulators were installed; one was used for this run. The name/OS
  destination failed to match as described above; the new `make duo` command resolves the ID dynamically.
- Clean clone of `feat/phase-0-scaffold` into a temporary directory, then `Scripts/ci.sh`: exit 0;
  both test runs reported `TEST SUCCEEDED`.
- `xcrun xctrace list templates`: includes `Animation Hitches` and `App Launch` (see below).

Additional checks from the implementation environment:

- `make duo` command wiring: passed with fixture simctl output and a stub xcodebuild. Verified first
  available Duo selection, runtime/type filtering, missing-device errors and command failure propagation.
  The simulator run above used xcodebuild directly; the new target was checked with fixtures here.
- `make generate`: passed. XcodeGen generated `ChronoFlow.xcodeproj`; Xcode 27.2 read the project and
  started package resolution. No fallback project format or generator was substituted.
- `make format`, `make lint`: passed.
- `plutil -lint App/Info.plist`: passed.
- `ibtool --minimum-deployment-target 17.0 --target-device iphone --compile ...`: passed; no document
  errors, warnings or notices. CoreSimulator connection errors also appeared in its log.
- Direct Swift 6 app-shell type-check against `arm64-apple-ios17.0-simulator`: passed.
- All four package targets and their test targets compiled for `arm64-apple-ios17.0-simulator` using
  `swift build --build-tests` with the installed simulator SDK and repo-local caches.
- AppUITests and PerfUITests directly type-checked against the same iOS 17 simulator target. XCTestCase
  subclasses are explicitly nonisolated, with MainActor test methods, to match XCTest's initializers
  under Swift 6.4's default MainActor isolation.
- Host package test run: passed, five Swift Testing tests across all four modules. The test command
  used `--disable-sandbox` to avoid SwiftPM's nested sandbox, repo-local caches, and
  `--triple arm64-apple-macosx14.0`. This is additional compile/test evidence, not simulator validation.
- Catalog guard proof: inserted `Phase 0 catalog guard probe` into `App/InfoPlist.xcstrings` with only
  an English value. `CatalogTests` failed with exit 1 and
  `Missing nl value for 'Phase 0 catalog guard probe'`. Restored the original catalog bytes; the same
  test passed with exit 0. The probe is absent from the committed catalogs.

Local command logs are under ignored `build/Logs/`.

## Instruments templates

Confirmed by the orchestrator with `xcrun xctrace list templates` on 5 November 2026, Xcode 27.2:

```text
Animation Hitches
App Launch
```

Both templates required for later performance work are available. No device performance measurements
were attempted in Phase 0.

## Phase 1 generators and design primitives

TokenGen reads `tokens.json`, checks its nine selected colors against `theme.css` (including aliases),
checks the 55% / 60% sky mid stops and the press rules, and reads the dot definition from `bundle.css`.
All 18 sRGB hex values and all 22 reference sky samples match the plan exactly. Display P3 values
match the table within its stated tolerance. Neither a source conflict nor a missing optical-size
axis was found.

Each sky has 17 stops, including the exact mid stop. Segment interpolation is checked at 1001 points
with a 0.25/255 error budget before rasterization. A separate host Core Animation test compares its
8-bit P3 raster against rounded 8-bit true-OKLab reference samples to within one byte per channel.
The generated report contains the full-precision palette. Dot tiles sample the CSS radial function
at pixel centers at the display scale; CoreGraphics' radial gradient approximation was insufficient
for the specified fade, so no approximate gradient is used for dots.

Google Fonts is pinned to `24ddc1f324cac5d9f5aedca126d298f56e3f1640`; source hashes, output hashes,
licenses, face names and axis cuts are recorded in `Resources/Fonts/manifest.json` and `SOURCE.md`.
Fraunces has opsz 9–144, so cuts 20/32/48 at both weights are available. SOFT=0 / WONK=1 match the
web build: equal font version and exact outlines for the tested Latin characters at all three cuts.
All ten static faces resolve after registration, including a second registration call. The plan's
`CTFontManagerRegisterFontsForURLs` API is used as requested; the SDK emits its deprecation warning.
Registration performs bundle lookup and synchronous CoreText work inside a detached task. Its call
site after the overlay flush belongs to Phase 3b.

AssetGen uses P3 contexts, CoreText and a separable Gaussian for the baked glow, with no runtime
filter or shadow. Its SVG coordinates are flipped once for bitmap rendering. Pixel tests check the
outer arc's color and the inner arc's orientation. Wordmark ink bounds are checked against CoreText
at both scales and in both themes. All app/package asset copies are identical. A generated moon path
also supplies `MoonShape`, so production shape geometry does not duplicate the path constants.

Launch image gamut decision (5 November 2026 review): **accept sRGB in `Assets.car`** for `LaunchMoon`
and `LaunchWordmark`; P3 describes their source PNGs, not their compiled renditions. `assetutil --info`
confirmed sRGB in both the app and package catalogs. Standalone `actool` probes with explicit
`display-gamut` slots (including separate files and P3-only slots) still produced sRGB color data on
Xcode 27.2. [Apple's image-set format](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/ImageSetType.html)
distinguishes display-gamut selection from the stored color space. The dawn colors and dark skyTitle
fit sRGB; light skyTitle exceeds linear sRGB blue by only about 0.0013. An AssetGen test guards that
conversion to 8-bit sRGB and back stays within 1/255 per P3 channel for both tokens in both themes.
That is within Phase 2's 2/255 frame parity budget and avoids duplicate gamut renditions for this
palette. Color sets and runtime gradients remain P3. Revisit this exception when the palette changes.

Primitives accept their actual view/rectangle size and display scale. No production primitive assumes
390 × 844 or uses a phone's fixed safe-area values. The four snapshot fixtures intentionally exercise
isolated primitives at two arbitrary widths, rather than introduce a screen design. They use a common
3× scale and 320 pt height across the simulator matrix.


`Scripts/swiftpm.sh` supplies `--disable-sandbox`, repo-local scratch/cache/config/security directories,
a repo-local temporary directory and `CFFIXED_USER_HOME` for Foundation's cache location. It leaves
`HOME` unchanged. Font tooling uses a repo-local venv, temporary directory and pip cache. Use the
standard SwiftPM build system; the deprecated native build system is not part of this workflow.

UIKit typography requires a nonoptional `UITraitCollection` argument; callers pass their view's traits
with its effective content-size category. On iOS 27.2, the ambient category read by the previous nil-traits
path did not follow `performAsCurrent` for an accessibility category, returning 16 pt instead of 45 pt.
There is no ambient category lookup or default argument now. An explicit `.large` returns the base font;
other categories are passed to `UIFontMetrics`. The splash stays fixed in all categories. Skipping metrics
at `.large` keeps the exact design size and avoids introducing screen-scale-dependent font rounding.
A host probe on this toolchain also reproduced a Swift Testing
mixed-type equality failure: ordinary `CGFloat(32) == Double(32)` is true, while the same expression
inside `#expect` fails. Typography assertions therefore compare two `CGFloat` values, retaining exact
equality without a tolerance. Tests check all eight styles at 2× and 3× with explicit small, large and
accessibilityExtraExtraExtraLarge categories. Scaled sizes must equal the appropriate UIKit text-style
metrics and grow/shrink as expected; default and splash sizes must exactly match the design.

## Phase 1 verification

The implementation environment previously passed `make format`, `make lint`, `make tokens fonts assets`,
`make generators-check` (6 TokenGen tests, 1 AssetGen test covering all 8 PNG variants, 2 Python font
tests), and 11 host package tests. Comparing SHA-256 hashes before and after regeneration confirmed
all 53 generated files were byte-identical. The host excludes the UIKit font and primitive snapshot
functions, so it cannot validate those iOS paths.

The orchestrator ran `make generate && make snapshots` on iPhone 17e / iOS 27.2 on 5 November 2026.
The iOS suites compiled and SnapshotTesting recorded four missing references under
`Tests/DesignSystemTests/__Snapshots__/PrimitiveSnapshotTests/` (within `Packages/ChronoFlowKit`).
The orchestrator visually approved light/dark at 240 and 560 pt widths; those PNGs are preserved.
That run failed on the expected first-recording issues and the UIKit font size assertions. The latter
now compare the same numeric type, and default font sizing bypasses metrics as described above.
The orchestrator subsequently ran `make check` on the same simulator: all checks passed except the new
nil-traits accessibility expectation (16 pt instead of 45 pt). That failure prompted the explicit-traits
API above. The updated UIKit test still requires an outside-sandbox rerun.

After the explicit-traits fix, `make format`, `make lint` and `make generators-check` passed again, as did all 11
host package tests. `swift build --build-tests` with the simulator SDK and
`--triple arm64-apple-ios17.0-simulator` compiled the updated UIKit implementation and test functions.
This compilation uses `build/SwiftPM-iOS` and the same repo-local SwiftPM caches as the host command;
it does not execute simulator tests. `make check` passed lint and generator checks, then failed because
the sandbox denied CoreSimulator/cache access. Logs: `build/Logs/phase-1-explicit-traits-*.log`.

Run the full check and Duo window checks outside Codex's implementation sandbox before committing:

```sh
make generate check
make duo
```

For the full D1c matrix, resolve devices by type/runtime, including Duo's separate runtime. These
commands select the first available device of each required type and run snapshots plus window tests
without storing a UDID:

```sh
set -eu
python3 -I - <<'PY' > build/phase-1-destinations.txt
import json
import subprocess

devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j']))['devices']
regular = 'com.apple.CoreSimulator.SimRuntime.iOS-27-2'
for device_type in ['iPhone-SE-3rd-generation', 'iPhone-17e', 'iPhone-17', 'iPhone-Air', 'iPhone-18-Pro', 'iPhone-18-Pro-Max']:
    identifier = 'com.apple.CoreSimulator.SimDeviceType.' + device_type
    match = next((d for d in devices.get(regular, []) if d.get('isAvailable') and d.get('deviceTypeIdentifier') == identifier), None)
    if match is None:
        raise SystemExit('No available simulator: ' + identifier + ' on ' + regular)
    print('platform=iOS Simulator,id=' + match['udid'])
print(subprocess.check_output(['python3', '-I', 'Scripts/duo-destination.py'], text=True).strip())
PY
while IFS= read -r destination; do
  make snapshots DESTINATION="$destination" || exit 1
  xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
    -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
    -destination "$destination" -only-testing:AppUITests/WindowTests test || exit 1
done < build/phase-1-destinations.txt
```

No hosted launch-screen parity test is added in Phase 1; that belongs to Phase 2. No Phase 1 simulator
matrix pass is claimed. Font API deprecation follows D11's specified registration API. CoreText may
log already-registered fonts when registration is repeated; the registry accepts that condition.
After the four task commits, verify regeneration leaves the checkout clean:

```sh
make tokens fonts assets
git diff --exit-code
```

Local command logs are under ignored `build/Logs/`.
