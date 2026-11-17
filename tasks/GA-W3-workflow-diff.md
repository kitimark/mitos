# GA-W3: Compare workflow leaves with PyYAML

phase: gate architecture
goal: Every PR compares the gate reader's decoded leaves with an independent PyYAML event parser on every workflow.
statement: none (external-parser tooling task)
touches: gate/workflow_leaves.py, gate/workflow-diff.sh, gate/workflow-diff-test.sh, .github/workflows/ci.yml, this file, own new ops/runs/ record
must_not_touch: statements.lock, models.lock, core/, eval/, gate/MitosGate/, .claude/, .cursor/, plan/, docs/process.md
checks: lake build, workflow differential and self-test, imports, lock, lint test, runlog, CI wiring tests
budget: 15 iterations, 2h wall, 1M tokens
escalation: hint, automation, stronger model, pair, split, revisit statement

## Context

[Issue #361](https://github.com/kitimark/mitos/issues/361) makes the one-time reader qualification permanent.
The CLI from #354 emits ordered JSONL paths and decoded scalar text.
The owner's qualification comment requires diagnostics to preserve JSON semantics while escaping CI command markers.

## Design

depth: build, executable scripts and named fixtures
revisit_when: Re-check test discovery after #164 merges.
modules: workflow_leaves.py owns event folding, leaf validation, comparison, and diagnostics. workflow-diff.sh starts isolated Python. workflow-diff-test.sh owns real-binary regressions and planted failures. ci.yml installs PyYAML when absent and runs the differential after the build.
types: A leaf is an object with a path list of string keys or integer indices and a value that is text, an empty mapping, or an empty sequence. File results are compared, allowlisted, or a difference.
statements: Exact ordered equality of decoded leaves against yaml.parse with SafeLoader. A refused file passes only at the repository's owner-ping.yml path with exit 1, empty stdout, and its exact anchor refusal line. A missing parser or executable exits 2.
reuse: Existing workflow parse and workflow leaves CLI commands, the checks job's gate/*-test.sh loop, Python JSON decoding, and PyYAML events before type resolution.
fixtures: Accepted text values including on, 0777, true, null, empty nodes, PANIC, and CI command markers. Changed, reordered, missing, malformed, and mistyped gate leaves. Anchor, alias, and tag refusals. A copied owner-ping basename, changed refusal text, and panic diagnostics. Missing Python, PyYAML, and gate. Default discovery with both workflow extensions.
cut_line: Compare shipped workflows on every PR. Leave the reader subset and existing YAML oracle job unchanged.
deferrals: Oracle retirement and prove coupling belong to #400. The older oracle-specific Shape D and red demonstration notes are outside this independent-parser change.
owner_decisions: The owner reviews the sole refusal exception, missing-parser failure, PyYAML installation step, and trusted-path merge. No spec files change.

## Verification

`lake build` passes with Lean 4.35.0. The real binary self-test passes 26 checks.
The live run compares six workflows, allowlists owner-ping.yml, and reports zero differences.
The differential takes a median 0.616 seconds across five complete runs, ranging from 0.579 to 0.654 seconds.
These measurements use the exact-main CI binary with warm filesystem caches while one unrelated Lean fixture module builds on another core.
Every run consumes both parsers' outputs for all seven files and exits 0. Process startup and parsing dominate this small input.

Imports, the 207-declaration statement lock, ten-module spec reach, runlog, CI trust, cache-key, cheat-shard, plan-task, and REST-wrapper checks pass.
The lint suite passes 184 of 190 cases. The six remaining cases fail before their child process starts because `unshare` cannot write `/proc/self/uid_map` in this environment.
The CI gate must pass those namespace checks, core replay, the comparator, and the corpus.

The no-comments pass removed 0 comments and raised 0 flags.
The supplemental verifier ran on GPT-6 Astra at xhigh. The repository-required Opus verifier is unavailable in this environment, so its verdict remains open.

The environment already imports PyYAML 6.0.3 with isolated Python. CI checks availability and installs python3-yaml if needed.
Local core replay cannot start because bubblewrap reports `setting up uid map: Read-only file system`. CI provides that check.

## Done when

- The real gate differential and self-test pass.
- CI is green at the PR head, with every review comment answered.
- The run-log record is written.
- The owner reviews the trust change and the required Opus verdict is available before merge.
