# tasks/P2-020-watch-deliver-report.md

phase: 2 (Watch track, #502; milestone 6)
goal: Each caller is told what changed since its acked mark through its own topic (the facts, which read no subscription and no app; the notes, which reach every caller; and the lens), and a batch counts only once its exact offer number is taken; the 25 statements on offers, acks, the facts, the notes and the lens are proved, the two EXPENSIVE ones by their proof plans.
statement: none locked. Named and audited: the offer, ack, facts, notes and lens statements of `Watch/Deliver.lean`, NoNewsStaysQuiet and EveryNotableChangeIsTold (both EXPENSIVE) and TheCatchAllHearsEverything (the coverage statement) among them.
touches: gate/MitosGate/Watch/Deliver.lean up to `waking` (marks, offers, acks, `facts`, `notes`, `Subscription.lens`, `report`, and the statements on them), gate/MitosGate/Watch.lean (imports), tasks/P2-020-watch-deliver-report.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the Deliver fixtures on `report` and on the lens
budget: 160 iterations · 8h wall · 6.2M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-020 in `plan/phase-2.md` (Watch track), issue [#569](https://github.com/kitimark/mitos/issues/569). It is PR 7b of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-019 ([#568](https://github.com/kitimark/mitos/issues/568)).
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: the report is `notes ++ lens (facts)`, the offer records the subscription as data only, and a changed topic is told once; 25 statements, was 17. At the build-depth upgrade the Architect also decides whether OwnerWordsWakeWhoeverHearsWords gains a conjunct for a `refused` item: today an unreadable post wakes a caller only through ARefusedItemIsTold, WhatIsToldPassesTheLens and `Rides.has`, and no statement names that.
- Role: PR owner, hard (`opus`, `max` effort). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 7b's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 7b of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-019 (#568) merges.
modules: PR 7b's part of the `Watch/Deliver.lean` row of `tasks/502-watch.md` (modules): the report, the offer and the ack
types: `Mark`, `Pending` (its offer records the subscription, as data), `ConsumerState` (with `under`), `Item` (with the `newTopic` note), `Told`, `Subject`, `facts`, `notes`, `Subscription.lens`, `report`, `waking`, `ConsumerState.ack` and `ConsumerState.offer` in `tasks/502-watch.md` (types)
statements: the offer-and-ack, facts, notes and lens groups of `Watch/Deliver.lean` in `tasks/502-watch.md` (statements), except CopiedTrailerNeverSpins, OfferMarksTheReportedState and TheOfferIgnoresTheSubscription, which P2-021 proves
reuse: the `LandAnswer` and `CheatsSlot` layouts (`tasks/502-watch.md`, modules)
fixtures: the `Deliver` fixtures on `report` in `tasks/502-watch.md` (fixtures): replay, stale `--seen`, gap, mark ahead, fresh PR owner, own merge; and on the lens and the notes: `aFailuresAgentHearsOnlyTheRedCheck`, `aRidingFailureIsToldAndDoesNotWake`, `anotherItemIsDropped`, `aGreenGateBesideARedCheckWakesTheRidingRoot`, `aNarrowedRootCountsWhatItHides`, `aWiderTopicIsToldOnce`, `aNarrowerTopicIsToldWhatItPasses`
cut_line: row 7b of `tasks/502-watch/PR-SEQUENCE.md`; the cut, `Moment`, `nextMove` and `finish` wait for P2-021
deferrals: from `tasks/502-watch.md` (deferrals): the `pulls/N` read before `gone` is told (with P2-016 and P2-018)
owner_decisions: default 6 (`Rides.byDefault`: `outside` rides); questions 10 (`outside` already rides by default; the root may let `failed` and `alarms` ride too once a handler is named) and 11 (`peers` off by default), open on PR 0b

### reshape
Inputs for this row's build-depth upgrade, from the `/no-comments` pass over the sketch at 588dc1a (`tasks/502-watch/REVIEW-LOG.md`, Amendment 1). The Architect settles each one before the build. None is fixed in the sketch.
- reshape (no-comments): `ConsumerState.fresh` (`Deliver.lean`): "the only constructor `Store` uses for a new state" is a convention that nothing enforces. Make the structure's constructor private.
- reshape (no-comments): `waking` (`Deliver.lean`): the replay rule has no name (`if 1 ≤ r then ... t.topic m .nothing`: after a replay that was itself not taken, only what is new since that offer wakes, under the topic the offer was made under). Extract a named function.

## Done when
- [ ] row 7b's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
