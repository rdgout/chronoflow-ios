# Tooling and verification — 5 November 2026

Toolchain: Xcode 27.2 (27B52), Apple Swift 6.4.2, XcodeGen 2.46.0 at `/opt/homebrew/bin/xcodegen`.
The app and package use Swift 6 language mode and an iOS 17.0 deployment target. UI modules default to
MainActor; AppCore is nonisolated.

## Commands

Run `Scripts/ci.sh` from a checkout to generate the ignored Xcode project and run `make check`.
`make check` runs strict formatting lint, generator freshness and host tests, hosted launch and AppCore
tests and the app window UI test, then the DesignSystem, Launch and Welcome suites. DesignSystem includes four approved
primitive image baselines; launch snapshots arrive in Phase 3c.

A clean clone needs network access for `make check` / `Scripts/ci.sh`: SwiftPM fetches the pinned
SnapshotTesting dependency from GitHub; `Tools/fonts.sh` installs fonttools 4.60.1 and brotli 1.1.0
from PyPI (including its file host) and fetches the pinned font TTFs and OFL licenses from
`raw.githubusercontent.com`. `--check` re-derives the committed outputs and has the same bootstrap
requirements as regeneration. Warm SwiftPM caches, `build/fonttools-venv` and `build/FontSources`
allow reuse offline; deleting `build` removes these local prerequisites. `build/pip-cache` caches
Python downloads. Every cached font source and license is SHA-256 verified; corrupt entries are
removed and downloaded again. Downloads go through temporary files, are verified before atomic
replacement, and are discarded on failure. Fix the network and rerun after a failed download;
manual cache deletion is unnecessary.

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
as the destination for `AppTests` and `AppUITests/WindowTests`. No UDID is stored in the repo. If no matching device
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
at both scales and in both themes. All app/package asset copies are identical. AssetGen parses the
moon's SVG `d` attribute from `SplashScreen.dc.html`, resolves its circular arcs (including SVG radius
correction), and uses that one description for the PNG, retained SVG and generated `MoonGlyph` used
by `MoonShape`. Unsupported path syntax fails generation. A translated in-memory board fixture
checks that changes reach both raster and Swift output; the board files themselves stay read-only.

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

The orchestrator verified the committed Phase 1 state outside the implementation sandbox on
2026-11-05 with Xcode 27.2:

- `make generate`: passed.
- `make snapshots` on iPhone 17e / iOS 27.2: passed. Four primitive baselines (light/dark at
  240 and 560 pt widths) were recorded and visually approved under
  `Packages/ChronoFlowKit/Tests/DesignSystemTests/__Snapshots__/PrimitiveSnapshotTests/`.
- `make check` on iPhone 17e / iOS 27.2: passed, including the updated explicit-traits UIKit font
  tests and the approved primitive snapshots. The earlier nil-traits failure is resolved.
- `make duo`: passed on iPhone Duo's iPhone19-4 iOS 27.2 runtime (24B91016s).
- `make tokens fonts assets`: reproduced the committed generated outputs with no diff.

The review corrections retain those four approved baselines. The implementation environment verifies
wordmark alpha coverage against an explicitly unsmoothed render at both scales in both themes,
advance-box centring within 0.01 pt, the sRGB palette round-trip bound, board-derived moon geometry,
and font-cache recovery. `make lint`, `make generators-check` (6 TokenGen tests, 3 AssetGen tests
covering all 8 PNG variants and the added regressions, 6 Python font/cache tests), regeneration and
all 11 host package tests pass. Repeating regeneration preserves every generated byte. Host tests
exclude the UIKit font and primitive snapshot functions; they do not replace simulator validation.
Mutation probes regenerated wordmarks with smoothing enabled and with left-aligned advances;
the alpha-coverage and midpoint assertions respectively rejected them. Both probes were restored.

For the revised tree, the orchestrator should run these outside the implementation sandbox:

```sh
make generate check
make duo
```

Inspect the rebuilt catalog encodings as well; sRGB launch images are accepted under D10's bounded
palette exception, while the source PNGs and color sets remain P3:

```sh
xcrun assetutil --info build/DerivedData/Build/Products/Debug-iphonesimulator/ChronoFlow.app/Assets.car
xcrun assetutil --info build/DerivedData/Build/Products/Debug-iphonesimulator/ChronoFlowKit_DesignSystem.bundle/Assets.car
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

Hosted launch-screen parity tests belong to Phase 2. The completed runs above cover iPhone 17e
and Duo; the remaining D1c devices have no recorded Phase 1 matrix pass. Font API deprecation follows
D11's specified registration API. CoreText may log already-registered fonts when registration is
repeated; the registry accepts that condition.
After applying the review patches and committing them, regeneration should leave the checkout clean:

```sh
make tokens fonts assets
git diff --exit-code
```

Local command logs are under ignored `build/Logs/`.

## Phase 2 system launch screen

`AppTests` is a hosted unit-test target: it loads the app's compiled `LaunchScreen.storyboard` and
main-bundle assets in a real scene window. `make test` includes it; `make duo` runs it alongside
the existing window UI test on Duo's separate runtime. Host resource tests check the storyboard's
constraints, unlocalised text-free structure, generated asset references and hosted-test linkage. `make launch-resources-check`
is part of `make check` and also runs eight fixture tests for the simulator matrix runner.

`LaunchStoryboardTests` checks behaviour after layout in the running device's window, in both
appearances, with normal and asymmetric safe-area insets. The image view's centre must match the
whole window within 0.5 pt, its size must match the catalog asset's natural size, every edge must
align to the display's pixel grid, and the background must resolve to the named `LaunchSky` colour.
The storyboard moon and catalog moon are rendered into identical 8-bit Display P3 buffers; no channel
may differ by more than 2/255. The reference asset is explicitly resolved using the requested
`userInterfaceStyle` and the window's `displayScale`, then copied into a `UIImage(cgImage:scale:orientation:)`
before rendering. This prevents an unattached reference image view from reselecting a catalog variant
using ambient traits. The hosted moon's traits and resolved image are checked against that reference
separately from its rendered pixels. Pixel failures report the style, maximum channel error and the
first pixel outside tolerance (x/y, RGBA channel, actual and expected bytes).

The orchestrator reports all `AppTests` (including the reference meta-test) and `WindowTests` pass
on all seven D1c devices, and `make duo` passes. The reference meta-test uses the host window's scale,
checks both appearances under opposite ambient traits and confirms their pixels differ. Its diagnostic
fixture checks first-pixel coordinates and maximum-error reporting independently.

Fix round 4 preserves the orchestrator's dependency correction in `project.yml`: hosted `AppTests`
depends only on `ChronoFlow`, with `TEST_HOST` / `BUNDLE_LOADER` resolving the package symbols already
in the app. Linking DesignSystem and Launch into the test bundle again duplicated the package resource
accessors and crashed package test processes with `unable to find bundle named ChronoFlowKit_DesignSystem`.
The trap is recorded in `AGENTS.md`. A host regression guard rejects duplicate dependencies or a missing
bundle loader; both failure mutations were verified without changing the source configuration.

Run the generated handoff script from the repo root:

```sh
sh build/commits/simulators.sh
```

It invokes the committed runner, which can also be run directly:

```sh
python3 -I Scripts/launch-simulators.py
```

The runner executes `make generate`, cleans the build folder, then resolves each D1c device by type
and runtime (Duo on iPhone19-4). For each device it deletes the installed app if present and restarts
the simulator to invalidate the launch cache, then runs the hosted, window and DesignSystem suites:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
  -destination "platform=iOS Simulator,id=$device" \
  -only-testing:AppTests -only-testing:AppUITests/WindowTests -only-testing:DesignSystemTests test
```

It continues after failed tests, missing devices or preparation errors and reports PASS/FAIL for every
device. It always attempts the final `make check` and `make duo` after the matrix and exits nonzero
if any step failed. Generation failure stops before simulator work. Host fixtures verify continuation,
aggregate status, runtime/type filtering, first-available selection, cache clearing, already booted
simulators and missing apps. No real simulator command runs in those fixture tests.

This checks an instantiated storyboard. The system launch screen itself is a cached snapshot;
screen-recorded last-system-frame/first-app-frame verification remains in Phase 8.

Phase 2 task 1 host verification (2026-11-06, fix round 4): `make generate`, `make lint`,
`make launch-resources-check` (4 resource tests and 8 runner tests), `make generators-check`
(6 TokenGen, 6 Python font/cache, 3 AssetGen tests), plist lint and `git diff --check` passed.
All hosted tests pass a direct Swift 6 type-check against the installed simulator SDK targeting iOS 17.0;
this does not run UIKit or replace the matrix commands above. Full `make check` remains for the orchestrator.

`LaunchFrameView(frame:traits:)` draws the generated skyTop and natural-size moon with the same
superview centring constraints as the storyboard. UIKit lays out the intrinsic image at display scale;
the hosted resize test checks that its origin is on the pixel grid, including odd pixel dimensions.
The supplied scene traits capture the launch appearance; the view keeps that appearance while the
underlying window changes. The frame is reusable by the overlay and Reduce Motion path in Phase 3b;
no scene-connection or animation code is introduced in Phase 2.

`LaunchFrameParityTests` renders both the app storyboard and the package-backed frame into 8-bit
Display P3 buffers at the running window's scale. Every channel of every pixel must differ by no
more than 2 bytes (2/255); alpha must be opaque and the moon must appear in the rendered buffer.
Both frame views are hosted in windows, so neither has the unattached-reference trait trap. Each
moon's resolved image and rendered pixels are also compared independently with the explicitly
resolved main-bundle asset, so matching wrong appearances cannot pass whole-frame parity alone.
Whole-frame and moon comparisons share the style and first-pixel diagnostics above.
Further tests exercise resizing, asymmetric insets, accessibility text size, captured appearance and
an animation-free layer tree without masks, filters or shadows. `LaunchImagesTests` checks natural
size, image scale and bitmap dimensions in both appearances at the running device's scale. Simulator
builds retain only that scale (`actool --filter-for-thinning-device-configuration`), so requesting both
2× and 3× in one process fails even though the source assets contain both. The package test reads
`UIScreen.main.scale` because a package runner may have no connected scene. The matrix runner now runs
DesignSystemTests on every device, exercising 2× on SE and 3× on the other devices. Generator host tests
continue to verify every uncompiled 2×/3× source PNG in both appearances. The revised package image test
needs execution outside this sandbox.

Phase 2 task 2 host verification (2026-11-06, fix round 4):

- Host SwiftPM suite with `--disable-sandbox`, repo-local scratch/cache/config/security/temp paths
  and `--triple arm64-apple-macosx14.0`: 11 tests passed. UIKit-specific tests are excluded on macOS.
- Direct compilation of DesignSystem and Launch and type-check of all hosted AppTests and the UIKit
  asset test against the installed simulator SDK targeting iOS 17.0: passed. Only D11's existing
  CoreText deprecation warning remains.

There are no Phase 2 OQ defaults to assume and no undesigned states to defer. Package simulator tests,
full `make check` and the updated D1c matrix runner remain for the orchestrator; the cached system-frame
recording remains in Phase 8. No physical-device task belongs to this phase.

## Phase 3a pure timeline — 6 November 2026

All six implementation tasks are complete. The app still uses the Phase 2 shell; scene playback,
Core Animation presentation-layer comparison and overlay wiring belong to Phase 3b.

`CubicBezier`, `MoonTarget`, `FlightPath`, `LaunchTimeline`, tracks and sampled values are pure Sendable
values. The UI target's default MainActor isolation does not apply to these launch value types.
Track `keyTimes` are absolute **seconds from t0**, including explicit opening holds. The Phase 3b
adapter must normalize them for CA, retain t0 as the animation begin time, and use one animation key
per layer/key path. Rebuilding an ending preserves the opening keys and replaces any earlier ending;
status remains independent of the ending. Moon position is an absolute window-space centre, with its
opening lift already included, so the adapter must not add a second translation.

The dot source track repeats from t0, with `replicaCount = 3` and `replicaDelay = 0.2` for the live
replicator. `sample(at:)` also returns `LayerValues.replicaOpacities`, in source/second/third order,
for rendering model snapshots of the three instances. They include the phase delay, even when the
status fade is committed late. Reduce Motion returns three constant 1.0 values and no repeating track.
Status visibility is a parent opacity; it stays at 1 after its fade while the container hands off.

The flight cubic's 1024-entry arc-length table gives length about 505.789 pt and apex (195, 512.5)
on the board fixture. Its 128 moving position samples include the exact 3% fraction knot at 560 ms;
the timeline adds one initial hold key at 0. The x controls scale with window width; all y coordinates
are bottom-anchored. Only the test fixture uses 390 × 844 as a window size.

The host rendering spike found cubic `CAShapeLayer.strokeEnd` trimming drift: at fraction 0.25 the
rendered tip was around x = 82, versus the arc-length reference x = 75.605. Although
[Apple documents linear interpretation along path length](https://developer.apple.com/documentation/quartzcore/cashapelayer/strokestart),
that cubic rendition did not meet the required plane/tip alignment. `FlightPath.path` therefore uses
the spec's sampled-polyline fallback, through the same 128 vertices as the plane. Numerical tests
compare the plane with both the original arc-length reference and the polyline's length-based tip
every 10 ms within 0.02 pt. A separate rendered shape-layer test checks pixels 1 pt before and after
the tip every 10 ms where visible. This passes on the host; the same test is included in the iOS
matrix. Flight endpoints extend 10 pt beyond the window by design and will be clipped by the container.

`MoonTarget.fallback` returns the glyph's 28 pt frame, rather than the 288 pt glow bitmap frame.
It centres the glyph vertically in `max(28, rowHeight)`. `contentBounds` applies top, left, bottom
and right safe insets: top `max(safeTop + 16, 64)`, sides `safeLeft/Right + 24`, bottom
`max(safeBottom, 40)`. Extra row height moves the target down; right/bottom insets limit the content
area without moving the top-leading row. Hosted tests use each running simulator's actual window
and safe areas, plus asymmetric additions, including Duo's side rail. Additional pure short/wide
fixtures exercise arbitrary sizes; they are not stored device-dimension assumptions.

Defaults assumed, recorded on the corresponding tasks (the OQ table remains open):

- OQ 6: Reduce Motion dots hold at 1.0, fade uses ease-out, no flying-moon cross-fade, stars stay
  as drawn during the dissolve. The actual star surface belongs to Phase 3b/5.
- OQ 7: a late Welcome ending starts at resolution, with W = max(1600 ms, resolution time).
- OQ 10: the fallback uses the spec's RN safe-area padding rule; Welcome's text scaling is Phase 5.
- OQ 11: RN width-scaled x controls and bottom anchoring, portrait iPhones including Duo.

Host verification for the final Phase 3a tree:

- `make format`, `make lint`: passed.
- Host package SwiftPM: **38 tests passed**, including 27 new pure timeline/geometry tests.
  UIKit-only asset, snapshot and hosted-window tests require the simulator and are not part of this count.
- `make generators-check`: passed (6 TokenGen, 6 Python font/cache, 3 AssetGen tests), with generated
  outputs unchanged.
- `make launch-resources-check`: passed (4 resource tests, 11 matrix-runner fixture tests).
- Direct Swift 6 module compilation for AppCore, DesignSystem and Launch and type-checking all
  AppTests, AppCoreTests and LaunchTests against `arm64-apple-ios17.0-simulator`: passed.
  This invokes swiftc, not xcodebuild, and does not execute UIKit tests. D11's existing CoreText
  registration deprecation is the only warning.
- `git diff --check`: passed. Six atomic patches are replayed with `git apply --index` against HEAD
  and checked against the final source tree byte for byte, including executable modes.

Reproduce the host package run without writing caches outside the repo:

```sh
mkdir -p build/tmp build/SwiftPMHome
TMPDIR="$PWD/build/tmp" CFFIXED_USER_HOME="$PWD/build/SwiftPMHome" \
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" \
swift test --disable-sandbox --package-path Packages/ChronoFlowKit \
  --scratch-path build/Phase3aHost --cache-path "$PWD/build/SwiftPMCache" \
  --config-path "$PWD/build/SwiftPMConfig" --security-path "$PWD/build/SwiftPMSecurity" \
  --triple arm64-apple-macosx14.0
```

The orchestrator must run the simulator matrix and complete `make check` outside the sandbox:

```sh
sh build/commits/simulators.sh
```

The wrapper invokes the committed runner, so it can also be run directly:

```sh
python3 -I Scripts/launch-simulators.py --timeline
```

It runs `make generate`, cleans the build folder, dynamically resolves all seven D1c device types
and runtimes, clears the launch cache as in Phase 2, and executes this command per resolved device:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
  -destination "platform=iOS Simulator,id=$device" \
  -only-testing:AppTests -only-testing:AppUITests/WindowTests \
  -only-testing:DesignSystemTests -only-testing:AppCoreTests -only-testing:LaunchTests test
```

It continues past missing devices, preparation and test failures, reports PASS/FAIL per device,
then attempts **both** final commands, aggregating failures into its exit status:

```sh
make check
make duo
```

Duo is resolved only on `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`; the regular
27.2 runtime is never a substitute. The runner's fixtures verify the Phase 3a suite selection,
continuation, aggregate failure status and Duo runtime filtering. As before, generation failure
stops before simulator work. Each asset test uses the running device's own displayScale, and hosted
AppTests still depends only on ChronoFlow with TEST_HOST/BUNDLE_LOADER.

Simulator execution and full `make check` are pending for the orchestrator. No physical-device or
Apple-team-dependent task belongs to Phase 3a, and no undesigned state was introduced or deferred.
The presentation-layer solver comparison remains in Phase 3b; snapshot approval remains in Phase 3c.
Logs from host verification are in ignored `build/phase3a-*.log`.
