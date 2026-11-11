#!/usr/bin/env bash
# shellcheck disable=SC2016 # fixtures keep $repo and "$2" as text
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0

is_rest_route() {
  local r=$1 path seg lseg lpath
  [ -n "$r" ] || return 1
  [[ $r == -* || $r == *' '* || $r == *'{'* || $r == *'}'* ]] && return 1
  [[ $r == http://* || $r == https://* ]] && return 1
  path=${r%%\?*}
  path=${path%/}
  seg=${path##*/}
  lseg=${seg,,}
  lpath=${path,,}
  [[ $lseg == graphql || $lpath == graphql || $lpath == /graphql ]] && return 1
  [[ $r == repos/* ]] || return 1
  [[ $r == *';'* || $r == *'|'* || $r == *'`'* || $r == *"'"* || $r == *'"'* ]] && return 1
  return 0
}

routes_of() {
  local f=$1 line rest tok nxt quoted route
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^[a-z_]+\(\)[[:space:]]*\{ ]]; then
      line=${line%% #*}
    fi
    if [[ $line =~ ^[[:space:]]*gh[[:space:]]*\\$ ]]; then
      IFS= read -r nxt || true
      line="${line%\\}${nxt}"
    fi
    if [[ $line =~ gh[[:space:]]+api ]]; then
      rest=${line#*"${BASH_REMATCH[0]}"}
      rest=${rest#"${rest%%[![:space:]]*}"}
      route=
      if [[ $rest == for\ * || $rest == '"$2"'* || $rest == '"${@:2}"'* ]]; then
        :
      else
        while [ -n "$rest" ]; do
          tok=${rest%%[[:space:]]*}
          rest=${rest#"$tok"}
          rest=${rest#"${rest%%[![:space:]]*}"}
          tok=${tok%,}; tok=${tok%\)}; tok=${tok#\"}; tok=${tok%\"}; tok=${tok#\'}; tok=${tok%\'}
          case $tok in
            -X|--method)
              nxt=${rest%%[[:space:]]*}
              rest=${rest#"$nxt"}; rest=${rest#"${rest%%[![:space:]]*}"} ;;
            --method=*|--raw-field=*|--field=*|--jq=*|--input=*|--header=*|--hostname=*) ;;
            -f|-F|--raw-field|--field|--jq|--input|--header|-H)
              nxt=${rest%%[[:space:]]*}
              rest=${rest#"$nxt"}; rest=${rest#"${rest%%[![:space:]]*}"} ;;
            --paginate|--slurp|--silent|--verbose|--cache) ;;
            -*) echo "unclassified flag $tok in $f" >&2; return 1 ;;
            '') ;;
            *) route=$tok; break ;;
          esac
        done
        [ -n "$route" ] || { echo "gh api has no route in $f" >&2; return 1; }
        printf '%s\n' "$route"
      fi
    fi
    if [[ $line =~ ^[[:space:]]*(fetch|fetch_all_pages|api)[[:space:]] ]]; then
      [[ $line == *'()'* ]] && continue
    elif [[ $line =~ \$\((fetch|fetch_all_pages|api)[[:space:]] ]]; then
      :
    elif [[ $line =~ (^|[[:space:]])(if|elif)[[:space:]]+(fetch|fetch_all_pages|api)[[:space:]] ]]; then
      :
    else
      continue
    fi
    quoted=$(grep -oE '"[^"]*"' <<<"$line" || true)
    route=
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      tok=${tok#\"}; tok=${tok%\"}
      [[ $tok == *.json ]] && continue
      route=$tok
    done <<<"$quoted"
    [ -n "$route" ] || { echo "call has no route: $line" >&2; return 1; }
    printf '%s\n' "$route"
  done <"$f"
}

check_file() {
  local f=$1 name routes n=0 route
  name=$(basename "$f")
  routes=$(routes_of "$f") || { echo "FAIL $name: $routes"; failed=1; return; }
  [ -n "$routes" ] || { echo "FAIL $name: no routes"; failed=1; return; }
  while IFS= read -r route; do
    n=$((n + 1))
    if ! is_rest_route "$route"; then
      echo "FAIL $name: not a REST path: $route"
      failed=1
      return
    fi
  done <<<"$routes"
  if [ "$n" -lt 10 ]; then
    echo "FAIL $name: only $n routes, the scan missed some"
    failed=1
    return
  fi
  echo "ok   $name ($n REST routes)"
}

check_file "$root/.claude/hooks/pr-state.sh"
check_file "$root/.claude/scripts/watch-github.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base="$root/.claude/hooks/pr-state.sh"
cp "$base" "$work/ok.sh"
printf '\nfetch extra "repos/$repo/pulls/1" &\n' >>"$work/ok.sh"
check_file "$work/ok.sh"

reject() {
  local name=$1 line=$2 copy="$work/bad.sh"
  cp "$base" "$copy"
  printf '\n%s\n' "$line" >>"$copy"
  local out
  out=$(routes_of "$copy" 2>&1) && {
    local route bad=0
    while IFS= read -r route; do
      is_rest_route "$route" || bad=1
    done <<<"$out"
    if [ "$bad" = 0 ]; then
      echo "FAIL $name was accepted"
      failed=1
      return
    fi
  }
  echo "ok   $name rejected"
}

reject "graphql endpoint" 'fetch bad "graphql" &'
reject "graphql under repos" 'fetch bad "repos/$repo/graphql" &'
reject "gh api graphql" "gh api graphql -f query='{ viewer { login } }'"
reject "graphql URL" 'api bad.json "https://api.github.com/graphql"'
reject "query text" 'api bad.json "query { viewer { login } }"'
reject "continued gh api" $'gh \\\n  api graphql --jq "repos/o/r/pulls"'
reject "api in a substitution" 'x=$(api gq.json "graphql")'
reject "gh api with two spaces" 'gh  api graphql'
reject "if fetch" 'if fetch gq "graphql"'

echo "gh-api-rest: done"
[ "$failed" = 0 ]
