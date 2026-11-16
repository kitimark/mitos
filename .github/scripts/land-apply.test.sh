#!/usr/bin/env bash
# shellcheck disable=SC2016
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/land-apply.sh
digester=$root/.github/scripts/land-digest.sh
wf=$root/.github/workflows/land.yml
# shellcheck source=.github/scripts/land-workflow.lib.sh
source "$root/.github/scripts/land-workflow.lib.sh"
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is not installed"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() {
  echo "FAIL $1"
  shift
  for line in "$@"; do echo "  | $line"; done
  fail=$((fail + 1))
}
problems=()
start() { problems=(); }
note() { problems+=("$@"); }
finish() { if [ ${#problems[@]} = 0 ]; then ok "$1"; else bad "$1" "${problems[@]}"; fi; }

head=1111111111111111111111111111111111111111
main=2222222222222222222222222222222222222222
mkdir -p "$tmp/bin" "$tmp/seed"
jq -n --arg h "$head" '{number:153,state:"open",draft:false,merged:false,
  head:{sha:$h,repo:{full_name:"owner/mitos"}},base:{ref:"main",repo:{full_name:"owner/mitos"}},
  labels:[{name:"spec-approved"}]}' >"$tmp/seed/pr.json"
jq -n --arg h "$head" '[[{id:450,user:{login:"owner",id:7,type:"User"},
  performed_via_github_app:null,created_at:"2026-11-15T08:00:00Z",updated_at:"2026-11-15T08:00:00Z",
  body:("/land "+$h)},{id:451,user:{login:"github-actions[bot]",id:8,type:"Bot"},
  performed_via_github_app:{slug:"github-actions"},created_at:"2026-11-15T07:00:00Z",
  updated_at:"2026-11-15T07:00:00Z",body:"prior report"}]]' >"$tmp/seed/comments.json"
echo '[[{"id":460,"pull_request_review_id":470,"user":{"login":"reviewer"},"performed_via_github_app":null,"created_at":"2026-11-15T07:00:00Z","updated_at":"2026-11-15T07:00:00Z","body":"review comment"}]]' >"$tmp/seed/review-comments.json"
echo '[[{"id":470,"user":{"login":"reviewer"},"performed_via_github_app":null,"state":"COMMENTED","commit_id":"1111111111111111111111111111111111111111","submitted_at":"2026-11-15T07:00:00Z","body":"review"}]]' >"$tmp/seed/reviews.json"
base_digest=$("$digester" "$tmp/seed/comments.json" "$tmp/seed/review-comments.json" "$tmp/seed/reviews.json") \
  || { echo "FAIL seed digest"; exit 1; }

cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${GH_TOKEN:-}" "$*" >>"$STUB_DIR/calls"
jq -cn --arg token "${GH_TOKEN:-}" --args '{token:$token,args:$ARGS.positional}' -- "$@" >>"$STUB_DIR/requests"
[ "$1" = api ] || exit 64
case "$*" in
  'api repos/owner/mitos/pulls/153')
    route=pr
    if [ -e "$STUB_DIR/put" ]; then
      [ ! -e "$STUB_DIR/read-back" ] || exit 64
      touch "$STUB_DIR/read-back"
      route=after
    fi ;;
  'api --paginate --slurp repos/owner/mitos/issues/153/comments?per_page=100') route=comments ;;
  'api --paginate --slurp repos/owner/mitos/pulls/153/comments?per_page=100') route=review-comments ;;
  'api --paginate --slurp repos/owner/mitos/pulls/153/reviews?per_page=100') route=reviews ;;
  "api -X PUT repos/owner/mitos/pulls/153/merge -f merge_method=rebase -f sha=$STUB_HEAD")
    [ ! -e "$STUB_DIR/put" ] || exit 64
    touch "$STUB_DIR/put"
    for route in pr comments review-comments reviews; do
      [ -e "$STUB_DIR/read-$route" ] || { echo "merge before $route" >&2; exit 64; }
    done
    case ${STUB_MERGE:-merged} in
      merged) jq -cn --arg m "$STUB_MAIN" '{merged:true,sha:$m}' ;;
      unmerged) echo '{"merged":false,"message":"not merged"}' ;;
      malformed) echo '{"merged":true,"sha":"not a commit"}' ;;
      lost) echo 'connection closed' >&2; exit 1 ;;
      *) printf 'gh: refused (HTTP %s)\n' "$STUB_MERGE" >&2; exit 1 ;;
    esac
    exit 0 ;;
  *) echo "unexpected call: $*" >&2; exit 64 ;;
esac
if [ "$route" != after ]; then
  [ ! -e "$STUB_DIR/read-$route" ] || exit 64
  touch "$STUB_DIR/read-$route"
fi
[ "${STUB_FAIL:-}" != "$route" ] || { echo "read failed" >&2; exit 1; }
if [ "${STUB_JUNK:-}" = "$route" ]; then echo 'not JSON'; exit 0; fi
cat "$STUB_DIR/reads/$route.json"
if [ "$route" = reviews ] && [ "${STUB_LATE_HOLD:-}" = 1 ]; then
  jq '.[0] += [.[0][0] | .id=499 | .body="/hold"
    | .created_at="2026-11-15T08:01:00Z" | .updated_at=.created_at]' \
    "$STUB_DIR/reads/comments.json" >"$STUB_DIR/late-hold.json"
  mv "$STUB_DIR/late-hold.json" "$STUB_DIR/reads/comments.json"
fi
STUB
chmod +x "$tmp/bin/gh"

prepare() {
  dir=$tmp/runs/$1
  rm -rf "$dir"
  mkdir -p "$dir/reads"
  cp "$tmp/seed/"*.json "$dir/reads/"
  jq --arg m "$main" '.merged=true | .merge_commit_sha=$m' "$dir/reads/pr.json" >"$dir/reads/after.json"
  : >"$dir/calls"
  : >"$dir/requests"
}
change() {
  local file=$1 filter=$2
  jq "$filter" "$dir/reads/$file.json" >"$dir/changed.json" \
    && mv "$dir/changed.json" "$dir/reads/$file.json"
}
digest_now() { "$digester" "$dir/reads/comments.json" "$dir/reads/review-comments.json" "$dir/reads/reviews.json"; }
run() {
  code=0
  env -u LAND_DIGEST_SCRIPT PATH="$tmp/bin:$PATH" STUB_DIR="$dir" STUB_HEAD="$head" STUB_MAIN="$main" \
    STUB_FAIL= STUB_JUNK= STUB_LATE_HOLD= STUB_MERGE=merged LAND_MERGE=on GITHUB_RUN_ATTEMPT=1 \
    GITHUB_REPOSITORY_OWNER=owner GITHUB_REPOSITORY_OWNER_ID=7 GH_TOKEN=read-token \
    LAND_MERGE_TOKEN=merge-token-secret LAND_PR=153 LAND_HEAD="$head" LAND_APPROVAL=450 \
    LAND_DIGEST="$base_digest" LAND_REQUIRES_SPEC=false GITHUB_OUTPUT="$dir/output" "$@" \
    "$script" owner/mitos "$dir/out" >"$dir/stdout" 2>"$dir/stderr" || code=$?
}
exits() { [ "$code" = "$1" ] || note "exit $code, expected $1" "$(cat "$dir/stderr")"; }
outcome() {
  exits 0
  local expected=$1 actual
  actual=$(cat "$dir/out/outcome.json" 2>/dev/null)
  [ "$(wc -l <"$dir/out/outcome.json" 2>/dev/null)" = 1 ] || note "outcome is not one line"
  jq -e --argjson want "$expected" '. == $want' <<<"$actual" >/dev/null 2>&1 \
    || note "outcome $actual, expected $expected"
  [ "$(cat "$dir/output" 2>/dev/null)" = "outcome=$actual" ] || note "output does not carry the outcome"
}
stopped() { outcome "{\"kind\":\"stopped\",\"why\":\"$1\"}"; no_put; }
no_put() { [ ! -e "$dir/put" ] || note "a stopped run sent PUT"; }
no_call() { [ ! -s "$dir/calls" ] || note "unexpected calls: $(cat "$dir/calls")"; }
one_put() {
  [ "$(jq -s '[.[] | select(.args[1] == "-X" and .args[2] == "PUT")] | length' "$dir/requests")" = 1 ] \
    || note "PUT was not sent exactly once"
}

start
prepare merged
run
outcome "{\"kind\":\"merged\",\"main\":\"$main\"}"
one_put
want_calls=$(printf '%s\n' \
  'read-token|api repos/owner/mitos/pulls/153' \
  'read-token|api --paginate --slurp repos/owner/mitos/issues/153/comments?per_page=100' \
  'read-token|api --paginate --slurp repos/owner/mitos/pulls/153/comments?per_page=100' \
  'read-token|api --paginate --slurp repos/owner/mitos/pulls/153/reviews?per_page=100' \
  "merge-token-secret|api -X PUT repos/owner/mitos/pulls/153/merge -f merge_method=rebase -f sha=$head")
[ "$(cat "$dir/calls")" = "$want_calls" ] || note "calls: $(cat "$dir/calls")"
finish merges-once-pinned-to-the-head

start
for value in off ON true 'on ' ''; do
  prepare "off-${value// /_}"
  run LAND_MERGE="$value"
  stopped off
  no_call
done
finish the-switch-off-calls-nothing

start
for value in 2 0 01 ''; do
  prepare "attempt-$value"
  run GITHUB_RUN_ATTEMPT="$value"
  stopped attempt
  no_call
done
finish a-second-attempt-calls-nothing

start
prepare no-plan
run LAND_PR=
stopped input
no_call
apply=$(job_block "$wf" apply)
grep -qF "needs.decide.outputs.pr != ''" <<<"$apply" || note "apply does not skip an empty handoff"
finish no-merge-plan-calls-nothing

start
for value in LAND_PR=012 LAND_PR=12345678 LAND_HEAD=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
  LAND_HEAD=abc LAND_APPROVAL=0 LAND_DIGEST=abc GITHUB_REPOSITORY_OWNER_ID=no \
  GH_TOKEN= LAND_MERGE_TOKEN= LAND_REQUIRES_SPEC= LAND_REQUIRES_SPEC=True LAND_REQUIRES_SPEC=0; do
  prepare "input-${value%%=*}-${value#*=}"
  run "$value"
  stopped input
  no_call
done
finish bad-input-calls-nothing

while IFS='|' read -r name filter; do
  start
  prepare "$name"
  change pr "$filter"
  run
  stopped pr
  finish "$name"
done <<'CASES'
a-moved-head-stops|.head.sha="3333333333333333333333333333333333333333"
a-draft-stops|.draft=true
a-closed-or-merged-pull-request-stops|.state="closed"
a-merged-pull-request-stops|.merged=true
another-base-stops|.base.ref="other"
another-base-repository-stops|.base.repo.full_name="owner/other"
a-fork-stops|.head.repo.full_name="outsider/mitos"
CASES

while IFS='|' read -r name file filter; do
  start
  prepare "$name"
  change "$file" "$filter"
  run
  stopped digest
  finish "$name"
done <<'CASES'
a-new-comment-stops|comments|.[0] += [.[0][0] | .id=499 | .body="/hold"]
an-edited-comment-stops|comments|.[0][0].body="edited"
a-deleted-comment-stops|comments|.[0] |= map(select(.id != 451))
an-edited-review-stops|reviews|.[0][0].body="edited review"
a-new-review-comment-stops|review-comments|.[0] += [.[0][0] | .id=461]
a-bot-edit-stops|comments|.[0][1].body="new report"
CASES

while IFS='|' read -r name filter; do
  start
  prepare "$name"
  change comments "$filter"
  run LAND_DIGEST="$(digest_now)"
  stopped approval
  finish "$name"
done <<'CASES'
an-approval-from-another-login-stops|.[0][0].user.login="outsider"
the-same-login-with-another-id-stops|.[0][0].user.id=99
an-approval-with-an-app-stops|.[0][0].performed_via_github_app={slug:"claude"}
an-edited-approval-stops|.[0][0].updated_at="2026-11-15T08:01:00Z"
an-absent-approval-stops|.[0] |= map(select(.id != 450))
a-bot-approval-stops|.[0][0].user.type="Bot"
a-duplicate-approval-stops|.[0] += [.[0][0]]
CASES

start
for route in pr comments review-comments reviews; do
  prepare "failed-$route"
  run STUB_FAIL="$route"
  stopped read
  prepare "junk-$route"
  run STUB_JUNK="$route"
  if [ "$route" = pr ]; then stopped pr; else stopped read; fi
done
finish a-failed-read-stops

start
for labels in '[]' 'null' '["spec-approved"]' '[{"name":"Spec-Approved"}]'; do
  prepare "missing-spec-${#labels}"
  change pr ".labels=$labels"
  run LAND_REQUIRES_SPEC=true
  stopped label
done
prepare spec-approved
run LAND_REQUIRES_SPEC=true
outcome "{\"kind\":\"merged\",\"main\":\"$main\"}"
one_put
prepare spec-not-required
change pr '.labels=[]'
run LAND_REQUIRES_SPEC=false
outcome "{\"kind\":\"merged\",\"main\":\"$main\"}"
one_put
finish the-required-spec-label-is-read-again

start
for status in 405 409; do
  prepare "refused-$status"
  run STUB_MERGE="$status"
  outcome "{\"kind\":\"refused\",\"status\":\"$status\"}"
  one_put
  [ ! -e "$dir/read-back" ] || note "$status retried a read"
done
finish 405-and-409-are-refusals-with-no-retry

start
for status in 401 403 422 500; do
  prepare "failed-$status"
  run STUB_MERGE="$status"
  outcome "{\"kind\":\"failed\",\"status\":\"$status\"}"
  one_put
  [ ! -e "$dir/read-back" ] || note "$status retried a read"
done
finish another-status-is-a-failure

start
for answer in unmerged malformed; do
  prepare "bad-200-$answer"
  run STUB_MERGE="$answer"
  outcome '{"kind":"failed","status":"200"}'
  one_put
done
finish a-200-that-did-not-merge-is-a-failure

start
for answer in merged open moved malformed unread; do
  prepare "lost-$answer"
  case $answer in
    open) change after '.merged=false' ;;
    moved) change after '.head.sha="3333333333333333333333333333333333333333"' ;;
    malformed) change after '.merge_commit_sha="junk"' ;;
  esac
  run STUB_MERGE=lost STUB_FAIL="$([ "$answer" = unread ] && echo after)"
  if [ "$answer" = merged ]; then
    outcome "{\"kind\":\"merged\",\"main\":\"$main\"}"
  else
    outcome '{"kind":"failed","status":"none"}'
  fi
  one_put
  [ "$(wc -l <"$dir/calls")" = 6 ] || note "$answer did not read back once"
  [ -e "$dir/read-back" ] || note "$answer did not read back"
done
finish a-lost-answer-reads-once

start
prepare late-hold
run STUB_LATE_HOLD=1
outcome "{\"kind\":\"merged\",\"main\":\"$main\"}"
one_put
jq -e 'any(.[][]; .body == "/hold")' "$dir/reads/comments.json" >/dev/null \
  || note "the later hold was not injected"
jq -e 'all(.[][]; .body != "/hold")' "$dir/out/comments.json" >/dev/null \
  || note "a hold after the cutoff was read"
[ "$(wc -l <"$dir/calls")" = 5 ] || note "the last conversation read was not the cutoff"
finish a-hold-after-the-last-conversation-read-is-outside-the-cutoff

start
while IFS= read -r request; do
  jq -e '(if .args[1] == "-X" and .args[2] == "PUT"
    then .token == "merge-token-secret" else .token == "read-token" end)
    and all(.args[]; contains("merge-token-secret") | not)' <<<"$request" >/dev/null \
    || note "token outside the merge request: $request"
done < <(cat "$tmp/runs/"*/requests)
if grep -rlF --exclude-dir=reads --include='*.json' --include=output --include=stdout \
  --include=stderr 'merge-token-secret' "$tmp/runs"; then
  note "the merge token reached an output or saved response"
elif [ "$?" != 1 ]; then
  note "the merge token search failed"
fi
finish the-app-token-only-merges

start
joined=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' "$script")
calls=$(grep -E '(^|[[:space:]])gh api' <<<"$joined")
[ "$(grep -cE 'timeout -k 5 120 gh api' <<<"$calls")" = "$(wc -l <<<"$calls")" ] \
  || note "a call has no timeout"
[ "$(wc -l <<<"$calls")" = 3 ] || note "unexpected gh call sites: $calls"
finish every-call-has-a-timeout

start
awk '!/^#/ && /merge-async|bypass_rules|merge_method=(squash|merge)/ {print; bad=1}
  END {exit bad}' "$script" \
  || note "another merge route or method"
[ "$(grep -cF 'gh api -X PUT' "$script")" = 1 ] || note "there is not one PUT site"
if other_routes=$(grep -rlE --exclude='*.test.sh' --exclude=land-apply.sh \
  'pulls/[^" ]*/merge|pulls/\$[^" ]*/merge' "$root/.github"); then
  note "another merge route: $other_routes"
elif [ "$?" != 1 ]; then
  note "the merge route search failed"
fi
finish no-merge-async-no-bypass

start
if [ "$(grep -c '^    environment: trusted$' "$wf")" != 1 ] \
  || ! grep -q '^    environment: trusted$' <<<"$apply"; then
  note "apply is not the only trusted job"
fi
for pin in "github.ref == 'refs/heads/main'" "github.run_attempt == '1'" \
  "needs.decide.outputs.pr != ''" '      group: land-apply' '      cancel-in-progress: false'; do
  grep -qF "$pin" <<<"$apply" || note "apply does not name [$pin]"
done
permissions=$(awk '/^    permissions:$/ {inside=1;next} inside && !/^      / {exit} inside {print}' <<<"$apply")
[ "$permissions" = '      contents: read
      pull-requests: read
      issues: read' ] || note "apply permissions: $permissions"
mint=$(awk '/^      - / {inside=0} /id: app$/ {inside=1} inside {print}' <<<"$apply")
[ "$(sed -E 's/ #.*$//' <<<"$mint")" = '        id: app
        if: env.LAND_MERGE == '"'"'on'"'"'
        uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547
        with:
          app-id: ${{ vars.PR_UPDATER_APP_ID }}
          private-key: ${{ secrets.PR_UPDATER_APP_KEY }}
          permission-contents: write
          permission-workflows: write' ] || note "apply mint: $mint"
[ "$(grep -cF 'steps.app.outputs.token' <<<"$apply")" = 1 ] || note "app token is used more than once"
grep -qxF '          GH_TOKEN: ${{ github.token }}' <<<"$apply" || note "apply does not read with github.token"
grep -qxF '          LAND_MERGE_TOKEN: ${{ steps.app.outputs.token }}' <<<"$apply" \
  || note "apply does not confine the app token to LAND_MERGE_TOKEN"
checkout=$(awk '/^      - / && inside {exit} /uses: actions\/checkout@/ {inside=1} inside {print}' <<<"$apply")
[ "$(sed -E 's/ #.*$//' <<<"$checkout")" = '      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
        with:
          sparse-checkout: .github/scripts
          persist-credentials: false' ] || note "apply checkout: $checkout"
! grep -E 'lake|install-|cache|github\.event' <<<"$apply" | grep -v '^    #' \
  || note "apply loads a toolchain or event data"
if [ "$(grep -cE "^[[:space:]]*LAND_MERGE:" "$wf")" != 1 ] \
  || ! grep -qxF "  LAND_MERGE: 'on'" "$wf"; then
  note "the switch is not the one workflow constant"
fi
grep -qxF '          LAND_REQUIRES_SPEC: ${{ needs.decide.outputs.requires_spec }}' <<<"$apply" \
  || note "apply does not receive requires_spec"
grep -qxF '        run: .github/scripts/land-apply.test.sh' "$root/.github/workflows/ci.yml" \
  || note "ci does not run this test"
finish holds-the-key-only-to-merge

mkdir -p "$tmp/live305"
cat >"$tmp/live305/comments.json" <<'JSON'
[[{"id":6895672172,"user":{"login":"coderabbitai[bot]"},"performed_via_github_app":{"slug":"coderabbitai"},"created_at":"2026-11-15T14:09:02Z","updated_at":"2026-11-15T19:03:25Z","body":"<!-- coderabbit-ai-generated:v1 -->\n\n<!-- This is an auto-generated comment: sum"},{"id":6896156566,"user":{"login":"kitimark"},"performed_via_github_app":{"slug":"claude"},"created_at":"2026-11-15T14:33:14Z","updated_at":"2026-11-15T14:33:14Z","body":"CodeRabbit's security concern on a651c31 is fixed in 184a10e. The concern: an ow"}]]
JSON
cat >"$tmp/live305/review-comments.json" <<'JSON'
[[{"id":4579039280,"pull_request_review_id":5911523649,"user":{"login":"coderabbitai[bot]"},"performed_via_github_app":null,"created_at":"2026-11-15T15:38:40Z","updated_at":"2026-11-15T17:00:29Z","body":"<!-- coderabbit-ai-generated:v1 -->\n\n**<picture><img src=\"https://storage.google"},{"id":4579279405,"pull_request_review_id":5911790351,"user":{"login":"kitimark"},"performed_via_github_app":null,"created_at":"2026-11-15T16:48:42Z","updated_at":"2026-11-15T16:48:42Z","body":"Fixed in 4afe70e, by the second option you named."}]]
JSON
cat >"$tmp/live305/reviews.json" <<'JSON'
[[{"id":5911523649,"user":{"login":"coderabbitai[bot]"},"performed_via_github_app":null,"state":"COMMENTED","commit_id":"ab4fcdbe6a475c1eadff3c347bd23984a3a090a5","submitted_at":"2026-11-15T15:38:41Z","body":"<!-- coderabbit-ai-generated:v1 -->\n\n**Actionable comments posted: 1**\n\n---\n\n<!-"},{"id":5911790351,"user":{"login":"kitimark"},"performed_via_github_app":null,"state":"COMMENTED","commit_id":"4afe70e5132b666b4ed207071c0889ed4f3610b1","submitted_at":"2026-11-15T16:48:42Z","body":""}]]
JSON
digest_file() {
  "$digester" "$dir/reads/comments.json" "$dir/reads/review-comments.json" "$dir/reads/reviews.json" \
    >"$dir/digest" 2>"$dir/digest.err"
}
live_case() {
  prepare "$1"
  cp "$tmp/live305/"*.json "$dir/reads/"
}
live_case digest-base
digest_file || { echo "FAIL live305 digest"; exit 1; }
live_digest=$(cat "$dir/digest")

start
for filter in '.' '[.[][] | .] | reverse | map([.])' '.[0] += [.[0][0]]'; do
  live_case "digest-stable-${#filter}"
  for file in comments review-comments reviews; do change "$file" "$filter"; done
  digest_file || note "digest failed for $filter"
  [ "$(cat "$dir/digest")" = "$live_digest" ] || note "digest changed for $filter"
done
[[ $live_digest =~ ^[0-9a-f]{64}$ ]] || note "digest is not 64 lowercase hex"
finish digest-same-reads-pages-order-and-repeated-items

start
for file in comments review-comments reviews; do
  for filter in '.[0] += [.[0][0] | .id += 1]' '.[0] |= .[1:]' \
    '.[0][0].body += "edited"' '.[0][0].user.login="other"' \
    '.[0][0].performed_via_github_app={slug:"other"}'; do
    live_case "digest-changed-$file-${#filter}"
    change "$file" "$filter"
    digest_file || note "$file digest failed for $filter"
    [ "$(cat "$dir/digest")" != "$live_digest" ] || note "$file ignored $filter"
  done
done
for file in comments review-comments; do
  live_case "digest-time-$file"
  change "$file" '.[0][0].updated_at="2026-11-15T20:00:00Z"'
  digest_file || note "$file digest failed after moved updated_at"
  [ "$(cat "$dir/digest")" != "$live_digest" ] || note "$file ignored moved updated_at"
done
live_case digest-state
change reviews '.[0][0].state="APPROVED"'
digest_file || note "digest failed after changed state"
[ "$(cat "$dir/digest")" != "$live_digest" ] || note "digest ignored changed state"
finish digest-add-delete-edit-time-login-app-and-state

start
for file in comments review-comments reviews; do
  for malformed in flat error empty multiple junk; do
    live_case "digest-bad-$file-$malformed"
    case $malformed in
      flat) change "$file" '.[0]' ;;
      error) echo '{"message":"failed"}' >"$dir/reads/$file.json" ;;
      empty) echo '[]' >"$dir/reads/$file.json" ;;
      multiple) cp "$dir/reads/$file.json" "$dir/extra.json"
        cat "$dir/extra.json" >>"$dir/reads/$file.json" ;;
      junk) echo 'not JSON' >"$dir/reads/$file.json" ;;
    esac
    digest_code=0
    digest_file || digest_code=$?
    [ "$digest_code" = 1 ] || note "$file exited $digest_code for $malformed, expected 1"
    [ ! -s "$dir/digest" ] || note "$file emitted a digest for $malformed"
  done
done
finish digest-malformed-reads-fail-without-a-hash

start
live_case digest-data
payload=$(printf '$(touch %s)\n\140touch %s\140\nlast line' "$dir/command-substitution" "$dir/backticks")
jq --arg body "$payload" '.[0][0].body=$body' "$dir/reads/comments.json" >"$dir/data.json"
mv "$dir/data.json" "$dir/reads/comments.json"
digest_file || note "shell text was not accepted as data"
[ "$(cat "$dir/digest")" != "$live_digest" ] || note "shell text body was ignored"
[ ! -e "$dir/command-substitution" ] && [ ! -e "$dir/backticks" ] || note "body text was executed"
first=$(cat "$dir/digest")
digest_file || note "same shell text failed a second time"
[ "$(cat "$dir/digest")" = "$first" ] || note "the same body changed digest"
finish digest-shell-text-and-newlines-are-data

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
