# Cached logs after restore (#58, #127, PR #125)

Design: n/a (restore-time workflow cleanup; no gate or spec change).

## Current scope

PR #125 started when `gate` built and ran the corpus in one job. Main at
`b59571b` has `checks`, three `cheat-shard` jobs, and `prove`. The first two
restore `.lake` and already remove cheat and mutant logs before installing
tools. `prove` uploads merged cheat logs only after successful aggregation.
Keep that layout and its checks. The original PR's removal of the old corpus
step's cleanup no longer applies to it.

Issue #58 is closed, but nightly `full` still restores `.lake` through setup
without clearing its logs. The migration in #158 changed the runner, not
cache cleanup. Clear both `.lake/cheats` and `.lake/mutants` immediately after
setup, since both have always-run uploads. Keep cleanup in `full`: the shared
setup also serves canary, which uploads neither artifact.

Issue #127 remains relevant to the shard uploads. Give the existing cleanup
steps in `checks` and `cheat-shard` `if: always()`, matching nightly. A failed
or cancelled restore can leave files behind. Cleanup must run before an
always-run upload, even when the corpus never starts. Preserve the shard's
existing pre-run cleanup, upload failure policy, and aggregate success rule.

Named-case runs keep their existing logs; the runner is unchanged. The setup
cache refactor in #168 remains separate. Its eventual replacement of the
inline steps must preserve unconditional cleanup before log uploads.

## Validation

- `.github/scripts/cache-logs.test.sh`: checks immediate placement and
  `always()` for all three jobs, executes each workflow's cleanup command on
  restored and cold fixtures, checks build caches survive, and checks a new
  run's log files are the only files present after cleanup.
- The regression script runs in CI `checks`. Local mutations removing the
  condition, delaying cleanup, and retaining mutant logs all fail the test.
- `.github/scripts/cheat-shard.test.sh` and
  `.github/scripts/ci-trust.test.sh`: pass.
- Actionlint 1.7.12 on CI and nightly: no findings (ShellCheck unavailable).
- Bash syntax and `git diff --check`: pass.

These fixture tests execute cleanup and inspect workflow conditions; they do
not simulate the GitHub scheduler or prove cancellation behavior on a hosted
runner. No hosted workflow was dispatched for this update. Lean is unavailable
in this environment; no Lean source, lock, or corpus expectation changed.
The original PR's historical gate evidence is not evidence for this new head.
