#!/usr/bin/env bash
# Usage: .github/scripts/land-decide.sh <owner/name> <dashboard-issue> <dir>
#
# One decide run, in a clone of the repository: the reads, the snapshot, the decision, then one
# line, <dir>/record.json. It holds no rule: every decision is `mitos-gate`'s, and it reads no
# line that another tool printed. Exit 0: decided, or skipped under the REST floor. Exit 1:
# refused, and the record says at which stage, or the record could not be written. Exit 2: usage.
set -u

die() { printf 'land-decide: %s\n' "$1" >&2; exit 2; }
[ $# = 3 ] || die "usage: land-decide.sh <owner/name> <dashboard-issue> <dir>"
repo=$1 dash=$2 out=$3
gate=${MITOS_GATE:-.lake/build/bin/mitos-gate}
fetch=${SNAPSHOT_FETCH:-gate/snapshot-fetch.sh}
floor=${LAND_REST_FLOOR:-300}
for tool in jq git date gh timeout; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"

sha() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
num() { [[ $1 =~ ^(0|[1-9][0-9]{0,18})$ ]]; }
trigger() {
  case ${LAND_EVENT:-workflow_dispatch} in
    push) jq -cn '{kind: "mainMoved"}' ;;
    workflow_run)
      sha "${LAND_EVENT_HEAD:-}" && [[ ${LAND_EVENT_CONCLUSION:-} =~ ^[a-z_]{1,32}$ ]] || return 1
      jq -cn --arg h "$LAND_EVENT_HEAD" --arg c "$LAND_EVENT_CONCLUSION" \
        '{kind: "gateDone", head: $h, conclusion: $c}' ;;
    issue_comment)
      num "${LAND_EVENT_PR:-}" && num "${LAND_EVENT_COMMENT:-}" || return 1
      jq -cn --argjson p "$LAND_EVENT_PR" --argjson c "$LAND_EVENT_COMMENT" \
        '{kind: "comment", pr: $p, id: $c}' ;;
    workflow_dispatch) jq -cn '{kind: "dispatch"}' ;;
    *) return 1 ;;
  esac
}
trig=$(trigger) || die "the trigger is not one this script records"
tool=$(git rev-parse --verify --quiet 'HEAD^{commit}') || die "not in a clone"
num "$floor" || die "LAND_REST_FLOOR is not a number"

unwritten() { printf 'land-decide: the record was not written\n' >&2; exit 1; }
now() { date -u +%s; }
lines() { if [ -f "$1" ]; then jq -Rsc 'split("\n") | map(select(. != ""))' "$1"; else echo '[]'; fi; }
t_job=${LAND_T0:-$(now)}; num "$t_job" || die "LAND_T0 is not a time"
t0=$(now)
stamp() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
head_of() {
  jq -cn --argjson trigger "$trig" --arg read "$(stamp "$1")" --arg tool "$tool" \
    --argjson setup "$((t0 - t_job))" '{v: 1, trigger: $trigger, read: $read, tool: $tool, setup: $setup}'
}

left=$(timeout -k 5 120 gh api rate_limit --jq .resources.core.remaining 2>/dev/null </dev/null) || left=
if num "$left" && [ "$left" -lt "$floor" ]; then
  jq -c --argjson left "$left" 'del(.setup) + {outcome: {kind: "skipped", remaining: $left}}' \
    <<<"$(head_of "$t0")" >"$out/record.json" || unwritten
  printf 'land-decide: skipped, %s REST calls left\n' "$left"
  exit 0
fi

"$fetch" "$repo" "$dash" "$out/reads" 2>"$out/fetch.err"; code=$?
after=$(timeout -k 5 120 gh api "repos/$repo/branches/main" --jq .commit.sha \
  2>"$out/main-after.err" </dev/null); after_code=$?
if [ "$after_code" = 0 ] && sha "$after"; then
  after_said='[]'
else
  if [ "$after_code" = 0 ]; then why="gave no commit"; else why="exited $after_code"; fi
  printf 'land-decide: the second read of main %s\n' "$why" >>"$out/main-after.err"
  after='' after_said=$(lines "$out/main-after.err")
fi
t1=$(now)
stage=fetch
if [ "$code" = 0 ]; then
  stage=snapshot
  "$gate" snapshot "$out/reads" >"$out/snapshot.json" 2>"$out/snapshot.err"; code=$?
fi
t2=$(now)
if [ "$code" = 0 ]; then
  stage=land
  "$gate" land "$out/snapshot.json" >"$out/decision.json" 2>"$out/land.err"; code=$?
fi
t3=$(now)

main=$(jq -er '.commit.sha' "$out/reads/main.json" 2>/dev/null) && sha "$main" || main=
reads=$(find "$out/reads" -name '*.json' 2>/dev/null | wc -l)
head=$(jq -c --arg main "$main" --arg after "$after" --argjson afterSaid "$after_said" \
  --argjson reads "$reads" --argjson unread "$(lines "$out/fetch.err")" \
  --argjson fetch "$((t1 - t0))" --argjson snapshot "$((t2 - t1))" --argjson decide "$((t3 - t2))" \
  '{v, trigger, read, main: $main, mainAfter: $after, mainAfterSaid: $afterSaid, tool,
    cost: {setup, fetch: $fetch, snapshot: $snapshot, decide: $decide, reads: $reads},
    unread: $unread}' <<<"$(head_of "$t1")")

if [ "$code" != 0 ] || [ -z "$main" ]; then
  jq -c --arg stage "$stage" --argjson said "$(lines "$out/$stage.err")" \
    '. + {outcome: {kind: "refused", stage: $stage, said: $said}}' <<<"$head" >"$out/record.json" || unwritten
  printf 'land-decide: refused at %s\n' "$stage" >&2
  exit 1
fi

trees='[]'
while read -r commit; do
  sha "$commit" || continue
  tree=$(git rev-parse --verify --quiet "$commit^{tree}") || continue
  trees=$(jq -c --arg c "$commit" --arg t "$tree" '. + [{commit: $c, tree: $t}]' <<<"$trees")
done < <(jq -r '.prs[] | select(.base.kind == "clean") | .base.replay' "$out/snapshot.json")

jq -c --argjson head "$head" --argjson trees "$trees" --slurpfile decision "$out/decision.json" \
  --argjson notes "$(lines "$out/snapshot.err")" \
  '$head + {outcome: {kind: "decided", snapshot: ., decision: $decision[0], trees: $trees,
    notes: $notes}}' "$out/snapshot.json" >"$out/record.json" || unwritten
cat "$out/decision.json" "$out/snapshot.err"
