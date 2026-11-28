# tasks/P2-019-watch-wake.md

phase: 2 (Watch track, #502; milestone 6)
goal: What a caller asks to hear is a closed type whose typed flags read back (`Watch/Topic.lean`), and which facts wake a caller, and of which kind, is decided by identity (the app GitHub names, or an id the caller recorded), quiet posts and the echoes of its own writes, never by the footer; the 19 Topic and Wake statements are proved.
statement: none locked. Named and audited: the 4 statements of `Watch/Topic.lean` and the 15 of `Watch/Wake.lean`, TheTrailerFlagsReadBack (moderate) among them.
touches: gate/MitosGate/Watch/Topic.lean, gate/MitosGate/Watch/Wake.lean, gate/MitosGate/Watch.lean (imports), tasks/P2-019-watch-wake.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: build, imports, lock (`lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check`), lint-test (`lake exe mitos-lint-test`), cheats (`lake exe mitos-gate cheats`, locally since the row touches `gate/`), `bash gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, the run-log check (`lake exe mitos-gate runlog --head ops/runs`); the Topic and Wake fixtures
budget: 95 iterations · 5h wall · 4M tokens (`tasks/502-watch.md`, budget)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-019 in `plan/phase-2.md` (Watch track), issue [#568](https://github.com/kitimark/mitos/issues/568). It is PR 7a of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: PR 0b (amendment 1, which carries the owner's answer to 5a: each agent's own topics) and P2-018 ([#567](https://github.com/kitimark/mitos/issues/567)).
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: it adds `Watch/Topic.lean` (kinds, scope, what rides, the subscription and its typed flags), and `Wake` gives each fact its kind; 19 statements, was 13.
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 7a's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. This row is PR 7a of `tasks/502-watch/PR-SEQUENCE.md`, and its sketch under `tasks/502-watch/sketch/` was never type-checked. Before a PR owner starts, the Architect type-checks this slice with the repository's toolchain, writes the stub bodies its statements are stated over, checks the statements against them, and upgrades this file to build depth (`tasks/502-watch.md`, Design).
revisit_when: re-check after P2-018 (#567) and PR 0b merge. Re-check the default topic after the owner answers question 11 on PR 0b.
modules: the rows of `tasks/502-watch.md` (modules) for `Watch/Topic.lean` and `Watch/Wake.lean`
types: `Scope`, `Kind`, `Kinds`, `Rides`, `Topic`, `Subscription`, `Flag`, `Consumer`, `PostRecord`, `WriteRecord` and `Told`, and the signatures of `quiet`, `Post.kind`, `Change.kinds`, `Subscription.flags` and `Subscription.ofFlags?` in `tasks/502-watch.md` (types)
statements: `Watch/Topic.lean` and `Watch/Wake.lean` in `tasks/502-watch.md` (statements)
reuse: the `Land` wake and the `Carry.lean` layout, and `Observe.lean`'s `Listed` layout for `Topic.lean` (`tasks/502-watch.md`, modules)
fixtures: the `Topic` and `Wake` decide fixtures in `tasks/502-watch.md` (fixtures)
cut_line: row 7a of `tasks/502-watch/PR-SEQUENCE.md`; the lens (`Subscription.lens`) waits for P2-020, the flags' text for P2-021 (`Render`) and P2-022 (`WatchCli.flags?`)
deferrals: from `tasks/502-watch.md` (deferrals): selecting on labels, milestones, issue versus pull request, one check or one app is left out on purpose
owner_decisions: question 5a (answered: each agent's own topics) and question 11 (`peers` off by default, open on PR 0b); defaults 5b (agents record review-thread reply ids with `watch.sh own`) and 6 (a wait with no `--ride` lets `outside` ride, `Rides.byDefault`)

### reshape
Inputs for this row's build-depth upgrade, from the `/no-comments` pass over the sketch at 588dc1a (`tasks/502-watch/REVIEW-LOG.md`, Amendment 1). The Architect settles each one before the build. None is fixed in the sketch.
- reshape (no-comments): `Wake.passingConclusions`: a list of strings, so "`cancelled` fails, and a conclusion never seen fails" is policy kept in prose. Use a closed `Conclusion` type.
- reshape (no-comments): `Change.kinds` (`Wake.lean`): the `[.passed]` results for a head change with nothing newly finished, or with no head after it, are fillers that nothing reads. Make the result non-empty by its type, or an `Option`.

## Done when
- [ ] row 7a's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement
- [ ] run-log record written (ops/runs/)
