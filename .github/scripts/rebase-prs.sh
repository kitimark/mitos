#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-main}"
git config user.name "mitos-pr-updater"
git config user.email "mitos-pr-updater@users.noreply.github.com"
git fetch -q origin "$BASE"
gh label create needs-rebase --color FBCA04 \
  --description "Could not be rebased onto $BASE automatically" >/dev/null 2>&1 || true

# A GitHub stack of pull requests is rebased as a whole, and a push from here to one of its
# branches would break its linear history. GitHub rebases a stack only when its bottom PR merges;
# when `$BASE` moves ahead, the stack's owner rebases it (Rebase stack, or `gh stack rebase` and
# `gh stack push`). So no PR in a stack is rebased or labelled `needs-rebase` here.
# `GET repos/{owner}/{repo}/stacks` lists every stack with its `pull_requests`. A pull request
# object also carries a `stack` field, but only for members and `gh pr list --json` cannot select
# it, so the stack list is the source. Every PR number in any stack is skipped, whatever the
# stack's `open` or the PR's `state` say: `gh pr list --state open` already keeps only open PRs,
# and a filter on those fields would skip nothing if they changed. `--slurp` gathers the pages
# into one array, and a page without a body breaks it. The run goes on only if there is at least
# one page and every page is an array of stacks whose `pull_requests` are objects with an integer
# `number`. Anything else rebases nothing: skipping is safe, a rebase that breaks a stack is not.
if ! stacked=$(gh api --paginate --slurp -H "X-GitHub-Api-Version: 2026-03-10" \
    "repos/{owner}/{repo}/stacks?per_page=100" \
    | jq -s -c 'def int: type == "number" and . == floor;
        def pr: type == "object" and (.number | int);
        def stack: type == "object" and (.pull_requests | type == "array" and all(.[]; pr));
        def page: type == "array" and all(.[]; stack);
        if length == 1 and (.[0] | type == "array" and length > 0 and all(.[]; page))
        then [.[0][][].pull_requests[].number] else error("unexpected stack list") end'); then
  echo "::error::could not read the stack list; no PR was rebased"
  exit 1
fi
echo "PRs in a stack, skipped: $stacked"

# `--base` and the `baseRefName` test both leave out a PR that targets another branch, which is a
# hand-made stack: its parent branch is not `$BASE`, so it is not ours to rebase onto `$BASE`.
prs=$(gh pr list --base "$BASE" --state open --limit 100 \
  --json number,headRefName,headRefOid,baseRefName,isCrossRepository,isDraft,labels \
  | jq -c --arg base "$BASE" --argjson stacked "$stacked" \
      '.[] | select((.isCrossRepository or .isDraft) | not)
           | select(.baseRefName == $base)
           | select([.number] | inside($stacked) | not)
           | select([.labels[].name] | index("no-auto-rebase") | not)
           | {number, ref: .headRefName, oid: .headRefOid,
              flagged: ([.labels[].name] | index("needs-rebase") != null)}')

status=0
flag() {
  if ! gh pr edit "$1" --add-label needs-rebase >/dev/null 2>&1; then
    echo "  could not label #$1 needs-rebase"; status=1
  fi
  if ! gh pr comment "$1" --body "$2" >/dev/null 2>&1; then
    echo "  could not comment on #$1"; status=1
  fi
}

while read -r pr; do
  [ -n "$pr" ] || continue
  n=$(jq -r .number <<<"$pr"); ref=$(jq -r .ref <<<"$pr"); oid=$(jq -r .oid <<<"$pr")
  flagged=$(jq -r .flagged <<<"$pr")
  git fetch -q origin "$oid"
  if git merge-base --is-ancestor "origin/$BASE" "$oid"; then
    echo "#$n ($ref): up to date"
    continue
  fi
  git checkout -q --detach "$oid"
  if git rebase -q "origin/$BASE" >/dev/null 2>&1; then
    if ! out=$(git push -q --force-with-lease="refs/heads/$ref:$oid" origin "HEAD:refs/heads/$ref" 2>&1); then
      if grep -q "stale info" <<<"$out"; then
        echo "#$n ($ref): branch moved during this run; left for the next run"
      else
        echo "#$n ($ref): push refused; labelled needs-rebase"
        echo "$out"
        [ "$flagged" = true ] || flag "$n" "The rebase onto \`$BASE\` succeeded but the push was refused, so this branch was left unchanged and labelled \`needs-rebase\`. The run log of \`update-prs.yml\` has the reason."
      fi
      continue
    fi
    echo "#$n ($ref): rebased $oid -> $(git rev-parse HEAD)"
    if [ "$flagged" = true ] && ! gh pr edit "$n" --remove-label needs-rebase >/dev/null 2>&1; then
      echo "  could not remove needs-rebase from #$n"; status=1
    fi
  else
    git rebase --abort
    echo "#$n ($ref): conflicts with $BASE; labelled needs-rebase"
    [ "$flagged" = true ] || flag "$n" "This branch no longer rebases cleanly onto \`$BASE\`. It was left unchanged and labelled \`needs-rebase\`."
  fi
done <<<"$prs"
exit "$status"
