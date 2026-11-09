#!/usr/bin/env bash
# Re-copy pstack skills and agents from https://github.com/cursor/plugins.
# Usage: resync-pstack.sh [<commit>]
# With no argument, uses the tip of that repo's main branch.
# Leaves .cursor/skills/kitimark-mode/ in place and rewrites the SHA lines
# in .cursor/skills/PSTACK_SOURCE.md.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
ref=${1:-main}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -C "$work" init -q plugins
git -C "$work/plugins" remote add origin https://github.com/cursor/plugins.git
git -C "$work/plugins" fetch --depth 1 origin "$ref"
git -C "$work/plugins" checkout -q --detach FETCH_HEAD

sha=$(git -C "$work/plugins" rev-parse HEAD)
tree=$(git -C "$work/plugins" rev-parse HEAD:pstack)
ver=$(git -C "$work/plugins" show HEAD:pstack/plugin.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')

git -C "$work/plugins" archive HEAD pstack/skills pstack/agents pstack/LICENSE | tar -x -C "$work"

skills="$root/.cursor/skills"
for dir in "$skills"/*/; do
  name=$(basename "$dir")
  [[ "$name" == kitimark-mode ]] && continue
  [[ -d "$work/pstack/skills/$name" ]] && continue
  rm -rf "$dir"
done
for dir in "$work/pstack/skills"/*/; do
  name=$(basename "$dir")
  if [[ "$name" == kitimark-mode ]]; then
    echo "upstream skill kitimark-mode collides; keeping the repository copy" >&2
    continue
  fi
  rm -rf "$skills/$name"
  cp -a "$dir" "$skills/$name"
done

rm -rf "$root/.cursor/agents"
mkdir -p "$root/.cursor/agents"
cp -a "$work/pstack/agents/." "$root/.cursor/agents/"
cp "$work/pstack/LICENSE" "$skills/PSTACK_LICENSE"

src="$root/.cursor/skills/PSTACK_SOURCE.md"
tmp=$(mktemp)
awk -v commit="$sha" -v tree="$tree" -v ver="$ver" '
  /^- Commit: / { print "- Commit: `" commit "`"; next }
  /^- `pstack` tree: / { print "- `pstack` tree: `" tree "`"; next }
  /^- Version: / { print "- Version: `" ver "` (`pstack/plugin.json`)"; next }
  { print }
' "$src" > "$tmp"
mv "$tmp" "$src"

echo "vendored pstack $ver at $sha (tree $tree)"
