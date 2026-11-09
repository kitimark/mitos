# tasks/cheat-runner.md

phase: 1
goal: The cheat corpus runs in parallel in CI, through a runner written in Lean whose decisions (the `expect` parser, the reading of the gate's verdict line, the pass rule with `guards=`, the table and the scheduler) are proved, and no case's verdict changes.
statement: none (tooling task); theorems in `gate/MitosGate/Cheats.lean`, outside the lock
touches: gate/MitosGate/Cheats.lean (new, pure), gate/MitosGate/CheatsRun.lean (new, I/O), gate/MitosGate/GateId.lean (new, `GateId` moved from Accept.lean), gate/MitosGate/Accept.lean (the verdict line is `Cheats.Verdict.render`), gate/Main.lean (the `cheats` subcommand), eval/cheats/model_include_str_src/expect (`heavy=yes` only), .github/workflows/ci.yml (the corpus step), docs/process.md (running the corpus), ops/runs/2026-11-09.ndjson (appended lines only), tasks/cheat-runner.md
must_not_touch: statements.lock, models.lock, core/, lakefile.toml, other `expect` lines, models
checks: build, imports, lock, lint test, runlog on main's data, gate/runlog-test.sh, cheats (both runners, tables compared)
budget: 25 iterations · 6h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- #55 PR 10, from the owner's request on #55 and the design comment "PR 10 design: a Lean cheat
  runner, with timing numbers". The corpus step took about 1300–1400 s of the `gate` job, because
  `eval/cheats/run.sh` runs its 94 gate runs one after another.
- It has no row in `plan/phase-1.md`, which the owner keeps; #55 tracks it.

## Decisions
- **A subcommand, not a new exe.** `mitos-gate cheats [--jobs N] [--timeout S] [case]...`, so the
  lakefile does not change. Each run is its own `mitos-gate accept` process (the runner starts its
  own binary), so a crash or the 13 GB case stays out of the runner.
- **Pure decisions, thin I/O.** `Cheats.lean` does no I/O and holds every decision with its
  theorem. `CheatsRun.lean` lists cases, copies workspaces, spawns, times out, writes logs and
  prints; it decides nothing.
- **One verdict printer.** The gate prints its verdict line with `Cheats.Verdict.render`, and the
  runner reads it with `Verdict.parse`, proved exact (`parse_eq_some_iff`). `GateId` moved to
  `GateId.lean` so that `Accept.lean` can import the pure module without a cycle. A run must have
  exactly one `VERDICT:` line and exit with that verdict's code, and must not have timed out;
  otherwise it has no verdict and its case fails. `run.sh` ignored the exit code and took a
  prefix match, so the runner is stricter; on the corpus both agree.
- **The `expect` parser.** Unknown keys, a key given twice (but `lock_append`, which the docs
  already say may repeat), blank lines, a flag other than `yes`, a `full=` that is not `0`–`6` and a
  `guards=` rule no case can guard are errors. `run.sh` read every key with `grep`, so a missing
  `comparator_only=` or a typo passed silently.
- **`guards=`.** Ported line by line from `run.sh`'s `check_guards`, with the same messages, so the
  tables can be compared byte for byte. The count on the `FAIL` line is read only in the gate's own
  shape, `— N violation(s)`.
- **Re-pinning.** `model_approved=yes` re-pins in-process with what `mitos-gate lock-models` (#65)
  runs: `Accept.modelFiles`, gate 0's walker, and `Accept.renderLock`, whose output gate 0 reads
  back (`lockEntries_renderLock`). `run.sh` calls the subcommand and ignores its exit code; the
  runner fails the run on an I/O error instead.
- **Prints.** Every line with a case name, an `expect` value or gate output goes through
  `oneLine`. #68 adds a CI-safe line function that also escapes `##[` and a leading `::`; it takes
  over these prints.
- **Scheduler.** FIFO over a fixed order: heavy jobs, then runs expected to reach the comparator,
  then the rest. A heavy job starts only when nothing runs, and nothing starts while it runs.
  `--jobs` default and timing: see the PR.
- **Migration.** CI runs both runners and diffs their tables. `run.sh`, the comparison and the
  nightly job's `run.sh` step go in a follow-up PR once a CI run shows the tables match.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no `native_decide`, no new axioms
- [x] run-log record written (ops/runs/)
- [ ] CI: both runners green and their tables equal
