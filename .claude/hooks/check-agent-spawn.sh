#!/usr/bin/env bash

command -v jq >/dev/null || exit 0

jq -c '
  .tool_input as $in
  | ($in.subagent_type // "") as $type
  | [ "model", "effort" ] as $fields
  | if $type == "fork" then
      [ $fields[] | select(($in[.] // "") != "") ]
      | if . == [] then empty
        else "This fork sets \(join(" and ")), which a fork ignores. It runs on the settings of the session that forks it. Leave both out, or spawn a fresh agent from the role table in .claude/skills/kitimark-mode/SKILL.md."
        end
    else
      [ $fields[] | select(($in[.] // "") == "") ]
      | if . == [] then empty
        else "This Agent call sets no \(join(" or ")). Set both from the role table in .claude/skills/kitimark-mode/SKILL.md, or say why the session default is right."
        end
    end
  | { systemMessage: ., hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: . } }
'

# Exit 2 would block the spawn, so no jq failure may pass through.
exit 0
