# tasks/P2-021-watch-deliver-move.md

phase: 2 (Watch track, #502; milestone 6)
goal: When a wait ends (the cut, the moment, `nextMove`, `finish`) and the text of every line it prints are fixed, so a caller that copies the trailer never spins and a healthy wait never ends blind; the 24 statements are proved.
statement: none locked. Named and audited: the cut, `nextMove` and `finish` statements of `Watch/Deliver.lean` and the statements of `Watch/Render.lean`, CopiedTrailerNeverSpins, OfferMarksTheReportedState and AHealthyWaitNeverEndsBlind among them.
touches: the rest of gate/MitosGate/Watch/Deliver.lean (the cut, `Moment`, `nextMove`, `finish`, and their statements; split into `Deliver/Report.lean` and `Deliver/Move.lean` past 600 lines, as planned), gate/MitosGate/Watch/Render.lean, gate/MitosGate/Watch.lean (imports), tasks/P2-021-watch-deliver-move.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the window, trailer, ride-along and healthy-end fixtures
budget: 120 iterations · 6h wall · 4.5M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-021 in `plan/phase-2.md` (Watch track), issue [#570](https://github.com/kitimark/mitos/issues/570). It is PR 7c of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-020 ([#569](https://github.com/kitimark/mitos/issues/569)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 7c's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 7c of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-020 (#569) merges. Re-check `nextMove`'s constants after P2-026's A/B (`tasks/502-watch.md`, revisit_when).
modules: PR 7c's part of the `Watch/Deliver.lean` row and the `Watch/Render.lean` row of `tasks/502-watch.md` (modules)
types: `Batch`, `Moment`, `Move`, `finish`, `cut`, `Moment.of` and `nextMove` in `tasks/502-watch.md` (types)
statements: the cut and `nextMove` groups of `Watch/Deliver.lean`, CopiedTrailerNeverSpins, OfferMarksTheReportedState, and `Watch/Render.lean` in `tasks/502-watch.md` (statements)
reuse: `Util.oneLine`, `printable` and `oneLine_printable` (`tasks/502-watch.md`, reuse)
fixtures: the window fixtures, `copiedTrailerBlocks`, `copiedTrailerBlocksAcrossARereadPoll` and the ride-along and healthy-end fixtures in `tasks/502-watch.md` (fixtures)
cut_line: row 7c of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: from `tasks/502-watch.md` (deferrals): an owned close or `gone` ranks with the notes in `cut`, never cut, with a statement that says so
owner_decisions: defaults 2a (a wait that exits on the first event) and 6

## Done when
- [ ] row 7c's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
