# GA-Y1 kernel and interpreter fixtures

phase: gate architecture
goal: The workflow line reader's small inputs have exact kernel-checked results and matching interpreter behavior.
statement: 63 exact-result fixture theorems in MitosGate.Yaml
touches: gate/MitosGate/Yaml/LineCases.lean, gate/MitosGate/WorkflowCli.lean, this file, ops/runs/
must_not_touch: core/, statements.lock, models.lock, .github/, eval/, plan/, .claude/, .cursor/
checks: build, workflow-test, live-workflows, PyYAML-differential, fixture-build-time
budget: 15 iterations · 2h wall · 500k tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

This is the dependent fixtures PR for [#348](https://github.com/kitimark/mitos/issues/348).
The issue requests a second PR with LineCases.lean if the line layer exceeds 400 changed lines.
The first PR implements the reader, CLI, source-aware coverage and executable tests.
This PR imports the fixtures from WorkflowCli so the normal executable build checks them.

## Design

depth: build
revisit_when: none
modules: LineCases.lean owns short exact-result fixtures. WorkflowCli.lean imports it so Lake checks the fixtures on each affected build.
types: the first PR's Refusal, Line and Except DecidableEq instances.
statements: eight exact escape/folding theorems, eight matching interpreter guards, and 55 exact-result regressions.
reuse: MitosGate.Yaml.Line; no separate scanner, oracle dependency or runtime fixture loading.
fixtures: hexadecimal, short and long Unicode, NEL, escaped line break, folded double/single/plain; A/B/C/D; comment boundaries; block ownership/indentation; node refusals; flow aliases/escapes; scalar-owner and contextual-separator regressions.
cut_line: build-time short fixtures only. Real workflow text remains runtime evidence, never include_str input.
deferrals: external oracle packaging remains #376; standing differential remains #361.
owner_decisions: Review the exact refusal/acceptance results and the eight escape rows, then obtain the required Opus verdict before owner merge.

## Evidence

`lake build mitos-gate` builds the fixtures with the interpreter enabled and runs all eight guards.
`gate/workflow-test.sh` passes against that binary. The final reader's source positions and block
lines match PyYAML 6.0.3 for all six accepted main workflows and #336's land workflow at e91b849.
The first PR's task records the full check matrix, source ownership model and benchmark method.

## Done when

- [x] All 63 exact-result kernel theorems and all eight interpreter guards compile.
- [x] The actual binary passes workflow tests and the live scanner differential.
- [x] The isolated complete fixture-and-C target takes 4.704 to 5.154 seconds across three builds.
- [ ] CodeRabbit is reviewed or explicitly refuses at the final head, with every finding answered.
- [ ] The required Opus verifier passes before owner merge.

Before the standalone-block fix, the complete reader-plus-fixtures target added 7.304 seconds by median, from 4.643 to 11.947 seconds.
The first PR records those earlier pairs and the current follow-up. The earlier flow-fix ci.yml samples took 0.077255 to 0.084352 seconds. The no-comments pass reports zero
deletions and zero flags. Inherited-model advisory review independently confirms all eight decoded
YAML values and all 62 lex fixture inputs. These passes do not replace the required Opus verdict.

The review round adds three flow-node hash refusal theorems and a positive flow-plain hash theorem.
The normal comment branch remains before the new refusal. Current main 583a13b has 298 block lines
and 79 expression positions across its six accepted workflows; both dumps match PyYAML 6.0.3.

## Standalone block review fix

The current subset refuses block headers on a separate line from their key or sequence dash.
Five exact cases pin mapping/sequence/folded/chomped/commented refusals and retained inline sequence
block data. The final module contains 63 kernel theorems and eight guards, with lexer inputs at
most 25 characters. A fresh advisory passes 38 valid PyYAML documents, including 26 refusals and
12 accepted inline/literal-data cases. The external Opus FAIL on B1 remains the latest reported
verdict until a fresh Opus review checks the fix.

The latest complete-build median overhead is 11.036 seconds over three interleaved pairs. The
isolated complete fixture-plus-C-object target takes 5.154, 4.704 and 4.820 seconds. A parallel
full-build fixture duration of 11 seconds is disclosed in the reader task, along with the full
build spread. All live workflows and the 298/79 current-main differential remain as expected.
Five silent successful ci.yml samples take 0.091565 to 0.219108 seconds.
