#!/usr/bin/env bash
session_id_ok() { [[ $1 =~ ^[A-Za-z0-9_-]{1,100}$ ]]; }

hook_state() (
  local uid f t
  uid=$(id -u) || return 1
  local -r max_symlinks_followed_per_walk=40 max_record_bytes=2000

  entry_is() { [ -n "$(find "$1" -prune "${@:2}" -print 2>/dev/null)" ]; }
  trusted_lookup_folder() {
    entry_is "$1" -type d \( -user "$uid" -o -user 0 \) \
      \( -perm -1000 -o \( ! -perm -g+w ! -perm -o+w \) \)
  }
  trusted_symlink() { entry_is "$1" -type l \( -user "$uid" -o -user 0 \); }
  folder_is_private() { entry_is "$1" -type d -user "$uid" ! -perm -g+w ! -perm -o+w; }

  walk() {
    local cur=/ rest=$1 c n t links=0
    while [ -n "$rest" ]; do
      c=${rest%%/*}
      if [[ $rest == */* ]]; then rest=${rest#*/}; else rest=''; fi
      case $c in
        '' | .) continue ;;
        ..) cur=${cur%/*}; cur=${cur:-/}; continue ;;
      esac
      trusted_lookup_folder "$cur" || return 1
      n=${cur%/}/$c
      if [ -L "$n" ]; then
        links=$((links + 1))
        [ "$links" -le "$max_symlinks_followed_per_walk" ] || return 1
        trusted_symlink "$n" || return 1
        t=$(readlink -- "$n") || return 1
        [[ $t == /* ]] && cur=/
        rest=$t/$rest
      elif [ -d "$n" ] || { [ "${2:-}" = make ] && (umask 077 && mkdir -- "$n") 2>/dev/null; }; then
        cur=$n
      else
        return 1
      fi
    done
    printf '%s\n' "$cur"
  }

  configured_folder() {
    local d=${MITOS_HOOK_STATE:-}
    if [ -z "$d" ]; then
      if [ -n "${XDG_RUNTIME_DIR:-}" ]; then d=$XDG_RUNTIME_DIR/mitos-hook-state
      elif [ -n "${HOME:-}" ]; then d=$HOME/.cache/mitos-hook-state
      else return 1; fi
    fi
    d=${d%"${d##*[!/]}"}
    [[ $d == /* && ${d##*/} != . && ${d##*/} != .. ]] || return 1
    printf '%s\n' "$d"
  }

  private_folder() {
    local d p
    d=$(configured_folder) || return 1
    if [ "${1:-}" = make ]; then
      [ -e "$d" ] || [ -L "$d" ] || walk "$d" make >/dev/null || true
    fi
    entry_is "$d" -type d || return 1
    p=$(walk "$d") || return 1
    folder_is_private "$p" || return 1
    printf '%s\n' "$p"
  }

  record_file() {
    local p
    session_id_ok "$1" || return 2
    case ${2:-} in
      sha | note | probe-opus | probe-sonnet | probe-haiku | probe-fable) ;;
      *) return 2 ;;
    esac
    p=$(private_folder) || return 1
    printf '%s\n' "$p/$1.$2"
  }

  publish_by_rename() {
    local dest=$1/$2 tmp
    if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then return 1; fi
    tmp=$(mktemp "$1/.$2.XXXXXX" 2>/dev/null) || return 1
    cat >"$tmp" && mv -f "$tmp" "$dest" && return 0
    rm -f "$tmp"
    return 1
  }

  case ${1:-} in
    ensure) private_folder make >/dev/null ;;
    read)
      f=$(record_file "${2:-}" "${3:-}") || return $?
      [ ! -L "$f" ] && [ -f "$f" ] && head -c "$max_record_bytes" "$f" | head -n 1
      ;;
    publish)
      f=$(record_file "${2:-}" "${3:-}") || return $?
      publish_by_rename "${f%/*}" "${f##*/}"
      ;;
    trusted_path)
      [[ ${2:-} == /* ]] || return 1
      walk "$2"
      ;;
    *) return 2 ;;
  esac
)
