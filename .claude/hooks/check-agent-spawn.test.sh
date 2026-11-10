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

# The note is read only from a private folder of this user, and never through a symlink.
spawn='{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","model":"opus","effort":"xhigh","run_in_background":true,"prompt":"p"}}'
with_note() { # folder: makes it private and puts the note in it
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

mkdir "$work/alone"
cp "$hook" "$work/alone/"
hook=$work/alone/check-agent-spawn.sh
check "without hook-state.sh the other warnings stay" \
  '{"session_id":"s1","tool_name":"Agent","tool_input":{"description":"verifier","prompt":"p"}}' \
  "sets no model or effort. Set both from the role table in .claude/skills/kitimark-mode/SKILL.md, or say why the session default is right. This Agent call does not set run_in_background"

exit "$failed"
