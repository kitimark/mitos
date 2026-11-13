#!/usr/bin/env bash
# shellcheck disable=SC2016 # fixture lines and the fake gh keep $repo, "$cmd" and "$*" as text
# No GraphQL in the scripts that read GitHub from a Claude Code session.
#
# The session proxy answers GraphQL with HTTP 403. gh pr, gh issue, gh run and the other gh
# commands except gh api use GraphQL without naming it. So these scripts read GitHub only
# through their wrappers fetch, fetch_all_pages and api, which run gh api.
#
# Threat model: an honest mistake, an agent that copies a familiar gh command into a scanned
# file. Two rules on text. Neither models bash.
#   1. Each use of the word gh outside a comment line, with the word after it, is listed in
#      EXPECTED, as often as it is listed. gh pr view, cmd=gh, eval "gh ...", bash -c 'gh ...'
#      and a direct gh api each change that list.
#   2. No line outside a comment line has the word graphql, in any case.
# Scanned: the NAMED files (a missing one fails) and every .claude/scripts/lib/*.sh.
# Out of scope. A finding in one of these classes is answered with its name, not with code:
#   O1 A spelling that hides the word gh or graphql: g"h", g\h, "$GH", a word built from parts.
#   O2 What a route holds and whether a branch runs it. pr-state.test.sh and
#      watch-github.test.sh run the calls, locally until #164 runs them in CI.
#   O3 A file that is not scanned: bot-review.sh, open-pr.sh, other hooks, .github/ (Actions
#      runners reach GraphQL), a file sourced from another folder.
#   O4 Text on a line whose first non-blank character is #, even inside a string or heredoc.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0

NAMED=(.claude/hooks/pr-state.sh .claude/hooks/hook-state.sh .claude/scripts/watch-github.sh)
files() { (cd "$1" && shopt -s nullglob && printf '%s\n' "${NAMED[@]}" .claude/scripts/lib/*.sh); }

# Per file: the count, then gh and the word after it, in LC_ALL=C sort order.
EXPECTED='.claude/hooks/pr-state.sh 2 gh
.claude/hooks/pr-state.sh 5 gh api
.claude/hooks/pr-state.sh 1 gh is
.claude/scripts/watch-github.sh 1 gh api
.claude/scripts/watch-github.sh 1 gh jq'
# pr-state.sh, gh api x5: the fetch and fetch_all_pages bodies, the "gh api for $n failed"
# message, and the 2 jq strings that print a merge or a patch command for the owner to copy.
# gh x2: `command -v gh` and "unexpected JSON from gh". gh is: "gh is not installed".
# watch-github.sh, gh api: the api body. gh jq: the `for tool in gh jq ...` probe.

code() { grep -vE '^[[:space:]]*#' "$1"; }

scan() { # scan <tree>: print what is wrong under <tree>, and return 1 if anything is
  local tree=$1 f list found bad=0
  for f in "${NAMED[@]}"; do [ -f "$tree/$f" ] || { echo "$f is missing"; bad=1; }; done
  mapfile -t list < <(files "$tree")
  found=$(for f in "${list[@]}"; do
    [ -f "$tree/$f" ] || continue
    code "$tree/$f" | grep -oE '\bgh\b( +[a-z]+)?' | LC_ALL=C sort | uniq -c | sed -E "s/^ +//; s|^|$f |"
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
mkdir "$work/bin"
# A fake gh that records its arguments. Fixture lines run only against it, with no token.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"$GH_ARGV"\n' >"$work/bin/gh"
chmod +x "$work/bin/gh"

runs() { # runs <line>: what bash asks gh to do when it runs <line> alone: rest, other or none
  local a v=none
  : >"$work/argv"
  env -u GH_TOKEN -u GITHUB_TOKEN GH_ARGV="$work/argv" PATH="$work/bin:$PATH" \
    timeout 10 bash -c "$1" >/dev/null 2>&1 </dev/null
  while IFS= read -r a; do
    if [[ $a =~ ^api\ repos/[^[:space:]]+$ && ${a,,} != *graphql* ]]; then [ "$v" = other ] || v=rest; else v=other; fi
  done <"$work/argv"
  echo "$v"
}

# check ok|bad <file> <name> [<line>]: in a copy, append <line> to <file>, or delete <file>
# when no line is given. The scan must stay as it was (ok), or change and return 1 (bad). A line
# that makes bash run gh with anything but `api repos/...` must be bad, whatever the label says.
check() {
  local want=$1 file=$2 name=$3 f out st got ran=none
  rm -rf "$work/tree"
  while IFS= read -r f; do mkdir -p "$work/tree/${f%/*}"; cp "$root/$f" "$work/tree/$f"; done < <(files "$root")
  mkdir -p "$work/tree/${file%/*}"
  if [ $# -ge 4 ]; then
    printf '\n%s\n' "$4" >>"$work/tree/$file"
    ran=$(runs "$4")
  else
    rm -f "$work/tree/$file"
  fi
  if out=$(scan "$work/tree"); then st=0; else st=1; fi
  if [ "$out" = "$base" ]; then got=ok; elif [ "$st" = 1 ]; then got=bad; else got="changed with status 0"; fi
  if [ "$got" = "$want" ] && { [ "$ran" != other ] || [ "$got" = bad ]; }; then
    echo "ok   $name (bash: $ran)"
  else
    echo "FAIL $name: expected $want, scan $got, bash $ran"; failed=1
  fi
}

if base=$(scan "$root"); then
  echo "ok   the scanned files use gh only as listed and never name graphql"
else
  echo "FAIL $base"; failed=1
fi
if [ "$(runs 'gh pr view 1')" = other ] && [ "$(runs 'gh api repos/o/r/pulls')" = rest ] && [ "$(runs :)" = none ]; then
  echo "ok   the fake gh records what bash runs"
else
  echo "FAIL the fake gh does not record what bash runs"; failed=1
fi

P=.claude/hooks/pr-state.sh W=.claude/scripts/watch-github.sh L=.claude/hooks/hook-state.sh
N=.claude/scripts/lib/new.sh
check ok  $P "a REST call through fetch"       'fetch extra "repos/$repo/pulls/1" &'
check ok  $W "a REST call through api"         'api extra.json --paginate "repos/$repo/issues"'
check ok  $P "a comment that names gh pr view" '# gh pr view fails in a session'
check bad $P "graphql endpoint"                'fetch bad "graphql" &'
check bad $P "graphql under repos"             'fetch bad "repos/$repo/graphql" &'
check bad $P "gh api graphql"                  "gh api graphql -f query='{ viewer { login } }'"
check bad $P "graphql URL"                     'api bad.json "https://api.github.com/graphql"'
check bad $P "gh pr view"                      'gh pr view 5 --json state'
check bad $W "gh issue list"                   'gh issue list'
check bad $P "a direct gh api"                 'gh api "repos/$repo/pulls" --jq ".[].number"'
check bad $P "a direct gh api, double space"   'gh  api "repos/$repo/pulls"'
check bad $P "command gh"                      'command gh pr checks 5'
check bad $P "cmd=gh then \$cmd"               'cmd=gh; "$cmd" pr view 5'
check bad $P "eval"                            'eval "gh pr view 5"'
check bad $W "bash -c"                         "bash -c 'gh pr view 5'"
check bad $P "inside a group"                  '{ gh pr view 5; }'
check bad $P "pr view on the next line"        $'gh \\\n  pr view 5'
check bad $L "a sourced file"                  'gh pr list'
check bad $N "a new file under lib"            'gh pr list'
check bad $L "a scanned file that is gone"

echo "gh-api-rest: done"
[ "$failed" = 0 ]
