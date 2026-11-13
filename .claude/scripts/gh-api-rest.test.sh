#!/usr/bin/env bash
# Rules, threat model and out-of-scope classes: https://github.com/kitimark/mitos/pull/184
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0

NAMED=(.claude/hooks/pr-state.sh .claude/hooks/hook-state.sh .claude/scripts/watch-github.sh)
files() { (cd "$1" && shopt -s nullglob && printf '%s\n' "${NAMED[@]}" .claude/scripts/lib/*.sh); }

EXPECTED='.claude/hooks/pr-state.sh 2 gh
.claude/hooks/pr-state.sh 5 gh api
.claude/hooks/pr-state.sh 1 gh is
.claude/scripts/watch-github.sh 1 gh api
.claude/scripts/watch-github.sh 1 gh jq'

code() { grep -vE '^[[:space:]]*#' "$1"; }

scan() {
  local tree=$1 f list found bad=0
  for f in "${NAMED[@]}"; do [ -f "$tree/$f" ] || { echo "$f is missing"; bad=1; }; done
  mapfile -t list < <(files "$tree")
  found=$(for f in "${list[@]}"; do
    [ -f "$tree/$f" ] || continue
    code "$tree/$f" | grep -oE '\bgh\b( +[a-z]+)?' | LC_ALL=C sort | uniq -c | while read -r line; do printf '%s %s\n' "$f" "$line"; done
  done)
  for f in "${list[@]}"; do
    [ -f "$tree/$f" ] || continue
    code "$tree/$f" | grep -qi graphql && { echo "$f names graphql outside a comment line"; bad=1; }
  done
  if [ "$found" != "$EXPECTED" ]; then
    echo "gh is used where EXPECTED does not list it (< listed, > found). gh pr, gh issue and the"
    echo "other gh commands except gh api use GraphQL, which the session proxy blocks. Read GitHub"
    echo "through fetch, fetch_all_pages or api. If the new line is a message or data, update EXPECTED:"
    diff <(echo "$EXPECTED") <(echo "$found") | grep '^[<>]'
    bad=1
  fi
  return $bad
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

check() {
  local want=$1 file=$2 name=$3 f got
  rm -rf "$work/tree"
  while IFS= read -r f; do mkdir -p "$work/tree/${f%/*}"; cp "$root/$f" "$work/tree/$f"; done < <(files "$root")
  if [ $# -ge 4 ]; then printf '\n%s\n' "$4" >>"$work/tree/$file"; else rm -f "$work/tree/$file"; fi
  if last=$(scan "$work/tree"); then got=ok; else got=bad; fi
  if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name: expected $want, got $got"; failed=1; fi
}

if out=$(scan "$root"); then
  echo "ok   the scanned files use gh only as listed and never name graphql"
else
  echo "FAIL $out"; failed=1
fi

P=.claude/hooks/pr-state.sh
# shellcheck disable=SC2016
check ok  $P "a REST call through fetch" 'fetch extra "repos/$repo/pulls/1" &'
check bad $P "gh pr view"                'gh pr view 5 --json state'
check bad $P "graphql endpoint"          'fetch bad "graphql" &'
check bad .claude/hooks/hook-state.sh "a scanned file that is gone"

L='.claude/scripts/lib/x|;e touch INJECTED;#.sh'
check bad "$L" "a lib file named with sed syntax" 'gh api x'
if [ ! -e INJECTED ] && grep -qF -- "> $L 1 gh api" <<<"$last"; then
  echo "ok   that file name is reported and runs nothing"
else
  echo "FAIL a scanned file name ran a command or was not reported"; failed=1
fi

echo "gh-api-rest: done"
[ "$failed" = 0 ]
