# GA-Y1 YAML line layer

phase: gate architecture
goal: Workflow line parsing preserves all non-comment source and refuses unsupported YAML forms.
statement: MitosGate.Yaml.lex_chars, step_comment, step_block_ends, lex_drops_only_comments, lex_lines, lex_line_count
touches: gate/MitosGate/Yaml/Line.lean, gate/MitosGate/Yaml/LineCases.lean, gate/MitosGate/WorkflowCli.lean, gate/Main.lean, gate/workflow-test.sh, this file, ops/runs/
must_not_touch: core/, statements.lock, models.lock, .github/, eval/, plan/, .claude/, .cursor/
checks: build, workflow-test, imports, lock, core-check, comparator-paranoid, lint-test, accept-toy, cheats, live-workflows, PyYAML-differential, build-and-runtime-perf
budget: 40 iterations · 4h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

[Issue #348](https://github.com/kitimark/mitos/issues/348) defines the subset and acceptance evidence.
Structure and decoded leaves belong to #354. Placement belongs to #359.
The reader does not replace the shell placement scanner in #336.

## Design

depth: build
revisit_when: none
modules: Line.lean owns physical lines, lexical state, refusals and coverage. WorkflowCli.lean adapts IO and diagnostics. Main.lean dispatches. workflow-test.sh tests the executable against live files and mutations. LineCases.lean owns the short kernel/interpreter fixtures in the second PR, as #348's size rule requests.
types: Refusal and Line derive DecidableEq. RawLine names source number, indentation and body. State holds a block's owner and first content column, plus a pending plain scalar's source line and typed entry or standalone owner. An empty entry retains its column until a delayed scalar starts. Context distinguishes node start, plain, quoted and closed scalar modes and flow depth. Scanned preserves kept and cut text.
statements: lex_chars requires every source character to be LF or printable ASCII. step_comment preserves the complete state when no block is active. step_block_ends reprocesses a nonblank line at or below the owner's column outside the block. lex_drops_only_comments relates every result to a numbered source line and its independently checked partition. lex_lines gives exact ordered positional Corresponds, including all source lines. lex_line_count rules out omitted or duplicated physical lines.
reuse: ciLine and hexDigits from MitosGate.Util, existing CLI dispatch and CI's gate/*-test.sh discovery.
fixtures: eight escape/folding forms each have a kernel theorem and compiler/interpreter guard. Other fixtures cover A/B/C/D, comment boundaries, node refusals, block indentation, nested and spaced sequence owners, flow nodes and plain shell quotes.
cut_line: only the line layer. No tree, scalar escape decoding, placement policy, oracle dependency or workflow changes.
deferrals: #354 supplies structure and leaves; #359 supplies placement; #361 supplies standing differential checks; #376 supplies the external oracle package.
owner_decisions: Review the refusal subset, coverage and behavior statements, fixture expectations and the model-gap module doc. This is trust infrastructure and requires owner merge plus the required Opus verifier.

The affected system has a pure domain module behind a thin IO adapter. Main dispatches each verb
to its CLI module. The adapter reads one file, calls lex and writes safe diagnostics through ciLine.
The runtime tests invoke the actual executable. Lake builds imported fixtures with the executable.

Two alternatives were explored before implementation. A pipeline with proved scanner certificates
would carry reconstruction and quote-prefix evidence through each recursive scanner branch. A
validated-output reader constructs ordinary Line values and checks an independent partition
predicate before exposing them. The second keeps the public interface small and makes the
coverage obligation executable. The checker never calls lex, step or scan. Its own sourceStep follows block ownership before classification, and numbered records that context on every source line. It compares raw bytes,
requires a separated hash outside quotes for each cut, and requires the full original text on every source-annotated block line.
A block comment cannot be misfiled as a comment, because the source annotation requires a block result first. The character check is independent of classification. Structural induction proves exact ordered
correspondence through readLines. The partition check refuses with multiline if a candidate
partition cannot be certified. That branch is conservative and does not silently discard input.

The quote-prefix specification shares the lexical transition function with the scanner, but
computes from the kept prefix independently of scanner state. It opens quotes only at node starts.
A shell quote embedded in a plain scalar therefore cannot hide a YAML comment. Node starts inside
flow collections also get the alias, anchor, tag and double-quoted escape checks.

PyYAML 6.0.3 accepts a hash directly after a quoted or flow scalar as a comment, although the
issue's comment rule requires separation. This reader refuses those adjacency forms rather than
misclassifying their expression text. It also refuses unclosed flow collections, including those
with a trailing comment. This conservative subset costs no accepted repository workflow.
Sequence ownership uses actual source columns, including extra spaces and nested sequence dashes.

The source-context coverage strengthening takes the core reader beyond the issue's approximate
270-line estimate. The first PR has 453 code lines. The fixtures remain a separate PR as
the issue requests. The extra source annotation is retained because per-output partitions alone
would permit dropping a comment-shaped block line.

The lexical separator policy also distinguishes physical entry boundaries from flow boundaries.
Space or end-of-line separates document markers and sequence dashes. Mapping colons use their
flow context, including adjacent quoted flow keys and opening flow delimiters. This prevents
refusing literal `<<:]` text or hiding an alias behind `x:[*q]` in a flow collection.

## Throughput checkpoint

- Blocking first steps were repository and issue grounding, two distinct designs and Lean setup.
- The code, proof statements and CLI share one owner. Read-only design and review work can run independently.
- A dedicated worktree and task-specific scratch files separate mutable state. No worker shares source writes.
- One code writer avoids concurrent changes to the lexical state and coverage interface.

## Plain scalar owner correction

The first draft assumed a standalone scalar's first content indentation was its continuation
threshold. PyYAML disproved that premise on `a:\n    nee\n  ds\n`: it folds to `nee ds`.
The scalar belongs to the empty `a:` entry at column zero, so both content indents continue it.
State now retains an empty entry's owner across blank and comment lines. A delayed scalar
inherits that owner, and a root scalar has column zero as an inclusive continuation threshold.
The short fixtures cover equal and lower content indents for root, mapping and sequence scalars.

## Evidence

At the initial main f0aacc7 snapshot, the live reader accepts ci, nightly, clear-needs-rebase,
land-protection, land and update-prs. It refuses owner-ping at line 27 for its anchor.
A scratch Lean dump and PyYAML 6.0.3 yaml.scan agree exactly on 284 block lines and 76 expression
positions across the six accepted main workflows. The open #336 land.yml at e91b849 also accepts
and has identical block lines and expression positions. The PR body includes both rerunnable scripts.

The container lacks /run/user. Native lake check first failed when bubblewrap tried to create that
path under its read-only root. Local checks use COMPARATOR_BWRAP pointing to an adapter that
inserts --tmpfs /run immediately after --ro-bind / / and then passes every original argument to
/usr/bin/bwrap. All namespace, read-only, environment and writable-path restrictions remain.
The repository comparator and checks are unchanged. The adapted core lake check passes and lists
only Classical.choice, propext and Quot.sound.

## Done when

- [x] The reader, CLI, shell tests and dependent fixtures build and pass.
- [x] The required local checks pass.
- [ ] CI passes before owner merge.
- [x] The measured build increase is at most 30 seconds and ci.yml runtime is below one second.
- [x] No sorry, partial, native_decide or new axiom occurs in the new reader.
- [x] The root's no-comments pass and inherited-model advisory reviews cover the source. They do not replace the required independent Opus verifier.
- [ ] The required Opus verifier is available and passes before merge.
- [ ] The owner reviews the subset rules and statements, then merges the stack.

## Final local verification

All 14 gate shell suites pass. The lint executable passes all 190 cases. Imports, statement lock,
header and append-only run-log checks pass. ToyRequire passes gates zero through six with paranoid
comparison. Core lake check and all six comparator kernels pass with the /run adapter above.
The complete corpus performs 100 runs of 50 cases at --jobs 3 and --timeout 600, all as expected,
in 1792 seconds. That run used the unchanged acceptance paths before the last reader-only separator
correction. The final reader and fixture binary separately pass the workflow suite and differential.
CI repeats the corpus on the final published head.

The root's no-comments review reports zero deletions and zero flags. The model-gap module doc is
kept as a public API contract. Separate inherited-model advisory reviews checked the source-aware
coverage, scalar owners, context-sensitive boundaries, exact fixture results and decoded escape
values. This Codex session cannot run Opus. An external Claude Opus review subsequently reported FAIL on B1; the latest validation below records its fix and the required fresh verdict. Advisory passes do not supersede that verdict.

## Initial build budget

These measurements cover the first published source and 54 fixtures. The review-round figures below supersede them for the current source.

The claim is a build increase below 30 seconds and fixture compilation below 10 seconds. A
separate worktree uses copied warmed upstream outputs. Both sides rebuild Main and link the
executable. Each run removes Yaml and WorkflowCli generated library and C outputs. The before
side uses main's CLI dispatch; the after side uses the complete reader and all 54 fixture theorems
and eight guards. Five interleaved pairs include the three runs requested by the issue. All ten
builds exit zero, and logs confirm the changed modules actually compile.

The measurement runs after the corpus finishes. The machine exposes five cores with a four-CPU
quota. An earlier run under corpus contention is excluded. The measured added work is Lean
compilation and kernel reduction in LineCases, with C compilation and linking on the same path.
Process CPU usage and Lake's per-module durations confirm that work, rather than a cached no-op.

| Run | Before seconds | After seconds |
| --- | ---: | ---: |
| 1 | 8.860 | 11.408 |
| 2 | 3.952 | 10.319 |
| 3 | 4.013 | 12.026 |
| 4 | 4.078 | 10.358 |
| 5 | 4.166 | 10.522 |

The median is 4.078 to 10.522 seconds, an increase of 6.444 seconds. The before range is
3.952 to 8.860 seconds and the after range is 10.319 to 12.026 seconds. The full fixture module
compiles in 3.8 to 4.7 seconds across the five runs. This clears both build budgets.

Five silent successful ci.yml parses on the final reader-and-fixtures binary take 0.069475,
0.075745, 0.067498, 0.074312 and 0.071689 seconds, below the one-second budget.

## Review-round validation

CodeRabbit found that a hash immediately after a flow opener or comma could be kept as scalar
text, although YAML treats it as a comment. The following physical lines can then remain in the
same flow collection. The reader now refuses a hash at a node start after checking ordinary
separated comments. This closes `a: [#x]`, `a: {#x}` and `a: [b,#x]` without changing quoted,
plain `x#y` or block-scalar hashes. Three exact refusal fixtures and a positive flow-plain fixture
bring the total to 58 kernel theorems, with all eight interpreter guards retained. The native
workflow suite also pins the three refusals and accepted plain/empty-value comments.

Both pull requests were concurrently rebased onto main 583a13b. Their patch IDs and scoped source
blobs were unchanged. The fix preserves those new remote heads and the upstream oracle workflow.
The upstream commits change no root Lean build inputs, so the benchmark's before code is unchanged.

Against main 583a13b, all six workflows accept and owner-ping still refuses line 27. PyYAML 6.0.3
and the final reader agree on 298 block lines and 79 expression positions across the six accepted
workflows. The open #336 still has head e91b849; its land workflow also accepts and matches the
oracle exactly. Five silent successful parses of the new 581-line ci.yml take 0.077255, 0.082981,
0.080108, 0.083578 and 0.084352 seconds.

Three interleaved build pairs refresh the same benchmark method after the review fix. Every build
exits zero and rebuilds the new modules and Main. The fixture module compiles in 4.1 to 4.6 seconds.

| Run | Before seconds | After seconds |
| --- | ---: | ---: |
| 1 | 5.332 | 11.403 |
| 2 | 4.414 | 12.333 |
| 3 | 4.643 | 11.947 |

The medians are 4.643 and 11.947 seconds, an increase of 7.304 seconds. The before range is
4.414 to 5.332 seconds and the after range is 11.403 to 12.333 seconds. Both build budgets and the
one-second runtime budget pass. A fresh inherited-model advisory check passes 22 focused native
cases, including four valid multiline-flow disguises, positive comment/hash cases and refusal line
origins. The required Opus verdict remains pending.

## Standalone block header validation

The external Claude Opus report on #385 found B1: `a:\n  |\n  x #${{ y }}\n` was accepted while
its block content was cut as an ordinary trailing comment. The runtime and source audit both used
the standalone header's indentation instead of its parent owner's column. The earlier claims
about independent block classification did not cover that admitted shape correctly.

The closed subset now requires a block header on the same physical line as its mapping key or
sequence dash. A standalone header is refused at its own line with the existing multiline
refusal. This removes the unsupported shape instead of adding a second pending-parent algorithm
to the source audit. The module's public contract states this restriction. Source annotation is
only a specification of the admitted subset, not an oracle for arbitrary YAML.

Five exact fixtures cover the reported mapping case, delayed sequence, folded/chomped forms,
a comment between key and header, and retained inline sequence block data. There are now 63
kernel fixture theorems and eight interpreter guards; the longest lexer input is 25 characters.
The workflow suite pins standalone literal/folded/chomped refusals and inline positives. A fresh
advisory independently passes 38 valid PyYAML documents: 26 refused standalone forms at the
correct header line and 12 accepted positives, including literal pipe/hash block data.

All six current-main workflows and #336's land workflow still accept, while owner-ping refuses
its line-27 anchor. The current-main PyYAML differential remains empty at 298 block lines and 79
expression positions. Five successful silent ci.yml parses take 0.199628, 0.091565, 0.219108,
0.167107 and 0.173183 seconds, all below one second.

Three refreshed complete-target build pairs use the same warmed-input/output-deletion method.

| Run | Before seconds | After seconds |
| --- | ---: | ---: |
| 1 | 5.387 | 16.423 |
| 2 | 7.752 | 23.634 |
| 3 | 5.035 | 12.098 |

The medians are 5.387 and 16.423 seconds, an increase of 11.036 seconds. The before range is
5.035 to 7.752 seconds and the after range is 12.098 to 23.634 seconds. All paired increases
are below 30 seconds. Parallel full-build fixture-module durations range from 4.7 to 11 seconds;
one run exceeds the 10-second fixture target in that parallel schedule. To isolate the fixture
cost, three runs delete only all LineCases generated outputs with dependencies warm, then run
`lake build MitosGate.Yaml.LineCases:c.o`. This checks all 63 theorems and eight guards and compiles
the C object together, in 5.154, 4.704 and 4.820 seconds. Each run exits zero and the logs confirm
both outputs rebuilt. The isolated complete fixture target clears the 10-second budget; the
parallel-build outlier is retained here rather than hidden.

The latest reported external Opus verdict is FAIL on B1 at the earlier heads. The fix requires a
fresh Opus verdict before owner merge. The current Codex advisory and CodeRabbit results cannot
replace it. B2 is separately fixed by refusing hashes at flow node starts.
