#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-main}"
n=${PR_NUMBER:-}
# PR_NUMBER is a workflow_dispatch input. A refusal never prints it: the runner reads an output
# line that starts with `::` as a workflow command.
if ! [[ $n =~ ^[1-9][0-9]{0,6}$ ]]; then
  echo "::error::PR_NUMBER is not a pull request number; nothing was rebased"
  exit 1
fi
git config user.name "mitos-pr-updater"
git config user.email "mitos-pr-updater@users.noreply.github.com"
git fetch -q origin "$BASE"
gh label create needs-rebase --color FBCA04 \
  --description "Could not be rebased onto $BASE automatically" >/dev/null 2>&1 || true

refuse() {
  echo "::error::#$n $1; it was not rebased"
  exit 1
}

# A GitHub stack of pull requests is rebased as a whole, and a push from here to one of its
# branches would break its linear history. GitHub rebases a stack only when its bottom PR merges;
# when `$BASE` moves ahead, the stack's owner rebases it (Rebase stack, or `gh stack rebase` and
# `gh stack push`). So no PR in a stack is rebased or labelled `needs-rebase` here.
# `GET repos/{owner}/{repo}/stacks` lists every stack with its `pull_requests`. A pull request
# object also carries a `stack` field, but only for members, so a missing field cannot be told
# from a renamed one, and the stack list is the source.
every_member_of_every_stack() {
  jq -s -c 'def int: type == "number" and . == floor;
      def pr: type == "object" and (.number | int);
      def stack: type == "object" and (.pull_requests | type == "array" and all(.[]; pr));
      def page: type == "array" and all(.[]; stack);
      if length == 1 and (.[0] | type == "array" and length > 0 and all(.[]; page))
      then [.[0][][].pull_requests[].number] else error("unexpected stack list") end'
}
if ! stacked=$(gh api --paginate --slurp -H "X-GitHub-Api-Version: 2026-03-10" \
    "repos/{owner}/{repo}/stacks?per_page=100" | every_member_of_every_stack); then
  echo "::error::could not read the stack list; #$n was not rebased"
  exit 1
fi
echo "PRs in a stack: $stacked"

pull_request_fields() {
  jq -c --argjson n "$n" 'def text: type == "string" and length > 0;
      if type == "object" and .number == $n and (.state | text) and (.draft | type == "boolean")
          and (.base.ref | text) and (.base.repo.full_name | text) and (.head.ref | text)
          and (.head.sha | type == "string" and test("^[0-9a-f]{40}$"))
          and (.labels | type == "array" and all(.[]; type == "object" and (.name | text)))
      then {state, draft, base: .base.ref, ref: .head.ref, oid: .head.sha,
            fork: (.head.repo == null or (.head.repo.full_name != .base.repo.full_name)),
            labels: [.labels[].name]}
      else error("unexpected pull request") end'
}
if ! pr=$(gh api "repos/{owner}/{repo}/pulls/$n" | pull_request_fields); then
  echo "::error::could not read #$n; it was not rebased"
  exit 1
fi
has() { jq -e "$1" <<<"$pr" >/dev/null; }
has '.state == "open"' || refuse "is not open"
[ "$(jq -r .base <<<"$pr")" = "$BASE" ] || refuse "is not based on $BASE"
has '.fork | not' || refuse "comes from a fork"
has '.draft | not' || refuse "is a draft"
jq -e --argjson n "$n" 'all(.[]; . != $n)' <<<"$stacked" >/dev/null || refuse "is in a stack"
has '.labels | index("no-auto-rebase") | not' || refuse "has the no-auto-rebase label"
ref=$(jq -r .ref <<<"$pr"); oid=$(jq -r .oid <<<"$pr")
flagged=$(jq -r '.labels | index("needs-rebase") != null' <<<"$pr")

status=0
flag() {
  if ! gh pr edit "$1" --add-label needs-rebase >/dev/null 2>&1; then
    echo "  could not label #$1 needs-rebase"; status=1
  fi
  if ! gh pr comment "$1" --body "$2" >/dev/null 2>&1; then
    echo "  could not comment on #$1"; status=1
  fi
}

unflag_or_absent() {
  local err
  if err=$(gh pr edit "$1" --remove-label needs-rebase 2>&1); then
    return 0
  fi
  if grep -Eqi "needs-rebase' not found|label does not exist" <<<"$err"; then
    return 0
  fi
  echo "  could not remove needs-rebase from #$1"; status=1
}

git fetch -q origin "$oid"
if git merge-base --is-ancestor "origin/$BASE" "$oid"; then
  echo "#$n ($ref): up to date"
  if [ "$flagged" = true ]; then
    if ! live=$(gh api "repos/{owner}/{repo}/pulls/$n" --jq .head.sha); then
      echo "::error::could not read #$n again; needs-rebase was kept"
      exit 1
    fi
    if [ "$live" = "$oid" ]; then
      unflag_or_absent "$n"
    else
      echo "#$n ($ref): head moved during this run; needs-rebase was kept"
    fi
  fi
  exit "$status"
fi
git checkout -q --detach "$oid"
if git rebase -q "origin/$BASE" >/dev/null 2>&1; then
  if ! out=$(git push -q --force-with-lease="refs/heads/$ref:$oid" origin "HEAD:refs/heads/$ref" 2>&1); then
    if grep -q "stale info" <<<"$out"; then
      echo "::error::#$n ($ref): branch moved during this run; it was not rebased"
    else
      echo "::error::#$n ($ref): push refused; labelled needs-rebase"
      echo "$out"
      [ "$flagged" = true ] || flag "$n" "The rebase onto \`$BASE\` succeeded but the push was refused, so this branch was left unchanged and labelled \`needs-rebase\`. The run log of \`update-prs.yml\` has the reason."
    fi
    exit 1
  fi
  echo "#$n ($ref): rebased $oid -> $(git rev-parse HEAD)"
  if [ "$flagged" = true ]; then
    unflag_or_absent "$n"
  fi
else
  git rebase --abort
  echo "::error::#$n ($ref): conflicts with $BASE; labelled needs-rebase"
  [ "$flagged" = true ] || flag "$n" "This branch no longer rebases cleanly onto \`$BASE\`. It was left unchanged and labelled \`needs-rebase\`."
  exit 1
fi
exit "$status"
