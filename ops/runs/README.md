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

Lint hits are expected while an agent works; a spike for one task usually means the task or its
statement is wrong.

## Merging

Run-log files are append-only. `.gitattributes` sets `merge=union` for `ops/runs/*.ndjson`, so
when two branches append different lines, a rebase or merge keeps the lines from both sides and
does not stop on a conflict. Never edit or reorder a line that is already in a file: if both
sides touch the same line, union keeps both versions. To correct a record, append a new one.
