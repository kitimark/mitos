# Claude Code skills and agents

Project skills (`skills/`) and subagents (`agents/`) for this repository. Most are adapted from
pstack (MIT); see `THIRD_PARTY_NOTICES.md`.

| Name | Kind | How it runs | What it does |
|---|---|---|---|
| `kitimark-mode` | skill | always: `CLAUDE.md` imports it (added in PR #2) | the session delegates to agents with a model and effort per role; how much agents decide alone in this repo |
| `/automate-me` | skill | you type it | mines past sessions and drafts or updates a `<handle>-mode` skill |
| `/no-comments` | skill | you type it, or poteto-mode runs it before review | spawns `comment-sicko` on a scope, reviews its report, fixes accepted flags |
| `comment-sicko` | agent | spawned by `/no-comments` | deletes comments outside a short keep-list; flags code to reshape |
| `/how` | skill | you type it, or `/no-comments` or poteto-mode follows it | explains how a part of the code works, with parallel explorers |
| `/why` | skill | you type it, or `/no-comments` or poteto-mode follows it | cited history of why code is shaped as it is |
| `/unslop` | skill | you type it, or `/automate-me` or poteto-mode follows it | cuts AI-sounding patterns from prose |
| `/poteto-mode` | skill | you type it | poteto's working style, with principles, 22 task playbooks, subagent and model rules, reply style |
| `poteto-agent` | agent | spawned inside a poteto-mode playbook step | reads poteto-mode first, then does one delegated code or helper task |
| `principle-*` (24) | skills | poteto-mode and other skills read the one that applies; you can type one | one engineering principle each, such as `principle-prove-it-works` |
| `/architect` | skill | you type it, or a poteto-mode playbook follows it | sketches types and signatures with two or more parallel designs before code |
| `/arena` | skill | you type it, or `/architect`, `/interrogate` or a playbook follows it | N candidates on one task, a cross-judge, a base, grafts from the rest |
| `/swarm` | skill | you type it, or a playbook follows it | fans out N workers and returns one report |
| `/interrogate` | skill | you type it, or a playbook follows it | adversaries try to break a change; only findings a run proves survive |
| `/in-your-own-words` | skill | you type it, or `/interrogate` follows it | restates the user's goal |
| `/benchmark-checklist` | skill | you type it, or a playbook follows it | vets a perf number before you report or act on it |
| `/figure-it-out` | skill | you type it, or poteto-mode routes to it | designs a bespoke playbook for large or unattended work |
| `/ketchup` | skill | you type it, or the Autopilot playbooks follow it | catches the user up and lists the calls waiting on them |
| `/bro` | skill | you type it; `/ketchup` borrows its voice | restates the last message in plain words |
| `/tdd` | skill | you type it, or the Bug fix playbook follows it | failing regression test first, then the fix |
| `/show-me-your-work` | skill | you type it, or poteto-mode follows it on long or unattended work | a TSV decision trail plus a cross-model review of it |
| `/reflect` | skill | you type it | three reviewers mine the session and route learnings to skill edits |
| `/technical-writing` | skill | you type it, or poteto-mode follows it for docs, PRs and commits | layered writing standard for docs, PR bodies and commit messages |

All the ported skills keep pstack's `disable-model-invocation: true`, so they run only when typed.
Where one skill uses another, it tells the agent to read the other's `SKILL.md` and follow it,
which works regardless of that flag.

## Changes from pstack

- Cursor's `Task` tool → the Agent tool; `readonly: true` → `subagent_type: "Explore"`;
  `generalPurpose` → `general-purpose`; `AskQuestion` → `AskUserQuestion` (2–4 options per
  question).
- Model slugs and the `pstack-models.mdc` rule → fixed aliases. In the PR #3 skills, explorers and
  investigators run on `sonnet`, and the explainer, synthesizer and `comment-sicko` on `opus`. In
  poteto-mode and its closure, code delegates and swarm workers run on `sonnet`, and judgment,
  prose and the hardest changes run on `opus`. A verifier runs on the model its author did not
  use. The reasoning level goes through the Agent tool's `effort`, starting at `xhigh`. In this
  repository the `kitimark-mode` role table sets both for each role. Cursor's fast mode has no
  counterpart and is dropped.
- pstack pairs a Claude model with a Grok model for a second opinion (arena runners and
  cross-judge, architect runners, interrogate adversaries, reflect reviewers, the
  show-me-your-work reviewer, an Orchestrate verifier). Claude Code offers only Claude models, so
  the port pairs `opus` with `sonnet`. Agreement between them is weaker evidence than agreement
  across families.
- `.cursor/` paths and Cursor transcripts → `.claude/` paths and `~/.claude/projects/<slug>/`; in
  cloud sessions, past sessions are read with `list_sessions` / `list_events`.
- `create-skill` (Cursor built-in) → the `skill-creator` skill, or direct authoring.
- Cursor cloud agents (`environment: "cloud"`, `cloud_base_branch`) → background subagents with
  `isolation: "worktree"`, told which branch to check out. The Cursor agent store and Project
  tracker → a directory outside every worktree that the root names in each brief.
- Origin, Graphite and Cursor's built-in PR tool → `gh` or the GitHub MCP tools.
- `/loop` (Cursor built-in) → the `/loop` skill that ships with Claude Code.
- `comment-sicko` investigates suspicious claims itself with git instead of calling `/how` and
  `/why`; `/no-comments` step 2 runs the full skills on what remains in doubt. It runs in a
  worktree so its deletions can be inspected before they are taken.
- `/no-comments` keeps the one-line replacements PR #3 wrote for `architect`,
  `principle-fix-root-causes` and `principle-redesign-from-first-principles`, although those skills
  now exist here. `setup-pstack` is not ported at all.

### poteto-mode closure

Each node that poteto-mode, its playbooks, or the skills they route to name, and what the port
does with it.

| Node | Decision | Replacement or note |
|---|---|---|
| `poteto-mode/SKILL.md` | ported, trimmed | Subagents section rewritten for fixed models; `deslop` and the control skills replaced inline (below) |
| playbooks (22) | ported | Babysit, Shipping, Opening a PR, Autopilot-full, Orchestrate and Multi-phase plan trimmed of Origin, cloud agents and the built-in PR tool |
| `playbooks/worktree-cleanup.md` | dropped | its lever reads Cursor transcripts and Origin, and half of it is macOS simulator cleanup; Claude Code removes an unchanged subagent worktree on its own |
| `references/bugbot-triage.md` | ported | unchanged |
| `scripts/check-plan.mjs` | ported | unchanged; Node only, reads one file, writes nothing; the Multi-phase plan playbook runs it |
| `scripts/check-plan.test.ts`, `package.json`, `bun.lock` | dropped | Bun test harness for the script above |
| `scripts/watch-pr/` (TypeScript), `scripts/bootstrap.ts` | dropped | about 2,500 lines of TypeScript that run `bun install` at first use; Babysit and Shipping now read the same `gh` facts directly (`gh pr view`, `gh pr checks`, the `reviewThreads` GraphQL query), with GitHub's merge-queue verdicts left out |
| `scripts/worktree-audit.sh` | dropped | with its playbook |
| `principle-*` (24) | ported | unchanged, except `principle-type-system-discipline` loses its pointer to `typescript-best-practices` |
| `typescript-best-practices` | dropped | only that pointer named it; this repo is Lean |
| `architect` (+3 references) | ported | runners `opus` and `sonnet` |
| `arena` | ported | runners `opus` and `sonnet`; the judge runs on whichever the parent does not |
| `swarm` | ported | workers `general-purpose` on `sonnet` in a worktree; a verifying worker runs on the model its author did not use |
| `interrogate` | ported | adversaries `general-purpose` in a worktree |
| `in-your-own-words`, `benchmark-checklist`, `tdd`, `technical-writing`, `bro` | ported | unchanged |
| `figure-it-out` | ported | drops the fast-mode clause, like every file that picks a reasoning level |
| `ketchup` | ported | `/visualize` (Cursor) → Mermaid diagrams and charts |
| `show-me-your-work` (+ template, `scripts/log.sh`) | ported | transcript path; `log.sh` only appends one row to a TSV file |
| `reflect` (+4 references) | ported | transcript path, `general-purpose`, models, `skill-creator` |
| `how`, `why`, `no-comments`, `unslop` | already ported in PR #3 | unchanged |
| `poteto-agent` (agent) | ported | finds poteto-mode under `.claude/skills/` or `~/.claude/skills/`; `is_background` dropped, callers pass `run_in_background` |
| `create-skill` (Cursor built-in) | replaced | `skill-creator` |
| `deslop` (`cursor-team-kit`) | replaced | "the slop strip", one inline step in poteto-mode's Non-negotiables |
| `control-ui`, `control-cli` (`cursor-team-kit`) | replaced | an inline definition of a control skill, with Bash or `tmux` for a CLI or TUI and a browser MCP, Playwright or `/run` for a UI |
| Cursor's built-in babysit skill | dropped | only named to say "do not route there" |
| `setup-pstack`, `pstack-models.mdc` | dropped | fixed model defaults in each file |
| Cursor cloud agents, Origin, Graphite, agent store | dropped | see the change list above |
