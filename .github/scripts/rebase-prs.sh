#!/usr/bin/env bash
# Rebase every open, same-repository, non-draft PR based on $BASE onto it. A PR that does not
# rebase cleanly is left untouched and labelled `needs-rebase`. Label a PR `no-auto-rebase` to
# opt out. Needs GH_TOKEN (gh) and a checkout whose pushes use a token that starts CI
# (a GitHub App installation token, not GITHUB_TOKEN). A failed label or comment is reported
# and fails the run at the end, after every PR has been tried.
set -euo pipefail
BASE="${BASE:-main}"
git config user.name "mitos-pr-updater"
git config user.email "mitos-pr-updater@users.noreply.github.com"
git fetch -q origin "$BASE"
gh label create needs-rebase --color FBCA04 \
  --description "Could not be rebased onto $BASE automatically" >/dev/null 2>&1 || true

prs=$(gh pr list --base "$BASE" --state open --limit 100 \
  --json number,headRefName,headRefOid,isCrossRepository,isDraft,labels \
  | jq -c '.[] | select((.isCrossRepository or .isDraft) | not)
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
