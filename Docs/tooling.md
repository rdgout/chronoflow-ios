# Tooling and verification — 5 November 2026

Toolchain: Xcode 27.2 (27B52), Apple Swift 6.4.2, XcodeGen 2.46.0 at `/opt/homebrew/bin/xcodegen`.
The app and package use Swift 6 language mode and an iOS 17.0 deployment target. UI modules default to
MainActor; AppCore is nonisolated.

## Commands

`Scripts/ci.sh` runs `make generate check`. The 2026-11-06 test-speed decision supersedes the runner
recipes in the dated phase history below. No phase or visual/device acceptance gate is closed by this tooling work.

| Command | Selection |
|---|---|
| `make check` | Lint, generators/host fixtures, SwiftPM host tests, then one combined 17e Debug run and isolated ReadinessRelease logic |
| `make host-tests` | Portable package tests on the Mac with repo-local SwiftPM caches; no simulator |
| `make test` / `make snapshots` | Individual 17e subsets; each builds Debug once |
| `make matrix` / `python3 -I Scripts/launch-simulators.py --welcome` | All seven D1c destinations; matrix suites everywhere, logic/Release once on 17e |
| `make duo` | Matrix suites on Duo, resolved by type and its separate runtime |
| `make targeted DEVICES="se duo" ONLY="AppTests/WelcomeSnapshotTests"` | Explicit target/suite/method selectors on selected aliases, build once per needed configuration |
| `make targeted DEVICES="se duo" ONLY="AppTests/WelcomeSnapshotTests/frozenIntro" REUSE_BUILD=1` | Same runner, reuse unchanged build-for-testing products |

Aliases are `se`, `17e`, `17`, `air`, `18pro`, `18promax`, `duo`. Resolution uses device type and runtime;
Duo requires `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`. No UDID/name/OS shortcut is stored.
`make generate` creates the ignored project and copies the committed package resolver lockfile. Regenerate
when project/package manifests change. Tests pin en/US. All builds use `-onlyUsePackageVersionsFromResolvedFile`
and `build/DerivedData`; missing package pins fail. Builds remain ad-hoc signed for hosted Keychain tests.

The runner builds Debug/ChronoFlow and, when selected, Release/ReadinessRelease sequentially with
`build-for-testing -destination generic/platform=iOS Simulator`. Only ReadinessRelease gets
`ENABLE_TESTABILITY=YES`. A bounded thread pool then launches a separate `test-without-building` subprocess
per device/configuration. `SIM_CONCURRENCY=4` is the default (allowed 1–4). A device owns its entire
record/compare sequence; Xcode test-worker parallelism is disabled to avoid clones sharing snapshot filenames
or appearance-changing UI tests. Duo's runtime works in the same pool. There is no matrix clean or trailing
`make check`/`make duo` rerun: the selected matrix already includes their test coverage. `Perf` remains separate.

Before each device job the runner boots it only if needed, waits for boot completion, and uninstalls the
app if present. Tests currently need no erase. A changed launch storyboard still requires the manual
clean/delete/restart cache procedure in AGENTS.md. The ordinary matrix never shuts down/reboots a booted device.

Results go to `build/test-results/<alias>/{prepare.log,record.log,record.xcresult,Debug-compare.log,Debug-compare.xcresult,Release-compare.log,Release-compare.xcresult}`
for the passes selected on that device; build logs are under `build/test-results/build/`. Repeated runs replace
that pass's result bundle/log. The runner reads xcresult test cases, prints one PASS/FAIL line per device and
selected suite, includes failing test identifiers, and returns nonzero on device/build/preparation/test/report
failure. A missing or empty test result is a failure. Failed Debug runs do not prevent Release or other devices.

`SUITES` in `Scripts/launch-simulators.py` is the scheduling table. Host discovery fails if a SwiftPM/Xcode test
target or suite is absent or duplicated. Matrix suites use the running window, safe areas, display scale, pixels,
scrolling or accessibility audits. Pure timeline, coordinator, readiness, session, routes, catalogs and fixed-fixture
unit tests run once on 17e except **all AppCore and LocalStore suites**, which are classified `host` and run on the Mac through `make host-tests` / `make check`. The seven-device matrix runs only when the user requests it (2026-11-06 override). DesignSystem's running-scale image checks remain matrix suites; its other unit tests
are logic. Perf is explicitly classified but excluded. Targeted selectors intentionally run on every requested
device, including logic when diagnosing a specific device. The compatibility flags `--timeline`, `--scene`,
`--readiness` and `--welcome` select the classified full matrix; `--snapshots` selects launch snapshots, and
`--snapshots --scene` selects the full matrix.

Snapshot recording stays opt-in: `SNAPSHOT_RECORD=1` records Welcome, `launch` records launch, `all` records both
with `--welcome`; `--snapshots` records launch. Only snapshot suites receive `TEST_RUNNER_SNAPSHOT_RECORD=1`;
comparison/build/preparation processes clear both record flags. Each concurrent device has a distinct simulator
model in the PNG filename; aliases are deduplicated and tests never run concurrent workers on the same model.

One profile catalog, `Packages/ChronoFlowKit/Tests/SnapshotSupport/profiles.json`, controls Swift capture and host
coverage checks. Full coverage stays on SE/17e/Duo/Pro Max. On 17/Air/18 Pro, Welcome keeps large/xxLarge in
both appearances/languages, type/layout loops use those sizes, frozen intro keeps 2700/3300 ms, and launch keeps
ready-0/ready-1400/slow-2600/welcome-2400/reduceMotion-0. This leaves 160 Welcome and 118 launch references.
72 obsolete images are removed; every retained PNG is byte-identical to HEAD. Existing launch images cover English
at large; localized status geometry now checks en/nl × large/xxLarge × both appearances on every device. Adding
new Dutch/xxLarge launch PNGs would require recording and remains open under the explicit no-re-record constraint.
No physical dimensions determine the profile. Unknown simulator models fail until assigned a profile.

Welcome comparison now encodes the capture once and decodes both immutable PNG inputs through the same ImageIO
sRGB RGBA8 path. Dimensions and every channel must match exactly; metadata/compression differences are ignored.
Host tests cover different PNG metadata/encodings and a one-channel mutation. The previous verifier already
compared pixels; different PNG bytes alone cannot be the SE cause. Without the two supplied recordings and UIKit
execution, the exact capture-state versus representation cause remains unproven. The regression below logs the
memory-versus-PNG channel count and writes fresh/warm PNGs under `build/test-results/intro-order/<model>/`.
It runs a fresh hosted process and a second process that executes all other Welcome suite tests before capturing
the same 2700 ms frame, compares both through `verifyWelcomeSnapshot`, and checks the retained baseline.
The committed in-suite reference is never replaced. Separate order-fresh/order-warm logs and xcresults are retained.

Measure outside Codex's sandbox, from the repo root (recording explicitly disabled):

```sh
make generate
SNAPSHOT_RECORD=0 /usr/bin/time -p make check
SNAPSHOT_RECORD=0 SIM_CONCURRENCY=4 /usr/bin/time -p make matrix
SNAPSHOT_RECORD=0 /usr/bin/time -p make targeted DEVICES="se duo" ONLY="AppTests/WelcomeSnapshotTests/frozenIntro" REUSE_BUILD=1
SNAPSHOT_RECORD=0 python3 -I Scripts/launch-simulators.py --no-generate --devices se --reuse-build --intro-order-check
SNAPSHOT_RECORD=0 make targeted DEVICES="se" ONLY="AppTests/WelcomeSnapshotTests" REUSE_BUILD=1
SNAPSHOT_RECORD=0 make duo
```

The first targeted command measures the post-build path; remove `REUSE_BUILD=1` after any source/project change.
Targets are full matrix ≤10 min, check ≤5 min and targeted ≤3 min after build; no simulator timing is claimed here.
Host validation: 85 SwiftPM tests, 20 runner/profile fixtures, nine resource checks, generator freshness with
seven TokenGen, six font/cache and three AssetGen tests, strict Swift formatting and XcodeGen generation passed.
Direct Swift 6/MainActor iOS 17 compilation/type-checking passed; these checks do not run UIKit. Root-cause proof,
simulator comparison and all pre-existing visual/physical-device checks stay open. No OQ default is newly assumed.

Clean-clone generator/network prerequisites are unchanged: SwiftPM fetches the pinned dependencies; font tooling
uses fonttools 4.60.1/brotli 1.1.0 and pinned Google Fonts sources, with SHA-256 cache verification. Repo-local
SwiftPM caches, `build/fonttools-venv`, `build/FontSources` and `build/pip-cache` permit warm offline runs.
`Scripts/swiftpm.sh` uses `--disable-sandbox`, repo-local scratch/cache/config/security/temp paths and CFFIXED_USER_HOME,
without changing HOME. The reproducible host SwiftPM invocation remains in the Phase 3a section below.

`make perf` keeps its isolated Release scheme; no physical-device timing is performed by this runner. Device
signing uses optional ignored `Config/Local.xcconfig`; simulator signing needs no Apple team. The historical
verification sections below retain the reported results for their dated trees, not results for this change.

## Phase 0 verified results

The orchestrator ran the following on 5 November 2026 with
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
  used `--disable-sandbox`, repo-local caches, and
  `--triple arm64-apple-macosx14.0`. This is additional compile/test evidence, not simulator validation.
- Catalog guard proof: inserted `Phase 0 catalog guard probe` into `App/InfoPlist.xcstrings` with only
  an English value. `CatalogTests` failed with exit 1 and
  `Missing nl value for 'Phase 0 catalog guard probe'`. Restored the original catalog bytes; the same
  test passed with exit 0. The probe is absent from the committed catalogs.


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
checks the 55% / 60% sky mid stops and the press rules. Dot parsing and generated pattern constants
were removed after the user dropped the pattern on 2026-11-06.
All 18 sRGB hex values and all 22 reference sky samples match the plan exactly. Display P3 values
match the table within its stated tolerance. Neither a source conflict nor a missing optical-size
axis was found.

Each sky has 17 stops, including the exact mid stop. Segment interpolation is checked at 1001 points
with a 0.25/255 error budget before rasterization. A separate host Core Animation test compares its
8-bit P3 raster against rounded 8-bit true-OKLab reference samples to within one byte per channel.
The generated report contains the full-precision palette. PatternDots and its tile tests are removed;
both splash and Welcome now draw only CfSky behind their content.

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
390 × 844 or uses a phone's fixed safe-area values. The four historical snapshot fixtures combined the sky, pattern-dots and moon. All four and their
fixture were removed with the no-pattern decision; unit coverage of CfSky, MoonShape and PressStyle remains.


`Scripts/swiftpm.sh` supplies `--disable-sandbox`, repo-local scratch/cache/config/security directories,
a repo-local temporary directory and `CFFIXED_USER_HOME` for Foundation's cache location. It leaves
`HOME` unchanged. Font tooling uses a repo-local venv, temporary directory and pip cache. Use the
standard SwiftPM build system; the deprecated native build system is not part of this workflow.

UIKit typography requires a nonoptional `UITraitCollection` argument; callers pass their view's traits.
ContentSizeCap clamps explicit categories at xxLarge before metrics are evaluated. On iOS 27.2,
the ambient category read by the previous nil-traits
path did not follow `performAsCurrent` for an accessibility category, returning 16 pt instead of 45 pt.
There is no ambient category lookup or default argument now. An explicit `.large` returns the base font;
other categories through xxLarge are passed to `UIFontMetrics`. The splash wordmark stays fixed;
the status uses capped metrics. Skipping metrics
at `.large` keeps the exact design size and avoids introducing screen-scale-dependent font rounding.
A host probe on this toolchain also reproduced a Swift Testing
mixed-type equality failure: ordinary `CGFloat(32) == Double(32)` is true, while the same expression
inside `#expect` fails. Typography assertions therefore compare two `CGFloat` values, retaining exact
equality without a tolerance. Tests check all eight styles at 2× and 3× with explicit small, large and
accessibilityExtraExtraExtraLarge categories. Scaled sizes must equal the appropriate UIKit text-style
metrics and grow/shrink as expected; default and splash sizes must exactly match the design.

## Phase 1 verification

The orchestrator verified the committed Phase 1 state on
2026-11-05 with Xcode 27.2:

- `make generate`: passed.
- `make snapshots` on iPhone 17e / iOS 27.2: passed. Four primitive baselines (light/dark at
  240 and 560 pt widths) were recorded and visually approved under
  `Packages/ChronoFlowKit/Tests/DesignSystemTests/__Snapshots__/PrimitiveSnapshotTests/`.
- `make check` on iPhone 17e / iOS 27.2: passed, including the updated explicit-traits UIKit font
  tests and the approved primitive snapshots. The earlier nil-traits failure is resolved.
- `make duo`: passed on iPhone Duo's iPhone19-4 iOS 27.2 runtime (24B91016s).
- `make tokens fonts assets`: reproduced the committed generated outputs with no diff.

Those four approved dot-bearing baselines were subsequently removed with the user's 2026-11-06 no-pattern decision. The implementation environment verifies
wordmark alpha coverage against an explicitly unsmoothed render at both scales in both themes,
advance-box centring within 0.01 pt, the sRGB palette round-trip bound, board-derived moon geometry,
and font-cache recovery. `make lint`, `make generators-check` (6 TokenGen tests, 3 AssetGen tests
covering all 8 PNG variants and the added regressions, 6 Python font/cache tests), regeneration and
all 11 host package tests pass. Repeating regeneration preserves every generated byte. Host tests
exclude the UIKit font and primitive snapshot functions; they do not replace simulator validation.
Mutation probes regenerated wordmarks with smoothing enabled and with left-aligned advances;
the alpha-coverage and midpoint assertions respectively rejected them. Both probes were restored.

For the revised tree, run:

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
Regeneration should leave the checkout clean:

```sh
make tokens fonts assets
git diff --exit-code
```


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

The orchestrator verified Phase 2 on **2026-11-06**: the launch matrix passed on all seven
D1c devices (iPhone SE 3rd gen, 17e, 17, Air, 18 Pro, 18 Pro Max and iPhone Duo), and
`make check` and `make duo` passed. This includes the hosted storyboard/frame tests,
WindowTests and DesignSystemTests at each running device's own display scale.

Hosted `AppTests` depends only on `ChronoFlow`, with `TEST_HOST` / `BUNDLE_LOADER` resolving
the package symbols already in the app. Linking package products into the hosted bundle again
duplicates resource accessors and can crash package test processes. A host regression guard
rejects duplicate dependencies or a missing bundle loader. The trap is recorded in `AGENTS.md`.

Run the committed matrix runner from the repo root:

```sh
python3 -I Scripts/launch-simulators.py
```

The runner executes `make generate`, cleans the build folder, then resolves each D1c device by
type and runtime (Duo on iPhone19-4). For each device it deletes the installed app if present and
restarts the simulator to invalidate the launch cache, then runs:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
  -destination "platform=iOS Simulator,id=$device" \
  -only-testing:AppTests -only-testing:AppUITests/WindowTests -only-testing:DesignSystemTests test
```

It continues after failed tests, missing devices or preparation errors and reports PASS/FAIL
for every device. It attempts both final commands, `make check` and `make duo`, and exits nonzero
if any step failed. Generation failure stops before simulator work. Host fixtures verify
continuation, aggregate status, runtime/type filtering, first-available selection, cache clearing,
already booted simulators and missing apps without executing real simulator commands.

`LaunchFrameView(frame:traits:)` draws the generated skyTop and natural-size moon with the same
superview centring as the storyboard. The supplied scene traits capture the launch appearance,
which stays fixed while the underlying window changes. UIKit lays out the intrinsic image at
display scale, including windows with odd pixel dimensions.

`LaunchFrameParityTests` renders the storyboard and package-backed frame into 8-bit Display P3
buffers at the running window's scale. Every channel must differ by no more than 2/255; alpha
must be opaque and the moon must appear. Both frames are hosted in windows. Independent image
and moon-pixel checks use the explicitly resolved main-bundle reference, with first-pixel and
maximum-error diagnostics. Further tests cover resizing, asymmetric insets, accessibility text
size, captured appearance and a tree without animations, masks, filters or shadows.

`LaunchImagesTests` checks natural size, image scale and bitmap dimensions in both appearances
at the running device's scale. Simulator builds thin compiled catalogs to that scale; the SE
matrix run exercises 2× and the other devices exercise 3×. Generator tests verify all uncompiled
source PNG variants. Host SwiftPM, generators, resource checks, plist lint, strict formatting and
direct Swift 6 compilation/type-check against the iOS 17 simulator SDK also passed.

There are no Phase 2 defaults or undesigned states to defer. The cached system launch screen's
last-frame/first-app-frame recording remains in Phase 8; the completed matrix checks an instantiated
storyboard rather than that system-owned cached snapshot.

## Phase 3a pure timeline — 6 November 2026

All six implementation tasks are complete. Scene playback, Core Animation presentation-layer
comparison and overlay wiring are covered by Phase 3b.

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
the timeline adds one initial hold key at 0. The x controls scale with window width. The user's
2026-11-06 vertical rule keeps the 844 pt composition at every height: every former `h - k` becomes
`h/2 + (422 - k)`. LaunchLayout supplies scene, timeline and path geometry; the band stretches to the
window bottom, and CfSky fills the whole window. Only the test fixture uses 390 × 844 as a window size.

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

- OQ 6: Reduce Motion dots hold at 1.0, fade uses ease-out, no flying-moon cross-fade. The user subsequently removed the splash/Welcome pattern on 2026-11-06.
- OQ 7: a late Welcome ending starts at resolution, with W = max(1600 ms, resolution time).
- OQ 10: the fallback uses the spec's RN safe-area padding rule; Welcome's text scaling is Phase 5.
- OQ 11: RN width-scaled x controls, portrait iPhones including Duo. Vertical anchoring was settled by the user on 2026-11-06: centre the board composition.

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
- `git diff --check`: passed.

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

Run the simulator matrix and complete `make check` using the committed runner:

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

The orchestrator verified Phase 3a on **2026-11-06**: all seven D1c devices, `make check` and
`make duo` passed. No physical-device or Apple-team-dependent task belongs to Phase 3a. The
presentation-layer solver comparison is covered by Phase 3b; snapshot approval belongs to Phase 3c.

## Phase 3b Core Animation scene — 6 November 2026

`LaunchScene` maps the pure timeline to a single layer tree. Its model sampler uses separate
static dots for the three replica opacities; live playback uses one CAReplicatorLayer with a
200 ms instance delay. The status text is created only after font registration and only when
requested. Both status strings use the Launch String Catalog with the specified Dutch copy.
The launch palette's white and glow alpha ramps come from TokenGen, guarded against the splash board.
No Gaussian integration runs while constructing the overlay.

The first process connection mounts the overlay before scheduling the main window on the
next run-loop turn. A process-owned `LaunchProcessState` gates later connections. Cold-start
URLs and notification request/action/payload/text are captured without routing. Both the
overlay controller and main hosting controller request a light status bar during the splash.
The overlay uses the Phase 2 frame view as its host, replacing the static moon with the layer
tree and allowing transparency for the eventual hand-off. Readiness, removal and Welcome
remain in their planned phases; an ordinary launch holds the settled opening until Phase 4.

Diagnostic arguments (milliseconds, nonnegative finite values up to 60000):

- `-cf.mode ready`: ready exit at 1500 ms.
- `-cf.mode slow`: status at 2000 ms, exit at `-cf.readyAt` (default 4600 ms).
- `-cf.mode welcome`: flight from 1600 ms to the safe-area/row-height fallback, using the captured text size.
- `-cf.freezeAt 700`: freeze the live tree at 700 ms without evaluating model samples.
- `-cf.mainThreadStall 500`: block main once at 300 ms for the device D3 proof.
- `-cf.reduceMotion`: force the static opening and motion-free ending.

All animations keep a nonzero absolute `beginTime = t0`. Consequently the paused container's
`timeOffset` is **t0 + elapsed seconds**, not elapsed seconds alone: the latter would precede
the tracks' begin times. Rebuilding while frozen preserves that same epoch and animation keys.
The hosted presentation test compares every tracked property every 100 ms from 0 to 3200 ms,
for ready, slow, welcome and Reduce Motion, in both appearances. Position tolerance is 0.5 pt
(including pixel alignment); scalar tolerance is 0.003. Separate light/dark XCUITests set device
appearance, terminate the app, return to SpringBoard, and poll the reported appearance for up to
10 seconds before launch. Async teardown terminates the app and waits for appearance restoration
before the next test. Each frozen 700 ms screenshot must match its own independently rendered model
and clearly differ from the opposite appearance. Both references and the live screenshot are retained
as attachments. It excludes the system status bar; tolerance remains a mean
channel error of 1/255 with at most 0.5% of channels differing by more than 8/255. The same limits
apply away from reference edges (adjacent channel change >8, dilated by one pixel). The best moon
alignment shift must be ≤0.5 pt, and the moon region must retain mean error ≤1/255, including away
from edges. No alignment is applied to the compared images. Synthetic 2×/3×
fixtures and mutations of the real sampled moon verify rejection of a 1 pt offset and a 20% opacity
error. No encoded image bytes are compared. Approved launch image baselines belong to Phase 3c.

Sampled transforms retain Z = 1: scaling Z makes an otherwise planar transform non-affine,
which `render(in:)` ignores. Hosted tests check the rendered moon width and affine container during
lift-away. The live tracks keep their specified scale key paths. Anchor arithmetic uses a 1e-9 pt
geometry tolerance for floating-point residuals; storyboard pixel parity retains its 2/255 limit.

The CA timing comparison retains position and interior-opacity checks with a 0.0005 tolerance for
CA's duration-dependent solver epsilon at a 1 s duration. An independent host bisection reference
checks all four presets at 1001 progress values to 0.0001, with intro(0.95) = 0.9997243836889174
checked to 1e-12. Production solver precision and screenshot tolerances are unchanged.

Run the committed runner from a clean clone:

```sh
python3 -I Scripts/launch-simulators.py --scene
```

The runner cleans and resolves all seven D1c devices by type/runtime, including Duo on iPhone19-4,
clears their launch caches, and runs this command for each resolved destination:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
  -destination "platform=iOS Simulator,id=$device" \
  -only-testing:AppTests -only-testing:AppUITests/WindowTests \
  -only-testing:DesignSystemTests -only-testing:AppCoreTests -only-testing:LaunchTests \
  -only-testing:AppUITests/LaunchSceneTests test
```

It continues past failures, reports PASS/FAIL per device and then attempts both `make check`
and `make duo`. The Duo target now also includes the launch scene UI test. AppTests still
links only the app through TEST_HOST/BUNDLE_LOADER. The separate UI-test runner links Launch
and DesignSystem to render its independent model reference; it does not inject duplicate
package code into the hosted unit-test bundle. Assets use only the current device's scale.

Host verification uses repo-local caches and the same SwiftPM invocation as Phase 3a, with
`--scratch-path build/Phase3bHost`: **47 tests pass**. The portable screenshot-comparison XCTest
also passes on the host, exercising 2×/3× offsets, opacity and one-byte dithering. `make format lint`,
`make generators-check` (6 TokenGen, 6 Python font/cache, 3 AssetGen tests) and
`make launch-resources-check` (4 resource tests, 14 runner fixtures) pass. Direct Swift 6
module compilation and type-check of the app, all hosted tests, AppCoreTests, LaunchTests
and AppUITests against `arm64-apple-ios17.0-simulator` pass. These commands invoke swiftc,
not xcodebuild, and do not run UIKit. The existing D11 CoreText deprecation remains.

The orchestrator verified Phase 3b on **2026-11-06**: all seven D1c devices, `make check` and
`make duo` passed. The device D3 proof remains open in `Docs/perf/2026-11-06-d3-spike.md`; no performance result is claimed.
Defaults carried into this phase: OQ 6 status dots/fade/no moon cross-fade (background pattern subsequently removed by the user);
OQ 10 RN fallback padding/row height; OQ 11 width-scaled x controls (vertical composition subsequently settled);
OQ 14 proposed device budget. There are no additional undesigned screens or states.

## Phase 3c splash snapshots

Compare the eleven Phase 3c frames in light and dark on every D1c simulator:

```sh
python3 -I Scripts/launch-simulators.py --snapshots
```

The runner resolves each device by type/runtime (Duo uses iPhone19-4), continues after failures,
reports PASS/FAIL per device, then attempts both `make check` and `make duo`. Add `--scene` to also
run hosted connection tests, window UI tests and both appearance parity UI tests in each comparison
pass. For the snapshot suite and Phase 3b review fixes together, run:

```sh
python3 -I Scripts/launch-simulators.py --snapshots --scene
```

It compares existing
baselines by default. To deliberately record before the comparison pass:

```sh
SNAPSHOT_RECORD=1 python3 -I Scripts/launch-simulators.py --snapshots
```

The record pass forwards `TEST_RUNNER_SNAPSHOT_RECORD=1` to xcodebuild, which exposes it to tests as
`SNAPSHOT_RECORD`. Comparison and final checks clear both variables. Missing baselines fail without
creating a reference. Per resolved device, comparison runs:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
  -destination "platform=iOS Simulator,id=$device" \
  -testLanguage en -testRegion US -only-testing:LaunchTests test
```

`make test` and `make snapshots` also pin en/US. Slow snapshot text resolves the Launch catalog's
explicit `en` localization independently of runner flags. Phase 3c has no Dutch snapshot requirement.
PNG names include the simulator model, window dimensions, own display scale, appearance, mode and
time. The sampler sets model values and static dot replicas, then renders through a transparent
parent so exit scale and opacity are included. Welcome content snapshots belong to Phase 5.

Geometry checks use the running window and all four safe-area insets, with asymmetric and side-only
additional insets. A zero top inset is valid on SE and Duo. Visible moon glyph, wordmark and status ink
stay fully inside the window and horizontal safe area. Per the user's 2026-11-06 composition decision,
the sun may extend below the window like a horizon on short screens; its top and sides remain inside,
with at least one third of its height visible. Host regressions exercise every D1c size/sample and
reject side/top overflow and a sun with insufficient visible height. The path's designed 10 pt bleed is
preserved and checked for vertical bounds and container clipping; full safe-area containment lacks a
design/default and stays open. Host tests assert the frame list, ending times, safe-area landing, all
154 PNGs' coverage/dimensions and S1: status top 518 is below apex 512.5 at height 844. With the
user's 2026-11-06 composition decision, height 874 keeps that relation: status top 533, apex 527.5.
The status text no longer crosses the path; its top remains 5.5 pt below the apex.

The orchestrator verified Phase 3c and the Phase 3b review fixes on **2026-11-06**:
all seven D1c devices passed snapshot comparison, hosted tests and both light/dark appearance UI
tests. `make check` and `make duo` passed. This includes notification-payload validation, the
post-flush opening accessibility label, captured overlay appearance and appearance synchronization.

PNG approval and side-by-side board review remain open because `_design/frames/` is absent.
The user settled the short-screen collision on 2026-11-06: keep the 844 pt board's vertical
relationships at every height while preserving the window-centred moon. SE and Duo now have the
board's glyph/wordmark/status clearances from the sun disc and path apex; ordinary assertions
replace the height-scoped known issues. At 844/874 the status starts 5.5 pt below the apex.
Geometry and timeline checks cover the revised rule; simulator and visual acceptance remain open.
During launch recording, unchanged 844 pt samples are compared against their existing references,
including frame 0, rather than overwritten. The no-pattern decision changes only its two
Welcome-exit samples (1950/2400), which may be recorded. Every non-844 device needs replacement
launch references for the changed composition.
The physical-device D3 proof remains open (needs a device; open). Snapshot work precedes that proof
by user direction; repeat review if it changes the layer tree. No device performance result is claimed.

## Phase 4 readiness and hand-off

Readiness starts after the first overlay flush. The coordinator uses that commit's media epoch,
resolves the session, then reads the gate and stored-data updates independently. The root mounts
its resolved route on its first frame. Stored-data updates support false → true during a first
load; the eight-second fallback remains scoped to the launch source. Window teardown is driven
by the container fade's CATransaction completion, isolated from the repeating status dots.

The native Keychain service is `net.chronoflow.app.native`, account `session`, with JSON keys
`token` and `accountId`. A malformed value is deleted and resolves signed out. No RN migration
or URL scheme is enabled. Release always resolves signed out. It parses `-cf.mode ready` and a validated
`-cf.mainThreadStall` for the physical-device D3 proof; slow/Welcome modes, freeze, readyAt and
readiness overrides are Debug-only. Debug destinations use route-name placeholders; Release
renders no placeholder text. Welcome content and anchor publication belong to Phase 5.

Debug readiness controls:

- `-cf.session in|out|never` (default: read the native Keychain).
- `-cf.gate app|terms|verify|walkthrough` (default: `app`).
- `-cf.stored yes|no|never` (default: `yes`). `never` leaves the stored-data fact unknown.
- `-cf.readyDelay 3.5` (seconds from the overlay commit, default: zero). With `stored no`,
  emit false immediately, then true at that deadline. A delay above eight seconds exercises
  the forced first-load path while preserving the slow status.

Existing `-cf.mode` and `-cf.freezeAt` diagnostics bypass readiness in Debug to retain frozen
scene comparisons. Release supports only ready playback and the main-thread stall; the isolated
Release suite asserts both the enabled diagnostic flags and signed-out readiness restriction.
The opening-window UI tests freeze at zero rather than racing the hand-off.

Run all Phase 4 hosted, readiness UI, existing window/parity, AppCore, Launch and DesignSystem
checks on all seven D1c devices:

```sh
python3 -I Scripts/launch-simulators.py --readiness
```

The runner prepares each device by type/runtime and pins `-testLanguage en -testRegion US`.
It attempts both the Debug suites and the Release override-isolation hosted test per device,
continues after failures, reports PASS/FAIL per device, then attempts both `make check` and `make duo`.
Duo remains on its iPhone19-4 runtime. `make duo` now includes the readiness UI suite and en/US.
The hosted Keychain round-trip uses a unique test service. AppTests still links only ChronoFlow
through TEST_HOST/BUNDLE_LOADER; package host tests use an in-memory SessionStore.

The dedicated `ReadinessRelease` scheme lists only AppTests. Its command enables testability for
the hosted `@testable import ChronoFlow`; the `Perf` scheme keeps its normal Release settings.
Package test bundles run only in Debug, where their `@testable` imports are supported. Selecting
a test with `-only-testing` does not remove other test targets from a scheme's build graph.

For one resolved simulator destination:

```sh
make generate
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow \
  -destination "platform=iOS Simulator,id=$device" -testLanguage en -testRegion US \
  -only-testing:AppTests -only-testing:AppCoreTests -only-testing:LaunchTests \
  -only-testing:DesignSystemTests -only-testing:AppUITests/WindowTests \
  -only-testing:AppUITests/LaunchSceneTests -only-testing:AppUITests/ReadinessTests test
make check
make duo
```

The orchestrator verified Phase 4 on **2026-11-06**: all seven D1c devices passed the Debug
suites plus the isolated Release check, and `make check` and `make duo` passed. OQ confirmations,
the physical-device D3 proof, status-bar observation and performance measurements remain open.

Simulator signing is ad-hoc for hosted Keychain access. The stub implements the async stored-data
stream requirement explicitly for both concrete and protocol callers. Tests cover the absolute
manual-clock deadline, already-passed deadlines and cancellation. Lifetime tests drain the run loop
and scoped autorelease pools for up to two seconds, then require both objects to deallocate.
The completion path uses weak captures and clears both window/controller references, including
on disconnection during a pending exit.

The Phase 4 review adds cancellation tests that stop with two signed-in or three signed-out
sleeps still pending, require them to drain before any clock advance, and reject later callbacks.
A separate unresolved session must observe task cancellation. Release diagnostic parsing tests
cover the D3 flags while retaining signed-out readiness and Debug-only overrides. These new checks
need the revised matrix run; the dated Phase 4 results above cover the previously reviewed tree.

Validate the Release signed-out restriction separately on the pinned simulator:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ReadinessRelease -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17e,OS=27.2' -testLanguage en -testRegion US \
  ENABLE_TESTABILITY=YES -only-testing:AppTests/ReleaseReadinessTests test
```

Direct hosted-test compilation must use `-swift-version 6 -default-isolation MainActor`, with
`-D DEBUG -Onone` for Debug and `-O` for Release. Compile through SIL generation as well as
type-checking: region-isolation diagnostics can arise during SIL generation. The stored-data
test consumes the stream in one detached task so its mutable iterator never crosses actor boundaries
between reads. A sleep-registration expectation replaces yield-count polling: both concrete and
protocol calls must use the injected clock before the test advances it.

## Phase 5 Welcome, intro and moon hand-over

Welcome follows `Main.dc.html` with one plain CfSky gradient (pattern-dots removed by the user on
2026-11-06), the six English/Dutch catalog entries,
board-derived generated metrics and the existing registered fonts. The content scrolls, with
space between the heading and action groups. Padding includes all four window safe-area insets,
including Duo's side rail. The designed pills use native SwiftUI Buttons and the shared PressStyle;
they retain their drawn surfaces on iOS 26 and later. Plan my trip routes to `.guestWizard` and
Sign in to `.signIn` through Navigator.

The user settled OQ 10's scaling part on 2026-11-06: Dynamic Type is capped at xxLarge once at
RootView and on the main and overlay windows. xxxLarge and AX1–AX5 render at xxLarge; smaller sizes
scale normally. ContentSizeCap also clamps explicit Typography traits and fallback moon-row metrics.
The status layer uses the capped font and scaled line height. Final snapshots cover large and xxLarge;
hosted frame/pixel equality checks compare xxxLarge and AX5 with xxLarge in both locales and themes
on every D1c device. OQ 10 still assumes RN scrolling and padding, including asymmetric insets.
OQ 12 assumes the guest wizard destination; OQ 6 assumes no moon cross-fade. The board's stale
GuestFlight link and the designed moon stroke/glow differences remain as recorded in the plan.

The glyph publishes its global frame through MoonAnchorStore to the launch coordinator. Font
registration completes before the root measures its text. Pre-flight anchor changes rebuild the
merged moon track; after flight begins the reducer retains its committed target. Diagnostic
`-cf.mode welcome -cf.freezeAt 2300` mounts Welcome and freezes the flying moon on its measured
anchor. UI checks compare its presentation-layer centre and scale with that frame at default/AX5.
The root stays hidden from accessibility until the overlay is removed.

Intro items use W+700 and the shared launch clock, with offsets 0/100/150/300/400/450 ms, a 450 ms
intro curve and a 14 pt rise. Frozen intro snapshots cover 2400/2450/2700/3200/3300 in both languages
and appearances. A claimed intro remains active after overlay teardown; later appearances and
scene reconnects do not replay it. Reduce Motion skips the intro and press scaling. The intro
signpost ends at W+1600, after the overlay's launch/exit intervals have ended.

Run the full Phase 5 D1c matrix from the repo root, including the hosted hand-over checks,
Welcome route/landing/accessibility UI tests, existing launch comparison and readiness suites:

```sh
python3 -I Scripts/launch-simulators.py --welcome
```

For Welcome-only baseline recording followed by comparison:

```sh
SNAPSHOT_RECORD=1 python3 -I Scripts/launch-simulators.py --welcome
```

Only AppTests/WelcomeSnapshotTests and AppTests/WelcomeSnapshotGuardTests run with `SNAPSHOT_RECORD=1`.
Use `launch` for launch-only recording or `all` for both sets after the composition/no-pattern decisions:

```sh
SNAPSHOT_RECORD=launch python3 -I Scripts/launch-simulators.py --welcome
SNAPSHOT_RECORD=all python3 -I Scripts/launch-simulators.py --welcome
```

The launch record selection is LaunchTests/LaunchSnapshotTests. Each record pass stays isolated from
UI/Release checks, then comparison runs every suite with recording disabled. There are 196 planned Welcome references: 56 final screens (seven devices,
two appearances, two languages, large/xxLarge) and 140 frozen intro frames. Recording is opt-in;
missing references fail comparison. Both locales are set explicitly in the tests, independently
of the host language. All xcodebuild test commands pin `-testLanguage en -testRegion US`.

The runner resolves each D1c device by type/runtime, including Duo on iPhone19-4, continues after
failures, reports PASS/FAIL per device/pass, then attempts both `make check` and `make duo`.
Each comparison pass runs the Debug suites and isolated `ReadinessRelease` tests, attempting Release
even if Debug fails. Recording flags are cleared for both comparison configurations and final checks.
`make duo` includes Welcome snapshots and UI tests. Appearance-changing UI tests wait for
SpringBoard and the requested appearance, then restore it before the next test. Hosted AppTests
continues to depend only on ChronoFlow through TEST_HOST/BUNDLE_LOADER.

Phase 5 host verification: 40 SwiftPM tests passed; strict formatting and generator freshness/tests
passed (7 TokenGen, 6 font/cache, 3 AssetGen), as did 7 launch-resource and 26 runner-fixture tests.
Swift 6/MainActor iOS 17 compilation/type-checking passed for the modules, Debug/Release app and
hosted tests, package tests and UI tests. Debug/Release app/hosted SIL compilation also passed.
The existing D11 CoreText registration deprecation remains.

The orchestrator's **2026-11-06** Phase 5 record passes completed on all seven devices, but all
196 Welcome references were uniform white or transparent. Comparison, `make check` and `make duo`
failed. Those references have been discarded. Replacement baseline recording/comparison and visual
approval remain open. Supplied iPhone 18 Pro app screenshots show actual Welcome content in both
themes; inspection against `Main.dc.html` confirms the board's fonts and token assignments.

Welcome snapshots and capture guards run inside hosted AppTests, using ChronoFlow as TEST_HOST.
Baselines live next to those tests under AppTests/__Snapshots__. AppTests has no additional package
dependencies: its local reference helper compares decoded RGBA pixels with the PNG reference, rejects
missing references in comparison mode and records only when explicitly enabled. The package WelcomeTests
keeps its portable smoke test. make snapshots selects the hosted suites as well as the package suites.
Welcome snapshot capture uses a key, visible hosting window with explicit appearance, content
size and the device's own display scale. It lays out the window/controller and waits for measured
frames before `drawHierarchy(afterScreenUpdates: true)`. A failed, uniform or transparent capture
throws before it can be recorded. Synthetic guards reject uniform/transparent/identical captures;
independent final-screen guards require both language and appearance changes to alter the pixels
at large and xxLarge text. Asymmetric-inset geometry checks cover every Dynamic Type size.

The first accessibility run reported 144 contrast failures, nine near failures and twelve English
text-clipping failures without element details. The issue handler now prints and attaches each
issue's audit type, optional element identifier/label and compact description. It ignores only
`.contrast` on `welcome.eyebrow`, `welcome.headline`, `welcome.copy` and `welcome.signIn`, the four
confirmed identifiers. Their font weights and `skyTitle`, `dawn`, `skyCopy` and `skyCopyBackground`
assignments match the board. Contrast on wordmark, plan or any other identifier still fails. Each pair is an open
design decision in `plan.md`. The full audit selects `.all.subtracting(.dynamicType)`, matching the
user's 2026-11-06 xxLarge cap, with an exact selection assertion naming that decision. The handler
does not ignore Dynamic Type issues. Unknown/nil identifiers, combined types, clipping and all other
selected audit issues still fail; tests exercise those boundaries. Production colours stay as drawn. The second diagnostic run identified English welcome.eyebrow clipping.
The tracked label now takes its intrinsic horizontal size, retaining the board typography. Hosted
checks compare natural attributed-string dimensions through all categories; UI audits cover clipping
at xxLarge and AX5 as well as the existing audits in both appearances/languages. Accessibility
acceptance remains open until the revised matrix passes.

Previous fix-round host verification: all 79 SwiftPM tests pass (42 AppCore, 27 Launch, 7 DesignSystem,
3 Welcome), including both pending-timer cancellation cases, unresolved-session cancellation and
two portable pixel-guard tests. All 28 runner fixtures pass. Strict formatting,
generator freshness/tests (7 TokenGen, 6 font/cache, 3 AssetGen) and 7 launch-resource tests pass.
The revised SwiftUI capture and audit tests compile for the iOS 17 deployment target; UIKit execution
still requires the matrix commands above. Phase 3c's orchestrator-verified results cover the earlier
tree; rerun its assertions with these changes. The short-screen collision and 874 pt crossing were subsequently settled by the user's
2026-11-06 composition decision; revised simulator recordings and visual review remain open. The physical-device D3 proof, status-bar observation, VoiceOver/device checks and
performance measurements remain in their existing tasks (needs a device; open).

The orchestrator's second 2026-11-06 attempt rejected every Welcome capture: package tests had no
app host/render-server connection. Those captures were not recorded. The hosted capture route and
xxLarge cap must be validated before new baselines are accepted. The launch ordering test now waits
for the asynchronously mounted root instead of assuming font registration completes within 50 ms.
It freezes the overlay at zero and retains flush-before-root and reconnect assertions.

The app's AppIcon asset reuses RN's opaque 1024 px icon unchanged, as requested by the user on
2026-11-06 (OQ 18). The universal iOS slot lets Xcode derive the device sizes. Host checks require
byte identity, dimensions and no alpha/transparency; AppIconTests checks the built app's CFBundleIcons
primary name is AppIcon. Dark/tinted variants and a layered Liquid Glass icon need design assets and
remain Open. iOS derives its appearances; Debug keeps the ordinary display name by default.

Host verification for the hosted-capture/xxLarge revision: 77 package tests pass (42 AppCore,
27 Launch, 7 DesignSystem, 1 Welcome); the two portable pixel guards pass separately. Strict formatting,
7 TokenGen tests, 6 font/cache tests, 3 AssetGen tests, 9 launch-resource checks and 28 runner fixtures
pass. XcodeGen generation passes. Direct Swift 6/MainActor compilation and type-checking for the
modules, Debug/Release app and hosted tests, package tests and UI tests pass against the iOS 17 SDK
floor. Debug/Release app and hosted SIL compilation passes. These are host checks; the replacement
D1c capture, accessibility and visual acceptance results remain open until the matrix is reported.


## Phase 5 fix round 3 and user decisions — 6 November 2026

The orchestrator reports that hosted Welcome recording succeeded on all seven D1c devices. The
remaining comparison failures were the expected Dynamic Type cap audit and one intermittent dark
English 2400 ms intro mismatch on iPhone18,4. No revised matrix pass is claimed yet.

Frozen IntroItem now takes a separate sampled branch with no live task or landed-state dependency.
The sample time remains fixed; font registration completes before capture. The on-appear intro claim
and frozen subtree disable animation transactions. The first body pass already presents the fixed
sample, so the appearance claim keeps the same rendered tree instead of switching from final content. Capture waits for both the intro claim and measured frames. A regression requires unchanged
RGBA pixels, frames and no live layer animations across ten mounts at 2400 ms, clock advances and render passes
at all five frozen times, in both locales and appearances. Pixel comparison tolerance is unchanged.
The simulator run must verify that this removes the intermittent mismatch.

The board composition and no-pattern decisions update the launch references on non-844 devices and
the two 844 Welcome-exit frames; all Welcome references need replacement. Run the combined recording
command above, then compare again without recording. Board-frame export, visual approval, the four
board-contrast design decisions and physical-device checks remain open.

## Phase 5 fix round 4 — 6 November 2026

The orchestrator reports `SNAPSHOT_RECORD=all` matrix passes on iPhone 17e, 17, Air, 18 Pro and
18 Pro Max, plus a passing `make check`. SE and Duo failed the sun's old full-containment assertion;
Duo also failed the Dutch Plan my trip contrast audit in both appearances because the action was
partly below the window. `make duo` failed. These results cover the preceding tree.

The sun test now accepts the designed bottom-edge horizon while retaining horizontal safe bounds,
an inside top edge and at least one third visible height. Other elements keep full containment.
Welcome audits run at the top and again after a bounded scroll until Sign in is hittable and fully
inside the window. The second pass asserts both actions are fully visible, with the same audit
handler/types and four board-contrast pairs. Plan my trip is never a board-contrast exception.
Frame regressions reject partially visible and empty actions. The layout and colours are unchanged;
scrolling at this Dutch text length follows the existing OQ 10 default.

Host verification passed: 80 SwiftPM tests (42 AppCore, 31 Launch, 6 DesignSystem, 1 Welcome),
including both sun containment regressions; strict formatting; generator freshness/tests (7 TokenGen,
6 font/cache, 3 AssetGen); 9 launch-resource checks and 30 simulator-runner fixtures. Direct Swift 6
compilation/type-checking passed for all modules, Debug/Release app and hosted tests, package tests
and UI tests against the iOS 17 deployment floor. UIKit test execution remains with the orchestrator.

Rerun from the repo root:

```sh
SNAPSHOT_RECORD=all sh build/commits/simulators.sh
sh build/commits/simulators.sh
make check
make duo
```

The wrapper still supports `SNAPSHOT_RECORD=1` (Welcome only) and `launch` (launch only).
The full comparison, SE/Duo audits, board-reference/visual acceptance, four contrast design decisions
and existing physical-device checks remain open. No revised simulator pass is claimed.

## Phase 5 review fixes — 6 November 2026

Welcome styles with a line height smaller than the font's natural metrics now use word-wrapped,
natural-height native labels centred on exact line boxes. Ink can overflow each box without clipping;
the English board headline occupies three generated 48 pt lines (144 pt). Kerning, token colours,
the single accessible headline/header and root xxLarge scaling remain. Wordmark, eyebrow and copy
retain their SwiftUI rendering path, with a pixel-equivalence regression. Host tests cover wrapping,
Unicode and half-leading; simulator tests cover scaled pitch, ascenders/descenders and Dutch actions.
The measured moon anchor and all-four-inset layout are unchanged (OQ 10 padding/scrolling default).

The orchestrator subsequently recorded all 196 Welcome references on all seven D1c devices.
Comparison/UI was stopped after SE, 17e and 17: the natural-label glyph test failed on 17e at every
category, and the SE light English 2700 ms frozen image differed immediately after recording.
This does not establish a full comparison or UI pass. The recordings are retained.
The delivery wrapper calls the committed, fixture-tested runner, including all seven D1c devices,
Duo's dynamically resolved iPhone19-4 runtime, isolated Release checks and final `make check`/`make duo`:

```sh
sh build/commits/simulators.sh
```

Equivalent committed entry points (independent of delivery artifacts):

```sh
python3 -I Scripts/launch-simulators.py --welcome
make check
make duo
```

Simulator pixel/geometry/audit execution, board-frame/visual approval, existing contrast design
decisions and physical-device checks remain open. Phase 9a is not started by these fixes.

Host verification passes: 82 package tests; strict formatting; generator freshness with 7 TokenGen,
6 font/cache and 3 AssetGen tests; 9 launch-resource checks and 30 simulator-runner fixtures. Direct
Swift 6/MainActor compilation/type-checking against the iOS 17 floor passes for all modules and tests;
Debug/Release app and hosted-test SIL compilation passes. These do not execute UIKit or replace
`make check`, snapshots or the D1c simulator matrix. The existing D11 CoreText deprecation remains.

Round 2 corrects the glyph test's capture rather than production. ExactLineTextView and its native
labels do not clip at the exact line box; Welcome adds no headline clip. The ScrollView still clips
at its viewport. The old test resized a UILabel and compared PNGs, confounding glyph coverage with
UIKit's vertical centring/raster rounding. The new test keeps natural label bounds and renders the
whole exact-line view on a transparent canvas, padded on all sides by at least the font's ascent,
descent and leading. Independent natural-height labels at the same half-leading positions must
match its ink bounds and every RGBA byte at 2× and 3×, for S/L/XXL/AX5 and narrow/wide widths.
Pitch/height assertions retain their exact scaled values. A deliberately compressed line clipped
at its bounds must lose ink, proving the padded capture detects clipping.

The frozen helper previously waited for geometry/intro claim plus 50 ms, which did not establish
that UIViewRepresentable's UILabel backing and render-server transaction were complete. Capture
now recursively lays out views, displays pending layer contents and flushes without animations
before drawHierarchy. A bounded 100-pass loop (10 ms yields) requires three consecutive captures
with identical exact RGBA pixels and frames. No sample clock advances or tolerance changes occur.
The frozen snapshot itself renders two fresh hosts at 2450, 2700, 3200 and 3300 ms in both locales
and appearances and refuses recording/comparison if they differ. The existing independent repeated
mount/clock/render test remains. Production rendering is unchanged from the orchestrator's recorded
tree: **the recorded baselines stay valid; do not re-record for round 2**. Targeted simulator execution
is still required to verify both fixes.

From the repo root, prove the two fixes without the full matrix (recording explicitly cleared):

```sh
make generate
SNAPSHOT_RECORD=0 make targeted DEVICES="se 17e" \
  ONLY="DesignSystemTests AppTests/WelcomeSnapshotTests/finalWelcome AppTests/WelcomeSnapshotTests/frozenIntro AppTests/WelcomeSnapshotTests/frozenIntroPixelsStayFixedAcrossClockAndRenderPasses"
```

DesignSystemTests includes scaledHeadlinePitchAndGlyphsFitNaturalLabels and its clipping mutation;
the hosted tests compare final/frozen baselines and repeat fresh hosts at all headline sample times.
All categories, widths, locales and appearances are covered internally. Both invocations must report
executed tests. After these targeted checks, the outstanding matrix/acceptance commands remain:

```sh
python3 -I Scripts/launch-simulators.py --welcome
make check
make duo
```

OQ 10's RN padding/scrolling default remains assumed on the task. No additional defaults or new
states are introduced. Board-frame exports/visual approval, five board-contrast design decisions and
the existing physical-device/Apple-team work remain open. Device work remains (needs a device; open).

Round 2 host checks pass: 82 SwiftPM tests, two portable capture guards, strict formatting,
7 TokenGen / 6 font-cache / 3 AssetGen tests and generator freshness, 9 launch-resource checks,
30 simulator-runner fixtures and XcodeGen generation. Direct Swift 6/MainActor iOS 17 module/test
type-checking and Debug/Release app/hosted-test SIL compilation pass; only the existing D11 CoreText
deprecation remains. These checks do not execute UIKit; revised SE/17e and matrix validation stay open.

The hand-over regression now begins with normal motion and a signed-out first connection. It
requires the window to mount, the intro to exist at exitStart + 700 ms and Welcome to claim it once.
After disconnect/reconnect it requires a new mounted window without overlay/intro and compares
its pixels with an explicit final Welcome reference immediately and after 500 ms. A separate
Reduce Motion regression requires the root window to mount before checking that no intro exists.
All mounting/claim waits are bounded and assert their outcome; UIKit execution remains open.

## Phase 9a: account store, sessions and device identity (6 November 2026)

`LocalStore` pins GRDB 7.8.0 in the package manifest and resolver. It opens one background-actor-owned
WAL pool per account, at Application Support/ChronoFlow/Accounts/<UUID>/account-<UUID>.db (API) or
ChronoFlowMock/Accounts/… (mock). UUID path components are validated and canonicalized. A database
instance stays bound to its account across close/reopen; another account gets another instance so an old
repository cannot read a replacement account. Native v1 creates the seven RN-final-schema tables;
it never replays RN migrations. The independent schema fixture records the source migration hashes.
Failure leaves files and credentials in place; no destructive recovery is implemented.

The directory and DB/WAL/SHM receive completeUntilFirstUserAuthentication protection on iOS, and the
whole account directory is excluded from backup. This includes drafts/outbox: **OQ 26 is still a shipping
question**; device loss/restore loses unsent local changes. macOS 27.2 writes the backup-exclusion xattr
but its Foundation resource getter returns false in this environment; host tests inspect the binary plist
xattr itself. The hosted iOS storage lifecycle test verifies the URL flag before and after reopen. On a
physical device it also reads back the directory/DB/WAL/SHM protection class; the simulator returns nil,
so it instead asserts that setting the same class does not throw. Neither simulator nor host tests prove
locked-device hardware protection; the physical lock check remains open.

Records retain raw JSON text, including unknown members, nulls and number representations. Repositories
expose cancellable GRDB value streams fetched off the main thread; database close cancels observations
and drains readers/writer. The pure MainActor AccountModel lives in LocalStore (the app aliases it), so
unknown/loaded-empty/loaded/error, cancellation and account replacement are host-tested without UIKit.
No view or new destination is mounted. Local mutations, pending-value protection, sync and wipe remain
9c/9d work.

The Phase 4 StoredSession/SessionStore reader is extended with a throwing readStoredSession() shared by
SessionController and the legacy readiness helper. The existing native Keychain service/session key/JSON
shape and WhenUnlockedThisDeviceOnly accessibility are retained; mock has a separate service.
SessionController serializes open/upsert/credential-write/publication, rejects stale/canceled operations,
and exposes epoch-bearing immutable updates plus a sync-request seam. Restore errors retain credentials
for unlock/activation retry in 9d. NativeSessionController composes the one reader and model, but ordinary
SceneDelegate still uses Phase 4 readiness until 9d. An injectable deferred readiness factory proves
first-flush-before-service-construction with a suspended off-main open.

DeviceIdentityStore creates UUIDv7 once through a shared in-flight operation and device-scoped lazy
DevicePreferences (`api.deviceId`), outside both account namespaces. Clock/randomness/persistence are
injectable. A persisted malformed identity raises a typed failure instead of silently rotating it. Device names
use a trimmed name or model fallback and the longest whole-grapheme prefix fitting **255 Unicode scalars**,
which also fits the backend's character limit for composed emoji. No IDFA/IDFV is used. App composition
in 9b/9d should share one identity store across sources. Tests recreate the preference/store objects and
remove the account directory to verify persistence and the future wipe-survival contract.

Verification performed in this worktree:

- `make host-tests`: **115 tests passed** (57 AppCore, 15 LocalStore, 34 Launch, 8 DesignSystem, 1 Welcome;
  30 new tests). The warmed test bodies complete in about 1.3 s total, excluding build/startup.
- `make lint`, `make generate`, `make generators-check`: passed; generators ran 7 TokenGen, 6 Python
  font/cache and 3 AssetGen tests with unchanged generated assets.
- `python3 -I Tests/test_launch_simulators.py`: **21 passed**; `python3 -I Tests/test_launch_resources.py`:
  **9 passed**. Host-classified suites are excluded from ordinary simulator selection; targeted selection
  remains explicit. Hosted AppTests still depends only on ChronoFlow.
- `swift build --build-tests` with the iOS 17 simulator triple/installed SDK and repo-local caches passed;
  direct Swift 6/MainActor Debug and Release app/hosted-test module and SIL compilation passed.
  Compilation is not simulator execution.

**Open:** `make check` / hosted execution requires the orchestrator; no xcodebuild or simulator is run in
this sandbox. The matrix runs only on user request. Hardware protection/lock testing still needs a signed
physical device. The passkey plan is updated from the read-only backend handoff; its code belongs to 9b/10,
and team/bundle confirmation plus deployed AASA/device verification remain open.

After applying the patches, run from this worktree (the generated project/lock copy is required):

```sh
make generate
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=D788B715-AA0A-4B5A-882B-323E1F984769' \
  -testLanguage en -testRegion US -parallel-testing-enabled NO \
  -only-testing:AppTests/AccountStorageLifecycleTests \
  -only-testing:AppTests/SessionLifecycleTests \
  -only-testing:AppTests/KeychainSessionStoreTests test
```

The first two classes are new; the Keychain class is extended. For the existing launch/readiness and
Release regression coverage, run `make check` (one 17e). The exact targeted Release command is:

```sh
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ReadinessRelease -configuration Release \
  -destination 'platform=iOS Simulator,id=D788B715-AA0A-4B5A-882B-323E1F984769' \
  -testLanguage en -testRegion US -parallel-testing-enabled NO ENABLE_TESTABILITY=YES \
  -only-testing:AppTests/ReleaseReadinessTests test
```
