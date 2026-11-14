# Cursor project setup

Claude Code loads `CLAUDE.md`, which imports `.claude/skills/kitimark-mode/SKILL.md`.
Cursor loads project rules from `.cursor/rules/` and skills from `.cursor/skills/`.
For compatibility it also discovers `.claude/skills/`.

`.claude/skills/kitimark-mode/SKILL.md` and `docs/process.md` are canonical. The files in the table
below point at them. The edited pstack skills carry the same mitos rules as their `.claude/`
copies (see pstack below).

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

Some copies are edited, not upstream verbatim:

- `architect`, `no-comments`, `poteto-mode`, `reflect`, `show-me-your-work`,
  `swarm` and `agents/poteto-agent.md` are upstream's files plus this
  repository's rules, written in Cursor's terms (`Task`, `generalPurpose`,
  Cursor model slugs, `.cursor/` paths). Everything else in them stays
  upstream's wording, so a re-sync diff stays small.
- `principle-split-by-topic` and `kitimark-mode` are this repository's own
  skills. Upstream has neither.

The `.claude/` copies carry the same mitos rules in Claude Code's terms. A
PR that changes a mitos rule in one copy changes the other copy too. Where a
rule names a step only Claude Code runs, such as the `Monitor` that watches
GitHub, a hook or `user-turns.sh`, the Cursor copy says so and says what a
Cursor agent does instead.

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

The script copies `pstack/skills/` and `pstack/agents/` again and leaves the
edited and repository-only skills and agents above in place (`kept_skills` and
`kept_agents` at its top). For each kept path that upstream changed since the
pinned commit, it prints the changed files and a compare link. Merge what
applies by hand, in the `.cursor/` copy and, where it applies, the `.claude/`
copy, before you commit the re-sync.

## Same skill name twice

Cursor discovers both `.cursor/skills/kitimark-mode/` and `.claude/skills/kitimark-mode/`.
Both use the skill name `kitimark-mode`. Follow `.claude/skills/kitimark-mode/SKILL.md`
when both appear. The wrapper under `.cursor/skills/` only points at that file.

Every other skill in both trees has the same name twice too. In Cursor, follow the
`.cursor/skills/` copy: it names Cursor's tools, and it carries the same mitos rules.

## No `AGENTS.md`

The repository has no `AGENTS.md`. [#100](https://github.com/kitimark/mitos/issues/100)
keeps it out: outside reviewers read instructions from the head, and a root instruction
file would be a second copy of these rules and a place a pull request could change them.
