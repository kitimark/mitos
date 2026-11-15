#!/usr/bin/env bash
# The spec-label rule and the wait for `prove`. This script sets its own
# flags: the step that calls it may be bash -e without pipefail.
#
# `check` is the label rule. On a push it returns 0 and does not read labels.
# On a pull request it writes `git diff --no-renames --name-only -z` to a file
# and fails if git does. Grep status 0 or 1 is a result; any other status
# fails, and status 0 with empty stdout fails. A spec path needs an exact
# `spec-approved` label from the API.
#
# `aggregate` runs `check`, waits until `prove` succeeded, then runs `check`
# again. A label removed during the corpus fails this run too.
set -euo pipefail

SPEC_RE='(^|/)(statements|models)\.lock$|^core/Challenge/|^core/comparator\.json$|^core/Mitos/Core(/|\.lean$|$)'
POLL_SECONDS=${POLL_SECONDS:-15}
WAIT_SECONDS=${WAIT_SECONDS:-1500}

die() { printf '%s\n' "$*" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

require_num() {
  [[ ${1:-} =~ ^[0-9]+$ ]] || die "refusing $2"
}

require_sha() {
  [[ ${1:-} =~ ^[0-9a-f]{40}$ ]] || die "refusing head sha"
}

require_repo() {
  [[ ${1:-} =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "refusing repo"
}

accept_base_ref() {
  [[ ${BASE_REF:-} =~ ^[A-Za-z0-9._/-]+$ ]] || die "refusing base ref"
  [[ $BASE_REF != *..* ]] || die "refusing base ref"
}

tsv_field() {
  printf '%s\n' "$1" | awk -F '\t' -v n="$2" -v c="$3" '$1 == n { v = $c } END { printf "%s", v }'
}

list_jobs() {
  require_num "$1" "run id"
  gh api --paginate --jq '.jobs[] | [.name, .status, (.conclusion // "")] | @tsv' \
    "repos/$REPO/actions/runs/$1/jobs?filter=latest"
}

list_runs() {
  gh api --paginate \
    --jq '.workflow_runs[] | [.id, .status, (.conclusion // "")] | @tsv' \
    "repos/$REPO/actions/workflows/ci.yml/runs?head_sha=${HEAD_SHA}&per_page=100"
}

check() {
  local gst st labels name approved
  [ "${EVENT_NAME:-}" = push ] && return 0
  [ "${EVENT_NAME:-}" = pull_request ] || die "unknown event ${EVENT_NAME:-}"
  require_repo "${REPO:-}"
  require_num "${PR:-}" "pull request number"
  accept_base_ref
  set +e
  git diff --no-renames --name-only -z "origin/${BASE_REF}...HEAD" >"$work/diff"
  gst=$?
  set -e
  [ "$gst" -eq 0 ] || die "git diff failed: $gst"
  set +e
  LC_ALL=C grep -zaE "$SPEC_RE" "$work/diff" >"$work/matches"
  st=$?
  set -e
  if [ "$st" -gt 1 ]; then
    die "grep failed: $st"
  fi
  if [ "$st" -eq 0 ] && [ ! -s "$work/matches" ]; then
    die "grep reported a match and printed nothing"
  fi
  [ "$st" -eq 0 ] || return 0
  if ! labels=$(gh api --paginate --jq '.[].name' "repos/$REPO/issues/$PR/labels"); then
    die "labels request failed"
  fi
  approved=0
  while IFS= read -r name || [ -n "$name" ]; do
    [ "$name" = spec-approved ] && approved=1
  done <<<"$labels"
  if [ "$approved" -ne 1 ]; then
    echo "These spec files changed without the spec-approved label:" >&2
    tr '\0' '\n' <"$work/matches" >&2
    exit 1
  fi
}

past_bound() { [ "$SECONDS" -ge "$deadline" ]; }

poll_this_run() {
  local jobs st co
  while true; do
    jobs=$(list_jobs "$RUN_ID") || die "could not list jobs of run $RUN_ID"
    st=$(tsv_field "$jobs" prove 2)
    co=$(tsv_field "$jobs" prove 3)
    if [ "$st" = completed ]; then
      [ "$co" = success ] || die "prove on run $RUN_ID concluded ${co:-unknown}"
      printf 'prove succeeded on run %s\n' "$RUN_ID"
      return 0
    fi
    if past_bound; then
      die "prove was still pending at the bound on run $RUN_ID"
    fi
    sleep "$POLL_SECONDS"
  done
}

poll_label_run() {
  local runs id status conclusion jobs st co cst cco found
  while true; do
    runs=$(list_runs) || die "could not list ci runs at $HEAD_SHA"
    found=
    # conclusion is read so a short line cannot slide into status.
    # shellcheck disable=SC2034
    while IFS=$'\t' read -r id status conclusion || [ -n "${id:-}" ]; do
      [ -n "${id:-}" ] || continue
      [ "$id" = "$RUN_ID" ] && continue
      jobs=$(list_jobs "$id") || die "could not list jobs of run $id"
      if [ -z "$jobs" ]; then
        if [ "$status" = completed ]; then
          die "run $id completed with no prove"
        fi
        found=pending
        break
      fi
      cst=$(tsv_field "$jobs" checks 2)
      cco=$(tsv_field "$jobs" checks 3)
      if [ "$cst" = completed ] && [ "$cco" = skipped ]; then
        continue
      fi
      if [ -z "$cst" ]; then
        if [ "$status" = completed ]; then
          die "run $id completed with no prove"
        fi
        found=pending
        break
      fi
      st=$(tsv_field "$jobs" prove 2)
      co=$(tsv_field "$jobs" prove 3)
      if [ "$st" = completed ]; then
        [ "$co" = success ] || die "prove on run $id concluded ${co:-unknown}"
        printf 'prove succeeded on run %s\n' "$id"
        return 0
      fi
      if [ -z "$st" ] && [ "$status" = completed ]; then
        die "run $id completed with no prove"
      fi
      found=$id
      break
    done <<<"$runs"
    if [ -z "$found" ]; then
      die "no ci run at $HEAD_SHA has a prove job"
    fi
    if past_bound; then
      if [ "$found" = pending ]; then
        die "prove was still pending at the bound"
      fi
      die "prove was still pending at the bound on run $found"
    fi
    sleep "$POLL_SECONDS"
  done
}

this_run() {
  [ "${EVENT_NAME:-}" = push ] && return 0
  [ "${EVENT_NAME:-}" = pull_request ] || return 1
  [ "${EVENT_ACTION:-}" != labeled ] && [ "${EVENT_ACTION:-}" != unlabeled ]
}

find_prove() {
  require_num "$POLL_SECONDS" "poll interval"
  require_num "$WAIT_SECONDS" "wait bound"
  require_repo "${REPO:-}"
  require_num "${RUN_ID:-}" "run id"
  require_sha "${HEAD_SHA:-}"
  deadline=$((SECONDS + WAIT_SECONDS))
  if this_run; then
    poll_this_run
  else
    poll_label_run
  fi
}

aggregate() {
  check
  find_prove
  check
}

cmd=${1:-}
case "$cmd" in
  check) check ;;
  aggregate) aggregate ;;
  *) die "usage: ci-trust.sh check|aggregate" ;;
esac
