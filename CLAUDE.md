@AGENTS.md

## Orchestration (Claude)

Codex implements and Opus reviews; Claude orchestrates and does not hand-write feature code.

1. Hand Codex one phase of `plan.md` with `codex exec -C /Users/rickgout/Sites/chronoflow-ios -s workspace-write`, on that phase's branch.
2. Opus reviewers check the diff against `plan.md`, the boards in `_design/canvas/`, the D1c device matrix and correctness/performance. Only findings that survive verification go back to Codex.
3. Repeat until the review is clean, then make sure `make check` passes and the commits are atomic and ticked in `plan.md`.

## Commands

`make generate` creates the ignored Xcode project. `make format` formats owned Swift sources;
`make check` runs lint, tests and the snapshot suites on iPhone 17e / iOS 27.2, with derived data in
`build/DerivedData`. `Scripts/ci.sh` runs `make generate check`.

Use `make lint`, `make test` or `make snapshots` for an individual check and `make perf` for the Release
launch metric scaffold. Phase 0 snapshot suites contain smoke tests; image baselines follow in Phases 1
and 3c. `make tokens`, `make fonts` and `make assets` require the Phase 1 generators and explain when
they are missing. Toolchain verification and environment limitations are recorded in `Docs/tooling.md`.

Signing is optional for simulators. Device signing comes from ignored `Config/Local.xcconfig`, included
by `Config/Base.xcconfig`; copy `Config/Local.xcconfig.example` to get started. All working rules and traps,
including the no-trailer commit rule, are inherited from `AGENTS.md`.
