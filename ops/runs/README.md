# Run logs

One JSON record per agent task attempt, each in its own file:
`ops/runs/<YYYY-MM-DD>/<task>-<role>-<attempt>.json`, such as
`ops/runs/2026-11-09/runlog-per-attempt-builder-1.json`. The file holds the record on one line.

| Field | Type | Meaning |
|---|---|---|
| `task` | string | task id, e.g. `P1-007` |
| `role` | string | `planner`, `builder`, `red-team`, `reviewer` |
| `model` | string | model that ran the attempt |
| `attempt` | int | attempt number for this task |
| `iterations` | int | edit-check cycles in the inner loop |
| `wall_min` | int | wall-clock minutes |
| `tokens` | int | total tokens |
| `errors_by_kind` | object | Lean error counts by kind (`type_mismatch`, `unsolved_goals`, `timeout`, …) |
| `lint_hits` | array | gate-1 violations the agent produced along the way |
| `escalations` | array | escalation steps used (`hint`, `grind`, `stronger-model`, `pair`, `split`, `spec`) |
| `outcome` | string | `in-review`, `merged`, `stuck`, `counterexample`, `abandoned` |
| `note` | string, optional | anything the numbers do not say, such as a correction to an earlier attempt's record |

Lint hits are expected while an agent works; a spike for one task usually means the task or its
statement is wrong.

## Writing a record

- Write the record on one line, then a newline, to a new file in the folder of the day you write
  it (UTC), named from the record's own `task`, `role` and `attempt`. The `task` starts with a
  letter or a digit, and the `task` and `role` hold only letters, digits, `.`, `_` and `-`,
  because they name the file.
- Each round of a PR is an attempt and adds its own file. Until the PR merges, it may rewrite its
  own files. A file on `main` never changes: put an update or a correction to an earlier record in
  the `note` of the next attempt's record.
- Before each push,
  `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
  shows only `A` lines.

## Merging

No merge driver is needed. A PR adds paths that no other PR writes, so a rebase replays only
those additions, and the change's `git patch-id --verbatim` stays the same. Replayed on the 19
bot rebases of #61 to #86, it stayed the same on 19 of 19; with one shared day file it changed on
all 19, because each record added on `main` moved the context lines of the PR's own line. Two PRs
that record one attempt on one day write one path: git keeps one file when the texts are equal,
and stops the rebase on a conflict when they differ, so the PR updater labels the PR
`needs-rebase` instead of keeping two records. One attempt on two days is two paths, which git
does not see; the check below fails it.

## Transition: the day files

Until #91, every record was a line of a day file, `ops/runs/<YYYY-MM-DD>.ndjson`, merged with
git's union driver. The four day files from 2026-11-06 to 2026-11-09 stay, and no PR may add one.
Until #113, a PR opened before this change may still append its lines to a day file that is
on `main`, and `.gitattributes` still merges the day files with union, so the PRs open now land
without a push. For those lines the old rules hold: never edit, delete or reorder a line that is
already in a day file, in any commit, even a line an earlier commit of the same branch added.
Union keeps both versions of an edited line, two records for one attempt, as on #62 twice (#74),
and a commit that deletes the stale copy does not hold, because the next rebase brings it back.
Such a PR's next attempt goes in a record file. #113 then freezes the day files, so that the
check wants each one as it is on `main`, and drops the union line.

## Enforced by CI

The `gate` job runs `lake exe mitos-gate runlog` on `ops/runs/`. It fails, with a `file:line`
annotation, when:

- a record file is not one line holding one record, is not named `<task>-<role>-<attempt>.json`
  from that record, has a `task` or a `role` with other characters, or is not in a folder named by
  a date, `YYYY-MM-DD`;
- an entry does not belong. Directly in `ops/runs/` belong `README.md`, the day files
  `*.ndjson` and the folders; in a folder, only `*.json` files. A symlink is refused and never
  read;
- two records, in day files and record files together, have the same `task`, `role` and
  `attempt`. `main` gets this check on every push;
- a record is not a JSON object with the fields above, or a field has the wrong type. `outcome`
  must be one of the five values, `errors_by_kind` must map to counts, and `lint_hits` and
  `escalations` must hold strings. The integers must be natural numbers, and `tokens` may also be
  `null`, as on every record so far, since no session meters tokens yet. Other fields are allowed.
  A blank line in a day file fails;
- on a pull request, against the merge base: a record file is missing from the PR's merge result
  or has other text; a line of a day file is missing, or occurs fewer times (an edit or a
  deletion); or the PR adds a day file.

The rules are proved in `gate/MitosGate/RunLog.lean`. When the check finds no problem, every
record of the merge base is a record of the head, no two records of the head share a key, and
every record file is one line holding one record, named by its key (`problems_eq_nil`,
`records_kept`, `recordFile_ok`, `singleLine?_spec`). A day folder then holds each key once
(`day_keys_nodup`), and a name built from a safe task and role is one plain path entry
(`fileName_safe`). For the day files, the append-only check holds exactly when the head is the
base plus some lines in any order, union of two sides that only append always passes it, and union
passes the duplicate check exactly when the lines of the base and both sides have distinct keys,
while an edited line that union kept next to the original fails it. The model of union, and what
git does with two record files at one path, are assumptions about git, replayed on real git by
`gate/runlog-test.sh`. The JSON parsing and file reading around the proved functions are not
proved.
