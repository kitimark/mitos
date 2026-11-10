# shellcheck shell=bash
# Sourced by pr-state.sh, which writes a session's .sha and .note files, and check-agent-spawn.sh,
# which puts the note into agent briefs. Another local user must not choose that text or turn a
# write into a write elsewhere (CWE-59, CWE-367). So the folder is used only by its physical path
# (symlinks above it resolved), and only when no other user can change any part of that path: the
# folder is a real folder, not a symlink, of this user with no group or other write bit, and every
# folder above it belongs to this user or root and has no group or other write bit unless it is
# sticky, as /tmp is, where nobody else can rename an entry they do not own. No file in it is read
# or written through a symlink. The default is per user, so that nobody else can create it first.

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

# Prints the folder's physical path when it is private.
hook_state_private() { # dir
  local uid p a
  uid=$(id -u) || return 1
  [ -n "$(find "$1" -prune -type d -print 2>/dev/null)" ] || return 1
  p=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  [ -n "$(find "$p" -prune -type d -user "$uid" ! -perm -g+w ! -perm -o+w -print 2>/dev/null)" ] || return 1
  a=$p
  while [ "$a" != / ]; do
    a=${a%/*}; a=${a:-/}
    [ -n "$(find "$a" -prune -type d \( -user "$uid" -o -user 0 \) \
      \( -perm -1000 -o \( ! -perm -g+w ! -perm -o+w \) \) -print 2>/dev/null)" ] || return 1
  done
  printf '%s\n' "$p"
}

# Prints the folder's physical path, made with mode 700 (and any missing folder above it) if it is
# missing, when it is private.
hook_state_open() {
  local d
  d=$(hook_state_dir) || return 1
  [ -e "$d" ] || [ -L "$d" ] || (umask 077 && mkdir -p "$d") 2>/dev/null
  hook_state_private "$d"
}

session_id_ok() { [[ $1 =~ ^[A-Za-z0-9_-]{1,100}$ ]]; }

state_read() { # dir, name: the first line, cut at 2000 bytes
  [ ! -L "$1/$2" ] && [ -f "$1/$2" ] && head -c 2000 "$1/$2" | head -n 1
}

# Writes stdin by a rename from a new file in the same folder, which replaces a name and never
# follows it, and refuses a name that is a symlink or anything other than a regular file.
state_write() { # dir, name
  local f=$1/$2 t
  if [ -L "$f" ] || { [ -e "$f" ] && [ ! -f "$f" ]; }; then return 1; fi
  t=$(mktemp "$1/.$2.XXXXXX" 2>/dev/null) || return 1
  cat >"$t" && mv -f "$t" "$f" && return 0
  rm -f "$t"
  return 1
}
