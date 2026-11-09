# tasks/runlog-per-attempt.md

phase: 1
goal: Each run-log record is its own file, `ops/runs/<date>/<task>-<role>-<attempt>.json`, so a bot rebase keeps a PR's `git patch-id --verbatim` and no merge driver re-adds a stale record; the check over the new layout is proved in Lean.
statement: none (tooling task); theorems in `gate/MitosGate/RunLog.lean`, outside the lock
touches: gate/MitosGate/RunLog.lean, gate/Main.lean (the `runlog` help line only), gate/runlog-test.sh, .gitattributes, ops/runs/README.md, ops/runs/2026-11-09/runlog-per-attempt-builder-1.json, docs/process.md (the run-log storage line), .claude/skills/kitimark-mode/SKILL.md (step 6), tasks/runlog-per-attempt.md
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, models, .github/, ops/runs/*.ndjson
checks: build (no warnings), gate/runlog-test.sh, lint test, imports, lock, the run-log step as ci.yml runs it, the 19-pair replay
budget: 20 iterations · 4h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Part of #91, cause B7, approved by the owner. Every PR appended its record to one shared day
  file, `ops/runs/<date>.ndjson`, merged with `merge=union`. Each record that landed on `main`
  moved the context lines of every open PR's own line, so each bot rebase changed the PR's
  `git patch-id --verbatim` and its verdict had to be re-run; and union re-added a stale copy of
  an edited line, two records for one attempt (#62, #74).
- The B7 experiment rewrote history into one file per record and replayed the 19 single bot
  rebases of #61 to #86: the id stayed the same on 19 of 19, against 0 of 19 today, with no
  conflict and no duplicate.

## Decisions
- **Layout and key.** `ops/runs/<YYYY-MM-DD>/<task>-<role>-<attempt>.json`, one record on one
  line, the date being the day the record is written (UTC). The name is built from the record's
  key, so two PRs that record one attempt on one day write one path: git keeps one file when the
  texts are equal and stops the rebase with an add/add conflict when they differ, so the PR
  updater labels the PR `needs-rebase` instead of keeping two records. The same attempt on two
  days is two paths, which git does not see, so the duplicate-key check across all files stays.
  The name is not parsed back: `task` and `role` may both hold `-`, and nothing needs the key from
  a name, only the name from a key.
- **Names.** `task` and `role` hold only `[A-Za-z0-9._-]`, and `task` starts with a letter or a
  digit, so the name is one plain path entry, neither hidden nor read as an option
  (`fileName_safe`). All 38 records on `main` meet this.
- **One record per file.** The text is one line, with or without a final newline
  (`singleLine?_spec`). Two lines, an empty file or a blank line after the record fail.
- **What belongs.** Directly in `ops/runs/`: `README.md` (a plain file), the day files `*.ndjson`
  and folders. A folder's name must be a date and it holds only `*.json` files. Anything else
  fails, so a misplaced record cannot pass unread. In the merge-base copy only an unreadable day
  or record file is a problem, because `main` is checked on its own push.
- **Kept.** On a PR, every record file of the merge base must be in the head with the same text:
  a file on `main` never changes, and a correction goes in the next attempt's `note`. A PR may
  rewrite its own files before it merges, since a rebase replays them as additions.
- **The whole check is one pure function.** `readTree` reads both directories into a `Tree`, and
  `problems` decides; the I/O around it only adds what it could not read. So the theorems are
  about the function the executable runs, for any parser, not about a model of it.
- **Transition, not a migration.** On 2026-11-09 all seven open PRs (#83, #84, #86, #98, #105,
  #106, #108) append to `ops/runs/2026-11-09.ndjson`. Two ways were open:
  - Freeze the day files now and give owners a one-command migration. Every one of the seven
    turns red when the updater rebases it after this merges, and each needs a push, so seven CI
    runs, seven paid bot reviews and seven new verdicts, some past their round budget. The
    migration is also not one command: moving a line out of a day file needs a commit that
    deletes it, and union brings a deleted line back on the next rebase (the #74 shape), so each
    branch's history must be rebuilt.
  - Keep accepting appends to a day file that is on the base, and keep `merge=union` for the day
    files, until those PRs land. This merge changes no day file, so the seven rebase cleanly and
    their change ids stay the same (#105: `0b24831` on `main` and on this branch). Their ids still
    move when another of them lands, as today, but that ends as they land; new PRs get stable ids
    at once.
  The second is chosen: nothing breaks at once, and no push is forced. Its limit: only lines
  appended to a day file the base has; no PR may add a day file; a PR that pushes anyway puts its
  next attempt in a record file. #113 freezes the day files (equality) and drops the union line
  once no open PR appends to one, target 2026-11-16.
- **Existing proofs.** `appendOnly`, the `union_*` theorems and `edit_then_union` still describe
  the day files, which keep append-only rules and union during the transition, so they stay and
  are used. #113 turns the day-file rule into equality.
- **`ci.yml` needs no change.** Its step archives the merge base's `ops/runs` with
  `git archive "$base" ops/runs`, which includes the folders, and runs `runlog --base --head` on
  a PR and `runlog --head` on `main`. Its comment ("every run-log line of the merge-base must
  still be there, so union merges stay correct") stays true for the day files. So this PR leaves
  `.github/` alone.
- **Pinned change id.** #83 merged while this PR was open. It replaced all three places in the
  kitimark-mode skill that computed a change id with `git patch-id` (Round budget, Verdicts, the
  catch-up Status) by the content id and `mitos-gate carry`, which git configuration does not
  change. So the pinned `git patch-id` command from the B7 experiment is not needed in the skill,
  and this PR does not add it. `gate/runlog-test.sh` and the replay use it to compare ids.
- **Relation to #83.** With one file per attempt, plain `git patch-id --verbatim` stays the same
  over a bot rebase, so #83's special case for run-log lines (`ops/runs/*.ndjson` lines wherever
  union put them) is no longer needed for new PRs; a record file is a new path, which its exact
  diff already covers (`content-id` on this branch counts the record file among the 9 files
  outside the run logs). #83's carry chain check, that only the updater pushed since the verified
  head, is still needed, because a matching id alone does not say who pushed. The rebase onto
  #83 conflicted only in the usage text of `gate/Main.lean`, which keeps both sides.

## Theorems (`gate/MitosGate/RunLog.lean`)
- `singleLine?_spec`: a record file's text is one non-empty line without `\n`, with or without a
  final `\n`.
- `recordFile_ok`: a record file that passes holds one record from that line, with a safe task
  and role, and is named `fileName` of its key.
- `fileName_safe`: such a name holds only `[A-Za-z0-9._-]` and starts with a letter or a digit.
- `day_keys_nodup`: a folder whose files pass holds each key at most once.
- `records_kept`: when the base's day-file lines are kept (`appendOnly`) and its record files are
  in the head, every base record is a head record, for any parser.
- `parseProblems_eq_nil`, `dupProblems_eq_nil`, `keptProblems_eq_nil`, and `problems_eq_nil`,
  which states what a pass means: no two head records share a key, every head line and record
  file parses, every record file is in a date folder and passes `recordFile`, and, given the base,
  every base record is kept and no day file is added.
- `lineRecords_map`, `located_map`, `lineErrors_eq_nil`: the located records the error messages
  use are the records.
- Kept from `tasks/run-log-check.md`: `appendOnly_*`, `union_appendOnly`, `union_noDupKeys_iff`,
  `noDupKeys_*`, `edit_then_union`, `firstMissing?_*`, `dupAt?_*`.

## Evidence
- The 19-pair replay on this layout (day files as at the pairs' common merge base `c79e03f`, every
  later record its own file): the id stayed the same on 19 of 19 bot rebases, against 0 of 19
  with the shared day file; every rebase was clean, and this branch's `runlog --base --head`
  passed on all 19 replayed heads.
- #105's branch, rebased locally onto this branch (not pushed): clean, its change id the same,
  and the run-log step as `ci.yml` runs it passes. With #108 landed first, #105 rebases cleanly
  through union and passes; with its next attempt as a record file it passes too.
- `gate/runlog-test.sh`: the per-file replays (an edit to the PR's own record keeps the id and
  one file; one attempt on one day stops on an add/add conflict; on two days the check fails; an
  identical record already on `main` is dropped) and the transition replay.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)
