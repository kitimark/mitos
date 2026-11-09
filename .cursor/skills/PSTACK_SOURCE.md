# Vendored pstack

Copied from [cursor/plugins](https://github.com/cursor/plugins), directory `pstack/`.

- Commit: `236e5481d05cbadc315b374a5de54971858c27bb`
- `pstack` tree: `4719e1c4b4c43bac85d4206a8b41dd2899769c1c`
- Version: `0.15.36` (`pstack/plugin.json`)

Cursor loads `pstack/skills/` and `pstack/agents/` (`pstack/.cursor-plugin/plugin.json`). Those two trees are copied here: each skill directory under `.cursor/skills/<name>/`, and the agent files under `.cursor/agents/`. Upstream ships no rules. `kitimark-mode` is this repository's skill. Upstream has no skill by that name, and re-sync does not replace it. If upstream later adds one, the script keeps this repository's copy and prints a notice.

Not copied. Cursor does not load these as project skills, rules, or agents:

- `pstack/docs/` and `pstack/README.md` (the guide). `poteto-help` links to them with paths relative to the plugin root. Those links do not resolve in this layout. The skill text is unchanged.
- `pstack/automations/` (the Benny automation package, separate from `pstack/skills/`).
- `pstack/assets/`, `pstack/plugin.json`, `pstack/.cursor-plugin/`, and `pstack/.gitignore` (marketplace metadata).

License: [`PSTACK_LICENSE`](PSTACK_LICENSE) (MIT, Copyright (c) 2026 Lauren Tan). The copyright notice and permission notice stay with this copy.

## Re-sync

From the repository root:

```bash
.cursor/skills/resync-pstack.sh
.cursor/skills/resync-pstack.sh <commit>
```

The script fetches that commit (default: `main`), copies `pstack/skills/` and `pstack/agents/`, refreshes `PSTACK_LICENSE`, and rewrites the three bullets above. It does not delete `.cursor/skills/kitimark-mode/`.
