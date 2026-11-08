#!/usr/bin/env bash
# Prints one line per GitHub change the root acts on, and nothing while nothing changes, so the
# root's Monitor that runs it costs no tokens between events (kitimark-mode skill, Watchers).
# Every 60 s it reads REST through `gh api` (GraphQL is blocked in these sessions) and reports:
#   - a PR merged or closed after the state directory was first used;
#   - a new open PR, and an open PR's labels or assignees, when they change;
#   - the head and finished checks of an open PR from the owner's account, when they change;
#   - a move of main;
#   - a comment or review from the owner's account that does not end with the Claude Code footer,
#     which marks an agent's post, with its id. A footer in a quote above the owner's own text
#     does not count.
#
# Usage: watch-github.sh <state-dir>
# The state directory keeps the last snapshot, the events already printed and the comment cursor,
# so a re-armed monitor neither repeats nor misses an event. Give each monitor a directory of its
# own, such as a new subdirectory of the session's scratchpad: two monitors on one directory would
# each consume the other's events, so a lock refuses the second. The first poll of a new directory
# only records what is there and prints nothing.
#
# Environment: WATCH_OWNER, the owner's login (default kitimark); WATCH_INTERVAL, seconds between
# polls (default 60); WATCH_POLLS, stop after this many polls (default 0, never; for tests);
# WATCH_MAX_LINES, the most lines one poll prints (default 30); WATCH_CHECKS, the check names
# printed by name (default gate,scorecard-comment,CodeRabbit: the jobs of ci.yml and the bot).
#
# Cost and outside text. Heads, checks and reviews are read only for PRs whose author is the
# owner's account, which opens every PR the agents carry. A poll makes 5 calls plus 2 per such
# PR, so about 780 an hour with 4 of them, well under the REST limit of 5000 an hour that all
# agents share. A PR from another account, such as a fork's, costs no call of its own: its labels,
# assignees and close are read from the PR lists and marked `outside`. So a flood of fork PRs
# cannot use up that limit, and the check names a fork's workflow chooses never reach the root.
# A check name outside WATCH_CHECKS is counted, not printed. Each call has a 20 s timeout.
# Text from GitHub is printed only after control, line-break and space characters become spaces
# and invisible format characters (bidi, zero-width, tag and the like) go, and it is cut to a
# fixed length. The owner's comments print first, and lines past WATCH_MAX_LINES are replaced by
# one line that says how many were left out. The origin URL is never printed, because it can
# carry a credential. Child commands do not inherit the lock, so a killed watcher frees it at once.
set -u

say() { printf 'watch-github: %s\n' "$1"; }
die() { say "$1"; exit 1; }

dir=${1:-}
[ -n "$dir" ] || die "usage: watch-github.sh <state-dir>"
owner=${WATCH_OWNER:-kitimark}
interval=${WATCH_INTERVAL:-60}
polls=${WATCH_POLLS:-0}
maxlines=${WATCH_MAX_LINES:-30}
checks=${WATCH_CHECKS:-gate,scorecard-comment,CodeRabbit}
[[ $owner =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || die "WATCH_OWNER is not a GitHub login"
[[ $interval =~ ^[0-9]+$ && $polls =~ ^[0-9]+$ ]] || die "WATCH_INTERVAL and WATCH_POLLS must be whole numbers"
[[ $maxlines =~ ^[1-9][0-9]{0,3}$ ]] || die "WATCH_MAX_LINES must be a whole number from 1 to 9999"
[[ $checks =~ ^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$ ]] || die "WATCH_CHECKS must be check names separated by commas"
for tool in gh jq git flock timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

# owner/name from the origin URL (https, ssh or proxy form).
url=$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null) || die "no origin remote"
repo=$(sed -E 's#/+$##; s#\.git$##; s#^.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "origin is not owner/name"

mkdir -p "$dir" 2>/dev/null || die "cannot make the state directory"
touch "$dir/lock" 2>/dev/null || die "cannot write the state directory"
exec 9>"$dir/lock"
flock -n 9 || die "another watcher uses this state directory"
touch "$dir/seen"
[ -s "$dir/start" ] || date -u +%Y-%m-%dT%H:%M:%SZ >"$dir/start"
start=$(cat "$dir/start")
[[ $start =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "the start file in the state directory is not a UTC time"
[ -s "$dir/cursor" ] || date -u +%s >"$dir/cursor"
# The cursor goes into shell arithmetic, which would run a command substitution in it.
cursor=$(cat "$dir/cursor")
[[ $cursor =~ ^[0-9]{1,12}$ ]] || die "the cursor file in the state directory is not a whole number"

# clean($n) sanitizes GitHub text: control, line-break and space characters become one space,
# invisible format characters go (bidi and zero-width marks, soft hyphen, word joiner, tag and
# variation characters, interlinear annotation, fillers), and the result is cut to $n characters.
# shellcheck disable=SC2016 # jq variables, not shell ones
defs='
def clean($n): tostring
  | gsub("[\\p{Cf}\u034f\u115f\u1160\u17b4\u17b5\u180b-\u180f\u3164\ufe00-\ufe0f\uffa0\\x{E0000}-\\x{E007F}\\x{E0100}-\\x{E01EF}]"; "")
  | gsub("[\\p{Cc}\\p{Zl}\\p{Zp}\\p{Zs}]+"; " ")
  | sub("^ "; "") | sub(" $"; "") | .[0:$n];
def lst: if length == 0 then "-" else .[0:20] | join(",") end;
def num: tostring | select(test("^[0-9]+$"));
def ours: .user.login == $owner;
def who: if ours then "" else " outside" end;
def mine: select(ours
  and ((.body // "") | test("_Generated by \\[Claude Code\\]\\(https://claude\\.ai/code\\)_\\s*$") | not));
'

w="$dir/poll"
api() { # file, then gh api arguments; fails on any error or a timeout
  timeout -k 2 20 gh api "${@:2}" >"$w/$1" 2>/dev/null </dev/null 9>&-
}

# One poll into $w. Any failed call or unexpected JSON fails the whole poll, so a partial read
# never shows up as a change.
poll() {
  rm -rf "$w" && mkdir "$w" || return 1
  local since
  since=$(date -u -d "@$((cursor - 300))" +%Y-%m-%dT%H:%M:%SZ) || return 1
  date -u +%s >"$w/now"
  api open.json --paginate "repos/$repo/pulls?state=open&per_page=100" || return 1
  api closed.json "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=50" || return 1
  api main.json "repos/$repo/branches/main" || return 1
  api icomments.json --paginate --slurp "repos/$repo/issues/comments?since=$since&per_page=100" || return 1
  api rcomments.json --paginate --slurp "repos/$repo/pulls/comments?since=$since&per_page=100" || return 1
  # Only the owner's account's PRs get calls of their own (see Cost and outside text above).
  jq -r --arg owner "$owner" "$defs"'
    .[] | select((.number | type) == "number" and (.head.sha // "" | test("^[0-9a-f]{40}$")) and ours)
    | "\(.number) \(.head.sha)"' "$w/open.json" >"$w/heads" 2>/dev/null || return 1
  local n sha
  while read -r n sha; do
    api "checks-$n.json" "repos/$repo/commits/$sha/check-runs?per_page=100" || return 1
    api "reviews-$n.json" --paginate --slurp "repos/$repo/pulls/$n/reviews?per_page=100" || return 1
  done <"$w/heads"

  # The snapshot: lines whose change is the event. A line that is new since the last poll prints.
  {
    jq -r --arg owner "$owner" "$defs"'
      .[] | "pr #\(.number | num)\(who) labels=\([.labels[].name | clean(50)] | sort | lst) assignees=\([.assignees[].login | clean(40)] | sort | lst)"' \
      "$w/open.json" &&
    jq -r '"main \(.commit.sha | select(test("^[0-9a-f]{40}$")) | .[0:7])"' "$w/main.json" &&
    while read -r n sha; do
      jq -r --arg owner "$owner" --arg n "$n" --arg h "${sha:0:7}" --arg checks "$checks" "$defs"'
        ($checks | split(",")) as $listed
        | [.check_runs | group_by(.name)[] | max_by(.id)] as $runs
        | ([$runs[] | select(.name | IN($listed[])) | "\(.name)=\(.conclusion // "pending" | clean(20))"]
           | sort | lst) as $shown
        | ([$runs[] | select(.name | IN($listed[]) | not)] | length) as $other
        | "pr #\($n) head \($h) checks \($shown)\(if $other > 0 then " unlisted=\($other)" else "" end)"' \
        "$w/checks-$n.json" || return 1
    done <"$w/heads"
  } >"$w/snapshot.raw" 2>/dev/null || return 1
  LC_ALL=C sort "$w/snapshot.raw" >"$w/snapshot" || return 1

  # Events: printed once each, keyed in the seen file. Each line is key, tier, text; tier 0 (the
  # owner's words) prints first, tier 2 (other accounts' PRs) last.
  {
    jq -r --arg start "$start" --arg owner "$owner" "$defs"'
      .[] | select(.closed_at != null and .closed_at >= $start)
      | "closed \(.number | num) \(.closed_at | clean(20))\t\(if ours then 1 else 2 end)\tpr #\(.number | num)\(who) \(if .merged_at != null then "merged" else "closed" end) at \(.closed_at | clean(20) | .[0:16])Z"' \
      "$w/closed.json" &&
    jq -r --arg owner "$owner" "$defs"'
      .[][] | mine | "comment \(.id | num)\t0\towner comment \(.id | num) on #\(.issue_url // "" | split("/") | last // "" | num): \(.body // "" | clean(120))"' \
      "$w/icomments.json" &&
    jq -r --arg owner "$owner" "$defs"'
      .[][] | mine | "review-comment \(.id | num)\t0\towner review comment \(.id | num) on #\(.pull_request_url // "" | split("/") | last // "" | num): \(.body // "" | clean(120))"' \
      "$w/rcomments.json" &&
    while read -r n sha; do
      jq -r --arg owner "$owner" --arg n "$n" "$defs"'
        .[][] | mine | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or (.body // "") != "")
        | "review \(.id | num)\t0\towner review \(.id | num) on #\($n): \(.state | ascii_downcase | clean(20)): \(.body // "" | clean(120))"' \
        "$w/reviews-$n.json" || return 1
    done <"$w/heads"
  } >"$w/events" 2>/dev/null || return 1
}

# Prints what changed since the last poll, at most $maxlines lines, and stores the new state. The
# first poll of a new state directory prints nothing.
report() {
  : >"$w/newkeys"
  awk -F '\t' -v keys="$w/newkeys" '
    FILENAME == ARGV[1] { seen[$0] = 1; next }
    !($1 in seen) { seen[$1] = 1; print $1 >keys; print $2 "\t" $3 }' "$dir/seen" "$w/events" >"$w/new-events"
  if [ -e "$dir/snapshot" ]; then
    {
      cat "$w/new-events"
      LC_ALL=C comm -13 "$dir/snapshot" "$w/snapshot" | awk '{ print (/^pr #[0-9]+ outside / ? 2 : 1) "\t" $0 }'
    } | LC_ALL=C sort -s -t "$(printf '\t')" -k1,1 | cut -f2- >"$w/out"
    local total
    total=$(wc -l <"$w/out")
    head -n "$maxlines" "$w/out"
    if [ "$total" -gt "$maxlines" ]; then
      say "$((total - maxlines)) more changes in this poll are not shown; read them over REST"
    fi
  fi
  cat "$w/newkeys" >>"$dir/seen"
  # Keep the newest 5000 keys. An older event is far outside the comment window, so dropping its
  # key can at most repeat a comment that was edited much later.
  if [ "$(wc -l <"$dir/seen")" -gt 5000 ]; then
    tail -n 5000 "$dir/seen" >"$w/seen" && mv "$w/seen" "$dir/seen"
  fi
  mv "$w/snapshot" "$dir/snapshot"
  cursor=$(cat "$w/now")
  printf '%s\n' "$cursor" >"$dir/cursor"
}

fails=0
count=0
while :; do
  if poll; then
    fails=0
    if [ -e "$dir/unreachable" ]; then
      rm -f "$dir/unreachable"
      say "GitHub answers again"
    fi
    report
  else
    fails=$((fails + 1))
    if [ "$fails" = 5 ]; then
      touch "$dir/unreachable"
      say "GitHub unreachable or answering oddly for 5 polls in a row; still trying"
    fi
  fi
  count=$((count + 1))
  [ "$polls" -gt 0 ] && [ "$count" -ge "$polls" ] && break
  sleep "$interval" 9>&-
done
