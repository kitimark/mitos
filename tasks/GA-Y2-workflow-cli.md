# GA-Y2 workflow CLI and regression evidence

phase: gate architecture
goal: Workflow parse and leaves expose the checked reader through the native executable.
statement: none (IO adapter and qualification tooling; reader statements are in GA-Y2-yaml-read.md)
touches: gate/MitosGate/WorkflowCli.lean, gate/Main.lean, gate/workflow-test.sh, gate/workflow-check.py, gate/workflow-differential.py, gate/workflow-benchmark.py, gate/workflow-fixtures/, gate/MitosGate/Yaml/Line.lean, gate/MitosGate/Yaml/LineCases.lean, this file, tasks/GA-Y2-workflow-timings.json, ops/runs/
must_not_touch: core/, statements.lock, models.lock, .github/, eval/, plan/, .claude/, .cursor/, gate/vendor/
checks: build, workflow-test, PyYAML-differential, imports, lock, core-check, comparator-paranoid, accept-toy, lint-test
budget: 40 iterations · 4h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

[Issue #354](https://github.com/kitimark/mitos/issues/354) replaces the line reader with the parsed tree.
[Issue #405](https://github.com/kitimark/mitos/issues/405) requires qualification of the pinned parser's known gaps.
The reader and audit are in the first PR. This second PR switches the CLI and removes both old line-reader modules.

## Design

depth: build
revisit_when: none
modules: WorkflowCli.lean owns IO, exit codes and JSON conversion. Main.lean owns dispatch and usage. workflow-check.py owns fixed CLI regressions. workflow-fixtures/ owns source bytes and expected leaves or refusals. workflow-differential.py owns reproducible qualification against PyYAML.
types: A leaf's path is a JSON array of strings and natural numbers. A scalar value is a JSON string, an empty mapping is {}, and an empty sequence is [].
statements: The CLI calls Yaml.read once before printing any leaf. Refusal exits 1, file or argument errors exit 2, acceptance exits 0. It enables exit-on-panic before argument handling or file IO.
reuse: Yaml.read and Refusal.render, Doc.leaves, Lean.Json, and ciLine for diagnostics.
fixtures: All 63 source inputs from LineCases are retained unchanged in cases.json, including its standalone partition input. Accepted migrations have fixed decoded leaves from PyYAML.compose. Separate files cover every refusal constructor, parser qualification, shapes A to D, flow ambiguity and JSON escaping.
cut_line: Reader integration and qualification only. The valid shape-E environment expression remains accepted here.
deferrals: Placement rejects shape E in #359. The standing CI differential is #361. Oracle retirement is #400. The alias seam is tested by the reader PR because an earlier anchor is refused before a valid alias can be reached through read.
owner_decisions: The user merges this trust-infrastructure change after the required independent Opus-xhigh verdict.

## Regression migration

The old line reader's quoted escapes and multiline scalars now have decoded leaf expectations.
Root sequences and root scalars are refused because a workflow document must be a mapping.
Hashes inside plain or block scalar values remain data. Expression-bearing YAML comments are refused.
The former shell tests' copied-workflow, control-character, escape and standalone-block inputs remain covered.
Empty block scalars are refused at this pin, including the old copied-workflow fixture with an empty name block.
The malformed inputs from #354 remain parse refusals. The plain key `?a` remains accepted.

## Verification

The native executable passes 132 fixed fixtures through both verbs, the byte and opener boundaries,
missing-file and argument errors, the six accepted workflows and the exact owner-ping anchor refusal.
The fixed corpus has 44 accepted leaf expectations and 88 refusal expectations. Its 63 legacy inputs
were also independently extracted from main `fea3fe6` and compared byte for byte.

The seeded differential passes with PyYAML 6.0.3 and seed 354405. Of 700 mutations, 250 are accepted
and 450 refused. All accepted leaves are equal, with zero unexpected errors or panics.
The six main workflow leaf counts are 245, 15, 29, 50, 55 and 27 for ci, clear-needs-rebase,
land-protection, land, nightly and update-prs. The issue's ci count predates the current main.
The land workflow from #336 at `e91b849` has 108 leaves and also matches PyYAML.

A separate verifier corpus checks 976 sources through the native executable. It accepts 405 and
refuses 571, with zero leaf mismatches, panics or unexpected exit codes. These are separate cases,
not part of the seeded 700-mutation total.

Run the fixed regressions with `gate/workflow-test.sh`.
Run qualification with `python3 gate/workflow-differential.py` after installing PyYAML 6.0.3.
The differential generates 700 mutations with seed 354405 from six current workflows and one small workflow.
Its 28 mutation families each occur 25 times. Every accepted result must equal PyYAML.compose's ordered leaves.
Every refusal must have exit 1, a diagnostic and no leaf output. Any panic, other exit code or accepted mismatch fails the run.

## Runtime and build cost

The native ci.yml parse takes a median 0.188955 seconds over ten runs, with a range of
0.124068 to 0.239565 seconds. Every run accepts with no output or diagnostic. The input has
23,485 bytes and 245 leaves, independently compared with PyYAML before timing.
Each sample starts a fresh process after an unreported strace run warms executable and input pages.
Child CPU times track wall times. The unreported trace spends 0.003683 seconds in 130 syscalls,
so the observed runtime is CPU-bound rather than disk-bound. No speedup comparison is claimed.

The following build measurements reuse unchanged dependencies, including View, on both sides.
They are affected-target rebuilds, not full-project clean builds. The baseline is main `fea3fe6`.
Both sides rebuild their reader, WorkflowCli, Main and executable. The baseline rebuilds Line and
LineCases. The new side rebuilds Yaml and all 19 newly reached parser modules, including Lean and
native C outputs. Each side gets one unreported warmup before three alternating measured trials.
All six builds succeed, and every resulting executable accepts ci.yml outside the timed region.

| Trial | Before seconds | After seconds |
| --- | ---: | ---: |
| 1 | 9.412064 | 48.968916 |
| 2 | 10.034268 | 33.462328 |
| 3 | 9.995791 | 32.094124 |

The medians are 9.995791 and 33.462328 seconds, a delta of 23.466537 seconds.
The ranges are 9.412064 to 10.034268 and 32.094124 to 48.968916 seconds.
The new work is dominated by parser compilation. In the second trial, TokenParser alone takes
13 seconds, followed by the reader's 3.3 seconds, in Lake's module log.
The machine exposes five logical CPUs with a four-CPU quota and a 16 GiB memory limit.
No other local builds or test runs overlap these measurements.

[Raw timing data](GA-Y2-workflow-timings.json) records every runtime and build sample, full baseline
and reader commits, source/input/binary hashes, host limits and reset conditions.
The unchanged final runtime binary is also the one used for the independent 976-source replay.
The reusable runner resolves its baseline ref before archiving it and records the full SHA.

Reproduce after `lake build mitos-gate`, with strace installed:

```bash
python3 gate/workflow-benchmark.py --base fea3fe6 --output /tmp/workflow-benchmark-replay
```

The no-comments pass found no added comments, suppressions or reshape findings. It made no edits.
Local imports, the statement lock and run-log checks pass. Core replay and the paranoid comparator
stop at the container's read-only bwrap uid map. Toy acceptance passes provenance and lint, then
stops at the same sandbox setup. The lint suite passes 184 of 190 cases; six namespace-dependent
runner cases stop at the read-only uid map. No sandbox checks are disabled.

## Review fix for relative benchmark output

CodeRabbit found that a relative `--output` path was repeated when the build runner changed its
working directory. A real `--mode build` run reproduced `FileNotFoundError` after the first
baseline build. The runner now resolves the output path before creating directories.

The same command with a relative output directory then completes both warmups and all six
build trials, writes `results.json`, and validates every resulting executable on ci.yml.
The independent fix verifier can inspect the before and after logs and the six-result file.
The original timing samples above stay unchanged. They used an absolute output directory and
record the runner at the earlier commit; this repair run checks path handling and execution.
