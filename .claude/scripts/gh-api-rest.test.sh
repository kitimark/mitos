#!/usr/bin/env bash
# shellcheck disable=SC2016 # fixtures keep $repo and "$2" as text
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0
# shellcheck disable=SC1003 # the value is one backslash
backslash=$(printf '\\')

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

# One shell word, quotes removed. a"pi", "ap"i, f""etch and 'api' are api.
# An unquoted \p is p, so a\pi is api. An unquoted \ before a separator stays
# in the word, so gh\ api is not gh api and a route's \  is a space.
# \$ \" \` and \\ inside double quotes are the escaped character. A single
# quote has no escapes. $(...) is recorded and scanned on its own; $(( is arithmetic.
read_word() {
  local s=$1 i=$2
  local n=${#s} c e q='' word='' bare=0 sawq=0 sub=0
  while (( i < n )); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$q" = '"' ] && [ "$c" = "$backslash" ]; then
        e=${s:i+1:1}
        [ -n "$e" ] || { i=$((i + 1)); continue; }
        case $e in
          '"'|'$'|'`'|"$backslash") word+=$e ;;
          *) word+=$c$e ;;
        esac
        i=$((i + 2))
        continue
      fi
      if [ "$q" = '"' ] && [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ] && [ "${s:i+2:1}" != '(' ]; then
        subst_at "$s" "$i"
        LEX_SUBS+=("$SUB_INNER")
        sub=1
        i=$SUB_END
        continue
      fi
      if [ "$c" = "$q" ]; then
        q=
        i=$((i + 1))
        continue
      fi
      word+=$c
      i=$((i + 1))
      continue
    fi
    case $c in
      [[:space:]]|\;|\&|\||\(|\)|\<|\>) break ;;
      \#)
        [ -n "$word" ] || break
        word+=$c
        bare=1
        i=$((i + 1))
        continue ;;
      \\)
        e=${s:i+1:1}
        [ -n "$e" ] || break
        word+=$e
        bare=1
        i=$((i + 2))
        continue ;;
      \"|\')
        sawq=1
        q=$c
        i=$((i + 1))
        continue ;;
      \$)
        if [ "${s:i+1:1}" = '(' ] && [ "${s:i+2:1}" != '(' ]; then
          subst_at "$s" "$i"
          LEX_SUBS+=("$SUB_INNER")
          sub=1
          i=$SUB_END
          continue
        fi
        word+=$c
        bare=1
        i=$((i + 1))
        continue ;;
      *)
        word+=$c
        bare=1
        i=$((i + 1))
        continue ;;
    esac
  done
  RW_END=$i
  RW_WORD=$word
  RW_SUB=$sub
  RW_BARE=0
  if (( bare == 1 && sawq == 0 )); then
    RW_BARE=1
  fi
}

# i points at '$' of $(...). SUB_END is the index after the closing paren.
subst_at() {
  local s=$1 i=$2
  local n=${#s} depth=1 q='' c
  i=$((i + 2))
  local start=$i
  while (( i < n && depth > 0 )); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$q" = '"' ] && [ "$c" = "$backslash" ]; then
        i=$((i + 2))
        continue
      fi
      [ "$c" = "$q" ] && q=
      i=$((i + 1))
      continue
    fi
    case $c in
      \'|\" ) q=$c ;;
      \\) i=$((i + 1)) ;;
      \() depth=$((depth + 1)) ;;
      \)) depth=$((depth - 1)) ;;
    esac
    i=$((i + 1))
  done
  SUB_END=$i
  if (( depth == 0 )); then
    SUB_INNER=${s:start:i-start-1}
  else
    SUB_INNER=${s:start}
  fi
}

is_wrapper() {
  case $1 in
    fetch|fetch_all_pages|api) return 0 ;;
  esac
  return 1
}

push_op() {
  LEX_KIND+=('o')
  LEX_TEXT+=("$1")
  LEX_BARE+=(0)
  LEX_SUBW+=(0)
}

# Words and operators of one line. A # between words ends the line.
# Braces stay in the word, so ${@:2} is one word and a bare { is too.
lex_line() {
  local s=$1 i=0 c prev
  local n=${#s}
  LEX_KIND=()
  LEX_TEXT=()
  LEX_BARE=()
  LEX_SUBW=()
  LEX_SUBS=()
  while (( i < n )); do
    c=${s:i:1}
    case $c in
      [[:space:]]) i=$((i + 1)); continue ;;
      \#) return 0 ;;
      \;) push_op ';'; i=$((i + 1)); continue ;;
      \&)
        if [ "${s:i:2}" = '&&' ]; then push_op '&&'; i=$((i + 2))
        elif [ "${s:i:2}" = '&>' ]; then push_op '&>'; i=$((i + 2))
        else push_op '&'; i=$((i + 1)); fi
        continue ;;
      \|)
        if [ "${s:i:2}" = '||' ]; then push_op '||'; i=$((i + 2))
        elif [ "${s:i:2}" = '|&' ]; then push_op '|&'; i=$((i + 2))
        else push_op '|'; i=$((i + 1)); fi
        continue ;;
      \() push_op '('; i=$((i + 1)); continue ;;
      \)) push_op ')'; i=$((i + 1)); continue ;;
      \<)
        if [ "${s:i:2}" = '<<' ]; then push_op '<<'; i=$((i + 2))
        elif [ "${s:i:2}" = '<&' ]; then push_op '<&'; i=$((i + 2))
        else push_op '<'; i=$((i + 1)); fi
        continue ;;
      \>)
        if [ "${s:i:2}" = '>>' ]; then push_op '>>'; i=$((i + 2))
        elif [ "${s:i:2}" = '>&' ]; then push_op '>&'; i=$((i + 2))
        else push_op '>'; i=$((i + 1)); fi
        continue ;;
    esac
    prev=$i
    read_word "$s" "$i"
    if (( RW_END <= prev )); then
      i=$((prev + 1))
      continue
    fi
    LEX_KIND+=('w')
    LEX_TEXT+=("$RW_WORD")
    LEX_BARE+=("$RW_BARE")
    LEX_SUBW+=("$RW_SUB")
    i=$RW_END
  done
}

# First non-flag word of a gh api argument list, from index $1.
# A quoted flag stays one word, so its argument is not split into the route.
# "$2" and "${@:2}" are the wrapper bodies, not literal routes.
take_gh() {
  local j=$1 n=${#LEX_KIND[@]} route='' saw=0 arg
  while (( j < n )) && [ "${LEX_KIND[j]}" = w ]; do
    arg=${LEX_TEXT[j]}
    case $arg in
      -X|--method|-f|-F|--raw-field|--field|--jq|--input|--header|-H)
        j=$((j + 1))
        if (( j < n )) && [ "${LEX_KIND[j]}" = w ]; then j=$((j + 1)); fi
        continue ;;
      --method=*|--raw-field=*|--field=*|--jq=*|--input=*|--header=*|--hostname=*)
        j=$((j + 1))
        continue ;;
      --paginate|--slurp|--silent|--verbose|--cache)
        j=$((j + 1))
        continue ;;
      -*)
        echo "unclassified flag $arg in $SCAN_FILE" >&2
        return 1 ;;
      '$2'|'${@:2}')
        saw=1
        route=''
        j=$((j + 1))
        break ;;
      '')
        if [ "${LEX_SUBW[j]}" = 1 ]; then
          saw=1
          j=$((j + 1))
          break
        fi
        j=$((j + 1))
        continue ;;
    esac
    route=$arg
    saw=1
    j=$((j + 1))
    break
  done
  if [ "$saw" = 0 ]; then
    echo "gh api has no route in $SCAN_FILE" >&2
    return 1
  fi
  while (( j < n )) && [ "${LEX_KIND[j]}" = w ]; do
    j=$((j + 1))
  done
  [ -n "$route" ] && ROUTES+=("$route")
  GH_END=$j
}

# fetch and fetch_all_pages pass their second word to gh api.
# api passes every word after the output name, flags included.
take_wrapper() {
  local name=$1 j=$2 n=${#LEX_KIND[@]} route subw
  if (( j >= n )) || [ "${LEX_KIND[j]}" != w ]; then
    echo "call has no route in $SCAN_FILE" >&2
    return 1
  fi
  j=$((j + 1))
  if [ "$name" = api ]; then
    take_gh "$j" || return 1
    return 0
  fi
  if (( j >= n )) || [ "${LEX_KIND[j]}" != w ]; then
    echo "call has no route in $SCAN_FILE" >&2
    return 1
  fi
  route=${LEX_TEXT[j]}
  subw=${LEX_SUBW[j]}
  j=$((j + 1))
  while (( j < n )) && [ "${LEX_KIND[j]}" = w ]; do
    j=$((j + 1))
  done
  if [ -n "$route" ]; then
    ROUTES+=("$route")
  elif [ "$subw" != 1 ]; then
    echo "call has no route in $SCAN_FILE" >&2
    return 1
  fi
  GH_END=$j
}

walk_line() {
  local n=${#LEX_KIND[@]} i=0 at=1 w bare
  local SKIP_FETCH=-1
  while (( i < n )); do
    if [ "${LEX_KIND[i]}" = o ]; then
      case ${LEX_TEXT[i]} in
        ';'|'&'|'&&'|'|'|'||'|'|&'|'(') at=1 ;;
        '>'|'<'|'>>'|'>&'|'<&'|'&>'|'<<')
          if (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ]; then i=$((i + 1)); fi
          ;;
      esac
      i=$((i + 1))
      continue
    fi
    w=${LEX_TEXT[i]}
    bare=${LEX_BARE[i]}
    if [ "$w" = '{' ]; then
      at=1
      i=$((i + 1))
      continue
    fi
    if [ "$at" = 1 ]; then
      if [ "$bare" = 1 ]; then
        case $w in
          if|while|until|elif|then|else|do|'!')
            i=$((i + 1))
            continue ;;
        esac
      fi
      if [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        i=$((i + 1))
        continue
      fi
      if (( i + 2 < n )) && [ "${LEX_KIND[i+1]}" = o ] && [ "${LEX_TEXT[i+1]}" = '(' ] \
        && [ "${LEX_KIND[i+2]}" = o ] && [ "${LEX_TEXT[i+2]}" = ')' ]; then
        i=$((i + 3))
        at=0
        continue
      fi
      if [ "$w" = gh ] && (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ] && [ "${LEX_TEXT[i+1]}" = api ]; then
        take_gh $((i + 2)) || return 1
        i=$GH_END
        at=0
        continue
      fi
      if is_wrapper "$w"; then
        take_wrapper "$w" $((i + 1)) || return 1
        i=$GH_END
        at=0
        continue
      fi
      if [ "$w" = git ] && (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ] \
        && [ "${LEX_TEXT[i+1]}" = fetch ] && [ "${LEX_BARE[i+1]}" = 1 ]; then
        SKIP_FETCH=$((i + 1))
      fi
      at=0
      i=$((i + 1))
      continue
    fi
    if [ "$w" = gh ] && (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ] && [ "${LEX_TEXT[i+1]}" = api ]; then
      take_gh $((i + 2)) || return 1
      i=$GH_END
      continue
    fi
    if [ "$bare" = 1 ] && is_wrapper "$w" && [ "$i" != "$SKIP_FETCH" ]; then
      echo "unclassified call in $SCAN_FILE" >&2
      return 1
    fi
    i=$((i + 1))
  done
}

# Substitutions are scanned first, then the words of this line.
scan_text() {
  local s=$1 depth=${2:-0} nsub=0 i sub
  local -a sk=() st=() sb=() sw=() ss=()
  if (( depth > 20 )); then
    echo "substitution too deep in $SCAN_FILE" >&2
    return 1
  fi
  lex_line "$s"
  if (( ${#LEX_KIND[@]} )); then
    sk=("${LEX_KIND[@]}")
    st=("${LEX_TEXT[@]}")
    sb=("${LEX_BARE[@]}")
    sw=("${LEX_SUBW[@]}")
  fi
  if (( ${#LEX_SUBS[@]} )); then
    ss=("${LEX_SUBS[@]}")
    nsub=${#ss[@]}
  fi
  for (( i = 0; i < nsub; i++ )); do
    scan_text "${ss[i]}" $((depth + 1)) || return 1
  done
  LEX_KIND=()
  LEX_TEXT=()
  LEX_BARE=()
  LEX_SUBW=()
  if (( ${#sk[@]} )); then
    LEX_KIND=("${sk[@]}")
    LEX_TEXT=("${st[@]}")
    LEX_BARE=("${sb[@]}")
    LEX_SUBW=("${sw[@]}")
  fi
  walk_line
}

odd_backslash() {
  local s=$1 n=0
  while [ -n "$s" ] && [ "${s: -1}" = "$backslash" ]; do
    n=$((n + 1))
    s=${s%\\}
  done
  (( n % 2 == 1 ))
}

routes_of() {
  local f=$1 line nxt
  SCAN_FILE=$f
  ROUTES=()
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    while odd_backslash "$line"; do
      IFS= read -r nxt || break
      line=${line%\\}$nxt
    done
    scan_text "$line" || return 1
  done <"$f"
  if (( ${#ROUTES[@]} )); then
    printf '%s\n' "${ROUTES[@]}"
  fi
}


check_file() {
  local f=$1 name routes n=0 route min=10
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
  case $name in
    # Thirteen calls. The jq program mentions gh api, and that text is not a call.
    pr-state.sh) min=13 ;;
    watch-github.sh) min=12 ;;
  esac
  if [ "$n" -lt "$min" ]; then
    echo "FAIL $name: only $n routes, the scan missed some"
    failed=1
    return
  fi
  echo "ok   $name ($n REST routes)"
}

check_file "$root/.claude/hooks/pr-state.sh"
check_file "$root/.claude/scripts/watch-github.sh"
if routes_of "$root/.claude/hooks/pr-state.sh" | grep -F -q ')/merge'; then
  echo "FAIL jq text was scanned as a call"
  failed=1
else
  echo "ok   jq text was not scanned"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base="$root/.claude/hooks/pr-state.sh"
cp "$base" "$work/ok.sh"
printf '\nfetch extra "repos/$repo/pulls/1" &\n' >>"$work/ok.sh"
check_file "$work/ok.sh"
# Same REST path: a fetch call is accepted, an api call the scanner does not classify is not.
cp "$base" "$work/rest.sh"
printf '\nfetch ok "repos/o/r/pulls/1"\n' >>"$work/rest.sh"
check_file "$work/rest.sh"
if ! routes_of "$work/rest.sh" | grep -qx 'repos/o/r/pulls/1'; then
  echo "FAIL REST call was not extracted"
  failed=1
else
  echo "ok   REST call extracted"
fi
cp "$base" "$work/miss.sh"
printf '\nenv api extra.json "repos/o/r/pulls/1"\n' >>"$work/miss.sh"
status=0
routes_of "$work/miss.sh" >/dev/null 2>&1 || status=$?
if [ "$status" = 0 ]; then
  echo "FAIL unclassified call was accepted"
  failed=1
else
  echo "ok   unclassified call failed closed"
fi
cp "$base" "$work/ghcont.sh"
printf '\n%s\n' $'gh \\\n  api \\\n  repos/o/r/pulls' >>"$work/ghcont.sh"
check_file "$work/ghcont.sh"
if ! routes_of "$work/ghcont.sh" | grep -qx 'repos/o/r/pulls'; then
  echo "FAIL continued gh api route was not extracted"
  failed=1
else
  echo "ok   continued gh api route extracted"
fi
cp "$base" "$work/sub.sh"
printf '\n%s\n' 'x=$(api gq.json "repos/o/r/pulls")' >>"$work/sub.sh"
check_file "$work/sub.sh"
if ! routes_of "$work/sub.sh" | grep -qx 'repos/o/r/pulls'; then
  echo "FAIL substitution route was not extracted"
  failed=1
else
  echo "ok   substitution route extracted"
fi

reject() {
  local name=$1 line=$2 copy="$work/bad.sh" out status=0
  cp "$base" "$copy"
  printf '\n%s\n' "$line" >>"$copy"
  out=$(routes_of "$copy" 2>"$work/scan.err") || status=$?
  if [ "$status" != 0 ]; then
    echo "FAIL $name: scanner error"
    cat "$work/scan.err"
    failed=1
    return
  fi
  local route bad=0
  while IFS= read -r route; do
    [ -n "$route" ] || continue
    is_rest_route "$route" || bad=1
  done <<<"$out"
  if [ "$bad" = 0 ]; then
    echo "FAIL $name was accepted"
    failed=1
    return
  fi
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
reject "quoted gh api before the call" "echo 'gh  api repos/o/r/pulls '; gh api graphql"
reject "if fetch then a later route" 'if fetch gq "graphql"; then echo "repos/o/r/pulls"; fi'
reject "two api calls" 'api ok.json "repos/o/r/pulls"; api gq.json "graphql"'
reject "api after another command" 'echo ready; api gq.json "graphql"'
reject "if fetch then a substitution" 'if fetch gq "graphql"; then x=$(fetch ok "repos/o/r/pulls"); fi'
reject "hash inside a word" 'echo foo#bar; api gq.json "graphql"'
reject "while fetch" 'while fetch gq "graphql"; do break; done'
reject "until fetch" 'until fetch gq "graphql"; do break; done'
reject "api in a double-quoted substitution" 'x="$(api gq.json "graphql")"'
reject "spaced fetch in double quotes" 'x="$( fetch gq "graphql")"'
reject "api after a double-quoted substitution" 'x="$(api ok.json "repos/o/r/pulls")"; api gq.json "graphql"'
reject "escaped quote before api" 'echo "\""; api gq.json "graphql"'
reject "assignment then api" 'x=foo api gq.json "graphql"'
reject "escaped api word" 'a\pi gq.json "graphql"'
reject "quoted api command" '"api" gq.json "graphql"'
reject "single quoted api command" "'api' gq.json \"graphql\""
reject "partially quoted api" 'a"pi" gq.json "graphql"'
reject "joined gh api words" 'g"h" a"pi" graphql'
cp "$base" "$work/ghqq.sh"
printf '\n%s\n' 'g"h" a"pi" repos/o/r/pulls/1' >>"$work/ghqq.sh"
check_file "$work/ghqq.sh"
if ! routes_of "$work/ghqq.sh" | grep -qx 'repos/o/r/pulls/1'; then
  echo "FAIL partially quoted gh api route was not extracted"
  failed=1
else
  echo "ok   partially quoted gh api route extracted"
fi
reject "empty quotes inside the command" 'f""etch gq "graphql"'
reject "unquoted graphql endpoint" 'api gq.json graphql'
reject "substitution in a wrapper argument" 'fetch ok "repos/o/r/pulls" "$(api gq.json "graphql")"'
cp "$base" "$work/echoqq.sh"
printf '\n%s\n' '"echo" "api" "graphql"' >>"$work/echoqq.sh"
check_file "$work/echoqq.sh"
cp "$base" "$work/echoq.sh"
printf '\n%s\n' 'echo "api"' >>"$work/echoq.sh"
check_file "$work/echoq.sh"
cp "$base" "$work/qfield.sh"
printf '\n%s\n' 'gh api "--field" "name=foo bar" repos/o/r/pulls' >>"$work/qfield.sh"
check_file "$work/qfield.sh"
if ! routes_of "$work/qfield.sh" | grep -qx 'repos/o/r/pulls'; then
  echo "FAIL quoted field argument was split"
  failed=1
else
  echo "ok   quoted field argument kept"
fi
cp "$base" "$work/qjq.sh"
printf '\n%s\n' 'gh api --jq ".[] | .title" repos/o/r/pulls' >>"$work/qjq.sh"
check_file "$work/qjq.sh"
if ! routes_of "$work/qjq.sh" | grep -qx 'repos/o/r/pulls'; then
  echo "FAIL quoted jq argument was split"
  failed=1
else
  echo "ok   quoted jq argument kept"
fi
cp "$base" "$work/glue.sh"
printf '\n%s\n' 'gh api repos/o/r/pulls""' >>"$work/glue.sh"
check_file "$work/glue.sh"
if ! routes_of "$work/glue.sh" | grep -qx 'repos/o/r/pulls'; then
  echo "FAIL glued quotes were left on the route"
  failed=1
else
  echo "ok   glued quotes joined"
fi
cp "$base" "$work/plain.sh"
printf '\n%s\n' 'fetch ok repos/o/r/pulls/1' >>"$work/plain.sh"
check_file "$work/plain.sh"
if ! routes_of "$work/plain.sh" | grep -qx 'repos/o/r/pulls/1'; then
  echo "FAIL unquoted endpoint was missed"
  failed=1
else
  echo "ok   unquoted endpoint kept"
fi
reject "escaped gh api word" 'gh a\pi graphql'
reject "escaped space in the route" 'gh api repos/o/r/pulls\ graphql'
cp "$base" "$work/amp.sh"
printf '\n%s\n' 'gh api repos/o/r/issues?state=open\&per_page=10' >>"$work/amp.sh"
check_file "$work/amp.sh"
if ! routes_of "$work/amp.sh" | grep -qx 'repos/o/r/issues?state=open&per_page=10'; then
  echo "FAIL escaped ampersand was not kept"
  failed=1
else
  echo "ok   escaped ampersand kept"
fi
reject "commented REST path" 'fetch gq "graphql" # "repos/o/r/pulls"'
reject "api after an escaped quote" 'echo \"hello; api gq.json "graphql"\"'
cp "$base" "$work/qarg.sh"
printf '\n%s\n' 'echo \"api gq.json "repos/o/r/pulls"\"' >>"$work/qarg.sh"
check_file "$work/qarg.sh"
cp "$base" "$work/cmt.sh"
printf '\n%s\n' 'echo foo # api gq.json "graphql"' >>"$work/cmt.sh"
check_file "$work/cmt.sh"
cp "$base" "$work/cmtgh.sh"
printf '\n%s\n' 'gh api repos/o/r/pulls # gh api graphql' >>"$work/cmtgh.sh"
check_file "$work/cmtgh.sh"
if routes_of "$work/cmtgh.sh" | grep -qx graphql; then
  echo "FAIL comment was scanned as a call"
  failed=1
else
  echo "ok   comment was not scanned"
fi
printf '%s\n' 'gh api repos/o/r/pulls' >"$work/one.sh"
before=$failed
failed=0
check_file "$work/one.sh"
if [ "$failed" = 0 ]; then
  echo "FAIL one REST route was accepted"
  failed=1
else
  echo "ok   one REST route rejected"
  failed=$before
fi

echo "gh-api-rest: done"
[ "$failed" = 0 ]
