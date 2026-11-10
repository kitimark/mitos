#!/usr/bin/env bash
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

# put <dir> <date> <task> <attempt> [note]: a record file under its own name,
# <task>-builder-<attempt>.json.
put() {
  mkdir -p "$1/$2"
  rec "$3" "$4" "${5:-}" >"$1/$2/$3-builder-$4.json"
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
expect "an appended day-file line fails" 1 "^::error file=$h/d1.ndjson,line=3::line 3 is not in the merge-base version: a day file may not gain a line" --base "$b" --head "$h"

fresh edit
{ rec A 1; rec B 1; rec C 1; } >"$b/d1.ndjson"
{ rec A 1; rec B 1 "corrected"; rec C 1; } >"$h/d1.ndjson"
expect "an edited line fails at its line" 1 "^::error file=$h/d1.ndjson,line=2::line 2 of the merge-base version differs from this file" --base "$b" --head "$h"

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
expect "a new day file fails" 1 "^::error file=$h/d2.ndjson,line=1::a new day file. Each attempt's record goes in its own file" --base "$b" --head "$h"

fresh order
{ rec A 1; rec B 1; rec C 1; } >"$b/d1.ndjson"
{ rec X 1; rec C 1; rec Y 1; rec A 1; rec B 1; } >"$h/d1.ndjson"
expect "a reordered day file fails" 1 "^::error file=$h/d1.ndjson,line=1::line 1 of the merge-base version differs" --base "$b" --head "$h"

fresh nonl
rec A 1 | tr -d '\n' >"$b/d1.ndjson"
rec A 1 | tr -d '\n' >"$h/d1.ndjson"
expect "a last line without a newline is a line" 0 '^run log OK: 1 file\(s\), 1 record\(s\)' --base "$b" --head "$h"

fresh other
rec A 1 >"$h/d1.ndjson"
echo 'not json' >"$h/README.md"
expect "README.md is not read" 0 '^run log OK: 1 file\(s\), 1 record\(s\)' --head "$h"
mkdir "$h/sub"
echo 'not json' >"$h/sub/x.ndjson"
expect "a day file in a folder does not belong" 1 "^::error file=$h/sub/x.ndjson,line=1::does not belong in a run-log folder" --head "$h"

fresh hidden
echo 'not json' >"$h/.ndjson"
expect "a name ending in .ndjson is read, dot or not" 1 "file=$h/.ndjson,line=1::the line is not valid JSON" --head "$h"

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

# Record files: ops/runs/<date>/<task>-<role>-<attempt>.json, one record each.
fresh files
rec A 1 >"$b/d1.ndjson"
put "$b" 2026-11-10 B 1
rec A 1 >"$h/d1.ndjson"
put "$h" 2026-11-10 B 1
put "$h" 2026-11-10 C 1
put "$h" 2026-11-11 B 2
echo 'not json' >"$h/README.md"
expect "record files pass next to a day file" 0 '^run log OK: 4 file\(s\), 4 record\(s\).*every day file matches the merge base and every record file is kept \(2 file\(s\) compared\)' --base "$b" --head "$h"
rec A 1 | sed 's/"builder"/"red-team"/' >"$h/2026-11-11/A-red-team-1.json"
expect "the role is part of the name" 0 '^run log OK: 5 file\(s\), 5 record\(s\)' --base "$b" --head "$h"

fresh nonl1
mkdir -p "$h/2026-11-10"
rec A 1 | tr -d '\n' >"$h/2026-11-10/A-builder-1.json"
expect "a record file without a final newline passes" 0 '^run log OK: 1 file\(s\), 1 record\(s\)' --head "$h"

fresh twolines
mkdir -p "$h/2026-11-10"
{ rec A 1; rec A 1; } >"$h/2026-11-10/A-builder-1.json"
expect "a record file with two lines fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::a record file holds one record on one line" --head "$h"

fresh emptyfile
mkdir -p "$h/2026-11-10"
: >"$h/2026-11-10/A-builder-1.json"
expect "an empty record file fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::a record file holds one record on one line" --head "$h"

fresh blankafter
mkdir -p "$h/2026-11-10"
{ rec A 1; echo; } >"$h/2026-11-10/A-builder-1.json"
expect "a blank line after the record fails" 1 "line=1::a record file holds one record on one line" --head "$h"

fresh badjson
mkdir -p "$h/2026-11-10"
echo '{"task":"A",' >"$h/2026-11-10/A-builder-1.json"
expect "a record file that is not JSON fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::the line is not valid JSON" --head "$h"

fresh badname
mkdir -p "$h/2026-11-10"
rec A 1 >"$h/2026-11-10/A-builder-2.json"
expect "a file not named by its record's key fails" 1 "^::error file=$h/2026-11-10/A-builder-2.json,line=1::the file must be named \"A-builder-1.json\", from its record's task, role and attempt" --head "$h"

fresh unsafe
mkdir -p "$h/2026-11-10"
rec 'a b' 1 >"$h/2026-11-10/a b-builder-1.json"
expect "a task with a blank fails" 1 "file=$h/2026-11-10/a b-builder-1.json,line=1::task \"a b\" must start with a letter or a digit" --head "$h"
expect "unsafe names are refused one by one" 1 '^1 run-log problem' --head "$h"
rec '.x' 1 >"$h/2026-11-10/.x-builder-1.json"
expect "a task that starts with a dot fails" 1 "file=$h/2026-11-10/.x-builder-1.json,line=1::task \".x\" must start" --head "$h"
rec 'P1/2' 1 >"$h/2026-11-10/P1-builder-1.json"
expect "a task with a slash fails" 1 "file=$h/2026-11-10/P1-builder-1.json,line=1::task \"P1/2\" must start" --head "$h"
rec B 1 | sed 's/"builder"/""/' >"$h/2026-11-10/B--1.json"
expect "an empty role fails" 1 "file=$h/2026-11-10/B--1.json,line=1::role \"\" must not be empty" --head "$h"

fresh notdate
mkdir -p "$h/notes"
rec A 1 >"$h/notes/A-builder-1.json"
expect "a record file outside a date folder fails" 1 "^::error file=$h/notes/A-builder-1.json,line=1::a record file must be in a folder named by its date" --head "$h"

fresh stray
rec A 1 >"$h/d1.ndjson"
echo x >"$h/notes.txt"
expect "a stray file fails" 1 "^::error file=$h/notes.txt,line=1::does not belong in the run log" --head "$h"
rm "$h/notes.txt"
mkdir -p "$h/2026-11-10/sub"
expect "a folder in a day folder fails" 1 "^::error file=$h/2026-11-10/sub,line=1::does not belong in a run-log folder" --head "$h"
rmdir "$h/2026-11-10/sub"
echo x >"$h/2026-11-10/.hidden"
expect "a stray file in a day folder fails" 1 "^::error file=$h/2026-11-10/.hidden,line=1::does not belong in a run-log folder" --head "$h"

# A folder named README.md is a folder like any other, so a record in it is not in a date folder.
# (An empty folder passes, but git keeps no empty folder.)
fresh readmedir
mkdir "$h/README.md"
rec A 1 >"$h/README.md/A-builder-1.json"
expect "a README.md that is a folder is not skipped" 1 "^::error file=$h/README.md/A-builder-1.json,line=1::a record file must be in a folder named by its date" --head "$h"

fresh readmelink
ln -s /dev/null "$h/README.md"
expect "a README.md that is a symlink fails" 1 "^::error file=$h/README.md,line=1::does not belong in the run log" --head "$h"

fresh jsondir
mkdir -p "$h/2026-11-10/A-builder-1.json"
expect "a folder named like a record file fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::not a regular file" --head "$h"

fresh symlinkrec
echo 'secret' >"$tmp/symlinkrec/outside"
mkdir -p "$h/2026-11-10"
ln -s "$tmp/symlinkrec/outside" "$h/2026-11-10/A-builder-1.json"
expect "a symlinked record file is refused, not read" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::not a regular file" --head "$h"
if grep -q secret "$out"; then echo "FAIL symlinked record file printed"; fail=$((fail + 1)); fi

fresh symlinkfolder
mkdir -p "$tmp/symlinkfolder/real"
rec A 1 >"$tmp/symlinkfolder/real/A-builder-1.json"
ln -s "$tmp/symlinkfolder/real" "$h/2026-11-10"
expect "a symlinked day folder is refused, not read" 1 "^::error file=$h/2026-11-10,line=1::does not belong in the run log" --head "$h"

fresh dupdays
put "$h" 2026-11-10 A 1 first
put "$h" 2026-11-11 A 1 second
expect "one attempt on two days fails" 1 "^::error file=$h/2026-11-11/A-builder-1.json,line=1::a second record for task \"A\", role \"builder\", attempt 1; the first is at $h/2026-11-10/A-builder-1.json:1" --head "$h"

fresh duplegacy
rec A 1 >"$h/d1.ndjson"
put "$h" 2026-11-10 A 1 again
expect "one attempt in a day file and a record file fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::a second record for task \"A\", role \"builder\", attempt 1; the first is at $h/d1.ndjson:1" --head "$h"

fresh changed
put "$b" 2026-11-10 A 1 first
put "$h" 2026-11-10 A 1 second
expect "a changed base record file fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::this record file is on the base branch and was changed. A record file never changes" --base "$b" --head "$h"

fresh deleted
put "$b" 2026-11-10 A 1
put "$b" 2026-11-10 B 1
put "$h" 2026-11-10 B 1
expect "a deleted base record file fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::this record file is on the base branch and was deleted" --base "$b" --head "$h"

fresh moved
put "$b" 2026-11-10 A 1
put "$h" 2026-11-11 A 1
expect "a base record file moved to another day fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::this record file is on the base branch and was deleted" --base "$b" --head "$h"

fresh basesymlink
mkdir -p "$b/2026-11-10"
ln -s /dev/null "$b/2026-11-10/A-builder-1.json"
put "$h" 2026-11-10 A 1
expect "a merge-base record file that cannot be read fails" 1 "^::error file=$h/2026-11-10/A-builder-1.json,line=1::the merge-base copy: not a regular file" --base "$b" --head "$h"

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
# raw <case> <what> <bytes>: the case fails if <bytes> occur in the output.
raw() { if grep -qF -- "$3" "$out"; then echo "FAIL $1: raw $2 in output"; fail=$((fail + 1)); fi; }
raw hostile "bidi override U+202E" $'\xe2\x80\xae'
raw hostile "zero-width space U+200B" $'\xe2\x80\x8b'
raw hostile "zero-width joiner U+200D" $'\xe2\x80\x8d'
raw hostile "soft hyphen U+00AD" $'\xc2\xad'
raw hostile "braille blank U+2800" $'\xe2\xa0\x80'

# The same hostile task in a record file, whose name holds a newline, a workflow command, a bidi
# override and a comma and colons, and the same in a day folder's name.
fresh hostilerec
mkdir -p "$h/2026-11-10" "$h/"$'d\n::warning::injected\xe2\x80\xae'
rec "$evil" 1 >"$h/2026-11-10/"$'x\n::warning::injected\xe2\x80\xae,a:b.json'
rec A 1 >"$h/"$'d\n::warning::injected\xe2\x80\xae/A-builder-1.json'
expect "a hostile record file prints safely" 1 '^::error file=.*/2026-11-10/x\\u\{000A\}%3A%3Awarning%3A%3Ainjected\\u\{202E\}%2Ca%3Ab\.json,line=1::task "x\\u\{000A\}::warning::injected\\u\{001B\}\[2J\\u\{202E\}%250A,y' --head "$h"
expect "a hostile folder name prints safely" 1 '^::error file=.*/d\\u\{000A\}%3A%3Awarning%3A%3Ainjected\\u\{202E\}/A-builder-1\.json,line=1::a record file must be in a folder named by its date' --head "$h"
if LC_ALL=C grep -q $'[\x01-\x08\x0b-\x1f\x7f]' "$out"; then
  echo "FAIL hostilerec: raw control character in output"; fail=$((fail + 1))
fi
if grep -v '^::error ' "$out" | grep -qv '^[0-9]* run-log problem(s)'; then
  echo "FAIL hostilerec: a line that is not an annotation or the summary"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
fi
raw hostilerec "bidi override U+202E" $'\xe2\x80\xae'

# A file name with a newline, a workflow command and a byte that is not UTF-8. Lean reads the name
# back with U+FFFD for that byte, so reading the file throws an I/O error that names the path. The
# error must be one `::error::` line, through oneLine, not printed raw by the Lean runtime.
fresh ioerror
rec A 1 >"$h/"$'z\n::warning::injected\xff.ndjson'
expect "an I/O error prints safely" 1 '^::error::the run-log check stopped on an I/O error: .*/z\\u\{000A\}::warning::injected\\u\{FFFD\}\.ndjson$' --head "$h"
if grep -qv '^::error::' "$out"; then
  echo "FAIL ioerror: a line that is not an annotation"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
fi
raw ioerror "U+FFFD" $'\xef\xbf\xbd'

fresh args
expect "--head is required" 2 'runlog needs --head' --base "$b"
expect "an unknown argument is refused" 2 'unknown or incomplete argument' --head "$h" --bogus
expect "an unknown argument prints safely" 2 '^unknown or incomplete argument "--x\\u\{000A\}::warning::injected\\u\{200B\}"$' --head "$h" $'--x\n::warning::injected\xe2\x80\x8b'
if grep -qE '^[[:space:]]*::' "$out"; then
  echo "FAIL args: a line starts a workflow command"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
fi
raw args "zero-width space U+200B" $'\xe2\x80\x8b'
expect "a missing directory fails" 1 '^::error::run-log directory .* is missing' --head "$tmp/nope"
expect "a missing base directory fails" 1 '^::error::run-log directory .* is missing' --base "$tmp/nope" --head "$h"
# A relative name, so that the 60 characters `quote` keeps hold all of it.
expect "a missing directory's name prints safely" 1 '^::error::run-log directory "nope\\u\{000A\}::warning::injected\\u\{200B\}" is missing' --head $'nope\n::warning::injected\xe2\x80\x8b'
raw missingdir "zero-width space U+200B" $'\xe2\x80\x8b'

# `mitos-gate lock-models`, as eval/cheats/run.sh re-pins a cheat case's models: a model file whose
# name holds a newline and a workflow command makes reading it throw an I/O error that names the
# path. In write mode and with --check, the exit must be 1, and stdout and stderr together, split at
# CR and LF as the runner splits a log, must be one line: the gate's own `::error::` line, through
# oneLine. So no line of the name, a `::warning::` or an `::error::` command, reaches the log.
# lockexpect <name> <workspace> <grep -E pattern> [--check]
lockexpect() {
  local name=$1 ws=$2 pat=$3 got=0 lines cmds
  shift 3
  rm -f "$ws/models.lock"
  "$bin" lock-models --workspace "$ws" "$@" >"$out" 2>&1 || got=$?
  lines=$(tr '\r' '\n' <"$out" | grep -c '' || true)
  cmds=$(tr '\r' '\n' <"$out" | grep -cE '^[[:space:]]*(::|##\[)' || true)
  if [ "$got" != 1 ]; then
    echo "FAIL $name: exit $got, expected 1"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
  elif [ "$lines" != 1 ] || [ "$cmds" != 1 ]; then
    echo "FAIL $name: $lines line(s) and $cmds workflow command(s), expected the gate's one"
    sed 's/^/  | /' "$out"; fail=$((fail + 1))
  elif ! grep -qE -- "$pat" "$out"; then
    echo "FAIL $name: output does not match /$pat/"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
  elif [ -e "$ws/models.lock" ]; then
    echo "FAIL $name: models.lock was written"; fail=$((fail + 1))
  else
    echo "ok   $name"; pass=$((pass + 1))
  fi
}

# The content is not UTF-8.
ws="$tmp/lockmodels/content"
mkdir -p "$ws/Models"
printf 'def a := 1\n' >"$ws/Models/A.lean"
printf '\xff' >"$ws/Models/"$'x\n::warning::forged-by-lock-models.lean'
for mode in "" --check; do
  lockexpect "lock-models${mode:+ $mode}: an I/O error on a model's content prints safely" "$ws" \
    '^::error::lock-models stopped on an I/O error: .*/Models/x\\u\{000A\}::warning::forged-by-lock-models\.lean' ${mode:+"$mode"}
done
# The name is not UTF-8, so Lean looks for a file named with U+FFFD, and the error says it is missing.
ws="$tmp/lockmodels/name"
mkdir -p "$ws/Models"
printf 'def a := 1\n' >"$ws/Models/A.lean"
printf 'def y := 1\n' >"$ws/Models/"$'y\n::error::forged\xff.lean'
for mode in "" --check; do
  lockexpect "lock-models${mode:+ $mode}: an I/O error on a model's name prints safely" "$ws" \
    '^::error::lock-models stopped on an I/O error: .*/Models/y\\u\{000A\}::error::forged\\u\{FFFD\}\.lean$' ${mode:+"$mode"}
  raw "lock-models name" "U+FFFD" $'\xef\xbf\xbd'
done

repo="$tmp/replay"
mkdir -p "$repo/ops/runs"
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
expect "replay: the PR's edit fails equality" 1 "^::error file=$tmp/pr-head/ops/runs/d1.ndjson,line=2::line 2 of the merge-base version differs" --base "$tmp/pr-base/ops/runs" --head "$tmp/pr-head/ops/runs"

g checkout -q pr
if g rebase -q main >"$out" 2>&1; then
  echo "FAIL replay: the rebase succeeded"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
elif g status --porcelain | grep -q '^UU ops/runs/d1.ndjson$'; then
  echo "ok   replay: an edit rebased over an append stops on a conflict"; pass=$((pass + 1))
else
  echo "FAIL replay: no conflict in the day file"; g status --porcelain | sed 's/^/  | /'; fail=$((fail + 1))
fi
g rebase --abort 2>/dev/null || true

# Replays of record files, one per attempt, rebased as .github/scripts/rebase-prs.sh rebases
# pid <rev>: the change id of <rev> against its merge base with main, with git's diff settings
# pinned so that no local configuration changes it.
pid() {
  g -c core.attributesFile=/dev/null diff --no-color --no-ext-diff --no-textconv --no-renames \
    --full-index --src-prefix=a/ --dst-prefix=b/ "$(g merge-base main "$1")" "$1" |
    git patch-id --verbatim | cut -d' ' -f1
}
# gate <case> <base rev> <head rev>: snapshots of both and the check as ci.yml runs it on a PR.
gate() {
  snap "$1-base" "$2"
  snap "$1-head" "$3"
  "$bin" runlog --base "$tmp/$1-base/ops/runs" --head "$tmp/$1-head/ops/runs" >"$out" 2>&1 || true
}
repo="$tmp/replay-files"
runs="$repo/ops/runs"
mkdir -p "$runs" "$repo/src"
g init -q -b main
printf 'one\ntwo\nthree\n' >"$repo/src/a.txt"
rec M 1 >"$runs/2026-11-09.ndjson"
put "$runs" 2026-11-09 N 1
g add -A
g commit -qm base

# The #74 shape: the PR adds its record and a later commit corrects it. Then main gains three
# records, two in the PR's day folder. The rebase is clean, keeps one file with the correction,
# and keeps the change id; the rebased PR passes.
g checkout -qb pr
printf 'one\ntwo\nthree\nfour\n' >"$repo/src/a.txt"
put "$runs" 2026-11-10 X 1 first
g add -A
g commit -qm "pr: a change and its record"
put "$runs" 2026-11-10 X 1 corrected
g commit -qam "pr: correct its own record"
before=$(pid pr)
g checkout -q main
put "$runs" 2026-11-10 Y 1
put "$runs" 2026-11-10 Z 3
put "$runs" 2026-11-11 W 1
g add -A
g commit -qm "main: three records"
g checkout -q --detach pr
if ! g rebase -q main >"$out" 2>&1; then
  echo "FAIL files replay: the rebase stopped"; sed 's/^/  | /' "$out"; fail=$((fail + 1)); g rebase --abort
else
  after=$(pid HEAD)
  if [ "$before" = "$after" ] && [ -n "$before" ]; then
    echo "ok   files replay: the change id is kept over the rebase (${before:0:12})"; pass=$((pass + 1))
  else
    echo "FAIL files replay: the change id changed, $before -> $after"; fail=$((fail + 1))
  fi
  n=$(g ls-tree -r --name-only HEAD ops/runs | grep -c '/X-builder-1\.json$' || true)
  if [ "$n" = 1 ] && g show HEAD:ops/runs/2026-11-10/X-builder-1.json | grep -q '"note":"corrected"'; then
    echo "ok   files replay: one file holds the corrected record"; pass=$((pass + 1))
  else
    echo "FAIL files replay: $n file(s) for X, or not the corrected one"; fail=$((fail + 1))
  fi
  gate rf main HEAD
  if grep -q '^run log OK: 6 file(s), 6 record(s).*kept (5 file(s) compared)' "$out"; then
    echo "ok   files replay: the rebased PR passes"; pass=$((pass + 1))
  else
    echo "FAIL files replay: the rebased PR does not pass"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
  fi
fi

# Two PRs record one attempt on one day with different text: one path, so the rebase stops on an
# add/add conflict (the updater labels the PR needs-rebase) instead of keeping two records.
g checkout -q -B same main
put "$runs" 2026-11-11 V 1 from-pr
g add -A
g commit -qm "same: V"
g checkout -q main
put "$runs" 2026-11-11 V 1 from-main
g add -A
g commit -qm "main: V"
g checkout -q --detach same
if g rebase -q main >"$out" 2>&1; then
  echo "FAIL same-day replay: the rebase succeeded"; fail=$((fail + 1))
elif g status --porcelain | grep -q '^AA ops/runs/2026-11-11/V-builder-1.json$'; then
  echo "ok   same-day replay: the rebase stops on an add/add conflict"; pass=$((pass + 1))
else
  echo "FAIL same-day replay: no add/add conflict"; g status --porcelain | sed 's/^/  | /'; fail=$((fail + 1))
fi
g rebase --abort 2>/dev/null || true

# One attempt on another day: two paths, so git sees nothing; the check across files fails it.
g checkout -q -B other main~1
put "$runs" 2026-11-12 V 1 from-other
g add -A
g commit -qm "other: V on another day"
g checkout -q --detach other
if ! g rebase -q main >"$out" 2>&1; then
  echo "FAIL other-day replay: the rebase stopped"; sed 's/^/  | /' "$out"; fail=$((fail + 1)); g rebase --abort
else
  gate ro main HEAD
  if grep -q "^::error file=$tmp/ro-head/ops/runs/2026-11-12/V-builder-1.json,line=1::a second record for task \"V\"" "$out"; then
    echo "ok   other-day replay: the rebased PR fails on the duplicate key"; pass=$((pass + 1))
  else
    echo "FAIL other-day replay: no duplicate-key error"; sed 's/^/  | /' "$out"; fail=$((fail + 1))
  fi
fi

# The same record already on main, as when a stacked PR's parent landed it: the rebase drops the
# commit and one file remains.
g checkout -q -B ident main
put "$runs" 2026-11-12 U 1 same
g add -A
g commit -qm "ident: U"
g checkout -q main
put "$runs" 2026-11-12 U 1 same
g add -A
g commit -qm "main: U"
g checkout -q --detach ident
if ! g rebase -q main >"$out" 2>&1; then
  echo "FAIL identical replay: the rebase stopped"; sed 's/^/  | /' "$out"; fail=$((fail + 1)); g rebase --abort
elif [ "$(g rev-parse HEAD)" = "$(g rev-parse main)" ]; then
  echo "ok   identical replay: the commit is dropped, one file remains"; pass=$((pass + 1))
else
  echo "FAIL identical replay: the commit was kept"; fail=$((fail + 1))
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
