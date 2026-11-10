#!/usr/bin/env bash

command -v jq >/dev/null || exit 0
input=$(cat)

note=''
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
if [[ $sid =~ ^[A-Za-z0-9_-]{1,100}$ ]]; then
  f=${MITOS_HOOK_STATE:-${TMPDIR:-/tmp}/mitos-hook-state}/$sid.note
  [ -f "$f" ] && note=$(head -c 2000 "$f" | head -n 1)
fi

jq -c --arg note "$note" '
  .tool_input as $in
  | ($in.subagent_type // "") as $type
  | [ "model", "effort" ] as $fields
  | [if $type == "fork" then
      [ $fields[] | select(($in[.] // "") != "") ]
      | if . == [] then empty
        else "This fork sets \(join(" and ")), which a fork ignores. It runs on the settings of the session that forks it. Leave both out, or spawn a fresh agent from the role table in .claude/skills/kitimark-mode/SKILL.md."
        end
    else
      [ $fields[] | select(($in[.] // "") == "") ]
      | if . == [] then empty
        else "This Agent call sets no \(join(" or ")). Set both from the role table in .claude/skills/kitimark-mode/SKILL.md, or say why the session default is right."
        end
    end] as $fields_msg
  | ((($in.description // "") | tostring) + " " + (($in.prompt // "") | tostring | .[0:600])) as $brief
  | [ $fields_msg[],
      (if $in.run_in_background != true then
         "This Agent call does not set run_in_background: true. Every spawn runs in the background, so the root stays free to answer the user (kitimark-mode, Roles)."
       else empty end),
      (if $type != "fork" and ($brief | test("\\b(PR owner|verifier)\\b"; "i")) and $in.isolation != "worktree" then
         "This PR owner or verifier spawn sets no isolation: \"worktree\". Give it one and name the commit to start from (kitimark-mode, Roles, Briefs)."
       else empty end),
      (if $note != "" then "\($note) Put this in the brief too." else empty end) ]
  | if . == [] then empty
    else join(" ") | { systemMessage: ., hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: . } }
    end
' <<<"$input" 2>/dev/null

# Exit 2 would block the spawn, so no jq failure may pass through.
exit 0
