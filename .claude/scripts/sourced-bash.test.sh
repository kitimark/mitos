#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
failed=0

bash_library() {
  local f=$1 line
  [ -f "$f" ] || return 1
  IFS= read -r line <"$f" || return 1
  [ "$line" = '#!/usr/bin/env bash' ] || return 1
  grep -q 'shellcheck shell=' "$f" && return 1
  return 0
}

libs=("$root"/.claude/scripts/lib/*.sh)
for f in "$root/.claude/hooks/hook-state.sh" "${libs[@]}"; do
  if bash_library "$f"; then
    echo "ok   $(basename "$f")"
  else
    echo "FAIL $(basename "$f") has no bash shebang, or still has a shellcheck shell directive"
    failed=1
  fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf '# shellcheck shell=bash\ntrue\n' >"$work/directive.sh"
printf '#!/bin/sh\ntrue\n' >"$work/sh.sh"
printf '#!/usr/bin/env bash\n# shellcheck shell=bash\ntrue\n' >"$work/both.sh"
printf 'true\n' >"$work/none.sh"
for c in directive sh both none; do
  if bash_library "$work/$c.sh"; then
    echo "FAIL $c was accepted"
    failed=1
  else
    echo "ok   $c rejected"
  fi
done

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "FAIL shellcheck is not installed"
  exit 1
fi

cp "$root/.claude/hooks/hook-state.sh" "$work/hook-state.sh"
sed -i '1s/^#!\/usr\/bin\/env bash$/# not a shebang/' "$work/hook-state.sh"
if shellcheck --shell=sh "$work/hook-state.sh" >"$work/sh-out" 2>&1; then
  echo "FAIL hook-state.sh without its shebang passed a sh check"
  failed=1
else
  echo "ok   hook-state.sh without its shebang fails shellcheck as sh"
fi
if ! shellcheck "$root/.claude/hooks/hook-state.sh" >"$work/sc-hook" 2>&1; then
  echo "FAIL shellcheck hook-state.sh"; cat "$work/sc-hook"; failed=1
else
  echo "ok   shellcheck hook-state.sh"
fi
for f in "${libs[@]}"; do
  if ! shellcheck "$f" >"$work/sc-lib" 2>&1; then
    echo "FAIL shellcheck $(basename "$f")"; cat "$work/sc-lib"; failed=1
  else
    echo "ok   shellcheck $(basename "$f")"
  fi
done
if ! shellcheck -x -S warning "$root/.claude/hooks/pr-state.sh" \
    "$root/.claude/hooks/check-agent-spawn.sh" \
    "$root/.claude/scripts/watch-github.sh" \
    "$root/.claude/scripts/bot-review.sh" \
    "$root/.claude/scripts/carry.sh" >"$work/sc-follow" 2>&1; then
  echo "FAIL shellcheck -x on the scripts that source the libraries"; cat "$work/sc-follow"; failed=1
else
  echo "ok   shellcheck -x follows the sourced libraries"
fi

echo "sourced-bash: done"
[ "$failed" = 0 ]
