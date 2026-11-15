#!/usr/bin/env bash
# Usage: carry.sh [--no-build] <pr> <commit>
#
# Whether <commit> covers the head of pull request <pr>: `mitos-gate carry origin/main <commit>
# <head>` of main's tool, over the pushes of the branch. It prints one line:
#   carry #<pr>: <commit> covers <head>          exit 0
#   carry #<pr>: <commit> does not cover <head>  exit 1
# An error prints one `carry:` line on standard error and exits 2. With --no-build it never builds
# main's tool, and a tool that is not built at main is an error.
set -u

say() { printf 'carry: %s\n' "$1" >&2; }
die() { say "$1"; exit 2; }
usage() { die "usage: carry.sh [--no-build] <pr> <commit>"; }

mode=ensure
if [ "${1:-}" = --no-build ]; then mode=ready; shift; fi
[ $# = 2 ] || usage
pr=$1 from=$2
[[ $pr =~ ^[1-9][0-9]{0,6}$ ]] || usage
[[ $from =~ ^[0-9a-f]{40}$ ]] || usage
for tool in gh jq git flock timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR source=lib/origin-repo.sh
source "$here/lib/origin-repo.sh"
# shellcheck source-path=SCRIPTDIR source=lib/main-tool.sh
source "$here/lib/main-tool.sh"
origin_repo
[ -z "${MITOS_MAIN_TOOL:-}" ] || say "MITOS_MAIN_TOOL is set, so the tool is not the one this clone keeps"

w=$(mktemp -d 2>/dev/null) || die "cannot make a temp dir"
trap 'rm -rf "$w"' EXIT
api() {
  local file=$1
  shift
  timeout -k 5 60 gh api "$@" >"$w/$file" 2>/dev/null </dev/null
}

api pr.json "repos/$repo/pulls/$pr" || die "cannot read PR #$pr"
IFS=$'\t' read -r head ref from_repo < <(jq -r \
  '[.head.sha, .head.ref, (.head.repo.full_name // "-")] | @tsv' "$w/pr.json" 2>/dev/null)
[[ ${head:-} =~ ^[0-9a-f]{40}$ ]] || die "PR #$pr has no head commit"
[[ ${ref:-} =~ ^[A-Za-z0-9._/-]+$ && $ref != -* && $ref != *..* ]] \
  || die "PR #$pr has a branch name this script does not put in a route"
[ "${from_repo:-}" = "$repo" ] || die "PR #$pr is from another repository"
pushes="repos/$repo/activity?ref=refs/heads/$ref&direction=desc&per_page=100"
if ! api activity.json --paginate --slurp "$pushes" \
  || ! jq -r '.[][] | [.timestamp, .activity_type, .actor.login, .before, .after] | @tsv' \
    "$w/activity.json" >"$w/activity.tsv" 2>/dev/null; then
  die "cannot read the pushes of PR #$pr"
fi

tool_dir=$(main_tool_dir) || die "not in a clone"
tool_bin=$(main_tool_bin "$tool_dir")
main_tool "$mode" "$tool_dir" 2>"$w/main-tool.err" || die "$(tail -n 1 "$w/main-tool.err")"
timeout -k 5 60 git -C "$tool_dir" fetch -q origin "$ref" "$from" </dev/null 2>/dev/null \
  || die "cannot fetch $ref and ${from:0:7}"
(cd "$tool_dir" && timeout -k 5 120 "$tool_bin" carry origin/main "$from" "$head") \
  <"$w/activity.tsv" >/dev/null 2>"$w/carry.err"
case $? in
  0) echo "carry #$pr: ${from:0:7} covers ${head:0:7}"; exit 0 ;;
  1)
    sed 's/^/carry: /' "$w/carry.err" | head -n 3 >&2
    echo "carry #$pr: ${from:0:7} does not cover ${head:0:7}"
    exit 1 ;;
  124 | 137) die "mitos-gate carry timed out" ;;
  *) die "mitos-gate carry did not answer" ;;
esac
