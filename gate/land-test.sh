#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
base="$root/gate/land-fixtures/queue.json"
land="$root/gate/MitosGate/Land.lean"
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

decides "the owner's /land gives one push, of that pull request" '.' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"step":{"head":"aaa","kind":"awaitPush"},"word":"stands"}'
decides "a landing in flight goes before an agent's entry" 'del(.prs[0]) | .pr = 149' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"ahead":159,"kind":"wait"},"word":"none"}'
decides "the step is of the pull request named, not of the first one listed" '.pr = 159' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"step":{"ahead":153,"kind":"wait"},"word":"none"}'
decides "nothing landing: no next, no push, and the agent may enter" \
  '.prs = [.prs[1] | .words = []] | .pr = 149' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"about":"bbb","kind":"enter"},"word":"none"}'
decides "/hold holds, and the line moves on" '.prs[0].words += [{"kind":"ownerHold","said":950}] | del(.prs[2])' \
  "$land149"',"step":{"kind":"stop","why":"held"},"word":"held"}'
decides "a red gate stops the pull request, and the line moves on" '.prs[0].gate = "failure"' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"kind":"stop","stuck":"red","why":"stuck"},"word":"stands"}'
decides "a replay that would change the content id is not pushed" \
  '.prs[0].base = {"kind":"clean","replay":"xx"} | del(.prs[2])' \
  "$land149"',"step":{"kind":"stop","stuck":"contentChanged","why":"stuck"},"word":"stands"}'
decides "a conflict is passed over" '.prs[0].base = {"kind":"conflict"} | del(.prs[2])' \
  "$land149"',"step":{"kind":"stop","stuck":"conflict","why":"stuck"},"word":"stands"}'
decides "protection that does not bind admins lands nothing" '.prs |= map(.enforced = false)' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"unenforced"},"word":"stands"}'
decides "a pushed head on main waits for its gate" \
  '.prs[0] |= (.head = "ar" | .pushes = [{"byUpdater":true,"before":"aaa","after":"ar"}] | .base = {"kind":"current"} | .gate = "pending") | del(.prs[2])' \
  '{"next":153,"plan":{"kind":"idle"},"step":{"head":"ar","kind":"awaitGate"},"word":"stands"}'
decides "green on main, a kept path: the workflow merges, the tool presents" \
  '.prs[0] |= (.head = "ar" | .pushes = [{"byUpdater":true,"before":"aaa","after":"ar"}] | .base = {"kind":"current"}) | del(.prs[2])' \
  '{"next":153,"plan":{"head":"ar","kind":"merge","pr":153},"step":{"head":"ar","kind":"present"},"word":"stands"}'
decides "green on main, off the kept paths: the allowed agent merges, pinned to the head" \
  "$only149"' | .prs[0] |= (.base = {"kind":"current"})' \
  '{"next":149,"plan":{"kind":"idle"},"step":{"head":"bbb","kind":"merge"},"word":"none"}'
decides "a /land on a kept path that does not approve is no entry, and its word is unnamed" \
  'del(.prs[0].words[0].approves)' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"noEntry"},"word":"unnamed"}'
decides "approves false reads as an absent approves" '.prs[0].words[0].approves = false' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"noEntry"},"word":"unnamed"}'
decides "an owner comment after the approval leaves no entry, and its word is spoke" \
  '.prs[0].words += [{"kind":"ownerSpoke","said":950}]' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"noEntry"},"word":"spoke"}'
decides "an owner comment before the approval does not retire it" \
  '.prs[0].words = [{"kind":"ownerSpoke","said":850}] + .prs[0].words' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"step":{"head":"aaa","kind":"awaitPush"},"word":"stands"}'
decides "an owner push after the approval leaves it stale" \
  '.prs[0] |= (.head = "fff" | .pushes = [{"byUpdater":false,"before":"aaa","after":"fff"}] | .ids += [{"sha":"fff","id":"id-f"}] | .base = {"kind":"current"})' \
  '{"next":159,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"},"word":"stale"}'

decides "a standing fail from a judge on the author's model blocks" \
  "$only149"' | .prs[0].verdicts += [{"said":760,"head":"bbb","judge":{"provider":"claude","name":"reviewer"},"model":"grok","result":"fail"}]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"},"word":"none"}'
decides "the same judge's newer pass lifts its fail" \
  "$only149"' | .prs[0].verdicts += [{"said":760,"head":"bbb","judge":{"provider":"claude","name":"reviewer"},"model":"grok","result":"fail"},{"said":770,"head":"bbb","judge":{"provider":"claude","name":"reviewer"},"model":"grok","result":"pass"}]' \
  "$land149"',"step":{"head":"bbb","kind":"awaitPush"},"word":"none"}'
decides "a pass on the author's model covers nothing" \
  "$only149"' | .prs[0].verdicts = [{"said":750,"head":"bbb","judge":{"provider":"claude","name":"verifier"},"model":"grok","result":"pass"}]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"},"word":"none"}'
decides "with no known author nothing is covered" "$only149"' | del(.prs[0].author)' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"},"word":"none"}'
decides "a canonical null model retains the standing independent Sonnet decision" \
  "$only149"' | .prs[0].author |= (.who.provider = "openai" | .model = null)' \
  "$land149"',"step":{"head":"bbb","kind":"awaitPush"},"word":"none"}'

refuses "present whole author null remains malformed" "$only149 | .prs[0].author = null" 'prs\[0\]\.author: expected an object'
refuses "nested model missing remains malformed" "$only149 | del(.prs[0].author.model)" 'prs\[0\]\.author\.model: missing'
for invalid_model in true 7 '{}' '[]'; do
  refuses "nested author model $invalid_model remains malformed" \
    "$only149 | .prs[0].author.model = $invalid_model" 'prs\[0\]\.author\.model: expected a string'
done

decides "a trust-critical diff needs a verifier-opus pass" \
  "$only149"' | .prs[0].paths = ["gate/Main.lean"]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"},"word":"none"}'
decides "wording-only from a judge other than the author covers, with no second pass" \
  "$only149"' | .prs[0].verdicts = [{"said":750,"head":"bbb","judge":{"provider":"claude","name":"root"},"model":"opus","result":"wordingOnly"}]' \
  "$land149"',"step":{"head":"bbb","kind":"awaitPush"},"word":"none"}'
decides "a standing fail beats wording-only" \
  "$only149"' | .prs[0].verdicts = [{"said":740,"head":"bbb","judge":{"provider":"claude","name":"verifier"},"model":"sonnet","result":"fail"},{"said":750,"head":"bbb","judge":{"provider":"claude","name":"root"},"model":"opus","result":"wordingOnly"}]' \
  '{"next":null,"plan":{"kind":"idle"},"step":{"kind":"stop","why":"notEligible"},"word":"none"}'

decides "a green gate wakes the lander of a pull request in line on an agent's entry" \
  'del(.me, .pr) | .event = {"kind":"gateDone","pr":149,"gate":"success"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"lander","pr":149}}'
decides "a red gate wakes the holder" \
  'del(.me, .pr) | .event = {"kind":"gateDone","pr":149,"gate":"failure"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"holder","pr":149}}'
decides "a green gate on a pull request in line only on the owner's word wakes nobody" \
  'del(.me, .pr) | .event = {"kind":"gateDone","pr":153,"gate":"success"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"nobody"}}'
decides "a red gate on a pull request in line only on the owner's word wakes the holder" \
  'del(.me, .pr) | .event = {"kind":"gateDone","pr":153,"gate":"failure"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"holder","pr":153}}'
pushed153='.prs[0] |= (.head = "ar" | .pushes = [{"byUpdater":true,"before":"aaa","after":"ar"}] | .base = {"kind":"current"})'
decides "a cancelled gate on the owner's word alone wakes the orchestrator to re-run it" \
  "$pushed153"' | .prs[0].gate = "cancelled" | del(.prs[2]) | .event = {"kind":"gateDone","pr":153,"gate":"cancelled"}' \
  '{"next":153,"plan":{"kind":"idle"},"step":{"head":"ar","kind":"awaitGate"},"wake":{"kind":"orchestrator"},"word":"stands"}'
decides "a skipped gate on the owner's word alone wakes the orchestrator, while the agent behind waits" \
  "$pushed153"' | .prs[0].gate = "skipped" | del(.prs[2]) | .pr = 149 | .event = {"kind":"gateDone","pr":153,"gate":"skipped"}' \
  '{"next":153,"plan":{"kind":"idle"},"step":{"ahead":153,"kind":"wait"},"wake":{"kind":"orchestrator"},"word":"none"}'
decides "an agent's entry beside the owner's word still wakes the lander on a green gate" \
  'del(.me, .pr) | .prs[1].words += [{"kind":"ownerLand","said":810,"about":"bbb"}] | .event = {"kind":"gateDone","pr":149,"gate":"success"}' \
  '{"next":149,"plan":{"expect":"bbb","kind":"push","pr":149,"replay":"br"},"wake":{"kind":"lander","pr":149}}'
decides "a move of main wakes nobody" 'del(.me, .pr) | .event = {"kind":"mainMoved"}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"wake":{"kind":"nobody"}}'
decides "the step and the wake are both answered when both are asked" \
  '.event = {"kind":"updaterPushed","pr":153}' \
  '{"next":153,"plan":{"expect":"aaa","kind":"push","pr":153,"replay":"ar"},"step":{"head":"aaa","kind":"awaitPush"},"wake":{"kind":"nobody"},"word":"stands"}'

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
refuses "an owner comment out of order" \
  '.prs[0].words = [{"kind":"ownerSpoke","said":950}] + .prs[0].words' \
  'pull request 153: the words are not in ascending comment id'
refuses "approves that is not true or false" '.prs[0].words[0].approves = "yes"' \
  'prs\[0\]\.words\[0\]\.approves: expected true or false'
refuses "approves on an owner hold" '.prs[0].words = [{"kind":"ownerHold","said":900,"approves":true}]' \
  'prs\[0\]\.words\[0\]\."approves": not a field here'
refuses "approves on an owner comment" '.prs[0].words = [{"kind":"ownerSpoke","said":900,"approves":true}]' \
  'prs\[0\]\.words\[0\]\."approves": not a field here'
refuses "approves on an agent's word" '.prs[1].words[0].approves = true' \
  'prs\[1\]\.words\[0\]\."approves": not a field here'
refuses "one comment id on two words" '.prs[1].words[0].said = 900' 'comment 900 is used by two words'
refuses "me without pr" 'del(.pr)' 'me and pr go together'
refuses "a pr that is not listed" '.pr = 7' 'pr: pull request 7 is not in prs'
refuses "an event about a pull request that is not listed" \
  '.event = {"kind":"gateDone","pr":7,"gate":"success"}' 'event\.pr: pull request 7 is not in prs'
refuses "no prs" 'del(.prs)' 'prs: missing'
refuses "a list that is not a list" '.prs = {}' 'prs: expected a list'
refuses "a snapshot that is not an object" '[]' 'snapshot: expected an object'

got=0
jq -c . "$base" | "$bin" land >"$tmp/out" 2>&1 || got=$?
if [ "$got" = 0 ] && grep -q '^{"next":153,' "$tmp/out"; then ok "a snapshot on standard input"; else bad "a snapshot on standard input" "$(cat "$tmp/out")"; fi
got=0
jq -c . "$base" | "$bin" land - >"$tmp/out" 2>&1 || got=$?
if [ "$got" = 0 ] && grep -q '^{"next":153,' "$tmp/out"; then ok "a snapshot on standard input, named -"; else bad "a snapshot on standard input, named -" "$(cat "$tmp/out")"; fi
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

name="the axiom check names each sorry and each other axiom"
mkdir "$tmp/planted"
if ! awk '
    $0 == "theorem holdWins : HoldWins := by" {
      print "theorem holdWins : HoldWins := sorry"; print "theorem holdWinsAsProved : HoldWins := by"
      n++; next }
    $0 == "theorem noOwnerWordIsNone : agentBehind.word = .none := by decide +kernel" {
      print "theorem noOwnerWordIsNone : agentBehind.word = .none := sorry"; n++; next }
    $0 == "namespace Fixture" {
      print "theorem plantedLemma : True := sorry"
      print "private theorem plantedPrivate : True := sorry"; print; n++; next }
    $0 == "end Fixture" {
      print "axiom plantedAxiom : False"
      print "theorem plantedFixture : (1 : Nat) = 2 := plantedAxiom.elim"; print; n++; next }
    { print }
    END { exit n == 4 ? 0 : 1 }' "$land" >"$tmp/planted/Land.lean"; then
  bad "$name" "a line the test plants beside is no longer in Land.lean"
else
  got=0
  (cd "$root" && lake env lean "$tmp/planted/Land.lean") >"$tmp/planted/out" 2>&1 || got=$?
  want="MitosGate.Land.holdWins depends on the axiom sorryAx
MitosGate.Land.plantedLemma depends on the axiom sorryAx
MitosGate.Land.plantedPrivate depends on the axiom sorryAx
MitosGate.Land.Fixture.noOwnerWordIsNone depends on the axiom sorryAx
MitosGate.Land.Fixture.plantedFixture depends on the axiom MitosGate.Land.Fixture.plantedAxiom"
  named=$(sed -E 's/^.*: error: //' "$tmp/planted/out" | grep ' depends on the axiom ' | sort)
  if [ "$got" = 0 ] || [ "$(grep -c ': error: ' "$tmp/planted/out")" != 1 ] ||
    ! grep -q ': error: .* depends on the axiom ' "$tmp/planted/out" ||
    [ "$named" != "$(printf '%s\n' "$want" | sort)" ]; then
    bad "$name" "exit $got" "$(grep -v ': warning: ' "$tmp/planted/out" | head -20)"
  else
    ok "$name"
  fi
fi

name="the axiom check refuses a listed statement that is no theorem"
mkdir "$tmp/notheorem"
if ! awk '
    $0 == "theorem holdWins : HoldWins := by" { print "def holdWins : HoldWins := by"; n++; next }
    { print }
    END { exit n == 1 ? 0 : 1 }' "$land" >"$tmp/notheorem/Land.lean"; then
  bad "$name" "a line the test changes is no longer in Land.lean"
else
  got=0
  (cd "$root" && lake env lean "$tmp/notheorem/Land.lean") >"$tmp/notheorem/out" 2>&1 || got=$?
  if [ "$got" = 0 ] || [ "$(grep -c ': error: ' "$tmp/notheorem/out")" != 1 ] ||
    ! grep -q ': error: MitosGate.Land.holdWins is not a theorem of this file$' "$tmp/notheorem/out"; then
    bad "$name" "exit $got" "$(grep -v ': warning: ' "$tmp/notheorem/out" | head -20)"
  else
    ok "$name"
  fi
fi
jq -c '.' "$base" >"$tmp/in"
if "$bin" land-answers "$tmp/in" >"$tmp/out" 2>"$tmp/err" &&
  jq -e '.merge == null and .answers[0].pr == 153 and
    .answers[0].line == "Queued at aaa: waiting for the replay." and
    (.answers[0].body | startswith("<!-- land-report -->\n"))' "$tmp/out" >/dev/null; then
  ok "land-answers on the fixture"
else bad "land-answers on the fixture" "$(cat "$tmp/out" "$tmp/err")"; fi
jq -c '.prs[0].words[0].approves = false' "$base" >"$tmp/in"
if "$bin" land-answers "$tmp/in" >"$tmp/out" 2>"$tmp/err" &&
  jq -e '.answers[0].line == "This PR touches a path you keep. To approve and merge it, comment only this line:" and
    .answers[0].body == "<!-- land-report -->\nThis PR touches a path you keep. To approve and merge it, comment only this line:\n\n```\n/land aaa\n```"' \
    "$tmp/out" >/dev/null; then
  ok "a bare land answer decodes its newlines and code block"
else bad "a bare land answer decodes its newlines and code block" "$(cat "$tmp/out" "$tmp/err")"; fi
jq -c '.prs[0] |= (.head = "ar" | .pushes = [{byUpdater:true,before:"aaa",after:"ar"}] |
  .base = {kind:"current"}) | del(.prs[2])' "$base" >"$tmp/in"
if "$bin" land-answers "$tmp/in" >"$tmp/out" 2>"$tmp/err" &&
  jq -e '.merge == {pr:153,head:"ar",approval:450,requiresSpec:false} and .answers == []' "$tmp/out" >/dev/null; then
  ok "the planned merge hands its approval"
else bad "the planned merge hands its approval" "$(cat "$tmp/out" "$tmp/err")"; fi
answers_are() {
  local name=$1 filter=$2 want=$3
  jq -c "$filter" "$base" >"$tmp/in" || { bad "$name" "the jq filter failed"; return; }
  if "$bin" land-answers "$tmp/in" >"$tmp/out" 2>"$tmp/err" &&
    [ "$(jq -c '[.answers[] | [.pr, .line, .land]]' "$tmp/out")" = "$want" ]; then
    ok "$name"
  else bad "$name" "got:  $(cat "$tmp/out" "$tmp/err")" "want: $want"; fi
}
held153='.prs[0].words += [{"kind":"ownerHold","said":1901}]'
answers_are "an answer names the comment of the owner's newest /land" '.' \
  '[[153,"Queued at aaa: waiting for the replay.",450]]'
answers_are "a hold with a failed read names the read" \
  "$held153 | .notes = [{pr: 153, unread: [\"dashboard\", \"protection\"], unmet: [], owner: true}]" \
  '[[153,"Held at aaa: a read failed (unread dashboard, protection). The next run reads again, so no new comment is needed.",450]]'
answers_are "a hold with every read done is the owner's own" \
  "$held153 | .notes = [{pr: 153, unread: [], unmet: [], owner: true}]" \
  '[[153,"Held by your /hold or an edited comment. Comment /land aaa to go on.",450]]'
answers_are "a hold with no note keeps the general line" "$held153" \
  '[[153,"Held by your /hold, an edited comment or a failed read. Comment /land aaa to go on.",450]]'
read_hold149='.prs = [.prs[1] | .words = [{"kind":"ownerHold","said":1601}]] | .pr = 149'
answers_are "a read hold where the owner asked nothing is left out" \
  "$read_hold149 | .notes = [{pr: 149, unread: [\"dashboard\"], unmet: [], owner: false}]" '[]'
answers_are "the same hold with no note is answered, and names no /land" "$read_hold149" \
  '[[149,"Held by your /hold, an edited comment or a failed read. Comment /land bbb to go on.",null]]'
answers_are "a missing provenance entry is named" \
  '.prs[0].rest = false | .notes = [{pr: 153, unread: [], unmet: ["entry"], owner: true}]' \
  '[[153,"Stopped: no provenance entry for the author (provenance admission incomplete).",450]]'
answers_are "with no note, an unmet rest keeps the general line" '.prs[0].rest = false' \
  '[[153,"Stopped: an unanswered owner comment, a missing required label or footer, or unmet author or reviewer verification requirements.",450]]'
jq -c "$held153" "$base" >"$tmp/plain"
jq -c "$held153 | .notes = [{pr: 153, unread: [\"dashboard\"], unmet: [\"entry\"], owner: false}]" "$base" >"$tmp/noted"
if "$bin" land "$tmp/plain" >"$tmp/plain.out" 2>"$tmp/err" && "$bin" land "$tmp/noted" >"$tmp/noted.out" 2>>"$tmp/err" &&
  [ -s "$tmp/plain.out" ] && cmp -s "$tmp/plain.out" "$tmp/noted.out"; then
  ok "a note changes no decision of land"
else bad "a note changes no decision of land" "$(cat "$tmp/plain.out" "$tmp/noted.out" "$tmp/err")"; fi
refuses "a note with a read that does not exist" \
  '.notes = [{pr: 153, unread: ["dashbord"], unmet: [], owner: true}]' \
  'notes\[0\]\.unread\[0\]: "dashbord" is not one of "protection", "stacks", "dashboard"'
refuses "a note with an unmet part that does not exist" \
  '.notes = [{pr: 153, unread: [], unmet: ["luck"], owner: true}]' \
  'notes\[0\]\.unmet\[0\]: "luck" is not one of "footer", "unanswered", "label"'
refuses "a note with a field the format does not define" \
  '.notes = [{pr: 153, unread: [], unmet: [], owner: true, why: "x"}]' 'notes\[0\]\."why": not a field here'
refuses "a note without its owner field" '.notes = [{pr: 153, unread: [], unmet: []}]' \
  'notes\[0\]\.owner: missing'
refuses "two notes for one pull request" \
  '.notes = [{pr: 153, unread: [], unmet: [], owner: true}, {pr: 153, unread: [], unmet: [], owner: false}]' \
  'notes: pull request 153 has two notes'
refuses "a note for a pull request that is not listed" \
  '.notes = [{pr: 1, unread: [], unmet: [], owner: true}]' 'notes: pull request 1 is not in prs'
echo '{"prs":[{"pr":1}]}' >"$tmp/in"
got=0
"$bin" land-answers "$tmp/in" >"$tmp/out" 2>"$tmp/err" || got=$?
if [ "$got" = 1 ] && [ ! -s "$tmp/out" ] && grep -q '^land-answers: the snapshot is refused:' "$tmp/err"; then
  ok "a refused snapshot is refused by land-answers too"
else bad "a refused snapshot is refused by land-answers too" "exit $got" "$(cat "$tmp/out" "$tmp/err")"; fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
