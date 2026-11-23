# tasks/P2-019-watch-wake.md

phase: 2 (Watch track, #502; milestone 6)
goal: Which facts wake which consumer is decided by identity (the app GitHub names, or an id the consumer recorded), quiet posts and the echoes of its own writes, never by the footer; the 13 Wake statements are proved.
statement: none locked. Named and audited: the 13 statements of `Watch/Wake.lean`.
touches: gate/MitosGate/Watch/Wake.lean, gate/MitosGate/Watch.lean (imports), tasks/P2-019-watch-wake.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the Wake fixtures
budget: 70 iterations · 4h wall · 3M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-019 in `plan/phase-2.md` (Watch track), issue [#568](https://github.com/kitimark/mitos/issues/568). It is PR 7a of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: owner question 5a and P2-018 ([#567](https://github.com/kitimark/mitos/issues/567)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 7a's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 7a of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-018 (#567) merges and the owner answers question 5a (`Wake.quiet` encodes it).
modules: the row of `tasks/502-watch.md` (modules) for `Watch/Wake.lean`
types: `Consumer`, `PostRecord`, `WriteRecord` and `Told` in `tasks/502-watch.md` (types)
statements: `Watch/Wake.lean` in `tasks/502-watch.md` (statements)
reuse: the `Land` wake and the `Carry.lean` layout (`tasks/502-watch.md`, modules)
fixtures: the `Wake` decide fixtures in `tasks/502-watch.md` (fixtures)
cut_line: row 7a of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: question 5a; defaults 5b (agents record review-thread reply ids with `watch.sh own`) and 6 (outside-account events ride along)

## Done when
- [ ] row 7a's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
