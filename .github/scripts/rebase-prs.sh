#!/usr/bin/env bash
# Rebase every open, same-repository, non-draft PR based on $BASE onto it. A PR that does not
# rebase cleanly is left untouched and labelled `needs-rebase`. Label a PR `no-auto-rebase` to
# opt out. Needs GH_TOKEN (gh) and a checkout whose pushes use a token that triggers CI.
set -euo pipefail
BASE="${BASE:-main}"
git config user.name "mitos-pr-updater"
git config user.email "mitos-pr-updater@users.noreply.github.com"
git fetch -q origin "$BASE"

gh pr list --base "$BASE" --state open --limit 100 \
  --json number,headRefName,headRefOid,isCrossRepository,isDraft,labels \
  | jq -c '.[] | select((.isCrossRepository or .isDraft) | not)
               | select([.labels[].name] | index("no-auto-rebase") | not)
               | {number, ref: .headRefName, oid: .headRefOid,
                  flagged: ([.labels[].name] | index("needs-rebase") != null)}' \
  | while read -r pr; do
      n=$(jq -r .number <<<"$pr"); ref=$(jq -r .ref <<<"$pr"); oid=$(jq -r .oid <<<"$pr")
      flagged=$(jq -r .flagged <<<"$pr")
      git fetch -q origin "$oid"
      if git merge-base --is-ancestor "origin/$BASE" "$oid"; then
        echo "#$n ($ref): up to date"
        continue
      fi
      git checkout -q --detach "$oid"
      if git rebase -q "origin/$BASE" >/dev/null 2>&1; then
        if ! git push -q --force-with-lease="refs/heads/$ref:$oid" origin "HEAD:refs/heads/$ref"; then
          echo "#$n ($ref): branch moved during this run; left for the next run"
          continue
        fi
        echo "#$n ($ref): rebased $oid -> $(git rev-parse HEAD)"
        if [ "$flagged" = true ]; then gh pr edit "$n" --remove-label needs-rebase >/dev/null; fi
      else
        git rebase --abort
        echo "#$n ($ref): conflicts with $BASE; labelled needs-rebase"
        if [ "$flagged" != true ]; then
          gh pr edit "$n" --add-label needs-rebase >/dev/null
          gh pr comment "$n" --body "This branch no longer rebases cleanly onto \`$BASE\`. It was left unchanged and labelled \`needs-rebase\`." >/dev/null
        fi
      fi
    done
