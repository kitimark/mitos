#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

check_job() {
  local workflow=$1 job=$2 predecessor=$3
  awk -v job="$job:" '
    /^  [a-z0-9-]+:$/ { active = ($1 == job) }
    active { print }
  ' "$root/.github/workflows/$workflow.yml" > "$work/job"
  awk '
    /^      - / { active = /name: Drop restored cheat and mutant logs$/ }
    active { print }
  ' "$work/job" > "$work/clear"
  [ "$(grep -c 'name: Drop restored cheat and mutant logs' "$work/clear")" = 1 ] \
    || fail "$workflow/$job needs one cleanup"
  grep -qx '        if: always()' "$work/clear" \
    || fail "$workflow/$job skips cleanup after failure or cancellation"
  awk -v predecessor="$predecessor" '
    /^      - / {
      if (/name: Drop restored cheat and mutant logs$/) found = (previous == predecessor)
      previous = $0
    }
    END { exit !found }
  ' "$work/job" || fail "$workflow/$job cleanup is not immediately after restore/setup"
  sed -n 's/^        run: //p' "$work/clear" > "$work/clear.sh"
  [ -s "$work/clear.sh" ] || fail "$workflow/$job has no cleanup command"

  printf 'ok   %s/%s cleanup is immediate and unconditional\n' "$workflow" "$job"

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
    (cd "$dir" && bash -e "$work/clear.sh")
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

check_job ci checks '      - uses: actions/cache@v4'
check_job ci cheat-shard '      - uses: actions/cache/restore@v4'
check_job nightly full '      - uses: ./.github/actions/setup'
