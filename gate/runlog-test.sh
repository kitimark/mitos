#!/usr/bin/env bash
# Tests for `mitos-gate runlog` (gate/MitosGate/RunLog.lean) on scratch directories, plus a replay
# of an edit and an append merged by git's union driver with the repository's .gitattributes.
# Run from anywhere: gate/runlog-test.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null)
bin="$root/.lake/build/bin/mitos-gate"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
out="$tmp/out"

# A valid record for task $1, attempt $2, with an optional note $3.
rec() {
  printf '{"task":"%s","role":"builder","model":"m","attempt":%s,"iterations":1,"wall_min":2,"tokens":null,"errors_by_kind":{"unsolved_goals":1},"lint_hits":[],"escalations":["hint"],"outcome":"in-review","note":"%s"}\n' "$1" "$2" "${3:-}"
}

# expect <name> <exit code> <grep -E pattern or ""> <runlog args...>
expect() {
  local name=$1 code=$2 pat=$3 got=0
  shift 3
  "$bin" runlog "$@" >"$out" 2>&1 || got=$?
  if [ "$got" != "$code" ]; then
    echo "FAIL $name: exit $got, expected $code"; sed 's/^/  | /' "$out"; fail=$((fail + 1)); return
  fi
  if [ -n "$pat" ] && ! grep -qE -- "$pat" "$out"; then
    echo "FAIL $name: output does not match /$pat/"; sed 's/^/  | /' "$out"; fail=$((fail + 1)); return
  fi
  echo "ok   $name"; pass=$((pass + 1))
}

# fresh <case>: empty base and head directories for one case.
fresh() {
  b="$tmp/$1/base"; h="$tmp/$1/head"
  mkdir -p "$b" "$h"
}

fresh append
{ rec A 1; rec B 1; } >"$b/d1.ndjson"
{ rec A 1; rec B 1; rec C 1; rec A 2; } >"$h/d1.ndjson"
expect "append-only additions pass" 0 '^run log OK: 1 file\(s\), 4 record\(s\).*1 file\(s\) compared' --base "$b" --head "$h"

fresh edit
{ rec A 1; rec B 1; rec C 1; } >"$b/d1.ndjson"
{ rec A 1; rec B 1 "corrected"; rec C 1; } >"$h/d1.ndjson"
expect "an edited line fails at its line" 1 "^::error file=$h/d1.ndjson,line=2::line 2 of the merge-base version is missing" --base "$b" --head "$h"

fresh delete
{ rec A 1; rec B 1; rec C 1; } >"$b/d1.ndjson"
{ rec A 1; rec C 1; } >"$h/d1.ndjson"
expect "a deleted line fails at its line" 1 "^::error file=$h/d1.ndjson,line=2::" --base "$b" --head "$h"

fresh delfile
rec A 1 >"$b/d1.ndjson"
rec B 1 >"$b/d2.ndjson"
rec A 1 >"$h/d1.ndjson"
expect "a deleted file fails" 1 "^::error file=$h/d2.ndjson,line=1::.*the file was deleted" --base "$b" --head "$h"

fresh dup
{ rec A 1; rec B 1 "first"; rec C 1; rec B 1 "second"; } >"$h/d1.ndjson"
expect "a union-produced duplicate fails at the second record" 1 "^::error file=$h/d1.ndjson,line=4::a second record for task \"B\", role \"builder\", attempt 1; the first is at $h/d1.ndjson:2" --head "$h"

fresh dupfiles
rec A 1 >"$h/d1.ndjson"
rec A 1 "again" >"$h/d2.ndjson"
expect "a duplicate across two files fails" 1 "^::error file=$h/d2.ndjson,line=1::a second record" --head "$h"

fresh samerole
{ rec A 1; rec A 2; rec A 1 | sed 's/"builder"/"verifier"/'; rec B 1; } >"$h/d1.ndjson"
expect "the key is task, role and attempt" 0 '^run log OK: 1 file\(s\), 4 record\(s\)' --head "$h"

fresh json
{ rec A 1; echo '{"task":"B","role":"builder",'; } >"$h/d1.ndjson"
expect "invalid JSON fails at its line" 1 "^::error file=$h/d1.ndjson,line=2::the line is not valid JSON" --head "$h"

fresh notobj
echo '["task","A"]' >"$h/d1.ndjson"
expect "a JSON value that is not an object fails" 1 "line=1::the line is not a JSON object" --head "$h"

fresh blank
{ rec A 1; echo; rec B 1; } >"$h/d1.ndjson"
expect "a blank line fails" 1 "line=2::the line is not valid JSON" --head "$h"

fresh missing
rec A 1 | sed 's/"wall_min":2,//' >"$h/d1.ndjson"
expect "a missing field fails" 1 "line=1::field \"wall_min\" is missing" --head "$h"

fresh type
{
  rec A 1 | sed 's/"attempt":1/"attempt":"1"/'
  rec B 1 | sed 's/"lint_hits":\[\]/"lint_hits":[1]/'
  rec C 1 | sed 's/"tokens":null/"tokens":-3/'
  rec D 1 | sed 's/"note":""/"note":7/'
} >"$h/d1.ndjson"
expect "a wrong type fails (attempt)" 1 "line=1::field \"attempt\" must be a natural number" --head "$h"
expect "a wrong type fails (lint_hits)" 1 "line=2::field \"lint_hits\" must be an array of strings" --head "$h"
expect "a wrong type fails (tokens)" 1 "line=3::field \"tokens\" must be a natural number or null" --head "$h"
expect "a wrong type fails (note)" 1 "line=4::field \"note\" must be a string" --head "$h"

fresh outcome
rec A 1 | sed 's/"in-review"/"done"/' >"$h/d1.ndjson"
expect "an unknown outcome fails" 1 'line=1::field "outcome" is "done", not one of' --head "$h"

fresh optional
rec A 1 | sed 's/,"note":""//; s/"tokens":null/"tokens":120000/' >"$h/d1.ndjson"
expect "note is optional and tokens may be a number" 0 '^run log OK' --head "$h"

fresh newfile
rec A 1 >"$b/d1.ndjson"
rec A 1 >"$h/d1.ndjson"
{ rec B 1; rec C 1; } >"$h/d2.ndjson"
expect "a new file passes" 0 '^run log OK: 2 file\(s\), 3 record\(s\)' --base "$b" --head "$h"

fresh order
{ rec A 1; rec B 1; rec C 1; } >"$b/d1.ndjson"
{ rec X 1; rec C 1; rec Y 1; rec A 1; rec B 1; } >"$h/d1.ndjson"
expect "interleaved order passes" 0 '^run log OK' --base "$b" --head "$h"

fresh nonl
rec A 1 | tr -d '\n' >"$b/d1.ndjson"
{ rec A 1; rec B 1 | tr -d '\n'; } >"$h/d1.ndjson"
expect "a last line without a newline is a line" 0 '^run log OK: 1 file\(s\), 2 record\(s\)' --base "$b" --head "$h"

fresh other
rec A 1 >"$h/d1.ndjson"
echo 'not json' >"$h/README.md"
mkdir "$h/sub"
echo 'not json' >"$h/sub/x.ndjson"
expect "only *.ndjson directly in the directory is read" 0 '^run log OK: 1 file\(s\)' --head "$h"

fresh hidden
echo 'not json' >"$h/.ndjson"
expect "a name that union's *.ndjson matches is read, dot or not" 1 "file=$h/.ndjson,line=1::the line is not valid JSON" --head "$h"

fresh linkdir
rec A 1 >"$h/d1.ndjson"
ln -s "$h" "$tmp/linkdir/runs"
expect "a symlinked directory is refused" 1 '^::error::run-log directory .* is missing, or is not a plain directory' --head "$tmp/linkdir/runs"

fresh symlink
echo 'secret' >"$tmp/symlink/outside"
ln -s "$tmp/symlink/outside" "$h/d1.ndjson"
expect "a symlink is refused, not read" 1 "line=1::not a regular file" --head "$h"
if grep -q secret "$out"; then echo "FAIL symlink target printed"; fail=$((fail + 1)); fi

fresh utf8
printf '\xff\xfe\n' >"$h/d1.ndjson"
expect "invalid UTF-8 fails" 1 "line=1::not valid UTF-8" --head "$h"

# A hostile key: a newline, an ANSI escape, a bidi override, a workflow command, a zero-width
# space and joiner, a soft hyphen and a braille blank in the task (JSON escapes, decoded by the
# parser), and a file name with a comma and colons. The output must stay one line per problem, with
# none of those characters raw and no second workflow command.
fresh hostile
evil='x\n::warning::injected\u001b[2J\u202e%0A,y\u200b\u200d\u00ad\u2800'
hf="$h/a,b::c.ndjson"
{ rec "$evil" 1; rec "$evil" 1 again; } >"$hf"
expect "a hostile string prints safely" 1 '^::error file=.*a%2Cb%3A%3Ac.ndjson,line=2::a second record for task "x\\u\{000A\}::warning::injected\\u\{001B\}\[2J\\u\{202E\}%250A,y\\u\{200B\}\\u\{200D\}\\u\{00AD\}\\u\{2800\}"' --head "$h"
if LC_ALL=C grep -q $'[\x01-\x08\x0b-\x1f\x7f]' "$out"; then
  echo "FAIL hostile: raw control character in output"; fail=$((fail + 1))
fi
if grep -v '^::error ' "$out" | grep -qv '^[0-9]* run-log problem(s)'; then
  echo "FAIL hostile: a line that is not an annotation or the summary"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
fi
raw() { if grep -qF -- "$2" "$out"; then echo "FAIL hostile: raw $1 in output"; fail=$((fail + 1)); fi; }
raw "bidi override U+202E" $'\xe2\x80\xae'
raw "zero-width space U+200B" $'\xe2\x80\x8b'
raw "zero-width joiner U+200D" $'\xe2\x80\x8d'
raw "soft hyphen U+00AD" $'\xc2\xad'
raw "braille blank U+2800" $'\xe2\xa0\x80'

fresh args
expect "--head is required" 2 'runlog needs --head' --base "$b"
expect "an unknown argument is refused" 2 'unknown or incomplete argument' --head "$h" --bogus
expect "a missing directory fails" 1 '^::error::run-log directory .* is missing' --head "$tmp/nope"
expect "a missing base directory fails" 1 '^::error::run-log directory .* is missing' --base "$tmp/nope" --head "$h"

# Replay: the base ends with record B; the PR corrects B in place; main appends C. With the
# repository's .gitattributes, the rebase of the PR onto main succeeds without a conflict, and
# keeps both versions of B.
repo="$tmp/replay"
mkdir -p "$repo/ops/runs"
cp "$root/.gitattributes" "$repo/.gitattributes"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
{ rec A 1; rec B 1 "wrong"; } >"$repo/ops/runs/d1.ndjson"
g add -A
g commit -qm base
g checkout -qb pr
{ rec A 1; rec B 1 "corrected"; } >"$repo/ops/runs/d1.ndjson"
g commit -qam "pr: correct B in place"
g checkout -q main
rec C 1 >>"$repo/ops/runs/d1.ndjson"
g commit -qam "main: append C"

snap() { rm -rf "${tmp:?}/$1"; mkdir -p "$tmp/$1"; g archive "$2" ops/runs | tar -x -C "$tmp/$1"; }
snap pr-base "$(g merge-base main pr)"
snap pr-head pr
expect "replay: the PR alone fails the append-only check" 1 "^::error file=$tmp/pr-head/ops/runs/d1.ndjson,line=2::line 2 of the merge-base version" --base "$tmp/pr-base/ops/runs" --head "$tmp/pr-head/ops/runs"

g checkout -q pr
if ! g rebase -q main >"$out" 2>&1; then
  echo "FAIL replay: the rebase stopped on a conflict"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
else
  echo "ok   replay: the rebase succeeds with merge=union"; pass=$((pass + 1))
  snap main-head main
  sed 's/^/  | /' "$repo/ops/runs/d1.ndjson"
  # The rebased PR keeps base line B, so append-only passes; the duplicate key is what fails.
  expect "replay: the rebased PR fails on the duplicate key" 1 "^::error file=$repo/ops/runs/d1.ndjson,line=[0-9]+::a second record for task \"B\", role \"builder\", attempt 1" --base "$tmp/main-head/ops/runs" --head "$repo/ops/runs"
  if grep -q 'merge-base version' "$out"; then echo "FAIL replay: append-only failed too"; fail=$((fail + 1)); fi
  n=$(grep -n '"corrected"' "$repo/ops/runs/d1.ndjson" | cut -d: -f1)
  m=$(grep -n '"wrong"' "$repo/ops/runs/d1.ndjson" | cut -d: -f1)
  second=$((n > m ? n : m))
  expect "replay: the annotation names the later version's line ($second)" 1 "^::error file=$repo/ops/runs/d1.ndjson,line=$second::" --head "$repo/ops/runs"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
