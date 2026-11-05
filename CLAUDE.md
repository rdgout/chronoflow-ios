@AGENTS.md

## Orchestration (Claude)

Codex implements and Opus reviews; Claude orchestrates and does not hand-write feature code.

1. Hand Codex one phase of `plan.md` with `codex exec -C /Users/rickgout/Sites/chronoflow-ios -s workspace-write`, on that phase's branch.
2. Opus reviewers check the diff against `plan.md`, the boards in `_design/canvas/`, the D1c device matrix and correctness/performance. Only findings that survive verification go back to Codex.
3. Repeat until the review is clean, then make sure `make check` passes and the commits are atomic and ticked in `plan.md`.
