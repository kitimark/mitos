#!/usr/bin/env bash
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
wf=$root/.github/workflows/ci.yml
old=$root/.github/scripts/cheat-partition.sh

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

[ ! -e "$old" ] || fail "cheat-partition.sh is still in the tree"
ok "the shell partition script is gone"

grep -q 'shard: \[0, 1, 2\]' "$wf" || fail "workflow matrix is not 0, 1, 2"
grep -q -- '--shard "${{ matrix.shard }}/3"' "$wf" || fail "a shard does not call mitos-gate cheats --shard"
grep -q 'mapfile' "$wf" && fail "the shard step still builds a bash name array"
grep -q 'cheat-partition.sh' "$wf" && fail "ci.yml still calls cheat-partition.sh"
grep -q 'status=$?' "$wf" || fail "the shard step does not keep the exit status"
grep -q 'shard-cases is empty' "$wf" || fail "an empty shard-cases file would not fail the shard"
grep -q 'cat .lake/cheats/table.txt' "$wf" || fail "a red shard does not print its table"
grep -q 'mitos-gate-bin' "$wf" || fail "prove is not given the checks binary"
grep -qF '/\.elan/' "$wf" || fail "the ldd guard does not refuse a toolchain library"
ok "workflow shard, binary upload and empty-record check are present"

co=$(grep -c 'uses: actions/checkout@v4' "$wf")
pc=$(grep -c 'persist-credentials: false' "$wf")
if [ "$co" != 5 ] || [ "$pc" != 5 ]; then
  fail "checkout=$co persist-credentials=$pc, want 5 and 5"
fi
grep -q '^concurrency:' "$wf" && fail "ci.yml has a top-level concurrency group"
ok "checkouts and the absent top-level concurrency group match"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

awk '
  /^  [a-z0-9-]+:$/ { job = $1; gsub(":", "", job) }
  /^    timeout-minutes:/ { print job, $2 }
' "$wf" >"$work/timeouts"
expect=$'cancel-superseded 5\nchecks 20\ncheat-shard 30\nyaml-oracle 15\nprove 10\ngate 30\nscorecard-comment 5'
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
grep -q 'cheat-partition.sh' "$work/prove" && fail "prove still runs the shell script"
grep -Eq 'lake |elan |LD_LIBRARY_PATH|\bldd\b' "$work/prove" && fail "prove builds or packs Lean"
grep -q 'gate-bin/mitos-gate cheats aggregate' "$work/prove" || fail "prove does not run the aggregate"
ok "gate cannot be skipped, and prove runs the uploaded binary"

awk '
  /^  cheat-shard:$/ { s = 1; next }
  /^  [a-z0-9-]+:$/ { s = 0 }
  s { print }
' "$wf" >"$work/shard"
grep -q 'if: always()' "$work/shard" || fail "a shard upload does not keep if: always()"
grep -q 'Cheat corpus is rejected' "$work/shard" && fail "a shard step is named like the corpus step"
ok "shard logs upload on a red run and no shard step wears the corpus name"

grep -q 'would be empty, and mitos-gate cheats with no names runs the whole corpus' \
  "$root/gate/MitosGate/CheatsShard.lean" || fail "the empty-shard refusal is not in Lean"
ok "the empty-shard refusal is the Lean sentence"

echo "cheat-shard: done"
