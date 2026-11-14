#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
fx="$root/gate/shadow-fixtures"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() {
  echo "FAIL $1"
  shift
  for l in "$@"; do echo "  | $l"; done
  fail=$((fail + 1))
}

got=0
"$bin" shadow "$fx/window" >"$tmp/out" 2>"$tmp/err" || got=$?
if [ "$got" = 0 ] && [ ! -s "$tmp/err" ] && diff "$fx/window.expected" "$tmp/out" >"$tmp/diff"; then
  ok "the window scores to its expected report"
else
  bad "the window scores to its expected report" "exit $got: $(cat "$tmp/err")" "$(cat "$tmp/diff")"
fi

idle="$fx/record-idle.json"
main=$(jq -r .main "$idle")
head257=$(jq -r '.outcome.snapshot.prs[] | select(.pr == 257) | .head' "$idle")
# One folder: the records given as <run>-1.json from 9001 on, and one merge of #257 at the head
# the real record read, 5 s after its read, onto the main it read.
window() {
  local dir=$1 n=9001 r
  shift
  rm -rf "$dir"
  mkdir -p "$dir/records"
  for r in "$@"; do cp "$r" "$dir/records/$n-1.json"; n=$((n + 1)); done
  jq -n --arg m "${BEFORE-$main}" --arg h "$head257" \
    '[{pr: 257, time: "2026-11-14T13:37:18Z", before: $m, head: $h, tree: ""}]' >"$dir/merges.json"
  echo '[]' >"$dir/runs.json"
  echo '[]' >"$dir/baseline.json"
}
scores() {
  local name=$1 pat=$2 got=0
  shift 2
  window "$tmp/w" "$@"
  "$bin" shadow "$tmp/w" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [ "$got" = 0 ] && grep -qxE -- "$pat" "$tmp/out"; then
    ok "$name"
  else
    bad "$name" "exit $got: $(cat "$tmp/err")" "want a line: $pat" "$(cat "$tmp/out")"
  fi
}
edited() { jq -c "$2" "$idle" >"$tmp/$1.json"; echo "$tmp/$1.json"; }

scores "a real record is scored, and this build repeats its decision" \
  '#257 at d7616ac: waits\. one word away, then awaitGate; record of run 9001, 5 s old; 2 updater pushes' \
  "$idle"
scores "a real record drifts nothing" \
  'shadow: 1 merges, 1 records, 0 refused, 0 skipped, 0 drifted, 0 unreadable' "$idle"
scores "a record read in the merge's second is not paired" '#257 at d7616ac: blind\. unseen' \
  "$(edited same-second '.read = "2026-11-14T13:37:18Z"')"
scores "a record whose main moved while it read pairs with no merge" \
  '#257 at d7616ac: blind\. unseen' "$(edited moved '.mainAfter = ("f" * 40)')"
scores "a record whose main was not read pairs with no merge" \
  '#257 at d7616ac: blind\. unseen' "$(edited unread-main '.main = "" | .mainAfter = ""')"
BEFORE='' scores "a merge whose main before it was not read pairs with no record, even one that read no main" \
  '#257 at d7616ac: blind\. unseen' "$(edited moved2 '.mainAfter = ("f" * 40)')"
scores "the control: the same record with main unmoved is paired" \
  '#257 at d7616ac: waits\. .*' "$(edited unmoved '.mainAfter = .main')"
scores "of two records, the newer one before the merge is used" \
  '#257 at d7616ac: waits\. one word away, then awaitGate; record of run 9002, 3 s old; 2 updater pushes' \
  "$idle" "$(edited newer '.read = "2026-11-14T13:37:15Z"')"
scores "a record whose decision this build does not repeat is listed" \
  'record 9001-1: drifted: it printed \{"next":257,"plan":\{"kind":"idle"\}\}, and this build decides \{"next":null,"plan":\{"kind":"idle"\}\}' \
  "$(edited drift '.outcome.decision.next = 257')"
scores "a drifted record is not scored" '#257 at d7616ac: blind\. unseen' "$(edited drift2 '.outcome.decision.next = 257')"
scores "a snapshot this build refuses is drift" \
  'record 9001-1: drifted: its snapshot is refused: prs\[0\]\."extra": not a field here' \
  "$(edited refused-snapshot '.outcome.snapshot.prs[0].extra = 1')"
scores "a key the scorer does not read is ignored" \
  '#257 at d7616ac: waits\. .*' "$(edited extra-key '. + {unknown: {kind: 1}}')"
scores "an empty mainAfterSaid is read" \
  '#257 at d7616ac: waits\. .*' "$(edited said-empty '. + {mainAfterSaid: []}')"
scores "a mainAfterSaid with lines is read" \
  '#257 at d7616ac: waits\. .*' "$(edited said-lines '. + {mainAfterSaid: ["gh: HTTP 502"]}')"
m5=$(jq -r .main "$fx/record-main-after-unread.json")
BEFORE=$m5 scores "the record whose second read of main failed is decided" \
  'shadow: 1 merges, 1 records, 0 refused, 0 skipped, 0 drifted, 0 unreadable' \
  "$fx/record-main-after-unread.json"
BEFORE=$m5 scores "the record whose second read of main failed pairs with no merge of its main" \
  '#257 at d7616ac: blind\. unseen' "$fx/record-main-after-unread.json"
BEFORE=$m5 scores "the control: with its second read, that record is paired" \
  '#257 at d7616ac: blind\. not listed in run 9001' \
  "$(jq -c '.mainAfter = .main | .mainAfterSaid = []' "$fx/record-main-after-unread.json" >"$tmp/said-control.json"; echo "$tmp/said-control.json")"
scores "the refused record is counted" \
  'shadow: 1 merges, 1 records, 1 refused, 0 skipped, 0 drifted, 0 unreadable' "$fx/record-refused.json"
scores "the skipped record is counted" \
  'shadow: 1 merges, 1 records, 0 refused, 1 skipped, 0 drifted, 0 unreadable' "$fx/record-skipped.json"
scores "a record of another version is refused" \
  'record 9001-1: unreadable: v is 2, and this scorer reads v 1' "$fx/record-v2.json"
scores "the record whose main moved is decided, and pairs with no merge of its main" \
  'shadow: 1 merges, 1 records, 0 refused, 0 skipped, 0 drifted, 0 unreadable' "$fx/record-main-moved.json"
scores "a time that is not UTC to the second is refused" \
  'record 9001-1: unreadable: \.read: expected a time, YYYY-MM-DDTHH:MM:SSZ' \
  "$(edited bad-time '.read = "2026-11-14T13:37:13+00:00"')"
scores "a commit that is not 40 hexadecimal digits is refused" \
  'record 9001-1: unreadable: \.outcome\.trees\[0\]\.tree: expected a commit, 40 hexadecimal digits' \
  "$(edited bad-tree '.outcome.trees = [{commit: ("a" * 40), tree: "::error::x"}]')"
scores "a trigger of an unknown kind is refused" \
  'record 9001-1: unreadable: \.trigger\.kind: "schedule" is not a trigger' \
  "$(edited bad-trigger '.trigger = {kind: "schedule"}')"
scores "an outcome of an unknown kind is refused" \
  'record 9001-1: unreadable: \.outcome\.kind: "late" is not an outcome' \
  "$(edited bad-outcome '.outcome.kind = "late"')"
scores "the runs of each trigger are counted" \
  'runs: mainMoved 1, gateDone 2 \(cancelled 1\), comment 1, dispatch 1; 0 superseded while pending, 0 skipped by the filter' \
  "$idle" "$(edited t1 '.trigger = {kind: "mainMoved"}')" \
  "$(edited t2 '.trigger = {kind: "gateDone", head: ("a" * 40), conclusion: "cancelled"}')" \
  "$(edited t3 '.trigger = {kind: "gateDone", head: ("a" * 40), conclusion: "success"}')" \
  "$(edited t4 '.trigger = {kind: "comment", pr: 257, id: 9}')"

window "$tmp/w" "$idle"
mv "$tmp/w/records/9001-1.json" "$tmp/w/records/latest.json"
got=0
"$bin" shadow "$tmp/w" >"$tmp/out" 2>&1 || got=$?
if [ "$got" = 0 ] && grep -qx 'record latest: unreadable: the name is not <run>-<attempt>.json' "$tmp/out"; then
  ok "a record file not named by its run is listed"
else
  bad "a record file not named by its run is listed" "exit $got" "$(cat "$tmp/out")"
fi

errs() {
  local name=$1 pat=$2 got=0
  "$bin" shadow "$tmp/w" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [ "$got" = 1 ] && [ ! -s "$tmp/out" ] && [ "$(grep -c '' "$tmp/err")" = 1 ] \
    && grep -qxE -- "shadow: $pat" "$tmp/err"; then
    ok "$name"
  else
    bad "$name" "exit $got, stdout: $(cat "$tmp/out")" "stderr: $(cat "$tmp/err")" "want: $pat"
  fi
}
window "$tmp/w" "$idle"
rm "$tmp/w/merges.json"
errs "a missing file is exit 1" 'merges\.json is missing'
window "$tmp/w" "$idle"
echo '[{"pr": 1}]' >"$tmp/w/merges.json"
errs "a merge without a time is exit 1" 'merges\.json\[0\]\.time: missing'
window "$tmp/w" "$idle"
echo '[{"id": 1, "conclusion": "Cancelled"}]' >"$tmp/w/runs.json"
errs "a conclusion that is not one is exit 1" 'runs\.json\[0\]\.conclusion: expected 1 to 32 of a-z and _'
window "$tmp/w" "$idle"
echo '{' >"$tmp/w/baseline.json"
errs "a file that is not JSON is exit 1" 'baseline\.json is not JSON: .*'
window "$tmp/w" "$idle"
rm -r "$tmp/w/records"
errs "a folder without records/ is exit 1" 'records/ is missing'
got=0
"$bin" shadow >"$tmp/out" 2>"$tmp/err" || got=$?
if [ "$got" = 2 ] && [ ! -s "$tmp/out" ]; then ok "no argument is a usage error"; else bad "no argument is a usage error" "exit $got"; fi

# shadow-fetch.sh, against a gh that answers each route from fixed text
day=$(date -u +%F)
art="$tmp/art"
mkdir -p "$art"
jq -c '.trigger = {kind: "mainMoved"}' "$idle" >"$art/record.json"
(cd "$art" && zip -q record.zip record.json) || { echo "FAIL zip"; exit 1; }
merge_sha=$(printf 'c%.0s' {1..40})
fake="$tmp/fake"
mkdir -p "$fake"
cat >"$fake/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
run() { printf '{"id":%s,"run_attempt":1,"event":"push","conclusion":"%s","created_at":"x","run_started_at":"x","updated_at":"x"}' "$1" "$2"; }
case "$*" in
  *"actions/workflows/land.yml/runs"*"&page=1")
    printf '{"workflow_runs":['
    for i in $(seq 8001 8099); do run "$i" skipped; printf ','; done
    run 8100 skipped
    printf ']}' ;;
  *"actions/workflows/land.yml/runs"*"&page=2")
    printf '{"workflow_runs":[%s,%s,%s]}' "$(run 9001 success)" "$(run 9002 cancelled)" "$(run 9003 skipped)" ;;
  *"actions/workflows/ci.yml/runs"*"&page=1")
    printf '{"workflow_runs":[{"id":1,"event":"pull_request","triggering_actor":{"login":"mitos-pr-updater[bot]"}},{"id":2,"event":"push","triggering_actor":null}]}' ;;
  *"artifacts?name=land-record-9001-1&"*)
    printf '{"total_count":3,"artifacts":[{"id":66,"expired":false,"workflow_run":{"id":4242}},{"id":55,"expired":true,"workflow_run":{"id":9001}},{"id":77,"expired":false,"workflow_run":{"id":9001}}]}' ;;
  *"artifacts?name="*) printf '{"total_count":0,"artifacts":[]}' ;;
  *"artifacts/77/zip"*) cat "$FAKE_ZIP" ;;
  *"pulls?state=closed"*"&page=1")
    printf '[{"number":257,"merged_at":"%sT23:59:59Z","updated_at":"%sT23:59:59Z","merge_commit_sha":"%s","head":{"sha":"%s"}},{"number":6,"merged_at":null,"updated_at":"%sT23:59:58Z","merge_commit_sha":null,"head":{"sha":"%s"}},{"number":5,"merged_at":"2000-01-01T00:00:00Z","updated_at":"2000-01-01T00:00:00Z","merge_commit_sha":"%s","head":{"sha":"%s"}}]' \
      "$FAKE_DAY" "$FAKE_DAY" "$FAKE_MERGE" "$FAKE_HEAD" "$FAKE_DAY" "$FAKE_HEAD" "$FAKE_MERGE" "$FAKE_HEAD" ;;
  "api -i repos/"*"/activity?ref=refs/heads/main&direction=desc&per_page=100")
    [ -n "${FAKE_NO_ACTIVITY:-}" ] && exit 1
    printf 'HTTP/1.1 200 OK\r\nLink: <https://api.github.com/repositories/1/activity?ref=refs%%2Fheads%%2Fmain&per_page=100&after=Y3Vy_c29y-1>; rel="next"\r\n\r\n'
    printf '[{"before":"x1","after":"x2","timestamp":"%sT23:59:59Z"}]' "$FAKE_DAY" ;;
  "api -i repos/"*"/activity?ref=refs/heads/main&direction=desc&per_page=100&after=Y3Vy_c29y-1")
    printf 'HTTP/1.1 200 OK\r\n\r\n[{"before":"%s","after":"%s","timestamp":"%sT23:59:59Z"},{"before":"x","after":"y","timestamp":"2000-01-01T00:00:00Z"}]' \
      "$FAKE_MAIN" "$FAKE_MERGE" "$FAKE_DAY" ;;
  *"git/commits/"*)
    [ -n "${FAKE_BLOCK:-}" ] && mkdir -p "$FAKE_BLOCK"
    printf 'dddddddddddddddddddddddddddddddddddddddd\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fake/gh"
fetch() {
  local got=0
  PATH="$fake:$PATH" FAKE_LOG="$tmp/gh.log" FAKE_ZIP="$art/record.zip" FAKE_DAY="$day" \
    FAKE_MERGE="$merge_sha" FAKE_HEAD="$head257" FAKE_MAIN="$main" \
    "$root/gate/shadow-fetch.sh" "$@" >"$tmp/fetch.out" 2>"$tmp/fetch.err" || got=$?
  return "$got"
}
rm -f "$tmp/gh.log"
if fetch owner/mitos "$day" "$tmp/f"; then
  have=$(cd "$tmp/f" && find . -type f | sort | paste -sd' ' -)
  want="./baseline.json ./merges.json ./records/9001-1.json ./runs.json"
  if [ "$have" = "$want" ] && [ ! -s "$tmp/fetch.err" ]; then
    ok "fetch: one file per input, and one record per artifact"
  else
    bad "fetch: one file per input, and one record per artifact" "have: $have" "$(cat "$tmp/fetch.err")"
  fi
  want='[{"pr":257,"time":"'"$day"'T23:59:59Z","head":"'"$head257"'","before":"'"$main"'","tree":"dddddddddddddddddddddddddddddddddddddddd"}]'
  if [ "$(jq -c . "$tmp/f/merges.json")" = "$want" ]; then
    ok "fetch: only the merges of the window, with main before and the tree"
  else
    bad "fetch: only the merges of the window, with main before and the tree" "$(cat "$tmp/f/merges.json")" "want: $want"
  fi
  if [ "$(jq -c 'map(.actor)' "$tmp/f/baseline.json")" = '["mitos-pr-updater[bot]",""]' ]; then
    ok "fetch: the baseline names who started each ci run"
  else
    bad "fetch: the baseline names who started each ci run" "$(cat "$tmp/f/baseline.json")"
  fi
  if grep -q "actions/workflows/land.yml/runs?created=$day&per_page=100&page=2" "$tmp/gh.log" \
    && ! grep -qi graphql "$tmp/gh.log" && [ "$(grep -c '^api ' "$tmp/gh.log")" = "$(grep -c '' "$tmp/gh.log")" ] \
    && ! grep -q 'land-record-9003' "$tmp/gh.log"; then
    ok "fetch: REST only, one day at a time, and no artifact read for a run the filter skipped"
  else
    bad "fetch: REST only, one day at a time, and no artifact read for a run the filter skipped" "$(cat "$tmp/gh.log")"
  fi
  if grep -q 'artifacts/77/zip' "$tmp/gh.log" && ! grep -qE 'artifacts/(55|66)/zip' "$tmp/gh.log"; then
    ok "fetch: only an unexpired artifact of the run itself is read"
  else
    bad "fetch: only an unexpired artifact of the run itself is read" "$(cat "$tmp/gh.log")"
  fi
  if [ "$(jq length "$tmp/f/runs.json")" = 103 ] && ! grep -q -- '--paginate' "$tmp/gh.log" \
    && grep -q 'after=Y3Vy_c29y-1$' "$tmp/gh.log" && ! grep -q 'page=2$' <(grep 'pulls?' "$tmp/gh.log"); then
    ok "fetch: pages by number and by cursor, and stops at the window"
  else
    bad "fetch: pages by number and by cursor, and stops at the window" "$(cat "$tmp/gh.log")"
  fi
  got=0
  "$bin" shadow "$tmp/f" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [ "$got" = 0 ] && grep -qxE '#257 at d7616ac: waits\. .*record of run 9001, [0-9]+ s old.*' "$tmp/out" \
    && grep -qx 'runs: mainMoved 1, gateDone 0 (cancelled 0), comment 0, dispatch 0; 1 superseded while pending, 101 skipped by the filter' "$tmp/out" \
    && grep -qx 'pushes: the updater started 1 ci runs; the plans name 0 distinct pushes' "$tmp/out"; then
    ok "fetch: the folder it writes is one the scorer reads"
  else
    bad "fetch: the folder it writes is one the scorer reads" "exit $got: $(cat "$tmp/err")" "$(cat "$tmp/out")"
  fi
else
  bad "fetch: one file per input, and one record per artifact" "exit non-zero: $(cat "$tmp/fetch.err")"
fi
got=0
FAKE_NO_ACTIVITY=1 fetch owner/mitos "$day" "$tmp/g" || got=$?
if [ "$got" = 1 ] && [ "$(cat "$tmp/fetch.err")" = 'shadow-fetch: the read of the activity of main failed' ]; then
  ok "fetch: a failed read is exit 1, with one line"
else
  bad "fetch: a failed read is exit 1, with one line" "exit $got: $(cat "$tmp/fetch.err")"
fi
got=0
FAKE_BLOCK="$tmp/k/merges.json" fetch owner/mitos "$day" "$tmp/k" || got=$?
if [ "$got" = 1 ] && [ "$(cat "$tmp/fetch.err")" = 'shadow-fetch: merges.json was not written' ]; then
  ok "fetch: a write that fails is exit 1, with one line"
else
  bad "fetch: a write that fails is exit 1, with one line" "exit $got: $(cat "$tmp/fetch.err")"
fi
refuses() {
  local args="$*"
  if fetch "$@"; then
    bad "fetch refuses: $args" "exit 0"
  elif [ "$(grep -c '' "$tmp/fetch.err")" = 1 ] && grep -q '^shadow-fetch: ' "$tmp/fetch.err"; then
    ok "fetch refuses: ${args//$tmp/<tmp>}"
  else
    bad "fetch refuses: $args" "$(cat "$tmp/fetch.err")"
  fi
}
refuses owner/mitos "$day"
refuses owner "$day" "$tmp/h"
refuses owner/.. "$day" "$tmp/h"
refuses owner/mitos 2026-02-30 "$tmp/h"
refuses owner/mitos "$(date -u -d tomorrow +%F)" "$tmp/h"
refuses owner/mitos "$day" "$tmp/f"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
