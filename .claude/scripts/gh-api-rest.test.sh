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

# i points at '$' of ${...}. PARAM_END is the index after the closing brace.
# A # or ) inside the expansion is data, not a comment or a substitution closer.
param_end() {
  local s=$1 i=$2
  local n=${#s} depth=1 q='' c
  i=$((i + 2))
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
      \$)
        if [ "${s:i+1:1}" = '{' ]; then
          depth=$((depth + 1))
          i=$((i + 1))
        fi
        ;;
      \}) depth=$((depth - 1)) ;;
    esac
    i=$((i + 1))
  done
  if (( depth != 0 )); then
    return 1
  fi
  PARAM_END=$i
}

# Record $(...) that sits inside a parameter expansion. The expansion itself is one word.
harvest_subst() {
  local s=$1
  local i=0 n=${#s} q='' c end=0
  while (( i < n )); do
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
      \'|\" ) q=$c; i=$((i + 1)); continue ;;
      \\) i=$((i + 2)); continue ;;
      \$)
        if [ "${s:i+1:1}" = '(' ] && [ "${s:i+2:1}" != '(' ]; then
          subst_at "$s" "$i" || return 1
          if [ "$SUB_OPEN" = 1 ]; then
            echo "unclosed substitution in $SCAN_FILE" >&2
            return 1
          fi
          LEX_SUBS+=("$SUB_INNER")
          i=$SUB_END
          continue
        fi
        if [ "${s:i+1:1}" = '{' ]; then
          param_end "$s" "$i" || {
            echo "unclosed parameter expansion in $SCAN_FILE" >&2
            return 1
          }
          end=$PARAM_END
          if (( end > i + 3 )); then
            harvest_subst "${s:i+2:end-i-3}" || return 1
          fi
          i=$end
          continue
        fi
        ;;
    esac
    i=$((i + 1))
  done
}

# One shell word, quotes removed. a"pi", "ap"i, f""etch and 'api' are api.
# An unquoted \p is p, so a\pi is api. An unquoted \ before a separator stays
# in the word, so gh\ api is not gh api and a route's \  is a space.
# \$ \" \` and \\ inside double quotes are the escaped character. A single
# quote has no escapes. $(...) is recorded and scanned on its own; $(( is arithmetic.
read_word() {
  local s=$1 i=$2
  local n=${#s} c e q='' word='' bare=0 sawq=0 sub=0 start=$2 pend=0
  RW_CONT=0
  RW_OPEN=0
  while (( i < n )); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$q" = '"' ] && [ "$c" = "$backslash" ]; then
        e=${s:i+1:1}
        if [ -z "$e" ]; then
          RW_CONT=1
          break
        fi
        case $e in
          '"'|'$'|'`'|"$backslash") word+=$e ;;
          *) word+=$c$e ;;
        esac
        i=$((i + 2))
        continue
      fi
      if [ "$q" = '"' ] && [ "$c" = '`' ]; then
        echo "unclassified backtick in $SCAN_FILE" >&2
        return 1
      fi
      if [ "$q" = '"' ] && [ "$c" = '$' ] && [ "${s:i+1:1}" = '(' ] && [ "${s:i+2:1}" != '(' ]; then
        subst_at "$s" "$i"
        if [ "$SUB_OPEN" = 1 ]; then
          RW_OPEN=1
          break
        fi
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
        # ""# is one word. # starts a comment only when the word has not started.
        (( i > start )) || break
        word+=$c
        bare=1
        i=$((i + 1))
        continue ;;
      \\)
        e=${s:i+1:1}
        if [ -z "$e" ]; then
          RW_CONT=1
          break
        fi
        word+=$e
        # \{ and \} are literal words, not grouping braces.
        if [ "$e" != '{' ] && [ "$e" != '}' ]; then bare=1; fi
        i=$((i + 2))
        continue ;;
      \`)
        echo "unclassified backtick in $SCAN_FILE" >&2
        return 1 ;;
      \"|\')
        sawq=1
        q=$c
        i=$((i + 1))
        continue ;;
      \$)
        if [ "${s:i+1:1}" = '(' ] && [ "${s:i+2:1}" != '(' ]; then
          subst_at "$s" "$i"
          if [ "$SUB_OPEN" = 1 ]; then
            RW_OPEN=1
            break
          fi
          LEX_SUBS+=("$SUB_INNER")
          sub=1
          i=$SUB_END
          continue
        fi
        if [ "${s:i+1:1}" = '{' ]; then
          param_end "$s" "$i" || {
            echo "unclosed parameter expansion in $SCAN_FILE" >&2
            return 1
          }
          pend=$PARAM_END
          word+=${s:i:pend-i}
          bare=1
          if (( pend > i + 3 )); then
            harvest_subst "${s:i+2:pend-i-3}" || return 1
          fi
          i=$pend
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
# A # at the start of a word comments out the rest of the line, so a ) there
# does not close the substitution.
subst_at() {
  local s=$1 i=$2
  local n=${#s} depth=1 q='' c boundary=1
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
    if [ "$c" = '$' ] && [ "${s:i+1:1}" = '{' ]; then
      param_end "$s" "$i" || {
        echo "unclosed parameter expansion in $SCAN_FILE" >&2
        return 1
      }
      i=$PARAM_END
      boundary=0
      continue
    fi
    if [ "$boundary" = 1 ] && [ "$c" = '#' ]; then
      while (( i < n )) && [ "${s:i:1}" != $'\n' ]; do
        i=$((i + 1))
      done
      continue
    fi
    case $c in
      \'|\" ) q=$c; boundary=0 ;;
      \\) i=$((i + 1)); boundary=0 ;;
      \() depth=$((depth + 1)); boundary=1 ;;
      \)) depth=$((depth - 1)); boundary=1 ;;
      [[:space:]]|\;|\&|\||\<|\>) boundary=1 ;;
      *) boundary=0 ;;
    esac
    i=$((i + 1))
  done
  SUB_END=$i
  if (( depth == 0 )); then
    SUB_INNER=${s:start:i-start-1}
    SUB_OPEN=0
  else
    SUB_INNER=${s:start}
    SUB_OPEN=1
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
    # A newline separates commands. A comment runs to the next newline only.
    if [ "$c" = $'\n' ]; then push_op ';'; i=$((i + 1)); continue; fi
    if [ "$c" = '#' ]; then
      while (( i < n )) && [ "${s:i:1}" != $'\n' ]; do i=$((i + 1)); done
      continue
    fi
    case $c in
      [[:space:]]) i=$((i + 1)); continue ;;
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
        if [ "${s:i:3}" = '<<<' ]; then push_op '<<<'; i=$((i + 3))
        elif [ "${s:i:2}" = '<<' ]; then push_op '<<'; i=$((i + 2))
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
    read_word "$s" "$i" || return 1
    if [ "$RW_CONT" = 1 ] || [ "$RW_OPEN" = 1 ]; then
      return 0
    fi
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
      -X|--method|-f|-F|--raw-field|--field|--jq|--input|--header|-H|--cache)
        j=$((j + 1))
        if (( j < n )) && [ "${LEX_KIND[j]}" = w ]; then j=$((j + 1)); fi
        continue ;;
      --method=*|--raw-field=*|--field=*|--jq=*|--input=*|--header=*|--hostname=*|--cache=*)
        j=$((j + 1))
        continue ;;
      --paginate|--slurp|--silent|--verbose)
        j=$((j + 1))
        continue ;;
      -*)
        echo "unclassified flag $arg in $SCAN_FILE" >&2
        return 1 ;;
      '$2'|'${@:2}')
        if is_wrapper "${FN-}" && (( FN_DEPTH > 0 )); then
          saw=1
          route=''
          j=$((j + 1))
          break
        fi
        echo "gh api has no route in $SCAN_FILE" >&2
        return 1 ;;
      '')
        if [ "${LEX_SUBW[j]}" = 1 ]; then
          echo "gh api has no route in $SCAN_FILE" >&2
          return 1
        fi
        j=$((j + 1))
        continue ;;
    esac
    if [ "${LEX_SUBW[j]}" = 1 ]; then
      echo "gh api has no route in $SCAN_FILE" >&2
      return 1
    fi
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
  if [ "$subw" = 1 ]; then
    echo "call has no route in $SCAN_FILE" >&2
    return 1
  fi
  j=$((j + 1))
  while (( j < n )) && [ "${LEX_KIND[j]}" = w ]; do
    j=$((j + 1))
  done
  if [ -n "$route" ]; then
    ROUTES+=("$route")
  else
    echo "call has no route in $SCAN_FILE" >&2
    return 1
  fi
  GH_END=$j
}

# The next word after one of these is the command. Options stay with the prefix.
pass_prefix() {
  local name=$1 a lookup=0
  i=$((i + 1))
  while (( i < n )) && [ "${LEX_KIND[i]}" = w ]; do
    a=${LEX_TEXT[i]}
    case $name in
      drop_lock_fd|nohup)
        if [ "$a" = -- ]; then i=$((i + 1)); continue; fi
        break ;;
      command)
        case $a in
          -v|-V) lookup=1; i=$((i + 1)); continue ;;
          -p|--) i=$((i + 1)); continue ;;
          -*)
            echo "unclassified command flag $a in $SCAN_FILE" >&2
            return 1 ;;
          *) break ;;
        esac ;;
      exec)
        case $a in
          -a|--argv0)
            i=$((i + 1))
            if (( i < n )) && [ "${LEX_KIND[i]}" = w ]; then i=$((i + 1)); fi
            continue ;;
          -a*|-c|-l|--) i=$((i + 1)); continue ;;
          -*)
            echo "unclassified exec flag $a in $SCAN_FILE" >&2
            return 1 ;;
          *) break ;;
        esac ;;
      env)
        case $a in
          -u|-C|--unset|--chdir)
            i=$((i + 1))
            if (( i < n )) && [ "${LEX_KIND[i]}" = w ]; then i=$((i + 1)); fi
            continue ;;
          -u*|--unset=*|--chdir=*|-i|-0|--) i=$((i + 1)); continue ;;
          -*)
            echo "unclassified env flag $a in $SCAN_FILE" >&2
            return 1 ;;
          *) break ;;
        esac ;;
      nice)
        case $a in
          -n|--adjustment)
            i=$((i + 1))
            if (( i < n )) && [ "${LEX_KIND[i]}" = w ]; then i=$((i + 1)); fi
            continue ;;
          --adjustment=*|-n*|-[0-9]*|--) i=$((i + 1)); continue ;;
          -*)
            echo "unclassified nice flag $a in $SCAN_FILE" >&2
            return 1 ;;
          *) break ;;
        esac ;;
      stdbuf)
        case $a in
          -i|-o|-e)
            i=$((i + 1))
            if (( i < n )) && [ "${LEX_KIND[i]}" = w ]; then i=$((i + 1)); fi
            continue ;;
          -i*|-o*|-e*|--) i=$((i + 1)); continue ;;
          -*)
            echo "unclassified stdbuf flag $a in $SCAN_FILE" >&2
            return 1 ;;
          *) break ;;
        esac ;;
      xargs)
        case $a in
          -I|-i|-L|-n|-P|-s|-E|-e|-a|-d|--max-args|--max-procs|--max-chars|--delimiter|--arg-file|--replace|--eof)
            i=$((i + 1))
            if (( i < n )) && [ "${LEX_KIND[i]}" = w ]; then i=$((i + 1)); fi
            continue ;;
          -*) i=$((i + 1)); continue ;;
          *) break ;;
        esac ;;
    esac
  done
  # command -v looks a name up. The words after it are not commands.
  if [ "$lookup" = 1 ]; then
    while (( i < n )) && [ "${LEX_KIND[i]}" = w ]; do
      i=$((i + 1))
    done
  fi
}

walk_line() {
  local n=${#LEX_KIND[@]} i=0 at=1 w bare
  local SKIP_FETCH=-1 IN_TEST=0 st
  while (( i < n )); do
    if [ "${LEX_KIND[i]}" = o ]; then
      case ${LEX_TEXT[i]} in
        ';'|'&'|'&&'|'|'|'||'|'|&'|'('|')')
          if (( IN_TEST == 0 )); then at=1; fi ;;
        '<<<'|'>'|'<'|'>>'|'>&'|'<&'|'&>')
          if (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ]; then i=$((i + 1)); fi
          ;;
        '<<')
          echo "unclassified here-document in $SCAN_FILE" >&2
          return 1 ;;
      esac
      i=$((i + 1))
      continue
    fi
    w=${LEX_TEXT[i]}
    bare=${LEX_BARE[i]}
    if [ "$w" = ']]' ] && (( IN_TEST > 0 )); then
      IN_TEST=$((IN_TEST - 1))
    fi
    if [ "$w" = '{' ] && [ "$bare" = 1 ]; then
      if [ -n "${FN-}" ]; then
        FN_DEPTH=$((FN_DEPTH + 1))
      fi
      at=1
      i=$((i + 1))
      continue
    fi
    if [ "$w" = '}' ] && [ "$bare" = 1 ]; then
      if [ -n "${FN-}" ]; then
        FN_DEPTH=$((FN_DEPTH - 1))
        if (( FN_DEPTH <= 0 )); then
          FN=
          FN_DEPTH=0
        fi
      fi
      at=1
      i=$((i + 1))
      continue
    fi
    if [ "$at" = 1 ]; then
      if [ "$bare" = 1 ]; then
        case $w in
          if|while|until|elif|then|else|do|'!'|time|-p)
            i=$((i + 1))
            continue ;;
        esac
      fi
      if [[ $w =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        i=$((i + 1))
        continue
      fi
      if [[ $w =~ ^[0-9]+$ ]] && (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = o ]; then
        case ${LEX_TEXT[i+1]} in
          '>'|'<'|'>>'|'>&'|'<&'|'&>'|'<<'|'<<<')
            i=$((i + 1))
            continue ;;
        esac
      fi
      if (( i + 2 < n )) && [ "${LEX_KIND[i+1]}" = o ] && [ "${LEX_TEXT[i+1]}" = '(' ] \
        && [ "${LEX_KIND[i+2]}" = o ] && [ "${LEX_TEXT[i+2]}" = ')' ]; then
        FN=$w
        FN_DEPTH=0
        i=$((i + 3))
        at=0
        continue
      fi
      # timeout's next command is still the command, so gh "api" is a call.
      if [ "$w" = timeout ]; then
        i=$((i + 1))
        while (( i < n )) && [ "${LEX_KIND[i]}" = w ]; do
          case ${LEX_TEXT[i]} in
            -k|--kill-after|-s|--signal)
              i=$((i + 1))
              if (( i < n )) && [ "${LEX_KIND[i]}" = w ]; then i=$((i + 1)); fi
              continue ;;
            --kill-after=*|--signal=*|--)
              i=$((i + 1))
              continue ;;
            --foreground|-v|--verbose|--preserve-status)
              i=$((i + 1))
              continue ;;
            -*)
              echo "unclassified timeout flag ${LEX_TEXT[i]} in $SCAN_FILE" >&2
              return 1 ;;
            *)
              i=$((i + 1))
              break ;;
          esac
        done
        continue
      fi
      case $w in
        command|env|nohup|exec|nice|stdbuf|xargs|drop_lock_fd)
          pass_prefix "$w"
          st=$?
          if [ "$st" = 1 ]; then return 1; fi
          if [ "$st" = 0 ]; then continue; fi
          ;;
      esac
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
      if [ "$w" = '[[' ]; then
        IN_TEST=$((IN_TEST + 1))
      fi
      if [[ $w == *'$'* && $w != '$' ]]; then
        if [ "$w" = '$@' ] && [ -n "${FN-}" ] && (( FN_DEPTH > 0 )); then
          at=0
          i=$((i + 1))
          continue
        fi
        echo "unclassified command in $SCAN_FILE" >&2
        return 1
      fi
      if [ "$w" = eval ]; then
        echo "unclassified command in $SCAN_FILE" >&2
        return 1
      fi
      if [[ $w == bash || $w == sh || $w == zsh ]] \
        && (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ] && [ "${LEX_TEXT[i+1]}" = -c ]; then
        echo "unclassified command in $SCAN_FILE" >&2
        return 1
      fi
      at=0
      i=$((i + 1))
      continue
    fi
    # A bare api here is the gh subcommand. A quoted api is an argument, as in echo.
    if [ "$w" = gh ] && (( i + 1 < n )) && [ "${LEX_KIND[i+1]}" = w ] \
      && [ "${LEX_TEXT[i+1]}" = api ] && [ "${LEX_BARE[i+1]}" = 1 ]; then
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
  lex_line "$s" || return 1
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

# End state of one physical line. SS_Q, SS_DEPTH and SS_INWORD carry in.
# A backslash at the end sets SS_CONT. A backtick outside single quotes fails.
step_line() {
  local s=$1
  local i=0 n=${#s} c e
  local q=$SS_Q depth=$SS_DEPTH inword=$SS_INWORD
  if [ -n "$q" ]; then inword=1; fi
  SS_CONT=0
  while (( i < n )); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$q" = '"' ] && [ "$c" = "$backslash" ]; then
        e=${s:i+1:1}
        if [ -z "$e" ]; then SS_CONT=1; break; fi
        i=$((i + 2))
        continue
      fi
      if [ "$q" = '"' ] && [ "$c" = '`' ]; then
        echo "unclassified backtick in $SCAN_FILE" >&2
        return 1
      fi
      if [ "$c" = "$q" ]; then q=; fi
      i=$((i + 1))
      continue
    fi
    if (( depth > 0 )); then
      case $c in
        "'") q="'" ;;
        '"') q='"' ;;
        \\)
          e=${s:i+1:1}
          if [ -z "$e" ]; then SS_CONT=1; break; fi
          i=$((i + 2))
          continue ;;
        \() depth=$((depth + 1)); inword=0 ;;
        \)) depth=$((depth - 1)); inword=0 ;;
        \`)
          echo "unclassified backtick in $SCAN_FILE" >&2
          return 1 ;;
        \#)
          if [ "$inword" = 0 ]; then
            SS_Q=$q
            SS_DEPTH=$depth
            SS_INWORD=0
            return 0
          fi ;;
        [[:space:]]|\;|\&|\||\<|\>) inword=0 ;;
        *) inword=1 ;;
      esac
      i=$((i + 1))
      continue
    fi
    case $c in
      [[:space:]]|\;|\&|\||\(|\)|\<|\>) inword=0; i=$((i + 1)); continue ;;
      \#)
        if [ "$inword" = 0 ]; then
          SS_Q=
          SS_DEPTH=0
          SS_INWORD=0
          return 0
        fi
        i=$((i + 1))
        continue ;;
      \\)
        e=${s:i+1:1}
        if [ -z "$e" ]; then SS_CONT=1; break; fi
        inword=1
        i=$((i + 2))
        continue ;;
      \`)
        echo "unclassified backtick in $SCAN_FILE" >&2
        return 1 ;;
      \$)
        if [ "${s:i+1:1}" = '(' ] && [ "${s:i+2:1}" != '(' ]; then
          depth=1
          inword=0
          i=$((i + 2))
          continue
        fi
        inword=1
        i=$((i + 1))
        continue ;;
      \"|\') q=$c; inword=1; i=$((i + 1)); continue ;;
      *) inword=1; i=$((i + 1)); continue ;;
    esac
  done
  SS_Q=$q
  SS_DEPTH=$depth
  SS_INWORD=$inword
}

routes_of() {
  local f=$1 line buf='' join_back=0
  SCAN_FILE=$f
  ROUTES=()
  FN=
  FN_DEPTH=0
  SS_Q=
  SS_DEPTH=0
  SS_INWORD=0
  # A backslash continues a line except inside a comment. A quote or a
  # $(...) stays open across lines. An open quote at the end of the file fails.
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$buf" ]; then
      buf=$line
    elif [ "$join_back" = 1 ]; then
      buf=${buf%"$backslash"}$line
    else
      buf+=$'\n'$line
    fi
    step_line "$line" || return 1
    join_back=$SS_CONT
    if [ "$SS_CONT" != 1 ]; then SS_INWORD=0; fi
    if [ -n "$SS_Q" ] || [ "$SS_CONT" = 1 ] || (( SS_DEPTH > 0 )); then
      continue
    fi
    scan_text "$buf" || return 1
    buf=
    SS_Q=
    SS_DEPTH=0
    SS_INWORD=0
  done <"$f"
  if [ -n "$SS_Q" ]; then
    echo "unclosed quote in $f" >&2
    return 1
  fi
  if (( SS_DEPTH > 0 )); then
    echo "unclosed substitution in $f" >&2
    return 1
  fi
  if [ -n "$buf" ]; then
    scan_text "$buf" || return 1
  fi
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
printf '\necho api extra.json "repos/o/r/pulls/1"\n' >>"$work/miss.sh"
status=0
routes_of "$work/miss.sh" >/dev/null 2>&1 || status=$?
if [ "$status" = 0 ]; then
  echo "FAIL unclassified call was accepted"
  failed=1
else
  echo "ok   unclassified call failed closed"
fi
cp "$base" "$work/envapi.sh"
printf '\nenv api extra.json "repos/o/r/pulls/1"\n' >>"$work/envapi.sh"
check_file "$work/envapi.sh"
if ! routes_of "$work/envapi.sh" | grep -qx 'repos/o/r/pulls/1'; then
  echo "FAIL env api route was not extracted"
  failed=1
else
  echo "ok   env api route extracted"
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

closed_error() {
  local name=$1 line=$2 copy="$work/bad.sh" status=0
  cp "$base" "$copy"
  printf '\n%s\n' "$line" >>"$copy"
  routes_of "$copy" >/dev/null 2>"$work/scan.err" || status=$?
  if [ "$status" = 0 ]; then
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
cp "$base" "$work/echogh.sh"
printf '\n%s\n' 'echo gh "api" graphql' >>"$work/echogh.sh"
check_file "$work/echogh.sh"
reject "timeout then quoted api" 'timeout 20 gh "api" graphql'
reject "command then quoted api" 'command gh "api" graphql'
reject "partially quoted command" 'c"ommand" gh "api" graphql'
reject "partially quoted timeout" 't"imeout" 20 gh "api" graphql'
closed_error "partially quoted eval" "e\"val\" 'gh api graphql'"
closed_error "partially quoted bash" "b\"ash\" -c 'gh api graphql'"
cp "$base" "$work/lookup.sh"
printf '\n%s\n' 'command -v api' >>"$work/lookup.sh"
check_file "$work/lookup.sh"
echo "ok   command -v api is a lookup"
reject "lookup argument runs" 'command -v "$(api gq.json "graphql")"'
reject "env then quoted api" 'env gh "api" graphql'
reject "nohup then quoted api" 'nohup gh "api" graphql'
reject "exec then quoted api" 'exec gh "api" graphql'
reject "nice then quoted api" 'nice gh "api" graphql'
reject "stdbuf then quoted api" 'stdbuf -oL gh "api" graphql'
reject "xargs then quoted api" 'xargs gh "api" graphql'
reject "drop_lock_fd then quoted api" 'drop_lock_fd gh "api" graphql'
reject "drop_lock_fd then timeout" 'drop_lock_fd timeout 20 gh "api" graphql'
reject "drop_lock_fd then api" 'drop_lock_fd "api" gq.json "graphql"'
reject "newline restores the command" $'x=$(\necho hi\n"api" gq.json "graphql"\n)'
reject "comment ends at the newline" $'x=$(\necho a # note\napi gq.json "graphql"\n)'
reject "hash after a semicolon" $'echo x;#\'\napi gq.json "graphql"\necho y;#\''
closed_error "here-document body" $'cat <<EOF\nit\'s $(api gq.json "graphql")\ndon\'t\nEOF'
closed_error "expanded command" 'c=api; $c gq.json graphql'
closed_error "expanded gh" 'c=gh; $c "api" graphql'
closed_error "eval" "eval 'gh api graphql'"
closed_error "bash -c" "bash -c 'gh api graphql'"
closed_error "sh -c" "sh -c 'api gq.json graphql'"
closed_error "zsh -c" "zsh -c 'gh api graphql'"
cp "$base" "$work/cache.sh"
printf '\n%s\n' 'gh api --cache 1h repos/o/r/pulls' >>"$work/cache.sh"
check_file "$work/cache.sh"
if ! routes_of "$work/cache.sh" | grep -qx 'repos/o/r/pulls'; then
  echo "FAIL cache duration was taken as the route"
  failed=1
else
  echo "ok   cache duration skipped"
fi
reject "time api" 'time "api" gq.json "graphql"'
reject "time -p api" 'time -p "api" gq.json "graphql"'
reject "case arm api" 'case x in a) "api" gq.json "graphql";; esac'
reject "redirection before api" '2>/dev/null "api" gq.json "graphql"'
reject "hash after empty quotes" '""#; api gq.json "graphql"'
reject "hash after a substitution" '$(true)#; api gq.json "graphql"'
reject "commented paren in a substitution" $'x="$(\n  # )\n  api gq.json "graphql"\n)"'
reject "hash inside a parameter expansion" 'x="$(echo ${v:- #}; api gq.json graphql)"'
reject "command substitution inside a parameter expansion" 'x="$(echo ${v:-$(api gq.json graphql)})"'
closed_error "escaped brace ends the function" $'fetch() { : \\{; }\nset -- ignored graphql\ngh api "$2"'
closed_error "quoted brace ends the function" $'fetch() { : \'{\'; }\nset -- ignored graphql\ngh api "$2"'
reject "comment does not continue" $': # \\\napi gq.json "graphql"'
reject "quote closes on the next line" $'echo \'\n\'; api gq.json "graphql"'
closed_error "unclosed quote" $'echo \''
closed_error "route outside a wrapper" $'g() { gh api "$2"; }\ng x graphql'
closed_error "substituted route" 'fetch ok "$(echo graphql)"'
closed_error "substituted gh route" 'gh api "$(echo graphql)"'
closed_error "partial substituted route" 'gh api "repos/o/r/$(echo graphql)"'
closed_error "backtick assignment" 'x=`api gq.json "graphql"`'
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
