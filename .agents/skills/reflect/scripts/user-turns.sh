#!/usr/bin/env bash
# The user's own turns in a Claude Code transcript, one JSON object per line: {"t": <timestamp>,
# "c": <text>}. A transcript's user lines also hold tool results, task notifications (`<task...`),
# messages from other sessions (`Another Claude ...`) and local command output (`<local-command...`);
# none of those are the user's words, so they are left out, and so are lines marked isMeta and the
# model-written summaries a compaction leaves (isCompactSummary).
#
# Usage: user-turns.sh <transcript.jsonl> [since]
# `since` is a timestamp such as 2026-11-09T00:00:00Z; only turns at or after it are printed,
# compared to the second, so a turn at 09:00:00.500Z counts as 09:00:00.
# A line that is not JSON is skipped.
set -u
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: user-turns.sh <transcript.jsonl> [since]" >&2; exit 2; }
[ -r "$1" ] || { echo "user-turns.sh: cannot read $1" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "user-turns.sh: jq is not installed" >&2; exit 2; }
jq -R -c --arg since "${2:-}" '
  fromjson? | select(type == "object" and .type == "user" and (.isMeta | not))
  | select(.isCompactSummary | not)
  | select($since == "" or ((.timestamp // "") | .[0:19]) >= ($since | .[0:19]))
  | (.message.content
     | if type == "string" then .
       elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text] | join("\n")
       else "" end) as $c
  | select($c != "" and ($c | test("^\\s*(<task|Another Claude|<local-command)") | not))
  | {t: .timestamp, c: $c}' "$1"
