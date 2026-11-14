#!/usr/bin/env bash
# Re-copy pstack skills and agents from https://github.com/cursor/plugins.
# Usage: resync-pstack.sh [<commit>]
# With no argument, uses the tip of that repo's main branch.
# Leaves the kept skills and agents below in place and rewrites the SHA lines
# in .cursor/skills/PSTACK_SOURCE.md.
set -euo pipefail

kept_skills=(architect kitimark-mode no-comments poteto-mode principle-split-by-topic reflect show-me-your-work swarm)
kept_agents=(poteto-agent.md)

root=$(git rev-parse --show-toplevel)
ref=${1:-main}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

skills="$root/.cursor/skills"
agents="$root/.cursor/agents"
src="$skills/PSTACK_SOURCE.md"
pinned=$(sed -n 's/^- Commit: `\([0-9a-f]\{40\}\)`$/\1/p' "$src")

is_in() {
  local want=$1 item
  shift
  for item in "$@"; do
    [[ "$item" == "$want" ]] && return 0
  done
  return 1
}

up="$work/plugins"
git -C "$work" init -q plugins
git -C "$up" remote add origin https://github.com/cursor/plugins.git
git -C "$up" fetch -q --depth 1 origin "$ref"
git -C "$up" checkout -q --detach FETCH_HEAD

sha=$(git -C "$up" rev-parse HEAD)
tree=$(git -C "$up" rev-parse HEAD:pstack)
ver=$(git -C "$up" show HEAD:pstack/plugin.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')

kept_paths=()
for name in "${kept_skills[@]}"; do kept_paths+=("pstack/skills/$name"); done
for name in "${kept_agents[@]}"; do kept_paths+=("pstack/agents/$name"); done

if [[ -z "$pinned" ]] || ! git -C "$up" fetch -q --depth 1 origin "$pinned"; then
  echo "cannot fetch the pinned commit ${pinned:-(no Commit line in PSTACK_SOURCE.md)}; compare these kept paths with upstream $sha by hand: ${kept_paths[*]}" >&2
  pinned=
fi

if [[ -n "$pinned" && "$pinned" != "$sha" ]]; then
  changed=0
  for path in "${kept_paths[@]}"; do
    before=$(git -C "$up" rev-parse -q --verify "$pinned:$path" || true)
    after=$(git -C "$up" rev-parse -q --verify "HEAD:$path" || true)
    [[ "$before" == "$after" ]] && continue
    changed=1
    if [[ -z "$after" ]]; then
      echo "upstream removed $path; keeping the repository copy" >&2
    elif [[ -z "$before" ]]; then
      echo "upstream added $path; keeping the repository copy" >&2
    else
      echo "upstream changed $path; keeping the repository copy. Merge what applies by hand:" >&2
      git -C "$up" diff --stat "$pinned" HEAD -- "$path" >&2
    fi
  done
  if [[ $changed == 1 ]]; then
    echo "full diff: https://github.com/cursor/plugins/compare/$pinned...$sha" >&2
    echo "merge these into .cursor/ (and .claude/ where the change applies there) before you commit this re-sync; the next run compares from $sha" >&2
  fi
fi

git -C "$up" archive HEAD pstack/skills pstack/agents pstack/LICENSE | tar -x -C "$work"

for dir in "$skills"/*/; do
  name=$(basename "$dir")
  is_in "$name" "${kept_skills[@]}" && continue
  [[ -d "$work/pstack/skills/$name" ]] && continue
  rm -rf "$dir"
done
for dir in "$work/pstack/skills"/*/; do
  name=$(basename "$dir")
  is_in "$name" "${kept_skills[@]}" && continue
  rm -rf "$skills/$name"
  cp -a "$dir" "$skills/$name"
done

mkdir -p "$agents"
for file in "$agents"/*; do
  [[ -e "$file" ]] || continue
  name=$(basename "$file")
  is_in "$name" "${kept_agents[@]}" && continue
  [[ -e "$work/pstack/agents/$name" ]] && continue
  rm -rf "$file"
done
for file in "$work/pstack/agents"/*; do
  [[ -e "$file" ]] || continue
  name=$(basename "$file")
  is_in "$name" "${kept_agents[@]}" && continue
  rm -rf "$agents/$name"
  cp -a "$file" "$agents/$name"
done
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
