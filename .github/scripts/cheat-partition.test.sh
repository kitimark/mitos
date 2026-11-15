#!/usr/bin/env bash
# Partition and aggregator. No network. A case the shards do not record fails
# the aggregator even when every shard agrees with the partition function.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/cheat-partition.sh
wf=$root/.github/workflows/ci.yml

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

[ -x "$script" ] || fail "partition script is not executable"

n=$("$script" n)
[ "$n" = 3 ] || fail "N is $n, the measured split is 3"

a=$("$script" cases)
b=$("$script" cases)
[ "$a" = "$b" ] || fail "case list changed between two runs"
[ -n "$a" ] || fail "the corpus has no cases"
"$script" check
ok "real corpus is stable, complete and has no empty shard"

one=$("$script" shard 0 | head -1)
[ -n "$one" ] || fail "shard 0 produced no name"
ok "a shard command names at least one case"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tiny=$work/tiny
mkdir -p "$tiny/one" "$tiny/two"
if "$script" check "$tiny" 2>"$work/empty.err"; then
  fail "N larger than the case count was accepted"
fi
grep -q "would be empty" "$work/empty.err" || fail "empty shard was not the reason"
ok "N larger than the case count fails"

mkdir -p "$tiny/three"
"$script" check "$tiny"
got=$(printf '%s\n' "$("$script" shard 0 "$tiny")" "$("$script" shard 1 "$tiny")" "$("$script" shard 2 "$tiny")" | LC_ALL=C sort)
want=$(printf '%s\n' one two three | LC_ALL=C sort)
[ "$got" = "$want" ] || fail "three cases did not land one per shard"
ok "three cases are one per shard"

# The recorded lists are what the aggregator trusts, not a second call of shard.
fill_shard() {
  local k=$1 name=$2 exit_code=${3:-0}
  local dir=$work/shards/cheat-shard-logs-$k
  mkdir -p "$dir"
  printf '%s\n' "$exit_code" >"$dir/shard-exit"
  printf '%s\n' "$name" >"$dir/shard-cases"
  printf 'case\tmode\tstart_ms\tend_ms\texit\ttimed_out\n%s\tfull\t0\t1\t1\tfalse\n%s\tcomparator\t1\t2\t1\tfalse\n' \
    "$name" "$name" >"$dir/timing.tsv"
  printf 'ran\n' >"$dir/$name.full.log"
  printf 'ran\n' >"$dir/$name.comparator.log"
  printf 'CASE FULL\n%s REJECTED\n\ncheat corpus: all 1 cases behave as expected\n' "$name" >"$dir/table.txt"
}

fill_good() {
  rm -rf "$work/shards" "$work/merged"
  # LC_ALL=C order is one, three, two, so indexes 0, 1, 2.
  fill_shard 0 one
  fill_shard 1 three
  fill_shard 2 two
}

run_agg() {
  local expect=$1 title=$2
  shift 2
  local st out
  set +e
  out=$(env "$@" "$script" aggregate "$work/shards" "$work/merged" "$tiny" 2>"$work/agg.err")
  st=$?
  set -e
  printf '%s\n' "$out" >"$work/agg.out"
  if [ "$expect" = 0 ]; then
    [ "$st" -eq 0 ] || fail "$title exited $st: $(cat "$work/agg.err")"
  else
    [ "$st" -ne 0 ] || fail "$title exited 0"
  fi
}

fill_good
run_agg 0 "complete fixture" CHECKS=success SHARDS=success
grep -qx 'cheat corpus: all 3 cases behave as expected' "$work/agg.out" \
  || fail "combined table did not report 3 cases"
# Each case row once. The summary line does not start with the case name.
for name in one two three; do
  c=$(awk -v n="$name" '$1 == n { c++ } END { print c+0 }' "$work/agg.out")
  [ "$c" = 1 ] || fail "case $name appears $c times in the combined table"
done
headers=$(awk 'BEGIN { c = 0 } $1 == "case" { c++ } END { print c }' "$work/merged/timing.tsv")
[ "$headers" = 1 ] || fail "timing.tsv has $headers headers"
if [ ! -f "$work/merged/one.full.log" ] || [ ! -f "$work/merged/three.comparator.log" ]; then
  fail "merged logs are missing"
fi
if ! grep -q $'\t0$' "$work/merged/timing.tsv" || ! grep -q $'\t2$' "$work/merged/timing.tsv"; then
  fail "timing.tsv has no shard column"
fi
ok "complete fixture exits 0 with one timing header and each case once"

fill_good
rm -rf "$work/shards/cheat-shard-logs-1"
run_agg 1 "missing shard" CHECKS=success SHARDS=success
grep -q "missing shard 1" "$work/agg.err" || fail "missing shard was not named"
ok "a missing shard fails"

fill_good
printf '1\n' >"$work/shards/cheat-shard-logs-2/shard-exit"
run_agg 1 "nonzero shard exit" CHECKS=success SHARDS=success
grep -q "shard 2 exited 1" "$work/agg.err" || fail "nonzero exit was not named"
ok "a nonzero shard exit fails"

fill_good
printf 'one\nextra\n' >"$work/shards/cheat-shard-logs-0/shard-cases"
run_agg 1 "extra name" CHECKS=success SHARDS=success
ok "an extra name fails"

fill_good
printf 'one\none\n' >"$work/shards/cheat-shard-logs-0/shard-cases"
run_agg 1 "duplicate name" CHECKS=success SHARDS=success
ok "a duplicate name fails"

fill_good
printf 'case\tmode\tstart_ms\tend_ms\texit\ttimed_out\none\tfull\t0\t1\t1\tfalse\n' \
  >"$work/shards/cheat-shard-logs-0/timing.tsv"
run_agg 1 "timing drops a case" CHECKS=success SHARDS=success
grep -q "drops one" "$work/agg.err" || fail "a dropped timing row was not named"
ok "a zero exit whose timing drops a case fails"

fill_good
run_agg 1 "checks failed" CHECKS=failure SHARDS=success
grep -q "checks=failure" "$work/agg.err" || fail "a failed checks job was not named"
ok "a failed checks job fails the corpus step"

fill_good
run_agg 1 "shard cancelled" CHECKS=success SHARDS=cancelled
grep -q "shards=cancelled" "$work/agg.err" || fail "a cancelled shard was not named"
ok "a cancelled shard fails the corpus step"

fill_good
run_agg 1 "shard skipped" CHECKS=success SHARDS=skipped
grep -q "shards=skipped" "$work/agg.err" || fail "a skipped shard was not named"
ok "a skipped shard fails the corpus step"

fill_good
printf 'CASE FULL\none REJECTED  <-- FAIL\n' >"$work/shards/cheat-shard-logs-0/table.txt"
run_agg 1 "table marks a failure" CHECKS=success SHARDS=success
ok "a table that marks a failure fails"

# The workflow's matrix, timeouts and checkout flags stay tied to this script.
grep -q 'shard: \[0, 1, 2\]' "$wf" || fail "workflow matrix is not 0, 1, 2"
grep -q 'refusing: mitos-gate cheats with no names runs the whole corpus' "$wf" \
  || fail "a shard can call mitos-gate cheats with no names"
grep -q 'status=$?' "$wf" || fail "the shard step does not keep the exit status"
grep -q 'cat .lake/cheats/table.txt' "$wf" || fail "a red shard does not print its table"
co=$(grep -c 'uses: actions/checkout@v4' "$wf")
pc=$(grep -c 'persist-credentials: false' "$wf")
if [ "$co" != 4 ] || [ "$pc" != 4 ]; then
  fail "checkout=$co persist-credentials=$pc, want 4 and 4"
fi
grep -q '^concurrency:' "$wf" && fail "ci.yml has a top-level concurrency group"
ok "workflow matrix, status, table and checkouts match"

awk '
  /^  [a-z0-9-]+:$/ { job = $1; gsub(":", "", job) }
  /^    timeout-minutes:/ { print job, $2 }
' "$wf" >"$work/timeouts"
expect=$'cancel-superseded 5\nchecks 20\ncheat-shard 30\nprove 10\ngate 30\nscorecard-comment 5'
[ "$(cat "$work/timeouts")" = "$expect" ] || fail "timeouts are [$(cat "$work/timeouts")]"
ok "job timeouts match the agreed minutes"

awk '
  /^  gate:$/ { g = 1; next }
  /^  [a-z0-9-]+:$/ { g = 0 }
  g && /^    needs:/ { bad = 1 }
  g && /^    if:/ { bad = 1 }
  END { exit bad }
' "$wf" || fail "gate has needs or a job if, so a skip would count as passed"
awk '
  /^  prove:$/ { p = 1; next }
  /^  [a-z0-9-]+:$/ { p = 0 }
  p { print }
' "$wf" >"$work/prove"
grep -q 'name: cheat-logs' "$work/prove" || fail "prove does not upload cheat-logs"
grep -q 'if: always()' "$work/prove" && fail "prove uploads cheat-logs on a failed corpus"
grep -q 'Cheat corpus is rejected (mitos-gate cheats, runs in parallel)' "$work/prove" \
  || fail "the corpus step is not in prove"
ok "gate cannot be skipped and cheat-logs uploads only after the corpus step"

awk '
  /^  cheat-shard:$/ { s = 1; next }
  /^  [a-z0-9-]+:$/ { s = 0 }
  s { print }
' "$wf" >"$work/shard"
grep -q 'if: always()' "$work/shard" || fail "a shard upload does not keep if: always()"
grep -q 'Cheat corpus is rejected' "$work/shard" && fail "a shard step is named like the corpus step"
ok "shard logs upload on a red run and no shard step wears the corpus name"

echo "cheat-partition: done"
