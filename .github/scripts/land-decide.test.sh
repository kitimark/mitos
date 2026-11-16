#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/land-decide.sh
wf=$root/.github/workflows/land.yml
source "$root/.github/scripts/land-workflow.lib.sh"
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
  printf '%s\n' "$STUB_MERGE_READS" >"$3/comments-153.json"
  echo '[[]]' >"$3/review-comments-153.json"
  echo '[[]]' >"$3/reviews-153.json"
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
start
"$real" land-answers "$tmp/queue.json" >"$tmp/answers.json"
marker=$(sed -n "s/^marker='\(.*\)'$/\1/p" "$root/.github/scripts/land-report.sh")
jq -e --arg m "$marker" 'all(.answers[]; .body | startswith($m + "\n"))' "$tmp/answers.json" >/dev/null \
  || note "the marker differs"
finish the-marker-is-the-reports

decide_wf=$tmp/decide.yml
job_block "$wf" decide >"$decide_wf"
if_block=$(awk '/^    if: >-$/ { on = 1; next } on && /^    [a-z]/ { exit } on { print }' "$decide_wf")
perm_block=$(awk '/^    permissions:$/ { on = 1; next } on && !/^      / { exit } on { print }' "$decide_wf")
joined=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$script")

start
grep -qx 'permissions: {}' "$wf" || note "land.yml has no top-level permissions: {}"
[ "$(grep -cE '^[[:space:]]*permissions:' "$decide_wf")" = 1 ] || note "decide has another permissions block"
[ -n "$perm_block" ] || note "the decide job has no permissions block"
while IFS= read -r l; do
  [[ $l =~ ^\ {6}[a-z-]+:\ read$ ]] || note "a permission that is not read: [$l]"
done <<<"$perm_block"
! grep -nE 'write|secrets\.|^[[:space:]]*environment:|github-app-token|app-id|private-key|id-token' "$decide_wf" \
  || note "land.yml names a write, a secret, an environment or an app token"
if [ "$(grep -c 'github.token' "$decide_wf")" != 1 ] || ! grep -qxF '          GH_TOKEN: ${{ github.token }}' "$decide_wf"; then
  note "land.yml uses the workflow token other than as GH_TOKEN of the decide step"
fi
grep -qx '          persist-credentials: false' "$decide_wf" || note "checkout keeps the token in the clone"
uses=$(grep -oE 'uses: [^ ]+' "$decide_wf" | sort -u | tr '\n' ' ')
[ "$uses" = "uses: actions/cache/restore@v4 uses: actions/checkout@v4 uses: actions/upload-artifact@v4 " ] \
  || note "land.yml uses another action: $uses"
runs=$(grep -E '^[[:space:]]*(- )?run:' "$decide_wf" | sed -E 's/^[[:space:]]*(- )?run: //')
want_runs='echo "at=$(date +%s)" >> "$GITHUB_OUTPUT"
.github/scripts/install-elan.sh
.github/scripts/install-toolchains.sh
lake build mitos-gate
.github/scripts/land-decide.sh "$GITHUB_REPOSITORY" "$LAND_DASHBOARD" "$RUNNER_TEMP/land"'
[ "$runs" = "$want_runs" ] || note "land.yml runs other commands:" "$runs"
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
! grep -qw gh "$wf" || note "land.yml calls gh itself"
bad_calls=$(grep -vxE 'api rate_limit --jq \.resources\.core\.remaining|api repos/owner/mitos/branches/main --jq \.commit\.sha' "$calls")
[ -z "$bad_calls" ] || note "the stub gh saw other calls:" "$bad_calls"
[ -s "$calls" ] || note "the stub gh saw no call"
finish holds-no-key

outputs_are_data() {
  awk '
    BEGIN { scope = block = value_indent = -1 }
    /^[[:space:]]*$/ { next }
    {
      match($0, /[^ ]/); indent = RSTART - 1
      if (/^[[:space:]]*#/ && (block < 0 || indent <= block) &&
          (value_indent < 0 || indent <= value_indent)) next
      if (indent <= scope) scope = -1
      if (indent <= block) block = -1
      if (indent <= value_indent) { value = ""; value_indent = indent }
      if (block < 0) {
        if (/^ *(- )?[a-zA-Z0-9_-]+:/) { value = ""; value_indent = indent }
        if (indent == 0) jobs = /^jobs:$/
        if (indent < 2) job = 0
        if (jobs && /^  [a-zA-Z0-9_-]+:$/) job = 1
        if (indent <= 4) steps = /^    steps:$/
        if (/^env:$/ || (job && /^    env:$/) || (steps && /^        env:$/) ||
            (job && /^    if:/)) scope = indent
        if (/:[[:space:]]*[|>][0-9+-]*([[:space:]]+#.*)?[[:space:]]*$/) block = indent
      }
      compact = tolower($0); gsub(/[[:space:]]/, "", compact); value = value compact
      if (value ~ /needs([.]|\[).*outputs/ && scope < 0) {
        print NR ":" $0; bad = 1
      }
    }
    END { exit bad }
  ' "$1"
}

start
for pin in "github.ref == 'refs/heads/main'" \
  "github.event.workflow_run.event == 'pull_request'" \
  "github.event.workflow_run.head_repository.full_name == github.repository" \
  "github.event.issue.pull_request" \
  "github.event.comment.user.login == github.repository_owner"; do
  grep -qF -- "$pin" <<<"$if_block" || note "the decide job's if: does not name [$pin]"
done
! grep -qE '^concurrency:' "$wf" || note "land.yml has a workflow-level concurrency group"
awk '/^    concurrency:$/ { c = NR } c && NR == c + 1 && /^      group: land-decide$/ { g = NR }
  g && NR == g + 1 && /^      cancel-in-progress: false$/ { ok = 1 } END { exit !ok }' "$decide_wf" \
  || note "the decide job has no concurrency group land-decide that keeps a running run"
! grep -nE '^[[:space:]]*(- )?run:.*\$\{\{' "$wf" || note "a run: line holds an expression"
! grep -nE '^[[:space:]]*(- )?run:[[:space:]]*[|>]' "$wf" || note "a run: block spans lines"
while IFS= read -r l; do
  [[ $l =~ ^\ {10}LAND_EVENT_[A-Z]+:\ \$\{\{\ github\.event\.[a-z_.]+\ \}\}$ ]] \
    && [ "$(grep -cxF -- "$l" "$wf")" = "$(grep -cxF -- "$l" "$decide_wf")" ] \
    || note "event text outside the decide step's env: [$l]"
done < <(grep -F '${{' "$wf" | grep -F 'github.event.')
outputs_are_data "$wf" || note "needs outputs outside env values or job if conditions"
finish filter-pins

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
outputs_are_data "$tmp/output-scopes.yml" || note "env values or a multiline job if were refused"
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
  cat "$tmp/output-scopes.yml" >"$tmp/output-unsafe.yml"
  printf '%s\n' "$snippet" >>"$tmp/output-unsafe.yml"
  scope_code=0
  outputs_are_data "$tmp/output-unsafe.yml" >"$tmp/output-scope.err" || scope_code=$?
  [ "$scope_code" = 1 ] || note "unsafe output scope was accepted or scanner failed: $snippet"
done
finish output-scope-fixtures

start
reads=$(grep -cE 'gh api' <<<"$joined")
timed=$(grep -cE 'timeout -k 5 120 gh api' <<<"$joined")
[ "$reads" -ge 2 ] && [ "$reads" = "$timed" ] || note "$timed of $reads gh api calls run under timeout -k 5 120"
grep -qE '^for tool in .*\btimeout\b' "$script" || note "land-decide.sh does not check for timeout"
finish every-read-has-a-timeout

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
