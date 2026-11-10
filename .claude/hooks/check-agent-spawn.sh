#!/usr/bin/env bash

command -v jq >/dev/null || exit 0
input=$(cat)

note=''
hook_dir=${BASH_SOURCE[0]%/*}; [[ $hook_dir == "${BASH_SOURCE[0]}" ]] && hook_dir=.
# shellcheck source-path=SCRIPTDIR source=hook-state.sh
if . "$hook_dir/hook-state.sh" 2>/dev/null; then
  sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
  if session_id_ok "$sid" && state=$(hook_state_dir) && state=$(hook_state_private "$state"); then
    note=$(state_read "$state" "$sid.note")
  fi
fi

jq -c --arg note "$note" '
  def brief_chars: 600;
  def names_pr_owner_or_verifier($in):
    ((($in.description // "") | tostring) + " " + (($in.prompt // "") | tostring | .[0:brief_chars]))
    | test("\\b(PR owner|verifier)\\b"; "i");

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
  | [ $fields_msg[],
      (if $in.run_in_background != true then
         "This Agent call does not set run_in_background: true. Every spawn runs in the background, so the root stays free to answer the user (kitimark-mode, Roles)."
       else empty end),
      (if $type != "fork" and names_pr_owner_or_verifier($in) and $in.isolation != "worktree" then
         "This PR owner or verifier spawn sets no isolation: \"worktree\". Give it one and name the commit to start from (kitimark-mode, Roles, Briefs)."
       else empty end),
      (if $note != "" then "\($note) Put this in the brief too." else empty end) ]
  | if . == [] then empty
    else join(" ") | { systemMessage: ., hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: . } }
    end
' <<<"$input" 2>/dev/null

# Exit 2 would block the spawn, so no jq failure may pass through.
exit 0
