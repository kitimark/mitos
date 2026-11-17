#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  printf 'Cache-log workflow checks run after the build in gate/cache-logs-test.sh\n'
  exit 0
fi
[ $# -eq 3 ] || { printf 'usage: %s <workflow> <job> <cleanup-script>\n' "$0" >&2; exit 2; }
workflow=$1 job=$2 cleanup=$3
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

check_scenarios() {
  local scenario
  for scenario in restored-cache success cold-cache; do
    local dir="$work/$workflow-$job-$scenario"
    mkdir -p "$dir/.lake/build" "$dir/core/.lake"
    printf 'build cache\n' > "$dir/.lake/build/keep"
    printf 'core cache\n' > "$dir/core/.lake/keep"
    if [ "$scenario" != cold-cache ]; then
      mkdir -p "$dir/.lake/cheats" "$dir/.lake/mutants"
      printf 'old cheat\n' > "$dir/.lake/cheats/deleted-case.full.log"
      printf 'old mutant\n' > "$dir/.lake/mutants/deleted-mutant.log"
    fi
    (cd "$dir" && bash -e "$cleanup")
    [ ! -e "$dir/.lake/cheats" ] && [ ! -e "$dir/.lake/mutants" ] \
      || fail "$workflow/$job/$scenario retains restored logs"
    [ "$(cat "$dir/.lake/build/keep")" = 'build cache' ] \
      && [ "$(cat "$dir/core/.lake/keep")" = 'core cache' ] \
      || fail "$workflow/$job/$scenario removed build cache"
    if [ "$scenario" = success ]; then
      mkdir -p "$dir/.lake/cheats" "$dir/.lake/mutants"
      printf 'fresh\n' > "$dir/.lake/cheats/current.full.log"
      printf 'fresh\n' > "$dir/.lake/mutants/current.log"
      [ "$(find "$dir/.lake/cheats" "$dir/.lake/mutants" -type f | wc -l)" -eq 2 ] \
        || fail "$workflow/$job success has extra logs"
    fi
    printf 'ok   %s/%s/%s\n' "$workflow" "$job" "$scenario"
  done
}

check_scenarios
