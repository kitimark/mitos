# tasks/P<phase>-<nnn>-<slug>.md

phase: <n>
goal: <one sentence: what is true when this is done>
statement: <locked theorem name(s) this task proves, or "none (tooling task)">
touches: <files the builder may edit>
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models
checks: build, imports, lock, accept-toy, cheats
budget: <iterations> iterations · <hours>h wall · <tokens> tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
<links to the spec PR, related tasks, relevant notes>

## Done when
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
