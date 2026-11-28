# tasks/P2-027-watch-rules-switch.md

phase: 2 (Watch track, #502; milestone 6)
goal: The rules make `watch.sh` the way every agent waits on GitHub, in any provider's cloud container, and they carry the caller protocol that the no-spin and no-livelock guarantees depend on, the root's catch-all that coverage rests on, who acts on a topic, and the host rules.
statement: none (rules change)
touches: the Watchers text and the `#224` line of "Catching the user up" (it names `watch-github.sh`) in both `kitimark-mode` SKILL.md copies; autonomous-run.md, babysit.md, orchestrate.md and shipping.md in both `poteto-mode/playbooks` copies; .claude/README.md; docs/process.md (the gh-only row and the "Waiting on GitHub" row); .agents/scripts/agents-roster.tsv (stamps for `kitimark-mode` and `poteto-mode`); tasks/P2-027-watch-rules-switch.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/, .github/, and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: `python3 .agents/scripts/agents-skills.py stamp` then `check`; the greps of row 13 (no rule still names `watch-github.sh` or `watch-own.sh` except the fallback paragraph; each of the five caller rules, and each topic and host rule, in both `kitimark-mode` copies); the run-log check
budget: 20 iterations · 2h wall · 1M tokens (`tasks/502-watch.md`, budget: script and rules PRs)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-027 in `plan/phase-2.md` (Watch track), issue [#576](https://github.com/kitimark/mitos/issues/576). It is PR 13 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: P2-025 ([#574](https://github.com/kitimark/mitos/issues/574)), P2-026 ([#575](https://github.com/kitimark/mitos/issues/575)) and its A/B pass.
- Amendment 1 (`tasks/502-watch/AMENDMENT-1.md`, landed by PR 0b) changed this row: the text also carries a fifth caller rule (exit 2, a `watch: usage:` line), the root's catch-all, what may ride for the root, who acts, topic agents as sessions of their own or short-lived, the `--max` bound, fetch and verify at session start, one wake source and the cap on waiting containers.
- Role: PR owner, hard (skill text; `opus`, `xhigh`). It touches `.claude/` and `docs/process.md`, so the owner merges it.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file names the slice and does not restate it.

## Design
PR 13's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: contract only. Row 13 of `tasks/502-watch/PR-SEQUENCE.md` names the files, the five caller rules and the topic and host rules the text must carry, and the greps that check them; there is no draft text.
revisit_when: re-check after P2-026 (#575) merges with its A/B numbers and its idle-cost counter.
modules: the Watchers text and the waiting playbooks named in `touches`
types: the exit-code table and the topic flags in `tasks/502-watch/DESIGN.md` (Usage)
statements: none (rules change)
reuse: the exit-code table and caller protocol in `tasks/502-watch/DESIGN.md` (Usage), its who-acts decision (Shape) and its Cloud host profile
fixtures: none
cut_line: row 13 of `tasks/502-watch/PR-SEQUENCE.md`; the bash watcher's fallback paragraph stays until P2-029
deferrals: from `tasks/502-watch.md` (deferrals): owner words older than the feed come from pr-state's unanswered column, which this row's text says the root reads at session start
owner_decisions: defaults 2a, 5b and 14, and questions 10 and 12 (open on PR 0b), as rules text

## Done when
- [ ] row 13's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally
- [ ] run-log record written (ops/runs/)
