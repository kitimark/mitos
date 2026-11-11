#!/usr/bin/env bash
# Remove needs-rebase when the pull request's base commit is an ancestor of its
# head. That is the same condition as `git merge-base --is-ancestor` in
# rebase-prs.sh: the compare API reports it as status "ahead" or "identical"
# with behind_by 0.
#
# Called from clear-needs-rebase.yml on pull_request_target. The workflow checks
# out the default branch, never the pull request head, and this script only
# calls the API. It does not fetch or run the head.
#
# Reads the event from GITHUB_EVENT_PATH (set by Actions). The head sha there
# selects which push this run is for. The base branch and the labels come from
# a fresh read of the pull request, so a later push is left for its own run.
# The compare uses the branch name, not pull_request.base.sha: that sha stays
# at the last update, so a head that contains it can look ahead of a main that
# has since moved.
set -euo pipefail

event=${GITHUB_EVENT_PATH:?}
repo=$(jq -er '.repository.full_name' "$event")
pr=$(jq -er '.pull_request.number' "$event")
head_want=$(jq -er '.pull_request.head.sha' "$event")
base_ref_want=${BASE_REF:-main}

[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "repository is not owner/name" >&2; exit 1; }
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "pull request number is not a number" >&2; exit 1; }
[[ "$head_want" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "head sha is not a commit" >&2; exit 1; }
[[ "$base_ref_want" =~ ^[A-Za-z0-9._/-]+$ && "$base_ref_want" != *..* && "$base_ref_want" != -* ]] \
  || { echo "BASE_REF is not a branch name" >&2; exit 1; }
head_want=$(printf '%s' "$head_want" | tr '[:upper:]' '[:lower:]')

pr_json=$(gh api "repos/$repo/pulls/$pr")
live_base_ref=$(jq -er '.base.ref' <<<"$pr_json")
live_head_sha=$(jq -er '.head.sha' <<<"$pr_json")
live_head_repo=$(jq -r '.head.repo.full_name // empty' <<<"$pr_json")
has=$(jq -r '([.labels[].name] | index("needs-rebase")) != null' <<<"$pr_json")

[[ "$live_head_sha" =~ ^[0-9a-fA-F]{40}$ ]] || { echo "head sha from the API is not a commit" >&2; exit 1; }
live_head_sha=$(printf '%s' "$live_head_sha" | tr '[:upper:]' '[:lower:]')

if [ "$live_head_repo" != "$repo" ]; then
  echo "#$pr is from ${live_head_repo:-another repository}; left unchanged"
  exit 0
fi
if [ "$live_base_ref" != "$base_ref_want" ]; then
  echo "#$pr targets $live_base_ref; left unchanged"
  exit 0
fi
if [ "$live_head_sha" != "$head_want" ]; then
  echo "#$pr moved from $head_want to $live_head_sha; left for the later run"
  exit 0
fi
if [ "$has" != true ]; then
  echo "#$pr has no needs-rebase label"
  exit 0
fi

cmp=$(gh api "repos/$repo/compare/${base_ref_want}...${live_head_sha}")
status=$(jq -er '.status' <<<"$cmp")
behind=$(jq -er '.behind_by' <<<"$cmp")
[[ "$behind" =~ ^[0-9]+$ ]] || { echo "#$pr: compare behind_by is not a number" >&2; exit 1; }

# behind_by 0 and ahead/identical is `git merge-base --is-ancestor base head`
# for the current tip of the base branch. Any other status keeps the label.
# An unknown status fails closed. gh removes that one label and leaves every
# other label in place.
if [ "$behind" -eq 0 ] && { [ "$status" = ahead ] || [ "$status" = identical ]; }; then
  if err=$(gh pr edit "$pr" --repo "$repo" --remove-label needs-rebase 2>&1); then
    echo "#$pr: $status of $base_ref_want; removed needs-rebase"
    exit 0
  fi
  if grep -Eqi "needs-rebase' not found|label does not exist" <<<"$err"; then
    echo "#$pr: needs-rebase was already absent"
    exit 0
  fi
  printf '%s\n' "$err" >&2
  echo "#$pr: could not remove needs-rebase" >&2
  exit 1
fi

if [ "$status" = behind ] || [ "$status" = diverged ]; then
  echo "#$pr: $status of $base_ref_want; kept needs-rebase"
  exit 0
fi

echo "#$pr: unexpected compare status $status (behind_by $behind) of $base_ref_want" >&2
exit 1
