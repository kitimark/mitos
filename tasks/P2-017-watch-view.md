# tasks/P2-017-watch-view.md

phase: 2 (Watch track, #502; milestone 6)
goal: The level view of open pulls and the owner's heads, with their checks and the `ci` health alarms, is one function `View.of`, and its 19 KeyMap and View statements are proved, the alarms both ways.
statement: none locked. Named and audited: the 6 statements of `Watch/KeyMap.lean` and the 13 of `Watch/View.lean`.
touches: gate/MitosGate/Watch/KeyMap.lean, gate/MitosGate/Watch/View.lean, gate/MitosGate/Watch/View/Health.lean (the split of `View.lean` past 400 lines, as planned), gate/MitosGate/Watch.lean (imports), tasks/P2-017-watch-view.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the View fixtures
budget: 100 iterations · 5h wall · 4M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-017 in `plan/phase-2.md` (Watch track), issue [#566](https://github.com/kitimark/mitos/issues/566). It is PR 5 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-016 ([#565](https://github.com/kitimark/mitos/issues/565)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 5's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 5 of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-016 (#565) merges.
modules: the rows of `tasks/502-watch.md` (modules) for `Watch/KeyMap.lean` and `Watch/View.lean`
types: `KeyMap`, `Delta`, `PullFacts`, `Run`, `Checks`, `HeadFacts`, `Health`, `HeadAge`, `View`, `Change` and `ciHealth` in `tasks/502-watch.md` (types)
statements: `Watch/KeyMap.lean` and `Watch/View.lean` in `tasks/502-watch.md` (statements)
reuse: `DecideList.sortStrings` and the `Snapshot/Fields.lean` layout (`tasks/502-watch.md`, reuse and modules)
fixtures: the `View` decide fixtures in `tasks/502-watch.md` (fixtures)
cut_line: row 5 of `tasks/502-watch/PR-SEQUENCE.md`; the row is not split, because the alarms are stated over `View.of`
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: default 4

## Done when
- [ ] row 5's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
