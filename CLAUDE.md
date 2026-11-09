@AGENTS.md

## Orchestration (Claude)

Codex implements and Opus reviews; Claude orchestrates and does not hand-write feature code.

1. Hand Codex one phase of `plan.md` with `codex exec -C /Users/rickgout/Sites/chronoflow-ios -s workspace-write`, on that phase's branch.
2. Opus reviewers check the diff against `plan.md`, the boards in `_design/canvas/`, the D1c device matrix and correctness/performance. Only findings that survive verification go back to Codex.
3. Repeat until the review is clean, then make sure `make check` passes and the commits are atomic and ticked in `plan.md`.

Codex's `workspace-write` sandbox cannot run `xcodebuild` (nested `sandbox-exec`), CoreSimulator or `xctrace`, and may be denied `.git/index.lock`. Running Codex with `danger-full-access` is not permitted. So Claude runs builds, tests and simulator checks (`make check`, `make duo`) outside the sandbox, feeds the exact output back to Codex, and makes the commits Codex could not, using Codex's suggested messages.

## Commands

`make generate` creates the ignored project. `Scripts/ci.sh` runs `make generate check`.
Use `make quick` for fix rounds: strict lint and every SwiftPM host suite, plus runner/resource fixtures.
The warm inner-loop target is under one minute. `make check` adds generator/font freshness and one
17e simulator: hosted AppTests with fixed worst-case screen fixtures, the UI smoke set and isolated
Release readiness. Debug and Release build once each; target under five minutes remains to be measured.

User decision, 2026-11-06: **skip the seven-simulator matrix unless asked for**. Device fit is covered
by the Mac device-table tests and hosted worst-case layout checks on 17e. Reference-comparing
snapshots are opt-in until references are approved; `make snapshots` compares and
`SNAPSHOT_RECORD=1 make snapshots` records every registered snapshot suite.
`make matrix` retains LPT scheduling and all seven runtimes on request only; no default/CI flow calls it.
`make duo` is an opt-in spot check for Duo runtime behaviour changes, resolved on its separate runtime.
Use `make targeted DEVICES="17e" ONLY="AppTests/WelcomeSnapshotTests/frozenIntro()"` for selected tests;
`REUSE_BUILD=1` skips an unchanged build. Select `DEVICES="se duo" ONLY="AppTests/DeviceGeometrySmokeTests"`
when explicitly diagnosing those runtimes. `SIM_CONCURRENCY=1…7` and `TEST_WORKERS=1…4` override worker limits.

One-time replacement recording is `SNAPSHOT_RECORD=1 make snapshots`, on 17e only, both screens.
All per-simulator references were removed. New profile references and visual approval remain open.
`make test` / `make snapshots` select 17e subsets; `make perf` remains the Release launch scaffold.
Device appearance/system-launch tests use `XCUIDevice.shared.appearance` in a serial pass; per-launch
appearance is valid only for the app's post-launch UI. Retain event/stability waits, root xxLarge cap
and the strict board-contrast/partial-visibility audit policy. Logs/xcresults are in `build/test-results/<alias>/`.
See `Docs/tooling.md` for exact commands, coverage mapping, budgets and environment limits.
`make tokens`, `make fonts` and `make assets` regenerate design outputs; `make generators-check` verifies them.

Simulators use ad-hoc signing without a team so hosted Keychain tests can run. Device signing comes from ignored `Config/Local.xcconfig`, included
by `Config/Base.xcconfig`; copy `Config/Local.xcconfig.example` to get started. All working rules and traps,
including the no-trailer commit rule, are inherited from `AGENTS.md`.

Simulator `build-for-testing` uses `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` in Debug, Release and Perf.
These runner command-line settings leave device builds and archives unchanged.

After the foreground Debug build, Release/Perf build in a background queue under `nice -n 10`
while Debug tests run. Each uses `build/DerivedData-Release` / `build/DerivedData-Perf`; Debug
keeps `build/DerivedData`. All share `build/SourcePackages`. Each pass waits for its build;
build failures still fail the run. `REUSE_BUILD=1` requires current products in these paths.
