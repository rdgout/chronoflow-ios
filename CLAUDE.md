@AGENTS.md

## Orchestration (Claude)

Codex implements and Opus reviews; Claude orchestrates and does not hand-write feature code.

1. Hand Codex one phase of `plan.md` with `codex exec -C /Users/rickgout/Sites/chronoflow-ios -s workspace-write`, on that phase's branch.
2. Opus reviewers check the diff against `plan.md`, the boards in `_design/canvas/`, the D1c device matrix and correctness/performance. Only findings that survive verification go back to Codex.
3. Repeat until the review is clean, then make sure `make check` passes and the commits are atomic and ticked in `plan.md`.

Codex's `workspace-write` sandbox cannot run `xcodebuild` (nested `sandbox-exec`), CoreSimulator or `xctrace`, and may be denied `.git/index.lock`. Running Codex with `danger-full-access` is not permitted. So Claude runs builds, tests and simulator checks (`make check`, `make duo`) outside the sandbox, feeds the exact output back to Codex, and makes the commits Codex could not, using Codex's suggested messages.

## Commands

`make generate` creates the ignored Xcode project. `make format` formats owned Swift sources;
`make check` runs lint and host checks, builds Debug and isolated Release once, then runs the combined
test/snapshot selection on iPhone 17e / iOS 27.2 without rebuilding, with derived data in `build/DerivedData`. `Scripts/ci.sh` runs `make generate check`.

Use `make matrix` for all seven D1c devices, `make duo` for Duo matrix suites, or
`make targeted DEVICES="se duo" ONLY="AppTests/WelcomeSnapshotTests"` for fix rounds. Set
`SIM_CONCURRENCY` to 1–4 (default 4); `REUSE_BUILD=1` skips building unchanged products for targeted runs.
Logs/xcresults are under `build/test-results/<alias>/`. The runner uninstalls for fresh app state without
cleaning/rebooting; logic runs only on 17e. Device profiles reduce mid-size intro/snapshot coverage,
with full coverage on SE/17e/Duo/Pro Max. Recording remains opt-in; timing commands are in `Docs/tooling.md`.

Use `make lint`, `make test` or `make snapshots` for an individual check and `make perf` for the Release
launch metric scaffold. Phase 1's four dot-bearing primitive baselines were removed by the user's 2026-11-06 no-pattern
decision; launch image baselines follow in Phase 3c. `make tokens`, `make fonts` and `make assets` regenerate the committed design outputs.
`make generators-check` verifies their freshness, fonts and raster assets on the host and is part of
`make check`. Toolchain and Phase 1 verification, remaining simulator commands and environment
limitations are recorded in `Docs/tooling.md`.

Simulators use ad-hoc signing without a team so hosted Keychain tests can run. Device signing comes from ignored `Config/Local.xcconfig`, included
by `Config/Base.xcconfig`; copy `Config/Local.xcconfig.example` to get started. All working rules and traps,
including the no-trailer commit rule, are inherited from `AGENTS.md`.
