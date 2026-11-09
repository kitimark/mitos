#!/usr/bin/env bash
# Says whether CodeRabbit has reviewed the current head of a PR, so that a catch-up never hands the
# owner a PR the bot has not reviewed (kitimark-mode skill, Catching the user up). It reads REST
# through `gh api` (GraphQL is blocked in these sessions): the PR's head, CodeRabbit's check run at
# that head, its reviews and its summary comment.
#
# Usage: bot-review.sh <pr> [--request]
#
# It prints one line, `coderabbit #<pr>: <state>`:
#   reviewed <head>                            its check at the head passed, or, with no run going,
#                                              its newest review is of the head; the only state
#                                              that exits 0
#   paused: last reviewed <sha>, head <head>   it paused reviews on the branch after many pushes
#                                              (`reviews.auto_review.auto_pause_after_reviewed_commits`)
#   behind: last reviewed <sha>, head <head>   its run at the head ended without a review: cancelled,
#                                              as when the head moved as it started, failed, or
#                                              skipped for a reason a request overrides, such as a
#                                              draft or a base branch without automatic reviews
#   refused: <reason>                          it skipped the head for its file limit (over 300
#                                              files), which a request does not change
#   pending: last reviewed <sha>, head <head>  its run at the head is queued or running, even when
#                                              it already posted its review, which comes minutes
#                                              before the run ends; or it has not started
# The other states exit 1. `<sha>` is `none` when it has never reviewed the PR. The last reviewed
# commit is the one its summary comment names under "Reviews paused", else the commit of its newest
# review with a body; a review with an empty body is only its reply in a thread. With no CodeRabbit
# check at the head, its summary comment decides: paused under "Reviews paused", and under "Review
# skipped" refused or behind, as for a check; otherwise pending. Any skip that is not a pause or
# the file limit reads behind, so that a request is tried before the owner gets the PR.
#
# A head that only rebases content CodeRabbit reviewed reads paused or behind, not reviewed: its
# check at such a head reads `Review paused` too, and telling a rebase from a change needs the old
# head's commits and `mitos-gate carry`, which builds Lean. One requested review costs less.
#
# --request, on paused or behind, on an open PR: posts one `@coderabbitai review` comment that ends
# with the Claude Code footer, and prints `coderabbit #<pr>: requested a review in comment <id>`.
# It posts nothing while an earlier request is open: a comment whose first line is that command, by
# a member of the repository, newer than CodeRabbit's check at the head, with no CodeRabbit comment
# after it.
#
# Only GitHub's own fields decide who wrote what: the check's app must be `coderabbitai`, and the
# reviews and the summary must come from `coderabbitai[bot]`. Of GitHub's text it prints only
# commit SHAs, checked as hex, and the refusal reason, cut to letters, digits and plain punctuation
# and to 80 characters. Each call has a 20 s timeout. An error prints one `bot-review:` line and
# exits 2. The origin URL is never printed, because it can carry a credential.
set -u

say() { printf 'bot-review: %s\n' "$1"; }
die() { say "$1"; exit 2; }
usage() { die "usage: bot-review.sh <pr> [--request]"; }

pr=
request=0
for a in "$@"; do
  case $a in
    --request) request=1 ;;
    -*) usage ;;
    *) [ -z "$pr" ] || usage; pr=$a ;;
  esac
done
[[ $pr =~ ^[1-9][0-9]{0,6}$ ]] || usage
for tool in gh jq git timeout; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

# owner/name from the origin URL (https, ssh or proxy form), as in watch-github.sh.
url=$(git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null) || die "no origin remote"
repo=$(sed -E 's#/+$##; s#\.git$##; s#^.*[/:]([^/:]+/[^/:]+)$#\1#' <<<"$url")
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "origin is not owner/name"

w=$(mktemp -d 2>/dev/null) || die "cannot make a temp dir"
trap 'rm -rf "$w"' EXIT
api() { # file, then gh api arguments; fails on any error or a timeout
  timeout -k 2 20 gh api "${@:2}" >"$w/$1" 2>/dev/null </dev/null
}

api pr.json "repos/$repo/pulls/$pr" || die "cannot read PR #$pr"
head=$(jq -r '.head.sha' "$w/pr.json" 2>/dev/null)
[[ $head =~ ^[0-9a-f]{40}$ ]] || die "PR #$pr has no head commit"
api checks.json "repos/$repo/commits/$head/check-runs?check_name=CodeRabbit&filter=all&per_page=100" \
  || die "cannot read the checks at the head of PR #$pr"
api reviews.json --paginate --slurp "repos/$repo/pulls/$pr/reviews?per_page=100" \
  || die "cannot read the reviews of PR #$pr"
api comments.json --paginate --slurp "repos/$repo/issues/$pr/comments?per_page=100" \
  || die "cannot read the comments of PR #$pr"

# One tab-separated line: state, last reviewed commit, refusal reason, open request id, PR state.
# An empty field is `-`, because `read` joins adjacent tabs. A field of the wrong shape fails jq.
# shellcheck disable=SC2016 # jq variables, not shell ones
out=$(jq -n -r --arg head "$head" --arg bot 'coderabbitai[bot]' \
  --slurpfile pr "$w/pr.json" --slurpfile checks "$w/checks.json" \
  --slurpfile reviews "$w/reviews.json" --slurpfile comments "$w/comments.json" '
  def hex: type == "string" and test("^[0-9a-f]{40}$");
  def ts: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
  def arr: if type == "array" then . else error("not an array") end;
  def clean: tostring
    | gsub("[\\p{Cc}\\p{Zl}\\p{Zp}\\p{Zs}]+"; " ") | gsub("[^A-Za-z0-9 .,:;!?()/+#_-]"; "")
    | sub("^ +"; "") | sub(" +$"; "") | .[0:80];
  # The skips a request does not override: the file limit ("Too many files!", "375 files exceed
  # the limit of 300").
  def limit: test("too many files|files? exceeds? the limit"; "i");
  ($checks[0].check_runs | arr) as $runs
  | ([$runs[] | select(.name == "CodeRabbit" and .app.slug == "coderabbitai" and .head_sha == $head
       and (.id | type) == "number")] | max_by(.id)) as $run
  | ([$reviews[0] | arr | .[] | arr | .[]
      | select(.user.login == $bot and (.body // "") != "" and (.commit_id | hex))]
     | sort_by(.submitted_at // "", .id) | last) as $review
  | [$comments[0] | arr | .[] | arr | .[] | select((.id | type) == "number")] as $all
  | [$all[] | select(.user.login == $bot)] as $botc
  | ([$botc[] | select(.body // "" | contains("<!-- This is an auto-generated comment: summarize by coderabbit.ai -->"))]
     | min_by(.id) | .body // "") as $sb
  | ($sb | contains("<!-- This is an auto-generated comment: review paused by coderabbit.ai -->")) as $pausednote
  | ((if $pausednote then [$sb | capture("Last reviewed commit: (?<s>[0-9a-f]{40})")] | .[0].s
      else null end) // $review.commit_id // "-") as $last
  | (if $run == null then null else $run.completed_at end) as $since
  | ([$all[] | select((.author_association // "") | IN("OWNER", "MEMBER", "COLLABORATOR"))
      | select((.body // "" | split("\n") | .[0] | sub("^[ \\t]+"; "") | sub("[ \\t\\r]+$"; ""))
               == "@coderabbitai review")
      | select(.created_at | ts) | select($since == null or ($since | ts | not) or .created_at > $since)]
     | max_by(.id)) as $req
  | (if $req != null and ([$botc[] | select((.created_at // "") > $req.created_at)] == [])
     then $req.id | tostring else "-" end) as $open
  | if $run != null and $run.status == "completed" and $run.conclusion == "success" then ["reviewed", "-"]
    elif $run != null and $run.status != "completed" then ["pending", "-"]
    elif $last == $head then ["reviewed", "-"]
    elif $run != null and $run.conclusion == "skipped" then
      ($run.output.title // "" | tostring) as $t
      | if ($t | test("paused"; "i")) then ["paused", "-"]
        elif ($t | limit) then ["refused", ($t | sub("^Review skipped:?"; "") | clean)]
        else ["behind", "-"] end
    elif $run != null then ["behind", "-"]
    elif $pausednote then ["paused", "-"]
    elif ($sb | test("## Review skipped")) then
      ([$sb | capture("## Review skipped[ \\t]*\\n(>[ \\t]*\\n)*>?[ \\t]*(?<r>[^\\n]+)")] | .[0].r // "") as $r
      | if ($r | limit) then ["refused", ($r | clean)] else ["behind", "-"] end
    else ["pending", "-"] end
  | [.[0], $last, .[1], $open, ($pr[0].state | tostring | clean)] | join("\t")' 2>/dev/null) \
  || die "unexpected JSON from GitHub for PR #$pr"
IFS=$'\t' read -r state last reason open prstate <<<"$out"
[[ $last == - || $last =~ ^[0-9a-f]{40}$ ]] && [[ $open == - || $open =~ ^[0-9]+$ ]] \
  || die "unexpected JSON from GitHub for PR #$pr"

h=${head:0:7}
l=${last:0:7}
[ "$last" = - ] && l=none
case $state in
  reviewed) echo "coderabbit #$pr: reviewed $h"; exit 0 ;;
  refused) echo "coderabbit #$pr: refused: $reason"; exit 1 ;;
  paused | behind | pending) echo "coderabbit #$pr: $state: last reviewed $l, head $h" ;;
  *) die "unexpected state for PR #$pr" ;;
esac

if [ "$request" = 1 ] && [[ $state == paused || $state == behind ]]; then
  if [ "$prstate" != open ]; then
    echo "coderabbit #$pr: no request posted: the PR is $prstate"
  elif [ "$open" != - ]; then
    echo "coderabbit #$pr: no request posted: comment $open already requests a review"
  else
    # -f sends the body as a string; -F would read a file named after the `@`.
    body=$(printf '@coderabbitai review\n\nThe head is %s, and CodeRabbit last reviewed %s (%s).\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_' \
      "$h" "$l" "$state")
    api posted.json -X POST "repos/$repo/issues/$pr/comments" -f "body=$body" \
      || die "cannot post the review request on PR #$pr"
    id=$(jq -r '.id | select(type == "number")' "$w/posted.json" 2>/dev/null)
    [[ $id =~ ^[0-9]+$ ]] || die "GitHub did not return the id of the request on PR #$pr"
    echo "coderabbit #$pr: requested a review in comment $id"
  fi
fi
exit 1
