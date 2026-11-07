#!/usr/bin/env bash
set -u
hook="$(dirname "$0")/check-agent-spawn.sh"
failed=0

check() {
  local name=$1 input=$2 expect=$3 out code
  out=$("$hook" <<<"$input" 2>/dev/null)
  code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL  $name: exit $code"; failed=1; return
  fi
  if [ -z "$expect" ]; then
    if [ -z "$out" ]; then echo "ok    $name: silent"; else echo "FAIL  $name: $out"; failed=1; fi
    return
  fi
  if jq -e --arg e "$expect" \
      '.hookSpecificOutput.hookEventName == "PreToolUse"
       and (.hookSpecificOutput.additionalContext | contains($e))
       and .systemMessage == .hookSpecificOutput.additionalContext' <<<"$out" >/dev/null; then
    echo "ok    $name: $(jq -r .systemMessage <<<"$out")"
  else
    echo "FAIL  $name: $out"; failed=1
  fi
}

check "owner with model and effort" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","prompt":"p"}}' ""
check "verifier without effort" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","prompt":"p"}}' "sets no effort."
check "no subagent_type, no model, no effort" \
  '{"tool_name":"Agent","tool_input":{"prompt":"p"}}' "sets no model or effort."
check "empty model string" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"","effort":"low","prompt":"p"}}' "sets no model."
check "fork with neither" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","prompt":"p"}}' ""
check "fork with model and effort" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","model":"opus","effort":"high","prompt":"p"}}' "sets model and effort, which a fork ignores"
check "fork with effort only" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","effort":"low","prompt":"p"}}' "sets effort, which a fork ignores"
check "input that is not JSON" 'not json' ""

exit "$failed"
