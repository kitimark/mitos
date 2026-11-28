#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/land-report.sh
command -v jq >/dev/null 2>&1 || { echo "FAIL jq is not installed"; exit 1; }
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
real=$root/.lake/build/bin/mitos-gate
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() {
  echo "FAIL $1"
  shift
  for l in "$@"; do echo "  | $l"; done
  fail=$((fail + 1))
}
problems=()
start() { problems=(); }
note() { problems+=("$@"); }
finish() { if [ ${#problems[@]} = 0 ]; then ok "$1"; else bad "$1" "${problems[@]}"; fi; }

head=1111111111111111111111111111111111111111
main=2222222222222222222222222222222222222222
marker='<!-- land-report -->'
run_link=https://github.com/owner/mitos/actions/runs/43
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
jq -cn --arg token "${GH_TOKEN:-}" --args '{token:$token,args:$ARGS.positional}' -- "$@" >>"$STUB_DIR/calls"
if [ $# = 4 ] && [ "$1 $2 $3" = 'api --paginate --slurp' ] \
  && [[ $4 =~ ^repos/owner/mitos/issues/([1-9][0-9]*)/comments\?per_page=100$ ]]; then
  pr=${BASH_REMATCH[1]}
  [ "${STUB_FAIL_READ:-}" != "$pr" ] || exit 1
  if [ "${STUB_JUNK_READ:-}" = "$pr" ]; then echo '{"message":"failed"}'; else cat "$STUB_DIR/comments-$pr.json"; fi
elif [ $# = 6 ] && [ "$1 $2 $3" = 'api -X POST' ] && [ "$5" = -f ] \
  && [[ $4 =~ ^repos/owner/mitos/issues/([1-9][0-9]*)/comments$ ]] && [[ $6 = body=* ]]; then
  pr=${BASH_REMATCH[1]} body=${6#body=}
  [ ! -e "$STUB_RUN/posted-$pr" ] || { echo 'duplicate POST' >&2; exit 64; }
  touch "$STUB_RUN/posted-$pr"
  [ "${STUB_FAIL_POST:-}" != "$pr" ] || exit 1
  jq -cn --argjson pr "$pr" --arg body "$body" '{pr:$pr,body:$body}' >>"$STUB_DIR/posts"
  jq --arg body "$body" '(([.[][] | .id] | max // 0) + 1) as $id
    | .[0] += [{id:$id,user:{login:"github-actions[bot]",type:"Bot"},
        performed_via_github_app:{slug:"github-actions"},body:$body}]' \
    "$STUB_DIR/comments-$pr.json" >"$STUB_DIR/changed.json"
  mv "$STUB_DIR/changed.json" "$STUB_DIR/comments-$pr.json"
else
  echo "unexpected call: $*" >&2
  exit 64
fi
STUB
chmod +x "$tmp/bin/gh"

prepare() {
  dir=$tmp/runs/$1
  rm -rf "$dir"
  mkdir -p "$dir"
  for pr in 153 154 155; do echo '[[]]' >"$dir/comments-$pr.json"; done
  : >"$dir/calls"
  : >"$dir/posts"
  invocation=0
}
run() {
  code=0
  invocation=$((invocation + 1))
  mkdir -p "$dir/run-$invocation"
  env PATH="$tmp/bin:$PATH" GH_TOKEN=report-token STUB_DIR="$dir" STUB_RUN="$dir/run-$invocation" \
    STUB_FAIL_READ= STUB_JUNK_READ= STUB_FAIL_POST= GITHUB_RUN_ID=43 \
    GITHUB_SERVER_URL=https://github.com LAND_PR= LAND_HEAD= LAND_ANSWERS='[]' \
    LAND_APPLIED=null LAND_APPLY_RESULT=success "$@" "$script" owner/mitos \
    >"$dir/stdout" 2>"$dir/stderr" || code=$?
}
exits() { [ "$code" = "$1" ] || note "exit $code, expected $1" "$(cat "$dir/stderr")"; }
no_call() { [ ! -s "$dir/calls" ] || note "unexpected calls: $(cat "$dir/calls")"; }
no_post() { [ ! -s "$dir/posts" ] || note "unexpected posts: $(cat "$dir/posts")"; }
body_is() {
  jq -es --argjson pr "$1" --arg body "$2" '[.[] | select(.pr == $pr)] == [{pr:$pr,body:$body}]' \
    "$dir/posts" >/dev/null 2>&1 || note "expected body for #$1: $2" "posts: $(cat "$dir/posts")"
}
answer() {
  jq -cn --argjson pr "$1" --arg line "$2" --arg body "$3" --argjson land "${4:-null}" \
    '[{pr:$pr,line:$line,body:$body,land:$land}]'
}
prior() {
  jq -n --arg body "$2" --argjson id "$1" '[[{id:$id,user:{login:"github-actions[bot]",type:"Bot"},
    performed_via_github_app:{slug:"github-actions"},body:$body}]]' >"$dir/comments-153.json"
}
line="Queued at $head: waiting for gate."
body="$marker"$'\n'"$line"
answers=$(answer 153 "$line" "$body")

start
prepare bodies
fence=$(printf '\140\140\140')
bare_line='This PR touches a path you keep. To approve and merge it, comment only this line:'
bare_body="$marker"$'\n'"$bare_line"$'\n\n'"$fence"$'\n'"/land $head"$'\n'"$fence"
many=$(jq -cn --arg l "$line" --arg b "$body" --arg bl "$bare_line" --arg bb "$bare_body" \
  '[{pr:154,line:$l,body:$b,land:null},{pr:153,line:$bl,body:$bb,land:null}]')
run LAND_ANSWERS="$many"
exits 0
body_is 153 "$bare_body"
body_is 154 "$body"
finish each-answer-posts-its-body

start
prepare same
prior 90 "$body"
run LAND_ANSWERS="$answers"
exits 0
no_post
[ "$(wc -l <"$dir/calls")" = 1 ] || note "dedupe did not make just one read"
finish the-same-answer-posts-nothing

owner_land() {
  jq --argjson id "$1" '.[0] += [{id:$id,user:{login:"owner",type:"User"},
    performed_via_github_app:null,body:"/land"}]' "$dir/comments-153.json" >"$dir/changed.json"
  mv "$dir/changed.json" "$dir/comments-153.json"
}
start
prepare new-land
prior 90 "$body"
owner_land 100
run LAND_ANSWERS="$(answer 153 "$line" "$body" 100)"
exits 0
body_is 153 "$body"
run LAND_ANSWERS="$(answer 153 "$line" "$body" 100)"
exits 0
[ "$(wc -l <"$dir/posts")" = 1 ] || note "the answered /land was answered again"
owner_land 102
run LAND_ANSWERS="$(answer 153 "$line" "$body" 102)"
exits 0
[ "$(wc -l <"$dir/posts")" = 2 ] || note "the next /land was not answered"
finish the-same-answer-to-each-new-land-posts-once

start
prepare old-land
prior 90 "$body"
owner_land 80
run LAND_ANSWERS="$(answer 153 "$line" "$body" 80)"
exits 0
no_post
finish the-same-answer-to-an-answered-land-posts-nothing

start
prepare first-land
owner_land 100
run LAND_ANSWERS="$(answer 153 "$line" "$body" 100)"
exits 0
body_is 153 "$body"
finish a-land-with-no-report-yet-is-answered

start
prepare forged-newer
prior 90 "$body"
owner_land 100
jq '.[0] += [.[0][0] | .id=200 | .user.login="outsider" | .user.type="User"]' \
  "$dir/comments-153.json" >"$dir/changed.json"
mv "$dir/changed.json" "$dir/comments-153.json"
run LAND_ANSWERS="$(answer 153 "$line" "$body" 100)"
exits 0
body_is 153 "$body"
finish a-forged-report-after-the-land-is-not-its-answer

start
named_answer() {
  prepare "named-$1"
  jq -c "$2" "$root/gate/land-fixtures/queue.json" >"$dir/snapshot.json"
  run LAND_ANSWERS="$("$real" land-answers "$dir/snapshot.json" | jq -c .answers)"
  exits 0
  body_is 153 "$marker"$'\n'"$3"
}
own_hold='.prs[0].words += [{"kind":"ownerHold","said":1901}]'
named_answer read "$own_hold | .notes = [{pr: 153, unread: [\"dashboard\"], unmet: [], owner: true}]" \
  'Held at aaa: a read failed (unread dashboard). The next run reads again, so no new comment is needed.'
named_answer hold "$own_hold | .notes = [{pr: 153, unread: [], unmet: [], owner: true}]" \
  'Held by your /hold or an edited comment. Comment /land aaa to go on.'
while IFS='|' read -r part text <&3; do
  named_answer "$part" \
    ".prs[0].rest = false | .notes = [{pr: 153, unread: [], unmet: [\"$part\"], owner: true}]" \
    "Stopped: $text."
done 3<<'PARTS'
footer|a PR body without exactly one footer or with a session link
unanswered|an unanswered owner comment
label|a spec path without the spec-approved label
provenance|unread provenance (provenance admission incomplete)
entry|no provenance entry for the author (provenance admission incomplete)
author|a recorded author that does not cover this head (provenance admission incomplete)
verdict|verdicts short of the reviewer requirements (provenance admission incomplete)
PARTS
named_answer fallback '.prs[0].rest = false' \
  'Stopped: an unanswered owner comment, a missing required label or footer, or unmet author or reviewer verification requirements.'
finish the-tools-named-reasons-are-posted

start
prepare pushed-bare
old_head=3333333333333333333333333333333333333333
prior 90 "${bare_body//$head/$old_head}"
run LAND_ANSWERS="$(answer 153 "$bare_line" "$bare_body")"
exits 0
body_is 153 "$bare_body"
finish a-bare-land-after-a-push-posts-the-new-head

start
prepare newer-different
prior 90 "$body"
jq --arg body "$marker"$'\n''Old answer.' '.[0] = [.[0][0] | .id=100 | .body=$body] + .[0]' \
  "$dir/comments-153.json" >"$dir/changed.json"
mv "$dir/changed.json" "$dir/comments-153.json"
run LAND_ANSWERS="$answers"
exits 0
body_is 153 "$body"
prepare newer-same
prior 100 "$body"
jq --arg body "$marker"$'\n''Old answer.' '.[0] += [.[0][0] | .id=90 | .body=$body]' \
  "$dir/comments-153.json" >"$dir/changed.json"
mv "$dir/changed.json" "$dir/comments-153.json"
run LAND_ANSWERS="$answers"
exits 0
no_post
finish the-newest-report-decides

start
prepare once
run LAND_ANSWERS="$many" LAND_PR=155 LAND_HEAD="$head" LAND_APPLIED="{\"kind\":\"merged\",\"main\":\"$main\"}"
exits 0
jq -es 'length == 3 and (group_by(.pr) | all(.[]; length == 1))' "$dir/posts" >/dev/null \
  || note "more than one post per pull request"
run LAND_ANSWERS="$many" LAND_PR=155 LAND_HEAD="$head" LAND_APPLIED="{\"kind\":\"merged\",\"main\":\"$main\"}"
exits 0
[ "$(wc -l <"$dir/posts")" = 3 ] || note "the repeated run posted another unchanged answer"
finish one-post-per-pull-request-per-run

start
for filter in '.user.login="outsider"' '.user.type="User"' \
  '.performed_via_github_app=null' '.performed_via_github_app.slug="other"'; do
  prepare "forged-${#filter}"
  prior 90 "$body"
  jq --argjson comment "$(jq -c ".[0][0] | $filter" "$dir/comments-153.json")" '[[$comment]]' \
    "$dir/comments-153.json" >"$dir/changed.json"
  mv "$dir/changed.json" "$dir/comments-153.json"
  run LAND_ANSWERS="$answers"
  exits 0
  body_is 153 "$body"
done
finish a-forged-marker-is-ignored

start
prepare landed
run LAND_PR=153 LAND_HEAD="$head" LAND_APPLIED="{\"kind\":\"merged\",\"main\":\"$main\"}"
exits 0
body_is 153 "$marker"$'\n'"Landed $head on your /land. main is $main."
finish landed-names-head-and-main

start
for status in 401 403 422 500 200 none; do
  prepare "failed-$status"
  run LAND_PR=153 LAND_HEAD="$head" LAND_APPLIED="{\"kind\":\"failed\",\"status\":\"$status\"}"
  exits 1
  body_is 153 "$marker"$'\n'"Merge call failed: $status."$'\n\n'"$run_link"
done
finish a-failed-call-posts-its-status-and-the-run

start
prepare failed-job
run LAND_PR=153 LAND_HEAD="$head" LAND_APPLY_RESULT=failure
exits 1
body_is 153 "$marker"$'\n''Merge call failed: no outcome.'$'\n\n'"$run_link"
finish a-failed-apply-job-posts-no-outcome

start
for why in digest approval label read off; do
  prepare "stopped-$why"
  case $why in
    digest) expected="Not merged yet at $head: the conversation changed after the decision. Comment /land $head again to go on." ;;
    approval) expected="Not merged yet at $head: the approval is not your unedited comment. Comment /land $head again to go on." ;;
    label) expected="Not merged yet at $head: the spec-approved label changed after the decision. Comment /land $head again to go on." ;;
    read) expected="Not merged yet at $head: a read failed. Comment /land $head again to go on."$'\n\n'"$run_link" ;;
    off) expected='Not merged: the merge switch is off.' ;;
  esac
  run LAND_PR=153 LAND_HEAD="$head" LAND_APPLIED="{\"kind\":\"stopped\",\"why\":\"$why\"}"
  exits 0
  body_is 153 "$marker"$'\n'"$expected"
done
finish not-merged-yet-for-digest-approval-label-read-off

start
for result in '{"kind":"refused","status":"405"}' '{"kind":"refused","status":"409"}' \
  '{"kind":"stopped","why":"attempt"}' '{"kind":"stopped","why":"input"}' '{"kind":"stopped","why":"pr"}'; do
  prepare "silent-${#result}"
  run LAND_PR=153 LAND_HEAD="$head" LAND_APPLIED="$result"
  exits 0
  no_call
done
finish a-refusal-or-another-stop-posts-nothing

start
for result in skipped cancelled; do
  prepare "$result"
  run LAND_PR=153 LAND_HEAD="$head" LAND_APPLY_RESULT="$result"
  exits 0
  no_call
done
finish a-skipped-or-cancelled-apply-posts-nothing

start
codes=$(sed -nE 's/.*\bstop ([a-z]+).*/\1/p' "$root/.github/scripts/land-apply.sh" | sort -u)
[ "$codes" = 'approval
attempt
digest
input
label
off
pr
read' ] || note "an apply stop has no pinned reporting behavior: $codes"
finish why-codes-are-worded

start
for payload in 'null' '{}' 'not JSON' '[{}]' \
  '[{"pr":153,"line":"x","body":"x","land":null}]' \
  '[{"pr":153,"line":"x\ny","body":"<!-- land-report -->\nx\ny","land":null}]' \
  '[{"pr":0,"line":"x","body":"<!-- land-report -->\nx","land":null}]' \
  '[{"pr":1.5,"line":"x","body":"<!-- land-report -->\nx","land":null}]' \
  '[{"pr":"153","line":"x","body":"<!-- land-report -->\nx","land":null}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx","land":null,"extra":1}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx"}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx","land":0}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx","land":1.5}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx","land":"100"}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx","land":false}]' \
  '[{"pr":153,"line":"x","body":"<!-- land-report -->\nx","land":9007199254740992}]'; do
  prepare "bad-answers-${#payload}"
  run LAND_ANSWERS="$payload"
  exits 2
  no_call
done
prepare duplicate-answer
run LAND_ANSWERS="$(jq -c '. + .' <<<"$answers")"
exits 2
no_call
prepare answers-cap
run LAND_ANSWERS="$(jq -cn --arg m "$marker" '[range(1;102) | {pr:.,line:"x",body:($m+"\nx"),land:null}]')"
exits 2
no_call
finish malformed-answers-call-nothing

start
prepare planned-answer
run LAND_PR=153 LAND_HEAD="$head" LAND_ANSWERS="$answers"
exits 2
no_call
finish the-planned-pr-among-answers-is-refused

start
prepare mentions
run LAND_ANSWERS="$(answer 153 'Hello @owner.' "$marker"$'\n''Hello @owner.')"
exits 2
no_call
while IFS= read -r post; do
  jq -e '.body | contains("@") | not' <<<"$post" >/dev/null || note "a post mentions someone"
done < <(cat "$tmp/runs/"*/posts)
finish no-post-mentions-anyone

start
for failure in failed malformed; do
  prepare "read-$failure"
  if [ "$failure" = failed ]; then more=(STUB_FAIL_READ=153); else more=(STUB_JUNK_READ=153); fi
  run LAND_ANSWERS="$many" "${more[@]}"
  exits 1
  body_is 154 "$body"
  [ "$(wc -l <"$dir/posts")" = 1 ] || note "a failed read posted or stopped the other pull request"
done
finish a-failed-read-skips-that-pull-request-and-fails-the-job

start
prepare failed-post
run LAND_ANSWERS="$many" STUB_FAIL_POST=153
exits 1
body_is 154 "$body"
finish a-failed-post-fails-the-job-and-keeps-the-other-answer

start
while IFS= read -r post; do
  jq -e --arg marker "$marker"$'\n' '.body | startswith($marker)' <<<"$post" >/dev/null \
    || note "a post lacks the report marker"
done < <(cat "$tmp/runs/"*/posts)
[ "$(cat "$tmp/runs/"*/posts | wc -l)" -gt 0 ] || note "no posts were observed"
finish every-post-starts-with-the-marker

start
"$real" workflow pins "$root" || note "decoded workflow authority pins were refused"
finish report-holds-no-key

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
