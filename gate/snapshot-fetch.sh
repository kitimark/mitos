#!/usr/bin/env bash
# Usage: gate/snapshot-fetch.sh <owner/name> <dashboard-issue> <dir>
#
# Saves the REST reads that `mitos-gate snapshot <dir>` turns into the landing snapshot, one file
# per read, `<dir>/<read>.json`, through `gh api` only: REST, never GraphQL. A read that fails
# leaves no file, so the snapshot holds every pull request that needs it; a list is read with
# `--paginate --slurp`, so a list with a failed page leaves no file either. The script parses only
# the numbers, heads and branch names of the open pull requests, to name their routes, and skips a
# route whose name it would have to build from anything else; `mitos-gate snapshot` checks every
# response it reads. It prints one line on standard error per failed read and exits 0; a usage
# error exits 2.
set -u

die() { printf 'snapshot-fetch: %s\n' "$1" >&2; exit 2; }
[ $# = 3 ] || die "usage: gate/snapshot-fetch.sh <owner/name> <dashboard-issue> <dir>"
repo=$1 dash=$2 out=$3
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
[[ $dash =~ ^[1-9][0-9]{0,6}$ ]] || die "<dashboard-issue> is not an issue number"
for tool in gh jq timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
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

read_to repo "repos/$repo"
pages_to open "repos/$repo/pulls?state=open&per_page=100"
read_to main "repos/$repo/branches/main"
read_to protection "repos/$repo/branches/main/protection"
pages_to stacks -H "X-GitHub-Api-Version: 2026-03-10" "repos/$repo/stacks?per_page=100"
read_to dashboard "repos/$repo/issues/$dash"

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
