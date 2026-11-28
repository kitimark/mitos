# tasks/P2-018-watch-feed.md

phase: 2 (Watch track, #502; milestone 6)
goal: The feed keeps posts, closes and refused items keyed by GitHub's time and numbered by poll, and one poll's step updates the clone's one shared observation; the 24 Feed and Shared statements are proved.
statement: none locked. Named and audited: the statements of `Watch/Feed.lean` and `Watch/Shared.lean`.
touches: gate/MitosGate/Watch/Feed.lean, gate/MitosGate/Watch/Shared.lean, gate/MitosGate/WatchCli.lean (the test-only `replay` arm), gate/MitosGate/Watch.lean (imports), gate/watch-test.sh, gate/watch-fixtures/history-84/, tasks/P2-018-watch-feed.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); `history-84` through `MITOS_WATCH_TEST=1 mitos-gate watch replay`; the rest of row 6's Check column
budget: 110 iterations · 6h wall · 4.5M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-018 in `plan/phase-2.md` (Watch track), issue [#567](https://github.com/kitimark/mitos/issues/567). It is PR 6 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-017 ([#566](https://github.com/kitimark/mitos/issues/566)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 6's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 6 of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-017 (#566) merges.
modules: the rows of `tasks/502-watch.md` (modules) for `Watch/Feed.lean` and `Watch/Shared.lean`, and the `replay` arm of `WatchCli.lean`
types: `EntryKey`, `Fact`, `Feed`, `Shared`, `Feed.sinceAt`, `Feed.add`, `Shared.step`, `Shared.checked?` and `Shared.nextAges` in `tasks/502-watch.md` (types)
statements: `Watch/Feed.lean` and `Watch/Shared.lean` in `tasks/502-watch.md` (statements)
reuse: the `Carry.lean` and `Snapshot/Obs.lean` layouts (`tasks/502-watch.md`, modules)
fixtures: the `Feed` and `Shared` decide fixtures and `gate/watch-fixtures/history-84/` in `tasks/502-watch.md` (fixtures)
cut_line: row 6 of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: from `tasks/502-watch.md` (deferrals): the reviews reader's refused items join the feed (with P2-016), and the `pulls/N` read before `gone` (with P2-016 and P2-020)
owner_decisions: default 4

### reshape
Inputs for this row's build-depth upgrade, from the `/no-comments` pass over the sketch at 588dc1a (`tasks/502-watch/REVIEW-LOG.md`, Amendment 1). The Architect settles each one before the build. None is fixed in the sketch.
- reshape (no-comments): `EntryKey.refused` (`Feed.lean`): the key has no time. That forces the dedupe rule in `Feed.add` (against the kept entries only) and the second telling a day later, after pruning. Put the time in the key, or restructure.

## Done when
- [ ] row 6's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
