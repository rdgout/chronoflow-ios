# Tooling and verification — 5 November 2026

Toolchain: Xcode 27.2 (27B52), Apple Swift 6.4.2, XcodeGen 2.46.0 at `/opt/homebrew/bin/xcodegen`.
The app and package use Swift 6 language mode and an iOS 17.0 deployment target. UI modules default to
MainActor; AppCore is nonisolated.

## Trying the app on a simulator

Run the Debug app with the default `CHRONOFLOW_DATA_SOURCE = mock`. Its fake server starts with
the same accounts, settings and seven trip/plan fixtures as RN's mock:

| Account | Email | Password | Two-factor code | Recovery code |
|---|---|---|---|---|
| Verified demo | `demo@example.com` | `password` | — | — |
| Verified two-factor | `twofactor@example.com` | `password` | `123456` | `AbCdEf1234-GhIjKl5678` |

Enter these values on Sign in; the form starts empty. Two-factor sign-in opens the code/recovery
form before accepting a session. Both accounts start with walkthrough unseen and the RN
accepted policy versions. Trip dates rebase at initial seeding time to include an active, an upcoming and a completed
trip relative to the injected clock. Instants, local dates and copy arguments move together;
airport zones stay intact, and local times and tick offsets use the rebased dates’ DST rules.
Progress and offline eligibility use those rebased dates.

The seed and its fixture payload compile only in Debug; Release/Perf contain neither. API selection
never constructs the mock. The seed loads lazily on the mock actor after the splash commit and is
saved in `Application Support/ChronoFlowMock/Server/state.json`. Missing, empty, incompatible or
unreadable JSON from an older shape reseeds, as in RN; filesystem errors still fail the request.
Current saved accounts, settings, sessions and consumed recovery codes survive relaunch. Explicit
empty/custom test seeds retain their existing persistence behavior and never acquire demo accounts.

`Sources/DataAccess/Mock/MockScenarioValues.swift` owns the shared sign-in values. The test fixture
path symlinks that file and enables `CHRONOFLOW_MOCK_SCENARIOS` only for DataAccessTests, so Release
host tests can use the scenarios without compiling credentials into the Release library.
`MockAppSeed+Fixtures.swift` embeds RN's `fixture-data.ts` default settings (including
`createMockAccount`'s optional-items override), `fixtures/trips.ts` and all seven `fixtures/plans`
payloads, read on 6 November 2026. They are mock data, separate from the sanitized API contract
fixtures. Trip detail contracts exclude mock-only form/revision. Phase 13 shares these non-account trip templates with mock generation; default account seeding and its credentials remain Debug-only. The template data is now available to the explicitly selected mock source in either build configuration.

Verify on the host with `sh Scripts/host-tests.sh --filter DataSourceSelectionTests`.
Hosted composition: `make targeted DEVICES="17e" ONLY="AppTests/DataSourceFactoryHostedTests"`.
Release seed exclusion runs with `ReleaseReadinessTests` in `make check`'s isolated Release pass.
Verification in this worktree: `make quick` passed (307 Swift tests, three signing checks, ten
resource checks and 53 runner fixtures); the final focused suite passed nine host tests, including
recovery-code consumption across restart. Four Release host selection tests passed. All 14 Release
DataAccess object files were checked for absent demo identities, recovery code, trip fixture data
and seed symbols. New Debug/Release hosted tests type-check for iOS 17 against the existing app
modules; hosted execution remains open. No xcodebuild or simulator was run for this fix.

## Member trip generation — Phase 13

The `TripWizard` package product is nonisolated and depends only on AppCore and DataAccess.
`TripGenerationService` accepts an injected data source and Sendable effects. The Sync target's
`TripGenerationEffects.storing` adapter binds profile merges and trip pulls to an existing database/session
epoch, preserving pending body-clock edits and raw detail bytes. It requests sync through the caller's
existing trigger, without constructing another sync engine or adding wizard writes to the outbox.

Review calls deduplicate by instance, sorted input/profile bytes, token and review revision (plus edit
context), with a 30 s cancellable deadline over the API's 90 s write timeout. `answerPrompts` applies
profile, leg, stay and top-level fields using the server's scope, then re-reviews. Save returns the
updated caller-owned `TripGenerationState`; keep that state, including `savedTripId`, for retries.
Expiry/credits clear its identity and return `reReviewNeeded`; other typed failures retain it. There
is no automatic retry or connectivity refusal. A supplied saved ID skips POST, and a successful
identity is also cached in the session-scoped actor. Successful saves pull list/detail best-effort
and request sync. End the actor with `cancel()` at session teardown; recovery persistence is Phase 16a.

The mock uses the shared seven RN templates, route selection and calendar/DST rebasing. It persists
member drafts, receipts, paid directions and exact generated-trip input snapshots in optional fields
so older mock-state files still restore. Seeded trips reconstruct input from flight blocks, using DTO
defaults for wizard answers absent from the old seed; newly saved inputs round-trip exactly. Mock
planning stays fixture-based. API wire fixtures and their exact pinned backend sources live in
`Tests/DataAccessTests/Fixtures/wizard/SOURCE.md`. No backend runs or UI changes are needed.

Verification is host-only: `make quick` and `make contracts-check`. The Phase 13 run passes all new
suites and strict lint; only the known cookie-test loopback `EPERM` prevents a zero exit from quick.
The remaining quick targets pass separately. See `build/phase13-{quick,host-tools,host-fixtures,contracts-check}.log`.

## Trip contracts — Phase 12

`make contracts` regenerates committed `AppCore/Contracts/Generated/TripPlan.swift`.
`make contracts-check` (also `Tools/contracts-check`) fails on any generated-output drift,
including enum literals. Both read the sibling web repository with `git show` at
`afd80dc0cd127e9ad864d8ac32699383826366c8`; neither writes to a sibling. Override its
location with `python3 -I Tools/contracts-gen/generate.py --web-repo /path/to/web`
or `Tools/contracts-check --web-repo /path/to/web`.
These manual commands are excluded from `make quick` and `make check` because they need
that sibling and pinned commit. Generation also requires Python 3 and the toolchain’s
`xcrun swift format`, with no added dependencies or network access.

The generator follows the trip list/detail and member trip-wizard DTO dependency graphs through Data/Api,
Data/Trips, Data/Plan, Planner/Input, Planner/Output, Enums and Planning/Copy.
It also includes all Planner/Output and Enums literals for the manual contracts gate.
The backend literal `unknown` becomes `.unknownValue`, reserving `.unknown(String)` for future literals.
It emits Codable/Sendable/Equatable structs, public initializers, optional nullable or
optional properties and string enums that round-trip `.unknown(String)` values.
Web DTO numbers are integral (PHP `int`) except wizard prompt min/max bounds, which use Double for 0.1–9.9 ratings; mixed copy values retain decimal JSON numbers.
Unsupported syntax and changed hand-written union signatures stop generation.
Block parameter dispatch and copy argument unions are hand-written; wizard primitive answer records reuse JSONValue and their envelope/profile request shapes are hand-written because they have no generated TS DTO. Snake_case DTO fields have generated CodingKeys. Block parameters
are decoded by the enclosing block’s `type`; the three caffeine families distinguish
legacy string amounts from structured drinks, while `caffeine_routine` uses its string shape.
The indistinguishable null-exception `no_caffeine` shapes decode to the legacy variant.

`TripDetailResponse` carries original response bytes beside its decoded immutable value.
`applyDetail` writes those UTF-8 bytes unchanged into the existing SQLite TEXT column,
including unknown fields and whitespace. `PlanVersionRecord.decodedDetail()` reads the typed
contract from storage. Rendering selects `renderableBlocks`; reconciliation deliberately
uses the complete stored block list so unknown check keys survive plan refreshes.
No schema migration is required. All seven pinned RN plans and full constructed trip
response fixtures have provenance in `Fixtures/plans/SOURCE.md` and `Fixtures/trips/SOURCE.md`.
Host verification is `make quick`; Phase 12 does not require simulator execution.

Phase 12 host verification (2026-11-07): generated-output freshness and the enum-literal
mutation check pass. All Phase 12 tests pass, including database reopen, unknown-block
reconciliation, all parameter variants and DST/leap-day rebasing. `make quick` passes lint
and all package tests except existing `APICookieTests.realRedirectCookieHandlingIsDisabled`:
the restricted worktree cannot bind its loopback socket (`EPERM`). The test remains intact;
full quick must be rerun where loopback binding is allowed. The remaining quick targets
(`make token-tests asset-tests launch-resources-check`) pass: 14 generator tests and 85
Python fixtures. Logs: `build/phase12-quick.log`, `build/phase12-host-tools.log` and
`build/phase12-contracts-mutation.log`. No simulator commands were run.

## Test tiers — user decision 2026-11-06

The user requests **skipping the seven-simulator matrix unless asked**. This section supersedes
all matrix/default-run and per-simulator recording recipes in the dated history below. Device-fit,
visual approval and physical-device requirements remain. The tier port preserves the implemented
Phase 9a–9d stack and its review records below.

| Tier | Command | Coverage | Target |
|---|---|---|---|
| Inner loop | `make quick` | Strict lint, all SwiftPM host tests, runner/resource fixtures | <1 min warm |
| Targeted | `make targeted DEVICES="17e" ONLY="AppTests/WelcomeSnapshotTests/frozenIntro()"` | Build once, selected suites/methods on selected aliases | <2–3 min after build |
| Commit gate | `make check` | Quick + generators/font checks, then 17e hosted AppTests with all-size snapshots, UI smoke, UIKit-only font/asset/glyph checks, isolated Release readiness | <5 min |
| Duo spot check | `make duo` | Opt-in runtime smoke after Duo-specific runtime changes | — |
| Requested matrix | `make matrix` | All seven runtime destinations, LPT-balanced logic/Release once; profile/system-reference tests once on 17e | No default or CI invocation |

Auth audit cost decision (2026-11-08, supersedes the dated five-variant default recipes below):
`make check`, the runner default and targeted `AuthAuditTests` run **one method per distinct screen state**,
English/light/default size, **one app launch per method**. There are 37 screen-state methods, plus six
policy guards that do not launch the app. The suite target is **under 15 minutes on 17e**; this is a
runtime acceptance target, not a host-verified timing. No default Dark/XXLarge variant methods run.
This separate audit budget supersedes the earlier five-minute whole-check target for this suite.
Each audit position covers all fully visible controls; pending controls must be revealed in full inside
the safe viewport above any keyboard and audited before the method ends. Failures include state,
language, appearance, element/stage, frames and rendered text minima. One screenshot is decoded per position.

```sh
# Default audit coverage and functional verification, without recording:
make generate
make targeted DEVICES="17e" ONLY="AppUITests/VerifyEmailTests AppUITests/AccountRecoveryTests AppUITests/AuthAuditTests"
# Full five-variant lean matrix: en/nl × light/dark at default size, plus en/light xxLarge:
make audits
# Equivalent opt-in using targeted selection:
AUTH_AUDIT_FULL=1 make targeted DEVICES="17e" ONLY="AppUITests/AuthAuditTests"
# Lean audit suite alone (make audits otherwise opts into the full matrix):
AUTH_AUDIT_FULL=0 make audits
```

`make audits` defaults to a 5,400-second overall pass cap, overridable with `TEST_RUN_TIMEOUT`;
`REUSE_BUILD=1` is available after an unchanged build. The full matrix code remains in the same
37 methods and launches each of its five variants serially. The runner forwards `AUTH_AUDIT_FULL=1`
as `TEST_RUNNER_AUTH_AUDIT_FULL` to XCTest, removing any stale prefixed value for default runs.

Reset/SignUp audit setup uses `CF_AUTH_TEST_AUDIT_SCREEN` / `CF_AUTH_TEST_AUDIT_STATE` only with a valid
isolated `CF_AUTH_TEST_ID`; that UUID also forces the Debug mock factory. Inputs are prefilled before
presentation, and submission still uses the actual button and model/server path. Only audits suppress
new-password error focus, so they do not invoke the system strong-password sheet. Functional typing,
AutoFill traits and keyboard tests retain the native path. Reset server/throttle setup waits for
`auth.banner` explicitly. Every rejected audit issue records an attributed XCTest failure and attachment;
returning handled to XCTest prevents its duplicate unattributed “Contrast failed”.

`sign-up.back` is measured using RenderedTextContrast, generated skyCopy/authLabel tokens, and the
centered text region from the current font/wrapping/button padding. An exception requires the matching
named contrast issue, matching current button geometry and a complete finite minimum **≥ 4.5:1**.
Lower, clipped or unmeasurable results fail with diagnostics. No ratio or runtime pass is inferred here.
The supplied compare xcresult shows `route.walkthrough` immediately after verification and after relaunch:
mock registration accepts current terms, so Verify/AccountRecovery expectations now use that gate.
All 364 Reset/SignUp/Verify reference PNGs remain unchanged.

Fix-round-3 host verification: `make -k quick` passes strict formatting lint, **367/368 package tests**,
10 TokenGen tests, 4 AssetGen tests and **90 signing/resource/runner fixtures** (3 + 10 + 77).
Only the known `APICookieTests.realRedirectCookieHandlingIsDisabled` loopback listener EPERM fails.
Direct Swift 6 compilation against `arm64-apple-ios17.0-simulator` passes for Auth, ChronoFlow,
AppTests and AppUITests; no simulator is started. Logs: `build/round3-quick.log`,
`build/round3-final-quick.log`, `build/round3-typecheck.log` and `build/round3-typecheck/*.log`.
The three ordered patches in `build/commits` apply on `42297c8`, with subjects in `messages.txt`.
Commits are assembled in an isolated packaging repository because workspace Git metadata is read-only.
Runtime UI/audit results, current footer ratios and the under-15-minute target remain unverified;
run the commands above on 17e. No snapshot recording, `make check`, Duo or seven-simulator matrix ran.

`Scripts/ci.sh` runs `make generate check`. The Make default is check. The runner's own default is
also check on 17e; only `--matrix` or explicit compatibility matrix flags request all seven.
`make test` and `make snapshots` select subsets on 17e. No default flow calls Duo or the matrix.
Generate the project after manifest/project changes. Debug/ChronoFlow and isolated Release/ReadinessRelease
build once each into `build/DerivedData`, with pinned resolution, then use `test-without-building`.
Only the Release verification build gets `ENABLE_TESTABILITY=YES`. Perf stays separate.

Each `test-without-building` pass watches its combined stdout/stderr log for byte growth. A pass
may run for more than the former 1,200-second limit while it keeps producing output:

| Environment override | Default | Meaning |
|---|---|---|
| `TEST_RUN_IDLE_TIMEOUT` | 600 seconds | Terminate after this long without log growth; each increase resets the inactivity deadline |
| `TEST_RUN_TIMEOUT` | 3,600 seconds; `make duo` keeps 600 | Overall cap per pass, even while output continues |

Both overrides require positive finite seconds. For example,
`TEST_RUN_IDLE_TIMEOUT=900 TEST_RUN_TIMEOUT=5400 make check` changes both limits. Merely touching
the log does not reset inactivity. The log and failed-suite details distinguish inactivity from
the overall cap. Either timeout sends SIGTERM to the process group, allows up to five seconds to
exit, then sends SIGKILL to the group, including lingering descendants. The log is retained and
later passes for that destination stop. SIGINT/SIGTERM forwarding and prompt worker cancellation
remain in effect. Build and simulator-preparation commands do not use these per-test-pass limits.

Timeout fix verification (2026-11-07): `make quick` passes, including all 72 runner fixtures.
Coverage includes a progressing 1,800-second simulated pass, stalled output, timestamp-only log
changes, the overall cap, override validation, Duo's cap, descendant cleanup and signal forwarding.
Log: `build/tooling-timeout-quick.log`. No simulator run was needed for this runner change.

After `bootstatus` completes, every runner destination receives `xcrun simctl spawn <udid> defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false` before testing, including already-booted devices and reused builds. This idempotent device preference prevents headless simulators with an attached hardware keyboard from minimizing the software keyboard; host-global Simulator.app preferences are untouched. Check, targeted, Duo, matrix and the separate Perf scheme all share this preparation. Keyboard helpers require a stable keyboard intersection of at least 100 × 100 points inside the app window, rejecting accessory strips and off-screen frames with “software keyboard not visible — check AutomaticMinimizationEnabled”.

Host package execution uses `Scripts/swiftpm.sh test ChronoFlowKit`, macOS 14 or later,
`--disable-sandbox`, repo-local scratch/cache/config/security/temp directories and `CFFIXED_USER_HOME`.
HOME is unchanged. Quick also runs TokenGen and AssetGen SwiftPM tests. Make prerequisite deduplication
runs each host suite once in check; generator/font freshness remains part of the commit gate.
Clean first runs may fetch the pinned packages/font tools; the warm target assumes those caches exist.

The Phase 9a–9d suites remain part of these tiers. All `AppCoreTests`, `LocalStoreTests`,
`DataAccessTests` and `SyncTests` suites have the `host` policy and run in quick/host-tests, including
through check. `Scripts/host-tests.sh` delegates to the shared ChronoFlowKit host runner and still
accepts SwiftPM filters and configurations.

| Phase 9a–9d hosted suites | Policy | Default execution |
|---|---|---|
| AccountStorageLifecycleTests, SessionLifecycleTests, KeychainSessionStoreTests, DataSourceBuildSettingTests, DataSourceFactoryHostedTests, SyncLifecycleTests, AccountWipeTests, SessionReadinessTests | logic | Debug AppTests, once on 17e in check |
| LaunchConnectionTests | matrix (live app lifecycle) | Debug AppTests on 17e in check; other runtimes only when requested |
| ReleaseReadinessTests | release | Isolated Release AppTests, once on 17e in check |

None of these suites uses the profile-rendering policy. Runner fixtures verify both selection and
the resulting check commands, including configuration, destination and exactly-once execution.

### Device fit without seven simulators

The shared fixture is `Packages/ChronoFlowKit/Tests/SnapshotSupport/profiles.json`:

| Profile | Points | Scale | Insets top / left / bottom / right |
|---|---|---|---|
| se | 375 × 667 | 2 | 20 / 0 / 0 / 0 |
| 17e | 390 × 844 | 3 | 47 / 0 / 34 / 0 |
| 17 | 402 × 874 | 3 | 62 / 0 / 34 / 0 |
| air | 420 × 912 | 3 | 68 / 0 / 34 / 0 |
| 18pro | 402 × 874 | 3 | 62 / 0 / 34 / 0 |
| 18promax | 440 × 956 | 3 | 62 / 0 / 34 / 0 |
| duo | 466 × 678 | 3 | 0 / 0 / 0 / 19 |

The fixture follows the retained runtime/profile dimensions, the reference brand geometry and Duo's
19 pt side rail. Production still measures window geometry; no fixture size reaches product layout.
Mac `DeviceGeometryTests`, `LaunchLayoutTests`, `LaunchSnapshotGeometryTests`, `WelcomeGeometryTests`
and `ExactLineTextLayoutTests` cover sampled containment, the bottom-only sun horizon with at least a
third visible, board/S1 clearances, all four insets, zero-inset board composition and English/Dutch
headline wrapping/pitch. `WelcomeGeometry` uses generated Welcome tokens in production as well as tests.
The duplicated simulator fallback/timeline/containment loops are removed.
`DeviceGeometrySmokeTests.testLiveWindowMatchesPureLayouts` checks the live window against both pure layouts.

Hosted `SnapshotContainer` supplies explicit point size, fixture insets and displayScale traits.
For profile snapshots, `UIHostingController.safeAreaRegions = []` disables host-safe-area injection;
the internal Welcome capture initializer passes the fixture's four insets straight into the same
`WelcomeGeometry` used by production. Ordinary app initialization still measures the live safe area.
The UIKit child's native safeAreaInsets is not a fixture API. `SnapshotContainerTests` checks rendered
brand/action coordinates, point bounds, traits and raster dimensions on every profile, then repeats with
parent additional insets of 120/80/100/90. This covers host insets larger than SE's 20/0 and Duo's 0/0/0/19.

Welcome reuses one window/controller per profile across appearance, locale and size variants. Each
configuration installs a new SwiftUI identity, intro and anchor store; callbacks from replaced identities
are ignored. A main-queue turn followed by descendant layout/display and transaction flush precedes
CPU `window.layer.render(in:)` at the fixture scale. Two consecutive exact sRGB RGBA rasters and frame
sets must agree, with all geometry callbacks and intro claim present, within eight passes. No fixed
sleep or pixel tolerance is used. Container tests compare fresh and reconfigured windows on every profile.

#### Second fix round: capture diagnosis and references (2026-11-06)

The user's first container run passed. Recording then completed, but immediate comparison failed 60
finalWelcome filenames; frozenIntro and splash passed. The subsequent check failed in 552 s.
The compare log reports the **first** differing byte, not the total differing-byte count.
Independent decoding of the recorded finalWelcome/landed-frozenIntro images reproduces those exact
first mismatches in sky-only pixels: 18 Pro dark byte 4246, Pro Max dark 4234, Air dark 3621,
Air light 4986 and Duo dark 4374. In their first 50 rows the respective differing-channel counts are
1402 / 3627 / 2810 / 130 / 4999, all with maximum magnitude 1. These are already present between
equivalent skies in the same recording. Text, locale and type-size changes do not account for them.
The axial CfSkyLayer gradient has horizontal quantization noise; the differing patches start partway
across row zero. This implicates the render-server gradient dither/quantization rather than text layout.
A definitive GPU state experiment cannot run inside the agent sandbox: CoreSimulator access is denied.

The fix bypasses that path: Welcome now uses the same CPU layer-tree capture API as splash, with
explicit scale and standard range. A Mac probe of the actual CfSkyLayer implementation at all seven
fixture sizes/scales, both appearances, fresh and reconfigured layers, produced identical raster hashes
in two independent processes. Hosted fresh/reused-window and repeated-clock/root tests remain the UIKit
acceptance checks. Comparison stays **byte-exact**, with no ±1 allowance or pixel-count budget. Uniform/
transparent rejection and the opposite-variant >8-channel-delta / >0.1% guard remain independent; the
latter now uses a buffer scan with an early success threshold, preserving its original rule.

**Capture rendering changes: re-record the 320 Welcome references.** All 792 of the user's recorded
PNGs are retained byte-for-byte by this delivery. Splash's 472 references and its capture path are
unchanged. An exact comparison against the old Welcome capture is expected to fail before recording.
Production rendering, tokens and geometry are unchanged. No references are deleted or fabricated here.

#### Wall-time diagnosis and stage budget

Saved xcresults/logs show Debug-compare **335.593 s**, serial device-appearance smoke **112.558 s**
(78.290 s in tests), and isolated Release **28.900 s** (0.009 s in tests). The remaining approximately
75 s of the user's 552 s gate includes host/generator work, builds, preparation and result extraction.
The original Welcome durations were frozenIntro 50.324 s, repeated frozen roots/clocks 84.536 s,
finalWelcome 34.192 s, cap equivalence 21.163 s and opposite-variant checks 21.270 s. All these Swift
Testing cases ran on the same hosted worker after the XCTest cases, leaving the UI worker idle.

`RenderTests/WelcomeRenderingTests` is now a separate app-hosted bundle, so Xcode can schedule the
fresh-root/clock/typography regressions independently of the AppTests profile snapshots on its two
isolated workers. It links only ChronoFlow, with TEST_HOST/BUNDLE_LOADER, just like AppTests. Both
bundles keep their own serialized Swift Testing suites. Recording selects only the two baseline suites;
guards and rendering regressions run once in comparison. Release and device appearance stay isolated.

finalWelcome retains **every existing profile filename/category**, including full SE/17e/Duo/Pro Max
coverage and compact 17/Air/18 Pro large/xxLarge coverage. Moving the remaining full categories to
compact would violate the settled profile decision, so no coverage is removed. It now checks actual
17e renders of every requested category above xxLarge against the existing xxLarge pixels and frames,
and compares large/xxLarge, locale and appearance variants using captures already in hand on every
profile. The separate cap and opposite-variant window loops are removed. Repeated frozen tests retain
two independent windows at every profile time in both locales/appearances and all three clock advances;
the redundant ten-window 2400 ms stress loop and third capture after layout are removed. Comparisons
use SnapshotRaster's exact memcmp. A fresh/warm separate-process intro diagnostic remains opt-in.

Launch parity's shift search evaluates zero displacement first and prunes a candidate only after its
accumulated nonnegative error exceeds the best complete result. The minimum-error and Manhattan-distance
tie rules are unchanged and checked against exhaustive search, including clamped edges. A warm unoptimized
Mac benchmark at 1170×2532 with a 340×340 moon search and radius 5 fell from **30.82 s to 3.18 s**, with
identical whole-image/interior metrics and displacement. This directly targets the long pixel-analysis
spans in Debug-serial and the hosted image-mutation/parity tests. It does not loosen parity thresholds.

Warm stage estimates, to be measured on 17e after recording (not simulator results):

| Stage | Expected wall time |
|---|---:|
| quick | 17 s (measured 16.82 s) |
| generator/font freshness beyond quick | 8 s (measured 7.72 s) |
| Debug + Release incremental builds | 15–25 s |
| preparation and result extraction | 5–10 s |
| Debug compare, two workers | 100–120 s |
| serial appearance smoke | 75–85 s |
| isolated Release readiness | 25–30 s |
| Total | approximately 245–295 s warm; the <300 s acceptance is still open |

Build or simulator startup variance can exceed this budget. The compare estimates depend on CPU capture
and worker distribution and need a real run; the sandbox permits host checks and iOS 17 type-checking
but not simulator execution. Do not claim the five-minute gate from the host benchmark alone.

The xcresult parser now recognizes a qualified identifier only when it contains target/suite/method;
`WelcomeTests/method()` under AppUITests must retain its suite name even though WelcomeTests is also a
package target. Fixtures cover qualified/unqualified forms, neighboring suite names, the actual Dutch
AX5 case, timing extraction and `Clone N` log lines. Executed-case timings, including failed cases, are retained even when another
suite fails, so the scheduler can learn from a failed compare run.

Splash displays/flushes and renders the parent layer at the profile scale. The **32 ready-1900 references**
are intentionally fully transparent: the designed 400 ms ready exit ends at 1900 ms. Host timeline tests
prove these are the only zero-opacity samples. The verifier explicitly requires all alpha bytes to be zero
for this endpoint and rejects any visible pixel; every other splash/Welcome sample must have visible variation.
SE renders at 2× inside the 3× 17e runtime; Duo retains its asymmetric layout inset.
The root Dynamic Type cap stays xxLarge. All 792 profile filenames remain required. Above-cap filenames
reuse xxLarge except on 17e, where every requested category is independently rendered and checked for
exact pixel/frame equivalence inside finalWelcome. Landed intro 3300 reuses 3200 where present; shared
intro tests prove all items have landed by 3200. Splash frames without status text reuse the raster
across language/type variants. There are 160 frozen roots, 144 final renders and 184 splash renders
per baseline pass, with 416 immutable PNG/raster preparations for 792 reference checks. Each suite
prints its capture count and elapsed time. Full/compact selections remain unchanged.

All **278 old per-simulator references are deleted**. Replacement references live under
`AppTests/__Snapshots__/{WelcomeSnapshotTests,LaunchSnapshotTests}` and use profile aliases, points and
scale in filenames. Expected coverage is **320 Welcome + 472 splash** references: both appearances and
languages, Welcome's profile categories/intro times, splash large/xxLarge at each retained frame.
The host inventory guard rejects partial or stale recordings; wholly absent suites are explicitly pending
orchestrator work. Compare-only simulator runs fail on missing references. No generated baseline is fabricated.

For this fix round, regenerate the project, verify capture/container invariants, re-record Welcome,
then run the complete gate. The targeted recording command writes **only Welcome**, once, and follows
it with an independent comparison process. Existing splash references are compared by check.

```sh
make generate
SNAPSHOT_RECORD=0 /usr/bin/time -p make targeted DEVICES="17e" ONLY="AppTests/SnapshotContainerTests"
SNAPSHOT_RECORD=1 /usr/bin/time -p make targeted DEVICES="17e" ONLY="AppTests/WelcomeSnapshotTests"
SNAPSHOT_RECORD=0 /usr/bin/time -p make check
```

Optional separate-process intro-order proof, reusing the just-built products:

```sh
SNAPSHOT_RECORD=0 python3 -I Scripts/launch-simulators.py --no-generate --devices 17e --reuse-build --intro-order-check
```

For future intentional changes to both screens, `SNAPSHOT_RECORD=1 make snapshots` records both baseline
suites once on 17e with one worker, then compares and runs guards/rendering regressions. Legacy explicit
`launch`/`all` recording selections remain supported. Shared profile namespaces are never recorded from
other simulators. Builds, preparation and comparisons clear recording variables. Inspect new images
alongside the boards; `_design/frames/` export/approval remains open.

Only for a Duo runtime change:

```sh
make duo
make targeted DEVICES="se duo" ONLY="AppTests/DeviceGeometrySmokeTests" REUSE_BUILD=1
```

The latter explicitly requests both runtimes; it is not part of check. Duo resolution uses device type and
`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4` (24B91016s), never name/OS or a stored UDID.
All other aliases resolve on the regular iOS 27.2 runtime. The cached system launch frame still needs the
existing physical-device recording; hosted storyboard parity does not claim to capture that system snapshot.

### Smoke set and isolation

UI launches cover serial launch-to-Welcome in each device appearance, frozen live screenshot parity,
Plan/Sign-in routes, one English/light and Dutch/dark audit journey (top then fully visible actions),
Dutch AX5 scroll reachability, and readiness hand-offs observable in the running app. Audit diagnostics,
the five exact board-contrast exceptions and the partial-visibility-only contrast rule remain strict.
All other assertions moved to hosted or Mac tests; the removed-assertion → replacement-test table is
in plan.md's tooling round 3 task 3. The real sampled-moon offset/opacity mutations are now hosted;
comparison/frame-stability helper tests run under host SwiftPM instead of a UI runner.

System launch/first splash appearance follows the **device**, so those tests use
`XCUIDevice.shared.appearance`, wait for the reported appearance before launch and restore it in teardown.
`SERIAL_TESTS` isolates both frozen parity classes and the launch journey. Per-launch AppleInterfaceStyle
is used only for the app's own post-launch audit UI. Frame stability means three consecutive equal,
finite, nonempty frame arrays, with reset after missing/changed data and a 60-second upper bound;
there is no six-second CPU-speed acceptance rule.

Single-device and heavy matrix jobs use two isolated AppTests/RenderTests/AppUITests workers by default;
`TEST_WORKERS=1…4` overrides. Serial selectors are removed from the parallel pass and run separately
with parallel testing disabled. Recording, Release and intro-order diagnostics always use one worker.
Snapshots retain suite serialization. XCTest workers run on isolated clones, bounded by a shared budget.
Every test target/suite is classified once; host discovery catches missing, duplicate **and stale** entries,
including an old XCTestCase class with no test methods. The command-failure fixture hook must never shadow
`unittest.TestCase.fail`; a regression guard prevents suppressed assertion failures. xcresult matching also fails absent suites.

Only requested matrix jobs use longest-processing-time placement. The runner loads measured per-device,
per-suite and per-test durations from `build/test-results/timings.json`, bootstraps previous logs and uses
static estimates where unavailable. Logic/Release run once on the earliest finishing destination, then
longest device jobs start first. Profile snapshots and system reference suites run on 17e once.
`SIM_CONCURRENCY=1…7` overrides automatic core/available-memory sizing. Targeted jobs preserve explicitly
requested repetition and alias order. Fresh state means uninstall, with no clean, erase or reboot; the
manual launch-storyboard cache trap still applies after that resource changes.
Logs/xcresults live in `build/test-results/<alias>/`; build logs use `build/test-results/build/`.
Debug failure does not suppress Release or other requested devices; per-suite failing identifiers are retained.

The exact intro-order selector stays
`AppTests/WelcomeSnapshotTests/frozenIntroOrderIndependence()`. The opt-in diagnostic enumerates compiled
flat identifiers first, requires the exact match, then compares fresh and warmed processes through the same
immutable PNG→sRGB RGBA verifier. Missing/skipped diagnostics, target/prefix collisions and empty results fail.
Fresh/warm captures are retained under `build/test-results/intro-order/<model>/`; the reference capture now
uses the explicit 17e profile so it is independent of the runtime selected for the diagnostic.

```sh
SNAPSHOT_RECORD=0 python3 -I Scripts/launch-simulators.py --no-generate --devices se --reuse-build --intro-order-check
```

This diagnostic is optional. The prior SE capture-state root cause and the new baseline's visual acceptance
remain unproven until the orchestrator executes the regression.

### Verification and open work

The supplied round 2 `make check` failed on 17e after **408 s** (exit 2): a dark opening captured light,
AX5 frame-settling timeout and a stale suite selector. These are the regressions addressed here.
Host verification for round 3: **make quick passes in 26.74 s warm**, including strict formatting,
**91 Swift Testing + 3 XCTest package tests**, **7 TokenGen**, **3 AssetGen**, **43 runner fixtures** and
**9 launch-resource checks**. Generator/font freshness and all **6 font/cache fixtures** pass.
Direct Swift 6/MainActor iOS 17 module compilation and Debug/Release hosted/UI/package/Perf type-checking
pass, without xcodebuild or running UIKit. The existing D11 CoreText registration deprecation remains.
These are host results; new simulator results are not claimed.

Fix-round host verification (2026-11-06): **make quick passed in 26.49 s** (earlier runs: 32.78 s / 25.87 s), including **96 package tests**
(93 Swift Testing + 3 XCTest), 7 TokenGen, 3 AssetGen, 43 runner and 9 resource checks. The added tests
cover the 32 transparent endpoints and explicit transparent recording/rejection. Generator/font freshness
and all six font/cache fixtures pass in **5.13 s**. Direct iOS 17
Debug/Release hosted/UI/package/Perf type-checking passes without xcodebuild or a simulator. An unoptimized
Mac raster microbenchmark over eight 17e-size transparent images measured the old blank guard at
**0.795 s**, the new guard at **0.088 s**, and exact transparency at **0.089 s**. These are host primitive
timings, not a simulator speed claim (`build/fix-raster-benchmark.log`).

The user's failed recording took **1111 s**, including frozenIntro 210 s, finalWelcome 96 s and splash
142 s; safe-area failures, the transparent-endpoint guard and one frozen equality failure invalidated it.
All **708** PNGs it produced were removed, retaining all **278** old baseline deletions. There are no new
references in this delivery. The unchanged inventory guard passes for absent suites and still rejects
partial/stale recordings; successful recording must supply all 320 + 472 names.

The orchestrator must record/compare/review references, run check and confirm its <300 s budget.
Measure targeted after an unchanged build (<180 s target). Matrix timing is requested work only:

```sh
SNAPSHOT_RECORD=0 /usr/bin/time -p make check
SNAPSHOT_RECORD=0 /usr/bin/time -p make targeted DEVICES="17e" ONLY="AppTests/WelcomeSnapshotTests/frozenIntro()" REUSE_BUILD=1
# Only when the user asks:
SNAPSHOT_RECORD=0 /usr/bin/time -p make matrix
```

Existing OQ 10 padding/scrolling and OQ 11 x-scaling defaults are retained and annotated on task 1;
no new screen/state is invented. Board contrast decisions and exported-frame/visual approval stay open.
Device-only D3/Instruments/locked-device/VoiceOver/status-bar checks retain their unticked tasks
**(needs a device; open)**, with Apple team/reference device still unavailable. No other phase is ticked.


The phase records below retain their original verification results. Historical command examples
use `LaunchToWelcomeTests` for the retired window smoke; the original runs preceded that replacement.

## Phase 0 verified results

The orchestrator ran the following on 5 November 2026 with
Xcode 27.2:

- `make generate && make check`: passed (`TEST SUCCEEDED`). Strict formatting lint, AppCore tests,
  the original window smoke on iPhone 17e / iOS 27.2, and the DesignSystem, Launch and Welcome suites
  all passed. This verifies XcodeGen output through a complete build and app launch.
- The original window smoke on iPhone Duo / its iPhone19-4 iOS 27.2 runtime, selected by device ID:
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
    -destination "$destination" -only-testing:AppUITests/LaunchToWelcomeTests test || exit 1
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
the original window smoke and DesignSystemTests at each running device's own display scale.

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
  -only-testing:AppTests -only-testing:AppUITests/LaunchToWelcomeTests -only-testing:DesignSystemTests test
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
  -only-testing:AppTests -only-testing:AppUITests/LaunchToWelcomeTests \
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
  -only-testing:AppTests -only-testing:AppUITests/LaunchToWelcomeTests \
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
  -only-testing:DesignSystemTests -only-testing:AppUITests/LaunchToWelcomeTests \
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

## Phase 9b: data-source contracts, API and mock (6 November 2026)

The `DataAccess` package implements the one `AppCore.DataSource` contract. Auth wire DTOs use explicit
coding keys, session/two-factor discriminators, optional guest fields and signed verification inputs.
Account/trip synchronization metadata and check keys are typed; unconsumed presentation objects retain
unknown members as JSON values. Outbox commands distinguish supported receipts from parked unsupported
kinds. API error mapping preserves HTTP status and field sentence keys/arguments; Laravel and RN argument
syntax normalizes to String Catalog format placeholders without displaying arbitrary server English.

`CHRONOFLOW_DATA_SOURCE` defaults to `mock` in Base.xcconfig, including Release. An explicit `api` selects
the API in either configuration; unknown values fail. Tests always select mock. The default base URL is
`https://api.chronoflow.net/v1`; Release rejects HTTP and every configuration rejects relative URLs,
credentials/query/fragment and path traversal. Local.xcconfig is included last so explicit overrides work.
API account storage/Keychain retain Phase 9a's namespace; mock uses ChronoFlowMock and the mock Keychain
service. `api.deviceId` remains outside both. `AppServices` exposes construction only; ordinary launch
still uses the Phase 4 composition until 9d, and no auth UI or sync lifecycle is mounted here.

The API client lazily creates an ephemeral URLSession on its actor. It disables cookies, URL credentials
and persistent caching, refuses every redirect, excludes bearer on all public auth routes and cancels
requests at injected 15/90/3-second deadlines. Tests inject a deny-by-default URLProtocol, with one
macOS-only loopback test for real HTTP cookies and redirects; fixtures
are synthesized from backend DTOs and assertions, with source/provenance notes alongside them. No live
API or production credential was used.

Mock state is separate fake-server JSON at `ChronoFlowMock/Server/state.json`, loaded only on the actor's
first operation, and never the local account DB. The default seed is empty; RN demo credentials and
accepted fake assertions exist only in named test scenarios. Tests inject memory/repo-local file stores,
clocks, identifiers and latency. Assumed mock defaults: 300–800 ms latency; five attempts per minute;
300-second/five-failure two-factor challenges; 60-second verification resend window; one-hour reset and
signed verification inputs; 90-day sliding device sessions. Passkey challenges use the backend's
120-second single-use lifetime and 10/min options, 5/min credential, 20/min IP and 20/hour failed-credential
limits. An injected assertion provider models acceptance; the default rejects all credentials. Mock checks
the production password shape (12/mixed case/number/symbol) without contacting the uncompromised-password
service. Mock signatures and credentials have no production meaning. Settings/readiness follow RN fake-server
behavior; planner presentation objects are fixture values rather than a native planner implementation.

The backend handoff at `841be4bd` takes precedence over the stale RN passkey TODO and token/email verify
shape. Passkeys return sessions for 2FA and unverified accounts, verification takes authenticated signed
fields, and reset revokes sessions without issuing a new session. AuthenticationServices, associated-domain
entitlements, confirmed Apple identifiers and actual device passkey verification belong to Phase 10.
The backend branch is not deployed; no deployment or AASA verification is claimed.

Verification in this worktree:

- `make host-tests`: **164 passed**, including **49 DataAccess tests** across eight suites. Parameterized
  cases additionally cover every error code, redirects, retry-after precedence and deadline values.
- `make lint`, `make generate`, `make generators-check`: passed (7 TokenGen, 6 font/cache, 3 AssetGen
  tests; generated assets unchanged).
- `make launch-resources-check`: passed (9 resource checks, 21 simulator-runner fixtures).
- SwiftPM `swift build --build-tests` for `arm64-apple-ios17.0-simulator` and direct Swift 6/MainActor
  Debug/Release app and hosted-test module/SIL compilation: passed. Compilation does not execute UIKit.
- Implementation commits, each with its task tick: `d6b54f0` (`feat(data-source)`),
  `6ed5c29` (`feat(api)`) and `c730aa3` (`feat(mock)`).

Run these exact targeted checks outside the sandbox on **one iPhone 17e**, without a matrix:

```sh
make generate
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=D788B715-AA0A-4B5A-882B-323E1F984769' \
  -testLanguage en -testRegion US -parallel-testing-enabled NO \
  -only-testing:AppTests/DataSourceBuildSettingTests \
  -only-testing:AppTests/DataSourceFactoryHostedTests test

xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ReadinessRelease -configuration Release \
  -destination 'platform=iOS Simulator,id=D788B715-AA0A-4B5A-882B-323E1F984769' \
  -testLanguage en -testRegion US -parallel-testing-enabled NO ENABLE_TESTABILITY=YES \
  -only-testing:AppTests/DataSourceBuildSettingTests \
  -only-testing:AppTests/DataSourceFactoryHostedTests test
```

These new hosted classes verify built Info.plist substitutions, mock-only factory selection and lazy
source construction. Their execution and the integrated `make check` remain **Open: orchestrator**.
The seven-simulator matrix runs only when requested. Existing physical-device protection/performance,
Apple team/bundle confirmation, deployed AASA and later UI/copy/shipping questions remain open;
none blocks this service-only 9b implementation.

## Phase 9b review corrections (6 November 2026)

Redirect stubs now notify URLSession of 301/302/307/308 redirects with Location and Set-Cookie.
Tests cover same-host and foreign-host targets, record both destinations, and use a delegate-less
control session that must follow each redirect. APIClient must refuse every redirect without a
second request or bearer/cookie leakage. Its internal effective-configuration snapshot returns a copy;
tests check cookie storage/policy, credentials, cache and additional headers after injection and use.

`APICookieTests` runs only on macOS. Its Network listener binds an ephemeral port on 127.0.0.1, closes
every HTTP connection and stops at test teardown. A control URLSession must follow a 302, store its
cookie and send it to the next path. APIClient must refuse that response, ignore a pre-seeded cookie,
store no response cookie and send no cookie on a later request. No external host or real-time sleep
is involved. `sh Scripts/host-tests.sh --filter 'APICookieTests|APIClientTests'`: **12 tests passed**.
Removing the installed redirect delegate fails the tests; removing cookie/cache/header protections
also fails, including the real cookie send/store assertions. The original stub fails the new
redirect control assertions before its fix.

The Phase 9b implementation record now names its three existing commits instead of saying no
commits were made. `python3 -I Tests/test_launch_resources.py
LaunchResourcesTests.test_phase9b_tooling_records_the_committed_implementation` fails against the
old note and passes after correction, checking the recorded hashes against git history.

Mock sign-in now uses the exact backend wrong-credentials key; register/reset attach mismatch errors
to `password_confirmation` alongside any independent password error. Exact host regressions fail
against the old behavior and pass after correction. Settings validation visits keys in sorted order
and collects all invalid field values before throwing. API/mock parity covers multiple errors in
reminders, preferences and body-clock patches, reversed insertion order and unchanged state after
rejection. Each regression fails against its original implementation.

Review verification: `make host-tests` passes **177 tests**, including **54 DataAccess tests**;
`make lint`, `make launch-resources-check` (10 resource/history checks, 21 runner fixtures), and
`make generators-check` (7 TokenGen, 6 font/cache, 3 AssetGen tests; generated assets unchanged)
all pass. Host SwiftPM uses `--disable-sandbox` and repo-local cache, scratch and temp paths.
These regressions need no new hosted execution; the existing factory/build-setting commands above
and integrated `make check` remain open for the orchestrator.

## Phase 9a review corrections (6 November 2026)

Accept's successful credential write is its commit point. Supersession and cancellation before the
write still reject the operation; after a successful write it publishes and returns success, including
when a newer invalid accept is queued or sync is still suspended. A same-account refresh retains the
previous published presence/token until commit. Switching accounts publishes signed-out before the
database transition; failure retains the previous credentials on disk for a later restore.

AccountModel resets to unknown when its observation ends normally. Native observation captures an
attachment token before its actor hops and checks it on the MainActor before attaching or detaching.
An intervening detach invalidates that token. SessionAccountDatabase also hides its active database
throughout close, including while waiting for detach, so a new lookup cannot attach to a closing pool.

Regression proof and host verification:

- The three write/sync race tests failed before fix 1 and passed afterward. They suspend credential
  writes and sync, preserving the existing test that rejects supersession before the write.
- The two parameterized post-sign-in failure tests failed before fix 2 and passed afterward, covering
  open/upsert/credential-write failures for the same and different accounts. Real database integration
  additionally verifies retained same-account credentials and closure of the replaced database.
- Closing an attached database left its record loaded before fix 3; the regression passes afterward.
  A suspended-close test rejects an attachment captured before detach, hides the still-open closing
  database, and proves that a stale attachment cannot replace a newer account's loaded model.
- `sh Scripts/host-tests.sh`: **172 passed** (62 AppCore, 18 LocalStore, 49 DataAccess, 34 Launch,
  8 DesignSystem, 1 Welcome), using `--disable-sandbox` and repo-local caches/temp paths.
- `make lint`: passed. `python3 -I Tests/test_launch_simulators.py`: **21 passed**.
  `python3 -I Tests/test_launch_resources.py`: **9 passed**. `git diff --check`: passed.

No xcodebuild, simulator or git commit ran in this sandbox. Three ordered patches and their Conventional
Commit messages are in `build/commits/`; apply each with `git apply --index` and commit its corresponding
message. The native observe-loop integration still needs this existing hosted test on iPhone 17e:

```sh
make generate
xcodebuild -project ChronoFlow.xcodeproj -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile -scheme ChronoFlow -configuration Debug \
  -destination 'platform=iOS Simulator,id=D788B715-AA0A-4B5A-882B-323E1F984769' \
  -testLanguage en -testRegion US -parallel-testing-enabled NO \
  -only-testing:AppTests/SessionLifecycleTests/testNativeCompositionObservesAndDetachesAccountsUsingOneKeychainStore test
```


## Phase 9c host verification (6 November 2026)

Task 1: `sh Scripts/host-tests.sh --filter 'LocalMutationsTests|OutboxFlusherTests'` passes
6 tests, including 11 failure-classification cases. Tests use file-backed temporary account pools
under this repository, scripted sources, injected dates/randomness, and no network or sleeps.
Covered: restart durability, transaction rollback, FIFO/dependency progress, unsupported parked
rows, receipt rollback/replay, supported local values, sensitive-key rejection, and final/transient
refusal metadata. Profile email changes need a password and remain online-only.

Defaults: syncFailure is a typed storage/event seam without UI (OQ 30 default assumed, confirm);
unsupported complete-trip/data-export/security rows remain parked with no producers (OQ 31 default
assumed, confirm). D19 backup exclusion remains inherited (OQ 26 default assumed, confirm); device
loss/restore loses unsent account changes. Shipping approval remains open.

Task 2: `sh Scripts/host-tests.sh --filter SyncTests` passes 22 tests across 6 suites
(including task 1). Full pull, pending protection, plan retention and check reconciliation are pure
host tests over GRDB and scripted mock sources. `synced_at` commits with account/settings/cards;
detail failures preserve it. A missing detail is tombstoned without scheduling a retry; later
explicit pulls may rediscover the card. No hosted UIKit/Keychain tests are needed for these services.

Task 3 and final checks:

- `sh Scripts/host-tests.sh`: **212 passed**, including **35 Sync tests** in 8 suites.
  The Sync suite also uses the persisted MockDataSource and an APIDataSource with a deny-by-default
  URLProtocol; it performs no network calls or real timer sleeps. Manual gates cover each source
  response, caller cancellation, parent epoch invalidation and a queued SQLite response write.
- `make lint`: passed.
- `make generators-check`: passed (7 TokenGen, 6 font/cache checks, 3 AssetGen tests); generated
  outputs remain unchanged.
- `python3 -I Tests/test_launch_simulators.py`: **21 passed**; Sync suites are classified as host-only.
- `python3 -I Tests/test_launch_resources.py`: **10 passed**.
- `git diff --check`: passed.

No new hosted AppTests are added: this phase needs neither UIKit nor Keychain, so there is no new
17e command. No xcodebuild, simulator or git commit was run. Existing 9a/9b hosted and hardware checks
remain open, as recorded in their sections; this does not replace those results.

SyncEngine owns one flight and coalesces requests into a rerun, debounces ordinary requests by
1 second with an injectable scheduler, and exposes immediate refresh and cancellation/drain. A
child SyncEpoch guards each flight through SQLite commit; invalidate its parent before detaching
the session. A canceled refresh cancels the shared flight; subsequent refreshes use a fresh child.
Result events carry only typed states, counts, sanitized refusals and relative retry delays.
The lifecycle owner in 9d will schedule exponential/retry-after retries from these results, wire
sign-in/activation/reconnect/outbox triggers, suspend verification pulls, and handle current-epoch
401 sign-out outside the engine task. This phase adds no UI, production composition or wipe handler.

Packaging: `build/commits/1.patch` through `3.patch` each contain their matching task tick and
Conventional Commit message in `messages.txt`. The first patch independently passes its 6 Sync
tests, and the first two patches together pass 22 Sync tests in a separate host checkout. Replay against HEAD with `git apply --index`
verified the index tree and every tracked file byte against the final worktree.


## Phase 9d: sync lifecycle, wipe and readiness (6 November 2026)

All three tasks are implemented without UI. SyncLifecycle in the pure Swift Sync target owns the
outbox-ID observation, injected path stream, retry scheduler and sanitized engine events. Open/sign-in,
scene activation and reconnect debounce through the same engine; committed outbox additions request
work, while acknowledgements/retry metadata do not form a feedback loop. Transient failures back off
1/2/4…300 seconds, successful pulls reset the series, and a larger retry-after deadline also constrains
explicit refresh. Offline waits for a trigger. Unverified accounts probe identity before protected work;
continuous SQLite gate observation lets a newly discovered verify gate release launch without a marker.
Background/disconnect stops the monitor, observers, timers and requests; activation resumes the current
session only. The future refresh API is NativeSessionController.refreshNow().

Sign-out shares SessionController's restore/accept queue and coalesces concurrent callers. A voluntary
flush returning pending rows yields needsConfirmation and leaves the session/rows intact; explicit discard
and current-epoch 401 wipe, with 401 skipping flush/logout. The old token is captured for logout only,
with an injected 3-second cancellation deadline. Teardown drains sync/observations, detaches the model,
routes Sign in, closes the pool and removes the entire account directory and session. The marker contains
only a validated account UUID, is namespace-scoped, backup-excluded and protected on iOS; it remains
until directory and credential cleanup succeed. Restore/accept retries it before opening any account.
An immutable session/epoch snapshot is unavailable during replacement, preventing activation from
recreating old-token work. Engine teardown releases its source and retained plan leases. Device ID,
language and appearance are outside the wipe. Mock fake-server persistence stays separate from the
account cache, as in 9b.

Ordinary Release uses CHRONOFLOW_READINESS=native and restores the selected data source's native
session. The Perf scheme now uses a separate Perf build configuration with
CHRONOFLOW_READINESS=signed-out; it constructs no account controller, SQLite store or data source.
Launch arguments cannot select this setting. Release still accepts only its existing ready-playback,
stall and Reduce Motion diagnostics; readiness overrides remain Debug-only. Configuration loading runs
on a detached worker after CATransaction.flush; account/Keychain/migration/observation work stays on
workers/actors. SessionLifecycleTests now drives the native service-configuration branch through an injected native-session
factory, independent of the hosted app's global session. Its literal cached/fresh/unverified fixtures exercise
StoredDataReadiness, assert first-commit ordering and off-main credential/open work, and suspend the real
account open while checking the overlay animations and MainActor heartbeat. The earlier ControllerReadiness
seam alone did not cover this production composition. Launch preserves
external session navigation while keeping the existing 2/8-second rules. No splash geometry, assets,
fonts, strings or Duo-specific behavior changed.

Original Phase 9d verification before review fixes:

- sh Scripts/host-tests.sh: **235 passed** (76 AppCore, 21 LocalStore, 41 Sync, 54 DataAccess,
  34 Launch, 8 DesignSystem, 1 Welcome), **23 new** compared with committed 9c.
- sh Scripts/host-tests.sh -c release: the same **235 passed**. New service tests use injected
  schedulers/gates, mock sources and inherited URLProtocol fixtures; no live network or real sleeps.
- make lint, make generate and make generators-check: passed (7 TokenGen, 6 font/cache, 3 AssetGen).
- python3 -I Tests/test_launch_simulators.py: **22 passed**; python3 -I Tests/test_launch_resources.py:
  **10 passed**. New pure suites are host-classified; hosted classes run only on 17e by default.
- SwiftPM --build-tests for arm64-apple-ios17.0-simulator: passed. Direct Swift 6/MainActor app module
  and app/hosted-test SIL compilation: **Debug and Release passed**. Compilation does not execute UIKit,
  Keychain, path-monitor callbacks or the render-server stall proof.

The original Phase 9d delivery used three patches. The review follow-up below supersedes those
build artifacts. No git commit, xcodebuild, simulator or live API request was run for that delivery.

The orchestrator runs these exact commands on **one iPhone 17e** after applying the patches. Each
new/changed hosted class has its own selector; ReleaseReadinessTests automatically selects the isolated
ReadinessRelease/Release build. Run make generate first.

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/SyncLifecycleTests"
make targeted DEVICES="17e" ONLY="AppTests/AccountWipeTests"
make targeted DEVICES="17e" ONLY="AppTests/SessionReadinessTests"
make targeted DEVICES="17e" ONLY="AppTests/LaunchConnectionTests"
make targeted DEVICES="17e" ONLY="AppTests/ReleaseReadinessTests"
```

To build each configuration once and run the selection together:

```sh
make targeted DEVICES="17e" ONLY="AppTests/SyncLifecycleTests AppTests/AccountWipeTests AppTests/SessionReadinessTests AppTests/LaunchConnectionTests AppTests/ReleaseReadinessTests AppTests/SessionLifecycleTests"
```

make check remains an orchestrator-only integrated check on 17e. **make duo is not needed** for 9d:
there is no Duo-specific change, and the user replaced Matrix S with host tests for this phase. No
seven-device matrix is requested. Physical-device locked/protected-data behavior, launch budgets and
the 500 ms render-server proof still require actual hardware/hosted execution; no measured result is claimed.

Defaults retained/assumed: OQ 7 (unknown at 8 seconds uses the existing signed-out fallback without
credential deletion), OQ 9 (native-only storage; RN migration deferred), OQ 24 (destination seams keep
ordinary Release non-shipping), OQ 26 (development backup exclusion; shipping confirmation open),
OQ 29 (needsConfirmation result only, explicit Verify exit may discard) and OQ 30 (typed store/sync
failures, no new UI). Each relevant task note records “OQ n default assumed, confirm”. Auth copy/design,
link delivery, Apple team/device proof and later feature/shipping OQs remain open; this phase does not
settle them.


### Phase 9d review follow-up

The review series applies to `3726b971c74e12c5a0c148e6e0c98e363fcd852a` on
`feat/phase-9d-session-lifecycle`, preserving the committed 9a–9d history and 9c review fixes.
`build/commits/messages.txt` maps `1.patch` through `10.patch` to Conventional Commit subjects.
Apply each numbered patch with `git apply --index` and commit with its matching subject. Each patch
contains its completed `plan.md` review task. An isolated index, object directory and worktree under
this repository verify sequential indexed application and exact equality with the resulting source tree.

The fixes preserve per-epoch retry state across background pauses, seed failures from durable outbox
attempts, and allow fresh triggers to replace exponential waits. Server retry-after is tracked separately
from local retry delays and survives coalesced engine flights. Voluntary sign-out checks the pending count
before flushing and fails safely when the account database is closed. Explicit sign-out upgrades a queued
401 flight and supersedes a pending accept. If that flight becomes stale, the replacement account uses
the explicit caller's discard/force intent; it cannot inherit the old account's forced discard. A failed
forced marker write remains pending and is retried before native activation resumes sync. Session
readiness no longer awaits sync data-source or path startup.

The readiness and trigger tests have independent literal oracles: cached/fresh/unverified account fixtures
expect explicit gates and stored-data booleans; lifecycle tests expect explicit API call sequences,
retry delays and start/stop sequences. They do not compute expectations with the production classifier.
The native launch test uses `serviceConfigurationFactory` and `nativeSessionFactory`, checks exactly
`[.sceneConnect, .overlayFirstCommit]` before service construction, and asserts the coordinator owns
`StoredDataReadiness`. Its credential reader and suspended account opener assert off-main execution.
After release, the opener forwards to the real SQLite open/migration and readiness repository. While
suspended, the overlay remains mounted with its animations and a MainActor heartbeat completes.
The scene test now observes real `NativeSessionController` / `SessionSync` source creation, path startup,
path shutdown and timer cancellation. A reconnect with an existing Today route resumes the same epoch
and has exactly one first-commit event across both connections.

Review validation:

- `sh Scripts/host-tests.sh`: **254 passed** (80 AppCore, 56 Sync, 21 LocalStore, 54 DataAccess,
  34 Launch, 8 DesignSystem, 1 Welcome).
- `sh Scripts/host-tests.sh -c release`: **254 passed**, with the same suites.
- Red/green checks in `build/commits/*before.log` / `*after.log` cover empty-outbox flushes,
  explicit/stale 401 races, replacement pending rows, lost retry state and exponent seeding,
  ignored triggers, failed forced-cleanup retry, awaited sync startup, missing path reconnect triggering
  and offline retry spinning. The coverage findings are checked with behavior mutations: the original
  code had missing proofs rather than observed runtime failures. Each corresponding fixed test passes.
- `make lint`: passed. `python3 -I Tests/test_launch_simulators.py`: **22 passed**;
  `python3 -I Tests/test_launch_resources.py`: **10 passed**. The new portable startup suite is
  classified as host-only.
- SwiftPM `--build-tests` for `arm64-apple-ios17.0-simulator`: passed. Direct Swift 6/MainActor
  module and SIL compilation of the app and all hosted tests: **Debug and Release passed**.
  These checks use repo-local caches and invoke no xcodebuild or simulator.

Hosted runtime tests, including the closed-store data-loss regression and production first-flush proof,
are **not executed in this sandbox**. The compile results do not establish UIKit/render-server timing,
Keychain behavior or the hosted tests' red/green runtime outcome. The following commands run the
changed hosted suites on the pinned **iPhone 17e / iOS 27.2**. LaunchConnectionTests and isolated
ReleaseReadinessTests also cover the affected composition. Generate the project before running them.

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/SessionLifecycleTests"
make targeted DEVICES="17e" ONLY="AppTests/SyncLifecycleTests"
make targeted DEVICES="17e" ONLY="AppTests/SessionReadinessTests"
make targeted DEVICES="17e" ONLY="AppTests/AccountWipeTests"
make targeted DEVICES="17e" ONLY="AppTests/LaunchConnectionTests"
make targeted DEVICES="17e" ONLY="AppTests/ReleaseReadinessTests"
```


## Test-tier port onto Phase 9a–9d (6 November 2026)

Eight patches preserve the source tier commits one-to-one on reviewed stack tip `f373dde`.
The standalone PNG-reference commit `ff50e24` is excluded. Only the source commits' 278 old
reference deletions are included; no replacement PNG is generated or changed. Apply that reference
commit separately before running profile comparison or check.

All 42 AppCore/LocalStore/DataAccess/Sync suites remain host-only. The eight hosted service suites
stay in logic; LaunchConnectionTests keeps its live-lifecycle policy and ReleaseReadinessTests its
isolated Release policy. Check runs all ten on 17e. The compatibility host script uses the shared
SwiftPM runner, so quick includes the complete store, data-access and sync package tests.
Matrix S/A now state the tier decision directly. Phase implementation and review results above
remain historical; the port does not claim new simulator or device acceptance.

Port validation: `make quick` passes in **21.76 s** with strict lint, **266 package tests**
(262 Swift Testing + 4 XCTest), **7 TokenGen**, **3 AssetGen**, **51 runner fixtures** and
**10 resource checks**. The package totals include **80 AppCore, 21 LocalStore, 54 DataAccess and
56 Sync tests**. `make generators-check` passes, including all **6 font/cache fixtures**.
Runner fixtures assert each Phase 9a–9d hosted selector appears exactly once in check's actual
17e test commands, with the intended Debug/Release configuration and no profile classification.
No xcodebuild, simulator, recording or git commit ran for this port.

After applying the patches and the separate reference commit, run outside the sandbox:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/AccountStorageLifecycleTests AppTests/SessionLifecycleTests AppTests/KeychainSessionStoreTests AppTests/DataSourceBuildSettingTests AppTests/DataSourceFactoryHostedTests AppTests/SyncLifecycleTests AppTests/AccountWipeTests AppTests/SessionReadinessTests AppTests/LaunchConnectionTests"
make targeted DEVICES="17e" ONLY="AppTests/ReleaseReadinessTests"
make check
```

## Phase 10a: native Auth and passkey sign-in (6 November 2026)

See `Docs/auth-gate.md` for implementation, defaults, missing Dutch rows, snapshot helper integration
and open acceptance. The original early-stack verification below predates 9c/9d; the integrated stack retains both phases.
No simulator execution or Auth reference recording is claimed for this port.
Original early-stack host verification: 185 SwiftPM tests (21 Auth) pass; strict lint, XcodeGen, generator freshness
(8 TokenGen / 4 AssetGen / 6 font/cache), 3 signing-guard, 9 resource and 22 runner tests pass.
SwiftPM package/test compilation for the iOS 17 simulator floor and direct Swift 6/MainActor
app/hosted/UI module compilation pass. No UIKit test has executed in this sandbox.

Run on the one pinned 17e after applying patches:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/AuthControlTests AppTests/AuthLayoutTests AppTests/SessionReadinessTests AppUITests/SignInTests AppUITests/AuthAuditTests"
```

Record only after review, then compare (the runner records and compares in that first command):

```sh
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests"
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests"
```

The Auth host suites run in quick; controls/layout and UI are logic suites in check, with the
appearance-switching audit isolated serially. AuthSnapshotTests uses the profiles policy and SNAPSHOTS.
Its SnapshotContainer windows reuse the shared profile fixtures, exact four insets and CPU layer
capture used by Welcome. Full SE/17e/Duo/Pro Max and compact 17/Air/18 Pro categories remain covered,
alongside the zero-inset board and AX5 cap equality. No Auth reference PNGs are included.
For explicit xcodebuild recording, set TEST_RUNNER_SNAPSHOT_RECORD=1 and select only
AppTests/AuthSnapshotTests. Normal comparisons never record implicitly. make host-tests runs all Auth
models/mapping/catalog/encoding and mock-provider logic on macOS.

For later physical passkey verification, supply a confirmed team in ignored Local.xcconfig and build
the app with -scheme ChronoFlow -configuration DeviceSigned -destination 'generic/platform=iOS'.
This config adds webcredentials:app.chronoflow.net only on iphoneos for the app target; the signing
guard requires an actual certificate/team. Debug/Release/simulator/ad-hoc builds have no association.
AASA deployment/CDN/team/real-device checks remain open.

## Phase 10a review fixes after the Phase 9b rebase — 6 November 2026

The full package host suite passed immediately after the rebase: 198 tests. Only the backend's
`These sign-in details don't match our records.` maps to the credentials banner; the old Laravel key
now has a server-fallback regression. The rebased mock's `password_confirmation` mapping is retained.

Auth controls now tint template glyphs with their button foreground, place the token-sized busy
spinner first in the centered content, suppress empty-field placeholders, and draw the one-point
field border plus its two-point outset focus ring. Error glyphs are centered. Forgot/Create fill the
card width when both fit and use generated line height with underlined WelcomeText. Hosted
AuthControlTests assert glyph ink in both appearances, spinner geometry, empty native fields,
focus-ring pixels/error alignment and late passkey anchor fallbacks. AuthLayoutTests assert link
edges on Pro Max/Duo and line height under a narrow Dutch xxLarge proposal.

Auth token generation reads uniquely selected board declarations and component utilities, checks
shared values for disagreement, and derives typography from the relevant element/named token.
Source mutations cover repeated gap/height declarations, metrics, focus/opacity utilities, font
family/weight/size/line height/tracking. Committed token values are numerically unchanged.

SignInModel routes after successful session acceptance even when the caller has been canceled.
The real SessionController already preserves committed acceptance after the rebase; a gated-sync
host regression verifies credentials, presence, routing and secret clearing for verified/unverified
accounts. Stale passkey anchor callbacks return the captured/current window or an empty anchor.

The strict Auth audit retains its original type set and now adds identifier, label, type, language,
appearance and scroll stage to failure messages, console output and retained attachments. Its issue
handler always returns false; no Auth contrast exemptions were added. Removing the system
placeholders and correcting the key foreground address real defects, but identifying the elements
behind the supplied 24 failures still requires the hosted rerun below.

TokenGen computes sRGB relative-luminance contrast from tokens.json (unrounded color values):

| Pair | Light | Dark |
|---|---:|---:|
| `primary-foreground` / `primary` (key and passkey label) | 12.2052:1 | 9.4892:1 |
| `muted-foreground` / `card` (divider text) | 11.6159:1 | 7.7103:1 |
| `foreground` / `card` (Forgot) | 17.1478:1 | 14.9195:1 |
| `dawn-text` / `card` (Create) | 5.4441:1 | 9.2888:1 |
| `input` / `card` (empty field boundary, outline exterior) | 1.5076:1 | 1.5051:1 |
| `input` / `background` (outline interior) | 1.4243:1 | 1.6222:1 |
| `border` / `card` (decorative divider lines) | 1.4140:1 | 1.3951:1 |

The border pairs are board properties, accepted, OQ 33 (user 2026-11-06), with their colors kept
exactly as drawn. They were not the audit's failing elements. Text contrast checks remain strict;
decorative divider lines are reported separately from passing text. RN keeps these values, and
the web's P8-D16 scope is WCAG 1.4.3 text contrast only (`tokens.json:167`: “Kept exact, flagged”).

Final host verification: **200 package tests (23 Auth), 9 TokenGen, 4 AssetGen, 6 font/cache,
3 signing-guard, 10 resource and 22 runner tests pass**; strict lint and generated-output freshness
pass. SwiftPM Auth/DataAccess/Launch compilation and direct Swift 6/MainActor type checking of
AuthControlTests/AuthLayoutTests/AuthSnapshotTests and AuthAuditTests pass at the iOS 17 simulator
floor. Hosted execution and screenshot review remained open in that round; no references were recorded.
The board border/footer values are now accepted, OQ 33 (user 2026-11-06).
The rebase's two explicit xcodebuild recipes above are preserved as separate complete shell blocks.

Run the audit first, then the remaining requested suites on the same build:

```sh
make targeted DEVICES="17e" ONLY="AppUITests/AuthAuditTests"
make targeted DEVICES="17e" ONLY="AppTests/AuthControlTests AppTests/AuthLayoutTests AppUITests/SignInTests" REUSE_BUILD=1
```

The second command is still useful if the first fails: each issue now supplies actionable details in
`build/test-results/17e/Debug-compare.xcresult`. This runner replaces that result on each pass; retain
the audit bundle/log before running the second command when diagnosing a failure.

## Phase 10a second fix round — 6 November 2026

The user's hosted 17e rerun passes AuthLayoutTests and SignInTests. AuthControlTests collected
its four global measurements during LaunchTestHost's initial 390-point scene layout, before
AuthTestHost resized the fixture to 375 points. Its count-only wait could therefore skip layout
entirely and compare the old 195-point centre with the new 187.5-point window centre. AuthButton's
inline spinner/glyph/label HStack already matches the board. The repaired test forces layout,
waits for stable resized geometry (without waiting for animated spinner pixels), asserts the
button width, and compares group/button frames in the same global coordinate space.

All 24 audit failures identify only `sign-in.guest`, the AuthSignIn footer at line 59. Native uses
exactly the board's `skyCopy` text and `skyCopyBackground` capsule, Figtree 500 at 14/20. Both
appearances retain the generated pill alpha of 0.9. The table includes compositing that pill
in encoded Display P3 over the generated sky ramp, followed by conversion to linear sRGB for
WCAG relative luminance. The board footer centre is y = 764 on its 812-point sky; the full-ramp
ranges cover other window heights and scroll positions without assuming the board's geometry.

| Pair | Light | Dark |
|---|---:|---:|
| Text / composited pill, board footer centre | 14.9260:1 | 15.0953:1 |
| Composited pill / sky, board footer centre | 2.3128:1 | 2.9450:1 |
| Text / composited pill, full sky range | 13.4635–15.0882:1 | 14.9473–16.1298:1 |
| Composited pill / sky, full sky range | 2.0004–10.7434:1 | 1.0001–3.4997:1 |

Text passes 4.5:1 everywhere. The board-centre boundary is below 3:1 in both appearances.
Following the user's instruction and Welcome's five explicit board pairs (including welcome.plan's
pill/sky precedent), Auth now allows only `(sign-in.guest, .contrast)`. It retains the issue's
identifier, label, type, language, appearance and stage in console/attachments and records whether
the pair was allowed. Nil/unknown identifiers, all other elements, combined audit types and every
non-contrast issue still fail. No partial-visibility exception was added. The footer and input/border
values are accepted, OQ 33 (user 2026-11-06). Keep this exact allow-list and strict text ratio guards;
rendered visual review remains open.

AuthBoardContrastTests pins both appearances' generated text/pill/sky RGBA values, alpha, label
font/size/leading and board-centre/full-ramp ratios. TokenGen checks the board's footer declarations
and generated freshness. AuthControlTests adds native pill/ink pixel checks in en/nl and light/dark.
A deliberate light-pill alpha mutation from 0.90 to 0.89 fails the pinned RGBA and ratio guards;
restoring the generated file passes. The simulator runner classifies the new guard as 17e logic.
All 201 package host tests, 10 TokenGen tests, 22 runner checks and 10 resource checks pass,
as do strict lint and direct iOS 17 type checks of the hosted/UI tests and new ratio guard.
CoreSimulator is inaccessible in this sandbox; revised UIKit/audit execution
and visual acceptance remain open. No production colors or snapshot references changed.

Apply the two ordered patches in `build/commits` and commit each corresponding line of
`messages.txt`. `replay.txt` records verification against the starting HEAD. Then run:

```sh
make generate
make targeted DEVICES="17e" ONLY="DesignSystemTests/AuthBoardContrastTests AppTests/AuthControlTests AppTests/AuthLayoutTests AppUITests/SignInTests AppUITests/AuthAuditTests"
```

This builds once and keeps the guard, native controls and all 24 audits in one result bundle:
`build/test-results/17e/Debug-compare.xcresult`. To repeat the same selection after an unchanged build,
add `REUSE_BUILD=1`. No reference recording or seven-device matrix is needed for these patches.

## Integrated Phase 10a port — 6 November 2026

This record supersedes the early-stack composition and patch-count instructions above while retaining
both histories. Twelve patches preserve the twelve source commit messages on fffa67d (Phase 9a–9d,
test tiers and recorded Launch/Welcome references). AuthSessionServices receives the scene's existing
NativeSessionController; it creates no second lifecycle composition. Password and passkey acceptance
use its SessionController and SQLite readiness gate. Unverified results call AppDelegate.verificationRequired;
current terms precede walkthrough, then the Today seam. SessionReadinessTests covers both methods across
all four gates, with and without cancellation after credential commit, followed by restore and sign-out.
Those 16 native integration scenarios are type-checked; hosted execution remains for the commands below.

AuthTests suites use the host policy in quick. AuthControlTests/AuthLayoutTests are hosted logic;
AuthBoardContrastTests remains logic and is explicitly included in check's UIKit selection.
SignInTests is UI logic; AuthAuditTests is registered for the serial device-appearance pass.
AuthSnapshotTests uses profiles and SNAPSHOTS, with SnapshotContainer windows, shared full/compact
profile fixtures, exact safe-area insets, window reuse and CPU layer capture. The zero-inset board and
AX5 cap checks remain. Reference names describe the fixture, never the executing simulator.
No Auth PNGs are supplied; existing recorded Launch/Welcome references are unchanged.

Port verification: make quick passes with 286 package host tests (23 Auth), 10 TokenGen, 4 AssetGen,
3 signing guards, 10 resource checks and 53 runner fixtures. Strict lint and generator freshness pass;
fonts verify all 10 static faces and all 6 font/cache tests pass. Every package/test target compiles for
arm64 iOS 17 simulator. Direct Swift 6/MainActor checks pass for the app and all hosted AppTests in
Debug and Release, and all AppUITests in Debug. These are compilation checks, not UIKit execution.
No xcodebuild, simulator, git commit or reference recording ran. OQ 23/24/28/30/33 defaults and records,
including the exact (sign-in.guest, .contrast) allow-list, remain as in the source.

Run the integrated Auth selection on 17e, then record only after review:

```sh
make generate
make targeted DEVICES="17e" ONLY="DesignSystemTests/AuthBoardContrastTests AppTests/AuthControlTests AppTests/AuthLayoutTests AppTests/SessionReadinessTests AppUITests/SignInTests AppUITests/AuthAuditTests"
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests"
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests"
```

The default two-worker Debug run writes logic to Debug-compare.xcresult and appearance audits to
Debug-serial.xcresult under build/test-results/17e. Recording runs serially, then compares in a fresh
test process; the final command supplies another independent comparison. All default/CI flows remain
single-simulator; no seven-device matrix or Duo-specific runtime run is introduced.

## Phase 10a port fix round — 6 November 2026

The user reports hosted passes for AuthBoardContrastTests, AuthControlTests, AuthLayoutTests,
SignInTests and serial AuthAuditTests. SessionReadinessTests failed the canceled post-commit
verify, terms and walkthrough cases: cancellation ends the gate's AsyncStream read immediately,
so it falls back to `.app`. NativeSessionController now delegates to the shared
StoredDataReadiness post-accept router, which reads the gate in an unstructured task and re-checks
the active session and epoch before navigating or invoking verification. Launch readiness retains
its existing cancellation behavior.

Host SignInModelTests calls that production router, ignoring the model's suggested route just as
AuthSessionServices does. It exercises password/passkey × four stored gates × canceled/uncanceled
requests, asserts cancellation is already set before routing, and checks verification epochs.
Four delayed-read/sign-out scenarios retain stale-session protection. Removing the unstructured
task reproduces the reported Today misroutes for both methods on the host; restoring it passes.

After applying the fix, rerun the full hosted SessionReadinessTests suite on the pinned 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/SessionReadinessTests"
```

These commands remain pending outside this sandbox. No simulator or xcodebuild execution is
claimed for this round.

The auth inventory now follows the **lean snapshot set, user 2026-11-07** (superseding the
original board/full-profile set): every implemented state on 17e/SE/Duo in en/nl × light/dark at
`large`, plus one `xxLarge` reference per state on 17e/en/light. Sign in has **52**, Two-factor **104**,
and Forgot **78** references. Each state has 13 references. All other device sizes retain Mac
geometry and hosted layout/guard coverage. AX5/xxLarge pixel equality runs once per screen.
Splash/Welcome profile coverage is unchanged. Exact filename guards reject stale extras and partial
sets; an entirely unrecorded suite remains pending. Compare mode never writes references.
After reviewing and recording the references, compare and run the commit gate:

```sh
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests"
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests"
make check
```

The recording command builds, records serially and compares in a fresh test process; the next
command repeats comparison with the same build. The inventory guard permits the pending state,
but hosted Auth comparison in `make check` needs the references. The user records after this
round, before closing the remaining acceptance task. All commands use one 17e; audits in
`make check` retain their serial appearance pass.

Round verification: `make quick` passes, including 24 Auth host tests, 53 runner fixtures,
10 resource checks, 3 signing checks, the remaining package/generator suites and strict lint.
Inventory probes accept absent/empty/complete Auth sets and reject partial/stale/suffix-drift
sets. Two ordered patches and plain Conventional Commit subjects are in `build/commits`;
`replay.txt` records application against the starting HEAD. No git commits or reference
recording were performed in this worktree.

### Phase 10b first task: two-factor code and recovery (2026-11-07)

Only the first 10b task is implemented. TwoFactorView uses the existing AuthScreen, AuthField,
AuthButton, AuthBanner and measured keyboard reveal. Code entry is a native oneTimeCode number
pad, limited to six ASCII digits with no auto-submit; recovery uses the regular keyboard and Go.
Changing mode clears input and feedback. Back/disappearance discards input and the memory-only
challenge, cancels the view request and rejects late responses. Missing challenges return to Sign in.
Every attempt clears input, and the shared form lock covers tap and Return.

The API's completion action uses `code` and `recovery_code`; these field messages are localized
using the resolved English/Dutch values. The board's example 30-second text is retained in the
catalog and board export, but actual failures display their backend key. Expired and five-failure
challenges return the existing rejected-code field message, so they use that designed field-error
pattern. There is no separate expiry screen. OQ 23/30 defaults remain kept (user informed): no
offline banner, submit stays enabled; hidden/unknown-field failures use the designed server banner.
Storage failures stay typed service seams. No new state presentation is added.

SignInModel owns the two-factor model and sends its success through the same acceptance method
as password sign-in, using the scene's NativeSessionController and SQLite gate. The native
SessionReadinessTests now cover password, passkey and two-factor through all four stored gates,
with and without cancellation after credential commit. The Debug mock account is
`twofactor@example.com` / `password`, with `123456` or recovery `AbCdEf1234-GhIjKl5678`.
Its seeded accepted terms and unseen walkthrough route success to the existing walkthrough seam.

TwoFactorModelTests cover missing/wrong/latest codes, input filtering without submission, recovery
success/reuse, expiry/exhaustion, throttling/server/offline, hidden-field mapping, localized messages
and deduplicated announcements, toggles, cancellation/back, double submission and storage boundaries.
The keyboard suite measures the focused field and Verify against the real keyboard/window/scroll
frames in both modes and languages at xxLarge, before and after field/server errors. Both auth
helpers and the interactive-dismiss test now require a visible software keyboard inside the window;
the off-screen fallback introduced at b56c328 was based on a minimized keyboard, not verified Duo
geometry. The interactive-dismiss drag from 8d92f8b is retained. Earlier keyboard passes do not
establish OQ 32 acceptance; the user's reruns on 17e, SE and Duo remain pending. A failure to fit
remains OQ 32; do not change the layout or shrink the root cap to pass it.

Fix round 3 validation: `make quick` passes, including 57 runner fixtures and four UIWaitTests.
All AppUITests type-check for the iOS 17 simulator target. No simulator UI execution is claimed
for this fix; the user will run the three keyboard suites on 17e, SE and Duo.

Debug-only `-cf.isolatedMockServer` gives UI launches a shared in-memory mock server for the auth
and native sync sources, preventing cross-test throttles and recovery consumption. Debug mock-only
`-cf.twoFactorServerFailure` injects one completion failure for keyboard coverage. Neither test seam
changes Release API behavior. The normal Debug mock keeps its file-backed server.

TwoFactorControlTests/TwoFactorLayoutTests are hosted logic, TwoFactorTests is UI logic,
TwoFactorKeyboardTests is a runtime suite and TwoFactorSnapshotTests uses profiles. All are
registered in the runner; targeted recording selects only the new suite. Snapshots cover both modes
and none/field-error/attempts/server states in the lean auth set:
104 references under `AppTests/__Snapshots__/Auth/TwoFactor`. One AX5/xxLarge comparison
verifies the root cap; all D1c sizes remain covered by geometry/layout guards. Fourteen board HTML exports are under `_design/frames/auth/two-factor-*`;
`node Scripts/export-auth-boards.cjs` regenerates them without changing the read-only canvas.

Verification: `make quick` passes, including 54 runner fixtures, 10 resource checks and 3 signing
checks. SwiftPM package/test compilation for the iOS 17 simulator target, direct Debug/Release app
module/SIL compilation, and hosted/UI test type checks pass. Compilation does not execute UIKit.
No xcodebuild, simulator, reference recording or seven-simulator matrix was run. Hosted execution,
snapshot recording/comparison/visual acceptance and this form's OQ 32 SE/Duo checks remain pending
the user's runs. Phase 10b's second task, including its complete auth gate/audit report, stays open.

Run these commands from this repository, in order:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/AuthControlTests AppTests/AuthLayoutTests AppTests/TwoFactorControlTests AppTests/TwoFactorLayoutTests AppTests/SessionReadinessTests AppUITests/TwoFactorTests AppUITests/TwoFactorKeyboardTests"
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/TwoFactorSnapshotTests"
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/TwoFactorSnapshotTests AppTests/AuthSnapshotTests"
make targeted DEVICES="se duo" ONLY="AppUITests/TwoFactorKeyboardTests"
```

Recording runs serially on 17e and compares in a fresh test process. Review the new references
against the exported boards; the recording itself is not visual acceptance. The SE/Duo suite keeps
frame logs and screenshots as attachments under `build/test-results/<alias>/`. No full matrix or
`make duo` is needed for this task; the explicit `se duo` keyboard selection is the OQ 32 check.


### Phase 10b task 2: auth acceptance runner and guards (2026-11-07)

This section supersedes the task-1 pending-results notes above. Task 1 is accepted at db09e29:
1,792 Two-factor references are recorded, Auth/TwoFactor comparison passes, and visible-keyboard
acceptance on 17e/SE/Duo is settled at 9505993 (OQ 32). Task 2 adds acceptance coverage; its new
simulator and Two-factor visual results remain open in `Docs/auth-gate.md`. Phases 6–8 stay open.
No seven-simulator matrix is required or requested.

`make check` selects all Auth/TwoFactor controls/layout/guard suites, both profile-snapshot suites,
SignInTests, TwoFactorTests, AuthSessionTests, AuthAuditTests and both keyboard suites exactly once
on 17e, retaining launch/Welcome/service coverage and isolated Release readiness. AuthAuditTests
(device appearance) and AuthSessionTests (background/foreground) join the serial pass. The opt-in
`make duo` includes the auth UI/keyboard/guard suites against Duo's separate runtime, without
repeating profile-reference rendering. `make snapshots` includes the auth capture/scroll guard.
Every path still runs the per-device AutomaticMinimizationEnabled=false preparation after bootstatus.

Auth selections fail if a test is failed, skipped, expected-failure or missing from results; a
record/build/test failure does not hide the later comparison, audit or Release pass. Recording is
explicit, serial and 17e-only. Guard/UI/Release suites never receive the record environment, even
when inherited TEST_RUNNER_SNAPSHOT_RECORD is set. The host inventory pins all 52 Sign in,
104 Two-factor and 78 Forgot filenames, not just their counts (lean set, user 2026-11-07). Compare mode never writes references.

AuthSnapshotCapture has Mac mutation tests and validates both snapshot and AX5 capture paths
before recording/comparison. The hosted AuthSnapshotGuardTests scrolls every control into full
containment across all seven profiles, both languages/appearances, default/xxLarge and an extra
asymmetric Duo fixture. Initial card overflow is intentional scrolling, not a reason to record a
clipped control as accepted. Actual keyboard frames remain covered by the two keyboard UI suites.

AuthSessionTests uses UUID-scoped Debug mock server/account storage and Keychain credentials:
`CF_AUTH_TEST_ID=<UUID>`, optionally `CF_AUTH_TEST_OFFLINE=1`, `CF_AUTH_TEST_UNVERIFIED=1` and
`CF_AUTH_TEST_WALKTHROUGH_SEEN=1`. Invalid/missing IDs leave the ordinary app unchanged; API
selection and Release/Perf ignore these test settings. Shared mock values compile directly into
AppUITests through project.yml; the new UI files use its existing directory glob. The route-name
text's test-only `cached` accessibility value comes from SQLite synced_at observation. Tapping
that same diagnostic in these launches invokes the real controller sign-out/discard/wipe path.
No extra UI, password prefill, real network call or Release seed is introduced. Each test UUID
survives process relaunch so offline cached restore exercises actual persistence. AccountWipeTests
supplies the exact file/Keychain deletion assertions alongside UI sign-out/relaunch coverage.

Run from this worktree after applying the implementation commit/patch:

```sh
make generate
make check
make duo
```

The first command regenerates the ignored project; no xcodeproj is committed. The check gate
already includes all new suites and all seven D1c profile renders on 17e. The third command is the
user-requested opt-in Duo spot check, not a seven-runtime gate. No clean, reboot or recording is
needed for these changes. Send the full failing selector, log and xcresult summary if any fail;
logs/results remain under `build/test-results/17e/` and `build/test-results/duo/`.

For focused diagnosis after an unchanged successful build-for-testing:

```sh
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotGuardTests AppTests/AuthSnapshotTests AppTests/TwoFactorSnapshotTests AppTests/AccountWipeTests AppUITests/AuthSessionTests AppUITests/AuthAuditTests"
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppUITests/SignInKeyboardTests AppUITests/TwoFactorKeyboardTests"
make auth-board-pngs
```

The board command writes browser exports under ignored `build/board-png/`. Review every
`two-factor-{code,recovery}-<state>-<light,dark>.png` alongside the corresponding
`AppTests/__Snapshots__/Auth/TwoFactor/board-<light,dark>-en-large-<code,recovery>-<state>.png`.
Board `field` maps to native `fieldError`; the recovery error uses the shared designed Field state
rather than an invented board. No Two-factor browser PNGs are available in this sandbox, so that
side-by-side acceptance stays open for the user's host. Existing Sign in visual acceptance stands.
There are no changed reference PNGs in task 2. If a separately reviewed visual change needs recording:

```sh
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests AppTests/TwoFactorSnapshotTests"
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/AuthSnapshotTests AppTests/TwoFactorSnapshotTests"
```

Host verification for task 2: `make quick`, `make generate` and `make generators-check` pass.
SwiftPM runs 316 package tests, 10 TokenGen and 4 AssetGen tests; signing/resource checks run
3/10 fixtures, and all 6 font/cache checks pass. The 62 runner fixtures cover
suite selection, failure continuation, skipped/missing auth tests, record isolation and per-device
keyboard preparation. Capture mutation and shared-mock offline/verification/walkthrough-persistence
regressions pass in SwiftPM. Direct Swift 6 compilation targets arm64-apple-ios17.0-simulator,
with Debug/Release DataAccess/app modules, app SIL, all hosted tests and Debug UI tests; it invokes
swiftc only. These checks do not execute UIKit, audits, reference comparisons, or device passkeys.
Local logs: `build/phase-10b-{quick,generate,typecheck}.log`.


## Phase 10b task 2 — fix round 1 (7 November 2026)

The user's check gate reports 1,919.8 seconds in the simulator runner (`build/rerun/check.log`),
with every suite passing except recovery AuthSessionTests and strict subtitle AuthAuditTests.
The separate targeted rerun repeats those two failures. The user's Duo run passed 108 cases,
last RootNavigationTests, then stalled until their 40-minute timeout. No revised runtime pass is
claimed here; CoreSimulator connections are denied in this sandbox.

Auth helpers now select `sign-in.scroll` or `two-factor.scroll`, including shared back controls;
no arbitrary first matching auth scroll remains. UIWindow's Debug safe-area diagnostic gives UI
helpers the live rectangle from all four insets; keyboard intersection further clips it. Hosted
scroll guards use each fixture's four insets and test ink in the revealed element's frame. Passkey
has an AuthElement/measurement, so it participates in horizontal capture and scroll/ink guards.
The offline relaunch requires cached data plus a real completed sync result of offline; an online
relaunch cannot pass that assertion. A hosted positive/negative launch-flag test covers both mock
construction paths. No customer copy, token, layout value or committed PNG changes.

All **80 failing subtitle crops** in the saved serial xcresult were exported and measured without
running the app. Per-line minima remain above 4.5:1: Two-factor default is 10.8872 / 10.6966 light
and 15.7349 / 15.5897 dark; xxLarge Two-factor and Dutch Sign in are 10.8559 / 10.4839 light and
15.6097 / 15.4609 dark. All saved stages/modes agree. The sky remains dark behind the text.
See [auth-subtitle-contrast.md](auth-subtitle-contrast.md) for method, static board/profile evidence
and limits. This does not establish a failing board value or justify another contrast exemption.
AuthSubtitleContrastTests is a hosted board/17e diagnostic for all audited language/appearance/
size/mode contexts and reveal positions; it also checks full-window gradient placement and fails
on missing ink or any line below 4.5. The strict system audit remains enabled and unresolved.

The saved runner suite durations explain the long gate (sum of case time, **not additive wall
stages**, because two workers overlap work):

| Work | Saved test seconds |
| --- | ---: |
| TwoFactorSnapshotTests | 580.69 |
| AuthSnapshotTests | 321.69 |
| AuthAuditTests (serial) | 515.52 |
| TwoFactorKeyboardTests | 183.30 |
| SignInKeyboardTests | 111.10 |
| AuthSnapshotGuardTests | 179.53 |
| AuthSessionTests (serial) | 103.46 |
| WelcomeSnapshotTests | 70.18 |

Auth profile capture alone accounts for **902.38 test seconds**; keyboard suites add **294.40**.
The latest targeted serial pass takes **646.609 wall seconds**, of which about 619 seconds is
audit/session cases. The latest targeted guard pass takes **218.911 wall seconds**, including
179.534 seconds in its test. Isolated Release takes **14.898 wall seconds**. The original full
Debug-compare log was replaced by the targeted guard run; `timings.json` merges suite samples
across runs, and its stored 180.994-second device wall is an older successful targeted sample,
not the failed full gate. Build/preparation/worker-startup contributions cannot be separated exactly
from these retained data. The runner's 1,919.8 seconds exclude make's preceding host/generator
steps. No tier restructuring or new speed claim is made.

`make duo` now selects exactly DeviceGeometrySmokeTests, LaunchHandOffTests, WelcomeHandOverTests,
LaunchToWelcomeTests, SignInKeyboardTests, TwoFactorKeyboardTests, SignInTests and TwoFactorTests.
It resolves the same separate Duo runtime. It performs no profile, full audit/session, service or
Release gate. Its per-test-run overall timeout remains **600 seconds**; other test passes now use
the **600-second inactivity / 3,600-second overall** policy documented in Test tiers above.
`TEST_RUN_TIMEOUT=<seconds>` overrides the overall cap; `TEST_RUN_IDLE_TIMEOUT=<seconds>` overrides
inactivity. On timeout the runner terminates the process
group, escalates to kill after at most five seconds, retains the log, fails selected suites and
stops subsequent passes for that destination. Timeout/selection fixtures use temporary directories.
An initial timeout fixture accidentally removed Duo's ignored Debug-compare log/xcresult; it was
corrected before final verification. The separate `build/rerun/duo.log`, saved timings and all
committed PNGs remain intact.

Host verification: `make quick` passes (318 package tests, 10 TokenGen, 4 AssetGen, 3 signing,
10 resource and 64 runner fixtures), including per-element ink and rendered-contrast sampler
regressions. Direct iOS 17 Debug/Release app module/SIL and hosted/UI test compilation passes;
these checks do not execute UIKit. Logs are `build/phase-10b-fix-{quick,typecheck}.log`. Git index
mutation is blocked by `index.lock` permissions; the requested ordered atomic patches and subjects
are delivered under `build/commits/`.

Run without recording, after applying the patches:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/AuthSubtitleContrastTests AppTests/AuthSnapshotGuardTests AppTests/DataSourceFactoryHostedTests AppUITests/AuthSessionTests AppUITests/AuthAuditTests"
make check
make duo
```

The focused diagnostic writes per-line frames, measured ink, ratios and scroll offsets to
`build/test-results/17e/Debug-compare.log`. Audit/session results stay in Debug-serial. Read the
ratio report before deciding whether the strict system audit is a false positive. If a board-
matching rendered line actually fails 4.5:1, add a design Open question with the measurements and
no proposed default; do not alter tokens or widen OQ 33. The existing Two-factor side-by-side
visual review and device-only passkey checks remain open; task 2 stays unticked.


## Phase 10b task 2 — fix round 2 (7 November 2026)

The user's round-1 `make check` passes every suite except 80 subtitle contrast audit results;
`make duo` completes in 404 seconds, with only the keyboard-open mode-toggle reveal assertion
failing. The user's 2026-11-07 measured subtitle decision is recorded in OQ 33, Matrix A and
[auth-subtitle-contrast.md](auth-subtitle-contrast.md). AuthAuditTests measures the source screenshot
inside each eligible issue handler and fails on unavailable/incomplete or below-4.5:1 measurements.
The guest pair remains the only unconditional allow-list entry.

Duo's saved synthesized gestures start at (233, 439), below the visible keyboard's y=414 top edge.
AuthUIFlow now computes drag endpoints inside its live four-inset/keyboard-safe viewport, using
stable keyboard frames and target overflow. App padding is unchanged. Hosted TwoFactorLayoutTests
adds Duo/SE keyboard-height inset fixtures and requires the last control to scroll fully clear.
Portable tests cover the saved event bounds, both drag directions, asymmetric viewports, missing
subtitle lines and low contrast. The new ToolingTests suite is classified as host-only.

Verification: `make quick` (strict lint, all host packages, signing/resource and 64 runner fixtures),
`make generate`, and direct Swift 6 iOS 17 app/hosted/UI compilation pass. Logs:
`build/phase-10b-round2-{quick,generate,typecheck,focused-typecheck}.log`. CoreSimulator access is denied here;
compilation does not execute the new hosted fixtures or audit. No snapshot PNG is changed.

Run on the user's host:

```sh
make generate
make check
make duo
```

For a focused reachability check on both runtimes, if needed:

```sh
make targeted DEVICES="se duo" ONLY="AppTests/TwoFactorLayoutTests/testLastControlCanScrollAboveKeyboardInsetsOnDuoAndSE AppUITests/TwoFactorTests/testModeToggleClearsCodeAndRecoveryReturnCompletesTheMockSession"
```

The seven-runtime matrix is not requested. Task 2 remains unticked for revised runtime acceptance
and the existing Two-factor side-by-side board review; device-only gates retain their original scope.

### Phase 11a Forgot acceptance

Run in this worktree. No seven-simulator matrix or simulator clean/reboot is needed.
The runner disables automatic software-keyboard minimization on each UI destination after boot.
Recording is restricted to 17e; the targeted recording invocation records the Forgot suite once,
then compares it. It cannot record guards, UI or Release tests.

```sh
make generate
make auth-board-pngs
make targeted DEVICES="17e" ONLY="AppTests/ForgotPasswordControlTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/ForgotPasswordLayoutTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/AuthSnapshotGuardTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/AuthLayoutTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/AuthSubtitleContrastTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/ForgotPasswordSnapshotTests/testRootCapMakesAX5EqualXXLarge"
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/ForgotPasswordSnapshotTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/AuthSnapshotTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppUITests/ForgotPasswordTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppUITests/ForgotPasswordKeyboardTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppUITests/SignInTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppUITests/AuthAuditTests"
make targeted DEVICES="se duo" REUSE_BUILD=1 ONLY="AppUITests/ForgotPasswordKeyboardTests"
```

Compare the default-size 17e/en Forgot references in `AppTests/__Snapshots__/Auth/Forgot/` with
`build/board-png/forgot-{none,sent,field,attempts,server}-{light,dark}.png`. Review all device/language/
size adaptations too. Board-to-device geometry is an adaptation; there are no board-size auth references
in the lean set. The offline reference matches the unchanged form. There should be 78
Forgot PNGs after a complete recording; partial sets fail the host inventory fixture. Send the
exact runner output and screenshots for any failures. Logs and xcresults are in
`build/test-results/<alias>/`. After resolving failures and accepting the references, run `make check`.
SE/Duo keyboard tests require visible stable keyboard/window intersection, focus, full field/submit
visibility and interactive dismissal; an off-screen or minimized keyboard cannot pass.

Phase 11a fix round 1 (2026-11-07): the supplied board export succeeds with all ten Forgot PNGs.
Forgot layout, AuthSnapshotGuard and AuthLayout pass individually. Forgot control feedback/focus,
server/throttle UI and visible-keyboard variants fail; the audit’s bare assertion is the same
missing server-banner wait at `AuthAuditTests.testForgotStatesInBothLanguagesAppearancesAndSizes`.
Unchanged native email writes during refocus now preserve feedback; a real edit still clears it.
Blank/whitespace email returns the backend required message; malformed email keeps its email message.
Failure injection, failure-to-banner mapping and the shared `auth.banner` identifier are present.

The saved root-cap failure differs only in the prefilled email text’s one-pixel vertical position,
not its font size. Hosted system categories now enter above the window cap, rather than overriding
the hosting controller below it. SwiftUI still receives the requested category before its root cap;
no per-view caps are added. Native field trait/font checks and exact AX5 comparisons remain required.
Both snapshot suites have bounded 12-turn settling and use immediate mock requests; there is no
unbounded model wait in either suite. Profile progress is now logged, and cap failures report their
fixture/context without expanding whole raster byte arrays. Run suites individually above to isolate
runtime stalls and retain each result before the next run replaces its logs/xcresult.

The measured subtitle exception now covers every auth screen, including Forgot. It locates the
unique scroll containing the exact issue subtitle, then measures that screenshot’s visible lines;
unmeasurable, incomplete, non-finite or < 4.5:1 still fails. See
[auth-subtitle-contrast.md](auth-subtitle-contrast.md). Forgot’s six states join the hosted contrast
and sky-position guard. Existing untracked Forgot references remain untouched and require a complete
successful recording/comparison and visual review before acceptance.

Fix-round validation: `make quick` passes strict lint, 333 package tests, 10 TokenGen tests,
4 AssetGen tests and 86 signing/resource/runner fixtures. Direct iOS 17 compilation passes
Debug/Release DataAccess/app modules and app SIL, all hosted tests, and Debug UI tests.
The final hosted/UI edits also pass a focused type-check. These checks do not execute UIKit;
the individual simulator reruns and visual review above remain open. Logs are
`build/phase-11a-fix-round1-{quick,typecheck,final-typecheck}.log`.

### Phase 11a fix round 2 — rerun without recording

The user’s lean auth decision (2026-11-07) reduces reference captures from 4,032 to **234**:
52 Sign in, 104 Two-factor and 78 Forgot. Surviving PNGs stay byte-for-byte unchanged; obsolete
references are deleted. Existing Forgot survivors remain untracked/unaccepted. Record only missing
or intentionally changed states after review; this round runs no recording command.

Forgot’s prefilled native email differs from the empty Sign in/Two-factor snapshot fields. The
UIKit root now receives the clamped category and observes changes from the window. The SwiftUI root
normalizes its environment to the same concrete capped value. The SE hosted frame regression checks
both Forgot states, including native input
bounds, text rect and font. The one pixel comparison per screen uses SE/en/light, with Forgot’s
field-error form exercising the prefilled input. No per-view cap is added.

The harness has instance-owned windows and no shared auth raster cache. Auth font registration has
a 10 s deadline; settling has cancellable yields, at most 12 captures and a 5 s deadline. The runner
also enables XCTest timeouts with a 600 s per-test maximum to catch synchronous main-actor or
CoreText stalls that cannot yield to an in-process timer. The saved timing inventory has capture
guards at 452 s and subtitle checks at 506 s, so a 300 s allowance would reject valid existing work.
The runner now requests `-resultStreamPath` and counts actual JSONL byte growth as activity when
parallel xcodebuild stdout is buffered. It prints stream progress at most every 30 s when new events
arrive; timestamp changes alone do not reset inactivity. The existing 600 s inactivity / 3,600 s
process limits remain. Streams are beside the logs as `Debug-compare.jsonl`. All-profile layout/guard
loops are retained. CoreSimulator is inaccessible
in this sandbox, so hosted execution and confirmation of the reported failures remain the host run.

Build and run Forgot first, including element-level diagnostics:

```sh
make targeted DEVICES="17e" ONLY="AppTests/ForgotPasswordSnapshotTests AppTests/ForgotPasswordLayoutTests AppTests/ForgotPasswordControlTests"
```

Then run one combined comparison against the same build:

```sh
REUSE_BUILD=1 make targeted DEVICES="17e" ONLY="AppTests/ForgotPasswordSnapshotTests AppTests/AuthSnapshotTests AppTests/TwoFactorSnapshotTests AppTests/AuthSnapshotGuardTests AppTests/AuthSubtitleContrastTests AppTests/AuthLayoutTests"
```

These commands do not record. Preserve `build/test-results/17e/Debug-compare.{log,xcresult}` after
the Forgot run if needed: the combined run replaces them. `TEST_WORKERS` retains its normal default
of two; no serialization workaround or seven-simulator run is required by this change.

Round-2 validation: `make quick` passes, including strict formatting and the exact lean inventories;
75 runner fixtures include buffered-stdout progress and genuine-stall regressions. Direct iOS 17
Debug/Release app/hosted compilation and Debug UI type-checking pass. Logs:
`build/phase-11a-round2-{quick,typecheck,runner}.log`. These checks do not execute UIKit.


### Phase 11a fix round 3 — lean audit and contrast reruns

The native auth field now uses explicit capped UIKit font metrics with a fixed-size SwiftUI font;
the SE regression keeps exact input/text-rect/AX5 comparisons and verifies native font metrics.
Audit and subtitle tests use five variants per state (en/nl × light/dark default, plus en/light
xxLarge), split into nine screen/state methods in each suite. Control reveals remain; repeated
scroll/keyboard positions are measured/audited once. No execution allowance is raised.
Back-button viewport checks include the navigation-bar region above the content safe area; content,
subtitle, horizontal safe-area and keyboard bounds keep their existing rules.

Forgot banner contrast uses rendered text/background pixels and generated banner/typography tokens.
Saved 17e default-size en/nl server/throttle PNGs measure **14.8840:1 light / 12.4197:1 dark**, with
complete line measurements (`build/phase-11a-round3-banner-contrast.log`). UI exceptions use fresh
screenshots, never these saved ratios. Only unattributed contrast issues in Forgot server/throttle
states may qualify, and only with a complete finite minimum ≥ 4.5:1. Named issues stay strict.
All 78 user-recorded Forgot references are preserved; no recording is performed here.

`make quick` runs strict lint and package checks but the existing
`APICookieTests.realRedirectCookieHandlingIsDisabled` fails because its loopback listener is denied
by this sandbox (`POSIXErrorCode(1): Operation not permitted`). `make -k quick` confirms strict lint, 333/334 package tests, all 10 TokenGen and 4 AssetGen tests,
and all 88 signing/resource/runner fixtures pass. Only that listener test fails. Logs: `build/phase-11a-round3-quick{,-all}.log`. No simulator, matrix or Duo
runtime command is run here. New timing, AX5 equality, reference comparison and audit acceptance
remain the user's host run.

Build once and verify the changed field against the kept references:

```sh
make targeted DEVICES="17e" ONLY="AppTests/ForgotPasswordLayoutTests AppTests/ForgotPasswordSnapshotTests AppTests/ForgotPasswordControlTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/AuthSubtitleContrastTests AppUITests/AuthAuditTests"
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppTests/AuthSnapshotTests AppTests/TwoFactorSnapshotTests AppTests/AuthSnapshotGuardTests AppTests/AuthLayoutTests AppUITests/ForgotPasswordTests AppUITests/ForgotPasswordKeyboardTests"
```

The first command builds the current sources; reuse only that unchanged build. These commands do
not record. Each command replaces `build/test-results/17e/Debug-compare.{log,xcresult,jsonl}`;
preserve earlier results before continuing when investigating a failure. The shared font change
may expose reference differences: inspect them before any intentional re-recording. The user's
previous passes are evidence for round 2, not a new runtime pass for this round.

### Phase 11a fix round 4a — native input height

AuthField now pins the input height before padding to the capped UIKit font line height, rounded up
to the current display pixel. The field subtree receives the same clamped Dynamic Type environment.
The SE layout test explicitly retains the xxLarge input rectangle `(48, 473.5, 279, 25)` and reports
the requested category, native category and resolved font on geometry/font failures.
Existing Forgot, Sign in and Two-factor PNGs are unchanged.

Host verification: `make quick` reaches only the known sandbox-denied loopback listener in
`APICookieTests.realRedirectCookieHandlingIsDisabled` (`Operation not permitted`).
`make -k quick` completes the remaining host checks; logs are
`build/phase-11a-round4-quick{,-all}.log`. Direct iOS 17 host compilation/type-checking of DesignSystem,
Auth, all hosted AppTests and AppUITests passes (`build/phase-11a-round4-typecheck.log`), without
simulator execution. Runtime geometry, pixel equality and unchanged default-size references remain
the user's checks. Build the changed sources and compare without recording:

```sh
make targeted DEVICES="17e" ONLY="AppTests/ForgotPasswordLayoutTests AppTests/ForgotPasswordSnapshotTests AppTests/ForgotPasswordControlTests AppTests/AuthSnapshotTests AppTests/TwoFactorSnapshotTests"
```

### Phase 11a fix round 4b — language-independent banner attribution

The exception now matches the current `auth.banner` identifier/frame and unattributed descendants,
with no copy checks. Previously accepted unattributed wordmark reports match the current `auth.brand`
frame. Both require a complete finite banner-text minimum ≥ 4.5:1 measured in the same audit context.
The user's round-3 Dutch server results already report **14.8840:1 light / 12.4197:1 dark**; the new
code still measures fresh screenshots. All other named controls, unrelated frames/states and other
audit types remain strict. Issue/banner/brand frames are included in diagnostics, and the policy test
covers containment, missing/invalid geometry and all measurement/state/type gates.

The round-4 host verification above includes the updated audit code. Strict lint and direct iOS 17
compilation/type-checking pass; `make -k quick` reports only the known APICookieTests listener EPERM,
with all other 333 package tests, 10 TokenGen tests, 4 AssetGen tests and 88 signing/resource/runner
fixtures passing. No simulator, matrix, Duo runtime or recording command is run here.
After the round-4a command builds the current sources, reuse that unchanged build:

```sh
make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppUITests/AuthAuditTests/testBannerExceptionRequiresMatchingGeometryAndPassingPixels AppUITests/AuthAuditTests/testForgotServerInLeanAuditMatrix AppUITests/AuthAuditTests/testForgotThrottleInLeanAuditMatrix"
```

Each targeted command replaces `build/test-results/17e/Debug-compare.{log,xcresult,jsonl}`; preserve
prior results when investigating failures. Runtime equality, default-size reference preservation and
strict audit acceptance remain unclaimed until these reruns pass.

## Phases 11b–11d: host checks and user simulator handoff

Only host verification runs in this round. `make quick` reaches the known APICookieTests sandbox
EPERM; `make -k quick` continues through the generators and runner/resource fixtures. Final totals: 352/353 package tests pass (only the known cookie listener failure); the remaining quick tiers pass separately (10 TokenGen, 4 AssetGen and 89 signing/resource/runner fixtures). The changed iOS package/app modules and all hosted/UI test sources also pass a static compiler check on the host against the iOS 17 minimum, without starting a simulator. Logs: build/recovery-quick.log, build/recovery-host-fixtures.log and build/recovery-typecheck/. No simulator, recording, matrix, make check or make duo was run.

Generate the project, then run the new hosted controls/layout and activity/factory tests on 17e:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/ResetPasswordControlTests AppTests/ResetPasswordLayoutTests AppTests/SignUpControlTests AppTests/SignUpLayoutTests AppTests/VerifyEmailControlTests AppTests/VerifyEmailLayoutTests AppTests/AuthUniversalLinkTests AppTests/DataSourceBuildSettingTests"
```

The three new snapshot suites have 364 references to record and review. They render 17e/SE/Duo
profiles inside the 17e simulator and never name references after the executing simulator:

```sh
SNAPSHOT_RECORD=1 make targeted DEVICES="17e" ONLY="AppTests/ResetPasswordSnapshotTests AppTests/SignUpSnapshotTests AppTests/VerifyEmailSnapshotTests"
make targeted DEVICES="17e" ONLY="AppTests/ResetPasswordSnapshotTests AppTests/SignUpSnapshotTests AppTests/VerifyEmailSnapshotTests"
make targeted DEVICES="17e" ONLY="AppUITests/ResetPasswordTests AppUITests/SignUpTests AppUITests/VerifyEmailTests AppUITests/AccountRecoveryTests AppUITests/AuthAuditTests"
```

Recording is performed by the user. The agent did not create or alter reference PNGs. AuthAuditTests
keeps one screen/state per method with five variants, all control reveals, same-context subtitle
measurements and the existing 600-second watchdog. Full-suite duration and each new method's actual
time require the user run; no higher watchdog or new board exception was introduced. Use the existing
board PNG export workflow for visual approval. DeviceSigned still reads DEVELOPMENT_TEAM from ignored
Config/Local.xcconfig and adds applinks:app.chronoflow.net alongside webcredentials. System email-link
opening still needs server AASA deployment with the confirmed team/bundle ID and physical acceptance.

## Phases 11b–11d — simulator fix round 2 (8 November 2026)

Input: branch `feat/phase-11d-verify`, HEAD `64ca779`, and the user's full failure log
`/private/tmp/claude-501/-Users-rickgout-Sites-chronoflow-ios/297ae62c-d4a3-4567-8832-5e7859cd8a0a/scratchpad/codex/p11bcd-sim1-failures.txt`.
The user reports Reset/SignUp/Verify snapshot compare passing. All 364 recorded references
are preserved byte-for-byte in their phase patches: 104 / 130 / 130.

The three ordered patches in `build/commits` apply on HEAD. They also apply immediately
after the corresponding sub-phase tip, retaining prior fixes: `1.patch` after `9228e7b`,
`2.patch` after `a1dcaee` plus patch 1, `3.patch` after `64ca779` plus patches 1–2.
`messages.txt` maps each patch to its phase and Conventional Commit subject. Shared native
field, AutoFill-entry and audit helpers are in 11b; sign-up entry/assertions/references are
in 11c; verification/recovery fixtures and references are in 11d. Commits are assembled in
an isolated packaging repository because this workspace's Git metadata is read-only.

Host verification: `make quick`, followed by `make -k quick` to finish the other tiers,
passes strict formatting lint, 366/367 package tests, 10 TokenGen tests, 4 AssetGen tests
and all 89 signing/resource/runner fixtures. Only the known loopback listener EPERM in
`APICookieTests.realRedirectCookieHandlingIsDisabled` fails. Direct Swift 6 compilation
against `arm64-apple-ios17.0-simulator` passes for all changed package/app modules and
hosted/UI test sources. This invokes swiftc only; it does not start a simulator.
Logs: `build/round2-11b-quick.log`, `build/round2-final-quick.log`,
`build/round2-typecheck.log` and `build/recovery-typecheck/*.log`.

Run the revised suites on the one 17e, without recording:

```sh
make generate
make targeted DEVICES="17e" ONLY="AppTests/ResetPasswordControlTests AppTests/SignUpControlTests AppTests/ResetPasswordSnapshotTests AppTests/SignUpSnapshotTests AppTests/VerifyEmailSnapshotTests AppUITests/ResetPasswordTests AppUITests/SignUpTests AppUITests/VerifyEmailTests AppUITests/AccountRecoveryTests"
TEST_RUN_TIMEOUT=14400 make targeted DEVICES="17e" REUSE_BUILD=1 ONLY="AppUITests/AuthAuditTests"
```

Select the whole AuthAuditTests suite to retain light, Dark and XXLarge methods for every
state. Audit methods now launch at most two variants each; collect actual method times
from `build/test-results/17e/Debug-serial.xcresult` and require each to finish well below
600 seconds. The four-hour limit above applies to the complete serial audit suite; it does
not change the 600-second per-method watchdog. No timing or runtime pass is inferred from host compilation. No recording,
`make check`, Duo runtime or seven-simulator matrix ran in this fix round. Existing board
review, server AASA/team ID and physical-mail/passkey acceptance remain open.
