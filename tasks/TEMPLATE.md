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

## Design
<written once at plan time and amended in place (.claude/skills/kitimark-mode/SKILL.md,
Plan-time designs); `touches` and `must_not_touch` above are its file lists>
depth: <build: a sketch that type-checks, plus named fixtures | contract only>
revisit_when: <"re-check after #N merges" for a row that depends on an unmerged row, else none>
types: <types and signatures>
statements: <named statements>
reuse: <existing modules to reuse>
fixtures: <named fixtures>
cut_line: <what this task ships, and what it leaves to `deferrals`>
deferrals: <each finding deferred to or from this row, with the row or issue it moves from or to>
owner_decisions: <the owner decisions the plan PR settles>

## Done when
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
