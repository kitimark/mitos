#!/usr/bin/env bash
set -u

die() { printf 'watch-own: %s\n' "$1" >&2; exit 1; }

usage="usage: watch-own.sh <state-dir> assign|unassign|label|unlabel <number> <value> | merge|close <number>"
[ $# -ge 3 ] || die "$usage"
dir=$1 kind=$2 n=$3 value=${4:-}
[[ $n =~ ^[0-9]{1,9}$ ]] || die "$usage"
case $kind in
  assign | unassign | label | unlabel)
    [ $# -eq 4 ] || die "$usage"
    [[ $value =~ ^[^[:space:][:cntrl:]]{1,50}$ ]] || die "the value must be one word of at most 50 characters" ;;
  merge | close)
    [ $# -eq 3 ] || die "$usage" ;;
  *) die "$usage" ;;
esac
command -v flock >/dev/null 2>&1 || die "flock is not installed"
if [ -n "${WATCH_NOW:-}" ]; then now=$WATCH_NOW; else now=$(date -u +%s); fi
[[ $now =~ ^[0-9]{1,12}$ ]] || die "WATCH_NOW must be epoch seconds"

mkdir -p "$dir" 2>/dev/null || die "cannot make the state directory"
exec 8>>"$dir/own.lock" || die "cannot write the state directory"
flock -w 5 8 || die "cannot lock the own-writes file"
printf '%s %s %s%s\n' "$now" "$kind" "$n" "${value:+ $value}" >>"$dir/own-writes" || die "cannot record the write"
