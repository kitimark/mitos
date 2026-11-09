# Run logs

One NDJSON record per agent task attempt, one file per day: `ops/runs/YYYY-MM-DD.ndjson`.

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

## Merging

Run-log files are append-only. `.gitattributes` sets `merge=union` for `ops/runs/*.ndjson`, so
when two branches append different lines, a rebase or merge keeps the lines from both sides and
does not stop on a conflict. Never edit, delete or reorder a line that is already in a file, in
any commit, even a line an earlier commit of the same branch added. A rebase, such as the PR
updater's, replays a branch commit by commit, so a later commit that rewrites the line replays
as an edit, and union keeps both versions: two records for one (task, role, attempt), which
turn `gate` red, as on #62 twice (#74). A commit that deletes the stale copy does not hold,
because the next rebase brings it back. A branch whose history already edits a line is rebuilt
so that its run-log change is appended once. Do not correct a record by appending a second
record for the same attempt either: the schema has no marker for which one wins, and union does
not fix line order. Put an update or a correction in the `note` of the next attempt's record.

## Enforced by CI

The `gate` job runs `lake exe mitos-gate runlog` on `ops/runs/*.ndjson` (the files directly in
this directory, the ones `.gitattributes` merges with union). It fails, with a `file:line`
annotation, when:

- on a pull request, a line of the merge-base's file is missing from the PR's merge result, or
  occurs there fewer times: an edit or a deletion. New lines and new files pass, in any order;
- two records, in any files, have the same `task`, `role` and `attempt`. This is what an edit
  becomes after union keeps both versions, so `main` gets the same check on every push;
- a line is not a JSON object with the fields above, or a field has the wrong type. `outcome`
  must be one of the five values, `errors_by_kind` must map to counts, and `lint_hits` and
  `escalations` must hold strings. The integers must be natural numbers, and `tokens` may also be
  `null`, as on every record so far, since no session meters tokens yet. Other fields are allowed.
  A blank line fails, and so does a file that is a symlink rather than a plain file.

The rules are proved in `gate/MitosGate/RunLog.lean`: the append-only check holds exactly when
the head is the base plus some lines in any order, union of two sides that only append always
passes it, and union passes the duplicate check exactly when the lines of the base and both sides
have distinct keys, while an edited line that union kept next to the original fails it. The model
of union in those theorems is an assumption about git, stated there and replayed on real git by
`gate/runlog-test.sh`. The JSON parsing and file reading around the proved functions are not
proved.
