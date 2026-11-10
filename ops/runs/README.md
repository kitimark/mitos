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

## Day files

Until #91, every record was a line of a day file, `ops/runs/<YYYY-MM-DD>.ndjson`. The four day
files from 2026-11-06 to 2026-11-09 stay on `main`. They are frozen: each one must match `main`
line for line, and no PR may add a day file or append, edit, delete or reorder a line. A new
attempt goes in its own record file. There is no merge driver for the day files. While git's
union driver merged them, an edit became two records for one attempt, as on #62 twice (#74); that
driver is gone.

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
- on a pull request, against the merge base: a record file is missing or has other text; a day
  file differs from the merge base (an appended, edited, deleted or reordered line, or a deleted
  file); or the PR adds a day file.

The rules are proved in `gate/MitosGate/RunLog.lean`. When the check finds no problem, every
record of the merge base is a record of the head, no two records of the head share a key, and
every record file is one line holding one record, named by its key (`problems_eq_nil`,
`records_kept`, `recordFile_ok`, `singleLine?_spec`). A day folder then holds each key once
(`day_keys_nodup`), and a name built from a safe task and role is one plain path entry
(`fileName_safe`). A day file passes exactly when its lines equal the merge base
(`keptProblems_eq_nil`). The theorems `union_appendOnly`, `union_noDupKeys_iff` and
`edit_then_union` record why those files were safe to freeze: under the old union merge, two
sides that only appended kept every base line, and an edited line kept beside the original failed
the duplicate check. The check does not use them. What git does with two record files at one path
is replayed on real git by `gate/runlog-test.sh`. The JSON parsing and file reading around the
proved functions are not proved.
