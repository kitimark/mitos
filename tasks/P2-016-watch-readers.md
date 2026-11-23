# tasks/P2-016-watch-readers.md

phase: 2 (Watch track, #502; milestone 6)
goal: Every REST read the waiter makes is a closed `Route` with bounded argv, and each route's answer is read by its own reader from live-captured answers; a bad owner item becomes a `Refused` item and the rest applies.
statement: none locked. Named and audited: the 7 statements of PR 4 in `Watch/Route.lean`, `Watch/Observe.lean` and `Watch/Time.lean`, IsoReadsBack (EXPENSIVE) among them.
touches: gate/MitosGate/Watch/Time.lean (`isoChars`, `ofHttpDate?`, IsoReadsBack), gate/MitosGate/Watch/Route.lean, gate/MitosGate/Watch/Observe.lean (all readers, `Plan.heads`), gate/MitosGate/Watch/Gh.lean (`Answer` and the pure header framing `frame` only), gate/MitosGate/WatchCli.lean (the test-only `read` arm, importing `Gh`), gate/MitosGate/Watch.lean (imports), gate/watch-test.sh, gate/watch-fetch.sh, gate/watch-fixtures/routes/, tasks/P2-016-watch-readers.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); reader cases through `MITOS_WATCH_TEST=1 mitos-gate watch read`; one real read of each route with `gate/watch-fetch.sh`, its result in the PR body; the rest of row 4's Check column
budget: 70 iterations · 4h wall · 3M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-016 in `plan/phase-2.md` (Watch track), issue [#565](https://github.com/kitimark/mitos/issues/565). It is PR 4 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-013 ([#562](https://github.com/kitimark/mitos/issues/562)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 4's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 4 of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-013 (#562) merges. Re-check `Observe` and `Time.ofHttpDate?` after this row's live read confirms `pull_request.merged_at` on the issues route, no app key on both review routes, and the `Date` header framing (`tasks/502-watch.md`, revisit_when).
modules: the rows of `tasks/502-watch.md` (modules) for `Watch/Route.lean`, the rest of `Watch/Time.lean` and `Watch/Observe.lean` (split into `Observe/Posts.lean` and `Observe/Pulls.lean` past 300 lines, as planned), and PR 4's part of `Watch/Gh.lean`
types: `Route`, `Repo`, `Sha40`, `OwnedHead`, `Gh.Answer`, `Fixed`, `Names` and `ofHttpDate?` in `tasks/502-watch.md` (types)
statements: `Watch/Route.lean`, `Watch/Observe.lean` and `Watch/Time.lean` in `tasks/502-watch.md` (statements). IsoReadsBack alone has a weaker fallback, a run-time check, and taking it is a deviation the PR body records
reuse: `Speech.stamp?`, `Shadow.Stamp.seconds`, `Base.Text`, `DecideList.sortStrings`, `Speech.isSha`, `Land (Pr)` and the `SnapshotCli` reader pattern (`tasks/502-watch.md`, reuse)
fixtures: the `Time` and `Observe` decide fixtures and `gate/watch-fixtures/routes/` in `tasks/502-watch.md` (fixtures)
cut_line: row 4 of `tasks/502-watch/PR-SEQUENCE.md`
deferrals: from `tasks/502-watch.md` (deferrals): the reviews reader's refused items join the feed as `Refused` (with P2-018), and a pull that left the open list with no close read gets one `pulls/N` read before `gone` is told (with P2-018 and P2-020)
owner_decisions: default 4 (placement in `gate/`)

## Done when
- [ ] row 4's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
