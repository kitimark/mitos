---
name: reflect
description: >-
  Spawn three parallel review subagents over the active transcript, surface
  learnings, and route each to a concrete edit on an existing skill. Read and
  follow .claude/skills/reflect/SKILL.md, the mitos port of this skill. Use
  when the user says reflect.
disable-model-invocation: true
---

# reflect

This file is a pointer. Read `.claude/skills/reflect/SKILL.md` and follow it. It carries the mitos rules that the upstream pstack copy lacks. Its relative paths, such as `references/synthesizer.md`, are under `.claude/skills/reflect/`.

Where that file names a Claude Code tool, agent type, model alias or transcript path, use the Cursor equivalent from "Changes from pstack" in `.claude/README.md`, such as the Task tool for the Agent tool. Read the skills it names under `.claude/skills/` as written.

`scripts/user-turns.sh` reads only Claude Code transcripts. On a Cursor transcript, read the user's turns yourself.
