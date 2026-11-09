#!/usr/bin/env bash
# Tests for user-turns.sh. Run: .claude/skills/reflect/scripts/user-turns.test.sh
set -u
script="$(cd "$(dirname "$0")" && pwd)/user-turns.sh"
failed=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

t=$work/t.jsonl
{
  jq -cn '{type:"user", timestamp:"2026-11-09T00:10:00Z", message:{role:"user", content:"please fix the footer"}}'
  jq -cn '{type:"assistant", timestamp:"2026-11-09T00:11:00Z", message:{role:"assistant", content:"ok"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:12:00Z", message:{content:[{type:"tool_result", tool_use_id:"x", content:"output"}]}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:15:18Z", message:{content:"<task-notification>\n<task-id>b1</task-id>\n<summary>Monitor event</summary>\n</task-notification>"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:16:00Z", message:{content:"Another Claude session sent a message:\n<agent-message from=\"x\">done</agent-message>"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:17:00Z", message:{content:"<local-command-stdout>Compacted </local-command-stdout>"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:18:00Z", isMeta:true, message:{content:"<local-command-caveat>The command below</local-command-caveat>"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:19:00Z", isMeta:true, message:{content:"a meta line"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T00:20:00Z", isMeta:null, isCompactSummary:true, isVisibleInTranscriptOnly:true, message:{content:"This session is being continued from a previous conversation that ran out of context."}}'
  echo 'not json at all'
  jq -cn '{type:"user", timestamp:"2026-11-09T09:00:00Z", message:{content:[{type:"text", text:"approve all"}, {type:"image", source:{}}]}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T09:30:00Z", message:{content:"  <task-notification>indented</task-notification>"}}'
  jq -cn '{type:"user", timestamp:"2026-11-09T10:00:00Z", message:{content:"why did <task> fail?"}}'
} >"$t"

is() { # name, got, want
  if [ "$2" = "$3" ]; then echo "ok    $1"; else
    echo "FAIL  $1"; printf '      got:  %q\n      want: %q\n' "$2" "$3"; failed=1
  fi
}
want_all='{"t":"2026-11-09T00:10:00Z","c":"please fix the footer"}
{"t":"2026-11-09T09:00:00Z","c":"approve all"}
{"t":"2026-11-09T10:00:00Z","c":"why did <task> fail?"}'
is "the user's own turns only" "$("$script" "$t")" "$want_all"
is "since leaves out earlier turns" "$("$script" "$t" 2026-11-09T09:00:00Z)" '{"t":"2026-11-09T09:00:00Z","c":"approve all"}
{"t":"2026-11-09T10:00:00Z","c":"why did <task> fail?"}'
is "since after every turn" "$("$script" "$t" 2026-11-10T00:00:00Z)" ""
jq -cn '{type:"user", timestamp:"2026-11-09T11:00:00.500Z", message:{content:"right at the cutoff"}}' >"$work/frac.jsonl"
is "a turn with a fraction of a second at the cutoff second" "$("$script" "$work/frac.jsonl" 2026-11-09T11:00:00Z)" \
  '{"t":"2026-11-09T11:00:00.500Z","c":"right at the cutoff"}'
jq -cn '{type:"user", timestamp:"2026-11-09T12:00:00Z", isCompactSummary:true, message:{content:[{type:"text", text:"This session is being continued from a previous conversation."}]}}' >"$work/compact.jsonl"
is "a compaction summary is not a user turn" "$("$script" "$work/compact.jsonl")" ""
"$script" >/dev/null 2>&1; is "no argument: exit 2" "$?" 2
"$script" "$work/none.jsonl" >/dev/null 2>&1; is "a missing file: exit 2" "$?" 2
is "an empty file: no output" "$(: >"$work/e.jsonl"; "$script" "$work/e.jsonl")" ""
exit "$failed"
