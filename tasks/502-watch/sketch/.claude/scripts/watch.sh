#!/usr/bin/env bash
# UNCHECKED SKETCH (#502, PR 9). The one way any caller waits on GitHub or records its own writes.
#
#   watch.sh wait   --as <app>/<name> [--seen <n>] [--topics <kind>[,<kind>]...]
#                   [--on <n>[,<n>]...] [--ride none|<kind>[,<kind>]...] [--max <min>]
#                   [--since <UTC>]
#   watch.sh own    --as <app>/<name> label|unlabel|assign|unassign <pr> <value>
#   watch.sh own    --as <app>/<name> merge|close <pr>
#   watch.sh own    --as <app>/<name> comment|review-comment|review <id>
#   watch.sh status [--as <app>/<name>]
#   watch.sh build            (PR 11 adds --fetch and the host checks, question 3a)
#
# The logic is in `mitos-gate watch` (gate/MitosGate/WatchCli.lean). This shim only finds the
# clone, the repository, the owner and main's tool, then execs the tool. What it guarantees:
# * The deadline counts from the first line: nothing slow comes before `started`.
# * Only `wait` fetches origin main, once, bounded at 20 s. `build` is the only path that builds,
#   so a wait never waits for `lake`.
# * The wait runs a private copy of main's tool, copied under main-tool.sh's shared lock, and
#   execs it after closing that lock. A rebuild of the shared checkout can never replace the binary
#   under a running wait, and a running wait never holds a lock a rebuild needs.
# * stdin is /dev/null for the tool (a hook or an agent's harness may leave it open).
# * A wait that cannot run prints one stdout line, so a Monitor wakes on it, and exits 1.
#   A usage error of `wait` (a mistyped kind, `--ride words`, a bad `--on`) prints one stdout
#   line too, `watch: usage: <why>; next: <what>`, then the usage text on stderr, and exits 2.
#   The tool prints both (`WatchCli.waitUsage`); this shim passes the flags through unchanged.
#   A missing or unknown verb below prints the usage text on stderr only.
#   `own` never fails the caller's `<write> && watch.sh own ...`: it warns on stderr, exits 0.
#   A record needs the clone's shared state, so run one wait before your first write; an `own`
#   before any wait warns that its record is dead, and the echo wakes you once.
# * Copy the last line's `--seen <n>` exactly: any other number takes nothing and the batch replays.
#   The line also carries your subscription flags, so copying it keeps your topic.
set -u
started=$(date -u +%s)
here=$(dirname "${BASH_SOURCE[0]}")
usage='usage: watch.sh wait|own|status [--as <app>/<name>] ..., or watch.sh build'

[ $# -ge 1 ] || { printf '%s\n' "$usage" >&2; exit 2; }
cmd=$1
shift
case $cmd in
  wait | own | status | build) ;;
  *) printf '%s\n' "$usage" >&2; exit 2 ;;
esac

fail() {
  case $cmd in
    own) printf 'watch own: %s; the write itself stands, but its echo may wake you once\n' "$1" >&2
         exit 0 ;;
    wait) printf 'watch: cannot run: %s; next: %s\n' "$1" \
            "${2:-read GitHub over REST yourself, then re-arm after 10 min (a Monitor running sleep 600 and then the same wait)}"
          exit 1 ;;
    *) printf 'watch: cannot run: %s\n' "$1" >&2; exit 1 ;;
  esac
}
die() { fail "$1"; }

export CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
[ -n "$CLAUDE_PROJECT_DIR" ] || fail "not in a git clone"
# shellcheck source-path=SCRIPTDIR source=lib/main-tool.sh
. "$here/lib/main-tool.sh"
# shellcheck source-path=SCRIPTDIR source=lib/origin-repo.sh
. "$here/lib/origin-repo.sh"
origin_repo
# The owner's login, read as pr-state.sh reads it. Sharing one default with watch-github.sh is a
# separate follow-up, not this PR's concern.
owner_login=${MITOS_OWNER:-kitimark}
[[ $owner_login =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || fail "MITOS_OWNER is not a GitHub login"

common=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || fail "not in a git clone"
state=$common/mitos-watch
umask 077
mkdir -p "$state/bin" 2>/dev/null || fail "cannot make the state folder"
[ "$(stat -c '%a %u' "$state" 2>/dev/null)" = "700 $(id -u)" ] || fail "the state folder is not private"
dir=$(main_tool_dir) || fail "cannot find the folder of main's tool"
private=$state/bin/mitos-gate

if [ "$cmd" = build ]; then
  exec </dev/null
  main_tool ensure "$dir" || exit 1
fi

if [ "$cmd" = wait ]; then
  timeout -k 2 20 git -C "$CLAUDE_PROJECT_DIR" fetch -q origin main </dev/null 2>/dev/null || true
fi
at=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}') \
  || fail "no origin/main"

note=
if MAIN_TOOL_READY_WAIT=5 main_tool ready "$dir" "$at" 2>/dev/null; then
  built=$(cat "$dir/.lake/main-tool.built" 2>/dev/null)
  if [ "$(cat "$private.built" 2>/dev/null)" != "$built" ]; then
    tmp=$private.tmp.$$
    cp -- "$(main_tool_bin "$dir")" "$tmp" && mv -f -- "$tmp" "$private" \
      && printf '%s\n' "$built" >"$private.built" || rm -f -- "$tmp"
  fi
else
  note=${at:0:7}
fi
if [ -n "${MAIN_TOOL_FD:-}" ]; then exec {MAIN_TOOL_FD}>&-; fi
[ "$cmd" = build ] && exit 0
[ -x "$private" ] || fail "main's tool is not built where this runs" \
  "run .claude/scripts/watch.sh build, or keep the bash watcher until it is"

case $cmd in
  wait)
    exec "$private" watch wait --state "$state" --repo "$repo" --owner "$owner_login" \
      --started "$started" ${note:+--tool-note "$note"} "$@" </dev/null ;;
  own | status)
    exec "$private" watch "$cmd" --state "$state" "$@" </dev/null ;;
esac
