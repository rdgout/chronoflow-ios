# Scaffold verification — 5 November 2026

Toolchain: Xcode 27.2 (27B52), Apple Swift 6.4.2, XcodeGen 2.46.0 at `/opt/homebrew/bin/xcodegen`.
The app and package use Swift 6 language mode and an iOS 17.0 deployment target. UI modules default to
MainActor; AppCore is nonisolated.

## Commands

Run `Scripts/ci.sh` from a checkout to generate the ignored Xcode project and run `make check`.
`make check` runs strict formatting lint, AppCore tests and the app window UI test, then the DesignSystem,
Launch and Welcome suites. The last three suites contain only smoke tests in Phase 0; design snapshots
arrive in Phases 1 and 3c. There are no image baselines to approve yet.

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
belongs to Phase 7. `tokens`, `fonts` and `assets` fail with an explanation until their Phase 1 tools exist.
Signing uses `Config/Base.xcconfig` with an optional `#include? "Local.xcconfig"`. Copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` for device runs.
Simulator signing is disabled independently of that setting.

## Verified results

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
