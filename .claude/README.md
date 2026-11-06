# Claude Code skills and agents

Project skills (`skills/`) and subagents (`agents/`) for this repository. Most are adapted from
pstack (MIT); see `THIRD_PARTY_NOTICES.md`.

| Name | Kind | How it runs | What it does |
|---|---|---|---|
| `kitimark-mode` | skill | always: `CLAUDE.md` imports it (added in PR #2) | how much agents decide alone in this repo |
| `/automate-me` | skill | you type it | mines past sessions and drafts or updates a `<handle>-mode` skill |
| `/no-comments` | skill | you type it | spawns `comment-sicko` on a scope, reviews its report, fixes accepted flags |
| `comment-sicko` | agent | spawned by `/no-comments` | deletes comments outside a short keep-list; flags code to reshape |
| `/how` | skill | you type it, or `/no-comments` follows it | explains how a part of the code works, with parallel explorers |
| `/why` | skill | you type it, or `/no-comments` follows it | cited history of why code is shaped as it is |
| `/unslop` | skill | you type it, or `/automate-me` follows it | cuts AI-sounding patterns from prose |

All the ported skills keep pstack's `disable-model-invocation: true`, so they run only when typed.
Where one skill uses another, it tells the agent to read the other's `SKILL.md` and follow it,
which works regardless of that flag.

## Changes from pstack

- Cursor's `Task` tool → the Agent tool; `readonly: true` → `subagent_type: "Explore"`;
  `generalPurpose` → `general-purpose`; `AskQuestion` → `AskUserQuestion` (2–4 options per
  question).
- Model slugs and the `pstack-models.mdc` rule → fixed aliases: explorers on `Explore`'s own model,
  investigators `sonnet`, explainer, synthesizer and `comment-sicko` `opus`.
- `.cursor/` paths and Cursor transcripts → `.claude/` paths and `~/.claude/projects/`; in cloud
  sessions, past sessions are read with `list_sessions` / `list_events`.
- `create-skill` (Cursor built-in) → the `skill-creator` skill, or direct authoring.
- Not ported: `poteto-mode` (only its model-choice section was used; replaced inline),
  `architect` and the two `principle-*` skills (replaced by one-line instructions in
  `/no-comments`), `setup-pstack`.
- `comment-sicko` investigates suspicious claims itself with git instead of calling `/how` and
  `/why`; `/no-comments` step 2 runs the full skills on what remains in doubt. It runs in a
  worktree so its deletions can be inspected before they are taken.
