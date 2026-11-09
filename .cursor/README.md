# Cursor project setup

Claude Code loads `CLAUDE.md`, which imports `.claude/skills/kitimark-mode/SKILL.md`.
Cursor loads project rules from `.cursor/rules/` and skills from `.cursor/skills/`.
For compatibility it also discovers `.claude/skills/`.

`.claude/` and `docs/process.md` are canonical. The files in this directory point at them.

| File | When Cursor loads it | What it tells the agent |
|---|---|---|
| `rules/kitimark-mode.mdc` | every chat (`alwaysApply: true`) | roles, the paths the owner keeps, `spec-approved`, catch-up, no `AGENTS.md` |
| `rules/process-pointers.mdc` | every chat (`alwaysApply: true`) | two-PR flow, lock files, `follow-up` and `process` labels, pstack yields to the mitos process |
| `rules/lean-trust.mdc` | a `.lean` file is in context (`globs`, `alwaysApply: false`) | proved Lean, no `sorry` or `admit` to get green, no weakened cheat or theorem |
| `skills/kitimark-mode/SKILL.md` | the agent judges the skill relevant, or someone types `/kitimark-mode` | read and follow the canonical skill and `docs/process.md` |

Rule files are `.mdc` with YAML frontmatter. `alwaysApply: true` includes the rule in every
chat. A file-scoped rule sets `alwaysApply: false` and a `globs` string. A plain `.md` file
in `.cursor/rules/` is ignored. Skill frontmatter needs `name` and `description`, and `name`
matches the parent folder. The format is the current Cursor docs:
[Rules](https://cursor.com/docs/rules), [Agent Skills](https://cursor.com/docs/skills).

## pstack

pstack skills and agents are vendored in this directory, from
[cursor/plugins `pstack/`](https://github.com/cursor/plugins/tree/main/pstack).
A Cursor session or a cloud agent on this repository loads them without
`/add-plugin pstack`. Each upstream skill is `.cursor/skills/<name>/`, helper
files included. The two upstream agents are `.cursor/agents/` (`poteto-agent`,
`comment-sicko`). The plugin manifest loads those two trees and no rules.
Upstream has no `kitimark-mode` skill.

On mitos, kitimark mode and `docs/process.md` win over generic pstack guidance.
That includes a playbook that says to merge, assign someone, or skip a check.
`rules/process-pointers.mdc` states the same precedence. The Claude Code port
under `.claude/` is a separate, edited copy (see `.claude/README.md`).

Provenance, the license, and what was left out are in
`skills/PSTACK_SOURCE.md`. Re-sync from the repository root:

```bash
.cursor/skills/resync-pstack.sh
.cursor/skills/resync-pstack.sh <commit>
```

The script copies `pstack/skills/` and `pstack/agents/` again and leaves
`skills/kitimark-mode/` in place.

## Same skill name twice

Cursor discovers both `.cursor/skills/kitimark-mode/` and `.claude/skills/kitimark-mode/`.
Both use the skill name `kitimark-mode`. Follow `.claude/skills/kitimark-mode/SKILL.md`
when both appear. The wrapper under `.cursor/skills/` only points at that file.

## No `AGENTS.md`

The repository has no `AGENTS.md`. [#100](https://github.com/kitimark/mitos/issues/100)
keeps it out: outside reviewers read instructions from the head, and a root instruction
file would be a second copy of these rules and a place a pull request could change them.
