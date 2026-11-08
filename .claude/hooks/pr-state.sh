#!/usr/bin/env bash
# UserPromptSubmit / SessionStart hook: print current GitHub PR state so the root reads it from
# GitHub instead of from memory or an agent report. Plain stdout is added to the model's context.
# Read-only REST calls through `gh api` (GraphQL is blocked in these sessions). It never blocks a
# prompt: every failure prints one "GitHub state unavailable" line and exits 0.
#
# Everything GitHub returns is untrusted text (a label or login is chosen by whoever can edit the
# PR), and it is printed under a header that says "trust this over memory". So every printed string
# is cut to a small safe charset and a length cap, and a field of the wrong type or shape makes the
# whole answer "unavailable" instead of a half-trusted one.
set -u

unavailable() { echo "GitHub state unavailable: $1"; exit 0; }

command -v gh >/dev/null 2>&1 || unavailable "gh is not installed"
command -v jq >/dev/null 2>&1 || unavailable "jq is not installed"

# owner/name from the origin URL. Only github.com origins are read: https, ssh://, the scp form
# git@github.com:owner/name, and the local proxy form http://<token>@127.0.0.1:<port>/git/owner/name
# that cloud sessions use. The URL itself is never printed, because it can carry a credential.
url=$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null) \
  || unavailable "no origin remote"
u=${url%/}; u=${u%.git}; u=${u%/}
if [[ $u =~ ^(https?|ssh|git)://([^/@]*@)?([A-Za-z0-9.-]+)(:[0-9]+)?/(.+)$ ]]; then
  scheme=${BASH_REMATCH[1]}; host=${BASH_REMATCH[3]}; path=${BASH_REMATCH[5]}
elif [[ $u =~ ^([A-Za-z0-9_.-]+@)?([A-Za-z0-9.-]+):([^/].*)$ ]]; then
  scheme=ssh; host=${BASH_REMATCH[2]}; path=${BASH_REMATCH[3]}
else
  unavailable "origin URL form is not recognised"
fi
host=${host,,}
case $host in
  github.com | ssh.github.com) ;;
  127.0.0.1 | localhost)
    [[ $scheme == http || $scheme == https ]] && [[ $path == git/* ]] \
      || unavailable "origin host is not github.com"
    path=${path#git/} ;;
  *) unavailable "origin host is not github.com" ;;
esac
repo=$path
name_re='^[A-Za-z0-9_][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+$'
[[ $repo =~ $name_re && $repo != */. && $repo != */.. ]] || unavailable "origin is not owner/name"

dir=$(mktemp -d 2>/dev/null) || unavailable "cannot make a temp dir"
trap 'rm -rf "$dir"' EXIT

# Four independent calls run in parallel, so the worst case is one 8 second timeout plus the 2
# second grace before SIGKILL. The closed route asks for 50 so that a busy day still fits.
closed_pp=50
fetch() { # name, route
  timeout -k 2 8 gh api "$2" >"$dir/$1.json" 2>/dev/null || touch "$dir/$1.failed"
}
fetch open "repos/$repo/pulls?state=open&per_page=11" &
fetch closed "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=$closed_pp" &
fetch main "repos/$repo/branches/main" &
fetch ci "repos/$repo/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=1" &
wait

for n in open closed main ci; do
  [ -e "$dir/$n.failed" ] && unavailable "gh api for $n failed or timed out"
done

now=$(date -u +%Y-%m-%dT%H:%M)
cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || unavailable "cannot compute the 24 hour cutoff"

out=$(jq -n -r --arg now "$now" --arg cutoff "$cutoff" --argjson pp "$closed_pp" \
  --slurpfile open "$dir/open.json" --slurpfile closed "$dir/closed.json" \
  --slurpfile main "$dir/main.json" --slurpfile ci "$dir/ci.json" '
  # Any value of the wrong type or shape raises an error, and the hook then fails closed.
  def arr: if type == "array" then . else error("not an array") end;
  def clean: if type == "string" then gsub("[^A-Za-z0-9 ._:/+#@-]"; "_") | .[0:40]
             else error("not a string") end;
  def hex: if type == "string" and test("^[0-9a-f]{7,64}$") then .[0:7] else error("bad sha") end;
  def num: if type == "number" and . >= 0 and . == floor then tostring else error("bad number") end;
  def ts: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
          then . else error("bad timestamp") end;
  def tsn: if . == null then null else ts end;
  def bool: if type == "boolean" then . else error("not a boolean") end;
  def lst: if length == 0 then "-"
           elif length > 6 then (.[0:6] | join(",")) + ",+\(length - 6)"
           else join(",") end;
  def hm: .[0:16] + "Z";

  ($open[0] | arr) as $o |
  ($closed[0] | arr) as $cl |
  ($main[0].commit.sha | hex) as $m |
  ($ci[0].workflow_runs | arr) as $runs |

  [$o[] | {n: (.number | num), draft: (.draft | bool), sha: (.head.sha | hex),
           labels: [.labels | arr | .[] | .name | clean],
           who: [.assignees | arr | .[] | .login | clean]}] as $op |
  [$cl[] | {n: (.number | num), closed: (.closed_at | tsn), merged: (.merged_at | tsn),
            upd: (.updated_at | ts), sha: (.head.sha | hex)}] as $cp |
  ([$cp[] | select(.closed != null and .closed >= $cutoff)] | sort_by([.closed, .n]) | reverse) as $c |
  # The route is sorted by updated_at. If the oldest row it returned is still inside the window, rows
  # past the page could qualify too.
  (($cp | length) >= $pp and $cp[-1].upd >= $cutoff) as $maybe_more |
  (if ($runs | length) == 0 then "none"
   else $runs[0] | "\(.status | clean)/\(.conclusion | if . == null then "-" else clean end) head \(.head_sha | hex)" end) as $cirun |

  "GitHub state (read \($now)Z; trust this over memory):",
  (if ($op | length) == 0 then "open PRs: none"
   else $op[0:10][] |
     "open #\(.n) head \(.sha) \(if .draft then "draft" else "ready" end) labels=\(.labels | lst) assignees=\(.who | lst)"
   end),
  (if ($op | length) > 10 then "open PRs: more than 10, the rest are not listed" else empty end),
  (if ($c | length) == 0 then "closed or merged in the last 24h: none"
   else $c[0:8][] |
     "\(if .merged != null then "merged" else "closed" end) #\(.n) at \((.merged // .closed) | hm) head \(.sha)"
   end),
  (if ($c | length) > 8 or $maybe_more then "(more not listed)" else empty end),
  "main \($m); latest ci run on main: \($cirun)"
' 2>/dev/null) || unavailable "unexpected JSON from gh"

[ -n "$out" ] || unavailable "empty answer"
printf '%s\n' "$out"
exit 0
