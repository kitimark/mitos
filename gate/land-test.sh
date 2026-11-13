#!/usr/bin/env bash
# `mitos-gate land` over fixed snapshots: each case edits gate/land-fixtures/queue.json with a jq
# filter and checks the printed decision, or the refusal, exactly. Not run by CI yet.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
base="$root/gate/land-fixtures/queue.json"
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

# decides <name> <jq filter over the base snapshot> <expected output>
decides() {
  local name=$1 filter=$2 want=$3 got=0
  jq -c "$filter" "$base" >"$tmp/in" || { bad "$name" "the jq filter failed"; return; }
  "$bin" land "$tmp/in" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [ "$got" != 0 ]; then bad "$name" "exit $got, expected 0" "$(cat "$tmp/err")"; return; fi
  if [ "$(cat "$tmp/out")" != "$want" ] || [ "$(grep -c '' "$tmp/out")" != 1 ]; then
    bad "$name" "got:  $(cat "$tmp/out")" "want: $want"
    return
  fi
  ok "$name"
}

# refuses <name> <jq filter> <regex the one error line starts with, after "land: the snapshot is refused: ">
refuses() {
  local name=$1 filter=$2 pat=$3 got=0
  jq -c "$filter" "$base" >"$tmp/in" || { bad "$name" "the jq filter failed"; return; }
  "$bin" land "$tmp/in" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [ "$got" != 1 ] || [ -s "$tmp/out" ]; then
    bad "$name" "exit $got (expected 1), stdout: $(cat "$tmp/out")"
    return
  fi
  if [ "$(grep -c '' "$tmp/err")" != 1 ] || ! grep -qE -- "^land: the snapshot is refused: $pat" "$tmp/err"; then
    bad "$name" "stderr: $(cat "$tmp/err")" "want:   $pat"
    return
  fi
  ok "$name"
}

only149='.prs = [.prs[1]] | .pr = 149'
land149='{"next":149,"plan":{"expect":"bbb","kind":"push","pr":149,"replay":"br"}'

# The base: the owner's `/land` on 153 goes before the agents' entries, and 153 is pushed once.
decides "the owner's /land gives one push, of that pull request" '.' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"step":{"head":"aaa","kind":"awaitPush"}}'
decides "a landing in flight goes before an agent's entry" 'del(.prs[0]) | .pr = 149' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"ahead":159,"kind":"wait"}}'
decides "nothing landing: no next, no push, and the agent may enter" \
  '.prs = [.prs[1] | .words = []] | .pr = 149' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"about":"bbb","kind":"enter"}}'
decides "/hold holds, and the line moves on" '.prs[0].words += [{"kind":"ownerHold","said":950}] | del(.prs[2])' \
  "$land149"',"step":{"kind":"stop","why":"held"}}'
decides "a red gate stops the pull request, and the line moves on" '.prs[0].gate = "failure"' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"kind":"stop","stuck":"red","why":"stuck"}}'
decides "a replay that would change the content id is not pushed" \
  '.prs[0].base = {"kind":"clean","replay":"xx"} | del(.prs[2])' \
  "$land149"',"step":{"kind":"stop","stuck":"contentChanged","why":"stuck"}}'
decides "a conflict is passed over" '.prs[0].base = {"kind":"conflict"} | del(.prs[2])' \
  "$land149"',"step":{"kind":"stop","stuck":"conflict","why":"stuck"}}'
decides "protection that does not bind admins lands nothing" '.prs |= map(.enforced = false)' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"unenforced"}}'
decides "a pushed head on main waits for its gate" \
  '.prs[0] |= (.head = "ar" | .pushes = [{"byUpdater":true,"before":"aaa","after":"ar"}] | .base = {"kind":"current"} | .gate = "pending") | del(.prs[2])' \
  '{"next":153,"plan":{"kind":"idle"},"step":{"head":"ar","kind":"awaitGate"}}'
decides "green on main, a kept path: the owner merges, the tool presents" \
  '.prs[0] |= (.head = "ar" | .pushes = [{"byUpdater":true,"before":"aaa","after":"ar"}] | .base = {"kind":"current"}) | del(.prs[2])' \
  '{"next":153,"plan":{"kind":"idle"},"step":{"head":"ar","kind":"present"}}'
decides "green on main, off the kept paths: the allowed agent merges, pinned to the head" \
  "$only149"' | .prs[0] |= (.base = {"kind":"current"})' \
  '{"next":149,"plan":{"kind":"idle"},"step":{"head":"bbb","kind":"merge"}}'

# `covered`: the amended rule.
decides "a standing fail from a judge on the author's model blocks" \
  "$only149"' | .prs[0].verdicts += [{"said":760,"head":"bbb","judge":{"provider":"claude","name":"reviewer"},"model":"grok","result":"fail"}]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"}}'
decides "the same judge's newer pass lifts its fail" \
  "$only149"' | .prs[0].verdicts += [{"said":760,"head":"bbb","judge":{"provider":"claude","name":"reviewer"},"model":"grok","result":"fail"},{"said":770,"head":"bbb","judge":{"provider":"claude","name":"reviewer"},"model":"grok","result":"pass"}]' \
  "$land149"',"step":{"head":"bbb","kind":"awaitPush"}}'
decides "a pass on the author's model covers nothing" \
  "$only149"' | .prs[0].verdicts = [{"said":750,"head":"bbb","judge":{"provider":"claude","name":"verifier"},"model":"grok","result":"pass"}]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"}}'
decides "with no known author nothing is covered" "$only149"' | del(.prs[0].author)' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"}}'
decides "a trust-critical diff needs a verifier-opus pass" \
  "$only149"' | .prs[0].paths = ["gate/Main.lean"]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"}}'
decides "wording-only from a judge other than the author covers, with no second pass" \
  "$only149"' | .prs[0].verdicts = [{"said":750,"head":"bbb","judge":{"provider":"claude","name":"root"},"model":"opus","result":"wordingOnly"}]' \
  "$land149"',"step":{"head":"bbb","kind":"awaitPush"}}'
decides "a standing fail beats wording-only" \
  "$only149"' | .prs[0].verdicts = [{"said":740,"head":"bbb","judge":{"provider":"claude","name":"verifier"},"model":"sonnet","result":"fail"},{"said":750,"head":"bbb","judge":{"provider":"claude","name":"root"},"model":"opus","result":"wordingOnly"}]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"}}'

# Who wakes.
decides "a green gate wakes the lander of a pull request in line" \
  'del(.me, .pr) | .event = {"kind":"gateDone","pr":149,"gate":"success"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"lander","pr":149}}'
decides "a red gate wakes the holder" \
  'del(.me, .pr) | .event = {"kind":"gateDone","pr":149,"gate":"failure"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"holder","pr":149}}'
decides "a move of main wakes nobody" 'del(.me, .pr) | .event = {"kind":"mainMoved"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"nobody"}}'
decides "the step and the wake are both answered when both are asked" \
  '.event = {"kind":"updaterPushed","pr":153}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"step":{"head":"aaa","kind":"awaitPush"},"wake":{"kind":"nobody"}}'

# A snapshot that is not well formed is refused, with one line and exit 1.
echo '{"prs": [' >"$tmp/in"
got=0
"$bin" land "$tmp/in" >"$tmp/out" 2>"$tmp/err" || got=$?
if [ "$got" = 1 ] && [ ! -s "$tmp/out" ] && grep -qE '^land: the snapshot is refused: not JSON: ' "$tmp/err"; then
  ok "text that is not JSON is refused"
else
  bad "text that is not JSON is refused" "exit $got" "$(cat "$tmp/err")"
fi
refuses "a field the format does not define" '.prs[0].extra = 1' \
  'prs\[0\]\."extra": not a field here'
refuses "a field with a hostile name is printed escaped, on one line" '.prs[0]["::error::x\ny"] = 1' \
  'prs\[0\]\."::error::x\\u\{005C\}ny": not a field here$'
refuses "a missing field" 'del(.prs[1].rest)' 'prs\[1\]\.rest: missing'
refuses "a wrong type" '.prs[0].pr = "153"' 'prs\[0\]\.pr: expected a natural number'
refuses "a negative number" '.prs[0].pr = -1' 'prs\[0\]\.pr: expected a natural number'
refuses "a fraction" '.prs[0].pr = 1.5' 'prs\[0\]\.pr: expected a natural number'
refuses "null for an optional field" '.prs[0].paths = null' 'prs\[0\]\.paths: expected a list'
refuses "a commit with a character outside letters and digits" '.prs[0].head = "a b"' \
  'prs\[0\]\.head: expected a commit, 1 to 64 letters and digits'
refuses "a commit with a command in it" '.prs[0].head = "##[add-mask]x"' \
  'prs\[0\]\.head: expected a commit, 1 to 64 letters and digits'
refuses "an empty commit" '.prs[0].pushes = [{"byUpdater":true,"before":"","after":"x"}]' \
  'prs\[0\]\.pushes\[0\]\.before: expected a commit'
refuses "a name that is not one of the gate results" '.prs[0].gate = "green"' \
  'prs\[0\]\.gate: "green" is not one of "success", "failure"'
refuses "a kind that is not one of the bases" '.prs[0].base.kind = "ahead"' \
  'prs\[0\]\.base\.kind: "ahead" is not one of "current"'
refuses "a key that does not belong to the kind" '.prs[0].base = {"kind":"current","replay":"x"}' \
  'prs\[0\]\.base\."replay": not a field here'
refuses "a word of a kind that does not exist" '.prs[0].words = [{"kind":"ownerLove","said":1}]' \
  'prs\[0\]\.words\[0\]\.kind: "ownerLove" is not one of'
refuses "a pull request listed twice" '.prs[1].pr = 153' 'pull request 153 is listed twice'
refuses "words out of order" \
  '.prs[0].words = [{"kind":"ownerHold","said":950},{"kind":"ownerLand","said":900,"about":"aaa"}]' \
  'pull request 153: the words are not in ascending comment id'
refuses "one comment id on two words" '.prs[1].words[0].said = 900' 'comment 900 is used by two words'
refuses "me without pr" 'del(.pr)' 'me and pr go together'
refuses "a pr that is not listed" '.pr = 7' 'pr: pull request 7 is not in prs'
refuses "no prs" 'del(.prs)' 'prs: missing'
refuses "a list that is not a list" '.prs = {}' 'prs: expected a list'
refuses "a snapshot that is not an object" '[]' 'snapshot: expected an object'

# Input: standard input, `-`, a file that does not exist, and too many arguments.
got=0
jq -c . "$base" | "$bin" land >"$tmp/out" 2>&1 || got=$?
[ "$got" = 0 ] && grep -q '^{"next":153,' "$tmp/out" && ok "a snapshot on standard input" || bad "a snapshot on standard input" "$(cat "$tmp/out")"
got=0
jq -c . "$base" | "$bin" land - >"$tmp/out" 2>&1 || got=$?
[ "$got" = 0 ] && grep -q '^{"next":153,' "$tmp/out" && ok "a snapshot on standard input, named -" || bad "a snapshot on standard input, named -" "$(cat "$tmp/out")"
got=0
"$bin" land "$tmp/no-such-file" >"$tmp/out" 2>"$tmp/err" || got=$?
if [ "$got" = 1 ] && [ ! -s "$tmp/out" ] && [ "$(grep -c '' "$tmp/err")" = 1 ] && grep -q '^land: stopped on an I/O error: ' "$tmp/err"; then
  ok "a missing file is an error with exit 1"
else
  bad "a missing file is an error with exit 1" "exit $got" "$(cat "$tmp/err")"
fi
got=0
"$bin" land a b >"$tmp/out" 2>"$tmp/err" || got=$?
if [ "$got" = 2 ] && [ ! -s "$tmp/out" ]; then ok "two arguments are a usage error"; else bad "two arguments are a usage error" "exit $got"; fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
