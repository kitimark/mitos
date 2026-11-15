#!/usr/bin/env bash
# The label rule and the prove wait, under bash -e without pipefail. The script
# under test sets its own flags. `--live` is the real labels route.
# shellcheck disable=SC2034 # assignments feed the git, grep and gh stubs
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
script=$root/.github/scripts/ci-trust.sh
sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

[ -x "$script" ] || fail "ci-trust.sh is not executable"

if [ "${1:-}" = --live ]; then
  # A pull request, not a plain issue: gate's token has pull-requests: read,
  # which covers this route only when the number is a pull request. Locally,
  # with no LIVE_PR, issue 165 stands in and the caller's token can read it.
  live_pr=${LIVE_PR:-165}
  names=$(gh api --paginate --jq '.[].name' "repos/kitimark/mitos/issues/${live_pr}/labels") \
    || fail "real labels GET failed"
  ok "real labels GET"
  # A spec path forces the labels read.
  body=$(mktemp)
  printf 'core/Challenge/A.lean\0' >"$body"
  export STUB_GIT_FILE=$body STUB_GIT_STATUS=0
  export EVENT_NAME=pull_request REPO=kitimark/mitos PR=$live_pr BASE_REF=main
  export EVENT_ACTION=synchronize RUN_ID=1 HEAD_SHA=$sha
  bin=$(mktemp -d)
  cat >"$bin/git" <<'EOF'
#!/bin/bash
if [[ "$*" == *diff* ]]; then
  cat "${STUB_GIT_FILE:?}"
  exit "${STUB_GIT_STATUS:-0}"
fi
echo "unexpected git: $*" >&2
exit 1
EOF
  chmod +x "$bin/git"
  set +e
  err=$(PATH="$bin:$PATH" "$script" check 2>&1 >/dev/null)
  st=$?
  set -e
  if printf '%s\n' "$names" | grep -qx 'spec-approved'; then
    [ "$st" -eq 0 ] || fail "exact spec-approved on the live route exited $st: $err"
  else
    [ "$st" -ne 0 ] || fail "a live route without spec-approved exited 0"
    printf '%s\n' "$err" | grep -q 'without the spec-approved label' \
      || fail "the live route did not apply the label rule: $err"
  fi
  ok "the script's labels read uses the live route"
  export REPO=kitimark/mitos-no-such-404
  set +e
  err=$(PATH="$bin:$PATH" "$script" check 2>&1 >/dev/null)
  st=$?
  set -e
  [ "$st" -ne 0 ] || fail "a 404 repo was accepted"
  printf '%s\n' "$err" | grep -q 'without the spec-approved label' \
    && fail "a 404 was treated as a missing label"
  printf '%s\n' "$err" | grep -qi '404\|not found\|labels request failed' \
    || fail "a 404 was not reported: $err"
  ok "a 404 repo name is red"
  rm -rf "$bin" "$body"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
bin=$work/bin
mkdir -p "$bin" "$work/stub"
log=$work/gh.log
: >"$log"

cat >"$bin/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${STUB_GIT_LOG:?}"
if [[ "$*" == *diff* ]]; then
  [ -z "${STUB_GIT_FILE:-}" ] || cat "$STUB_GIT_FILE"
  exit "${STUB_GIT_STATUS:-0}"
fi
echo "unexpected git: $*" >&2
exit 1
EOF

cat >"$bin/grep" <<'EOF'
#!/bin/bash
if [ -n "${STUB_GREP_STATUS:-}" ]; then
  exit "$STUB_GREP_STATUS"
fi
if [ "${STUB_GREP_EMPTY:-}" = 1 ]; then
  exit 0
fi
exec /usr/bin/grep "$@"
EOF

cat >"$bin/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${STUB_LOG:?}"
url=
for a in "$@"; do
  case "$a" in
    repos/*) url=$a ;;
  esac
done
if [[ $url == *"/labels" ]]; then
  st=${STUB_LABELS_STATUS:-0}
  if [ "$st" -ne 0 ]; then
    echo "HTTP $st" >&2
    exit "$st"
  fi
  n=$(grep -c '/labels' "${STUB_LOG}" || true)
  if [ "$n" -ge 2 ] && [ -n "${STUB_LABELS_2+x}" ]; then
    printf '%s\n' "$STUB_LABELS_2"
  else
    printf '%s\n' "${STUB_LABELS:-}"
  fi
  exit 0
fi
if [[ $url == *"/jobs"* ]]; then
  id=${url#*runs/}
  id=${id%%/*}
  n=$(grep -c "runs/${id}/jobs" "${STUB_LOG}" || true)
  if [ -f "${STUB_DIR}/jobs-${id}-${n}" ]; then
    cat "${STUB_DIR}/jobs-${id}-${n}"
  elif [ -f "${STUB_DIR}/jobs-${id}" ]; then
    cat "${STUB_DIR}/jobs-${id}"
  fi
  exit 0
fi
if [[ $url == *"/workflows/ci.yml/runs"* ]]; then
  [ -f "${STUB_DIR}/runs" ] && cat "${STUB_DIR}/runs"
  exit 0
fi
if [[ $url == *"/workflows/"* ]]; then
  echo "unexpected workflow url: $url" >&2
  exit 2
fi
echo "unexpected gh url: $url" >&2
exit 2
EOF
chmod +x "$bin/git" "$bin/grep" "$bin/gh"

export STUB_LOG=$log STUB_GIT_LOG=$work/git.log STUB_DIR=$work/stub
export PATH="$bin:$PATH"
# The git, grep and gh stubs are child processes. Assignments below must export.
set -a
export POLL_SECONDS=0 WAIT_SECONDS=60
export REPO=kitimark/mitos PR=165 BASE_REF=main HEAD_SHA=$sha RUN_ID=100
export EVENT_ACTION=synchronize

reset() {
  : >"$log"
  : >"$work/git.log"
  rm -rf "$work/stub"
  mkdir -p "$work/stub"
  unset STUB_GIT_STATUS STUB_GIT_FILE STUB_GREP_STATUS STUB_GREP_EMPTY
  unset STUB_LABELS STUB_LABELS_2 STUB_LABELS_STATUS
}

spec_diff() { printf 'core/Challenge/A.lean\0' >"$work/diff"; export STUB_GIT_FILE=$work/diff; }
readme_diff() { printf 'README.md\0' >"$work/diff"; export STUB_GIT_FILE=$work/diff; }

prove_success() { printf 'prove\tcompleted\tsuccess\n' >"$work/stub/jobs-100"; }
checks_and_prove() {
  local id=$1 conclusion=$2
  printf 'checks\tcompleted\tsuccess\nprove\tcompleted\t%s\n' "$conclusion" >"$work/stub/jobs-$id"
}

run_cmd() {
  local expect=$1 title=$2
  shift 2
  local st
  set +e
  env "$@" "$script" "${cmd:-aggregate}" >"$work/out" 2>"$work/err"
  st=$?
  set -e
  unset STUB_GREP_STATUS STUB_GREP_EMPTY
  if [ "$expect" = 0 ]; then
    [ "$st" -eq 0 ] || fail "$title exited $st: $(cat "$work/err")"
  else
    [ "$st" -ne 0 ] || fail "$title exited 0: $(cat "$work/out")"
  fi
}

# The caller's shell has no pipefail. One direct bash -e invocation too.
reset
readme_diff
cmd=check
set +e
EVENT_NAME=pull_request bash -e "$script" check >"$work/out" 2>"$work/err"
st=$?
set -e
[ "$st" -eq 0 ] || fail "bash -e check exited $st: $(cat "$work/err")"
[ ! -s "$log" ] || fail "a pull request with no spec path called gh"
ok "no spec path passes under bash -e, and labels are not read"

reset
spec_diff
STUB_GIT_STATUS=128
cmd=check
run_cmd 1 "git diff 128" EVENT_NAME=pull_request
grep -q 'git diff failed: 128' "$work/err" || fail "git's status was swallowed"
ok "git diff exiting 128 is red"

reset
spec_diff
STUB_GREP_STATUS=2
cmd=check
run_cmd 1 "grep status 2" EVENT_NAME=pull_request
grep -q 'grep failed: 2' "$work/err" || fail "grep status 2 was swallowed"
ok "grep exiting 2 is red"

reset
spec_diff
STUB_GREP_EMPTY=1
cmd=check
run_cmd 1 "grep empty match" EVENT_NAME=pull_request
grep -q 'printed nothing' "$work/err" || fail "an empty match was accepted"
ok "grep status 0 with empty stdout is red"

reset
export BASE_REF=main/../other
cmd=check
run_cmd 1 "base ref with dotdot" EVENT_NAME=pull_request
grep -q 'refusing base ref' "$work/err" || fail "a base ref with .. was accepted"
[ ! -s "$work/git.log" ] || fail "a refused base ref reached git"
export BASE_REF=main
ok "a base ref with .. fails before git"

reset
spec_diff
STUB_LABELS_STATUS=403
cmd=check
run_cmd 1 "labels 403" EVENT_NAME=pull_request
grep -q 'HTTP 403' "$work/err" || fail "HTTP 403 was not reported"
grep -q 'without the spec-approved label' "$work/err" && fail "HTTP 403 became a missing label"
ok "a labels HTTP 403 is red"

reset
spec_diff
STUB_LABELS=needs-rebase
cmd=check
run_cmd 1 "wrong label" EVENT_NAME=pull_request
grep -q 'without the spec-approved label' "$work/err" || fail "a wrong label passed"
ok "a wrong label is red"

reset
spec_diff
STUB_LABELS=spec-approved-extra
cmd=check
run_cmd 1 "spec-approved-extra" EVENT_NAME=pull_request
grep -q 'without the spec-approved label' "$work/err" || fail "spec-approved-extra matched"
ok "spec-approved-extra does not match"

reset
spec_diff
STUB_LABELS=$'follow-up\nspec-approved'
cmd=check
run_cmd 0 "exact spec-approved" EVENT_NAME=pull_request
ok "an exact spec-approved line passes"

reset
printf 'core/Challenge/a\377.lean\0' >"$work/diff"
STUB_GIT_FILE=$work/diff
STUB_LABELS=spec-approved
cmd=check
run_cmd 0 "non-utf8 spec path" EVENT_NAME=pull_request
grep -q '/labels' "$log" || fail "the non-utf8 path was not found"
ok "a non-UTF-8 path under core/Challenge is caught"

reset
cmd=check
run_cmd 0 "push check" EVENT_NAME=push
[ ! -s "$log" ] || fail "a push called gh during check"
ok "a push does not call the labels API"

# aggregate: this run, prove succeeds, no spec path, so no labels call.
reset
readme_diff
prove_success
cmd=aggregate
run_cmd 0 "push aggregate" EVENT_NAME=push
grep -q '/labels' "$log" && fail "a push aggregate called the labels API"
grep -q 'workflows/ci.yml' "$log" && fail "a push looked up other runs"
grep -q "prove succeeded on run 100" "$work/out" || fail "the push did not name the run"
ok "a push waits on this run and does not read labels"

reset
readme_diff
printf 'prove\tin_progress\t\n' >"$work/stub/jobs-100-1"
printf 'prove\tin_progress\t\n' >"$work/stub/jobs-100-2"
printf 'prove\tcompleted\tsuccess\n' >"$work/stub/jobs-100-3"
cmd=aggregate
run_cmd 0 "prove on the third poll" EVENT_NAME=pull_request EVENT_ACTION=synchronize
ok "this run lists prove from the third poll"

reset
readme_diff
printf '200\tin_progress\t\n' >"$work/stub/runs"
printf 'checks\tin_progress\t\nprove\tin_progress\t\n' >"$work/stub/jobs-200-1"
printf 'checks\tin_progress\t\nprove\tin_progress\t\n' >"$work/stub/jobs-200-2"
printf 'checks\tcompleted\tsuccess\nprove\tcompleted\tsuccess\n' >"$work/stub/jobs-200-3"
cmd=aggregate
run_cmd 0 "label run third poll" EVENT_NAME=pull_request EVENT_ACTION=labeled
grep -q 'prove succeeded on run 200' "$work/out" || fail "the label run did not name run 200"
grep -q 'workflows/ci.yml' "$log" || fail "the label run did not query ci.yml"
grep -E 'workflows/[^c]|workflows/c[^i]' "$log" && fail "a workflow other than ci.yml was queried"
ok "a label run lists prove from the third poll of the other ci run"

reset
spec_diff
STUB_LABELS=spec-approved
STUB_LABELS_2=needs-rebase
printf 'prove\tin_progress\t\n' >"$work/stub/jobs-100-1"
printf 'prove\tcompleted\tsuccess\n' >"$work/stub/jobs-100-2"
cmd=aggregate
run_cmd 1 "label removed on the second check" EVENT_NAME=pull_request EVENT_ACTION=synchronize
grep -q 'without the spec-approved label' "$work/err" || fail "the second check did not see the removal"
ok "a label removed while prove runs turns this gate red"

reset
readme_diff
printf 'checks\tcompleted\tskipped\nprove\tcompleted\tskipped\n' >"$work/stub/jobs-300"
printf '300\tcompleted\tsuccess\n' >"$work/stub/runs"
cmd=aggregate
run_cmd 1 "only skipped prove" EVENT_NAME=pull_request EVENT_ACTION=labeled
grep -q 'no ci run' "$work/err" || fail "only skipped prove runs were accepted"
ok "only skipped prove runs are red"

reset
readme_diff
printf 'checks\tcompleted\tskipped\nprove\tcompleted\tskipped\n' >"$work/stub/jobs-400"
checks_and_prove 300 success
printf '400\tcompleted\tsuccess\n300\tcompleted\tsuccess\n' >"$work/stub/runs"
cmd=aggregate
run_cmd 0 "skipped plus older success" EVENT_NAME=pull_request EVENT_ACTION=unlabeled
grep -q 'prove succeeded on run 300' "$work/out" || fail "the older success was not the one kept"
ok "a label run is passed over for an older prove success"

reset
readme_diff
checks_and_prove 400 failure
checks_and_prove 300 success
printf '400\tcompleted\tsuccess\n300\tcompleted\tsuccess\n' >"$work/stub/runs"
cmd=aggregate
run_cmd 1 "newer failure" EVENT_NAME=pull_request EVENT_ACTION=labeled
grep -q 'prove on run 400 concluded failure' "$work/err" || fail "the newer failure was not named"
grep -q 'run 300' "$work/out" && fail "an older success hid a newer failure"
ok "a newer prove failure is red"

reset
readme_diff
printf 'prove\tcompleted\tcancelled\n' >"$work/stub/jobs-100"
cmd=aggregate
run_cmd 1 "prove cancelled" EVENT_NAME=pull_request EVENT_ACTION=synchronize
grep -q 'concluded cancelled' "$work/err" || fail "a cancelled prove was not named"
ok "a cancelled prove is red"

reset
readme_diff
printf 'prove\tin_progress\t\n' >"$work/stub/jobs-100"
cmd=aggregate
run_cmd 1 "prove never finishes" EVENT_NAME=pull_request EVENT_ACTION=opened WAIT_SECONDS=0
grep -q 'still pending at the bound' "$work/err" || fail "the wait bound was not hit"
ok "a prove that never finishes hits the wait bound"

reset
readme_diff
printf '200\tcompleted\tsuccess\n' >"$work/stub/runs"
printf 'checks\tcompleted\tsuccess\n' >"$work/stub/jobs-200"
cmd=aggregate
run_cmd 1 "run completed with no prove" EVENT_NAME=pull_request EVENT_ACTION=labeled
grep -q 'completed with no prove' "$work/err" || fail "a missing prove was accepted"
ok "a completed run with no prove is red"

# Gate's permissions are the three reads, and the job cannot be skipped.
awk '
  /^  gate:$/ { g = 1; next }
  /^  [a-z0-9-]+:$/ { g = 0 }
  g && /^    permissions:$/ { p = 1; next }
  g && p && /^    [a-z]/ { p = 0 }
  g && p { gsub(/^      /, ""); print }
' "$root/.github/workflows/ci.yml" >"$work/perms"
expect=$'contents: read\npull-requests: read\nactions: read'
[ "$(cat "$work/perms")" = "$expect" ] || fail "gate permissions are [$(cat "$work/perms")]"
ok "gate permissions are contents, pull-requests and actions read"

echo "ci-trust: done"
