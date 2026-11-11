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

# fetch_all_pages before fetch, so the longer name is the one that matches.
wrapper_re='fetch_all_pages|fetch|api'

command_head() {
  local s=$1 i c q='' out=''
  for ((i=0; i<${#s}; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      [ "$c" = "$q" ] && q=
      out+=$c
      continue
    fi
    case $c in
      \"|\') q=$c; out+=$c ;;
      \;|\||\&|\)) break ;;
      *) out+=$c ;;
    esac
  done
  printf '%s\n' "$out"
}

# Index of the next fetch/fetch_all_pages/api call in $1, in source order.
# Command words count only at a command boundary, so an earlier if/fetch is
# not skipped for a later $(...), and a call after `;` is still seen.
next_wrapper() {
  local s=$1
  local i=0 n=${#s} c e at=1 q=${2-}
  while (( i < n )); do
    c=${s:i:1}
    if [ -n "${q:-}" ]; then
      # $(...) inside double quotes still runs. Single quotes do not.
      # A q: index tells the caller the enclosing quote is still open.
      # \" \$ \\ and \` stay inside the double-quoted word. \' does not, in single quotes.
      if [ "$q" = '"' ] && [ "$c" = '\' ]; then
        e=${s:i+1:1}
        if [ "$e" = '"' ] || [ "$e" = '$' ] || [ "$e" = '\' ] || [ "$e" = '`' ]; then
          i=$((i + 2))
          continue
        fi
      fi
      if [ "$q" = '"' ] && [ "$c" = '$' ] && [[ ${s:i} =~ ^\$\([[:space:]]*($wrapper_re)[[:space:]] ]]; then
        printf 'q:%s\n' "$i"
        return 0
      fi
      [ "$c" = "$q" ] && q=
      i=$((i + 1))
      continue
    fi
    case $c in
      \"|\') q=$c; i=$((i + 1)); continue ;;
      [[:space:]]) i=$((i + 1)); continue ;;
      \#)
        # A word that begins with # is a comment. foo#bar is one argument.
        if [ "$i" -eq 0 ]; then return 1; fi
        case ${s:i-1:1} in
          [[:space:]]|\;|\&|\||\(|\)|\<|\>) return 1 ;;
        esac
        i=$((i + 1))
        continue ;;
      \;) at=1; i=$((i + 1)); continue ;;
      \&)
        [ "${s:i:2}" = "&&" ] && i=$((i + 1))
        at=1; i=$((i + 1)); continue ;;
      \|)
        [ "${s:i:2}" = "||" ] && i=$((i + 1))
        at=1; i=$((i + 1)); continue ;;
      \() at=1; i=$((i + 1)); continue ;;
      \{)
        [ "$i" -eq 0 ] || [ "${s:i-1:1}" != '$' ] && at=1
        i=$((i + 1)); continue ;;
      \$)
        if [[ ${s:i} =~ ^\$\(($wrapper_re)[[:space:]] ]]; then
          printf '%s\n' "$i"
          return 0
        fi
        i=$((i + 1))
        continue ;;
    esac
    if [ "$at" = 1 ]; then
      if [[ ${s:i} =~ ^(while|until|elif|then|else|if|do)[[:space:]] ]]; then
        i=$((i + ${#BASH_REMATCH[0]}))
        at=1
        continue
      fi
      if [[ ${s:i} =~ ^($wrapper_re)[[:space:]] ]]; then
        printf '%s\n' "$i"
        return 0
      fi
      if [[ ${s:i} =~ ^[A-Za-z0-9_]+ ]]; then
        i=$((i + ${#BASH_REMATCH[0]}))
        if [ "${s:i:1}" = "=" ]; then
          i=$((i + 1))
          # The value is part of the assignment, not the command. A quoted or
          # substituted value is left for the next pass, still at a boundary.
          while (( i < n )); do
            case ${s:i:1} in
              [[:space:]]|\;|\&|\||\)|\"|\'|\$) break ;;
              *) i=$((i + 1)) ;;
            esac
          done
          at=1
          continue
        fi
      else
        i=$((i + 1))
      fi
      at=0
      continue
    fi
    i=$((i + 1))
  done
  return 1
}

blank_span() {
  local s=$1 i=$2 n=$3
  printf '%s%*s%s' "${s:0:i}" "$n" '' "${s:i+n}"
}

# The line bash runs. An unquoted \p is the letter p, so a\pi is the command api.
# An unquoted \ before a separator stays one word, so gh\ api is not gh api.
# An unquoted \" is a quote character in the word, so \"api is not the command api.
# A # at a word boundary ends the line. Quotes keep both.
visible_code() {
  local s=$1
  local i=0 n=${#s} q='' c e out=''
  while (( i < n )); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$q" = '"' ] && [ "$c" = '\' ]; then
        out+="$c${s:i+1:1}"
        i=$((i + 2))
        continue
      fi
      [ "$c" = "$q" ] && q=
      out+=$c
      i=$((i + 1))
      continue
    fi
    case $c in
      \\)
        e=${s:i+1:1}
        [ -n "$e" ] || break
        case $e in
          \'|\") out+=_ ;;
          [[:space:]]|\;|\&|\||\(|\)|\$|\#|\`|\\|\<|\>) out+=$'\1' ;;
          *) out+=$e ;;
        esac
        i=$((i + 2))
        continue ;;
      \"|\') q=$c; out+=$c; i=$((i + 1)); continue ;;
      \#)
        if [ "$i" -eq 0 ]; then break; fi
        case ${s:i-1:1} in
          [[:space:]]|\;|\&|\||\(|\)|\<|\>) break ;;
        esac
        out+=$c; i=$((i + 1)); continue ;;
      *) out+=$c; i=$((i + 1)) ;;
    esac
  done
  printf '%s' "$out"
}

# Drop comments and quoted text. A wrapper call inside $(...) was already blanked,
# so what remains in quotes is data, not a call.
blank_quotes_comments() {
  local s=$1
  local i=0 n=${#s} q='' c e out=''
  while (( i < n )); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$q" = '"' ] && [ "$c" = '\' ]; then
        e=${s:i+1:1}
        out+=' '
        if [ "$e" = '"' ] || [ "$e" = '$' ] || [ "$e" = '\' ] || [ "$e" = '`' ]; then
          out+=' '
          i=$((i + 2))
          continue
        fi
        i=$((i + 1))
        continue
      fi
      [ "$c" = "$q" ] && q=
      out+=' '
      i=$((i + 1))
      continue
    fi
    case $c in
      \"|\') q=$c; out+=' '; i=$((i + 1)); continue ;;
      \#)
        if [ "$i" -eq 0 ]; then
          printf '%s%*s' "$out" "$((n - i))" ''
          return
        fi
        case ${s:i-1:1} in
          [[:space:]]|\;|\&|\||\(|\)|\<|\>)
            printf '%s%*s' "$out" "$((n - i))" ''
            return ;;
        esac
        out+=$c; i=$((i + 1)); continue ;;
      *) out+=$c; i=$((i + 1)) ;;
    esac
  done
  printf '%s' "$out"
}

# 0 when the line still contains a call word the scanner did not take.
# Comments, quoted data, function definitions, and `git fetch` are classified.
unclassified_line() {
  local s=$1 meta idx call guard=0 pre at
  while (( guard++ < 80 )); do
    meta=$(next_wrapper "$s") || break
    idx=$meta
    [[ $meta == q:* ]] && idx=${meta#q:}
    call=$(command_head "${s:idx}")
    [ -n "$call" ] || break
    s=$(blank_span "$s" "$idx" "${#call}")
  done
  guard=0
  while [[ $s =~ gh[[:space:]]+api ]] && (( guard++ < 40 )); do
    pre=${s%%"${BASH_REMATCH[0]}"*}
    at=${#pre}
    s=$(blank_span "$s" "$at" "${#BASH_REMATCH[0]}")
  done
  s=$(blank_quotes_comments "$s")
  s=${s//git fetch/git      }
  guard=0
  while [[ $s =~ (^|[^A-Za-z0-9_])($wrapper_re)[[:space:]]*\(\) ]] && (( guard++ < 20 )); do
    pre=${s%%"${BASH_REMATCH[0]}"*}
    at=${#pre}
    s=$(blank_span "$s" "$at" "${#BASH_REMATCH[0]}")
  done
  if [[ $s =~ (^|[^A-Za-z0-9_])($wrapper_re)([^A-Za-z0-9_]|$) ]]; then
    return 0
  fi
  return 1
}

routes_of() {
  local f=$1 line rest tok nxt quoted route scan call restline idx meta carry_q
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^[a-z_]+\(\)[[:space:]]*\{ ]]; then
      line=${line%% #*}
    fi
    if [[ $line =~ ^[[:space:]]*gh[[:space:]]*\\$ ]]; then
      while [[ $line =~ \\$ ]]; do
        IFS= read -r nxt || break
        line="${line%\\}${nxt}"
      done
    fi
    line=$(visible_code "$line")
    scan=$line
    while [[ $scan =~ gh[[:space:]]+api ]]; do
      rest=${scan#*"${BASH_REMATCH[0]}"}
      scan=$rest
      rest=${rest#"${rest%%[![:space:]]*}"}
      route=
      if [[ $rest == for\ * || $rest == '"$2"'* || $rest == '"${@:2}"'* ]]; then
        continue
      fi
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
    done
    restline=$line
    carry_q=
    while true; do
      if [ -n "$carry_q" ]; then
        meta=$(next_wrapper "$restline" "$carry_q") || break
      else
        meta=$(next_wrapper "$restline") || break
      fi
      carry_q=
      idx=$meta
      if [[ $meta == q:* ]]; then
        idx=${meta#q:}
        carry_q='"'
      fi
      call=$(command_head "${restline:idx}")
      [ -n "$call" ] || break
      quoted=$(grep -oE '"[^"]*"' <<<"$call" || true)
      route=
      while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        tok=${tok#\"}; tok=${tok%\"}
        [[ $tok == *.json ]] && continue
        route=$tok
      done <<<"$quoted"
      [ -n "$route" ] || { echo "call has no route: $line" >&2; return 1; }
      printf '%s\n' "$route"
      restline=${restline:$((idx + ${#call}))}
      case $restline in
        ')'*|';'*|'|'*|'&'*) restline=${restline:1} ;;
      esac
    done
    if [[ $line =~ gh[[:space:]]+api || $line =~ (^|[^A-Za-z0-9_])($wrapper_re)([^A-Za-z0-9_]|$) ]]; then
      if unclassified_line "$line"; then
        echo "unclassified call in $f" >&2
        return 1
      fi
    fi
  done <"$f"
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
    pr-state.sh) min=15 ;;
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
reject "escaped gh api word" 'gh a\pi graphql'
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
