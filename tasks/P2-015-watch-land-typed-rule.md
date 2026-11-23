# tasks/P2-015-watch-land-typed-rule.md

phase: 2 (Watch track, #502; milestone 6)
goal: Optional: land's merge admission takes Voice's typed rule, so a typed owner comment that ends with a footer is the owner's words in `land` too, and land and pr-state keep one rule.
statement: none locked. `SpeaksAsLandUnlessTyped` and `AnswersAsLandUnlessTyped` (P2-013) become equalities with no exception, and every Snapshot statement stays proved.
touches: gate/MitosGate/Watch/Voice.lean (`SpeaksAsLandUnlessTyped` and `AnswersAsLandUnlessTyped` only: their non-typed premise goes), gate/MitosGate/Snapshot/Types.lean (the place on `Post`), gate/MitosGate/Snapshot/Fields.lean (`posts`, `speaks`, `answers`, `unanswered`), gate/MitosGate/Snapshot/Obs.lean (its anonymous `Post` constructors, `spokeInReview`, the proofs, and a note on whether `KeptMergeIsTheOwnersTypedApproval` or any other named land statement changes meaning), the review-comment reader in gate/MitosGate/SnapshotCli.lean, gate/MitosGate/Snapshot/Fixtures.lean, gate/snapshot-test.sh, tasks/P2-015-watch-land-typed-rule.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches`, and every other path outside `touches`
checks: build, imports, lock, lint-test, `bash gate/snapshot-test.sh`, `lake exe mitos-gate cheats`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check; the two equalities and every Snapshot statement proved
budget: 60 iterations · 3h wall · 2.5M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-015 in `plan/phase-2.md` (Watch track), issue [#564](https://github.com/kitimark/mitos/issues/564). It is PR 3c of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: a yes to owner question 8b, and P2-013 ([#562](https://github.com/kitimark/mitos/issues/562)).
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 3c's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 3c of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-013 (#562) merges and the owner answers question 8b.
modules: the PR 3c Snapshot set in `tasks/502-watch.md` (touches): a place field on `Snapshot.Post`, set by `posts` and by every constructor
types: `Place` (`issueComment | reviewComment | review`) in `tasks/502-watch.md` (types), as a field of land's `Post`
statements: `Watch/Voice.lean`'s SpeaksAsLandUnlessTyped and AnswersAsLandUnlessTyped in `tasks/502-watch.md` (statements), and every statement in `Snapshot/Obs.lean`
reuse: `Snapshot.speaks` and `Snapshot.answers` as they are, with the place added
fixtures: the existing Snapshot fixtures, with a typed comment that ends with the footer
cut_line: row 3c of `tasks/502-watch/PR-SEQUENCE.md`; on a no to 8b the row is dropped
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: question 8b (yes runs this row; no drops it, and land and pr-state then differ on typed words that end with a footer)

## Done when
- [ ] row 3c's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
