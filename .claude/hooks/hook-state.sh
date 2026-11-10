# shellcheck shell=bash
# Sourced by pr-state.sh, which writes a session's .sha and .note files, and check-agent-spawn.sh,
# which puts the note into agent briefs. Another local user must not choose that text or turn a
# write into a write elsewhere (CWE-59, CWE-367). So the folder's name is resolved one part at a
# time, following each symlink as the kernel does, and the folder is used, and a missing folder on
# the way made, only by the physical path that gives, and only when no other user can change where
# the name leads: every folder a part is looked up in, the parts of a symlink's target included,
# belongs to this user or root and has no group or other write bit unless it is sticky, as /tmp
# is, where nobody else can rename an entry they do not own; every symlink on the way belongs to
# this user or root; and the folder is a real folder, not a symlink, of this user with no group or
# other write bit. No file in it is read or written through a symlink. The default is per user, so
# that nobody else can create it first.

hook_state_dir() {
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

# Prints the physical path of an absolute name, resolved one part at a time as the kernel does, when
# each folder a part is looked up in belongs to this user or root and has no group or other write
# bit unless it is sticky, and each symlink on the way belongs to this user or root. Every folder
# above the result was looked up in on the way. With "make", a missing folder is made, with mode
# 700, in a folder that passed. It follows at most 40 symlinks.
hook_state_resolve() {
  local cur=/ rest=$1 c n t links=0
  while [ -n "$rest" ]; do
    c=${rest%%/*}
    if [[ $rest == */* ]]; then rest=${rest#*/}; else rest=''; fi
    case $c in
      '' | .) continue ;;
      ..) cur=${cur%/*}; cur=${cur:-/}; continue ;;
    esac
    [ -n "$(find "$cur" -prune -type d \( -user "$2" -o -user 0 \) \
      \( -perm -1000 -o \( ! -perm -g+w ! -perm -o+w \) \) -print 2>/dev/null)" ] || return 1
    n=${cur%/}/$c
    if [ -L "$n" ]; then
      links=$((links + 1))
      [ "$links" -le 40 ] || return 1
      [ -n "$(find "$n" -prune -type l \( -user "$2" -o -user 0 \) -print 2>/dev/null)" ] || return 1
      t=$(readlink -- "$n") || return 1
      [[ $t == /* ]] && cur=/
      rest=$t/$rest
    elif [ -d "$n" ] || { [ "${3:-}" = make ] && (umask 077 && mkdir -- "$n") 2>/dev/null; }; then
      cur=$n
    else
      return 1
    fi
  done
  printf '%s\n' "$cur"
}

hook_state_private() {
  local uid p
  uid=$(id -u) || return 1
  [ -n "$(find "$1" -prune -type d -print 2>/dev/null)" ] || return 1
  p=$(hook_state_resolve "$1" "$uid") || return 1
  [ -n "$(find "$p" -prune -type d -user "$uid" ! -perm -g+w ! -perm -o+w -print 2>/dev/null)" ] || return 1
  printf '%s\n' "$p"
}

hook_state_open() {
  local d
  d=$(hook_state_dir) || return 1
  [ -e "$d" ] || [ -L "$d" ] || hook_state_resolve "$d" "$(id -u)" make >/dev/null
  hook_state_private "$d"
}

session_id_ok() { [[ $1 =~ ^[A-Za-z0-9_-]{1,100}$ ]]; }

state_read() {
  [ ! -L "$1/$2" ] && [ -f "$1/$2" ] && head -c 2000 "$1/$2" | head -n 1
}

# Writes stdin by a rename from a new file in the same folder, which replaces a name and never
# follows it, and refuses a name that is a symlink or anything other than a regular file.
state_write() {
  local f=$1/$2 t
  if [ -L "$f" ] || { [ -e "$f" ] && [ ! -f "$f" ]; }; then return 1; fi
  t=$(mktemp "$1/.$2.XXXXXX" 2>/dev/null) || return 1
  cat >"$t" && mv -f "$t" "$f" && return 0
  rm -f "$t"
  return 1
}
