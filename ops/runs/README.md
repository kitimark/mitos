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
| `outcome` | string | `merged`, `stuck`, `counterexample`, `abandoned` |

Lint hits are expected while an agent works; a spike for one task usually means the task or its
statement is wrong.
