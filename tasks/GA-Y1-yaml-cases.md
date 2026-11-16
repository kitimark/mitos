# GA-Y1 kernel and interpreter fixtures

phase: gate architecture
goal: The workflow line reader's small inputs have exact kernel-checked results and matching interpreter behavior.
statement: 58 exact-result fixture theorems in MitosGate.Yaml
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
statements: eight exact escape/folding theorems, eight matching interpreter guards, and 50 exact-result regressions.
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

- [x] All 58 exact-result kernel theorems and all eight interpreter guards compile.
- [x] The actual binary passes workflow tests and the live scanner differential.
- [x] The measured fixture build is 4.1 to 4.6 seconds across three builds without corpus contention.
- [ ] CodeRabbit is reviewed or explicitly refuses at the final head, with every finding answered.
- [ ] The required Opus verifier passes before owner merge.

The complete reader-plus-fixtures target adds 7.304 seconds by median, from 4.643 to 11.947 seconds.
The first PR records all three refreshed interleaved pairs and their spread. Five successful silent parses of
ci.yml take 0.077255 to 0.084352 seconds on the final binary. The no-comments pass reports zero
deletions and zero flags. Inherited-model advisory review independently confirms all eight decoded
YAML values and all 57 lex fixture inputs. These passes do not replace the required Opus verdict.

The review round adds three flow-node hash refusal theorems and a positive flow-plain hash theorem.
The normal comment branch remains before the new refusal. Current main 583a13b has 298 block lines
and 79 expression positions across its six accepted workflows; both dumps match PyYAML 6.0.3.
