# ChronoFlow iOS

ChronoFlow is a jet-lag planner. It plans sleep, light and caffeine for a trip. This repo is the native iOS app (Swift, UIKit scene life cycle hosting SwiftUI), built to perform better than the Expo / React Native app.

`plan.md` is the plan. Work one phase at a time, tick each task in the same commit that completes it, and follow its Decisions (D1–D17), spec and Open questions. Do not start a task whose phase is blocked by an open question.

## Sources (read-only)

- `_design/canvas/`: the design boards (`*.dc.html`), `canvas.json` and the design system (`ds/chronoflow/tokens.json`, `README.md`, `components/`). The canvas itself is a claude.ai artifact the user maintains; this is a local copy.
- `_design/icon/`: supplied icon masters, layers, Icon Composer starter and glass reference renders; intent is in `_design/canvas/AppIcon.dc.html`.
- `/Users/rickgout/Sites/chronoflow-mobile`: the RN app. Its `plan.md` Phase 21 holds settled splash rules. Read it; never write to it, and never run `expo prebuild` or builds inside it.
- `/Users/rickgout/Sites/chronoflow-new`: the web app, the product source of truth. Read-only.

## Working rules

- **No design, no invention.** If a screen or state has no board, stop and say so. Deferring beats inventing.
- **Values only from generated tokens and assets**, light and dark. No hard-coded colours or 390 × 844 geometry.
- **Every iPhone, iPhone Duo included.** Splash and Welcome geometry is computed from the window size and all four safe-area insets (Duo has a side rail). Verify device fit with the D1c device-table Mac tests and worst-case hosted layout fixtures inside one 17e simulator. Reference-comparing profile snapshots are opt-in until references are approved. Run the seven-simulator matrix only when asked; use `make duo` only for Duo-specific runtime changes.
- Dynamic Type is capped at xxLarge at the root; never add per-view caps or bypass the cap.
- **Minimum iOS 17.0.** No `#available` checks below 17.
- **Liquid Glass on iOS 26+.** Never set `UIDesignRequiresCompatibility`. Use system controls so they pick up Liquid Glass automatically. Explicit glass APIs only behind `if #available(iOS 26, *)` with the plain system default as fallback, never a hand-drawn imitation. Designed surfaces stay as drawn.
- **Native components** over hand-built look-alikes of system controls.
- **English and Dutch together.** Every visible string goes into a String Catalog with its `nl` value in the same commit. Never hard-code customer-facing text.
- **Copy** promises a clock shift, never symptom relief.
- **No unneeded comments.** Write only the comment that records a *why* the code cannot show.
- **Performance.** No synchronous I/O on the main thread before the splash overlay is committed. No `+load` or static initialisers. No `mask`, `filters` or shadows in the splash layer tree.

## Tests

Write every new or changed test this way (user, 2026-11-10). Wizard tests that ignored these rules cost a morning of 3–10 minute hangs and five fix rounds aimed at a harness artifact.

- **Pick the cheapest layer that can fail.**
  - **Logic** (validation, timing, retries, offline, persistence, computed values, multi-step flows): SwiftPM unit tests.
  - **Layout and geometry:** hosted AppTests.
  - **XCUITest:** only for what needs the real app — native controls, navigation, system UI and appearance. Never test logic through a screen.
- **One UI journey per feature, at most,** as a smoke test. Every other UI test seeds a state and checks one screen.
- **UI tests launch seeded.**
  - Use `ScreenTestApp`, with `AuthUIFlow.launchSignedIn` plus a board or fixture env such as `CF_WIZARD_BOARD_CAPTURE`. The app launches once per class and reseeds between tests.
  - Never sign in through the form or click through earlier steps to reach the screen under test. Only the auth tests drive sign-in.
- **Queries and waits.**
  - Query exactly: `app.buttons["id"]`, adding `.firstMatch` when needed.
  - No `descendants(matching: .any)`, no whole-tree predicates, and no loops over element properties.
  - Wait with `UIWait` (backoff polling), never fixed sleeps.
- **Budgets.**
  - A UI test should finish in under 10 s and a hosted test in under 5 s.
  - Set `executionTimeAllowance = 60`, XCTest's minimum, so a hang fails in a minute rather than 10.
  - Split a test that loops over many profiles × languages × sizes into one test per profile.
  - A test that needs more time is a design smell: fix the test, don't raise the allowance.
- **Know what the harness can show.**
  - `AuthTestHost` simulates insets with SwiftUI `safeAreaInset` outside the view. Horizontal insets do not reach screens inside a `NavigationStack`.
  - Check Duo side-rail fit for those screens with one seeded screenshot on the Duo runtime: `simctl launch` with the seed env, then `simctl io --display=1 screenshot`. Don't add hosted assertions for it.
  - When a check can't fail for the real reason, don't keep fixing the app to satisfy it.
- **Running tests.**
  - When fixing or diagnosing a failure, run only the failing test method, e.g. `ONLY="AppTests/Suite/testMethod"`, never the whole suite. With a reused build that takes seconds to a couple of minutes.
  - Run only the suites you touched: `make targeted ... ONLY=...`.
  - Before bisecting, read the suspect diff. Bisect only the failing methods, one build per step.
  - After one fix round that changes nothing, or a hang, stop. Bisect or rethink the test before another round.

## Commands

| Command | What it does |
| --- | --- |
| `make generate` | Generate `ChronoFlow.xcodeproj` from `project.yml` (the project file is not committed) |
| `make quick` | Inner loop: strict lint and all SwiftPM host tests plus runner/resource fixtures; target <1 min warm |
| `make check` | Commit gate: quick + generators, then 17e hosted screen tests, UI smoke and isolated Release readiness; target <5 min |
| `make format` | Format owned Swift sources with the toolchain formatter |
| `make lint` | Run strict Swift formatting lint on the host |
| `make test` / `make snapshots` | Run test or hosted profile-snapshot subsets on 17e / iOS 27.2 |
| `make duo` | Opt-in runtime smoke when Duo-specific behaviour changes; resolve by type and iPhone19-4 runtime |
| `make matrix` | On request only: full seven-simulator runtime matrix, LPT scheduling and automatic concurrency (1–7 override) |
| `make targeted DEVICES="se duo" ONLY="AppTests/DeviceGeometrySmokeTests"` | Build once and run selected suites on these aliases; REUSE_BUILD=1 skips the build after an unchanged build-for-testing |
| `make perf` | Run the Release `Perf` scheme (launch metric scaffold until Phase 7) |
| `make tokens` / `make fonts` / `make assets` | Regenerate the committed tokens, static fonts and generated assets (including app icons) |
| `make generators-check` | Verify generated outputs, fonts and raster assets and run their host tests; first run needs network (see `Docs/tooling.md`) |
| `Scripts/ci.sh` | Run `make generate check` locally |

Test-tier decision (user, 2026-11-06): “skip the 7 simulator matrix unless asked for”. Device fit stays mandatory through Mac device-table tests and hosted worst-case layout checks on 17e. Reference-comparing snapshots are opt-in until references are approved (`make snapshots`; `SNAPSHOT_RECORD=1 make snapshots` records them). Profiles keep full coverage on SE/17e/Duo/Pro Max and compact coverage on 17/Air/18 Pro. Device-appearance/system-launch tests run serially with `XCUIDevice.shared.appearance`; only post-launch app UI may use per-launch appearance. No default/CI matrix, clean or reboot. Logs and xcresults are under `build/test-results/<alias>/`; `Docs/tooling.md` has recording and timing commands.

Simulators: Xcode 27.2 with iOS 27.2 runtimes (iPhone SE 3rd gen, 17e, 17, Air, 18 Pro, 18 Pro Max, iPhone Duo). Duo runs on its own runtime (`com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`, build 24B91016s); the regular runtime (24B8117) has no Duo device type. Use `make duo`, which resolves by device type and runtime instead of name/OS or a fixed UDID. No iOS 17 simulator runtime is downloadable for Xcode 27.

## Git

- One branch per phase (`feat/phase-N-slug`), stacked. Never commit to `main` directly after the first docs commit; never merge, push or force-push unless asked. There is no remote yet.
- Commits are atomic and follow Conventional Commits: `type(scope): subject`, lower-case imperative subject. No `Co-Authored-By` or other trailers.

## Traps

- `xcode-select` points at full Xcode (`/Applications/Xcode.app`); keep it that way.
- Headless simulators can report an off-screen keyboard as existing; after boot, the runner sets each device's `com.apple.keyboard.preferences AutomaticMinimizationEnabled` to false via `simctl spawn`, never host-global Simulator.app preferences.
- The launch screen is cached by iOS. After changing it: Clean Build Folder, delete the app, restart the Simulator.
- `*.xcodeproj` is generated; edit `project.yml`, never the project file.
- Hosted `AppTests` must depend only on `ChronoFlow`, using `TEST_HOST` / `BUNDLE_LOADER`; linking its package products again duplicates resource-bundle accessors and crashes package test processes.
- XcodeGen target presets override project-level settings. Set `TARGETED_DEVICE_FAMILY: "1"` and `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO` on every iOS target to keep it iPhone only.
- App icons come from the supplied design set (OQ 18 settled). `make assets` generates `ChronoFlow.appiconset` and `ChronoFlow.icon`; keep their primary name identical. The board selects opaque dark. XcodeGen's post-generation adapter sets `folder.iconcomposer.icon` for actool; preserve it. Composer replaces legacy flats under Apple's supported configuration (OQ 18 limitation). `make icon-probe` establishes authored-flat and Composer-only content controls; `Scripts/check-app-icon.py` verifies shipped legacy pixels and the glass stack by content (see `Docs/app-icon.md`).
- Fonts are registered from the package with `CTFontManagerRegisterFontsForURLs`, not `UIAppFonts`.
- The launch storyboard is not localised.
- `make snapshots` renders hosted splash/Welcome profile suites on 17e. `SNAPSHOT_RECORD=1 make snapshots` records both screens once; new profile references require review. Never name references after the executing simulator. Phase 1's four dot-bearing primitive baselines were removed with the user's 2026-11-06 no-pattern decision; the old per-simulator launch/Welcome references were removed in tooling round 3; replacement recording remains open.
- `Config/Base.xcconfig` optionally includes ignored `Config/Local.xcconfig`; copy `Local.xcconfig.example` there for a device team. Simulator builds use ad-hoc signing (`CODE_SIGN_IDENTITY = -`) with no team; disabling signing breaks hosted Keychain access (`errSecMissingEntitlement`).

Simulator `build-for-testing` uses `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` in Debug, Release and Perf.
These runner command-line settings leave device builds and archives unchanged.

After the foreground Debug build, Release/Perf build in a background queue under `nice -n 10`
while Debug tests run. Each uses `build/DerivedData-Release` / `build/DerivedData-Perf`; Debug
keeps `build/DerivedData`. All share `build/SourcePackages`. Each pass waits for its build;
build failures still fail the run. `REUSE_BUILD=1` requires current products in these paths.

When the worker budget permits, 17e Debug comparison runs on the primary plus Xcode clones
followed by Debug serial tests on the primary. Only Release/Perf tests run concurrently on a
persistent `ChronoFlow 17e Isolated`.
The runner resolves/creates it by iPhone 17e type and regular runtime, excludes clones, and
prepares destinations in background threads during builds. Results stay under `17e/` and
`17e-isolated/`; summaries and `timings.json` merge under 17e. `SIM_CONCURRENCY=1` keeps one
destination; recording and intro-order diagnostics retain their existing single-device sequence.
Before each pass, live device state is checked and the destination is booted and prepared as needed.
Post-pass appearance cleanup skips devices that are not booted and never boots them; skips/errors
are logged in `prepare.log` and do not fail tests.

`ReadinessRelease` builds only the hosted `ReleaseReadinessTests` target from its own directory,
with `TEST_HOST`/`BUNDLE_LOADER` and only a ChronoFlow dependency. Select it with
`make targeted DEVICES="17e" ONLY="ReleaseReadinessTests/ReleaseReadinessTests"`.
Regenerate the project before running; Release no longer compiles the Debug AppTests bundle.

Simulator passes use `-collect-test-diagnostics never` by default. Failure results, attachments
and session/stdout logs remain. `TEST_DIAGNOSTICS=1 make targeted DEVICES="17e" ONLY="AppUITests/SignInTests"`
restores Xcode's on-failure logarchive/sysdiagnose collection.

ChronoFlow's iOS test action includes only DesignSystemTests among package bundles. Explicit
LaunchTests/WelcomeTests selections use `PackageLogic` (Debug); host-only bundles stay in quick.
Build logs print elapsed time per scheme/configuration. Concurrent Swift Testing suite timings
use max case duration; XCTest/serialized suites keep sums. See Docs/tooling.md for warm-run timing commands.
