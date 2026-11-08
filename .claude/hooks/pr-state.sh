#!/usr/bin/env bash
# UserPromptSubmit / SessionStart hook: print current GitHub PR state so the root reads it from
# GitHub instead of from memory or an agent report. Plain stdout is added to the model's context.
# Read-only REST calls through `gh api` (GraphQL is blocked in these sessions). It never blocks a
# prompt: every failure prints one "GitHub state unavailable" line and exits 0.
set -u

unavailable() { echo "GitHub state unavailable: $1"; exit 0; }

command -v gh >/dev/null 2>&1 || unavailable "gh is not installed"
command -v jq >/dev/null 2>&1 || unavailable "jq is not installed"

# owner/name from the origin URL (https, ssh or proxy form). The URL itself is never printed,
# because it can carry a credential.
url=$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null) \
  || unavailable "no origin remote"
repo=$(sed -E 's#/+$##; s#\.git$##; s#^.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || unavailable "origin is not owner/name"

dir=$(mktemp -d 2>/dev/null) || unavailable "cannot make a temp dir"
trap 'rm -rf "$dir"' EXIT

# Four independent calls run in parallel, so the worst case is one 8 second timeout.
fetch() { # name, route
  timeout 8 gh api "$2" >"$dir/$1.json" 2>/dev/null || touch "$dir/$1.failed"
}
fetch open "repos/$repo/pulls?state=open&per_page=11" &
fetch closed "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=20" &
fetch main "repos/$repo/branches/main" &
fetch ci "repos/$repo/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=1" &
wait

for n in open closed main ci; do
  [ -e "$dir/$n.failed" ] && unavailable "gh api for $n failed or timed out"
done

now=$(date -u +%Y-%m-%dT%H:%M)
cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || unavailable "cannot compute the 24 hour cutoff"

out=$(jq -r --arg now "$now" --arg cutoff "$cutoff" \
  --slurpfile closed "$dir/closed.json" --slurpfile main "$dir/main.json" \
  --slurpfile ci "$dir/ci.json" '
  def sha: .[0:7];
  def lst: if length == 0 then "-" else join(",") end;
  def hm: .[0:16] + "Z";
  "GitHub state (read \($now)Z; trust this over memory):",
  (if length == 0 then "open PRs: none"
   else .[0:10][] |
     "open #\(.number) head \(.head.sha | sha) \(if .draft then "draft" else "ready" end) labels=\([.labels[].name] | lst) assignees=\([.assignees[].login] | lst)"
   end),
  (if length > 10 then "open PRs: more than 10, the rest are not listed" else empty end),
  ([$closed[0][] | select(.closed_at != null and .closed_at >= $cutoff)]
     | sort_by(.closed_at) | reverse as $c |
   if ($c | length) == 0 then "closed or merged in the last 24h: none"
   else $c[0:8][] |
     "\(if .merged_at != null then "merged" else "closed" end) #\(.number) at \((.merged_at // .closed_at) | hm) head \(.head.sha | sha)"
   end),
  ($main[0].commit.sha // "" | sha) as $m |
  ($ci[0].workflow_runs[0] // null) as $r |
  "main \($m); latest ci run on main: " +
    (if $r == null then "none"
     else "\($r.status)/\($r.conclusion // "-") head \($r.head_sha | sha)" end)
' "$dir/open.json" 2>/dev/null) || unavailable "unexpected JSON from gh"

[ -n "$out" ] || unavailable "empty answer"
printf '%s\n' "$out"
exit 0
