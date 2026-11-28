#!/usr/bin/env bash
# Usage: land.sh <pr>
#
# One step of `land` for pull request <pr>, as claude/orchestrator. It prints one line,
# `land #<pr>: <answer>`:
#   merged <head>                exit 0
#   stopped: <why>               exit 1: held, unenforced, notEligible, stuck <how>, noEntry, closed,
#                                present <head> (the merge is not this caller's), or a land record
#                                that is no word
#   entered <head>, record <id>  exit 3: the land record is posted; call again now
#   waiting: <for what>          exit 3: call again when the monitor shows this pull request
# An error prints one `land:` line on standard error and exits 2.
set -u

say() { printf 'land: %s\n' "$1" >&2; }
die() { say "$1"; exit 2; }
pr=${1:-}
[ $# = 1 ] && [[ $pr =~ ^[1-9][0-9]{0,6}$ ]] || die "usage: land.sh <pr>"
answer() { printf 'land #%s: %s\n' "$pr" "$1"; exit "$2"; }
for tool in gh jq git flock timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
here=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR source=lib/origin-repo.sh
source "$here/lib/origin-repo.sh"
# shellcheck source-path=SCRIPTDIR source=lib/main-tool.sh
source "$here/lib/main-tool.sh"
# shellcheck source-path=SCRIPTDIR source=lib/land-snapshot.sh
source "$here/lib/land-snapshot.sh"
origin_repo
provider=claude teammate=orchestrator app=claude
[ -z "${MITOS_MAIN_TOOL:-}" ] || say "MITOS_MAIN_TOOL is set, so the tool is not the one this clone keeps"

w=$(mktemp -d 2>/dev/null) || die "cannot make a temp dir"
trap 'rm -rf "$w"' EXIT
common=$(git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die "not in a clone"
exec {pr_lock}>>"$common/mitos-land-$pr.lock" || die "cannot open the lock for #$pr"
flock -n "$pr_lock" || die "another land.sh runs for #$pr"
posted=$common/mitos-land-$pr.record

api() { timeout -k 5 60 gh api "$@" 2>"$w/api.err" </dev/null; }
short() { printf '%s' "${1:0:7}"; }
sha() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
clean() { tr -c 'A-Za-z0-9 .,:;()/#_-' ' ' | cut -c1-80 | sed 's/ *$//'; }

settled() {
  local state head
  api "repos/$repo/pulls/$pr" >"$w/pr.json" || die "cannot read #$pr"
  IFS=$'\t' read -r state head < <(jq -r \
    '[(if .merged_at != null then "merged" else .state end), .head.sha] | @tsv' "$w/pr.json" 2>/dev/null)
  case ${state:-} in
    merged)
      sha "${head:-}" || die "#$pr has no head commit"
      answer "merged $(short "$head")" 0 ;;
    closed) answer "stopped: closed" 1 ;;
    open) ;;
    *) die "cannot read the state of #$pr" ;;
  esac
}

settled
tool_dir=$(main_tool_dir) || die "not in a clone"
tool_bin=$(main_tool_bin "$tool_dir")
main_tool ensure "$tool_dir" 2>"$w/main-tool.err" || die "main's tool: $(tail -n 1 "$w/main-tool.err")"
land_snapshot "$repo" "$w" "$tool_dir" "$tool_bin" 2>"$w/land-snapshot.err" \
  || die "$(tail -n 1 "$w/land-snapshot.err")"
if ! jq -e --argjson n "$pr" 'any(.prs[]; .pr == $n)' "$w/snapshot.json" >/dev/null 2>&1; then
  settled
  die "#$pr is open but not in the snapshot"
fi
jq -c --arg p "$provider" --arg t "$teammate" --argjson n "$pr" \
  '. + {me: {provider: $p, name: $t}, pr: $n}' "$w/snapshot.json" >"$w/input.json" \
  || die "cannot name the caller in the snapshot"
timeout -k 5 120 "$tool_bin" land "$w/input.json" >"$w/decision.json" 2>"$w/land.err" </dev/null
case $? in
  0) ;;
  124 | 137) die "mitos-gate land timed out" ;;
  *) die "the decision is refused: $(head -n 1 "$w/land.err" | clean)" ;;
esac
step=$(jq -c '.step | objects' "$w/decision.json" 2>/dev/null)
[ -n "$step" ] || die "the decision has no step"
field() { jq -r --arg k "$1" '.[$k] | tostring' <<<"$step"; }
obs() {
  jq -r --argjson n "$pr" --arg k "$1" '.prs[] | select(.pr == $n) | .[$k] | tostring' "$w/snapshot.json"
}

as_read() {
  local word
  word=$(jq -r '.word | strings' "$w/decision.json" 2>/dev/null)
  case $word in
    none | held | unnamed | spoke | stale | stands) ;;
    *) word='?' ;;
  esac
  jq -r --argjson n "$pr" --arg word "$word" '.prs[] | select(.pr == $n) | . as $o
    | ($o.author.model // "none" | if test("^[a-z0-9.-]{1,20}$") then . else "?" end) as $author
    | ["updatable=\($o.updatable)", "enforced=\($o.enforced)", "rest=\($o.rest)",
       "base=\($o.base.kind)", "gate=\($o.gate)", "author=\($author)",
       "verdicts=\($o.verdicts | length)", "botAt=\(($o.botAt // "none")[0:7])", "word=\($word)"]
    | "#\($o.pr) as read: " + join(" ")' "$w/snapshot.json" 2>/dev/null \
    | while IFS= read -r line; do say "$line"; done
}

held_lines() {
  local named='^snapshot: #[0-9]+[ :]|^snapshot-fetch: the read of [a-z-]+-[0-9]+ '
  local mine="^snapshot: #${pr}[ :]|^snapshot-fetch: the read of [a-z-]+-$pr "
  {
    grep -hEv "$named" "$w/fetch.err" "$w/snapshot.err"
    grep -hE "$mine" "$w/fetch.err" "$w/snapshot.err"
  } 2>/dev/null | head -n 20 | sed 's/^/land: /' >&2
}

pull_view='[.state, .draft, .head.sha, (.head.repo.full_name // ""), .base.ref, .base.repo.full_name,
  ([.labels[].name] | sort), (.body // "")]'
talk_view='[.[][] | [.id, (.updated_at // .submitted_at // ""), (.state // ""), (.body // "")]] | sort'
board_view='[.title, .state, (.user.login // ""), (.body // "")]'
same() {
  local now was
  now=$(jq -c "$1" "$2" 2>/dev/null) && was=$(jq -c "$1" "$3" 2>/dev/null) \
    && [ -n "$now" ] && [ "$now" = "$was" ]
}
unchanged() {
  local f route dash
  api "repos/$repo/pulls/$pr" >"$w/now-pr.json" || return 2
  jq -c --argjson n "$pr" '.[][] | select(.number == $n)' "$w/reads/open.json" >"$w/was-pr.json" 2>/dev/null
  same "$pull_view" "$w/now-pr.json" "$w/was-pr.json" || return 1
  for f in comments review-comments reviews; do
    case $f in
      comments) route="repos/$repo/issues/$pr/comments?per_page=100" ;;
      review-comments) route="repos/$repo/pulls/$pr/comments?per_page=100" ;;
      reviews) route="repos/$repo/pulls/$pr/reviews?per_page=100" ;;
    esac
    api --paginate --slurp "$route" >"$w/now-$f.json" || return 2
    same "$talk_view" "$w/now-$f.json" "$w/reads/$f-$pr.json" || return 1
  done
  dash=$(jq -r '.number | numbers' "$w/reads/dashboard.json" 2>/dev/null)
  [[ $dash =~ ^[1-9][0-9]{0,6}$ ]] || return 1
  api "repos/$repo/issues/$dash" >"$w/now-dashboard.json" || return 2
  same "$board_view" "$w/now-dashboard.json" "$w/reads/dashboard.json" || return 1
}
read_again() {
  unchanged
  case $? in
    0) ;;
    1) answer "waiting: #$pr changed since the read" 3 ;;
    *) die "cannot read #$pr again" ;;
  esac
}

record() {
  # shellcheck disable=SC2016
  printf '```mitos-protocol\n%s\n```\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_' \
    "$(jq -cn --argjson n "$pr" --arg p "$provider" --arg t "$teammate" --arg h "$1" \
      '{v: 1, kind: "land", task: $n, as: {provider: $p, teammate: $t}, head: $h}')"
}

gate_run() {
  jq -r --arg h "$1" '[.[].check_runs[]? | select(.name == "gate" and .app.slug == "github-actions"
      and .head_sha == $h)] | max_by(.id) | .details_url // ""
    | capture("/actions/runs/(?<r>[0-9]+)/").r // empty' "$w/reads/checks-$pr.json" 2>/dev/null
}

case $(field kind) in
  merge)
    head=$(field head)
    sha "$head" || die "the step names no full commit"
    read_again
    if api -X PUT "repos/$repo/pulls/$pr/merge" -f merge_method=rebase -f "sha=$head" >"$w/merge.json"; then
      if ! api "repos/$repo/pulls/$pr" >"$w/after.json" \
        || ! jq -e '.merged_at != null' "$w/after.json" >/dev/null 2>&1; then
        die "the merge call answered, but #$pr does not read merged"
      fi
      answer "merged $(short "$head")" 0
    fi
    code=$(sed -n 's/.*(HTTP \([0-9][0-9][0-9]\))$/\1/p' "$w/api.err" | tail -n 1)
    case $code in
      405 | 409)
        said=$(jq -r '.message // ""' "$w/merge.json" 2>/dev/null | clean)
        answer "waiting: GitHub refused the merge ($code): $said" 3 ;;
      *) die "the merge call failed: ${code:+HTTP }${code:-no HTTP status}" ;;
    esac ;;
  enter)
    about=$(field about)
    sha "$about" || die "the step names no full commit"
    was='' id=''
    [ ! -f "$posted" ] || read -r was id <"$posted"
    if [ "$was" = "$about" ] && [[ $id =~ ^[1-9][0-9]*$ ]] \
      && jq -e --argjson id "$id" 'any(.[][]; .id == $id)' "$w/reads/comments-$pr.json" >/dev/null 2>&1; then
      as_read
      answer "stopped: the land record in comment $id is read and is no word" 1
    fi
    read_again
    api -X POST "repos/$repo/issues/$pr/comments" -f "body=$(record "$about")" >"$w/posted.json" \
      || die "cannot post the land record"
    id='' slug=''
    IFS=$'\t' read -r id slug < <(jq -r '[(.id | numbers), (.performed_via_github_app.slug // "-")] | @tsv' \
      "$w/posted.json" 2>/dev/null)
    [[ $id =~ ^[1-9][0-9]*$ ]] || die "GitHub returned no id for the land record"
    printf '%s %s\n' "$about" "$id" >"$posted" || say "cannot keep the id of the land record, comment $id"
    [ "$slug" = "$app" ] \
      || answer "stopped: the land record in comment $id carries no $app app, so it is no word" 1
    answer "entered $(short "$about"), record $id" 3 ;;
  wait)
    ahead=$(field ahead)
    [[ $ahead =~ ^[1-9][0-9]*$ ]] || die "the step names no pull request"
    answer "waiting: #$ahead lands first" 3 ;;
  awaitPush)
    head=$(field head)
    sha "$head" || die "the step names no full commit"
    answer "waiting: the replay of $(short "$head") onto main" 3 ;;
  awaitGate)
    head=$(field head) gate=$(obs gate)
    sha "$head" || die "the step names no full commit"
    if [ "$gate" = cancelled ] && run=$(gate_run "$head") && [[ $run =~ ^[1-9][0-9]*$ ]] \
      && api "repos/$repo/actions/runs/$run" >"$w/run.json" \
      && jq -e '.status == "completed" and (.run_attempt | type == "number" and . < 3)' "$w/run.json" \
        >/dev/null 2>&1; then
      api -X POST "repos/$repo/actions/runs/$run/rerun-failed-jobs" >/dev/null \
        || die "cannot re-run the failed jobs of run $run"
      answer "waiting: gate cancelled at $(short "$head"), re-ran the failed jobs of run $run" 3
    fi
    case $gate in
      success | failure | cancelled | skipped | pending | missing) ;;
      *) gate=unread ;;
    esac
    answer "waiting: gate $gate at $(short "$head")" 3 ;;
  present)
    head=$(field head)
    sha "$head" || die "the step names no full commit"
    answer "stopped: present $(short "$head"), the merge is not this caller's" 1 ;;
  stop)
    why=$(field why)
    as_read
    case $why in
      held)
        held_lines
        answer "stopped: held" 1 ;;
      unenforced | notEligible | noEntry) answer "stopped: $why" 1 ;;
      stuck)
        how=$(field stuck)
        case $how in
          conflict | contentChanged | red | historyError | unread) answer "stopped: stuck $how" 1 ;;
        esac ;;
    esac ;;
esac
die "the decision names a step this script does not know"
