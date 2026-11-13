#!/usr/bin/env bash
set -u
script="$(cd "$(dirname "$0")" && pwd)/usage-sum.sh"
failed=0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

msg() {
  printf '{"type":"assistant","message":{"id":"%s","model":"%s","content":[{"type":"%s"}],"usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' \
    "$1" "${6:-m}" "${7:-text}" "$2" "$3" "$4" "$5"
}

mkdir -p "$work/wf_demo-1a2" "$work/plain"
{
  msg msg_A 2 100 1000 50 m thinking
  msg msg_A 2 100 1000 50 m text
  msg msg_A 2 100 1000 50 m tool_use
  echo '{"type":"user","message":{"role":"user","content":"hi"}}'
  echo 'not json at all'
  msg msg_B 3 10 2000 5
  msg msg_syn 0 0 0 0 '<synthetic>'
  printf '{"type":"assistant","message":{"model":"m","content":[],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
  printf '{"type":"assistant","message":{"model":"m","content":[],"usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":1,"cache_creation_input_tokens":1}}}\n'
} >"$work/wf_demo-1a2/agent-one.jsonl"
{
  msg msg_A 4 7 11 13
  msg msg_C 4 7 11 13
} >"$work/wf_demo-1a2/agent-two.jsonl"
echo '{"type":"system","subtype":"x"}' >"$work/wf_demo-1a2/journal.jsonl"
msg msg_D 6 20 300 40 >"$work/plain/solo.jsonl"
printf '%s\n' '{"type":"assistant","message":{"id":"msg_F","model":"m","content":[{"type":"text"}],"usage":{"input_tokens":1,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":4,"iterations":[{"type":"message","input_tokens":1,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":0},{"type":"fallback_message","input_tokens":1,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":4}]}}}' >"$work/fallback.jsonl"

row() { printf '%s\n' "$1" | awk -v l="$2" '$1 == l {print $2, $3, $4, $5, $6}'; }

check() {
  local what=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then echo "ok    $what"; else echo "FAIL  $what: got '$got', want '$want'"; failed=1; fi
}

out=$("$script" "$work/wf_demo-1a2/agent-one.jsonl")
check "a message split over 3 blocks counts once; id-less lines count each; synthetic and non-JSON are skipped" \
  "$(row "$out" total)" "4 7 112 3002 57"

out=$("$script" "$work/wf_demo-1a2/agent-two.jsonl")
check "the same id in another file counts again (dedup is per file)" "$(row "$out" total)" "2 8 14 22 26"

out=$("$script" "$work/fallback.jsonl")
check "a refusal fallback counts every attempt in usage.iterations as one call" "$(row "$out" total)" "1 2 25 400 4"

out=$("$script" "$work/wf_demo-1a2" "$work/plain")
check "a directory takes every journal with usage" "$(row "$out" total)" "7 21 146 3324 123"
check "the workflow line is named by its folder" \
  "$(printf '%s\n' "$out" | awk '$1 == "workflow" {print $2, $3, $4, $5, $6, $7}')" "wf_demo-1a2 6 15 126 3024 83"
check "a journal without usage gets no line" "$(printf '%s\n' "$out" | grep -c 'journal.jsonl')" "0"
check "a file outside a workflow folder is in the total only" "$(printf '%s\n' "$out" | grep -c 'workflow .*plain')" "0"

out=$("$script" "$work/plain/solo.jsonl" "$work/plain/solo.jsonl")
check "a file named twice is counted twice" "$(row "$out" total)" "2 12 40 600 80"

"$script" "$work/missing" >/dev/null 2>"$work/err"
status=$?
check "a missing path exits 1" "$status" "1"
check "a missing path is named" "$(grep -c 'no such file or directory' "$work/err")" "1"

"$script" "$work/wf_demo-1a2/journal.jsonl" >/dev/null 2>"$work/err"
check "no usage anywhere exits 1" "$?" "1"

"$script" >/dev/null 2>&1
check "no argument exits 2" "$?" "2"

exit "$failed"
