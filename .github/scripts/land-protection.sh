#!/usr/bin/env bash
# Usage: .github/scripts/land-protection.sh <owner/name> <dir>
set -u

die() { printf 'land-protection: %s\n' "$1" >&2; exit 2; }
[ $# = 2 ] || die "usage: land-protection.sh <owner/name> <dir>"
repo=$1 out=$2
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
for tool in gh jq timeout date; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
[ "${GITHUB_REF:-}" = refs/heads/main ] || die "GITHUB_REF is not refs/heads/main"
[[ ${GITHUB_RUN_ID:-} =~ ^[1-9][0-9]{0,19}$ ]] || die "GITHUB_RUN_ID is not a run id"
[[ ${GITHUB_RUN_ATTEMPT:-} =~ ^[1-9][0-9]{0,4}$ ]] || die "GITHUB_RUN_ATTEMPT is not an attempt"
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"

failed() { printf 'land-protection: %s\n' "$1" >&2; rm -f -- "$out/protection.part" "$out/read.json"; exit 1; }
read=$(date -u +%Y-%m-%dT%H:%M:%SZ) || failed "the clock did not answer"
timeout -k 5 120 gh api "repos/$repo/branches/main/protection" >"$out/protection.part" </dev/null \
  || failed "the read of main's protection failed"
jq -e 'type == "object"' "$out/protection.part" >/dev/null 2>&1 \
  || failed "main's protection is not a JSON object"
jq -c --arg repo "$repo" --argjson run "$GITHUB_RUN_ID" --argjson attempt "$GITHUB_RUN_ATTEMPT" \
  --arg read "$read" \
  '{v: 1, repo: $repo, ref: "refs/heads/main", run: $run, attempt: $attempt, read: $read, protection: .}' \
  "$out/protection.part" >"$out/read.json" || failed "the file was not written"
rm -f -- "$out/protection.part"
printf 'land-protection: read main'"'"'s protection at %s\n' "$read"
