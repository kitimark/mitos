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
#
# Rules freshness (#91, B2). At SessionStart it records the commit whose rules the session loaded
# (HEAD of the project checkout) under the session id from the hook input. On every run it names
# the rule files (.claude/, CLAUDE.md, docs/process.md) that changed on main since that commit and
# says to read them, and it leaves the same note where check-agent-spawn.sh adds it to each spawn.
# A session with no record yet records HEAD at its first prompt.
#
# Merge readiness (#91, B5). For each open PR from the owner's account it adds `gate` at the head,
# the verdict head on the Owner dashboard, the owner's unanswered comments and whether the PR
# touches a path the user keeps. Only when the dashboard's verdict head is the current head, `gate`
# is green there and no owner comment is unanswered, it prints a merge command pinned to that head.
# It never prints one that reads the head when it runs, because that drops the link to the head the
# verifiers checked. An owner comment is unanswered (B3) when it does not end with the Claude Code
# footer and is newer than the latest footer comment on the same PR, read from the newest 100 issue
# comments and the newest 100 review comments of the repository; older ones and reviews are left to
# watch-github.sh, which reads whole threads.
#
# Environment: MITOS_OWNER, the owner's login (default kitimark); MITOS_HOOK_STATE, the directory
# for the per-session records (default $TMPDIR/mitos-hook-state).
set -u

unavailable() { echo "GitHub state unavailable: $1"; exit 0; }

command -v gh >/dev/null 2>&1 || unavailable "gh is not installed"
command -v jq >/dev/null 2>&1 || unavailable "jq is not installed"

# The hook input names the session and the event; a run by hand has none.
input=''
[ -t 0 ] || input=$(cat 2>/dev/null)
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)
[[ $sid =~ ^[A-Za-z0-9_-]{1,100}$ ]] || sid=''
owner=${MITOS_OWNER:-kitimark}
[[ $owner =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || unavailable "MITOS_OWNER is not a GitHub login"
proj=${CLAUDE_PROJECT_DIR:-.}

# The commit whose rules this session loaded: HEAD at SessionStart, or at the first run that finds
# no record. Without a session id there is nothing to key it by, so freshness is skipped.
loaded='' state=''
if [ -n "$sid" ]; then
  state=${MITOS_HOOK_STATE:-${TMPDIR:-/tmp}/mitos-hook-state}
  if mkdir -p "$state" 2>/dev/null; then
    loaded=$(cat "$state/$sid.sha" 2>/dev/null)
    if [ "$event" = SessionStart ] || ! [[ $loaded =~ ^[0-9a-f]{40}$ ]]; then
      loaded=$(git -C "$proj" rev-parse HEAD 2>/dev/null)
      if [[ $loaded =~ ^[0-9a-f]{40}$ ]]; then printf '%s\n' "$loaded" >"$state/$sid.sha"; else loaded=''; fi
    fi
  else
    state=''
  fi
fi

# owner/name from the origin URL. Only github.com origins are read: https, ssh://, the scp form
# git@github.com:owner/name, and the local proxy form http://<token>@127.0.0.1:<port>/git/owner/name
# that cloud sessions use. The URL itself is never printed, because it can carry a credential.
url=$(git -C "$proj" remote get-url origin 2>/dev/null) \
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

# Two rounds of parallel calls, each cut at 5 seconds plus 1 second of grace before SIGKILL, so the
# worst case stays under the hook's 15 second timeout. The first four answers are needed; the rest
# only add detail, and a failure there shows as `?`. The closed route asks for 50 so that a busy
# day still fits.
closed_pp=50
fetch() { # name, route
  timeout -k 1 5 gh api "$2" >"$dir/$1.json" 2>/dev/null || touch "$dir/$1.failed"
}
fetch open "repos/$repo/pulls?state=open&per_page=11" &
fetch closed "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=$closed_pp" &
fetch main "repos/$repo/branches/main" &
fetch ci "repos/$repo/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=1" &
fetch icomments "repos/$repo/issues/comments?sort=created&direction=desc&per_page=100" &
fetch rcomments "repos/$repo/pulls/comments?sort=created&direction=desc&per_page=100" &
fetch dash "repos/$repo/issues?state=open&creator=$owner&sort=updated&direction=desc&per_page=30" &
wait

for n in open closed main ci; do
  [ -e "$dir/$n.failed" ] && unavailable "gh api for $n failed or timed out"
done

# The owner's PRs among the ten listed, and their heads.
jq -r --arg owner "$owner" '.[0:10][]
  | select(type == "object" and (.user.login? // "") == $owner and (.number | type) == "number"
           and ((.head.sha // "") | type == "string" and test("^[0-9a-f]{40}$")))
  | "\(.number) \(.head.sha)"' "$dir/open.json" >"$dir/heads" 2>/dev/null || : >"$dir/heads"
while read -r n sha; do
  fetch "gate-$n" "repos/$repo/commits/$sha/check-runs?check_name=gate&per_page=30" &
  fetch "files-$n" "repos/$repo/pulls/$n/files?per_page=100" &
done <"$dir/heads"

# Rules freshness: the rule files main changed since the loaded commit, from local objects when
# both commits are here, or else from the REST compare route.
main_sha=$(jq -r '.commit.sha // empty' "$dir/main.json" 2>/dev/null)
compare=''
if [ -n "$loaded" ] && [[ $main_sha =~ ^[0-9a-f]{40}$ ]] && [ "$loaded" != "$main_sha" ]; then
  if git -C "$proj" cat-file -e "$main_sha^{commit}" 2>/dev/null \
    && git -C "$proj" cat-file -e "$loaded^{commit}" 2>/dev/null \
    && git -C "$proj" diff --name-only "$loaded...$main_sha" -- .claude CLAUDE.md docs/process.md \
      >"$dir/rules" 2>/dev/null; then
    :
  else
    compare=1
    fetch compare "repos/$repo/compare/$loaded...$main_sha" &
  fi
fi
wait

fresh=''
if [ -n "$compare" ]; then
  if [ ! -e "$dir/compare.failed" ] && jq -e '.files | type == "array"' "$dir/compare.json" >/dev/null 2>&1; then
    jq -r '.files[] | .filename | select(type == "string")' "$dir/compare.json" 2>/dev/null \
      | grep -E '^(\.claude/|CLAUDE\.md$|docs/process\.md$)' >"$dir/rules"
  else
    fresh="Rule freshness unknown: main could not be compared with ${loaded:0:7}, the commit this session loaded its rules from. Read .claude/skills/kitimark-mode/SKILL.md, CLAUDE.md and docs/process.md on origin/main before acting."
  fi
fi
if [ -z "$fresh" ] && [ -s "$dir/rules" ]; then
  total=$(grep -c . "$dir/rules")
  names=$(LC_ALL=C sed 's#[^A-Za-z0-9._/+-]#_#g' "$dir/rules" | cut -c1-80 | head -n 8 | paste -sd, - | sed 's/,/, /g')
  more=''
  [ "$total" -gt 8 ] && more=" (+$((total - 8)) more)"
  fresh="Rule files changed on main since this session loaded its rules at ${loaded:0:7}: $names$more. Read these before acting: git fetch origin main, then git show origin/main:<file>."
fi
# check-agent-spawn.sh adds the note to each spawn of this turn.
if [ -n "$state" ] && [ -n "$loaded" ] && [[ $main_sha =~ ^[0-9a-f]{40}$ ]]; then
  case $fresh in
    "Rule files changed"*) printf '%s\n' "$fresh" >"$state/$sid.note" 2>/dev/null ;;
    *) : >"$state/$sid.note" 2>/dev/null ;;
  esac
fi

# Per PR: `gate` at the head, and whether the PR touches a path the user keeps (kitimark-mode, What
# stays with the user). A full page of files may be incomplete, so it counts as unknown.
: >"$dir/extra.ndjson"
while read -r n sha; do
  gate='?' kept='?'
  if [ ! -e "$dir/gate-$n.failed" ]; then
    gate=$(jq -r '[.check_runs | if type == "array" then .[] else error("no runs") end | select(.name == "gate")]
      | if length == 0 then "none" else max_by(.id) | if .status == "completed" then .conclusion else "pending" end end
      | if type == "string" then gsub("[^a-z_]"; "_") | .[0:20] else error("bad conclusion") end' \
      "$dir/gate-$n.json" 2>/dev/null) || gate='?'
  fi
  if [ ! -e "$dir/files-$n.failed" ]; then
    kept=$(jq -r '
      def kept: test("^(gate/|eval/cheats/|\\.github/|\\.claude/|plan/|core/Mitos/Core/|core/Challenge/)")
        or IN("lean-toolchain", "lakefile.toml", "core/lakefile.toml", "core/Mitos/Core.lean",
              "core/comparator.json", "CLAUDE.md", "docs/process.md")
        or test("(^|/)(statements|models)\\.lock$");
      if type != "array" then error("not an array") elif length >= 100 then "?"
      else [.[] | .filename, (.previous_filename // empty)
            | if type == "string" then . else error("bad name") end]
        | if any(.[]; kept) then "yes" else "no" end end' "$dir/files-$n.json" 2>/dev/null) || kept='?'
  fi
  [ -n "$gate" ] || gate='?'
  [ -n "$kept" ] || kept='?'
  jq -cn --argjson n "$n" --arg sha "$sha" --arg gate "$gate" --arg kept "$kept" \
    '{n: $n, sha: $sha, gate: $gate, kept: $kept}' >>"$dir/extra.ndjson"
done <"$dir/heads"

# The verdict head per PR from the In flight table of the owner's "Owner dashboard" issue. The row's
# last cell is the verdict: `PASS <who> at <head>`, `wording-only at <head>`, or `PASS carried
# from <old>`, which covers the row's Head cell (kitimark-mode, Verdicts). Anything else is none.
verdicts=null
if [ ! -e "$dir/dash.failed" ]; then
  verdicts=$(jq -c --arg owner "$owner" '
    [.[] | select(type == "object" and .title == "Owner dashboard" and .pull_request == null
                  and .user.login == $owner)][0]
    | if . == null then {} else
      [(.body // "") | if type == "string" then . else error("bad body") end | split("\n")[]
       | select(test("^\\s*\\|\\s*#[0-9]+"))
       | (capture("^\\s*\\|\\s*#(?<n>[0-9]+)").n) as $n
       | [split("|")[] | gsub("^\\s+|\\s+$"; "") | select(. != "")] as $cells
       | ($cells[-1] | gsub("^[*_]+"; "")) as $v
       | (($cells[1] // "" | capture("(?<h>[0-9a-f]{7,40})").h)? // null) as $headcell
       | (if ($v | test("^PASS\\b")) or ($v | test("^wording-only\\b"; "i")) then
            (if ($v | test("\\bcarried\\b")) then
               (($v | capture("carried (from `?[0-9a-f]{7,40}`? )?to `?(?<h>[0-9a-f]{7,40})").h)? // $headcell)
             else (($v | capture("\\bat `?(?<h>[0-9a-f]{7,40})\\b").h)? // null) end)
          else null end) as $h
       | {key: $n, value: $h}] | from_entries end' "$dir/dash.json" 2>/dev/null) || verdicts=null
  [ -n "$verdicts" ] || verdicts=null
fi

# The owner's unanswered comments per issue or PR, from the newest 100 of each kind.
unans=null
if [ ! -e "$dir/icomments.failed" ] && [ ! -e "$dir/rcomments.failed" ]; then
  unans=$(jq -n -c --arg owner "$owner" --slurpfile ic "$dir/icomments.json" --slurpfile rc "$dir/rcomments.json" '
    def footer: test("_Generated by \\[Claude Code\\]\\(https://claude\\.ai/code\\)_\\s*$");
    def ts: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
            then . else error("bad timestamp") end;
    def num: if type == "number" and . >= 0 and . == floor then . else error("bad number") end;
    def thread: if type == "string" then ((split("/") | last | tonumber?) // error("bad url"))
                else error("bad url") end;
    def arr: if type == "array" then .[] else error("not an array") end;
    def post($u): {n: ($u | thread), id: (.id | num), t: (.created_at | ts), who: .user.login,
                   agent: (.body // "" | if type == "string" then footer else error("bad body") end)};
    [($ic[0] | arr | post(.issue_url)), ($rc[0] | arr | post(.pull_request_url))]
    | map(select(.who == $owner)) | group_by(.n)
    | map((map(select(.agent) | .t) | max) as $f
          | {key: (.[0].n | tostring),
             value: ([.[] | select((.agent | not) and ($f == null or .t > $f)) | .id] | sort)})
    | map(select(.value != [])) | from_entries' 2>/dev/null) || unans=null
  [ -n "$unans" ] || unans=null
fi

now=$(date -u +%Y-%m-%dT%H:%M)
cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || unavailable "cannot compute the 24 hour cutoff"

out=$(jq -n -r --arg now "$now" --arg cutoff "$cutoff" --argjson pp "$closed_pp" --arg repo "$repo" \
  --arg fresh "$fresh" --argjson verdicts "$verdicts" --argjson unans "$unans" \
  --slurpfile open "$dir/open.json" --slurpfile closed "$dir/closed.json" \
  --slurpfile main "$dir/main.json" --slurpfile ci "$dir/ci.json" --slurpfile extra "$dir/extra.ndjson" '
  # Any value of the wrong type or shape raises an error, and the hook then fails closed.
  def arr: if type == "array" then . else error("not an array") end;
  def clean: if type == "string" then gsub("[^A-Za-z0-9 ._:/+#@-]"; "_") | .[0:40]
             else error("not a string") end;
  def hex: if type == "string" and test("^[0-9a-f]{7,64}$") then .[0:7] else error("bad sha") end;
  def hex40: if type == "string" and test("^[0-9a-f]{40}$") then . else error("bad sha") end;
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
  ($extra | map({key: (.n | tostring), value: (.sha |= hex40)}) | from_entries) as $ex |

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
  (if $fresh != "" then $fresh else empty end),
  (if ($op | length) == 0 then "open PRs: none"
   else $op[0:10][] | .n as $n | $ex[$n] as $e |
     (if $e == null then null else
        ($verdicts | if . == null then "?" else (.[$n] // "none") end) as $v |
        ($unans | if . == null then "?"
                  else ((.[$n] // []) | if length == 0 then "-" else map(tostring) | lst end) end) as $u |
        {v: $v, u: $u, head: ($v != "?" and $v != "none" and ($e.sha | startswith($v)))} end) as $r |
     "open #\($n) head \(.sha) \(if .draft then "draft" else "ready" end) labels=\(.labels | lst) assignees=\(.who | lst)\(
       if $r == null then ""
       else " gate=\($e.gate) verdict=\($r.v)\(if $r.head then "(the head)" elif $r.v == "?" or $r.v == "none" then "" else "(an old head)" end) owner-unanswered=\($r.u) user-kept=\($e.kept)" end)",
     (if $r != null and $r.head and $e.gate == "success" and $r.u == "-" then
        "merge-ready #\($n), \(if $e.kept == "no" then "an agent merges" elif $e.kept == "yes" then "the user merges (it touches a path the user keeps)" else "the user merges (its files could not be read)" end): gh api -X PUT repos/\($repo)/pulls/\($n)/merge -f merge_method=rebase -f sha=\($e.sha)"
      else empty end)
   end),
  (if ($op | length) > 10 then "open PRs: more than 10, the rest are not listed" else empty end),
  (($unans // {}) | to_entries | map(select(.key as $k | $ex | has($k) | not))
   | if length == 0 then empty
     else "owner comments with no later footer comment, elsewhere: "
       + (.[0:5] | map("#\(.key) \(.value | map(tostring) | lst)") | join("; "))
       + (if length > 5 then "; +\(length - 5) more" else "" end) end),
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
