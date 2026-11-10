#!/usr/bin/env bash
# The session proxy rewrites the body of every PR create (#91, B1: a plain footer's
# https://claude.ai/code becomes a session link, and a body without that footer, or with no body at
# all, gets a footer with a session link appended). A later PATCH is not given one.
#
# Usage: open-pr.sh --head <branch> --title <title> --body-file <file> [--base <branch>] [--draft]
# The base defaults to main. It prints the PR number and URL and whether the create was rewritten,
# and exits 1 if any call fails or the title or body still holds a session link after the PATCH.
set -u

say() { printf 'open-pr: %s\n' "$1"; }
die() { say "$1" >&2; exit 1; }

usage="usage: open-pr.sh --head <branch> --title <title> --body-file <file> [--base <branch>] [--draft]"
head='' title='' body='' base=main draft=''
while [ $# -gt 0 ]; do
  case $1 in
    --draft) draft=1; shift; continue ;;
    --head | --title | --body-file | --base) [ $# -ge 2 ] || die "$usage" ;;
    *) die "$usage" ;;
  esac
  case $1 in
    --head) head=$2 ;;
    --title) title=$2 ;;
    --body-file) body=$2 ;;
    --base) base=$2 ;;
  esac
  shift 2
done
[ -n "$head" ] && [ -n "$title" ] && [ -n "$body" ] || die "$usage"
[[ $head =~ ^[A-Za-z0-9._/-]+$ && $base =~ ^[A-Za-z0-9._/-]+$ ]] || die "a branch name has a character other than A-Z a-z 0-9 . _ / -"
[ -f "$body" ] && [ -r "$body" ] || die "cannot read the body file $body"
link_re='claude\.ai/code/session_'
grep -Eq "$link_re" "$body" && die "the body file holds a session link; remove it first"
grep -Eq '^[[:space:]>]*Claude-Session:' "$body" && die "the body file holds a Claude-Session line; remove it first"
grep -Eq "$link_re" <<<"$title" && die "the title holds a session link; remove it first"
grep -Eq 'Claude-Session:' <<<"$title" && die "the title holds a Claude-Session line; remove it first"
for tool in gh jq git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

url=$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null) || die "no origin remote"
repo=$(sed -E 's#/+$##; s#\.git$##; s#^.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "origin is not owner/name"

tmp=$(mktemp -d) || die "cannot make a temp dir"
trap 'rm -rf "$tmp"' EXIT

args=(-X POST "repos/$repo/pulls" -f "title=$title" -f "head=$head" -f "base=$base" -F "body=@$body")
[ -n "$draft" ] && args+=(-F draft=true)
gh api "${args[@]}" >"$tmp/create.json" 2>"$tmp/err" || die "the create failed: $(head -c 300 "$tmp/err")"
n=$(jq -r '.number' "$tmp/create.json" 2>/dev/null)
[[ $n =~ ^[0-9]+$ ]] || die "the create answered without a PR number"
say "#$n https://github.com/$repo/pull/$n"

readback() {
  gh api "repos/$repo/pulls/$n" --jq '(.title // "") + "\n" + (.body // "")' >"$1" 2>"$tmp/err" \
    || die "reading #$n back failed: $(head -c 300 "$tmp/err")"
}
readback "$tmp/first"
if ! grep -Eq "$link_re" "$tmp/first"; then
  say "the title and body came back clean at create"
  exit 0
fi
say "the title or body came back with a session link at create; patching both ($body is the body)"
gh api -X PATCH "repos/$repo/pulls/$n" -f "title=$title" -F "body=@$body" >/dev/null 2>"$tmp/err" \
  || die "the PATCH of #$n failed: $(head -c 300 "$tmp/err"); the title or body still holds a session link"
readback "$tmp/second"
if grep -Eq "$link_re" "$tmp/second"; then
  die "#$n still holds a session link after the PATCH, in its title or body; fix it with gh api -X PATCH repos/$repo/pulls/$n -f title=<clean title> -F body=@<clean file>"
fi
say "read back clean after the PATCH; the first revision in the edit history still holds the link"
exit 0
