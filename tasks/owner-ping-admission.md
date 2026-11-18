# tasks/owner-ping-admission.md

phase: 1
goal: The independent workflow differential compares owner-ping as an ordinary admitted document without changing its notification behavior.
statement: none (tooling task)
touches: .github/workflows/owner-ping.yml, gate/workflow-check.py, gate/workflow-diff-test.sh, gate/workflow-differential.py, gate/workflow_leaves.py, tasks/owner-ping-admission.md, ops/runs/2026-11-18/owner-ping-admission-builder-1.json
must_not_touch: statements.lock, models.lock, core/, gate/MitosGate/, gate/Main.lean, .github/workflows/ci.yml, .github/workflows/land.yml, plan/, models, eval/cheats/
checks: workflow reader and placement controls, permanent workflow differential and planted failures, seven live workflows and 700 qualification mutants, complete YAML parity, actionlint, ShellCheck, imports, runlog, current-head CI
budget: 10 iterations · 2h wall · 500K tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

This is unit N in the accepted split of #336 after the B+C repair in #488.
The existing L4YAML reader rejects anchors and aliases. Owner-ping's shared step therefore
requires an exact-path exception in the independent PyYAML differential. Expanding the step
lets the ordinary comparison cover every shipped workflow without widening the reader.

## Design

depth: build; existing interfaces, complete source migration and named native controls
revisit_when: owner-ping behavior or YAML admission changes
modules:
- `.github/workflows/owner-ping.yml` owns notifications. Expand the existing step in its two jobs, about 105 lines.
- `gate/workflow_leaves.py` owns the independent leaf comparison. Delete its owner-ping exception and allowlisted result, about 150 lines.
- `gate/workflow-check.py` owns fixed reader/oracle controls. Admit owner-ping in the live traversal, about 215 lines.
- `gate/workflow-differential.py` owns qualification mutations. Include owner-ping among its live inputs and mutation bases, about 115 lines.
- `gate/workflow-diff-test.sh` owns differential command controls. Require ordinary owner-ping comparison and refusal of the former anchored document, about 130 lines.
types: reuse the existing parse/leaves commands and ordered leaf records; comparison results are compared or differences
statements: no Lean statements change
reuse: existing L4YAML admission, PyYAML event-leaf oracle, CLI diagnostics and CI scheduling
fixtures: real and copied owner-ping; exact old refusal, changed refusal and panic stubs; reconstructed anchored workflow in default discovery; existing type, order, missing-tool and both-extension controls
cut_line: expand the notification step and migrate its oracle, qualification corpus and differential controls together
deferrals: the native workflow contract and permanent two-copy coherence check remain in unit T of #336; activation remains in unit F
owner_decisions: none added; reuse the accepted split design after verifying all five source blobs still match its base

The caller remains `gate/workflow-diff.sh`, which compares both notification copies through
the ordinary reader and independent oracle. A parsed-tree comparison must match the complete
old alias-resolved workflow, and the two expanded step blocks must be byte-identical.
Triggers, job conditions, permissions, timeouts, environment and shell text stay the same.
The generic reader continues to reject anchors and aliases.

The tradeoff is duplicated source. This unit establishes parity at its reviewed head; it does
not add or claim T's permanent native two-copy invariant. Extracting a checked-out script would
change the notification workflow's trust boundary, and parser expansion would change admission.
Rollback keeps the five source and test migrations together.

## Done when

- [ ] Native reader, placement, differential and qualification controls pass.
- [ ] Complete old/new YAML trees and expanded source blocks match.
- [ ] Workflow and shell lint pass; current-head CI passes.
- [ ] Fresh no-comments and independent review cover the final head.
- [ ] The run-log record describes this attempt.
