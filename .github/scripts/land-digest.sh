#!/usr/bin/env bash
# Usage: .github/scripts/land-digest.sh <comments.json> <review-comments.json> <reviews.json>
# Each file is one read of its route with `gh api --paginate --slurp`: a non-empty list of pages,
# each a list. Prints the SHA-256, 64 hex digits, of the pull request's conversation as land.yml's
# decide and apply read it. Exit 1: a file is missing or not of its route's shape. Exit 2: usage.
set -u -o pipefail
die() { printf 'land-digest: %s\n' "$1" >&2; exit 2; }
[ $# = 3 ] || die "usage: land-digest.sh <comments.json> <review-comments.json> <reviews.json>"
for tool in jq sha256sum; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
# shellcheck disable=SC2016
doc=$(jq -ncS --slurpfile c "$1" --slurpfile rc "$2" --slurpfile rv "$3" '
  def one: if length == 1 then .[0] else error("not one read") end;
  def items: if type == "array" and length > 0 and all(.[]; type == "array") then [.[][]]
    else error("not the pages of a list") end;
  def t: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
    then . else error("not a time") end;
  def n: if type == "number" and . >= 1 and floor == . then . else error("not an id") end;
  def who: [(.user.login | if type == "string" then . else error("no login") end),
    (.performed_via_github_app.slug // null)];
  {issue: [$c | one | items[] | [(.id | n)] + who +
     [(.created_at | t), (.updated_at | t), (.body // "")]] | unique,
   reviewComment: [$rc | one | items[] | [(.id | n), (.pull_request_review_id | n)] + who +
     [(.created_at | t), (.updated_at | t), (.body // "")]] | unique,
   review: [$rv | one | items[] | [(.id | n)] + who +
     [.state, (.commit_id // ""), (.submitted_at // ""), (.body // "")]] | unique}' 2>/dev/null) \
  || { printf 'land-digest: a read is not of its route'"'"'s shape\n' >&2; exit 1; }
printf '%s' "$doc" | sha256sum | cut -c1-64
