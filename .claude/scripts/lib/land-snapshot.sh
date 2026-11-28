#!/usr/bin/env bash

readonly LAND_SNAPSHOT_STEP_SECONDS_DEFAULT=240

land_snapshot_why() { printf '%s\n' "$1" >&2; }

land_snapshot() {
  local repo=$1 out=$2 tool_dir=$3 tool_bin=$4 dash
  local step_seconds=${LAND_SNAPSHOT_STEP_SECONDS:-$LAND_SNAPSHOT_STEP_SECONDS_DEFAULT}
  [[ $out == /* ]] || { land_snapshot_why "land_snapshot takes an absolute folder"; return 1; }
  dash=$(sed -n 's/^ *LAND_DASHBOARD: \([1-9][0-9]\{0,6\}\)$/\1/p' \
    "$tool_dir/.github/workflows/land.yml" 2>/dev/null)
  [[ $dash =~ ^[1-9][0-9]{0,6}$ ]] \
    || { land_snapshot_why "main's land.yml does not name one LAND_DASHBOARD"; return 1; }
  timeout -k 5 "$step_seconds" "$tool_dir/gate/snapshot-fetch.sh" "$repo" "$dash" "$out/reads" \
    2>"$out/fetch.err" </dev/null
  case $? in
    0) ;;
    124 | 137) land_snapshot_why "the fetch timed out"; return 1 ;;
    *) land_snapshot_why "the fetch refused: $(tail -n 1 "$out/fetch.err")"; return 1 ;;
  esac
  (cd "$tool_dir" && timeout -k 5 "$step_seconds" "$tool_bin" snapshot "$out/reads") >"$out/snapshot.json" \
    2>"$out/snapshot.err" </dev/null
  case $? in
    0) ;;
    124 | 137) land_snapshot_why "the snapshot timed out"; return 1 ;;
    *) land_snapshot_why "the snapshot refused: $(tail -n 1 "$out/snapshot.err")"; return 1 ;;
  esac
}
