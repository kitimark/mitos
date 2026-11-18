#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/land-decide.sh
wf=$root/.github/workflows/land.yml
queue=$root/gate/land-fixtures/queue.json
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is not installed"; exit 1; }
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
real=$root/.lake/build/bin/mitos-gate
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() {
  echo "FAIL $1"
  shift
  for l in "$@"; do echo "  | $l"; done
  fail=$((fail + 1))
}

clone=$tmp/clone
g() { git -C "$clone" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$clone"
g init -q -b main
echo one >"$clone/a.txt"
g add -A
g commit -qm M1
m1=$(g rev-parse HEAD)
echo two >"$clone/a.txt"
g commit -qam R1
r1=$(g rev-parse HEAD)
r1tree=$(g rev-parse 'HEAD^{tree}')
g checkout -q --detach "$m1"
moved=2222222222222222222222222222222222222222
absent=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[ $# = 4 ] && [ "$1" = api ] && [ "$3" = --jq ] || { echo "stub gh: unexpected call" >&2; exit 64; }
case "$2 $4" in
  "rate_limit .resources.core.remaining")
    [ -z "${STUB_BLOCK:-}" ] || mkdir -p -- "$STUB_BLOCK"
    if [ -n "${STUB_RATE_FAIL:-}" ]; then echo "gh: rate read failed" >&2; exit 1; fi
    echo "${STUB_LEFT:-5000}" ;;
  "repos/owner/mitos/branches/main .commit.sha")
    case ${STUB_AFTER:-same} in
      same) echo "$STUB_MAIN" ;;
      fail) echo '{"message":"Branch not found","status":"404"}'; echo 'gh: Branch not found (HTTP 404)' >&2; exit 1 ;;
      junk) echo 'not a commit' ;;
      *) echo "$STUB_AFTER" ;;
    esac ;;
  *) echo "stub gh: unexpected call" >&2; exit 64 ;;
esac
EOF
cat >"$tmp/fetch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_FETCH_ARGS"
[ $# = 3 ] && mkdir -p -- "$3" || exit 2
echo '{"full_name":"owner/mitos","owner":{"login":"owner"}}' >"$3/repo.json"
[ -n "${STUB_NO_MAIN:-}" ] || jq -n --arg s "$STUB_MAIN" '{commit: {sha: $s}}' >"$3/main.json"
[ -z "${STUB_FETCH_ERR:-}" ] || printf '%s\n' "$STUB_FETCH_ERR" >&2
if [ -n "${STUB_MERGE_READS:-}" ]; then
  for read_pr in 153 "${STUB_EXTRA_READ_PR:-153}"; do
    printf '%s\n' "$STUB_MERGE_READS" >"$3/comments-$read_pr.json"
    echo '[[]]' >"$3/review-comments-$read_pr.json"
    echo '[[]]' >"$3/reviews-$read_pr.json"
  done
fi
exit "${STUB_FETCH_CODE:-0}"
EOF
cat >"$tmp/gate" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  snapshot)
    if [ "$STUB_SNAPSHOT" = fail ]; then
      echo "snapshot: the list of open pull requests is not of its route's shape" >&2
      exit 1
    fi
    if [ "$STUB_SNAPSHOT" = needs-main ] && [ ! -f "$2/main.json" ]; then
      echo "snapshot: the read of main is missing or not JSON" >&2
      exit 1
    fi
    cat "$STUB_SNAPSHOT_FILE"
    [ -z "${STUB_NOTES:-}" ] || printf '%s\n' "$STUB_NOTES" >&2 ;;
  land) shift; exec "$REAL_GATE" land "$@" ;;
  land-answers)
    [ -z "${STUB_ANSWERS:-}" ] || { cat "$STUB_ANSWERS"; exit; }
    shift; exec "$REAL_GATE" land-answers "$@" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$tmp/bin/gh" "$tmp/fetch" "$tmp/gate"

jq -c '{prs}' "$queue" >"$tmp/queue.json"
want_queue=$("$real" land "$tmp/queue.json") || { echo "FAIL mitos-gate land on the fixture"; exit 1; }
jq -c --arg r "$r1" --arg x "$absent" '{prs}
  | .prs[0].base.replay = $r | .prs[0].ids[1].sha = $r
  | .prs[1].base.replay = $x | .prs[1].ids[1].sha = $x' "$queue" >"$tmp/push.json"
jq -c '{prs: [{pr: 1}]}' -n >"$tmp/bad-snapshot.json"

calls=$tmp/calls.log
: >"$calls"
run() {
  local name=$1
  shift
  dir=$tmp/runs/$name
  rm -rf "$dir"
  mkdir -p "$dir"
  rec=$dir/out/record.json
  code=0
  (cd "$clone" && env -u LAND_EVENT -u LAND_EVENT_HEAD -u LAND_EVENT_CONCLUSION -u LAND_EVENT_PR \
    -u LAND_EVENT_COMMENT -u LAND_T0 -u LAND_REST_FLOOR -u MITOS_GATE -u SNAPSHOT_FETCH \
    PATH="$tmp/bin:$PATH" LAND_DIGEST_SCRIPT="$root/.github/scripts/land-digest.sh" MITOS_GATE="$tmp/gate" SNAPSHOT_FETCH="$tmp/fetch" REAL_GATE="$real" \
    STUB_LOG="$dir/gh.log" STUB_FETCH_ARGS="$dir/fetch.args" STUB_MAIN="$m1" \
    GITHUB_OUTPUT="$dir/outputs" STUB_SNAPSHOT=file STUB_SNAPSHOT_FILE="$tmp/queue.json" "$@" \
    "$script" owner/mitos 43 "$dir/out") >"$dir/stdout" 2>"$dir/stderr" || code=$?
  [ ! -f "$dir/gh.log" ] || cat "$dir/gh.log" >>"$calls"
}

problems=()
start() { problems=(); }
note() { problems+=("$@"); }
finish() { if [ ${#problems[@]} = 0 ]; then ok "$1"; else bad "$1" "${problems[@]}"; fi; }
exits() { [ "$code" = "$1" ] || note "exit $code, expected $1" "stderr: $(cat "$dir/stderr")"; }
has() {
  local f=$1
  shift
  if [ ! -f "$rec" ]; then note "no record.json"; return; fi
  [ "$(grep -c '' "$rec")" = 1 ] || note "the record is not one line"
  jq -e --arg tool "$m1" "$@" "$f" "$rec" >/dev/null 2>&1 || note "record fails: $f" "record: $(cat "$rec")"
}
full='keys_unsorted == ["v","trigger","read","main","mainAfter","mainAfterSaid","tool","cost","unread","outcome"]
  and .v == 1 and .tool == $tool
  and (.read | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  and (.cost | keys_unsorted == ["setup","fetch","snapshot","decide","reads"]
    and all(.[]; type == "number" and . >= 0))'
decided='.outcome | keys_unsorted == ["kind","snapshot","decision","trees","notes"] and .kind == "decided"'

start
run decided
exits 0
has "$full"
has "$decided"
has '.trigger == {kind: "dispatch"} and .main == $m and .mainAfter == $m and .mainAfterSaid == []
  and .unread == [] and .cost.reads == 2' --arg m "$m1"
has '.outcome.decision == $d and .outcome.snapshot == $s[0] and .outcome.trees == []
  and .outcome.notes == []' --argjson d "$want_queue" --slurpfile s "$tmp/queue.json"
[ "$(cat "$dir/stdout")" = "$want_queue" ] || note "stdout: $(cat "$dir/stdout")" "want:   $want_queue"
[ "$(cat "$dir/fetch.args")" = "$(printf '%s\n' owner/mitos 43 "$dir/out/reads")" ] \
  || note "the fetch got: $(tr '\n' ' ' <"$dir/fetch.args")"
finish decided-on-the-land-fixture

start
run refused-fetch STUB_FETCH_CODE=2 STUB_FETCH_ERR="snapshot-fetch: the folder is not empty"
exits 1
has "$full"
has '.outcome == {kind: "refused", stage: "fetch", said: ["snapshot-fetch: the folder is not empty"]}
  and .unread == ["snapshot-fetch: the folder is not empty"]'
[ ! -e "$dir/out/snapshot.json" ] || note "the snapshot ran after a refused fetch"
grep -qx 'land-decide: refused at fetch' "$dir/stderr" || note "stderr: $(cat "$dir/stderr")"
finish refused-fetch-is-red

start
run refused-snapshot STUB_SNAPSHOT=fail
exits 1
has "$full"
has '.outcome == {kind: "refused", stage: "snapshot",
  said: ["snapshot: the list of open pull requests is not of its route'"'"'s shape"]} and .main == $m' \
  --arg m "$m1"
[ ! -e "$dir/out/decision.json" ] || note "land ran after a refused snapshot"
grep -qx 'land-decide: refused at snapshot' "$dir/stderr" || note "stderr: $(cat "$dir/stderr")"
finish refused-snapshot-is-red

start
run refused-land STUB_SNAPSHOT_FILE="$tmp/bad-snapshot.json"
exits 1
has "$full"
has '.outcome.kind == "refused" and .outcome.stage == "land" and (.outcome.said | length) == 1
  and (.outcome.said[0] | startswith("land: the snapshot is refused: "))'
finish refused-land-is-red

start
run unread-main STUB_NO_MAIN=1 STUB_SNAPSHOT=needs-main \
  STUB_FETCH_ERR="snapshot-fetch: the read of main failed"
exits 1
has "$full"
has '.main == "" and .mainAfter == $m and .unread == ["snapshot-fetch: the read of main failed"]
  and .cost.reads == 1
  and .outcome == {kind: "refused", stage: "snapshot", said: ["snapshot: the read of main is missing or not JSON"]}' \
  --arg m "$m1"
run unread-main-unchecked STUB_NO_MAIN=1
exits 1
has "$full"
has '.main == "" and .outcome == {kind: "refused", stage: "land", said: []}'
finish unread-main-is-red

start
run failed-reads STUB_FETCH_ERR=$'snapshot-fetch: the read of protection failed\nsnapshot-fetch: the read of stacks failed' \
  STUB_NOTES='snapshot: #153 holds: unread protection, stacks'
exits 0
has "$full"
has "$decided"
has '.unread == ["snapshot-fetch: the read of protection failed", "snapshot-fetch: the read of stacks failed"]
  and .outcome.notes == ["snapshot: #153 holds: unread protection, stacks"]'
[ "$(cat "$dir/stdout")" = "$want_queue"$'\n''snapshot: #153 holds: unread protection, stacks' ] \
  || note "stdout: $(cat "$dir/stdout")"
finish failed-reads-pass-through

start
run main-moved STUB_AFTER="$moved"
exits 0
has "$full"
has "$decided"
has '.main == $m and .mainAfter == $x and .mainAfterSaid == []' --arg m "$m1" --arg x "$moved"
finish main-moved-while-reading

start
run main-after-fails STUB_AFTER=fail
exits 0
has "$full"
has "$decided"
has '.main == $m and .mainAfter == ""
  and .mainAfterSaid == ["gh: Branch not found (HTTP 404)", "land-decide: the second read of main exited 1"]' \
  --arg m "$m1"
run main-after-junk STUB_AFTER=junk
exits 0
has "$decided"
has '.mainAfter == "" and .mainAfterSaid == ["land-decide: the second read of main gave no commit"]'
finish failed-second-read-of-main

start
run floor STUB_LEFT=299
exits 0
has 'keys_unsorted == ["v","trigger","read","tool","outcome"] and .v == 1 and .tool == $tool
  and .trigger == {kind: "dispatch"} and .outcome == {kind: "skipped", remaining: 299}'
[ ! -e "$dir/out/reads" ] || note "the fetch ran under the floor"
[ "$(cat "$dir/gh.log")" = "api rate_limit --jq .resources.core.remaining" ] \
  || note "gh calls: $(tr '\n' ';' <"$dir/gh.log")"
grep -qx 'land-decide: skipped, 299 REST calls left' "$dir/stdout" || note "stdout: $(cat "$dir/stdout")"
run at-floor STUB_LEFT=300
exits 0
has "$decided"
run floor-unread STUB_RATE_FAIL=1
exits 0
has "$decided"
run floor-set STUB_LEFT=999 LAND_REST_FLOOR=1000
has '.outcome == {kind: "skipped", remaining: 999}'
finish rate-floor-skips

start
for bad_env in \
  "LAND_EVENT=workflow_run|LAND_EVENT_HEAD=\$(id)|LAND_EVENT_CONCLUSION=success" \
  "LAND_EVENT=workflow_run|LAND_EVENT_HEAD=$r1|LAND_EVENT_CONCLUSION=success; id" \
  "LAND_EVENT=workflow_run|LAND_EVENT_HEAD=$r1|LAND_EVENT_CONCLUSION=" \
  "LAND_EVENT=workflow_run|LAND_EVENT_HEAD=${r1^^}|LAND_EVENT_CONCLUSION=success" \
  "LAND_EVENT=issue_comment|LAND_EVENT_PR=12 |LAND_EVENT_COMMENT=34" \
  "LAND_EVENT=issue_comment|LAND_EVENT_PR=12|LAND_EVENT_COMMENT=34\"}" \
  "LAND_EVENT=issue_comment|LAND_EVENT_PR=012|LAND_EVENT_COMMENT=34" \
  "LAND_EVENT=pull_request_target"; do
  IFS='|' read -r -a vars <<<"$bad_env"
  run bad-event "${vars[@]}"
  exits 2
  [ ! -e "$rec" ] || note "a record for [$bad_env]"
  [ ! -s "$dir/gh.log" ] || note "gh was called for [$bad_env]"
  grep -qx 'land-decide: the trigger is not one this script records' "$dir/stderr" \
    || note "stderr for [$bad_env]: $(cat "$dir/stderr")"
done
finish bad-event-text-is-refused

start
run t-push STUB_LEFT=0 LAND_EVENT=push
has '.trigger == {kind: "mainMoved"}'
run t-run STUB_LEFT=0 LAND_EVENT=workflow_run LAND_EVENT_HEAD="$r1" LAND_EVENT_CONCLUSION=startup_failure
has '.trigger == {kind: "gateDone", head: $h, conclusion: "startup_failure"}' --arg h "$r1"
run t-comment STUB_LEFT=0 LAND_EVENT=issue_comment LAND_EVENT_PR=12 LAND_EVENT_COMMENT=6877066338
has '.trigger == {kind: "comment", pr: 12, id: 6877066338}'
run t-dispatch STUB_LEFT=0 LAND_EVENT=workflow_dispatch
has '.trigger == {kind: "dispatch"}'
finish each-event-has-its-trigger

start
for kind in skipped decided refused; do
  case $kind in
    skipped) more=(STUB_LEFT=0) ;;
    decided) more=() ;;
    refused) more=(STUB_SNAPSHOT=fail) ;;
  esac
  run "unwritten-$kind" STUB_BLOCK="$tmp/runs/unwritten-$kind/out/record.json" "${more[@]}"
  exits 1
  [ -d "$rec" ] || note "$kind: the record path is not the blocking folder"
  grep -qx 'land-decide: the record was not written' "$dir/stderr" \
    || note "$kind: stderr: $(cat "$dir/stderr")"
  [ ! -s "$dir/stdout" ] || [ "$kind" = skipped ] || note "$kind: printed a decision: $(cat "$dir/stdout")"
done
finish an-unwritten-record-is-red

start
run push-plan STUB_SNAPSHOT_FILE="$tmp/push.json"
exits 0
has "$decided"
has '.outcome.decision.plan == {kind: "push", pr: 153, expect: "aaa", replay: $r}
  and .outcome.trees == [{commit: $r, tree: $t}]' --arg r "$r1" --arg t "$r1tree"
finish a-push-plan-records-its-tree

h=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
jq -c --arg h "$h" '{prs:[.prs[0]]} | .prs[0] |= (.head=$h | .base={kind:"current"} |
  .pushes=[] | .ids=[{sha:$h,id:"a"}] | .words[0].about=$h | .botAt=$h |
  .verdicts |= map(.head=$h))' "$queue" >"$tmp/merge.json"
read_comments='[[{"id":450,"user":{"login":"owner"},"created_at":"2026-11-14T08:00:00Z","updated_at":"2026-11-14T08:00:00Z","body":"/land"}]]'
start
run merge-outputs STUB_SNAPSHOT_FILE="$tmp/merge.json" STUB_MERGE_READS="$read_comments"
exits 0
want_answers=$("$real" land-answers "$tmp/merge.json")
digest=$("$root/.github/scripts/land-digest.sh" "$dir/out/reads/comments-153.json" \
  "$dir/out/reads/review-comments-153.json" "$dir/out/reads/reviews-153.json")
[ "$(cat "$dir/outputs")" = "$(printf 'pr=153\nhead=%s\napproval=450\ndigest=%s\nrequires_spec=false\nanswers=%s' \
  "$h" "$digest" "$(jq -c .answers <<<"$want_answers")")" ] || note "outputs: $(cat "$dir/outputs")"
finish decide-outputs-on-a-merge-plan
start
jq -cn --arg h "$h" '{merge:{pr:999,head:$h,approval:450,requiresSpec:false},answers:[]}' >"$tmp/wrong-pr.json"
run wrong-pr STUB_SNAPSHOT_FILE="$tmp/merge.json" STUB_MERGE_READS="$read_comments" STUB_EXTRA_READ_PR=999 STUB_ANSWERS="$tmp/wrong-pr.json"
exits 1
[ ! -s "$dir/outputs" ] || note "wrong PR wrote outputs"
finish merge-with-wrong-pr-is-refused
start
jq -cn --arg h "$absent" '{merge:{pr:153,head:$h,approval:450,requiresSpec:false},answers:[]}' >"$tmp/wrong-head.json"
run wrong-head STUB_SNAPSHOT_FILE="$tmp/merge.json" STUB_MERGE_READS="$read_comments" STUB_ANSWERS="$tmp/wrong-head.json"
exits 1
[ ! -s "$dir/outputs" ] || note "wrong head wrote outputs"
finish merge-with-wrong-head-is-refused
start
for file in "$tmp/queue.json" "$tmp/push.json"; do
  run no-merge STUB_SNAPSHOT_FILE="$file"
  exits 0
  if grep -qx 'pr=' "$dir/outputs" && grep -qx 'head=' "$dir/outputs" && grep -qx 'approval=' "$dir/outputs" \
    && grep -qx 'digest=' "$dir/outputs" && grep -qx 'requires_spec=' "$dir/outputs" \
    && grep -q '^answers=\[' "$dir/outputs"; then :
  else note "nonmerge handoff: $(cat "$dir/outputs")"; fi
done
finish no-merge-hands-nothing-to-apply
start
echo '{"merge":{"pr":999,"head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","approval":450,"requiresSpec":false},"answers":[]}' >"$tmp/wrong.json"
run disagree STUB_ANSWERS="$tmp/wrong.json"
exits 1
[ ! -s "$dir/outputs" ] || note "disagreement wrote outputs"
echo '{"answers":[]}' >"$tmp/wrong.json"
run missing STUB_ANSWERS="$tmp/wrong.json"
exits 1
[ ! -s "$dir/outputs" ] || note "missing key wrote outputs"
finish land-and-land-answers-disagree-is-refused
start
run missing-reads STUB_SNAPSHOT_FILE="$tmp/merge.json"
exits 1
has "$decided"
[ ! -s "$dir/outputs" ] || note "missing reads wrote outputs"
finish a-merge-without-its-reads-is-not-handed-on
start
jq -n '{merge:null,answers:[{pr:1,line:("x" * 65537),body:"x"}]}' >"$tmp/large.json"
run answer-cap STUB_ANSWERS="$tmp/large.json" STUB_SNAPSHOT_FILE="$tmp/push.json"
exits 1
has "$decided"
[ ! -s "$dir/outputs" ] || note "large answers wrote outputs"
finish answers-over-the-cap-are-refused
for answer_count in 100 101; do
  start
  count_marker=$(sed -n "s/^marker='\(.*\)'$/\1/p" "$root/.github/scripts/land-report.sh")
  [ -n "$count_marker" ] || note "the report marker is missing"
  jq -cn --arg h "$h" --arg m "$count_marker" --argjson n "$answer_count" \
    '{merge:{pr:153,head:$h,approval:450,requiresSpec:false},
      answers:[range(1; $n + 1) | {pr:.,line:"answer",body:($m + "\nanswer")}]}' \
    >"$tmp/answers-$answer_count.json"
  [ "$(wc -c <"$tmp/answers-$answer_count.json")" -lt 65536 ] || note "count fixture exceeds the byte cap"
  run "answer-count-$answer_count" STUB_SNAPSHOT_FILE="$tmp/merge.json" STUB_MERGE_READS="$read_comments" \
    STUB_ANSWERS="$tmp/answers-$answer_count.json"
  has "$decided"
  if [ "$answer_count" = 100 ]; then
    exits 0
    sed -n 's/^answers=//p' "$dir/outputs" | jq -e 'length == 100' >/dev/null \
      || note "the valid 100-answer list was not handed on"
    finish answers-at-the-count-cap-are-handed-on
  else
    exits 1
    [ ! -s "$dir/outputs" ] || note "101 answers wrote outputs"
    finish answers-over-the-count-cap-are-refused
  fi
done
start
"$real" land-answers "$tmp/queue.json" >"$tmp/answers.json"
marker=$(sed -n "s/^marker='\(.*\)'$/\1/p" "$root/.github/scripts/land-report.sh")
marker_matches='$m != "" and (.answers | length > 0) and all(.answers[]; .body | startswith($m + "\n"))'
jq -e --arg m "$marker" "$marker_matches" "$tmp/answers.json" >/dev/null \
  || note "the marker differs"
! jq -e --arg m '' "$marker_matches" "$tmp/answers.json" >/dev/null || note "an empty marker passed"
printf '{"answers":[]}\n' >"$tmp/empty-answers.json"
! jq -e --arg m "$marker" "$marker_matches" "$tmp/empty-answers.json" >/dev/null || note "empty answers passed"
finish the-marker-is-the-reports

joined=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$script")

start
"$real" workflow pins "$root" || note "decoded workflow authority pins were refused"
gh_lines=$(grep -wE 'gh' <<<"$joined" | grep -vE '^for tool in ')
[ "$(grep -c '' <<<"$gh_lines")" = 2 ] || note "land-decide.sh does not make exactly two gh calls"
while IFS= read -r l; do
  grep -qF -e 'gh api rate_limit --jq .resources.core.remaining ' \
    -e 'gh api "repos/$repo/branches/main" --jq .commit.sha ' <<<"$l" \
    || note "a gh call that is not one of the two reads: [$l]"
  ! grep -qE -- '(^|[[:space:]])(-X|-f|-F|--method|--field|--raw-field|--input)([[:space:]=]|$)' <<<"$l" \
    || note "a gh call with a write flag: [$l]"
done <<<"$gh_lines"
! grep -nwE 'curl|wget' "$script" || note "land-decide.sh names curl or wget"
! grep -wE 'git' <<<"$joined" | grep -vE '^for tool in |git rev-parse --verify --quiet ' \
  || note "land-decide.sh runs git other than rev-parse"
bad_calls=$(grep -vxE 'api rate_limit --jq \.resources\.core\.remaining|api repos/owner/mitos/branches/main --jq \.commit\.sha' "$calls")
[ -z "$bad_calls" ] || note "the stub gh saw other calls:" "$bad_calls"
[ -s "$calls" ] || note "the stub gh saw no call"
finish holds-no-key


placement_refused() {
  local name=$1 file=$2 reason=$3 line=${4:-} status=0
  "$real" workflow placement "$file" >"$tmp/placement.out" 2>"$tmp/placement.err" || status=$?
  [ "$status" = 1 ] || note "$name: exit $status, expected 1"
  [ ! -s "$tmp/placement.out" ] || note "$name: unexpected stdout"
  grep -qF -- "$reason" "$tmp/placement.err" || note "$name: wrong refusal: $(cat "$tmp/placement.err")"
  if [ -n "$line" ]; then
    grep -qF -- "$file:$line: refused" "$tmp/placement.err" \
      || note "$name: wrong source line: $(cat "$tmp/placement.err")"
  fi
}


start
"$real" workflow placement "$wf" || note "workflow placement was refused"
finish filter-pins

base_lines=$(wc -l <"$wf")

start
cat >"$tmp/output-scopes.yml" <<'YAML'
env:
  INPUT: ${{ needs.decide.outputs.head }}
jobs:
  check:
    if: >-
      needs.decide.outputs.pr != ''
    env:
      INPUT: ${{ needs.decide.outputs.head }}
    steps:
      - name: Pass outputs as data
        env:
          INPUT: >-
            ${{ needs.decide.outputs.head }}
        run: check
YAML
"$real" workflow placement "$tmp/output-scopes.yml" || note "env values or a multiline job if were refused"
scope_fixture=0
for snippet in \
  '        name: ${{ needs.decide.outputs.pr }}' \
  "        if: needs.decide.outputs.pr != ''" \
  '        with:
          script: |
            console.log("${{ needs.decide.outputs.answers }}");' \
  '        with:
          script: |
            console.log("${{ needs .decide.outputs.head }}");' \
  '        with:
          script: |
            console.log("${{ needs.decide
              .outputs.head }}");' \
  '        name: >-
          ${{ needs.decide
            .outputs.pr }}' \
  '        name: |-
          # ${{ needs.decide.outputs.head }}' \
  '        name: |2- # name
          # ${{ needs.decide.outputs.head }}' \
  '        name: "Prefix
          # ${{ needs.decide.outputs.head }}"' \
  "        name: \${{ Needs [ 'decide' ] .Outputs.head }}" \
  '        with:
          script: |
            const text = `
              env:
                INPUT: ${{ needs.decide.outputs.head }}
            `;'; do
  cat "$wf" >"$tmp/output-unsafe.yml"
  printf '\n  placement-fixture:\n    steps:\n      - run: check\n%s\n' "$snippet" >>"$tmp/output-unsafe.yml"
  scope_fixture=$((scope_fixture + 1))
  reason='rule N'
  relative=5
  case $scope_fixture in
    3 | 4 | 5 | 11) relative=6 ;;
    8) reason='block indentation indicator' ;;
  esac
  placement_refused "output-scope-$scope_fixture" "$tmp/output-unsafe.yml" "$reason" "$((base_lines + relative))"
done
[ "$scope_fixture" = 11 ] || note "expected 11 original output-scope fixtures"
finish output-scope-fixtures

start
cat >"$tmp/quoted-safe.yml" <<'YAML'
jobs:
  check:
    if: "needs.decide.outputs.pr != ''"
    env:
      INPUT: '${{ needs.decide.outputs.head }}'
    steps:
      - run: echo "shell quotes"
      - run: echo , "unfinished
      - name: Keep { "quote
        run: echo 'a [ "b'
      - run: "echo \"shell\"" # "unclosed comment
      - run: 'echo ''shell'''
      - env:
          INPUT: |
            "unclosed block text
        with:
          script: |
            const text = "unclosed block text
YAML
"$real" workflow placement "$tmp/quoted-safe.yml" || note "single-line quotes or quotes in plain/block scalars were refused"
quoted_fixture=0
: >"$tmp/quoted-unsafe.yml"
while IFS= read -r line; do
  if [ "$line" = --- ]; then
    quoted_fixture=$((quoted_fixture + 1))
    cat "$wf" >"$tmp/quoted-mutation.yml"
    if [ "$quoted_fixture" = 12 ]; then
      printf '\n  placement-fixture:\n    env:\n' >>"$tmp/quoted-mutation.yml"
      sed '1d; s/^/    /' "$tmp/quoted-unsafe.yml" >>"$tmp/quoted-mutation.yml"
    else
      printf '\n  placement-fixture:\n' >>"$tmp/quoted-mutation.yml"
      tail -n +3 "$tmp/quoted-unsafe.yml" >>"$tmp/quoted-mutation.yml"
    fi
    if [ "$quoted_fixture" = 12 ]; then
      "$real" workflow placement "$tmp/quoted-mutation.yml" || note "multiline quoted environment data was refused"
      if ! "$real" workflow leaves "$tmp/quoted-mutation.yml" >"$tmp/quoted-leaves.jsonl"; then
        note "multiline quoted environment data could not be decoded"
      elif ! jq -se 'any(.[]; .path == ["jobs","placement-fixture","env","INPUT"] and .value == "two lines")' \
          "$tmp/quoted-leaves.jsonl" >/dev/null; then
        note "multiline quoted environment data is not at the intended environment path"
      fi
    elif [ "$quoted_fixture" = 13 ]; then
      placement_refused quoted-env-code "$tmp/quoted-mutation.yml" 'rule X' "$((base_lines + 7))"
    elif [ "$quoted_fixture" = 6 ]; then
      placement_refused quoted-flow-run "$tmp/quoted-mutation.yml" 'unsupported flow collection'
    else
      quote=double
      relative=4
      case $quoted_fixture in
        2 | 5) quote=single ;;
        3) relative=8 ;;
        7 | 9 | 10) relative=5 ;;
      esac
      placement_refused "quoted-$quoted_fixture" "$tmp/quoted-mutation.yml" \
        "parse: under-indented continuation line in $quote-quoted scalar at line $((base_lines + relative))"
    fi
    : >"$tmp/quoted-unsafe.yml"
  else
    printf '%s\n' "$line" >>"$tmp/quoted-unsafe.yml"
  fi
done <<'YAML'
jobs:
  check:
    steps:
      - run: "echo
        env:
          ${{ needs.decide.outputs.answers }}"
---
jobs:
  check:
    steps:
      - run: 'echo
        env:
          ${{ needs.decide.outputs.answers }}'
---
jobs:
  check:
    permissions:
      pull-requests: write
    steps:
      - uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b
        with:
          script: "console.log(`
        env:
          ${{ needs.decide.outputs.answers }}`);"
---
jobs:
  check:
    steps:
      - run: "echo \"quoted\"
        env:
          ${{ needs.decide.outputs.answers }}"
---
jobs:
  check:
    steps:
      - run: 'echo ''quoted''
        env:
          ${{ needs.decide.outputs.answers }}'
---
jobs:
  check:
    steps:
      - {run: "echo
        env:
          ${{ needs.decide.outputs.answers }}"}
---
jobs:
  check:
    steps:
      - uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b
        with: {script: "console.log(`
        env:
          ${{ needs.decide.outputs.answers }}`);"}
---
jobs:
  check:
    steps:
      - run: !!str "echo
        env:
          ${{ needs.decide.outputs.answers }}"
---
jobs:
  check:
    steps:
      - run:
          "echo
        env:
          ${{ needs.decide.outputs.answers }}"
---
jobs:
  check:
    steps:
      - ? run
        : "echo
        env:
          ${{ needs.decide.outputs.answers }}"
---
jobs:
  check:
    steps:
      - "r\u0075n": "echo
        env:
          ${{ needs.decide.outputs.answers }}"
---
env:
  INPUT: "two
    lines"
---
jobs:
  check:
    env:
      INPUT: "two
        lines"
    steps:
      - run: "${{ env.INPUT }}"
---
YAML
[ "$quoted_fixture" = 13 ] || note "expected 12 original quoted fixtures and one paired code-site refusal"
finish quoted-scalar-fixtures


start
while IFS='|' read -r name reason relative; do
  snippet=''
  while IFS= read -r line && [ "$line" != --- ]; do snippet+="$line"$'\n'; done
  cat "$wf" >"$tmp/placement-mutation.yml"
  printf '\n  placement-fixture:\n    steps:\n%s' "$snippet" >>"$tmp/placement-mutation.yml"
  placement_refused "$name" "$tmp/placement-mutation.yml" "$reason" "$((base_lines + relative))"
done <<'YAML'
shape-a|rule N|5
      # x: |
      - run: echo ${{ needs.d.outputs.p }}
---
shape-b|rule N|6
      - name: |
          step
        run: echo ${{ needs.d.outputs.p }}
---
shape-d|rule N|4
      - run: "${{ \x6eeeds.d.outputs.p }}"
---
shape-d2|expression count differs|4
      - run: "\x24{{ needs.d.outputs.p }}"
---
shape-e|rule X|6
      - env:
          X: ${{ needs.d.outputs.p }}
        run: echo ${{ env.X }}
---
alias|alias|4
      - run: *answers
---
to-json|rule N|4
      - name: ${{ toJSON(needs) }}
---
from-json|rule N|4
      - run: echo ${{ fromJSON(toJSON(needs)).decide.outputs.answers }}
---
computed-member|rule N|4
      - run: echo ${{ needs.decide[format('{0}puts','out')].answers }}
---
hash-content|rule N|4
      - run: echo a#${{ needs.d.outputs.p }}
---
script-indirection|rule X|7
      - env:
          X: ${{ needs.d.outputs.p }}
        with:
          script: ${{ env.X }}
---
multiline-plain-code|rule X|4
      - run: echo ${{ env.X }}
          [literal
      - run: echo , "unfinished
---
YAML
cat "$wf" >"$tmp/placement-mutation.yml"
printf '\n  placement-fixture:\n    steps:\n      - run: echo ok\rneeds.x\n' >>"$tmp/placement-mutation.yml"
placement_refused shape-c "$tmp/placement-mutation.yml" 'character U+000D outside LF and printable ASCII' "$((base_lines + 4))"
cat "$wf" >"$tmp/placement-mutation.yml"
printf '\n  placement-fixture:\n    env:\n      X: &answers ${{ needs.decide.outputs.answers }}\n    steps:\n      - run: *answers\n' >>"$tmp/placement-mutation.yml"
placement_refused env-anchor-alias "$tmp/placement-mutation.yml" 'anchor'
cat "$wf" >"$tmp/placement-mutation.yml"
printf '\n  placement-fixture:\n    steps:\n      - run: echo\n          [literal\n      - run: echo , "unfinished\n' >>"$tmp/placement-mutation.yml"
"$real" workflow placement "$tmp/placement-mutation.yml" || note "valid multiline plain shell data was refused"
finish decoded-placement-mutations

start
reads=$(grep -cE 'gh api' <<<"$joined")
timed=$(grep -cE 'timeout -k 5 120 gh api' <<<"$joined")
[ "$reads" -ge 2 ] && [ "$reads" = "$timed" ] || note "$timed of $reads gh api calls run under timeout -k 5 120"
grep -qE '^for tool in .*\btimeout\b' "$script" || note "land-decide.sh does not check for timeout"
finish every-read-has-a-timeout

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
