#!/usr/bin/env bash
# Runs the cancel-superseded step from ci.yml against a stub gh. No token, no network.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
wf=$root/.github/workflows/ci.yml

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || fail "jq is not installed"

extract_body() {
  awk '
    /^[[:space:]]*# cancel-superseded-body[[:space:]]*$/ { n++; grab=1; next }
    /^[[:space:]]*# end-cancel-superseded-body[[:space:]]*$/ {
      if (!grab) exit 3
      grab=0
      end=1
      next
    }
    grab { print }
    END { if (n != 1 || end != 1) exit 2 }
  ' "$1"
}

strip_indent() {
  local n
  n=$(printf '%s\n' "$1" | awk 'NF { match($0, /^ */); print RLENGTH; exit }')
  if [ -z "$n" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  printf '%s\n' "$1" | sed -E "s/^ {$n}//"
}

require_body() {
  local file=$1 body
  body=$(extract_body "$file") || return 1
  body=$(strip_indent "$body")
  [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || return 1
  printf '%s\n' "$body"
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf '%s\n' '  # cancel-superseded-body' '  true' '  # end-cancel-superseded-body' >"$work/ok.yml"
got=$(require_body "$work/ok.yml")
[ "$got" = "true" ] || fail "indent strip produced [$got]"
ok "indent strip"

printf '%s\n' '  # cancel-superseded-body' '  # end-cancel-superseded-body' >"$work/empty.yml"
if require_body "$work/empty.yml" >/dev/null; then fail "empty body was accepted"; fi
ok "empty body fails"

printf '%s\n' 'no markers here' >"$work/missing.yml"
if require_body "$work/missing.yml" >/dev/null; then fail "missing markers were accepted"; fi
ok "missing markers fail"

printf '%s\n' '  # cancel-superseded-body' '  true' >"$work/noend.yml"
if require_body "$work/noend.yml" >/dev/null; then fail "missing end marker was accepted"; fi
ok "missing end marker fails"

script=$(require_body "$wf") || fail "workflow body is missing or empty"
first=${script%%$'\n'*}
[ "$first" = "set -euo pipefail" ] || fail "extracted body starts with [$first]"
last=$(printf '%s\n' "$script" | awk 'NF { line=$0 } END { print line }')
[ "$last" = "cancel_runs_whose_head_differs" ] || fail "extracted body ends with [$last]"
printf '%s\n' "$script" >"$work/body.sh"

stub_bin=$work/bin
mkdir -p "$stub_bin"
cat >"$stub_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = api ] || { printf 'stub gh: expected api, got %s\n' "${1:-}" >&2; exit 1; }
shift
spec=${STUB_SPEC:?}
method=GET
jq_expr=
url=
while [ $# -gt 0 ]; do
  case $1 in
    --paginate|--silent) shift ;;
    -X) method=$2; shift 2 ;;
    --jq) jq_expr=$2; shift 2 ;;
    -f) shift 2 ;;
    --*) printf 'stub gh: unknown flag %s\n' "$1" >&2; exit 1 ;;
    -*) printf 'stub gh: unknown flag %s\n' "$1" >&2; exit 1 ;;
    *) url=$1; shift ;;
  esac
done
[ -n "$url" ] || { printf 'stub gh: no url\n' >&2; exit 1; }

record() { printf '%s\n' "$1" >>"$spec/calls"; }

case $url in
  */runs/*/cancel)
    id=${url%/cancel}
    id=${id##*/}
    record "POST $id"
    if [ -f "$spec/cancel/$id" ]; then
      cat "$spec/cancel/$id" >&2
      exit 1
    fi
    exit 0
    ;;
  */runs/*/jobs)
    id=${url%/jobs}
    id=${id##*/}
    record "JOBS $id"
    [ -f "$spec/jobs/$id" ] || { printf 'stub gh: jobs for %s were not set\n' "$id" >&2; exit 1; }
    jobw=$(<"$spec/jobs/$id")
    [ "$jobw" = FAIL ] && { printf 'stub gh: jobs read failed\n' >&2; exit 1; }
    printf '%s\n' "$jobw"
    exit 0
    ;;
  */workflows/*/runs)
    record LIST
    cat "$spec/list.json"
    exit 0
    ;;
  */pulls/*)
    record PR
    cat "$spec/pr"
    exit 0
    ;;
  */runs/*)
    id=${url##*/}
    case $jq_expr in
      *workflow_id*)
        record OWN
        cat "$spec/own"
        exit 0
        ;;
      .status)
        record "STATUS $id"
        [ -f "$spec/status/$id" ] || { printf 'stub gh: status for %s was not set\n' "$id" >&2; exit 1; }
        st=$(<"$spec/status/$id")
        [ "$st" = FAIL ] && { printf 'stub gh: status read failed\n' >&2; exit 1; }
        printf '%s\n' "$st"
        exit 0
        ;;
      *)
        printf 'stub gh: unexpected jq [%s] for %s\n' "$jq_expr" "$url" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    printf 'stub gh: unexpected url %s (method %s)\n' "$url" "$method" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$stub_bin/gh"

# The line from job 131201990951.
phrase='gh: Cannot cancel a workflow run that has not been queued yet. (HTTP 409)'
msg403='gh: Resource not accessible by integration (HTTP 403)'
msg500='gh: Internal Server Error (HTTP 500)'

WF=42
OWN_SHA=curhead
BRANCH=reuse
REPO=kitimark/mitos
RUN_ID=100

prepare() {
  local spec=$1 pair id sha json sep
  shift
  rm -rf "$spec"
  mkdir -p "$spec/cancel" "$spec/status" "$spec/jobs" "$spec/tmp"
  printf '%s\n' "$WF $OWN_SHA $BRANCH" >"$spec/own"
  printf '%s\n' "open $OWN_SHA" >"$spec/pr"
  : >"$spec/calls"
  json='{"workflow_runs":['
  sep=
  for pair in "$@"; do
    id=${pair%%:*}
    sha=${pair#*:}
    json="$json$sep{\"id\":$id,\"head_sha\":\"$sha\",\"status\":\"queued\",\"event\":\"pull_request\",\"head_branch\":\"$BRANCH\",\"head_repository\":{\"full_name\":\"$REPO\"}}"
    sep=,
  done
  printf '%s]}\n' "$json" >"$spec/list.json"
}

refuse() { printf '%s\n' "$3" >"$1/cancel/$2"; }
status_of() { printf '%s\n' "$3" >"$1/status/$2"; }
jobs_of() { printf '%s\n' "$3" >"$1/jobs/$2"; }

notice_line() {
  printf '::notice::Run %s is not started (status %s, %s jobs). GitHub refused the cancel with HTTP 409. Leaving the run.' "$1" "$2" "$3"
}

dump() {
  local spec=$1
  printf '%s\n' '--- stdout ---' >&2
  cat "$spec/out" >&2 2>/dev/null || true
  printf '%s\n' '--- stderr ---' >&2
  cat "$spec/err" >&2 2>/dev/null || true
  printf '%s\n' '--- calls ---' >&2
  cat "$spec/calls" >&2 2>/dev/null || true
  printf '%s\n' '--- list ---' >&2
  cat "$spec/list.json" >&2 2>/dev/null || true
}

run_body() {
  local spec=$1
  env -u GH_TOKEN \
    PATH="$stub_bin:$PATH" \
    REPO="$REPO" \
    PR=149 \
    RUN_ID=$RUN_ID \
    CONFIRM_SECONDS=0 \
    RUNNER_TEMP="$spec/tmp" \
    STUB_SPEC="$spec" \
    bash "$work/body.sh"
}

posts_of() {
  awk '$1=="POST" { printf "%s%s", sep, $2; sep="," }' "$1"
}

saw_kind() {
  awk -v k="$2" '$1==k { found=1 } END { exit found ? 0 : 1 }' "$1/calls"
}

run_case() {
  local name=$1 spec=$2 want_rc=$3 want_posts=$4 notice=${5-}
  local rc got n all
  set +e
  run_body "$spec" >"$spec/out" 2>"$spec/err"
  rc=$?
  set -e
  if [ "$rc" != "$want_rc" ]; then
    dump "$spec"
    fail "$name: exit $rc want $want_rc"
  fi
  got=$(posts_of "$spec/calls")
  if [ "$got" != "$want_posts" ]; then
    dump "$spec"
    fail "$name: posts [$got] want [$want_posts]"
  fi
  if awk '$1=="POST" && $2=="100" { found=1 } END { exit found ? 0 : 1 }' "$spec/calls"; then
    dump "$spec"
    fail "$name: the current run was posted"
  fi
  if [ -n "$notice" ]; then
    n=$(grep -F -x -c "$notice" "$spec/out" || true)
    all=$(grep -F -c '::notice::' "$spec/out" || true)
    if [ "$n" != 1 ] || [ "$all" != 1 ]; then
      dump "$spec"
      fail "$name: notice count exact=$n any=$all"
    fi
  elif grep -F -q '::notice::' "$spec/out"; then
    dump "$spec"
    fail "$name: unexpected notice"
  fi
  ok "$name"
}

open_pair() { prepare "$1" "100:$OWN_SHA" "200:oldhead"; }

spec=$work/a
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 queued
jobs_of "$spec" 200 0
run_case "(a) stuck, never started" "$spec" 0 200 "$(notice_line 200 queued 0)"

spec=$work/b500
open_pair "$spec"
refuse "$spec" 200 "$msg500"
status_of "$spec" 200 completed
run_case "(b) finished after the listing (HTTP 500)" "$spec" 0 200
saw_kind "$spec" STATUS || fail "(b) HTTP 500 did not read status"
if saw_kind "$spec" JOBS; then fail "(b) HTTP 500 read jobs"; fi
ok "(b) HTTP 500 left jobs unread"

spec=$work/b409
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 completed
run_case "(b) finished after the listing (the 409 line)" "$spec" 0 200
saw_kind "$spec" STATUS || fail "(b) 409 did not read status"
if saw_kind "$spec" JOBS; then fail "(b) 409 read jobs"; fi
ok "(b) 409 line left jobs unread"

spec=$work/c
open_pair "$spec"
run_case "(c) cancel accepted" "$spec" 0 200
if saw_kind "$spec" STATUS || saw_kind "$spec" JOBS; then
  fail "(c) read status or jobs"
fi
ok "(c) left status and jobs unread"

spec=$work/d403
open_pair "$spec"
refuse "$spec" 200 "$msg403"
status_of "$spec" 200 in_progress
jobs_of "$spec" 200 1
run_case "(d) in_progress refused with HTTP 403" "$spec" 1 200

spec=$work/d500
open_pair "$spec"
refuse "$spec" 200 "$msg500"
status_of "$spec" 200 in_progress
jobs_of "$spec" 200 3
run_case "(d) in_progress refused with HTTP 500" "$spec" 1 200

spec=$work/in-progress-zero
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 in_progress
jobs_of "$spec" 200 0
run_case "409 phrase with in_progress and 0 jobs" "$spec" 1 200

spec=$work/queued-jobs
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 queued
jobs_of "$spec" 200 4
run_case "409 phrase with queued and 4 jobs" "$spec" 1 200

spec=$work/queued-403
open_pair "$spec"
refuse "$spec" 200 "$msg403"
status_of "$spec" 200 queued
jobs_of "$spec" 200 0
run_case "queued, 0 jobs, HTTP 403 without the phrase" "$spec" 1 200

spec=$work/queued-500
open_pair "$spec"
refuse "$spec" 200 "$msg500"
status_of "$spec" 200 queued
jobs_of "$spec" 200 0
run_case "queued, 0 jobs, HTTP 500 without the phrase" "$spec" 1 200

both() {
  local slug=$1 title=$2 first=$3 second=$4 msg=$5 posts=$6 spec
  spec=$work/$slug
  prepare "$spec" "100:$OWN_SHA" "$first" "$second"
  refuse "$spec" 200 "$phrase"
  status_of "$spec" 200 queued
  jobs_of "$spec" 200 0
  refuse "$spec" 300 "$msg"
  status_of "$spec" 300 in_progress
  jobs_of "$spec" 300 1
  run_case "$title" "$spec" 1 "$posts" "$(notice_line 200 queued 0)"
}

both stuck-first "stuck then in_progress refusal" "200:oldhead" "300:midhead" "$msg403" "200,300"
both refused-first "in_progress refusal then stuck" "300:midhead" "200:oldhead" "$msg500" "300,200"

spec=$work/status-fail
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 FAIL
jobs_of "$spec" 200 0
run_case "failed status read on the 409 path" "$spec" 1 200

spec=$work/jobs-fail
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 queued
jobs_of "$spec" 200 FAIL
run_case "failed jobs read on the 409 path" "$spec" 1 200

spec=$work/twice
open_pair "$spec"
refuse "$spec" 200 "$phrase"
status_of "$spec" 200 queued
jobs_of "$spec" 200 0
: >"$spec/calls"
set +e
run_body "$spec" >"$spec/out" 2>"$spec/err"
rc1=$?
cp "$spec/out" "$spec/out1"
run_body "$spec" >"$spec/out" 2>"$spec/err"
rc2=$?
cp "$spec/out" "$spec/out2"
set -e
if [ "$rc1" != 0 ] || [ "$rc2" != 0 ]; then
  dump "$spec"
  fail "(a) twice: exits $rc1 and $rc2"
fi
got=$(posts_of "$spec/calls")
if [ "$got" != "200,200" ]; then
  dump "$spec"
  fail "(a) twice: posts [$got] want [200,200]"
fi
if awk '$1=="POST" && $2=="100" { found=1 } END { exit found ? 0 : 1 }' "$spec/calls"; then
  dump "$spec"
  fail "(a) twice: the current run was posted"
fi
for n in 1 2; do
  c=$(grep -F -x -c "$(notice_line 200 queued 0)" "$spec/out$n" || true)
  [ "$c" = 1 ] || { dump "$spec"; fail "(a) twice: notice count $c on run $n"; }
done
ok "(a) twice on the same stub: exit 0 both times, posted both times"
