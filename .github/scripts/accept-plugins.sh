#!/usr/bin/env bash
set -euo pipefail

PLUGINS=(
  "ToyRequire:Models.ToyRequire.model"
  "GoMod:Models.GoMod.model"
)

mode=${1:-}
case $mode in
  --record|--no-record) ;;
  *) echo "usage: accept-plugins.sh --record|--no-record" >&2; exit 2 ;;
esac
cd "$(dirname "$0")/../.."
ws=examples/acme
fail() { echo "::error::accept-plugins.sh: $*" >&2; exit 1; }
names() { LC_ALL=C sort | tr '\n' ' '; }

listed=$(printf '%s\n' "${PLUGINS[@]%%:*}" | names)
plugins=$(find "$ws/Plugins" -maxdepth 1 -type f -name '*.lean' -printf '%f\n' | sed 's/\.lean$//' | names)
[ "$listed" = "$plugins" ] || fail "Plugins/ holds [$plugins] and this script accepts [$listed]"
stray=$(find "$ws/accepted" -mindepth 1 ! -regex '.*/[A-Za-z][A-Za-z0-9_]*\.json' -print)
[ -z "$stray" ] || fail "accepted/ holds something that is not a record: $stray"
recorded=$(find "$ws/accepted" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | sed 's/\.json$//' | names)
[ "$listed" = "$recorded" ] || fail "accepted/ holds records for [$recorded] and this script accepts [$listed]"

for entry in "${PLUGINS[@]}"; do
  args=(accept --workspace "$ws" --plugin "${entry%%:*}" --model "${entry#*:}" --paranoid)
  if [ "$mode" = --record ]; then args+=(--record); fi
  lake exe mitos-gate "${args[@]}"
done

if [ "$mode" = --record ]; then
  git diff --exit-code -- "$ws/accepted" \
    || fail "a committed record is not what accept --record writes for this tree; re-record it at the head, after the last rebase"
  left=$(git status --porcelain --untracked-files=all -- "$ws/accepted")
  [ -z "$left" ] || fail "the gate left files that are not committed: $left"
fi
