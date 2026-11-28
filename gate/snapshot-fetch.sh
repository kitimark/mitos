#!/usr/bin/env bash
# Usage: gate/snapshot-fetch.sh <owner/name> <provenance-issue> <dir>
#
# Saves the REST reads that `mitos-gate snapshot <dir>` turns into the landing snapshot, one file
# per read, `<dir>/<read>.json`, through `gh api` only: REST, never GraphQL. A read that fails
# leaves no file, so the snapshot holds every pull request that needs it; a list is read with
# `--paginate --slurp`, so a list with a failed page leaves no file either. It prints one line on
# standard error per failed read and exits 0; a usage error exits 2.
set -u

die() { printf 'snapshot-fetch: %s\n' "$1" >&2; exit 2; }
[ $# = 3 ] || die "usage: gate/snapshot-fetch.sh <owner/name> <provenance-issue> <dir>"
repo=$1 issue=$2 out=$3
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
[[ $issue =~ ^[1-9][0-9]{0,6}$ ]] || die "<provenance-issue> is not an issue number"
for tool in gh jq timeout unzip mktemp sleep; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
wait_s=${SNAPSHOT_PROTECTION_WAIT:-60} poll_s=${SNAPSHOT_PROTECTION_POLL:-5}
[[ $wait_s =~ ^(0|[1-9][0-9]{0,3})$ ]] || die "SNAPSHOT_PROTECTION_WAIT is not a number of seconds"
[[ $poll_s =~ ^[1-9][0-9]{0,2}$ ]] || die "SNAPSHOT_PROTECTION_POLL is not a number of seconds"
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"

read_to() {
  local name=$1
  shift
  if timeout -k 5 120 gh api "$@" >"$out/$name.part" 2>/dev/null </dev/null; then
    mv -- "$out/$name.part" "$out/$name.json"
  else
    rm -f -- "$out/$name.part"
    printf 'snapshot-fetch: the read of %s failed\n' "$name" >&2
  fi
}
pages_to() {
  local name=$1
  shift
  read_to "$name" --paginate --slurp "$@"
}

get() {
  local file=$1
  shift
  timeout -k 5 120 gh api "$@" >"$file" 2>/dev/null </dev/null
}
stamp='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
# shellcheck disable=SC2016
ours='[.workflow_runs[] | select(type == "object"
  and .path == ".github/workflows/land-protection.yml" and .head_branch == "main"
  and .head_repository.full_name == $repo and .repository.full_name == $repo
  and (.event | IN("push", "workflow_run", "issue_comment", "workflow_dispatch"))
  and .head_sha == $main and (.id | type == "number") and (.run_attempt | type == "number"))]'
# shellcheck disable=SC2016
done_since='[.[] | select(.status == "completed" and .conclusion == "success"
  and (.updated_at | type == "string" and test($re)) and .updated_at >= $since)]'

protection_from() {
  local s=$1 main since pick seen='' id attempt name art deadline
  if ! main=$(jq -er '.commit.sha' "$out/main.json" 2>/dev/null) || [[ ! $main =~ ^[0-9a-f]{40}$ ]] \
    || [[ ! ${GITHUB_RUN_ID:-} =~ ^[1-9][0-9]{0,19}$ ]] \
    || ! get "$s/own.json" "repos/$repo/actions/runs/$GITHUB_RUN_ID" \
    || ! since=$(jq -er --arg re "$stamp" '.run_started_at | select(type == "string" and test($re))' \
      "$s/own.json" 2>/dev/null); then
    echo failed
    return 1
  fi
  deadline=$((SECONDS + wait_s))
  while :; do
    if ! get "$s/runs.json" \
      "repos/$repo/actions/workflows/land-protection.yml/runs?branch=main&exclude_pull_requests=true&per_page=30" \
      || ! jq -e '.workflow_runs | type == "array"' "$s/runs.json" >/dev/null 2>&1 \
      || ! pick=$(jq -r --arg repo "$repo" --arg main "$main" --arg since "$since" --arg re "$stamp" \
        "$ours | $done_since"' | first | select(.) | "\(.id) \(.run_attempt)"' "$s/runs.json" 2>/dev/null); then
      echo failed
      return 1
    fi
    if [ -n "$pick" ] && [ "$pick" != "$seen" ]; then
      seen=$pick
      read -r id attempt <<<"$pick"
      name=land-protection-$id-$attempt
      if [[ ! $id =~ ^[1-9][0-9]{0,19}$ || ! $attempt =~ ^[1-9][0-9]{0,4}$ ]] \
        || ! get "$s/artifacts.json" "repos/$repo/actions/runs/$id/artifacts?name=$name&per_page=100" \
        || ! art=$(jq -er --arg name "$name" --argjson id "$id" \
          '[.artifacts[] | select(.name == $name and .expired == false and .workflow_run.id == $id
            and (.size_in_bytes | type == "number" and . <= 1048576))]
           | if length == 1 then .[0].id else empty end' "$s/artifacts.json" 2>/dev/null) \
        || [[ ! $art =~ ^[1-9][0-9]{0,19}$ ]] \
        || ! get "$s/artifact.zip" "repos/$repo/actions/artifacts/$art/zip" \
        || ! unzip -p "$s/artifact.zip" read.json >"$s/read.json" 2>/dev/null \
        || ! jq -e --arg re "$stamp" 'type == "object" and (.read | type == "string" and test($re))
          and (.protection | type == "object")' "$s/read.json" >/dev/null 2>&1; then
        echo failed
        return 1
      fi
      if ! jq -e --arg repo "$repo" --argjson id "$id" --argjson attempt "$attempt" \
        '.v == 1 and .repo == $repo and .ref == "refs/heads/main" and .run == $id
          and .attempt == $attempt' "$s/read.json" >/dev/null; then
        echo "is from another run, repository or ref than run $id, attempt $attempt"
        return 1
      fi
      if jq -e --arg since "$since" '.read >= $since' "$s/read.json" >/dev/null; then
        if jq -c .protection "$s/read.json" >"$out/protection.part" \
          && mv -- "$out/protection.part" "$out/protection.json"; then
          return 0
        fi
        rm -f -- "$out/protection.part"
        echo failed
        return 1
      fi
    fi
    if [ "$SECONDS" -ge "$deadline" ] || ! jq -e --arg repo "$repo" --arg main "$main" \
      "$ours"' | any(.[]; .status != "completed")' "$s/runs.json" >/dev/null 2>&1; then
      echo "is stale: no successful land-protection run at $main read it at or after $since"
      return 1
    fi
    sleep "$poll_s"
  done
}
unread() { printf 'snapshot-fetch: the read of protection %s\n' "$1" >&2; }
protection() {
  local s why
  s=$(mktemp -d 2>/dev/null) || { unread failed; return; }
  why=$(protection_from "$s") || unread "$why"
  rm -rf -- "$s"
}

read_to repo "repos/$repo"
pages_to open "repos/$repo/pulls?state=open&per_page=100"
read_to main "repos/$repo/branches/main"
protection
pages_to stacks -H "X-GitHub-Api-Version: 2026-03-10" "repos/$repo/stacks?per_page=100"
read_to provenance-issue "repos/$repo/issues/$issue"

[ -e "$out/open.json" ] || exit 0
prs=$(jq -r '.[][] | [.number, .head.sha, .head.ref] | @tsv' "$out/open.json" 2>/dev/null) || exit 0
while IFS=$'\t' read -r n sha ref; do
  [[ $n =~ ^[1-9][0-9]{0,6}$ ]] || continue
  pages_to "comments-$n" "repos/$repo/issues/$n/comments?per_page=100"
  pages_to "review-comments-$n" "repos/$repo/pulls/$n/comments?per_page=100"
  pages_to "reviews-$n" "repos/$repo/pulls/$n/reviews?per_page=100"
  pages_to "files-$n" "repos/$repo/pulls/$n/files?per_page=100"
  if [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
    pages_to "checks-$n" "repos/$repo/commits/$sha/check-runs?filter=all&per_page=100"
  fi
  if [[ $ref =~ ^[A-Za-z0-9._/-]+$ && $ref != -* && $ref != *..* ]]; then
    pages_to "activity-$n" "repos/$repo/activity?ref=refs/heads/$ref&direction=desc&per_page=100"
  fi
done <<<"$prs"
exit 0
