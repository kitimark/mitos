#!/usr/bin/env bash

command -v jq >/dev/null || exit 0
input=$(cat)

probe_models=(opus sonnet haiku)
note=''
probes=''
hook_dir=${BASH_SOURCE[0]%/*}; [[ $hook_dir == "${BASH_SOURCE[0]}" ]] && hook_dir=.
# shellcheck source-path=SCRIPTDIR source=hook-state.sh
if . "$hook_dir/hook-state.sh" 2>/dev/null; then
  sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
  event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)
  case $event in
    PostToolUse | PostToolUseFailure)
      family=$(jq -r --arg m "${probe_models[*]}" '
        select(.tool_input.run_in_background != true and ((.tool_input.prompt // "") | tostring | gsub("^\\s+|\\s+$"; "") | ascii_downcase) == "probe")
        | (.tool_input.model // "" | tostring | ascii_downcase) as $model
        | ($m | split(" ") | map(select(. as $f | $model | contains($f))) | first // empty)' \
        <<<"$input" 2>/dev/null)
      if [[ -n $family ]]; then
        result=$(jq -r '
          if .hook_event_name == "PostToolUseFailure" or .tool_response.is_error == true
             or ((.tool_response | tojson) | test("rate.?limit|usage limit|limit reached|quota|overloaded"; "i"))
          then "fail" else "pass" end' <<<"$input" 2>/dev/null)
        hook_state ensure
        printf '%s %s\n' "$(date +%s)" "${result:-fail}" | hook_state publish "$sid" "probe-$family"
      fi
      exit 0
      ;;
  esac
  note=$(hook_state read "$sid" note)
  for m in "${probe_models[@]}"; do
    rec=$(hook_state read "$sid" "probe-$m")
    [[ -n $rec ]] && probes+="$m $rec"$'\n'
  done
fi

jq -c --arg note "$note" --arg probes "$probes" --argjson now "$(date +%s)" '
  def brief_chars: 600;
  def probe_window: 3600;
  def families: ["opus", "sonnet", "haiku"];
  def is_probe($in):
    (($in.prompt // "") | tostring | gsub("^\\s+|\\s+$"; "") | ascii_downcase) == "probe";
  def family_of($s): ($s | ascii_downcase) as $l | families | map(select(. as $f | $l | contains($f))) | first // "";
  def limit_claim($in):
    ((($in.description // "") | tostring) + " " + (($in.prompt // "") | tostring | .[0:2000]))
    | test("(at|hit|reached|over|near)( (its|the|a|their))?( (usage|rate|plan|weekly|daily))? limit|rate.?limit|usage limit|limit reached|out of (usage|quota)|quota|downgrad|fall(ing)? ?back"; "i");
  def limited_models($in):
    ((($in.description // "") | tostring) + " " + (($in.prompt // "") | tostring | .[0:2000]) | ascii_downcase) as $text
    | family_of($in.model // "") as $spawned
    | ([families[] | select(. as $f | $text | contains($f)) | select(. != $spawned)]) as $named
    | if $named == [] then (if $spawned == "opus" then [] else ["opus"] end) else $named end;
  def fresh_probe($family):
    [ $probes | split("\n")[] | split(" ") | select(length == 3 and .[0] == $family and (.[1] | test("^[0-9]+$")) and (($now - (.[1] | tonumber)) < probe_window)) ] | length > 0;
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
      (if $in.run_in_background != true and (is_probe($in) | not) then
         "This Agent call does not set run_in_background: true. Every spawn runs in the background, so the root stays free to answer the user (kitimark-mode, Roles)."
       else empty end),
      (if $type != "fork" and names_pr_owner_or_verifier($in) and $in.isolation != "worktree" then
         "This PR owner or verifier spawn sets no isolation: \"worktree\". Give it one and name the commit to start from (kitimark-mode, Roles, Briefs)."
       else empty end),
      (if limit_claim($in) then
         [ limited_models($in)[] | select(fresh_probe(.) | not) ]
         | if . == [] then empty
           else "This brief says a model is at its limit or downgrades a role, but no probe of \(join(" or ")) is on record from the last hour. Run a foreground Agent call with the prompt probe and that model first, and use the fallback only if the probe fails."
           end
       else empty end),
      (if $note != "" then "\($note) Put this in the brief too." else empty end) ]
  | if . == [] then empty
    else join(" ") | { systemMessage: ., hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: . } }
    end
' <<<"$input" 2>/dev/null

# Exit 2 would block the spawn, so no jq failure may pass through.
exit 0
