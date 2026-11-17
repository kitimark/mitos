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

## Original integration verification

The original integration at `4815e3f` passed 132 fixed fixtures through both verbs, the byte and opener boundaries,
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

These are historical measurements of the original reader/integration at `335259e` and `4815e3f`,
before the reserved-directive fix and the later main refresh. The current runtime sample is
recorded separately below. No new matched build-delta claim is made for this fix.

The original native ci.yml parse takes a median 0.188955 seconds over ten runs, with a range of
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
That original runtime binary was also the one used for the independent 976-source replay.
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

## Opus reserved-directive fix

The Opus review of #408 at `335259e` found a balanced expression swap through a discarded
reserved directive. The native CLI reproduced all five supplied forms before the fix: a
reserved directive, the full title-injection example, comment-like directive text, multiple
balanced directive lines and a directive after the document-end marker. Both verbs accepted
each input and exposed the decoded leaves.

The parent now refuses literal column-zero `%` source lines before scanning. This child adds
13 deterministic cases, retaining every one of the original 132 entries: ten refused reserved
directive or unindented quoted-continuation sources, and three accepted quoted/indented percent
data controls. Valid YAML with a percent line at column zero inside a quoted continuation is
intentionally outside this conservative subset. No quote lexer or vendor patch is introduced.

The original 700-mutation generator and seed remain unchanged. These directive cases extend
the fixed corpus rather than silently changing those 28 historical mutation families.
Both PR branches are refreshed onto main `0e33a5f`; the upstream change adds no callers of the
deleted Line or LineCases modules, and the integration has no remaining Lean imports of them.

The fresh native executable passes all 145 cases through both verbs, with 47 accepted leaf
expectations and 98 refusal expectations. The unchanged seeded 700-mutant comparison still
accepts 250 and refuses 450, with no PyYAML drift or panics. Each of the five originally accepted
exploit variants now returns the exact directive refusal and no leaf output from either verb.

An independent native matrix checks 1,544 sources through both verbs: 1,460 exact directive
refusals, 81 accepted percent-data controls whose full leaves match PyYAML, and three checks that
size/character/opener prefilters take precedence. Seed 354408 and PyYAML 6.0.3 produce no panics,
leaf drift or exit anomalies. The parent guard-removal controls fail ten source-directive guards
and one expression-bearing-flow guard respectively.

The current ten-run native ci.yml sample has median 0.067999 seconds and range 0.061614–0.074838
seconds. All ten parse calls accept without stdout or stderr. The 23,485-byte input still has 245
PyYAML-equal leaves. Median child CPU time is 0.065560 seconds, close to wall time; the unreported
strace run totals 0.008064 seconds across 130 syscalls. The measured path is CPU work rather than
waiting on disk, and no other build or test overlaps the samples. This is a current sample, not
a speedup comparison with the earlier measurements.

[Directive-fix evidence](GA-Y2-directive-checks.json) retains the raw ten samples, source/input/binary
hashes, host limits, mutation outcomes and independent matrix counts. Imports and the 206-entry
statement lock pass; new run logs use UTC folders. Core replay, paranoid comparison and toy
acceptance stop at the read-only uid map. The lint suite passes 184 of 190 cases, with the same
six namespace-dependent runner cases blocked. The sandbox stays enabled.

## Source structure allowance for #420

The earlier inferred claim of about two seconds at the 64 KiB cap is withdrawn. Input size alone
does not prevent resource exhaustion. The reader now refuses more than 2,048 raw `-?:,[{`
characters before scanning. The task's [reader design](GA-Y2-yaml-read.md#design-for-420) records
the conservative admission policy and its alternatives. The vendor and the three reader theorem
statements and proof bodies are unchanged.

The original safe 2,048-dash fixture exits 0 on main through both verbs. Its new regression fails
with `AssertionError: ('source-structure-budget', 0, '', 0, '')`. With the fix, both verbs exit 1
with `refused: 2049 structural characters exceeds 2048` and no leaf output. All 146 fixed fixtures
and 35 generated structure cases pass. The existing 700-mutation comparison keeps 250 accepts
and 450 refusals, with zero leaf mismatches and no `PANIC` markers. All six workflow leaf counts remain equal
to PyYAML 6.0.3.

The resource experiment measures 23 input families, with five fresh native processes per family.
Twenty-one inputs are exactly 65,536 bytes. The compact reproducer is 65,535 bytes, and ci.yml is
23,485 bytes. Accepted leaves match PyYAML or explicit expectations for deeply nested paths.
Every refusal has an exact expected diagnostic and no stdout. Trials alternate forward and reverse
family order. No builds or other tests overlap the timed region. Leaf qualification warms the
executable and input pages first. The native command is `mitos-gate workflow parse <input>`.

| Family | Median seconds | Range seconds | Maximum RSS, KiB |
| --- | ---: | ---: | ---: |
| Refused 65,535-byte compact sequence | 0.056894 | 0.053646 to 0.062197 | 99,176 |
| Accepted 2,047-level compact sequence at byte cap | 0.253613 | 0.244506 to 0.301336 | 168,424 |
| Accepted 2,048-key mapping with long shared prefixes | 2.619652 | 2.487568 to 2.694645 | 105,076 |
| Accepted quoted scalar with 21,840 one-space continuation lines | 12.155507 | 11.870566 to 13.228187 | 104,792 |

The dense quoted scalar is the slowest tested family. Its median child CPU time is 12.136629
seconds. The separate two-space quoted sample spends 0.024172 seconds in 130 syscalls under
strace, compared with its measured median 6.4692 seconds of child CPU time. The parser is doing
CPU work. The pinned quoted scanner rebuilds accumulated content on each folded line.
The multiline plain family reaches 666,684 KiB RSS. These residual scalar costs remain outside
the collection-depth fix and are tracked in [#431](https://github.com/kitimark/mitos/issues/431)
before #359, #360 or #361 consumes pull-request YAML. The general duplicate-key optimization remains #413 m2. None of these
measurements proves a universal maximum or a two-second bound.

[Resource evidence](GA-Y2-resource-checks.json) retains all 115 samples, source and executable
hashes, per-child RSS, exact diagnostics and trace output. The first 22-family matrix and the
dense scalar extension name their runner revisions separately. The host has five logical CPUs,
a four-CPU quota and a 16 GiB memory limit.

Reproduce the complete matrix after building the executable:

```bash
python3 gate/workflow-resource-benchmark.py --output /tmp/workflow-resource-checks
```

Imports and the 206-entry statement lock pass. Core builds. Core replay, paranoid comparison,
toy acceptance, cheat runs and six of 190 lint cases encounter read-only uid maps. No sandbox
check is disabled. The CodeRabbit CLI installs but its login reports `environment_unsupported`.
Remote PR review remains separate. The runtime cannot supply the required Opus-xhigh verdict.

CodeRabbit's review requested a proof of the new source-admission invariant. The private
`read_structure` now proves that every accepted source meets the raw-character allowance and
passes the existing axiom audit. Runtime admission code and the existing three proofs are unchanged.
The resource samples remain measurements of the executable at `9bbd900`, identified by the
recorded hashes. The proof addition does not justify repeating those measurements or claiming a
vendor runtime bound.

## Multiline admission for #431

The reader now refuses cumulative line-prefix work above 16,777,216 before vendor scanning,
after directive and structure checks. Work is the sum of one-based UTF-8 byte offsets ending
in LF, in every source context. Both verbs render the full count with no leaf output.
[The design and qualification](GA-Y2-multiline-bound.md) records the rejected LF-only design,
the replacement policy, exact boundary/priority tests and [raw evidence](GA-Y2-multiline-checks.json).
Historical samples above remain unchanged.

The native matrix passes 90 families × five fresh processes (450 samples); maximum observed
child CPU is 0.507467 seconds and RSS 166,504 KiB. These qualify named families on the recorded
host, not a universal two-second bound. All 147 fixtures, unchanged 35 structure cases and 37
line-work cases pass. The unchanged differential keeps 250 accepts/450 refusals with zero
leaf mismatches; current workflow leaf counts remain equal to PyYAML. The new task note records
the read-only UID-map checks and unavailable CodeRabbit CLI/Opus verification separately.
