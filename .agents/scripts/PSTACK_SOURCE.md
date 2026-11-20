# Vendored pstack

Copied from [cursor/plugins](https://github.com/cursor/plugins), directory `pstack/`.

- Commit: `236e5481d05cbadc315b374a5de54971858c27bb`
- `pstack` tree: `4719e1c4b4c43bac85d4206a8b41dd2899769c1c`
- Version: `0.15.36` (`pstack/plugin.json`)

The upstream plugin loads `pstack/skills/` and `pstack/agents/` (`pstack/.cursor-plugin/plugin.json`). This repository copies those trees to `.agents/skills/<name>/` and `.agents/agents/`. Upstream ships no rules. `.cursor/` holds project rules only.

Re-sync keeps every rewrite-class skill, `principle-type-system-discipline`, and `agents/poteto-agent.md`. `principle-type-system-discipline` stays because its `.agents` body is the Claude wording, which dropped the TypeScript pointer. Skill names come from `python3 .agents/scripts/agents-skills.py kept`, and `kept_agents` stays in the script. For each one that upstream changed, added or removed since the pinned commit, it prints a notice, the changed files and a compare link, so a person merges upstream's change by hand. The `.claude/` ports carry the same rules (`.cursor/README.md`).

Not copied. Cursor does not load these as project skills, rules, or agents:

- `pstack/docs/` and `pstack/README.md` (the guide). `poteto-help` links to them with paths relative to the plugin root. Those links do not resolve in this layout. The skill text is unchanged.
- `pstack/automations/` (the Benny automation package, separate from `pstack/skills/`).
- `pstack/assets/`, `pstack/plugin.json`, `pstack/.cursor-plugin/`, and `pstack/.gitignore` (marketplace metadata).

License: [`PSTACK_LICENSE`](PSTACK_LICENSE) (MIT, Copyright (c) 2026 Lauren Tan). The copyright notice and permission notice stay with this copy.

## Re-sync

From the repository root:

```bash
.agents/scripts/resync-pstack.sh
.agents/scripts/resync-pstack.sh <commit>
```

The script fetches that commit (default: `main`), copies `pstack/skills/` into `.agents/skills/` and `pstack/agents/` into `.agents/agents/`, refreshes `.agents/scripts/PSTACK_LICENSE`, and rewrites the three bullets above. It leaves the kept skills and `agents/poteto-agent.md` in place, then runs `python3 .agents/scripts/agents-skills.py sync`.

## Neutral tree

`.agents/scripts/agents-roster.tsv` classifies every skill under `.agents/skills`. `python3 .agents/scripts/agents-skills.py check` fails when `.agents/skills` and the roster disagree. `python3 .agents/scripts/agents-skills.py sync` copies a mirror whose source is the Claude tree from `.claude/skills/<name>/` onto `.agents` and refreshes the explicit `agents/openai.yaml` files. It does not write a rewrite body. A mirror whose source is `agents` stays as the bytes already under `.agents` until a later re-sync refreshes it from upstream. Re-sync is not done until that sync has run. The script runs it after the vendor copy and exits non-zero when the tree does not match.
