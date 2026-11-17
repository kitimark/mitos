# GA-Y6: Retire the duplicate L4YAML oracle

phase: gate architecture
goal: CI keeps the independent PyYAML comparison and stops building a second copy of the gate's YAML parser.
statement: none (CI tooling task)
touches: .github/workflows/ci.yml, .github/actions/setup/action.yml cache description, .github/scripts/cheat-shard.test.sh, .github/scripts/cache-key.test.sh, .github/scripts/install-toolchains.sh, deleted .github/scripts/yaml-oracle.sh and yaml-oracle.test.sh, deleted eval/yaml-oracle/, this file, own new ops/runs/ records
must_not_touch: statements.lock, models.lock, core/, gate/, .claude/, .cursor/, plan/, docs/process.md
checks: lake build, imports, lock, runlog, workflow differential and fixtures, CI wiring tests, shellcheck, actionlint
budget: 15 iterations, 2h wall, 1M tokens
escalation: hint, automation, stronger model, pair, split, revisit statement

## Context

[Issue #400](https://github.com/kitimark/mitos/issues/400) retires the oracle added in #376.
The gate now uses the same L4YAML parser, so that oracle cannot provide an independent comparison.
Vendoring #397 and the PyYAML leg #361 are merged. The owner requested this implementation.

## Design

depth: build, deletions and regression assertions on the CI graph
revisit_when: none
modules: ci.yml retains checks, cheat-shard, prove, and gate. The toolchain installer and cache-key test cover all remaining tracked toolchain files. cheat-shard.test.sh pins the complete CI job list and prove's two upstream results.
types: prove needs exactly checks and cheat-shard. CHECKS and SHARDS receive those jobs' actual results and are passed to cheats aggregate.
statements: The independent PyYAML check remains in checks. Failed, cancelled, or skipped required upstream jobs cannot satisfy the aggregate. The retired toolchain and oracle job have no live callers.
reuse: Existing cheat-shard.test.sh job and timeout assertions, cheats aggregate failure-status fixtures, workflow-fixtures/shape-d.yml, and cases.json old-script-escape.
fixtures: Nine planted workflow regressions remove either dependency, add the retired dependency, replace either result with success, remove either aggregate argument, remove always(), or add an unpinned job.
cut_line: Retire the duplicate parser and pin prove's coupling. Change no parser, independent comparison, or core statement.
deferrals: The repository-required Opus verdict and owner review of the removed check remain merge prerequisites.
owner_decisions: The owner reviews and merges this trust-infrastructure change. No spec approval is needed.

## Verification

The affected CI tests pass, including cache-key, cache-logs, cancel-superseded, ci-trust, and land-protection.
The cache-key check still finds five cache blocks, eleven tracked pin files, and six cache paths.
All nine planted workflow regressions fail cheat-shard.test.sh with exit 1.
A stub elan records only `toolchain install leanprover/lean4:v4.35.0` from the real installer.
Shell syntax checks, actionlint 1.7.12, and shellcheck 0.11.0 at warning severity pass.
Shellcheck's informational SC2016 notices describe intentional literal workflow expressions already used by this test.

The preserved Shape D fixtures assert that `"${{ \\x6eeeds.decide.outputs.pr }}"` decodes to `needs`.
The fixture file and the old-script-escape case remain unchanged.

The separate no-comments pass raised zero flags and deleted zero comments. It restored no comments and required no rerun or constraint encoding.
The CodeRabbit CLI installer completed, but the CLI cannot start because its config directory is read-only:
`EROFS: read-only file system, mkdir '/home/agent/.coderabbit'`.
The same failure persists with a narrow filesystem permission grant. Version, auth status, and agent login cannot complete. GitHub's CodeRabbit review remains a separate required check.

## Historical PR wall times

The wall metric is workflow `run_started_at` through the final gate job's `completed_at`.
These are three completed full PR runs before retirement, excluding label-only runs:

| Run | Wall to gate | Oracle job | Lean 4.32 download in oracle log |
| --- | ---: | ---: | --- |
| [44082689070](https://github.com/kitimark/mitos/actions/runs/44082689070) | 393 s | 28 s | yes, 12:23:54 UTC |
| [44081082127](https://github.com/kitimark/mitos/actions/runs/44081082127) | 357 s | 22 s | yes, 12:13:23 UTC |
| [44081077253](https://github.com/kitimark/mitos/actions/runs/44081077253) | 486 s | 21 s | yes, 12:13:20 UTC |

The median before retirement is 393 seconds, with a 357 to 486 second spread.
Each oracle job restored its own package cache and still downloaded `lean-4.32.0-linux.tar.zst`.
The samples use different prior PR heads and runners, so they do not isolate the effect of this change on total wall time.
The after sample uses the initial full PR run and two reruns at the same head, without extra commits for timing.
The PR body and catch-up hold the final hosted measurements and check results.

## Done when

- The local checks and CI gate pass.
- Three before and three after PR runs document the toolchain download removal and wall-time spread.
- User and CodeRabbit comments are answered at the current head.
- The run-log record is written.
- The owner reviews the job graph and a required Opus verdict is available before merge.
