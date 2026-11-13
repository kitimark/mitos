#!/usr/bin/env bash
set -u
hook="$(cd "$(dirname "$0")" && pwd)/check-agent-spawn.sh"
failed=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export MITOS_HOOK_STATE=$work/state

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
lacks() {
  local out
  out=$("$hook" <<<"$2" 2>/dev/null)
  if grep -qF -- "$3" <<<"$out"; then echo "FAIL  $1: $out"; failed=1; else echo "ok    $1"; fi
}

check "owner with model and effort" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"prompt":"p"}}' ""
check "verifier without effort" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","run_in_background":true,"prompt":"p"}}' "sets no effort."
check "no subagent_type, no model, no effort" \
  '{"tool_name":"Agent","tool_input":{"run_in_background":true,"prompt":"p"}}' "sets no model or effort."
check "empty model string" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"","effort":"low","run_in_background":true,"prompt":"p"}}' "sets no model."
check "fork with neither" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","run_in_background":true,"prompt":"p"}}' ""
check "fork with model and effort" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","model":"opus","effort":"high","run_in_background":true,"prompt":"p"}}' "sets model and effort, which a fork ignores"
check "fork with effort only" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","effort":"low","run_in_background":true,"prompt":"p"}}' "sets effort, which a fork ignores"
check "input that is not JSON" 'not json' ""

check "no run_in_background" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"low","prompt":"Watch #84."}}' \
  "does not set run_in_background: true"
check "run_in_background false" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"low","run_in_background":false,"prompt":"p"}}' \
  "does not set run_in_background: true"
check "run_in_background as a string" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"low","run_in_background":"true","prompt":"p"}}' \
  "does not set run_in_background: true"
check "a fork without run_in_background" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","prompt":"p"}}' "does not set run_in_background: true"
check "a PR owner without a worktree" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"description":"PR owner for #91","prompt":"p"}}' \
  "sets no isolation: \"worktree\""
check "a verifier named in the prompt, without a worktree" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"xhigh","run_in_background":true,"prompt":"Role: Verifier at head 3c6e3bb."}}' \
  "sets no isolation: \"worktree\""
check "a PR owner in a worktree" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"isolation":"worktree","description":"PR owner for #91","prompt":"p"}}' ""
check "a researcher needs no worktree" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"medium","run_in_background":true,"description":"Researcher: CI queue","prompt":"Diagnose the queue."}}' ""
check "both warnings in one message" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","description":"PR owner","prompt":"p"}}' \
  "so the root stays free to answer the user (kitimark-mode, Roles). This PR owner or verifier spawn sets no isolation"
check "all three in one message" \
  '{"tool_name":"Agent","tool_input":{"description":"verifier","prompt":"p"}}' \
  "sets no model or effort. Set both from the role table in .claude/skills/kitimark-mode/SKILL.md, or say why the session default is right. This Agent call does not set run_in_background"
lacks "a fork is not checked for a worktree" \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"fork","run_in_background":true,"description":"verifier","prompt":"p"}}' "isolation"
lacks "a role named past the first 600 characters is not read" \
  "$(jq -cn --arg p "$(printf 'x%.0s' $(seq 700)) verifier" '{tool_name:"Agent",tool_input:{subagent_type:"general-purpose",model:"sonnet",effort:"low",run_in_background:true,prompt:$p}}')" "isolation"

mkdir -m 700 "$MITOS_HOOK_STATE"
note='Rule files changed on main since this session loaded its rules at beb6f01: .claude/skills/kitimark-mode/SKILL.md. Read these before acting: git fetch origin main, then git show origin/main:<file>.'
printf '%s\n' "$note" >"$MITOS_HOOK_STATE/s1.note"
check "the freshness note on a spawn that is otherwise fine" \
  '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"isolation":"worktree","description":"PR owner","prompt":"p"}}' \
  "$note Put this in the brief too."
check "the note after a warning" \
  '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","run_in_background":true,"prompt":"p"}}' \
  "sets no effort. Set both from the role table in .claude/skills/kitimark-mode/SKILL.md, or say why the session default is right. Rule files changed on main"
check "another session gets no note" \
  '{"session_id":"s2","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"prompt":"p"}}' ""
: >"$MITOS_HOOK_STATE/s1.note"
check "an empty note adds nothing" \
  '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"prompt":"p"}}' ""
printf 'first line\nsecond line\n' >"$MITOS_HOOK_STATE/s1.note"
lacks "only the note's first line is read" \
  '{"session_id":"s1","tool_name":"Agent","tool_input":{"run_in_background":true,"prompt":"p"}}' "second line"
lacks "a session id that names a path reads no file" \
  '{"session_id":"../state/s1","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"prompt":"p"}}' "first line"

spawn='{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"prompt":"p"}}'
with_note() {
  mkdir -p "$1"; chmod 700 "$1"; printf '%s\n' "$note" >"$1/s1.note"
}
printf '%s\n' "$note" >"$work/planted"
rm -f "$MITOS_HOOK_STATE/s1.note"
ln -s "$work/planted" "$MITOS_HOOK_STATE/s1.note"
check "a symlinked note is not read" "$spawn" ""
with_note "$work/link-target"
ln -s "$work/link-target" "$work/link"
MITOS_HOOK_STATE=$work/link; check "a symlinked folder is not read" "$spawn" ""
MITOS_HOOK_STATE=$work/link/; check "a symlinked folder named with a '/' at the end is not read" "$spawn" ""
MITOS_HOOK_STATE=$work/link/.; check "a symlinked folder named with '/.' at the end is not read" "$spawn" ""
with_note "$work/g"; chmod 770 "$work/g"
MITOS_HOOK_STATE=$work/g; check "a group-writable folder is not read" "$spawn" ""
with_note "$work/o"; chmod 1707 "$work/o"
MITOS_HOOK_STATE=$work/o; check "a folder others can write, sticky as /tmp, is not read" "$spawn" ""
with_note "$work/gpn/st"; chmod 770 "$work/gpn"
MITOS_HOOK_STATE=$work/gpn/st; check "a note under a group-writable parent is not read" "$spawn" ""
with_note "$work/rpn/st"; chmod 700 "$work/rpn"; ln -s "$work/rpn" "$work/lpn"
MITOS_HOOK_STATE=$work/lpn/st
check "a note through a symlinked parent is read from the real folder" "$spawn" "$note Put this in the brief too."
with_note "$work/vpn/st"; mkdir "$work/wpn"; chmod 777 "$work/wpn"; ln -s "$work/vpn" "$work/wpn/team"
MITOS_HOOK_STATE=$work/wpn/team/st
check "a note through a symlink in a folder others can write is not read" "$spawn" ""
with_note "$work/u"
mkdir "$work/otheruser"
printf '#!/bin/sh\necho %s\n' "$(($(id -u) + 1))" >"$work/otheruser/id"
chmod +x "$work/otheruser/id"
MITOS_HOOK_STATE=$work/u
check "control: a private folder's note is read" "$spawn" "$note Put this in the brief too."
saved_path=$PATH
PATH="$work/otheruser:$PATH"; check "a folder of another user is not read" "$spawn" ""
PATH=$saved_path
if [ "$(id -u)" = 0 ]; then
  with_note "$work/u2"; chown 65534 "$work/u2"
  MITOS_HOOK_STATE=$work/u2; check "a folder chowned to another user is not read" "$spawn" ""
  with_note "$work/ostk/st"; chmod 1777 "$work/ostk"; chown 65534 "$work/ostk"
  MITOS_HOOK_STATE=$work/ostk/st; check "a note under a sticky folder of another user is not read" "$spawn" ""
fi
saved_pwd=$PWD
cd "$work" || exit 1
MITOS_HOOK_STATE=u; check "a relative folder is not read" "$spawn" ""
cd "$saved_pwd" || exit 1
unset MITOS_HOOK_STATE
saved_home=$HOME
with_note "$work/tmpd/mitos-hook-state"
export TMPDIR XDG_RUNTIME_DIR
HOME=$work/home TMPDIR=$work/tmpd; check "the default folder is not under TMPDIR" "$spawn" ""
with_note "$work/home/.cache/mitos-hook-state"
check "the default folder is under HOME/.cache" "$spawn" "$note Put this in the brief too."
with_note "$work/xdg/mitos-hook-state"
HOME=$work/nohome XDG_RUNTIME_DIR=$work/xdg; check "XDG_RUNTIME_DIR comes first" "$spawn" "$note Put this in the brief too."
HOME=$saved_home; unset TMPDIR XDG_RUNTIME_DIR

mkdir -m 700 "$work/probes"
export MITOS_HOOK_STATE=$work/probes
limit_brief() {
  jq -cn --arg p "$1" --arg m "$2" '{session_id:"p1",tool_name:"Agent",tool_input:{subagent_type:"general-purpose",model:$m,effort:"high",run_in_background:true,prompt:$p}}'
}
probe_call() {
  jq -cn --arg e "$1" --arg m "$2" --arg r "$3" \
    '{session_id:"p1",hook_event_name:$e,tool_name:"Agent",tool_input:{subagent_type:"general-purpose",model:$m,effort:"low",prompt:"probe"},tool_response:{content:[{type:"text",text:$r}]}}'
}
probe_line() { cat "$MITOS_HOOK_STATE/p1.probe-$1" 2>/dev/null; }
limit_msg="is on record from the last hour"
opus_limit=$(limit_brief "Opus is at its limit, so this routine job runs on Sonnet." sonnet)
check "a limit claim for opus with no probe on record warns" "$opus_limit" "no probe of opus $limit_msg"
check "a downgrade with no limit words names opus too" \
  "$(limit_brief "Downgrading this role to Sonnet for the rest of the day." sonnet)" "no probe of opus $limit_msg"
check "a brief that names no limit is not checked" "$(limit_brief "Rebase #12 onto main." sonnet)" ""
check "an opus spawn that says nothing of another model is not checked" \
  "$(limit_brief "Fix the line limit in the script." opus)" ""

check "a PostToolUse probe records nothing on the spawn path" "$(probe_call PostToolUse opus ok)" ""
read -r stamp result <<<"$(probe_line opus)"
if [[ $stamp =~ ^[0-9]+$ && $result == pass ]]; then echo "ok    a passing opus probe is recorded"; else echo "FAIL  a passing opus probe is recorded: '$(probe_line opus)'"; failed=1; fi
check "a fresh passing probe silences the limit warning" "$opus_limit" ""

"$hook" <<<"$(probe_call PostToolUse claude-opus-4-1 "Rate limit reached")" >/dev/null 2>&1
if [[ $(probe_line opus) == *" fail" ]]; then echo "ok    a limit answer to a probe is recorded as fail"; else echo "FAIL  limit answer: '$(probe_line opus)'"; failed=1; fi
check "a fresh failing probe also counts as a real check" "$opus_limit" ""
rm -f "$MITOS_HOOK_STATE/p1.probe-opus"
"$hook" <<<"$(probe_call PostToolUseFailure opus "")" >/dev/null 2>&1
if [[ $(probe_line opus) == *" fail" ]]; then echo "ok    a failed probe call is recorded as fail"; else echo "FAIL  failed probe call: '$(probe_line opus)'"; failed=1; fi

printf '%s pass\n' "$(($(date +%s) - 3700))" >"$MITOS_HOOK_STATE/p1.probe-opus"
check "a probe older than an hour warns again" "$opus_limit" "no probe of opus $limit_msg"
printf '%s pass\n' "$(($(date +%s) - 3500))" >"$MITOS_HOOK_STATE/p1.probe-opus"
check "a probe just under an hour old counts" "$opus_limit" ""
printf '%s pass\n' "$(date +%s)" >"$MITOS_HOOK_STATE/p1.probe-sonnet"
rm -f "$MITOS_HOOK_STATE/p1.probe-opus"
check "a probe of another model does not count" "$opus_limit" "no probe of opus $limit_msg"
check "a limit claim in a session with no record warns" \
  "$(limit_brief "Opus is at its limit." sonnet | jq -c '.session_id = "p2"')" "no probe of opus $limit_msg"

rm -f "$MITOS_HOOK_STATE/p1.probe-opus"
"$hook" <<<"$(probe_call PostToolUse opus "Async agent launched" | jq -c '.tool_input.run_in_background = true')" >/dev/null 2>&1
if [[ -z $(probe_line opus) ]]; then echo "ok    a background probe launch notice is not recorded"; else echo "FAIL  background probe recorded: '$(probe_line opus)'"; failed=1; fi
# Real journals: a call sent with run_in_background false can still come back as a launch notice.
async_notice=$(probe_call PostToolUse opus "x" | jq -c '.tool_input.run_in_background = false | .tool_response = {status:"async_launched",isAsync:true,agentId:"a1"}')
"$hook" <<<"$async_notice" >/dev/null 2>&1
if [[ -z $(probe_line opus) ]]; then echo "ok    an async_launched notice for a foreground-flagged probe is not recorded"; else echo "FAIL  async notice recorded: '$(probe_line opus)'"; failed=1; fi
"$hook" <<<"$(jq -c 'del(.tool_response.status)' <<<"$async_notice")" >/dev/null 2>&1
if [[ -z $(probe_line opus) ]]; then echo "ok    an isAsync notice alone is not recorded"; else echo "FAIL  isAsync notice recorded: '$(probe_line opus)'"; failed=1; fi
"$hook" <<<"$(jq -c 'del(.tool_response.isAsync)' <<<"$async_notice")" >/dev/null 2>&1
if [[ -z $(probe_line opus) ]]; then echo "ok    a status async_launched notice alone is not recorded"; else echo "FAIL  status notice recorded: '$(probe_line opus)'"; failed=1; fi
"$hook" <<<"$(jq -c '.tool_response = {status:"completed",isAsync:false,content:[{type:"text",text:"ok"}]}' <<<"$async_notice")" >/dev/null 2>&1
if [[ $(probe_line opus) == *" pass" ]]; then echo "ok    a completed foreground probe is recorded"; else echo "FAIL  completed probe: '$(probe_line opus)'"; failed=1; fi
rm -f "$MITOS_HOOK_STATE/p1.probe-opus"
"$hook" <<<"$(probe_call PostToolUse opus "You have hit your weekly limit, resets Friday")" >/dev/null 2>&1
if [[ $(probe_line opus) == *" fail" ]]; then echo "ok    the real weekly-limit text is recorded as fail"; else echo "FAIL  weekly limit text: '$(probe_line opus)'"; failed=1; fi
rm -f "$MITOS_HOOK_STATE/p1.probe-opus"
check "a background probe does not silence the limit warning" "$opus_limit" "no probe of opus $limit_msg"
check "a spawn with no model still gets the limit check" \
  '{"session_id":"p1","tool_name":"Agent","tool_input":{"subagent_type":"fork","run_in_background":true,"prompt":"Opus is at its limit; fall back."}}' \
  "no probe of opus $limit_msg"

# fable: the role table prefers it, so it needs its own record and its own warning.
rm -f "$MITOS_HOOK_STATE/p1.probe-fable"
"$hook" <<<"$(probe_call PostToolUse fable ok)" >/dev/null 2>&1
if [[ $(probe_line fable) == *" pass" ]]; then echo "ok    a passing fable probe is recorded"; else echo "FAIL  fable probe: '$(probe_line fable)'"; failed=1; fi
rm -f "$MITOS_HOOK_STATE/p1.probe-fable"
"$hook" <<<"$(probe_call PostToolUse claude-fable-5-2 ok)" >/dev/null 2>&1
if [[ $(probe_line fable) == *" pass" ]]; then echo "ok    a probe on the resolved fable id is recorded"; else echo "FAIL  resolved fable probe: '$(probe_line fable)'"; failed=1; fi
rm -f "$MITOS_HOOK_STATE/p1.probe-fable"
check "fable at its limit, running on opus, names fable" \
  "$(limit_brief "Fable is at its limit, so this runs on Opus." opus)" "no probe of fable $limit_msg"
check "downgrading from fable to opus names fable" \
  "$(limit_brief "Downgrading from fable to opus for this row." opus)" "no probe of fable $limit_msg"
lacks "fable at its limit, running on sonnet, does not name opus" \
  "$(limit_brief "Fable is at its limit, so this runs on Sonnet." sonnet)" "probe of opus"
check "fable at its limit, running on sonnet, names fable" \
  "$(limit_brief "Fable is at its limit, so this runs on Sonnet." sonnet)" "no probe of fable $limit_msg"
printf '%s pass\n' "$(date +%s)" >"$MITOS_HOOK_STATE/p1.probe-fable"
check "a fresh fable probe silences the fable warning" \
  "$(limit_brief "Fable is at its limit, so this runs on Opus." opus)" ""
rm -f "$MITOS_HOOK_STATE/p1.probe-fable"
check "'hit your weekly limit' in a brief is a limit claim" \
  "$(limit_brief "You hit your weekly limit on Opus, so run on Sonnet." sonnet)" "no probe of opus $limit_msg"

before=$(probe_line sonnet)
"$hook" <<<"$(probe_call PostToolUse sonnet "an ordinary answer" | jq -c '.tool_input.prompt = "do the work"')" >/dev/null 2>&1
if [[ $(probe_line sonnet) == "$before" ]]; then echo "ok    a call that is not a probe leaves the record alone"; else echo "FAIL  non-probe changed record"; failed=1; fi
"$hook" <<<"$(probe_call PostToolUse sonnet "ok" | jq -c '.tool_input.prompt = "ok"')" >/dev/null 2>&1
if [[ $(probe_line sonnet) == "$before" ]]; then echo "ok    a different one-word prompt is not recorded"; else echo "FAIL  one-word prompt recorded"; failed=1; fi

probe_spawn=$(probe_call PreToolUse opus "" | jq -c 'del(.hook_event_name, .tool_response)')
check "a one-word probe spawn gets no run_in_background warning" "$probe_spawn" ""
check "a probe spawn is still checked for effort" \
  "$(jq -c 'del(.tool_input.effort)' <<<"$probe_spawn")" "sets no effort."
check "a different one-word prompt is not a probe" \
  "$(jq -c '.tool_input.prompt = "ok"' <<<"$probe_spawn")" "does not set run_in_background: true"
unset MITOS_HOOK_STATE

# The hook only runs after a call if settings.json wires it to both post-call events.
settings=${hook%/*}/../settings.json
for ev in PostToolUse PostToolUseFailure; do
  if jq -e --arg ev "$ev" '[.hooks[$ev][]? | select(.matcher == "Agent") | .hooks[].command | endswith("/check-agent-spawn.sh")] | any' "$settings" >/dev/null 2>&1; then
    echo "ok    settings.json runs the spawn hook on $ev for Agent"
  else echo "FAIL  settings.json does not run the spawn hook on $ev for Agent"; failed=1; fi
done

mkdir "$work/alone"
cp "$hook" "$work/alone/"
hook=$work/alone/check-agent-spawn.sh
check "without hook-state.sh the other warnings stay" \
  '{"session_id":"s1","tool_name":"Agent","tool_input":{"description":"verifier","prompt":"p"}}' \
  "sets no model or effort. Set both from the role table in .claude/skills/kitimark-mode/SKILL.md, or say why the session default is right. This Agent call does not set run_in_background"

# Without hook-state.sh a post-call event must print nothing, not a PreToolUse warning.
out=$("$hook" <<<"$(probe_call PostToolUse sonnet ok | jq -c 'del(.tool_input.effort, .tool_input.model)')" 2>/dev/null)
if [ -z "$out" ]; then echo "ok    a post-call event without hook-state.sh prints nothing"; else echo "FAIL  post-call output: $out"; failed=1; fi

exit "$failed"
