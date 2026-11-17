#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bin="$root/.lake/build/bin/mitos-gate"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cleanup='Drop restored cheat and mutant logs'

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

check_job() {
  local file=$1 job=$2 predecessor=$3
  local selector="jobs.$job.steps[name=$cleanup]" line path index previous command
  [ "$("$bin" workflow get "$file" "$selector.name")" = "$cleanup" ] \
    || fail "$file/$job needs one cleanup"
  [ "$("$bin" workflow get "$file" "$selector.if")" = 'always()' ] \
    || fail "$file/$job skips cleanup after failure or cancellation"
  line=$("$bin" workflow each "$file" "$selector.name")
  path=${line%%$'\t'*}
  [[ $path =~ \.steps\[([0-9]+)\]\.name$ ]] || fail "$file/$job has no cleanup index"
  index=${BASH_REMATCH[1]}
  [ "$index" -gt 0 ] || fail "$file/$job cleanup has no predecessor"
  previous=$((index - 1))
  [ "$("$bin" workflow get "$file" "jobs.$job.steps[$previous].uses")" = "$predecessor" ] \
    || fail "$file/$job cleanup is not immediately after restore/setup"
  command=$("$bin" workflow get "$file" "$selector.run") || fail "$file/$job has no cleanup command"
  [ -n "$command" ] || fail "$file/$job has no cleanup command"
  printf '%s\n' "$command" > "$work/clear.sh"
  printf 'ok   %s/%s cleanup is immediate and unconditional\n' "$(basename "$file")" "$job"
  "$root/.github/scripts/cache-logs.test.sh" "$(basename "$file")" "$job" "$work/clear.sh"
}

if [ $# -eq 3 ]; then
  check_job "$@"
  exit 0
fi
[ $# -eq 0 ] || fail 'expected no arguments or <workflow-file> <job> <predecessor-uses>'
check_job .github/workflows/ci.yml checks actions/cache@v4
check_job .github/workflows/ci.yml cheat-shard actions/cache/restore@v4
check_job .github/workflows/nightly.yml full ./.github/actions/setup
python3 -I gate/cache-logs-mutations.py "$bin" "$root/gate/cache-logs-test.sh"
