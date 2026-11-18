#!/usr/bin/env bash
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
wf=$root/.github/workflows/ci.yml
old=$root/.github/scripts/cheat-partition.sh

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for job in checks gate-tests cheat-shard; do
  awk -v target="$job:" '
    /^  [a-z0-9-]+:$/ { inside = ($1 == target) }
    inside { print }
  ' "$wf" >"$work/$job"
done

[ ! -e "$old" ] || fail "cheat-partition.sh is still in the tree"
ok "the shell partition script is gone"

grep -q 'shard: \[0, 1, 2\]' "$work/cheat-shard" || fail "workflow matrix is not 0, 1, 2"
grep -q -- '--shard "${{ matrix.shard }}/3"' "$work/cheat-shard" || fail "a shard does not call mitos-gate cheats --shard"
grep -q 'mapfile' "$work/cheat-shard" && fail "the shard step still builds a bash name array"
grep -q 'cheat-partition.sh' "$wf" && fail "ci.yml still calls cheat-partition.sh"
grep -q 'status=$?' "$work/cheat-shard" || fail "the shard step does not keep the exit status"
grep -q 'shard-cases is empty' "$work/cheat-shard" || fail "an empty shard-cases file would not fail the shard"
grep -q 'cat .lake/cheats/table.txt' "$work/cheat-shard" || fail "a red shard does not print its table"
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


awk '
  /^  [a-z0-9-]+:$/ { job = $1; gsub(":", "", job) }
  /^    timeout-minutes:/ { print job, $2 }
' "$wf" >"$work/timeouts"
expect=$'cancel-superseded 5\nchecks 20\ngate-tests 20\ncheat-shard 30\nprove 10\ngate 30\nscorecard-comment 5'
[ "$(cat "$work/timeouts")" = "$expect" ] || fail "timeouts are [$(cat "$work/timeouts")]"
awk '
  /^jobs:$/ { jobs = 1; next }
  jobs && /^  [^[:space:]#]/ { sub(/:$/, "", $1); print $1 }
' "$wf" >"$work/jobs"
printf '%s\n' "$expect" | cut -d ' ' -f 1 >"$work/expected-jobs"
cmp -s "$work/jobs" "$work/expected-jobs" || fail "CI job list differs from the pinned jobs"
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
[ "$(grep '^    needs:' "$work/prove")" = '    needs: [checks, gate-tests, cheat-shard]' ] \
  || fail "prove must need exactly checks, gate-tests and cheat-shard"
grep -qFx '      always() &&' "$work/prove" \
  || fail "prove does not run after a failed, cancelled or skipped dependency"
grep -qFx '          CHECKS: ${{ needs.checks.result }}' "$work/prove" \
  || fail "prove does not pass the checks result"
grep -qFx '          SHARDS: ${{ needs.cheat-shard.result }}' "$work/prove" \
  || fail "prove does not pass the cheat-shard result"
grep -qF -- '--checks "$CHECKS" --shards "$SHARDS" --merged merged' "$work/prove" \
  || fail "prove does not give both job results to the aggregate"
grep -qFx '          GATE_TESTS: ${{ needs.gate-tests.result }}' "$work/prove" \
  || fail "prove does not pass the gate-tests result"
grep -qFx '          python3 -I .github/scripts/gate-tests.py verify --job "$GATE_TESTS" --shards 3 '"\\" "$work/prove" \
  || fail "prove does not validate the gate-tests records"
grep -qFx '            gate-test-logs/gate-tests-0 gate-test-logs/gate-tests-1 gate-test-logs/gate-tests-2' "$work/prove" \
  || fail "prove does not validate all three gate-tests artifacts"
grep -qFx '          pattern: gate-tests-*' "$work/prove" \
  || fail "prove does not download the gate-tests artifacts"
[ "$(grep -c 'gate-tests.py verify' "$work/prove")" = 1 ] \
  || fail "prove must verify gate-tests exactly once"
[ "$(grep -n 'gate-tests.py verify' "$work/prove" | cut -d: -f1)" -lt \
  "$(grep -n 'gate-bin/mitos-gate cheats aggregate' "$work/prove" | cut -d: -f1)" ] \
  || fail "prove validates gate-tests after aggregation"
ok "prove needs all jobs and validates shell evidence before native aggregation"
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

grep -qFx '        shard: [0, 1, 2]' "$work/gate-tests" || fail "gate-tests matrix changed"
grep -qFx '      fail-fast: false' "$work/gate-tests" || fail "gate-tests stops other workers"
grep -qFx '          fetch-depth: 0' "$work/gate-tests" || fail "gate-tests lost full history"
grep -qFx '      contents: read' "$work/gate-tests" || fail "gate-tests lost contents read"
grep -qFx '        run: lake build' "$work/gate-tests" || fail "gate-tests does not build"
awk '
  /^      - name: Gate suite shard / { inside = 1; next }
  inside && /^      - / { exit }
  inside && NF { print }
' "$work/gate-tests" >"$work/executor"
[ "$(cat "$work/executor")" = '        run: python3 -I .github/scripts/gate-tests.py run --shard "${{ matrix.shard }}/3" --out "$RUNNER_TEMP/gate-tests-${{ matrix.shard }}"' ] \
  || fail "gate-tests executor changed or can skip"
grep -qFx '          name: gate-tests-${{ matrix.shard }}' "$work/gate-tests" \
  || fail "gate-tests artifact identity changed"
grep -qFx '          path: ${{ runner.temp }}/gate-tests-${{ matrix.shard }}' "$work/gate-tests" \
  || fail "gate-tests output can enter the cache"
grep -qFx '        if: always()' "$work/gate-tests" || fail "gate-tests drops failed logs"
grep -qFx '          if-no-files-found: error' "$work/gate-tests" || fail "gate-tests accepts missing logs"
[ "$(grep -c 'gate-tests.test.py' "$work/checks")" = 1 ] \
  || fail "checks does not test the gate-tests protocol exactly once"
grep -q 'for t in gate/\*-test.sh' "$work/checks" && fail "checks still runs the serial suite loop"
grep -q 'continue-on-error:' "$work/gate-tests" && fail "gate-tests hides a failure"
for job in checks gate-tests cheat-shard; do
  sed -n '/^    if: >-$/,/^    runs-on:/p' "$work/$job" >"$work/$job-condition"
done
cmp -s "$work/checks-condition" "$work/gate-tests-condition" || fail "gate-tests event rule differs"
cmp -s "$work/checks-condition" "$work/cheat-shard-condition" || fail "cheat-shard event rule differs"
ok "gate-tests isolated execution, artifacts and event rules are pinned"

grep -q 'would be empty, and mitos-gate cheats with no names runs the whole corpus' \
  "$root/gate/MitosGate/CheatsShard.lean" || fail "the empty-shard refusal is not in Lean"
ok "the empty-shard refusal is the Lean sentence"

echo "cheat-shard: done"
