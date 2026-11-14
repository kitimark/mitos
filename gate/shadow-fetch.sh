#!/usr/bin/env bash
set -u

die() { printf 'shadow-fetch: %s\n' "$1" >&2; exit 2; }
failed() { printf 'shadow-fetch: the read of %s failed\n' "$1" >&2; exit 1; }
unwritten() { printf 'shadow-fetch: %s was not written\n' "$1" >&2; exit 1; }
[ $# = 3 ] || die "usage: gate/shadow-fetch.sh <owner/name> <from-date> <dir>"
repo=$1 from=$2 out=$3
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
for tool in gh jq timeout unzip date; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
[[ $from =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $(date -u -d "$from" +%F 2>/dev/null) == "$from" ]] \
  || die "<from-date> is not a date, YYYY-MM-DD"
today=$(date -u +%F)
[[ $from > $today ]] && die "<from-date> is after today"
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"
mkdir -- "$out/records" || die "cannot make the folder"
start="${from}T00:00:00Z"
workflow=${SHADOW_WORKFLOW:-land.yml}
tmp=$(mktemp -d) || die "cannot make a scratch folder"
trap 'rm -rf -- "$tmp"' EXIT

api() { timeout -k 5 120 gh api "$@" 2>/dev/null </dev/null; }

by_number() {
  local route=$1 items=$2 stop=$3 k=1
  while :; do
    if ! api "$route&page=$k" >"$tmp/page" || ! jq -c "${items}[]" "$tmp/page"; then return 1; fi
    [ "$(jq "$items | length" "$tmp/page")" -lt 100 ] && return 0
    jq -e --arg start "$start" "$stop" "$tmp/page" >/dev/null && return 0
    k=$((k + 1))
  done
}
by_cursor() {
  local route=$1 stop=$2 after=
  while :; do
    api -i "$route${after:+&after=$after}" >"$tmp/page" || return 1
    sed '1,/^\r*$/d' "$tmp/page" >"$tmp/body"
    jq -c '.[]' "$tmp/body" || return 1
    jq -e --arg start "$start" "$stop" "$tmp/body" >/dev/null && return 0
    after=$(sed -n '1,/^\r*$/p' "$tmp/page" | grep -io '^link:.*' | grep -o '<[^>]*>; rel="next"' \
      | sed -n 's/.*[?&]after=\([^&>]*\).*/\1/p')
    [ -n "$after" ] || return 0
    [[ $after =~ ^[A-Za-z0-9%_=.-]+$ ]] || return 1
  done
}

# A list of runs filtered by date holds at most 1000 runs, so this reads one day at a time.
runs_of() {
  local wf=$1 keep=$2 file=$3 day=$from
  { : >"$tmp/runs"; } 2>/dev/null || unwritten "a scratch file"
  while [[ ! $day > $today ]]; do
    if ! by_number "repos/$repo/actions/workflows/$wf/runs?created=$day&per_page=100" \
      .workflow_runs false >"$tmp/items" || ! jq -c "$keep" "$tmp/items" >>"$tmp/runs"; then
      failed "the runs of $wf on $day"
    fi
    day=$(date -u -d "$day + 1 day" +%F)
  done
  { jq -s . "$tmp/runs" >"$out/$file"; } 2>/dev/null || unwritten "$file"
}

runs_of "$workflow" '{id, attempt: .run_attempt, event, conclusion, created: .created_at,
  started: .run_started_at, updated: .updated_at}' runs.json
runs_of ci.yml '{id, event, actor: (.triggering_actor.login // "")}' baseline.json

while read -r id attempts; do
  [[ $id =~ ^[0-9]+$ && $attempts =~ ^[0-9]+$ ]] || failed "the runs of $workflow"
  for ((a = 1; a <= attempts; a++)); do
    name="land-record-$id-$a"
    if ! api "repos/$repo/actions/artifacts?name=$name&per_page=100" >"$tmp/list" \
      || ! art=$(jq -r --argjson run "$id" \
        '[.artifacts[] | select((.expired | not) and .workflow_run.id == $run)][0].id // ""' \
        "$tmp/list"); then
      failed "the artifacts named $name"
    fi
    [[ $art =~ ^[0-9]+$ ]] || continue
    if ! api "repos/$repo/actions/artifacts/$art/zip" >"$tmp/zip" \
      || ! unzip -p "$tmp/zip" record.json >"$out/records/$id-$a.json"; then
      failed "the artifact $name"
    fi
  done
done < <(jq -r '.[] | select(.conclusion != "skipped") | "\(.id) \(.attempt)"' "$out/runs.json")

# shellcheck disable=SC2016
by_number "repos/$repo/pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100" \
  . '.[-1].updated_at < $start' >"$tmp/pulls" || failed "the closed pull requests"
# shellcheck disable=SC2016
by_cursor "repos/$repo/activity?ref=refs/heads/main&direction=desc&per_page=100" \
  '.[-1].timestamp < $start' >"$tmp/activity" || failed "the activity of main"
jq -c --arg start "$start" --slurpfile act "$tmp/activity" \
  'select(.merged_at != null and .merged_at >= $start) | .merge_commit_sha as $after |
   {pr: .number, time: .merged_at, head: .head.sha, after: ($after // ""),
    before: ([$act[] | select($after != null and .after == $after)][0].before // "")}' \
  "$tmp/pulls" >"$tmp/merged" || failed "the merged pull requests"
{ : >"$tmp/merges"; } 2>/dev/null || unwritten "a scratch file"
while read -r merge; do
  after=$(jq -r .after <<<"$merge")
  tree=
  if [[ $after =~ ^[0-9a-f]{40}$ ]]; then
    tree=$(api "repos/$repo/git/commits/$after" --jq .tree.sha) || failed "the commit $after"
  fi
  { jq -c --arg tree "$tree" 'del(.after) + {tree: $tree}' <<<"$merge" >>"$tmp/merges"; } \
    2>/dev/null || unwritten "a scratch file"
done <"$tmp/merged"
{ jq -s . "$tmp/merges" >"$out/merges.json"; } 2>/dev/null || unwritten merges.json
exit 0
