# tasks/run-log-check.md

phase: 1
goal: CI fails a PR that edits or deletes a run-log line, and fails any tree with two records for one `(task, role, attempt)`, by a check whose algorithm is proved in Lean.
statement: none (tooling task); theorems in `gate/MitosGate/RunLog.lean`, outside the lock
touches: gate/MitosGate/RunLog.lean, gate/Main.lean (the `runlog` subcommand only), gate/runlog-test.sh, .github/workflows/ci.yml (one step in the `gate` job), ops/runs/README.md, ops/runs/2026-11-08.ndjson (one line)
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, models
checks: build, imports, lock, core check, core comparator --paranoid, example build, scorer, accept-toy --paranoid, lint test, cheats, runlog on main's data, gate/runlog-test.sh, actionlint, shellcheck
budget: 20 iterations · 3h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- #49 set `ops/runs/*.ndjson merge=union`, so a rebase keeps both sides' run-log lines. An edit to
  a line that is already on `main` then silently becomes two records for one attempt: union keeps
  the old line from `main` and the new one from the PR.
- It has no row in `plan/phase-1.md`, which the owner keeps.

## Decisions
- **A CI check, not a custom merge driver.** A driver needs `git config` in every clone and in
  the PR updater. During a rebase, a driver would run a script from the PR's own tree with the
  bot's token. The README already forbids edits, so the fix is to enforce that rule; union is then
  always correct.
- **In the gate package.** `gate/MitosGate/RunLog.lean` with a `mitos-gate runlog` subcommand,
  so no new package and no new toolchain. JSON is parsed with Lean core's `Lean.Json.parse`;
  `gate/` already imports `Lean`.
- **What is compared.** On a PR, the merge-base's `ops/runs/` (from `git archive`) against the
  checked-out tree, which on `pull_request` is the PR merged into its base. On a push to `main`,
  only the JSON and duplicate-key checks run. Lines are compared as text, so reformatting a line
  counts as an edit; order is ignored, since union does not fix it.
- **Key.** `(task, role, attempt)`, as the README's rule "one record per attempt" reads.
  Duplicates count across all files, since an attempt is one record wherever it is filed.
- **Fields.** Checked against the README's table and against every record on `main`. Looser than
  the table where the data needs it: `tokens` may be `null` (all ten records so far are). Stricter
  where the table gives only a container type: `errors_by_kind` values are counts, `lint_hits` and
  `escalations` hold strings, integers are natural numbers, `outcome` is one of the five values.
  `note` is optional and must be a string; the README's merging rules already use it, and the
  table now lists it. Blank lines and symlinks fail. A last line without a final newline is a
  line: git's union adds the newline when it merges such a file (checked on a scratch repo).
- **Files.** Every entry directly in `ops/runs/` whose name ends in `.ndjson`, a dot name
  included, since union's `*.ndjson` matches those too. A file or directory that is a symlink
  fails, so the check never reads, or prints part of, a file outside the tree.
- **Historical data.** `main` at `cb4aaa4` passes: 3 files, 10 records, no duplicate key. The one
  earlier in-place edit (`e15cc8c`, the `pr-updater-stacks` attempt-2 line) left no duplicate, so
  no allowlist is needed. Replayed with `--base` at `e15cc8c^` and `--head` at `e15cc8c`, the
  check fails at `2026-11-08.ndjson` line 2, so that edit would have been caught on its own PR.
- **Only one problem per kind.** The check reports the first missing line of each file and the
  first duplicate key; fixing one and rerunning shows the next.
- **Printing (#55, PR 3).** Every line the check prints that holds a file name, a field value or a
  message passes through `oneLine` (`gate/MitosGate/Util.lean`), the gate's one sanitizer for
  untrusted text; `quote` only quotes. The earlier denylist here (`unsafeChar`, `clean`) let the
  zero-width space and joiner, the soft hyphen and blank fillers through. `escapeData` and
  `escapeProperty` map one character at a time, so `example`s pin what `Problem.render` prints.

## Theorems (`gate/MitosGate/RunLog.lean`)
- `appendOnly_iff_count`, `appendOnly_iff_subperm`, `appendOnly_iff_perm_append`
- `appendOnly_eq_false_of_count_lt`, `appendOnly_edit`, `appendOnly_delete`
- `union_appendOnly`, `union_noDupKeys_iff` (under the stated model of union)
- `noDupKeys_iff`, `noDupKeys_perm`, `noDupKeys_eq_false_of_mem`, `edit_then_union`
- `firstMissing?_eq_none_iff`, `firstMissing?_spec`, `dupAt?_eq_none_iff`, `dupAt?_spec`: the
  locators the executable prints are right.

## Not in this task
- `gate/runlog-test.sh` is not a CI step: the brief allowed one step. A follow-up can add it.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)
