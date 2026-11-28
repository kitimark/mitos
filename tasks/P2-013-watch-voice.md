# tasks/P2-013-watch-voice.md

phase: 2 (Watch track, #502; milestone 6)
goal: `mitos-gate watch unanswered` lists the owner's unanswered words per thread, read from the three post routes, by land's rule plus the #501 fix (a typed issue comment is words even with a footer, and never answers), and the 8 `Watch/Voice.lean` statements are proved.
statement: none locked (tooling task). Named and audited in `gate/MitosGate/Watch.lean`: the 8 statements of `Watch/Voice.lean`.
touches: gate/MitosGate/Watch/{Time,Voice,Observe}.lean (Time: `Epoch`, `ofStamp`, `ofIso?` only; Observe: the three post readers with `Refused` and `Reading`, and `readJsonFile` only), gate/MitosGate/WatchCli.lean (`unanswered` only, importing `MitosGate.Watch`), gate/MitosGate/Watch.lean (imports of Time, Voice, Observe; the audit), gate/Main.lean (one import, one usage block, the `watch` arm), gate/watch-test.sh (mode 100755), gate/watch-fixtures/posts-336/, docs/process.md (one check-matrix row), tasks/P2-013-watch-voice.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the rest of row 2's Check column
budget: 50 iterations · 3h wall · 2M tokens (`tasks/502-watch.md`, budget; the Architect re-budgets at the upgrade)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-013 in `plan/phase-2.md` (Watch track), issue [#562](https://github.com/kitimark/mitos/issues/562). It is PR 2 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: the merge of the #502 plan PR (PR 0). The owner answered questions 1 and 8a on 27 November, so PR 0 merges as it is.
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it. `docs/process.md` is owner-kept too.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 2's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 2 of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after PR 0 (the #502 plan PR) merges: the Architect's upgrade to build depth is this row's first step. Re-check `Voice` only if the owner refuses default 8c on PR 0b (8a and 8b are answered yes).
modules: the rows of `tasks/502-watch.md` (modules) for `Watch/Voice.lean`, PR 2's part of `Watch/Time.lean` and `Watch/Observe.lean`, `WatchCli.lean` (`unanswered`) and `Watch.lean`
types: `Place`, `Via`, `Speaker`, `Said`, `Excerpt`, `Refused`, `Reading`, and the signatures of the post readers and `unanswered` in `tasks/502-watch.md` (types)
statements: `Watch/Voice.lean` in `tasks/502-watch.md` (statements): TypedOnlyFromAnIssueCommentWithNoApp, ReviewRoutesAreNeverTyped, TypedIsAlwaysWords, AnAppPostIsNeverWords, SpeaksAsLandUnlessTyped, AnswersAsLandUnlessTyped, TypedWordsAreListedUntilAnswered, ExcerptIsOneLine
reuse: `tasks/502-watch.md` (reuse): `Speech.footer`, `Speech.apps`, the classes of `Snapshot.speaks` and `Snapshot.answers`, `Util.oneLine` and `oneLine_printable`, `Speech.stamp?`, `Base.Text`, the `SnapshotCli` reader pattern, `SpeechCli.parse`'s shape and the `Snapshot.lean` audit pattern
fixtures: the `Voice` decide fixtures and `gate/watch-fixtures/posts-336/` (`expected.json`, `classes.tsv`) in `tasks/502-watch.md` (fixtures)
cut_line: row 2 of `tasks/502-watch/PR-SEQUENCE.md`; `ofHttpDate?`, `isoChars` and the other readers wait for P2-016
deferrals: none of `tasks/502-watch.md`'s deferrals moves to or from this row
owner_decisions: questions 1 and 8a (answered yes on 27 November), default 4 (all of it in `gate/`, in `mitos-gate`) and default 8c (no app besides `claude` and `cursor` answers without its footer)

## Done when
- [ ] row 2's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
