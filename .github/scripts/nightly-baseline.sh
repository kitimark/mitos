#!/usr/bin/env bash
set -euo pipefail

repo=${GITHUB_REPOSITORY:?}
run=${GITHUB_RUN_ID:?}
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $run =~ ^[0-9]+$ ]] || exit 2
base=${RUNNER_TEMP:?}/base
rm -rf "$base"
mkdir -p "$base"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
page=1
while :; do
  gh api -X GET "repos/$repo/actions/workflows/nightly.yml/runs" -f branch=main -f status=completed \
    -f per_page=100 -f page="$page" > "$tmp/runs.json"
  jq -e '.workflow_runs | type == "array"' "$tmp/runs.json" > /dev/null
  jq -r --arg repo "$repo" --argjson current "$run" '.workflow_runs[]
    | select(.id != $current and .path == ".github/workflows/nightly.yml"
        and .head_branch == "main" and .head_repository.full_name == $repo
        and .status == "completed") | .id' "$tmp/runs.json" > "$tmp/ids"
  while read -r id; do
    [[ $id =~ ^[0-9]+$ ]] || exit 1
    gh api --paginate "repos/$repo/actions/runs/$id/artifacts?per_page=100" > "$tmp/artifacts.json"
    jq -se 'all(.[]; .artifacts | type == "array")' "$tmp/artifacts.json" > /dev/null
    artifact=$(jq -sr '[.[].artifacts[]
      | select(.name == "scorecard-numbers" and .expired == false)][0].id // empty' \
      "$tmp/artifacts.json")
    [ -n "$artifact" ] || continue
    [[ $artifact =~ ^[0-9]+$ ]] || exit 1
    gh api "repos/$repo/actions/artifacts/$artifact/zip" > "$tmp/base.zip"
    python3 - "$tmp/base.zip" "$tmp/numbers.tsv" <<'PYZIP'
import stat
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    entries = archive.infolist()
    if len(entries) != 1 or entries[0].filename != "numbers.tsv":
        raise ValueError("scorecard-numbers must hold exactly numbers.tsv")
    kind = stat.S_IFMT(entries[0].external_attr >> 16)
    if kind not in (0, stat.S_IFREG):
        raise ValueError("numbers.tsv must be a regular file")
    with open(sys.argv[2], "wb") as output:
        output.write(archive.read(entries[0]))
PYZIP
    mv "$tmp/numbers.tsv" "$base/numbers.tsv"
    echo "Baseline: nightly run $id, artifact $artifact"
    exit 0
  done < "$tmp/ids"
  count=$(jq '.workflow_runs | length' "$tmp/runs.json")
  [ "$count" -eq 100 ] || break
  page=$((page + 1))
done
echo 'No previous main nightly has an unexpired scorecard-numbers artifact.'
