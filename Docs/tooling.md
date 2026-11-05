# Scaffold verification — 5 November 2026

Toolchain: Xcode 27.2 (27B52), Apple Swift 6.4.2, XcodeGen 2.46.0 at `/opt/homebrew/bin/xcodegen`.
The app and package use Swift 6 language mode and an iOS 17.0 deployment target. UI modules default to
MainActor; AppCore is nonisolated.

## Commands

Run `Scripts/ci.sh` from a checkout to generate the ignored Xcode project and run `make check`.
`make check` runs strict formatting lint, AppCore tests and the app window UI test, then the DesignSystem,
Launch and Welcome suites. The last three suites contain only smoke tests in Phase 0; design snapshots
arrive in Phases 1 and 3c. There are no image baselines to approve yet.

All Makefile Xcode builds use `build/DerivedData` and
`platform=iOS Simulator,name=iPhone 17e,OS=27.2`. The Duo window check is:

```sh
xcodebuild -project ChronoFlow.xcodeproj -scheme ChronoFlow \
  -destination 'platform=iOS Simulator,name=iPhone Duo,OS=27.2' \
  -derivedDataPath build/DerivedData -only-testing:AppUITests/WindowTests test
```

The `Perf` scheme uses Release. Phase 0 supplies only a launch metric smoke test; the comparison harness
belongs to Phase 7. `tokens`, `fonts` and `assets` fail with an explanation until their Phase 1 tools exist.
Signing uses `Config/Base.xcconfig` with an optional `#include? "Local.xcconfig"`. Copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` for device runs.
Simulator signing is disabled independently of that setting.

## Results in the implementation environment

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
- The 17e Debug build, Duo window UI test, `make check`, `make snapshots` and `Scripts/ci.sh` could not
  complete. Xcode's package resolution exits 74 with
  `sandbox-exec: sandbox_apply: Operation not permitted`; Make exits 2. CoreSimulator also reports
  `CoreSimulatorService connection became invalid` and `Operation not permitted` for its log directory.
  Full app builds, launches, window bounds and the clean-clone CI check remain unverified. XcodeGen
  compatibility through a complete build is therefore still unverified.

Local command logs are under ignored `build/Logs/`.

## Instruments templates

Attempted `xcrun xctrace list templates` with Xcode 27.2. It aborted before producing any template lines:

```text
Cannot create temporary directory for Instruments Analysis Core
You don’t have permission to save the file “path_manager” in the folder “com.apple.dt.InstrumentsCLI”.
Operation not permitted
```

The requested `Animation Hitches` and `App Launch` lines could not be confirmed. Rerun the command in an
environment that permits Instruments' cache access and record those exact lines here before performance
work begins. No device performance measurements were attempted in Phase 0.
