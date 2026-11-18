#!/usr/bin/env bash
# shellcheck disable=SC2016
# Usage: .github/scripts/land-apply.sh <owner/name> <dir>
# land.yml's apply: on decide's planned merge, reads the pull request and its conversation again
# with GH_TOKEN, then makes the one pinned rebase-merge with LAND_MERGE_TOKEN (amendment #178,
# section 4). Env: LAND_MERGE, GITHUB_RUN_ATTEMPT, GITHUB_REPOSITORY_OWNER,
# GITHUB_REPOSITORY_OWNER_ID, GH_TOKEN, LAND_MERGE_TOKEN, LAND_PR, LAND_HEAD, LAND_APPROVAL,
# LAND_DIGEST, LAND_REQUIRES_SPEC. Writes <dir>/outcome.json, one line, and `outcome=<that line>` to $GITHUB_OUTPUT:
#   {"kind":"stopped","why":"off|attempt|input|read|pr|label|digest|approval"}
#   {"kind":"refused","status":"405|409"}   {"kind":"merged","main":"<40 hex>"}
#   {"kind":"failed","status":"<3 digits>|none"}
# Exit 0: an outcome was written. Exit 1: none could be. Exit 2: usage.
set -u
die() { printf 'land-apply: %s\n' "$1" >&2; exit 2; }
[ $# = 2 ] || die "usage: land-apply.sh <owner/name> <dir>"
repo=$1 out=$2
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
for tool in gh jq timeout sha256sum sed; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
digester=${LAND_DIGEST_SCRIPT:-$(dirname "$0")/land-digest.sh}
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"

outcome() {
  local line
  line=$(jq -cn "$@") || exit 1
  printf '%s\n' "$line" >"$out/outcome.json" || exit 1
  [ -z "${GITHUB_OUTPUT:-}" ] || printf 'outcome=%s\n' "$line" >>"$GITHUB_OUTPUT" || exit 1
  printf 'land-apply: %s\n' "$line"
  exit 0
}
stop() { outcome --arg why "$1" '{kind: "stopped", why: $why}'; }
read_to() { timeout -k 5 120 gh api "$2" >"$out/$1.json" 2>"$out/$1.err" </dev/null; }
pages_to() { timeout -k 5 120 gh api --paginate --slurp "$2" >"$out/$1.json" 2>"$out/$1.err" </dev/null; }

[ "${LAND_MERGE:-}" = on ] || stop off
[ "${GITHUB_RUN_ATTEMPT:-}" = 1 ] || stop attempt
pr=${LAND_PR:-} head=${LAND_HEAD:-} approval=${LAND_APPROVAL:-} digest=${LAND_DIGEST:-}
requires_spec=${LAND_REQUIRES_SPEC:-}
owner=${GITHUB_REPOSITORY_OWNER:-} owner_id=${GITHUB_REPOSITORY_OWNER_ID:-}
[[ $pr =~ ^[1-9][0-9]{0,6}$ && $head =~ ^[0-9a-f]{40}$ && $approval =~ ^[1-9][0-9]{0,19}$ &&
  $digest =~ ^[0-9a-f]{64}$ && $owner =~ ^[A-Za-z0-9-]{1,39}$ && $owner_id =~ ^[1-9][0-9]{0,19}$ &&
  ($requires_spec = true || $requires_spec = false) && $repo == "$owner"/* && -n ${GH_TOKEN:-} && -n ${LAND_MERGE_TOKEN:-} ]] || stop input
read_to pr "repos/$repo/pulls/$pr" || stop read
jq -e --arg h "$head" --arg r "$repo" --argjson n "$pr" '.number == $n and .state == "open"
  and .draft == false and .merged == false and .head.sha == $h and .base.ref == "main"
  and .base.repo.full_name == $r and .head.repo.full_name == $r' "$out/pr.json" >/dev/null 2>&1 \
  || stop pr
if [ "$requires_spec" = true ]; then
  jq -e '.labels | type == "array" and any(.[]; .name == "spec-approved")' "$out/pr.json" \
    >/dev/null 2>&1 || stop label
fi
pages_to comments "repos/$repo/issues/$pr/comments?per_page=100" || stop read
pages_to review-comments "repos/$repo/pulls/$pr/comments?per_page=100" || stop read
pages_to reviews "repos/$repo/pulls/$pr/reviews?per_page=100" || stop read
now=$("$digester" "$out/comments.json" "$out/review-comments.json" "$out/reviews.json") || stop read
[ "$now" = "$digest" ] || stop digest
jq -e --argjson id "$approval" --arg o "$owner" --argjson oid "$owner_id" \
  '[.[][] | select(.id == $id)] | length == 1 and (.[0] | .user.login == $o and .user.id == $oid
    and .user.type == "User" and .performed_via_github_app == null and .created_at == .updated_at)' \
  "$out/comments.json" >/dev/null 2>&1 || stop approval
GH_TOKEN=$LAND_MERGE_TOKEN timeout -k 5 120 gh api -X PUT "repos/$repo/pulls/$pr/merge" \
  -f merge_method=rebase -f "sha=$head" >"$out/merge.json" 2>"$out/merge.err" </dev/null
code=$?
if [ "$code" = 0 ]; then
  main=$(jq -er 'select(.merged == true) | .sha' "$out/merge.json" 2>/dev/null) \
    && [[ $main =~ ^[0-9a-f]{40}$ ]] && outcome --arg m "$main" '{kind: "merged", main: $m}'
  outcome '{kind: "failed", status: "200"}'
fi
status=$(sed -n 's/.*(HTTP \([0-9][0-9][0-9]\))$/\1/p' "$out/merge.err" | tail -n 1)
case $status in
  405 | 409) outcome --arg s "$status" '{kind: "refused", status: $s}' ;;
  [0-9][0-9][0-9]) outcome --arg s "$status" '{kind: "failed", status: $s}' ;;
esac
if read_to after "repos/$repo/pulls/$pr" &&
  main=$(jq -er --arg h "$head" 'select(.merged == true and .head.sha == $h) | .merge_commit_sha' \
    "$out/after.json" 2>/dev/null) && [[ $main =~ ^[0-9a-f]{40}$ ]]; then
  outcome --arg m "$main" '{kind: "merged", main: $m}'
fi
outcome '{kind: "failed", status: "none"}'
