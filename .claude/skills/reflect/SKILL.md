---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## 1. Locate the active transcript

Before fanning out, find this conversation's transcript in `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/`, where `<slug>` is the workspace path with every character other than a letter or digit changed to `-`. Do not glob across `~/.claude/projects/*/`. That crosses workspace boundaries and reads private chats from unrelated projects.

```bash
d="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slug>"
ls -t "$d"/*.jsonl "$d"/*/subagents/*.jsonl 2>/dev/null | head -10
```

That covers the session (`<session>.jsonl`) and subagent (`<session>/subagents/<child>.jsonl`) layouts. For each candidate, read the first line whose `type` is `user`. Take the file whose message contains the conversation's opening user prompt and whose `cwd` field is this workspace's path, because two workspaces can share a slug. If none matches, or more than one does, pass a tight digest of the session instead.

## 2. Spawn three reviewers in parallel

One message, three Agent calls, `subagent_type: "general-purpose"`, never `Explore`. Reviewers need MCP access to look up the tickets, chat threads, and observability traces the transcript references, and `Explore` does not reach every MCP tool.

Set each reviewer's `model` from the table. If the Agent tool rejects a model, omit `model` so the reviewer runs on the parent model, and say so. Pick each subagent's reasoning level for the job, per the Subagents section of the **poteto-mode** skill.

| Lens | `model` | Prompt template |
|---|---|---|
| Judgment | `opus` | `references/judgment-reviewer.md` |
| Tooling | `sonnet` | `references/tooling-reviewer.md` |
| Divergent | `opus` | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the Agent result.

## 3. Synthesize

One Agent call, `subagent_type: "general-purpose"`, `model: "opus"`. It spot-verifies citations through MCP, which `Explore` does not reach. Pass `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. It returns an Accepted / Rejected / Backlog list.

## 4. Structural enforcement check

Move any Accepted item that a lint rule, script, metadata flag, or runtime check would enforce more reliably to Backlog. See the **encode-lessons-in-structure** principle skill.

## 5. Apply

Present the synthesizer's full Accepted / Rejected / Backlog output and wait for explicit approval before applying any Accepted edit. The user picks the subset and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

File each Backlog item to your team's devex or backlog tracker without waiting. Under the **kitimark-mode** skill, each Backlog item the user approves becomes an issue in this repository labelled `process`, naming its target path, the cause it fixes and its owner (the PR owner who builds it, or the user for a path only they change). The parent files them right after approval and links them in the reply. Only the Accepted list and, under kitimark-mode, the Backlog wait for approval.

Never edit a skill under `~/.claude/plugins/`. Before approval, show its destination, `.claude/skills/<skill>/` or `~/.claude/skills/<skill>/`. After approval, copy the skill folder there and edit the copy. Never open a PR or push, unless the **kitimark-mode** skill applies. There the skills are this repository's files, so the parent hands the approved rows to a PR owner, which makes the edits below on a branch and opens a PR for the user to merge.

Follow each approved row's Routing exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): the parent does it directly. Under the **kitimark-mode** skill the PR owner above does it.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the `skill-creator` skill and run its draft / test / iterate loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to `skill-creator` and run its description-optimization loop.
- `new skill via skill-creator: <kebab-name>`: hand creation to `skill-creator`. Do not invent the shape ad hoc.
- Without `skill-creator` installed, make the three edits above directly, following `poteto-mode/playbooks/authoring-a-skill.md` and the structure of the skills already in `.claude/skills/`.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done.

## 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker, or under kitimark-mode as `process` issues: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
