#!/usr/bin/env bash

main_tool_inputs=(gate core lakefile.toml lake-manifest.json lean-toolchain .github/workflows/land.yml)

main_tool_dir() {
  local common
  common=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || return 1
  printf '%s\n' "${MITOS_MAIN_TOOL:-$common/mitos-main-tool}"
}

main_tool_bin() { printf '%s\n' "$1/.lake/build/bin/mitos-gate"; }

main_tool_why() { printf '%s\n' "$1" >&2; }

main_tool_fresh() {
  local proj=$1 stamp=$2 at=$3 bin=$4 built
  built=$(cat "$stamp" 2>/dev/null) || return 1
  [[ $built =~ ^[0-9a-f]{40}$ ]] && [ -x "$bin" ] || return 1
  [ "$built" = "$at" ] \
    || git -C "$proj" diff --quiet "$built" "$at" -- "${main_tool_inputs[@]}" 2>/dev/null
}

main_tool() {
  local mode=$1 dir=${2:-} at=${3:-} proj=${CLAUDE_PROJECT_DIR:-.} bin stamp wait try
  case $mode in
    ensure) wait=1800 ;;
    ready) wait=${MAIN_TOOL_READY_WAIT:-30} ;;
    *) main_tool_why "main_tool takes ensure or ready"; return 1 ;;
  esac
  [ -n "$dir" ] || { main_tool_why "main_tool takes the folder main_tool_dir prints"; return 1; }
  bin=$(main_tool_bin "$dir")
  stamp=$dir/.lake/main-tool.built
  if [ "$mode" = ensure ] || [ -z "$at" ]; then
    # Two callers fetching at once lock the same remote-tracking ref, and the loser fails.
    for try in 1 2 3; do
      timeout -k 5 60 git -C "$proj" fetch -q origin main </dev/null 2>/dev/null && break
      [ "$try" = 3 ] && { main_tool_why "cannot fetch origin main"; return 1; }
      sleep 1
    done
    at=$(git -C "$proj" rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}') \
      || { main_tool_why "no origin/main"; return 1; }
  fi
  [[ $at =~ ^[0-9a-f]{40}$ ]] || { main_tool_why "main is not a commit"; return 1; }
  if [ -z "${MAIN_TOOL_FD:-}" ]; then
    exec {MAIN_TOOL_FD}>>"$dir.lock" || { main_tool_why "cannot open the lock"; return 1; }
  fi
  flock -s -w "$wait" "$MAIN_TOOL_FD" || { main_tool_why "the checkout is busy"; return 1; }
  main_tool_fresh "$proj" "$stamp" "$at" "$bin" && return 0
  if [ "$mode" = ready ]; then
    main_tool_why "main's tool is not built at ${at:0:7}"
    return 1
  fi
  command -v lake >/dev/null 2>&1 || { main_tool_why "lake is not installed"; return 1; }
  flock -x -w 1800 "$MAIN_TOOL_FD" || { main_tool_why "the checkout stayed busy"; return 1; }
  if ! main_tool_fresh "$proj" "$stamp" "$at" "$bin"; then
    rm -f -- "$stamp"
    if [ -e "$dir/.git" ]; then
      git -C "$dir" checkout -q --force --detach "$at" 2>/dev/null \
        || { main_tool_why "cannot move the checkout to ${at:0:7}"; return 1; }
    else
      git -C "$proj" worktree add -q --detach "$dir" "$at" 2>/dev/null \
        || { main_tool_why "cannot add the checkout"; return 1; }
    fi
    (cd "$dir" && lake build mitos-gate) >"$dir.build.log" 2>&1 </dev/null \
      || { main_tool_why "the build at ${at:0:7} failed, see $dir.build.log"; return 1; }
    printf '%s\n' "$at" >"$stamp" || { main_tool_why "cannot write the stamp"; return 1; }
  fi
  flock -s "$MAIN_TOOL_FD" || { main_tool_why "cannot take the shared lock back"; return 1; }
}
