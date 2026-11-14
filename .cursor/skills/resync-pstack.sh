#!/usr/bin/env bash
# Re-copy pstack skills and agents from https://github.com/cursor/plugins.
# Usage: resync-pstack.sh [<commit>]
# With no argument, uses the tip of that repo's main branch.
set -euo pipefail

kept=(architect kitimark-mode no-comments poteto-mode reflect)

root=$(git rev-parse --show-toplevel)
ref=${1:-main}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

skills="$root/.cursor/skills"
src="$skills/PSTACK_SOURCE.md"
pinned=$(sed -n 's/^- Commit: `\([0-9a-f]\{40\}\)`$/\1/p' "$src")

is_kept() {
  local name
  for name in "${kept[@]}"; do
    [[ "$name" == "$1" ]] && return 0
  done
  return 1
}

git -C "$work" init -q plugins
up="$work/plugins"
git -C "$up" remote add origin https://github.com/cursor/plugins.git
git -C "$up" fetch --depth 1 origin "$ref"
git -C "$up" checkout -q --detach FETCH_HEAD

sha=$(git -C "$up" rev-parse HEAD)
tree=$(git -C "$up" rev-parse HEAD:pstack)
ver=$(git -C "$up" show HEAD:pstack/plugin.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')

if [[ -z "$pinned" ]] || ! git -C "$up" fetch -q --depth 1 origin "$pinned"; then
  echo "cannot fetch the pinned commit ${pinned:-(no Commit line in PSTACK_SOURCE.md)}; compare these kept skills with upstream by hand: ${kept[*]}" >&2
  pinned=
fi

if [[ -n "$pinned" ]]; then
  for name in "${kept[@]}"; do
    before=$(git -C "$up" rev-parse -q --verify "$pinned:pstack/skills/$name" || true)
    after=$(git -C "$up" rev-parse -q --verify "HEAD:pstack/skills/$name" || true)
    [[ "$before" == "$after" ]] && continue
    if [[ -z "$after" ]]; then
      echo "upstream removed skill $name; keeping the repository copy" >&2
    elif [[ -z "$before" ]]; then
      echo "upstream added skill $name; keeping the repository copy" >&2
    else
      echo "upstream changed skill $name; keeping the repository copy. Port what applies into .claude/skills/$name/:" >&2
      git -C "$up" diff --stat "$pinned" HEAD -- "pstack/skills/$name" >&2
    fi
  done
fi

git -C "$up" archive HEAD pstack/skills pstack/agents pstack/LICENSE | tar -x -C "$work"

for dir in "$skills"/*/; do
  name=$(basename "$dir")
  is_kept "$name" && continue
  [[ -d "$work/pstack/skills/$name" ]] && continue
  rm -rf "$dir"
done
for dir in "$work/pstack/skills"/*/; do
  name=$(basename "$dir")
  is_kept "$name" && continue
  rm -rf "$skills/$name"
  cp -a "$dir" "$skills/$name"
done

rm -rf "$root/.cursor/agents"
mkdir -p "$root/.cursor/agents"
cp -a "$work/pstack/agents/." "$root/.cursor/agents/"
cp "$work/pstack/LICENSE" "$skills/PSTACK_LICENSE"

tmp=$(mktemp)
awk -v commit="$sha" -v tree="$tree" -v ver="$ver" '
  /^- Commit: / { print "- Commit: `" commit "`"; next }
  /^- `pstack` tree: / { print "- `pstack` tree: `" tree "`"; next }
  /^- Version: / { print "- Version: `" ver "` (`pstack/plugin.json`)"; next }
  { print }
' "$src" > "$tmp"
mv "$tmp" "$src"

echo "vendored pstack $ver at $sha (tree $tree)"
