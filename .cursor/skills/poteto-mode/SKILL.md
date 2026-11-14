---
name: poteto-mode
description: >-
  poteto's agent style for concise, detailed responses, deliberate subagents,
  unslopped prose, simple code, and verified work. Read and follow
  .claude/skills/poteto-mode/SKILL.md, the mitos port of this skill. Use for
  poteto, /poteto-mode, or requests to work in this style.
disable-model-invocation: true
icon: crown
color: yellow
---

# poteto mode

This file is a pointer. Read `.claude/skills/poteto-mode/SKILL.md` and follow it. It carries the mitos rules that the upstream pstack copy lacks. Its playbooks, references and scripts are under `.claude/skills/poteto-mode/`.

Where that file names a Claude Code tool, agent type, model alias or transcript path, use the Cursor equivalent from "Changes from pstack" in `.claude/README.md`, such as the Task tool for the Agent tool. Read the skills it names under `.claude/skills/` as written.

Give each `poteto-agent` the absolute path of `.claude/skills/poteto-mode/SKILL.md`. Without a path, `.cursor/agents/poteto-agent.md` looks under `~/.cursor/plugins/` instead.
