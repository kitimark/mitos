#!/usr/bin/env bash
# Usage: .github/scripts/land-report.sh <owner/name>
# land.yml's report: posts at most one comment per pull request, an answer that differs from the
# newest <!-- land-report --> comment github-actions posted there, or that answers a /land the owner
# typed after that comment (amendment #178, section 4; #520). Env: GH_TOKEN, GITHUB_SERVER_URL,
# GITHUB_RUN_ID, LAND_ANSWERS (decide's list of {pr, line, body, land}, where land is the id of the
# comment with the owner's newest /land, or null), LAND_PR and LAND_HEAD (decide's planned merge,
# empty if none), LAND_APPLY_RESULT and LAND_APPLIED (apply's job result and outcome).
# Exit 0: every answer was read and posted as needed. Exit 1: a read or a post failed, or the merge
# call failed. Exit 2: usage or malformed input, and nothing was called.
set -u
marker='<!-- land-report -->'
die() { printf 'land-report: %s\n' "$1" >&2; exit 2; }
[ $# = 1 ] || die "usage: land-report.sh <owner/name>"
repo=$1
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
for tool in gh jq timeout mktemp; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
[[ ${GITHUB_RUN_ID:-} =~ ^[1-9][0-9]{0,19}$ ]] || die "GITHUB_RUN_ID is not a run id"
run_link="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/$GITHUB_RUN_ID"
pr=${LAND_PR:-} head=${LAND_HEAD:-}
[ -z "$pr" ] || [[ $pr =~ ^[1-9][0-9]{0,6}$ && $head =~ ^[0-9a-f]{40}$ ]] \
  || die "the planned merge is not of its shape"
answers=$(jq -ce --arg m "$marker" --arg p "$pr" 'if type == "array" and length <= 100 and all(.[];
    type == "object" and keys == ["body", "land", "line", "pr"] and (.pr | type == "number" and . >= 1
    and floor == .) and (.pr | tostring) != $p and (.land | . == null or (type == "number"
    and . >= 1 and . <= 9007199254740991 and floor == .)) and (.line | type == "string" and length > 0
    and (contains("\n") | not)) and (.body | type == "string" and (contains("@") | not))
    and (.line as $l | .body == $m + "\n" + $l or (.body | startswith($m + "\n" + $l + "\n"))))
    and ([.[].pr] | length == (unique | length)) then sort_by(.pr) else error("bad") end' \
  <<<"${LAND_ANSWERS:-[]}" 2>/dev/null) || die "the answers are not of their shape"

planned='' failed=0
if [ -n "$pr" ]; then
  kind=$(jq -r '.kind // ""' <<<"${LAND_APPLIED:-null}" 2>/dev/null) || kind=
  again="Comment /land $head again to go on."
  case ${LAND_APPLY_RESULT:-}/$kind in
    success/merged)
      main=$(jq -r '.main' <<<"$LAND_APPLIED")
      [[ $main =~ ^[0-9a-f]{40}$ ]] && planned="Landed $head on your /land. main is $main." ;;
    success/failed)
      status=$(jq -r '.status' <<<"$LAND_APPLIED")
      [[ $status =~ ^([0-9]{3}|none)$ ]] || status=none
      planned="Merge call failed: $status."$'\n\n'"$run_link" failed=1 ;;
    success/stopped)
      case $(jq -r '.why' <<<"$LAND_APPLIED") in
        label) planned="Not merged yet at $head: the spec-approved label changed after the decision. $again" ;;
        digest) planned="Not merged yet at $head: the conversation changed after the decision. $again" ;;
        approval) planned="Not merged yet at $head: the approval is not your unedited comment. $again" ;;
        read) planned="Not merged yet at $head: a read failed. $again"$'\n\n'"$run_link" ;;
        off) planned="Not merged: the merge switch is off." ;;
      esac ;;
    failure/*) planned="Merge call failed: no outcome."$'\n\n'"$run_link" failed=1 ;;
  esac
fi

tmp=$(mktemp -d) || die "cannot make a scratch folder"
trap 'rm -rf -- "$tmp"' EXIT
# A comment's id grows with the time it was posted.
post_due() {
  timeout -k 5 120 gh api --paginate --slurp "repos/$repo/issues/$1/comments?per_page=100" \
    >"$tmp/c.json" 2>/dev/null </dev/null || return 1
  jq -e 'type == "array" and all(.[]; type == "array")' "$tmp/c.json" >/dev/null 2>&1 || return 1
  jq -e --arg m "$marker" --arg b "$2" --argjson land "$3" \
    '[.[][] | select(.user.login == "github-actions[bot]"
      and .user.type == "Bot" and .performed_via_github_app.slug == "github-actions"
      and (.body | type == "string" and startswith($m + "\n")))] | max_by(.id)
      | .body == $b and ($land == null or ((.id | type) == "number" and .id > $land))' \
    "$tmp/c.json" >/dev/null 2>&1 && return 0
  timeout -k 5 120 gh api -X POST "repos/$repo/issues/$1/comments" -f "body=$2" \
    >/dev/null 2>&1 </dev/null
}
problems=0
while IFS= read -r item; do
  n=$(jq -r .pr <<<"$item") body=$(jq -r .body <<<"$item") land=$(jq -c .land <<<"$item")
  post_due "$n" "$body" "$land" \
    || { printf 'land-report: #%s was not answered\n' "$n" >&2; problems=1; }
done < <(jq -c '.[]' <<<"$answers")
if [ -n "$planned" ]; then
  post_due "$pr" "$marker"$'\n'"$planned" null \
    || { printf 'land-report: #%s was not answered\n' "$pr" >&2; problems=1; }
fi
[ "$problems" = 0 ] && [ "$failed" = 0 ]
