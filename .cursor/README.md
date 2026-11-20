# Cursor project setup

Claude Code loads `CLAUDE.md`, which imports `.claude/skills/kitimark-mode/SKILL.md`.
Cursor loads project rules from `.cursor/rules/`. The skills themselves are under
`.agents/skills/`. For compatibility Cursor also discovers `.claude/skills/`.

`.claude/skills/kitimark-mode/SKILL.md` and `docs/process.md` are canonical. The files in the table
below point at them. The edited pstack skills carry the same mitos rules as their `.claude/`
copies (see pstack below).

| File | When Cursor loads it | What it tells the agent |
|---|---|---|
| `rules/kitimark-mode.mdc` | every chat (`alwaysApply: true`) | roles, the paths the owner keeps, `spec-approved`, catch-up, no `AGENTS.md` |
| `rules/process-pointers.mdc` | every chat (`alwaysApply: true`) | two-PR flow, lock files, `follow-up` and `process` labels, pstack yields to the mitos process |
| `rules/lean-trust.mdc` | a `.lean` file is in context (`globs`, `alwaysApply: false`) | proved Lean, no `sorry` or `admit` to get green, no weakened cheat or theorem |

Rule files are `.mdc` with YAML frontmatter. `alwaysApply: true` includes the rule in every
chat. A file-scoped rule sets `alwaysApply: false` and a `globs` string. A plain `.md` file
in `.cursor/rules/` is ignored. Skill frontmatter needs `name` and `description`, and `name`
matches the parent folder. The format is the current Cursor docs:
[Rules](https://cursor.com/docs/rules), [Agent Skills](https://cursor.com/docs/skills).

## pstack

pstack skills and agents are vendored under `.agents/`, from
[cursor/plugins `pstack/`](https://github.com/cursor/plugins/tree/main/pstack).
A session on this repository loads them without `/add-plugin pstack`. Each skill is
`.agents/skills/<name>/`, helper files included. The two agents are `.agents/agents/`
(`poteto-agent`, `comment-sicko`). `.cursor/` holds `rules/` and this README. Upstream
ships no rules and has no `kitimark-mode` skill.

Re-sync leaves every rewrite-class skill in place, and also `principle-type-system-discipline`.
That skill's `.agents` body is the Claude wording, which dropped the TypeScript pointer, and an
upstream refresh must not put that pointer back. `agents/poteto-agent.md` stays too.
`kitimark-mode` is this repository's own skill. Its canonical text is
`.claude/skills/kitimark-mode/SKILL.md`.

The `.claude/` copies carry the same mitos rules in Claude Code's terms. A
PR that changes a mitos rule in one copy changes the other copy too. Where a
rule names a step only Claude Code runs, such as the `Monitor` that watches
GitHub, a hook or `user-turns.sh`, the neutral copy says so and says what a
Cursor agent does instead.

On mitos, kitimark mode and `docs/process.md` win over generic pstack guidance.
That includes a playbook that says to merge, assign someone, or skip a check.
`rules/process-pointers.mdc` states the same precedence. The Claude Code port
under `.claude/` is a separate, edited copy (see `.claude/README.md`).

Provenance, the license, and what was left out are in
`.agents/scripts/PSTACK_SOURCE.md`. Re-sync from the repository root:

```bash
.agents/scripts/resync-pstack.sh
.agents/scripts/resync-pstack.sh <commit>
```

The script copies `pstack/skills/` into `.agents/skills/` and `pstack/agents/` into
`.agents/agents/`. Kept skill names come from `python3 .agents/scripts/agents-skills.py kept`.
`kept_agents` stays at the top of the script. After the vendor copy, the script runs
`python3 .agents/scripts/agents-skills.py sync`. Sync copies a mirror whose source is the
Claude tree from `.claude/skills/<name>/` onto `.agents`, and it does not write a rewrite
body. For each kept path that upstream changed since the pinned commit, the script prints
the changed files and a compare link. Merge what applies by hand, in the `.agents/` copy
and, where it applies, the `.claude/` copy, before you commit the re-sync.

## Same skill name

Follow `.claude/skills/kitimark-mode/SKILL.md`. `.agents/skills/kitimark-mode/` is the
harness-neutral text for a host that does not load the Claude file. It is not always on.
Invoke it as `$kitimark-mode` or `/kitimark-mode`.

Codex and Antigravity follow `.agents/skills/<name>/`.

## No `AGENTS.md`

The repository has no `AGENTS.md`. [#100](https://github.com/kitimark/mitos/issues/100)
keeps it out: outside reviewers read instructions from the head, and a root instruction
file would be a second copy of these rules and a place a pull request could change them.
`.agents/` holds `skills/`, `agents/`, and `scripts/`: no `AGENTS.md`, no `.agents/rules`,
and no `.agents/README.md`.
