#!/usr/bin/env bash
set -u

unavailable() { echo "GitHub state unavailable: $1"; exit 0; }

hook_dir=${BASH_SOURCE[0]%/*}; [[ $hook_dir == "${BASH_SOURCE[0]}" ]] && hook_dir=.
# shellcheck source-path=SCRIPTDIR source=hook-state.sh
. "$hook_dir/hook-state.sh" || unavailable "hook-state.sh is missing"

command -v gh >/dev/null 2>&1 || unavailable "gh is not installed"
command -v jq >/dev/null 2>&1 || unavailable "jq is not installed"

input=''
[ -t 0 ] || input=$(cat 2>/dev/null)
sid=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null)
source=$(jq -r '.source // empty' <<<"$input" 2>/dev/null)
session_id_ok "$sid" || sid=''
owner=${MITOS_OWNER:-kitimark}
[[ $owner =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || unavailable "MITOS_OWNER is not a GitHub login"
dashboard=${MITOS_DASHBOARD:-43}
[[ $dashboard =~ ^[1-9][0-9]{0,6}$ ]] || unavailable "MITOS_DASHBOARD is not an issue number"
proj=${CLAUDE_PROJECT_DIR:-.}

rules_loaded_at='' state_ready='' state_refused=''
reloads_rules=0
[ "$event" = SessionStart ] && [ "$source" != resume ] && [ "$source" != compact ] && reloads_rules=1
if [ -n "$sid" ]; then
  if hook_state ensure; then
    state_ready=1
    rules_loaded_at=$(hook_state read "$sid" sha)
    if [ "$reloads_rules" = 1 ] || ! [[ $rules_loaded_at =~ ^[0-9a-f]{40}$ ]]; then
      rules_loaded_at=$(git -C "$proj" rev-parse HEAD 2>/dev/null)
      if [[ $rules_loaded_at =~ ^[0-9a-f]{40}$ ]]; then printf '%s\n' "$rules_loaded_at" | hook_state publish "$sid" sha; else rules_loaded_at=''; fi
    fi
  else
    state_ready='' state_refused=1
  fi
fi

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

closed_pp=50
files_per_page=100
hook_timeout_s=15 fetch_rounds=2 fetch_timeout_s=3 fetch_kill_s=1
provenance_calls=2 provenance_timeout_s=1 provenance_kill_s=1
(( fetch_rounds * (fetch_timeout_s + fetch_kill_s) + provenance_calls * (provenance_timeout_s + provenance_kill_s) < hook_timeout_s )) \
  || unavailable "fetch and provenance budget exceeds the hook timeout"
fetch() {
  timeout -k "$fetch_kill_s" "$fetch_timeout_s" gh api "$2" >"$dir/$1.json" 2>/dev/null \
    || { rm -f "$dir/$1.json"; touch "$dir/$1.failed"; }
}
fetch_all_pages() {
  timeout -k "$fetch_kill_s" "$fetch_timeout_s" gh api "$2" --paginate --slurp >"$dir/$1.json" 2>/dev/null \
    || { rm -f "$dir/$1.json"; touch "$dir/$1.failed"; }
}
fetch open "repos/$repo/pulls?state=open&per_page=11" &
fetch closed "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=$closed_pp" &
fetch main "repos/$repo/branches/main" &
fetch ci "repos/$repo/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=1" &
fetch icomments "repos/$repo/issues/comments?sort=created&direction=desc&per_page=100" &
fetch rcomments "repos/$repo/pulls/comments?sort=created&direction=desc&per_page=100" &
fetch dash "repos/$repo/issues/$dashboard" &
wait

for n in open closed main ci; do
  [ -e "$dir/$n.failed" ] && unavailable "gh api for $n failed or timed out"
done

jq -r --arg owner "$owner" '.[0:10][]
  | select(type == "object" and (.user.login? // "") == $owner and (.number | type) == "number"
           and ((.head.sha // "") | type == "string" and test("^[0-9a-f]{40}$")))
  | "\(.number) \(.head.sha)"' "$dir/open.json" >"$dir/heads" 2>/dev/null || : >"$dir/heads"
main_sha=$(jq -r '.commit.sha // empty' "$dir/main.json" 2>/dev/null)
provenance=null provenance_hold=main-tool-unavailable tool_bin=''
if [[ $main_sha =~ ^[0-9a-f]{40}$ ]] && [ ! -e "$dir/dash.failed" ]; then
  # shellcheck source-path=SCRIPTDIR source=../scripts/lib/main-tool.sh
  if . "$hook_dir/../scripts/lib/main-tool.sh" 2>"$dir/tool.err"; then
    tool_dir=$(main_tool_dir) || tool_dir=''
    if [ -n "$tool_dir" ]; then
      [[ $tool_dir == /* ]] || tool_dir=$PWD/$tool_dir
      if MAIN_TOOL_READY_WAIT=0 main_tool ready "$tool_dir" "$main_sha" 2>"$dir/tool.err"; then
        tool_bin=$(main_tool_bin "$tool_dir")
        provenance_hold=''
      fi
    fi
  fi
elif [ -e "$dir/dash.failed" ]; then
  provenance_hold='source-unavailable'
else
  provenance_hold=main-unavailable
fi

provenance_output_ok() {
  local file=$1 mode=$2 bytes
  bytes=$(wc -c <"$file") || return 1
  [ "$bytes" -le 16384 ] || return 1
  jq -e --stream -s '
    [.[] | select(length == 2)] as $values
    | all($values[]; ((.[0] | length) == 2) or (.[0] == [] and .[1] == {}))
      and (($values | map(.[0]) | unique | length) == ($values | length))
  ' "$file" >/dev/null 2>&1 || return 1
  jq -e -s --arg mode "$mode" --rawfile heads "$dir/heads" '
    ($heads | split("\n") | map(select(. != "") | split(" ") | {key: .[0], value: .[1]}) | from_entries) as $expected
    | length == 1 and (.[0] | type == "object"
      and (keys == ($expected | keys))
      and all(to_entries[];
        (.key | test("^[1-9][0-9]*$"))
        and (.value | type == "object" and keys == ["candidate", "eligible", "head", "reason"])
        and (.value.head | type == "string" and test("^[0-9a-f]{40}$"))
        and (.value.head == $expected[.key])
        and (.value.candidate | type == "boolean")
        and (.value.eligible | type == "boolean")
        and (.value.reason | type == "string" and test("^[a-z][a-z0-9-]{0,39}$"))
        and (.value.eligible == false or .value.candidate == true)
        and ($mode != "candidates" or .value.eligible == false)))
  ' "$file" >/dev/null 2>&1
}

provenance_read() {
  local mode=$1 status=0
  if [ "$mode" = candidates ]; then
    (cd "$proj" && timeout -k "$provenance_kill_s" "$provenance_timeout_s" "$tool_bin" \
      provenance candidates "$dir" "$repo" "$owner") >"$dir/provenance.json" 2>"$dir/provenance.err" || status=$?
  else
    (cd "$proj" && timeout -k "$provenance_kill_s" "$provenance_timeout_s" "$tool_bin" \
      provenance hook "$dir" "$repo" "$owner" "$main_sha") >"$dir/provenance.json" 2>"$dir/provenance.err" || status=$?
  fi
  if [ "$status" != 0 ]; then
    provenance_hold=native-unavailable
    [ "$status" != 124 ] && [ "$status" != 137 ] || provenance_hold=native-timeout
    provenance=null
    return 1
  fi
  if ! provenance_output_ok "$dir/provenance.json" "$mode"; then
    provenance_hold=native-output-invalid
    provenance=null
    return 1
  fi
  if [ "$mode" = hook ] && ! jq -e --slurpfile initial "$dir/provenance-candidates.json" '
    all(to_entries[]; .value.candidate == $initial[0][.key].candidate)
  ' "$dir/provenance.json" >/dev/null 2>&1; then
    provenance_hold=native-output-invalid
    provenance=null
    return 1
  fi
  provenance=$(jq -c . "$dir/provenance.json") || { provenance_hold=native-output-invalid; provenance=null; return 1; }
  if [ "$mode" = candidates ]; then cp "$dir/provenance.json" "$dir/provenance-candidates.json"; fi
}

if [ -z "$provenance_hold" ]; then provenance_read candidates || :; fi

: >"$dir/full_thread_prs"
while read -r n sha; do
  fetch "gate-$n" "repos/$repo/commits/$sha/check-runs?check_name=gate&per_page=30" &
  fetch "files-$n" "repos/$repo/pulls/$n/files?per_page=$files_per_page" &
  candidate=$(jq -r --arg n "$n" '.[$n].candidate // false' <<<"$provenance" 2>/dev/null)
  if [ "$candidate" = true ]; then
    echo "$n" >>"$dir/full_thread_prs"
    fetch "pull-$n" "repos/$repo/pulls/$n" &
    fetch_all_pages "thread-ic-$n" "repos/$repo/issues/$n/comments?per_page=100" &
    fetch_all_pages "thread-rc-$n" "repos/$repo/pulls/$n/comments?per_page=100" &
    fetch_all_pages "thread-rv-$n" "repos/$repo/pulls/$n/reviews?per_page=100" &
    ref=$(jq -r --argjson n "$n" '.[] | select(.number == $n) | .head.ref // empty | select(type == "string")' "$dir/open.json" 2>/dev/null)
    if [ -n "$ref" ]; then
      ref_uri=$(jq -rn --arg ref "refs/heads/$ref" '$ref | @uri')
      fetch_all_pages "activity-$n" "repos/$repo/activity?ref=$ref_uri&direction=desc&per_page=100" &
    else
      touch "$dir/activity-$n.failed"
    fi
  fi
done <"$dir/heads"

compare=''
if [ -n "$rules_loaded_at" ] && [[ $main_sha =~ ^[0-9a-f]{40}$ ]] && [ "$rules_loaded_at" != "$main_sha" ]; then
  if git -C "$proj" cat-file -e "$main_sha^{commit}" 2>/dev/null \
    && git -C "$proj" cat-file -e "$rules_loaded_at^{commit}" 2>/dev/null \
    && git -C "$proj" diff --name-only "$rules_loaded_at...$main_sha" -- .claude CLAUDE.md docs/process.md \
      >"$dir/rules" 2>/dev/null; then
    :
  else
    compare=1
    fetch compare "repos/$repo/compare/$rules_loaded_at...$main_sha" &
  fi
fi
wait

if [ -z "$provenance_hold" ]; then provenance_read hook || :; fi

fresh=''
[ -n "$state_refused" ] && fresh="Rule freshness unknown: the hook state folder is not a private folder of this user, so this session's rules commit is not recorded. Read .claude/skills/kitimark-mode/SKILL.md, CLAUDE.md and docs/process.md on origin/main before acting."
if [ -n "$compare" ]; then
  # The route lists at most 300 files, so a full list may leave rule files out: unknown.
  if [ ! -e "$dir/compare.failed" ] && jq -e '.files | type == "array" and length < 300' "$dir/compare.json" >/dev/null 2>&1; then
    jq -r '.files[] | .filename | select(type == "string")' "$dir/compare.json" 2>/dev/null \
      | grep -E '^(\.claude/|CLAUDE\.md$|docs/process\.md$)' >"$dir/rules"
  else
    fresh="Rule freshness unknown: main could not be compared with ${rules_loaded_at:0:7}, the commit this session loaded its rules from. Read .claude/skills/kitimark-mode/SKILL.md, CLAUDE.md and docs/process.md on origin/main before acting."
  fi
fi
if [ -z "$fresh" ] && [ -s "$dir/rules" ]; then
  total=$(grep -c . "$dir/rules")
  names=$(LC_ALL=C sed 's#[^A-Za-z0-9._/+-]#_#g' "$dir/rules" | cut -c1-80 | head -n 8 | paste -sd, - | sed 's/,/, /g')
  more=''
  [ "$total" -gt 8 ] && more=" (+$((total - 8)) more)"
  fresh="Rule files changed on main since this session loaded its rules at ${rules_loaded_at:0:7}: $names$more. Read these before acting: git fetch origin main, then git show origin/main:<file>."
fi
if [ -n "$state_ready" ] && [ -n "$rules_loaded_at" ] && [[ $main_sha =~ ^[0-9a-f]{40}$ ]]; then
  case $fresh in
    "Rule files changed"*) printf '%s\n' "$fresh" | hook_state publish "$sid" note ;;
    *) hook_state publish "$sid" note </dev/null ;;
  esac
fi

: >"$dir/extra.ndjson"
while read -r n sha; do
  gate='?' user_kept='?'
  if [ ! -e "$dir/gate-$n.failed" ]; then
    gate=$(jq -r '[.check_runs | if type == "array" then .[] else error("no runs") end | select(.name == "gate")]
      | if length == 0 then "none" else max_by(.id) | if .status == "completed" then .conclusion else "pending" end end
      | if type == "string" then gsub("[^a-z_]"; "_") | .[0:20] else error("bad conclusion") end' \
      "$dir/gate-$n.json" 2>/dev/null) || gate='?'
  fi
  if [ ! -e "$dir/files-$n.failed" ]; then
    user_kept=$(jq -r --argjson files_per_page "$files_per_page" '
      def trust_critical: test("^(gate/|eval/cheats/|\\.github/|core/Mitos/Core/|core/Challenge/)")
        or IN("lean-toolchain", "lakefile.toml", "core/lakefile.toml", "lake-manifest.json", "core/lake-manifest.json", "core/Mitos/Core.lean", "core/comparator.json")
        or test("(^|/)(statements|models)\\.lock$");
      def user_kept: trust_critical or test("^(\\.claude/|\\.cursor/|plan/)") or IN("CLAUDE.md", "docs/process.md");
      def yn(f): if any(.[]; f) then "yes" else "no" end;
      if type != "array" then error("not an array") elif length >= $files_per_page then "?"
      else [.[] | .filename, (.previous_filename // empty)
            | if type == "string" then . else error("bad name") end]
        | yn(user_kept) end' "$dir/files-$n.json" 2>/dev/null) || user_kept='?'
  fi
  [ -n "$gate" ] || gate='?'
  mergeable=unread
  if grep -qx "$n" "$dir/full_thread_prs"; then
    mergeable='?'
    if [ ! -e "$dir/pull-$n.failed" ]; then
      mergeable=$(jq -r --arg sha "$sha" 'if (.mergeable | type) != "boolean" and (.mergeable | type) != "null" then error("bad mergeable")
        elif (.mergeable_state | type) != "string" and (.mergeable_state | type) != "null" then error("bad state")
        elif (.rebaseable | type) != "boolean" and (.rebaseable | type) != "null" then error("bad rebaseable")
        elif (.head.sha | type) != "string" and (.head.sha | type) != "null" then error("bad head")
        elif (.head.sha | type) == "string" and .head.sha != $sha then "head-moved"
        elif .mergeable == false or .mergeable_state == "dirty" then "dirty"
        elif .mergeable == null then "unknown"
        elif (.head.sha | type) != "string" then error("no head")
        elif .rebaseable == false then "not-rebaseable"
        elif .mergeable_state == "behind" then "behind"
        elif .mergeable_state == "blocked" then "blocked"
        elif (.mergeable_state | IN("clean", "unstable", "has_hooks")) then "clean"
        else "unknown" end' "$dir/pull-$n.json" 2>/dev/null) || mergeable='?'
      [ -n "$mergeable" ] || mergeable='?'
    fi
  fi
  [ -n "$user_kept" ] || user_kept='?'
  full_thread_unanswered=null
  if grep -qx "$n" "$dir/full_thread_prs"; then
    full_thread_unanswered='"?"'
    if [ ! -e "$dir/thread-ic-$n.failed" ] && [ ! -e "$dir/thread-rc-$n.failed" ] && [ ! -e "$dir/thread-rv-$n.failed" ]; then
      full_thread_unanswered=$(jq -n -c --arg owner "$owner" --slurpfile ic "$dir/thread-ic-$n.json" \
        --slurpfile rc "$dir/thread-rc-$n.json" --slurpfile rv "$dir/thread-rv-$n.json" '
        def footer: test("_Generated by \\[Claude Code\\]\\(https://claude\\.ai/code\\)_\\s*$");
        def ts: select(type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"));
        def num: if type == "number" and . >= 0 and . == floor then . else error("bad number") end;
        def items: if type == "array" then .[] | if type == "array" then .[] else error("not a page") end
                   else error("not an array") end;
        def post($t): select(type == "object" and .user.login == $owner)
          | {id: (.id | num), t: ($t | ts), agent: (.body // "" | if type == "string" then footer else error("bad body") end)};
        [($ic[0] | items | post(.created_at)), ($rc[0] | items | post(.created_at)),
         ($rv[0] | items | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or (.body // "") != "")
                 | post(.submitted_at))]
        | (map(select(.agent) | .t) | max) as $f
        | [.[] | select((.agent | not) and ($f == null or .t > $f)) | .id] | unique' 2>/dev/null) || full_thread_unanswered='"?"'
      [ -n "$full_thread_unanswered" ] || full_thread_unanswered='"?"'
    fi
  fi
  jq -cn --argjson n "$n" --arg sha "$sha" --arg gate "$gate" --arg user_kept "$user_kept" --arg mergeable "$mergeable" --argjson full_thread_unanswered "$full_thread_unanswered" \
    '{n: $n, sha: $sha, mergeable: $mergeable, gate: $gate, user_kept: $user_kept, full_thread_unanswered: $full_thread_unanswered}' >>"$dir/extra.ndjson"
done <"$dir/heads"

owner_unanswered_by_thread=null
if [ ! -e "$dir/icomments.failed" ] && [ ! -e "$dir/rcomments.failed" ]; then
  owner_unanswered_by_thread=$(jq -n -c --arg owner "$owner" --slurpfile ic "$dir/icomments.json" --slurpfile rc "$dir/rcomments.json" '
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
    | map(select(.value != [])) | from_entries' 2>/dev/null) || owner_unanswered_by_thread=null
  [ -n "$owner_unanswered_by_thread" ] || owner_unanswered_by_thread=null
fi

now=$(date -u +%Y-%m-%dT%H:%M)
cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
  || unavailable "cannot compute the 24 hour cutoff"

out=$(jq -n -r --arg now "$now" --arg cutoff "$cutoff" --argjson pp "$closed_pp" --arg repo "$repo" \
  --arg fresh "$fresh" --argjson provenance "$provenance" --arg provenance_hold "$provenance_hold" --argjson owner_unanswered_by_thread "$owner_unanswered_by_thread" \
  --slurpfile open "$dir/open.json" --slurpfile closed "$dir/closed.json" \
  --slurpfile main "$dir/main.json" --slurpfile ci "$dir/ci.json" --slurpfile extra "$dir/extra.ndjson" '
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
           who: [.assignees | arr | .[] | .login | clean],
           link: (.body // "" | if type == "string" then test("claude\\.ai/code/session_")
                               else error("bad body") end)}] as $op |
  [$cl[] | {n: (.number | num), closed: (.closed_at | tsn), merged: (.merged_at | tsn),
            upd: (.updated_at | ts), sha: (.head.sha | hex)}] as $cp |
  ([$cp[] | select(.closed != null and .closed >= $cutoff)] | sort_by([.closed, .n]) | reverse) as $c |
  (($cp | length) >= $pp and $cp[-1].upd >= $cutoff) as $closed_page_may_hold_more |
  (if ($runs | length) == 0 then "none"
   else $runs[0] | "\(.status | clean)/\(.conclusion | if . == null then "-" else clean end) head \(.head_sha | hex)" end) as $cirun |

  "GitHub state (read \($now)Z; trust this over memory):",
  (if $fresh != "" then $fresh else empty end),
  (if $provenance_hold != "" then "Provenance hold: \($provenance_hold)" else empty end),
  (if ($op | length) == 0 then "open PRs: none"
   else $op[0:10][] | .n as $n | $ex[$n] as $e |
     (if $e == null then null else
        ($provenance | if . == null then null else .[$n] end) as $vi |
        (if $vi == null then "unavailable" else $vi.reason end) as $reason |
        (if $e.full_thread_unanswered != null
         then ($e.full_thread_unanswered | if . == "?" then "?" elif length == 0 then "-" else map(tostring) | lst end)
         else ($owner_unanswered_by_thread | if . == null then "?"
                        else ((.[$n] // []) | if length == 0 then "-" else map(tostring) | lst end) end) end) as $u |
        ($vi != null and $vi.head == $e.sha and $vi.candidate == true and $vi.eligible == true) as $eligible |
        (if (.labels | any(. == "needs-rebase")) then "needs-rebase" elif ($e.mergeable | IN("dirty", "behind", "blocked", "not-rebaseable", "head-moved")) then $e.mergeable elif $e.mergeable == "unknown" then "not-computed" elif $e.mergeable == "?" then "unreadable" else null end) as $cf |
        {u: $u, eligible: $eligible, reason: $reason, cf: $cf, hold: (if $eligible then null else (if $provenance_hold != "" then $provenance_hold else $reason end) end)} end) as $r |
     "open #\($n) head \(.sha) \(if .draft then "draft" else "ready" end) labels=\(.labels | lst) assignees=\(.who | lst)\(
       if $r == null then ""
       else " gate=\($e.gate) provenance=\($r.reason) owner-unanswered=\($r.u) user-kept=\($e.user_kept)\(if $r.cf != null then " conflict=\($r.cf)" else "" end)\(if $r.hold != null then " merge-hold=\($r.hold)" else "" end)" end)",
     (if $r != null and $r.eligible == true and $r.hold == null and $e.gate == "success" and $r.u == "-" and $r.cf == null and $e.mergeable == "clean" and (.draft | not) then
        "merge-ready #\($n), \(if $e.user_kept == "no" then "an agent merges" elif $e.user_kept == "yes" then "the user merges (it touches a path the user keeps)" else "the user merges (its files could not be read)" end): gh api -X PUT repos/\($repo)/pulls/\($n)/merge -f merge_method=rebase -f sha=\($e.sha)"
      else empty end)
   end),
  (if ($op | length) > 10 then "open PRs: more than 10, the rest are not listed" else empty end),
  ([$op[0:10][] | select(.link) | "#\(.n)"]
   | if length == 0 then empty
     else "session link in the body of open \(join(", ")): patch each clean with gh api -X PATCH repos/\($repo)/pulls/<n> -F body=@<clean file>, then read it back (open-pr.sh does both)" end),
  (($owner_unanswered_by_thread // {}) | to_entries | map(select(.key as $k | $ex | has($k) | not))
   | if length == 0 then empty
     else "owner comments with no later footer comment, elsewhere: "
       + (.[0:5] | map("#\(.key) \(.value | map(tostring) | lst)") | join("; "))
       + (if length > 5 then "; +\(length - 5) more" else "" end) end),
  (if ($c | length) == 0 then "closed or merged in the last 24h: none"
   else $c[0:8][] |
     "\(if .merged != null then "merged" else "closed" end) #\(.n) at \((.merged // .closed) | hm) head \(.sha)"
   end),
  (if ($c | length) > 8 or $closed_page_may_hold_more then "(more not listed)" else empty end),
  "main \($m); latest ci run on main: \($cirun)"
' 2>/dev/null) || unavailable "unexpected JSON from gh"

[ -n "$out" ] || unavailable "empty answer"
printf '%s\n' "$out"
exit 0
