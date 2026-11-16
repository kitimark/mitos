#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
vendor=gate/vendor/l4yaml
if [ "${1:-}" = --if-changed ]; then
  [[ ${HEAD_SHA:-} =~ ^[0-9a-f]{40}$ ]] || { echo 'vendor-provenance: invalid head' >&2; exit 2; }
  case ${EVENT_NAME:-} in
    pull_request)
      [[ ${BASE_SHA:-} =~ ^[0-9a-f]{40}$ ]] || { echo 'vendor-provenance: invalid base' >&2; exit 2; }
      base=$(git merge-base "$BASE_SHA" "$HEAD_SHA") || exit 2 ;;
    push)
      base=${BEFORE_SHA:-}
      if [[ ! $base =~ ^[0-9a-f]{40}$ || $base == 0000000000000000000000000000000000000000 ]]; then base=; fi ;;
    *) echo 'vendor-provenance: invalid event' >&2; exit 2 ;;
  esac
  if [ -n "$base" ]; then
    status=0
    git diff --quiet "$base" "$HEAD_SHA" -- gate/vendor/ || status=$?
    case $status in
      0) echo 'vendor-provenance: vendor unchanged; no upstream fetch'; exit 0 ;;
      1) ;;
      *) echo 'vendor-provenance: cannot compare vendor changes' >&2; exit 2 ;;
    esac
  fi
elif [ "$#" -ne 0 ]; then
  echo 'usage: vendor-provenance.sh [--if-changed]' >&2
  exit 2
fi
work=$(mktemp -d) || { echo 'vendor-provenance: cannot create temporary directory' >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
fail() { printf 'vendor-provenance: %s\n' "$*" >&2; exit 1; }

[ -d "$vendor" ] && [ ! -L gate/vendor ] || fail "$vendor is missing or linked"
linked=$(find gate/vendor -type l -print -quit)
[ -z "$linked" ] || fail "symlink $linked"
unusual=$(find "$vendor" ! -type f ! -type d -print -quit)
[ -z "$unusual" ] || fail "nonregular file $unusual"
for name in PIN MANIFEST; do
  [ -f "$vendor/$name" ] || fail "$vendor/$name is missing"
done
mapfile -t pin < "$vendor/PIN"
[ "${#pin[@]}" -eq 5 ] || fail "$vendor/PIN must have five lines"
[[ ${pin[0]} == url=https://github.com/nasa-jpl/L4YAML && ${pin[1]} =~ ^rev=[0-9a-f]{40}$ &&
   ${pin[2]} =~ ^branch=[A-Za-z0-9._/-]+$ && ${pin[3]} == toolchain="$(cat lean-toolchain)" &&
   ${pin[4]} == entry=L4YAML.Parser.Composition ]] || fail "$vendor/PIN has invalid fields"
rev=${pin[1]#rev=}
toolchain=${pin[3]#toolchain=}
[ -f "$vendor/LICENSE" ] || fail "$vendor/LICENSE is missing"
previous=
while read -r hash path extra || [ -n "${hash:-}${path:-}${extra:-}" ]; do
  [[ $hash =~ ^[0-9a-f]{40}$ && -z $extra &&
     ( $path == LICENSE || $path =~ ^L4YAML/([A-Za-z0-9_]+/)*[A-Za-z0-9_]+\.lean$ ) ]] \
    || fail "$vendor/MANIFEST has an unsafe row for $path"
  [[ -z $previous || $previous < $path ]] || fail "$vendor/MANIFEST is unsorted or duplicates $path"
  previous=$path
  [ -f "$vendor/$path" ] && [ ! -x "$vendor/$path" ] || fail "$vendor/$path is missing or executable"
  [ "$(git hash-object --no-filters "$vendor/$path")" = "$hash" ] || fail "$vendor/$path blob differs"
  printf '%s\n' "$path" >> "$work/expected"
done < "$vendor/MANIFEST"
[ "$(wc -l < "$work/expected")" -eq 20 ] || fail "$vendor/MANIFEST must list 20 files"
find "$vendor" -type f ! -path "$vendor/PIN" ! -path "$vendor/MANIFEST" \
  | sed "s|^$vendor/||" | sort > "$work/actual"
diff -u "$work/expected" "$work/actual" || fail "$vendor file set differs"
metadata=$(find gate/vendor \( -name lean-toolchain -o -name 'lakefile.*' -o -name lake-manifest.json \) -print -quit)
[ -z "$metadata" ] || fail "forbidden build metadata $metadata"

git init --bare -q "$work/upstream" || { echo 'vendor-provenance: cannot initialize fetch directory' >&2; exit 2; }
if ! git -C "$work/upstream" fetch -q --depth 1 "${pin[0]#url=}" "$rev"; then
  echo 'vendor-provenance: cannot fetch pinned revision' >&2
  exit 2
fi
if ! upstream_toolchain=$(git -C "$work/upstream" show "$rev:lean-toolchain"); then
  fail "upstream lean-toolchain is missing"
fi
[ "$upstream_toolchain" = "$toolchain" ] || fail "upstream lean-toolchain differs"
while read -r hash path || [ -n "${hash:-}${path:-}" ]; do
  if ! row=$(git -C "$work/upstream" ls-tree "$rev" -- "$path"); then
    echo 'vendor-provenance: cannot read upstream tree' >&2
    exit 2
  fi
  [ "$row" = "$(printf '100644 blob %s\t%s' "$hash" "$path")" ] || fail "$vendor/$path differs from upstream"
done < "$vendor/MANIFEST"
printf 'vendor-provenance: %s files equal upstream %s\n' "$(wc -l < "$work/expected")" "$rev"
