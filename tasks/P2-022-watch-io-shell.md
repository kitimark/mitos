# tasks/P2-022-watch-io-shell.md

phase: 2 (Watch track, #502; milestone 6)
goal: `mitos-gate watch wait`, `own` and `status` run the pure modules against GitHub and the state files, and every fault case row 8 names behaves as stated.
statement: none locked. `Gh`, `Store` and `WatchCli` are tested, not proved (`tasks/502-watch.md`, statements, last item).
touches: gate/MitosGate/Watch/Gh.lean (the process), gate/MitosGate/Watch/Store.lean, gate/MitosGate/WatchCli.lean (`wait`, `own`, `status`), gate/watch-test.sh, gate/watch-fixtures/state/, gate/watch-fixtures/faults/, tasks/P2-022-watch-io-shell.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the fault-injection cases of row 8; the build log names no `sorry` in a `gate/MitosGate/Watch*` file; one real `wait --max 0` against the repository
budget: 80 iterations · 4h wall · 3M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-022 in `plan/phase-2.md` (Watch track), issue [#571](https://github.com/kitimark/mitos/issues/571). It is PR 8 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-021 ([#570](https://github.com/kitimark/mitos/issues/570)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 8's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 8 of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-021 (#570) merges.
modules: the rows of `tasks/502-watch.md` (modules) for `Watch/Gh.lean` (the process), `Watch/Store.lean` and `WatchCli.lean`
types: `Store.Read`, the state-file `version`, and the flags in `tasks/502-watch/DESIGN.md` (Usage, Interface depth)
statements: none proved here; the tested list at the end of `tasks/502-watch.md` (statements)
reuse: `Accept.writeByRename`, the `CheatsRun.runChild` pattern (copied into `Gh`) and `SpeechCli.parse`'s shape (`tasks/502-watch.md`, reuse)
fixtures: `gate/watch-fixtures/state/` and `gate/watch-fixtures/faults/` in `tasks/502-watch.md` (fixtures)
cut_line: row 8 of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: from `tasks/502-watch.md` (deferrals): `own comment|review-comment|review` reads the id back over REST before it records it
owner_decisions: defaults 4 and 5b

## Done when
- [ ] row 8's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
