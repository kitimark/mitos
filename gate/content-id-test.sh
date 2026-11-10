#!/usr/bin/env bash
# Tests for `mitos-gate content-id` (gate/MitosGate/ContentId.lean) on scratch repositories: what
# changes the id and what keeps it, where a hunk applies, the git config and environment variants,
# and a shell reference for the normalized diff. Day files are ordinary files in that diff. Run
# from anywhere:
# gate/content-id-test.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null)
bin="$root/.lake/build/bin/mitos-gate"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
out="$tmp/out"
pass=0
fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; [ -s "$out" ] && sed 's/^/  | /' "$out"; fail=$((fail + 1)); }

repo="$tmp/repo"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }
# cid <base> <head> [--verbose]: the id, or empty with the message in $out. It runs in $cwd, or
# at the top of $repo.
cwd=""
cid() { (cd "${cwd:-$repo}" && "$bin" content-id "$@" 2>"$out") || true; }
# old <base> <head>: the rule this replaces, under the repository's own config; empty if it fails.
old() {
  local mb
  mb=$(g merge-base "$1" "$2") || return 0
  { g diff "$mb" "$2" | g patch-id --verbatim | cut -d' ' -f1; } 2>/dev/null || true
}
# pdiff <from> <to>: the diff with the tool's pinned options, for the shell references.
pdiff() {
  g -c core.quotePath=true -c diff.suppressBlankEmpty=false diff --patch --no-color --no-ext-diff \
    --no-textconv --no-renames --text --full-index --diff-algorithm=myers --indent-heuristic \
    --unified=3 --inter-hunk-context=0 --src-prefix=a/ --dst-prefix=b/ --no-relative \
    --ignore-submodules=none --submodule=short -O/dev/null "$@"
}
same() { if [ -n "$2" ] && [ "$2" = "$3" ]; then ok "$1"; else echo "  ids: '$2' '$3'"; bad "$1"; fi; }
differ() { if [ -n "$2" ] && [ -n "$3" ] && [ "$2" != "$3" ]; then ok "$1"; else echo "  ids: '$2' '$3'"; bad "$1"; fi; }
# refused <name> <grep -E pattern> <base> <head>: exit 1, no id, and the message on one line.
refused() {
  local name=$1 pat=$2 got=0 id
  shift 2
  id=$(cd "$repo" && "$bin" content-id "$@" 2>"$out") || got=$?
  if [ "$got" != 1 ] || [ -n "$id" ]; then echo "  exit $got, id '$id'"; bad "$name"; return; fi
  if [ "$(grep -c '' "$out")" != 1 ] || ! grep -qE -- "$pat" "$out"; then bad "$name"; return; fi
  ok "$name"
}

rec() { printf '{"task":"%s","role":"builder","attempt":%s}\n' "$1" "$2"; }
lean() { # A.lean with 40 lines; $1 is the proof line of theorem t at line 21.
  for i in $(seq 1 19); do echo "def v$i : Nat := $i"; done
  echo "theorem t (h : True) : True := by"
  echo "$1"
  for i in $(seq 22 40); do echo "def v$i : Nat := $i"; done
}

mkdir -p "$repo"
g init -q -b main
mkdir -p "$repo/ops/runs" "$repo/src"
lean "  exact h" >"$repo/A.lean"
printf 'b1\nb2\n' >"$repo/B.lean"
{ rec A 1; rec B 1; } >"$repo/ops/runs/d1.ndjson"
printf 'bin\0ary\377\r\n' >"$repo/blob.bin"
printf 'x\n' >"$repo/tool.sh"
g add -A
g commit -qm base
g tag base

# The PR: a proof change in A.lean. The day file stays as it is on the base.
g checkout -qb pr
lean "  exact h.elim" >"$repo/A.lean"
g commit -qam pr
id_pr=$(cid main pr)
if [[ "$id_pr" =~ ^[0-9a-f]{64}$ ]]; then ok "the id is 64 hex digits"; else bad "the id is 64 hex digits ($id_pr)"; fi
same "the id is the same on a second run" "$id_pr" "$(cid main pr)"
same "the base can be a name or a commit id" "$id_pr" "$(cid "$(g rev-parse main)" "$(g rev-parse pr)")"

# A whitespace-only change: one space less of indentation, which Lean reads.
g checkout -qb ws base
lean " exact h.elim" >"$repo/A.lean"
g commit -qam ws
differ "a whitespace-only change in a .lean file changes the id" "$id_pr" "$(cid main ws)"
mbw=$(g merge-base main ws)
mbp=$(g merge-base main pr)
same "  (git patch-id without --verbatim cannot see it)" \
  "$(g diff "$mbp" pr -- A.lean | g patch-id | cut -d' ' -f1)" \
  "$(g diff "$mbw" ws -- A.lean | g patch-id | cut -d' ' -f1)"

# Other real changes.
for change in "binary byte:printf 'bin\\0arY\\377\\r\\n' >blob.bin" \
  "carriage return:printf 'b1\\r\\nb2\\n' >B.lean" \
  "mode:chmod +x tool.sh" "symlink:rm tool.sh; ln -s A.lean tool.sh" \
  "new empty file:: >empty.txt" "deleted file:rm B.lean" \
  "file under ops/runs/sub:mkdir -p ops/runs/sub; echo x >ops/runs/sub/x.ndjson"; do
  g checkout -qB var pr
  (cd "$repo" && eval "${change#*:}")
  g add -A
  g commit -qm var
  differ "a change changes the id: ${change%%:*}" "$id_pr" "$(cid main var)"
done

# Replace refs and grafts in the clone do not change the id: git reads the commits as they are.
g replace "$(g rev-parse pr:A.lean)" "$(g rev-parse base:B.lean)"
same "a replace ref for a head blob does not change the id" "$id_pr" "$(cid main pr)"
g replace "$(g rev-parse pr)" "$(g rev-parse ws)"
same "a replace ref for the head commit does not change the id" "$id_pr" "$(cid main pr)"
g replace -l | while read -r r; do g replace -d "$r" >/dev/null; done
g rev-parse pr >"$repo/.git/info/grafts"
if g merge-base main pr >/dev/null 2>&1; then bad "  (the graft should hide the merge-base from plain git)"; fi
same "a graft in info/grafts does not change the id" "$id_pr" "$(cid main pr)"
rm "$repo/.git/info/grafts"

# Rebases. main changes a file the PR does not touch: the PR's diff is unchanged, so the id stays.
g checkout -q main
printf 'b1\nb2\nb3\n' >"$repo/B.lean"
g commit -qam "main: B.lean"
g checkout -qB rebased pr
g rebase -q main
same "a rebase over a file the PR does not touch keeps the id" "$id_pr" "$(cid main rebased)"
# main adds lines far above the PR's hunk: the hunk moves, the id stays.
g checkout -q main
{ printf -- '-- header %s\n' 1 2 3 4 5 6 7 8 9 10; cat "$repo/A.lean"; } >"$repo/A2" && mv "$repo/A2" "$repo/A.lean"
g commit -qam "main: lines at the top of A.lean"
g checkout -qB moved pr
g rebase -q main
same "a rebase that moves the PR's hunk keeps the id" "$id_pr" "$(cid main moved)"
# main changes a line within the PR hunk's three context lines: the id changes.
g checkout -q main
sed -i 's/^def v19 : Nat := 19$/def v19 : Nat := 190/' "$repo/A.lean"
g commit -qam "main: context of the PR's hunk"
g checkout -qB ctx pr
g rebase -q main
differ "a main change in the hunk's context changes the id" "$id_pr" "$(cid main ctx)"

# Where a hunk applies. The same hunk text can apply at two places of a file; the marker `@@ <k>`
# counts how many times the hunk's old-side lines occur above it in the merge-base file.
repo="$tmp/pos"
mkdir -p "$repo"
g init -q -b main
blk() { printf '  run lint\n  run build\n  run proofs\n  run axioms\n  run cheats\n  run lock\n'; }
paranoid() { sed 's/^  run axioms$/  run axioms --paranoid/'; }
{ echo 'strict() {'; blk; echo '}'; } >"$repo/check.sh"
g add -A
g commit -qm base
g checkout -qb pr
{ echo 'strict() {'; blk | paranoid; echo '}'; } >"$repo/check.sh"
g commit -qam "pr: strict() checks axioms with --paranoid"
id_pos=$(cid main pr)
g checkout -q main
{ echo 'strict() {'; blk; echo '}'; echo 'lax() {'; blk; echo '}'; } >"$repo/check.sh"
g commit -qam "main: lax() with the same checks"
g checkout -qb rebased pr
g rebase -q main
same "a rebase over a copy of the hunk's lines below it keeps the id" "$id_pos" "$(cid main rebased)"
g checkout -qb other main
{ echo 'strict() {'; blk; echo '}'; echo 'lax() {'; blk | paranoid; echo '}'; } >"$repo/check.sh"
g commit -qam "the same line in lax() instead"
differ "the same hunk in the other copy changes the id (verifier's rebase pair)" \
  "$(cid main rebased)" "$(cid main other)"
same "  (git patch-id --verbatim cannot see it)" "$(old main rebased)" "$(old main other)"
# The same deletion in strict() and in lax(), at one merge-base.
g checkout -qb h1 main
awk '/^lax\(\) \{/{f=1} !(f && $0=="  run axioms")' "$repo/check.sh" >"$tmp/x" && mv "$tmp/x" "$repo/check.sh"
g commit -qam "drop axioms from lax()"
g checkout -qb h2 main
awk '/^lax\(\) \{/{f=1} !(!f && $0=="  run axioms")' "$repo/check.sh" >"$tmp/x" && mv "$tmp/x" "$repo/check.sh"
g commit -qam "drop axioms from strict()"
differ "one deletion in strict() and in lax() gives two ids (verifier's pair)" "$(cid main h1)" "$(cid main h2)"
same "  (git patch-id --verbatim cannot see it)" "$(old main h1)" "$(old main h2)"
# The marker, against a shell reference: 1 for the copy in lax(), 0 for the one in strict().
for c in "h1 1" "h2 0"; do
  ref=$(pdiff main "${c% *}" | LC_ALL=C grep -av '^index ' |
    LC_ALL=C sed "s/^@@ .*/@@ ${c#* }/" | sha256sum | cut -d' ' -f1)
  (cd "$repo" && "$bin" content-id --verbose main "${c% *}" >/dev/null 2>"$out") || true
  same "the marker of ${c% *} is @@ ${c#* } (shell reference)" "$ref" "$(sed -n 's/^rest \([0-9a-f]*\) .*/\1/p' "$out")"
done
# main adds a copy of the hunk's lines above it: the count moves, so the id changes (fail safe).
g checkout -q main
{ echo 'pre() {'; blk; echo '}'; echo 'strict() {'; blk; echo '}'; echo 'lax() {'; blk; echo '}'; } >"$repo/check.sh"
g commit -qam "main: pre() with the same checks, above strict()"
g checkout -qb above rebased
g rebase -q main
differ "a rebase over a copy of the hunk's lines above it changes the id" "$id_pos" "$(cid main above)"

# Git config and environment. Each variant must give the id of the plain config. The repository
# for these has a rename, a mode change, a binary file, a tab and a quote and a byte that is not
# ASCII in a name, a CRLF line, blank lines in a hunk's context, and a .lean hunk.
repo="$tmp/cfg"
mkdir -p "$repo"
g init -q -b main
mkdir -p "$repo/ops/runs"
lean "  exact h" >"$repo/A.lean"
printf 'one\n\ntwo\n\nthree\nfour\nfive\nsix\nseven\n' >"$repo/blank.txt"
for i in $(seq 1 30); do echo "line $i of a file the PR renames"; done >"$repo/old-name.txt"
printf 'bin\0ary\377\n' >"$repo/blob.bin"
printf 'x\n' >"$repo/tool.sh"
rec A 1 >"$repo/ops/runs/d1.ndjson"
g add -A
# A submodule, as a gitlink with no checkout.
mkdir "$repo/sub"
g update-index --add --cacheinfo 160000,0123456789012345678901234567890123456789,sub
g commit -qm base
g checkout -qb pr
lean "  exact h.elim" >"$repo/A.lean"
printf 'one\n\ntwo\n\nTHREE\nfour\nfive\nsix\nseven\n' >"$repo/blank.txt"
g mv old-name.txt new-name.txt
echo "one more line" >>"$repo/new-name.txt"
printf 'bin\0arY\377\n' >"$repo/blob.bin"
chmod +x "$repo/tool.sh"
printf 'crlf\r\n' >"$repo/"$'n\xc3\xa9w\tt"q.txt'
rec B 1 >>"$repo/ops/runs/d1.ndjson"
g add -A
g update-index --cacheinfo 160000,9876543210987654321098765432109876543210,sub
g commit -qm pr
if [ "$(g diff --raw --no-renames main pr | wc -l)" != 9 ]; then
  echo "FAIL config variants: the PR should change 9 entries"; g diff --raw --no-renames main pr; fail=$((fail + 1))
fi
plain=$(cid main pr)
plain_old=$(old main pr)
if [[ "$plain" =~ ^[0-9a-f]{64}$ ]]; then ok "config variants: the plain id"; else bad "config variants: the plain id ($plain)"; fi
cfgcase() { # cfgcase <name> <setup> <undo>: the id under the setup equals the plain id.
  pushd "$repo" >/dev/null && eval "$2" && popd >/dev/null
  local id o
  id=$(cid main pr)
  o=$(old main pr)
  pushd "$repo" >/dev/null && eval "$3" && popd >/dev/null
  if [ "$o" = "$plain_old" ]; then o="same"; elif [ -z "$o" ]; then o="EMPTY"; else o="differs"; fi
  same "config: $1 (old rule: $o)" "$plain" "$id"
}
gc() { git config "$@"; }
for kv in diff.noprefix=true diff.mnemonicPrefix=true diff.renames=false diff.renames=copies color.diff=always \
  color.ui=always diff.algorithm=histogram diff.algorithm=patience diff.indentHeuristic=false \
  diff.context=8 diff.interHunkContext=10 diff.suppressBlankEmpty=true core.quotePath=false \
  diff.relative=true diff.external=false core.bigFileThreshold=1 diff.ignoreSubmodules=all \
  diff.submodule=log diff.srcPrefix=x/ diff.dstPrefix=y/ core.abbrev=7; do
  cfgcase "$kv" "gc ${kv%%=*} ${kv#*=}" "gc --unset ${kv%%=*}"
done
printf 'A.lean\nblank.txt\n' >"$tmp/order"
cfgcase "diff.orderFile" "gc diff.orderFile $tmp/order" "gc --unset diff.orderFile"
cfgcase "a global config file" "printf '[diff]\n\tnoprefix = true\n\trenames = true\n' >$tmp/global; export GIT_CONFIG_GLOBAL=$tmp/global" "unset GIT_CONFIG_GLOBAL"
cfgcase "config from GIT_CONFIG_COUNT" "export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.noprefix GIT_CONFIG_VALUE_0=true" "unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0"
cfgcase "GIT_DIFF_OPTS=-u9" "export GIT_DIFF_OPTS=-u9" "unset GIT_DIFF_OPTS"
cfgcase "GIT_EXTERNAL_DIFF" "export GIT_EXTERNAL_DIFF=false" "unset GIT_EXTERNAL_DIFF"
cfgcase "attributes: *.lean -diff" "printf '*.lean -diff\n' >.git/info/attributes" "rm .git/info/attributes"
cfgcase "attributes: * binary" "printf '* binary\n' >.git/info/attributes" "rm .git/info/attributes"
cfgcase "attributes: a textconv driver" "printf '*.lean diff=up\n' >.git/info/attributes; gc diff.up.textconv 'tr a-z A-Z <'" "rm .git/info/attributes; gc --unset diff.up.textconv"
cfgcase "attributes: a function-name pattern" "printf '*.lean diff=fn\n' >.git/info/attributes; gc diff.fn.xfuncname '^def.*'" "rm .git/info/attributes; gc --unset diff.fn.xfuncname"
cfgcase "core.attributesFile with -diff" "printf '*.lean -diff\n' >$tmp/attrs; gc core.attributesFile $tmp/attrs" "gc --unset core.attributesFile"
cfgcase "run from a subdirectory" "mkdir -p dir; cwd=$repo/dir" "cwd="

# The shell reference: with no run-log change, `rest` is the SHA-256 of the pinned diff with its
# index lines dropped and its hunk headers written as markers. Every hunk here applies at the only
# place its old-side lines occur in the file, a submodule, a deleted file, a binary file and a new
# file included, so each marker is `@@ 0`. This checks the byte handling (a NUL, a byte that is
# not UTF-8, a CR) and the normalization against an independent implementation.
g checkout -qB norl pr
g checkout -q main -- ops/runs/d1.ndjson
g commit -qm "no run-log change"
mb=$(g merge-base main norl)
ref=$(pdiff "$mb" norl | LC_ALL=C grep -av '^index ' | LC_ALL=C sed 's/^@@ .*/@@ 0/' | sha256sum |
  cut -d' ' -f1)
(cd "$repo" && "$bin" content-id --verbose main norl >/dev/null 2>"$out") || true
same "rest is the SHA-256 of the normalized diff (shell reference)" "$ref" "$(sed -n 's/^rest \([0-9a-f]*\) .*/\1/p' "$out")"
pre=$(printf 'rest %s\nruns\n' "$ref" | sha256sum | cut -d' ' -f1)
same "the id is the SHA-256 of 'rest <rest>' and an empty runs list" "$pre" "$(cid main norl)"

# Usage and revisions.
got=0; (cd "$repo" && "$bin" content-id main >"$out" 2>&1) || got=$?
if [ "$got" = 2 ]; then ok "one argument is a usage error"; else bad "one argument is a usage error (exit $got)"; fi
refused "a name that is not a commit is refused" '"nope" is not a commit in this repository' main nope
refused "a name that starts with - is refused" '"--output=x" is not a revision' main --output=x
g checkout -q --orphan other
g commit -qm "unrelated root"
refused "commits with no merge-base are refused" 'no merge-base' main other

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
