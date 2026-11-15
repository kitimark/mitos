#!/usr/bin/env bash
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bin=$root/.lake/build/bin/mitos-gate

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

[ -x "$bin" ] || fail "mitos-gate is not built"

list_shard() { "$bin" cheats --list --shard "$1"; }

a=$(list_shard 0/3)
b=$(list_shard 0/3)
[ "$a" = "$b" ] || fail "shard 0 changed between two listings"
[ -n "$a" ] || fail "shard 0 is empty on the real corpus"
one=$(list_shard 1/3)
two=$(list_shard 2/3)
[ -n "$one" ] && [ -n "$two" ] || fail "a real residue is empty"
got=$(printf '%s\n' "$a" "$one" "$two" | LC_ALL=C sort)
want=$(find eval/cheats -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | LC_ALL=C sort)
[ "$got" = "$want" ] || fail "the three shards are not the case directory"
ok "the real corpus is one stable partition"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tiny=$work/tiny
mkdir -p "$tiny/one" "$tiny/two"
if "$bin" cheats --list --shard 2/3 --cases "$tiny" >"$work/empty.out" 2>"$work/empty.err"; then
  fail "a residue past the case count was accepted"
fi
grep -q "would be empty" "$work/empty.err" || fail "empty shard was not the reason: $(cat "$work/empty.err")"
ok "N larger than the case count fails"

mkdir -p "$tiny/three"
got=$("$bin" cheats --list --shard 0/3 --cases "$tiny"; "$bin" cheats --list --shard 1/3 --cases "$tiny"; "$bin" cheats --list --shard 2/3 --cases "$tiny")
[ "$got" = $'one\nthree\ntwo' ] || fail "three cases listed as [$got]"
ok "three cases are one per shard"

if "$bin" cheats --list --shard 0/10000000000 --cases "$tiny" >"$work/huge.out" 2>"$work/huge.err"; then
  fail "a huge modulus was accepted"
fi
grep -q "shard 3 would be empty" "$work/huge.err" || fail "huge modulus said $(cat "$work/huge.err")"
ok "a huge modulus is refused without walking it"

if "$bin" cheats --shard 0/3 --cases "$tiny" >"$work/run.out" 2>"$work/run.err"; then
  fail "--cases without --list was allowed to run"
fi
grep -q "only lists" "$work/run.err" || fail "--cases without --list gave $(cat "$work/run.err")"
ok "a shard does not run a directory other than eval/cheats"

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
  printf 'CASE FULL\n%s REJECTED\n' "$name" >"$dir/table.txt"
}

fill_good() {
  rm -rf "$work/shards" "$work/merged" "$work/merged.work" "$work/merged.old"
  fill_shard 0 one
  fill_shard 1 three
  fill_shard 2 two
}

run_agg() {
  local expect=$1 title=$2
  shift 2
  local st
  set +e
  env "$@" "$bin" cheats aggregate \
    --checks "${CHECKS:-success}" --shards "${SHARDS:-success}" \
    --merged "$work/merged" --cases "$tiny" \
    "$work/shards/cheat-shard-logs-0" \
    "$work/shards/cheat-shard-logs-1" \
    "$work/shards/cheat-shard-logs-2" >"$work/agg.out" 2>"$work/agg.err"
  st=$?
  set -e
  if [ "$expect" = 0 ]; then
    [ "$st" -eq 0 ] || fail "$title exited $st: $(cat "$work/agg.err")"
  else
    [ "$st" -ne 0 ] || fail "$title was accepted"
    grep -q "$expect" "$work/agg.err" || fail "$title said $(cat "$work/agg.err")"
  fi
}

fill_good
CHECKS=success SHARDS=success run_agg 0 "complete records"
grep -q 'cheat corpus: all 3 cases behave as expected' "$work/agg.out" || fail "verdict line missing"
[ -f "$work/merged/one.full.log" ] || fail "full log was not published"
[ -f "$work/merged/two.comparator.log" ] || fail "comparator log was not published"
grep -q $'false\t0' "$work/merged/timing.tsv" || fail "timing has no shard column"
CHECKS=success SHARDS=success run_agg 0 "republish"
[ -f "$work/merged/one.full.log" ] || fail "republish dropped a log"
ok "a complete record publishes, and a second run replaces it"

rm -rf "$work/shards/cheat-shard-logs-1"
run_agg "missing shard" "missing shard"
ok "a missing shard fails"

fill_good
printf '1\n' >"$work/shards/cheat-shard-logs-2/shard-exit"
run_agg "exited 1" "bad exit"
ok "a nonzero shard exit fails"

fill_good
printf 'one\nextra\n' >"$work/shards/cheat-shard-logs-0/shard-cases"
run_agg "not the partition" "extra name"
ok "an extra recorded name fails"

fill_good
printf 'case\tmode\tstart_ms\tend_ms\texit\ttimed_out\none\tfull\t0\t1\t1\tfalse\n' \
  >"$work/shards/cheat-shard-logs-0/timing.tsv"
run_agg "drops one" "timing drop"
ok "a dropped timing mode fails"

fill_good
CHECKS=failure SHARDS=success run_agg "checks=failure" "checks failed"
CHECKS=success SHARDS=cancelled run_agg "shards=cancelled" "shards cancelled"
CHECKS=success SHARDS=skipped run_agg "shards=skipped" "shards skipped"
ok "a failed, cancelled, or skipped job fails"

fill_good
printf 'CASE FULL\none REJECTED  <-- FAIL\n' >"$work/shards/cheat-shard-logs-0/table.txt"
CHECKS=success SHARDS=success run_agg "marks it failed" "table fail"
ok "a failed table row fails"

fill_good
rm "$work/shards/cheat-shard-logs-0/one.full.log"
ln -s one.comparator.log "$work/shards/cheat-shard-logs-0/one.full.log"
CHECKS=success SHARDS=success run_agg "has no full log" "symlink log"
ok "a symlink is not a log"

fill_good
mv "$work/shards/cheat-shard-logs-0" "$work/shards/real-0"
ln -s real-0 "$work/shards/cheat-shard-logs-0"
CHECKS=success SHARDS=success run_agg "missing shard" "symlinked shard dir"
ok "a symlinked shard directory is not a shard"

fill_good
rm "$work/shards/cheat-shard-logs-0/one.full.log"
mkdir "$work/shards/cheat-shard-logs-0/one.full.log"
CHECKS=success SHARDS=success run_agg "has no full log" "directory log"
ok "a directory in place of a log is not a log"

fill_good
mkdir -p "$tiny/four"
run_agg "not the partition" "dropped directory name"
rmdir "$tiny/four"
ok "a case the records omit fails"

echo "cheats-shard: done"
