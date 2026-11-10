#!/usr/bin/env bash
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
cwd=""
cid() { (cd "${cwd:-$repo}" && "$bin" content-id "$@" 2>"$out") || true; }
verbatim_patch_id() {
  local mb
  mb=$(g merge-base "$1" "$2") || return 0
  { g diff "$mb" "$2" | g patch-id --verbatim | cut -d' ' -f1; } 2>/dev/null || true
}
pdiff() {
  g -c core.quotePath=true -c diff.suppressBlankEmpty=false diff --patch --no-color --no-ext-diff \
    --no-textconv --no-renames --text --full-index --diff-algorithm=myers --indent-heuristic \
    --unified=3 --inter-hunk-context=0 --src-prefix=a/ --dst-prefix=b/ --no-relative \
    --ignore-submodules=none --submodule=short -O/dev/null "$@"
}
same() { if [ -n "$2" ] && [ "$2" = "$3" ]; then ok "$1"; else echo "  ids: '$2' '$3'"; bad "$1"; fi; }
differ() { if [ -n "$2" ] && [ -n "$3" ] && [ "$2" != "$3" ]; then ok "$1"; else echo "  ids: '$2' '$3'"; bad "$1"; fi; }
refused() {
  local name=$1 pat=$2 got=0 id
  shift 2
  id=$(cd "$repo" && "$bin" content-id "$@" 2>"$out") || got=$?
  if [ "$got" != 1 ] || [ -n "$id" ]; then echo "  exit $got, id '$id'"; bad "$name"; return; fi
  if [ "$(grep -c '' "$out")" != 1 ] || ! grep -qE -- "$pat" "$out"; then bad "$name"; return; fi
  ok "$name"
}

rec() { printf '{"task":"%s","role":"builder","attempt":%s}\n' "$1" "$2"; }
lean() {
  for i in $(seq 1 19); do echo "def v$i : Nat := $i"; done
  echo "theorem t (h : True) : True := by"
  echo "$1"
  for i in $(seq 22 40); do echo "def v$i : Nat := $i"; done
}

mkdir -p "$repo"
g init -q -b main
cp "$root/.gitattributes" "$repo/.gitattributes"
mkdir -p "$repo/ops/runs" "$repo/src"
lean "  exact h" >"$repo/A.lean"
printf 'b1\nb2\n' >"$repo/B.lean"
{ rec A 1; rec B 1; } >"$repo/ops/runs/d1.ndjson"
printf 'bin\0ary\377\r\n' >"$repo/blob.bin"
printf 'x\n' >"$repo/tool.sh"
g add -A
g commit -qm base
g tag base

g checkout -qb pr
lean "  exact h.elim" >"$repo/A.lean"
rec C 1 >>"$repo/ops/runs/d1.ndjson"
g commit -qam pr
id_pr=$(cid main pr)
if [[ "$id_pr" =~ ^[0-9a-f]{64}$ ]]; then ok "the id is 64 hex digits"; else bad "the id is 64 hex digits ($id_pr)"; fi
same "the id is the same on a second run" "$id_pr" "$(cid main pr)"
same "the base can be a name or a commit id" "$id_pr" "$(cid "$(g rev-parse main)" "$(g rev-parse pr)")"

g checkout -qb ws base
lean " exact h.elim" >"$repo/A.lean"
rec C 1 >>"$repo/ops/runs/d1.ndjson"
g commit -qam ws
differ "a whitespace-only change in a .lean file changes the id" "$id_pr" "$(cid main ws)"
mbw=$(g merge-base main ws)
mbp=$(g merge-base main pr)
same "  (git patch-id without --verbatim cannot see it)" \
  "$(g diff "$mbp" pr -- A.lean | g patch-id | cut -d' ' -f1)" \
  "$(g diff "$mbw" ws -- A.lean | g patch-id | cut -d' ' -f1)"

for change in "binary byte:printf 'bin\\0arY\\377\\r\\n' >blob.bin" \
  "carriage return:printf 'b1\\r\\nb2\\n' >B.lean" \
  "mode:chmod +x tool.sh" "symlink:rm tool.sh; ln -s A.lean tool.sh" \
  "new empty file:: >empty.txt" "deleted file:rm B.lean" "file under ops/runs/sub:mkdir -p ops/runs/sub; echo x >ops/runs/sub/x.ndjson" \
  "second run-log record:rec D 1 >>ops/runs/d1.ndjson" "new run-log file:rec E 1 >ops/runs/d2.ndjson"; do
  g checkout -qB var pr
  (cd "$repo" && eval "${change#*:}")
  g add -A
  g commit -qm var
  differ "a change changes the id: ${change%%:*}" "$id_pr" "$(cid main var)"
done

g replace "$(g rev-parse pr:A.lean)" "$(g rev-parse base:B.lean)"
same "a replace ref for a head blob does not change the id" "$id_pr" "$(cid main pr)"
g replace "$(g rev-parse pr)" "$(g rev-parse ws)"
same "a replace ref for the head commit does not change the id" "$id_pr" "$(cid main pr)"
g replace -l | while read -r r; do g replace -d "$r" >/dev/null; done
g rev-parse pr >"$repo/.git/info/grafts"
if g merge-base main pr >/dev/null 2>&1; then bad "  (the graft should hide the merge-base from plain git)"; fi
same "a graft in info/grafts does not change the id" "$id_pr" "$(cid main pr)"
rm "$repo/.git/info/grafts"

g checkout -qB eol1 base
rec D 1 >>"$repo/ops/runs/d1.ndjson"
g commit -qam eol1
g checkout -qB eol2 base
rec D 1 | tr -d '\n' >>"$repo/ops/runs/d1.ndjson"
g commit -qam eol2
differ "a run-log record with and without a final newline gives two ids" "$(cid main eol1)" "$(cid main eol2)"
g checkout -qB eol3 base
rec D 1 | sed 's/$/\r/' >>"$repo/ops/runs/d1.ndjson"
g commit -qam eol3
differ "a run-log record with and without a carriage return gives two ids" "$(cid main eol1)" "$(cid main eol3)"

g checkout -qB order base
{ rec A 1; rec D 1; rec B 1; rec C 1; } >"$repo/ops/runs/d1.ndjson"
g commit -qam order1
o1=$(cid main order)
{ rec A 1; rec B 1; rec C 1; rec D 1; } >"$repo/ops/runs/d1.ndjson"
g commit -qam order2
same "added run-log lines count wherever they are" "$o1" "$(cid main order)"

g checkout -qB edit base
{ rec A 1; rec B 2; } >"$repo/ops/runs/d1.ndjson"
g commit -qam edit
refused "a run-log line edit is refused" '^content-id refused: line 2 of the merge-base version of "ops/runs/d1.ndjson" is missing at the head\. Run-log lines are append-only' main edit
g checkout -qB del base
rec B 1 >"$repo/ops/runs/d1.ndjson"
g commit -qam del
refused "a run-log line deletion is refused" 'line 1 of the merge-base version' main del
g checkout -qB delfile base
g rm -q ops/runs/d1.ndjson
g commit -qm delfile
refused "a deleted run-log file is refused" '"ops/runs/d1.ndjson" is deleted' main delfile
g checkout -qB modef base
chmod +x "$repo/ops/runs/d1.ndjson"
rec C 1 >>"$repo/ops/runs/d1.ndjson"
g commit -qam modef
refused "a run-log mode change is refused" 'changes mode from 100644 to 100755' main modef
g checkout -qB linkf base
ln -s ../../A.lean "$repo/ops/runs/d3.ndjson"
g add -A
g commit -qm linkf
refused "a run-log symlink is refused" '"ops/runs/d3.ndjson" is added with mode 120000' main linkf
g checkout -qB typef base
rm "$repo/ops/runs/d1.ndjson"
ln -s ../../A.lean "$repo/ops/runs/d1.ndjson"
g add -A
g commit -qm typef
refused "a run-log file turned into a symlink is refused" 'changes in type' main typef
g checkout -qB evil base
evil=$'ops/runs/x\n::warning::forged\xe2\x80\x8b##[warning]too.ndjson'
rec Z 1 >"$repo/$evil"
g add -A
g commit -qm evil-base
g tag evil-base
g rm -q "$evil"
g commit -qm evil
refused "a hostile run-log name prints on one line" '"ops/runs/x\\u\{000A\}::warning::forged.*##\\u\{005B\}warning\]too' evil-base evil
if grep -qF '##[' "$out" || grep -qE '^[[:space:]]*::' "$out"; then bad "  (a workflow command in the refusal)"; fi

g checkout -q main
rec M 1 >>"$repo/ops/runs/d1.ndjson"
printf 'b1\nb2\nb3\n' >"$repo/B.lean"
g commit -qam "main: record M, B.lean"
g checkout -qB rebased pr
g rebase -q main
same "a union rebase over main's run-log record keeps the id" "$id_pr" "$(cid main rebased)"
differ "  (the rule this replaces changes on it)" "$(verbatim_patch_id main pr)" "$(verbatim_patch_id main rebased)"
g checkout -q main
{ printf -- '-- header %s\n' 1 2 3 4 5 6 7 8 9 10; cat "$repo/A.lean"; } >"$repo/A2" && mv "$repo/A2" "$repo/A.lean"
g commit -qam "main: lines at the top of A.lean"
g checkout -qB moved pr
g rebase -q main
same "a rebase that moves the PR's hunk keeps the id" "$id_pr" "$(cid main moved)"
g checkout -qB newlog main
rec N 1 >"$repo/ops/runs/2026-01-01.ndjson"
g add -A
g commit -qm "pr: new run-log file"
id_newlog=$(cid main newlog)
g checkout -q main
rec O 1 >"$repo/ops/runs/2026-01-01.ndjson"
g add -A
g commit -qm "main: the same new run-log file"
g checkout -q newlog
g rebase -q main
same "a union rebase over the same new run-log file keeps the id" "$id_newlog" "$(cid main newlog)"
g checkout -q main
sed -i 's/^def v19 : Nat := 19$/def v19 : Nat := 190/' "$repo/A.lean"
g commit -qam "main: context of the PR's hunk"
g checkout -qB ctx pr
g rebase -q main
differ "a main change in the hunk's context changes the id" "$id_pr" "$(cid main ctx)"

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
same "  (git patch-id --verbatim cannot see it)" "$(verbatim_patch_id main rebased)" "$(verbatim_patch_id main other)"
g checkout -qb h1 main
awk '/^lax\(\) \{/{f=1} !(f && $0=="  run axioms")' "$repo/check.sh" >"$tmp/x" && mv "$tmp/x" "$repo/check.sh"
g commit -qam "drop axioms from lax()"
g checkout -qb h2 main
awk '/^lax\(\) \{/{f=1} !(!f && $0=="  run axioms")' "$repo/check.sh" >"$tmp/x" && mv "$tmp/x" "$repo/check.sh"
g commit -qam "drop axioms from strict()"
differ "one deletion in strict() and in lax() gives two ids (verifier's pair)" "$(cid main h1)" "$(cid main h2)"
same "  (git patch-id --verbatim cannot see it)" "$(verbatim_patch_id main h1)" "$(verbatim_patch_id main h2)"
for c in "h1 1" "h2 0"; do
  ref=$(pdiff main "${c% *}" | LC_ALL=C grep -av '^index ' |
    LC_ALL=C sed "s/^@@ .*/@@ ${c#* }/" | sha256sum | cut -d' ' -f1)
  (cd "$repo" && "$bin" content-id --verbose main "${c% *}" >/dev/null 2>"$out") || true
  same "the marker of ${c% *} is @@ ${c#* } (shell reference)" "$ref" "$(sed -n 's/^rest \([0-9a-f]*\) .*/\1/p' "$out")"
done
g checkout -q main
{ echo 'pre() {'; blk; echo '}'; echo 'strict() {'; blk; echo '}'; echo 'lax() {'; blk; echo '}'; } >"$repo/check.sh"
g commit -qam "main: pre() with the same checks, above strict()"
g checkout -qb above rebased
g rebase -q main
differ "a rebase over a copy of the hunk's lines above it changes the id" "$id_pos" "$(cid main above)"

repo="$tmp/cfg"
mkdir -p "$repo"
g init -q -b main
cp "$root/.gitattributes" "$repo/.gitattributes"
mkdir -p "$repo/ops/runs"
lean "  exact h" >"$repo/A.lean"
printf 'one\n\ntwo\n\nthree\nfour\nfive\nsix\nseven\n' >"$repo/blank.txt"
for i in $(seq 1 30); do echo "line $i of a file the PR renames"; done >"$repo/old-name.txt"
printf 'bin\0ary\377\n' >"$repo/blob.bin"
printf 'x\n' >"$repo/tool.sh"
rec A 1 >"$repo/ops/runs/d1.ndjson"
g add -A
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
plain_old=$(verbatim_patch_id main pr)
if [[ "$plain" =~ ^[0-9a-f]{64}$ ]]; then ok "config variants: the plain id"; else bad "config variants: the plain id ($plain)"; fi
cfgcase() {
  pushd "$repo" >/dev/null && eval "$2" && popd >/dev/null
  local id o
  id=$(cid main pr)
  o=$(verbatim_patch_id main pr)
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

got=0; (cd "$repo" && "$bin" content-id main >"$out" 2>&1) || got=$?
if [ "$got" = 2 ]; then ok "one argument is a usage error"; else bad "one argument is a usage error (exit $got)"; fi
refused "a name that is not a commit is refused" '"nope" is not a commit in this repository' main nope
refused "a name that starts with - is refused" '"--output=x" is not a revision' main --output=x
g checkout -q --orphan other
g commit -qm "unrelated root"
refused "commits with no merge-base are refused" 'no merge-base' main other

heads="61 6ca77036fa2d3eaf5d5e53447d3af64c2a4668c3 11282769e7f0907593165eea6ef68150b9689269
61 e197a4fcd997d9aa2b410ad93e0fd8dc76953f78 b14fa5a6ef8638b97d961ecff4e5200c8c92942f
62 1d7d159db55b5532afdcfd579664619d19b1b6df 09a65980a7c56c0c535f906ea98a634cf8be8485
62 d5828ef11311ab94cb17b704cdb97375d20d7d82 d60080fbadf74efc94a888743a60e72abc6e2536
64 dd314f46093f8fb7e3147b3a10a9dfdc154086f8 c3184fe21eef9d0dfed1f34c1f64e940ce9022db
64 c3184fe21eef9d0dfed1f34c1f64e940ce9022db d165747e5a037c5eb79c8b0c193a69653290644b
65 4c2d2d36bbf8882f5857305c937b0dcb1e187bab 89c4d2d461e00c53e0c1aafbdaa941600b360e3d
65 d183ff725ba9a5c7d465b3e38e9f2fb7a499ef09 882d62b7c9ffe14ee06756a1f18eaa395ecd8d7a
65 402874afeaad537b35da0d345cacffe3df3139d8 db3a359051b2c8b377f75e96517c78ec73bf75c3
73 f206d1f2bdf1c084aba8932ea49b1b5a4c034fff 79e5479b3332bc667d7904d62b856b034d6e0a55
78 16feff883e34988e2a9a04f79fc9f0eae7f6f00d a7f21be99478254795186249b6a37ce2328939d4
78 430c4cb01c83d44192c68fbab753897d3021b921 07d9fadbec2b16f005199000681db568691a3d21
81 5901fed8c81a3a41619bee29edc4578461dba7b3 935efda6bba23380375ba1bcc8e4980424399ed2
81 935efda6bba23380375ba1bcc8e4980424399ed2 bf1d1384b37e891085440fd546d19a6ea530edbb
82 fd137193d8eb35ef847cd314f315482e238d6ecc 5d32d52c100f554a475f6bd830fd1aaed8273958
82 fddbc83f34e99a17fc0960b9803d6e94a7672c5d d358c86e0eda9316aa1798c0114b72431940f5a7
83 b9771fdcd31e0df4763bc6ec83f8770062e9a80c d944a75a7d53c20ccf5b1baf3625af12dfa9b189
84 e7d9347beb1cc18213e09dd708930debedadd634 00e437d9c8a684c7213e7f157c563fde429f93c7
86 b7dde79703a85426661ce1563cc43f033e794bd0 20341e2b2eca7e6bbe33a28358aae86172317b77"
total=$(echo "$heads" | wc -l)
repo="$root"
if git -C "$root" rev-parse -q --verify origin/main >/dev/null &&
  echo "$heads" | awk '{print $2; print $3}' | git -C "$root" cat-file --batch-check | grep -v ' commit ' >/dev/null; then
  echo "skip replay: the replayed heads are not in this clone"
elif git -C "$root" rev-parse -q --verify origin/main >/dev/null; then
  kept_old=0; kept_new=0; changed=""
  while read -r pr before after; do
    o1=$(verbatim_patch_id origin/main "$before"); o2=$(verbatim_patch_id origin/main "$after")
    n1=$(cid origin/main "$before"); n2=$(cid origin/main "$after")
    [ -n "$n1" ] && [ -n "$n2" ] || { bad "replay: content id at #$pr ${after:0:7}"; continue; }
    [ "$o1" = "$o2" ] && kept_old=$((kept_old + 1))
    if [ "$n1" = "$n2" ]; then kept_new=$((kept_new + 1)); else changed="$changed #$pr:${after:0:7}"; fi
    echo "  #$pr ${before:0:7} -> ${after:0:7}  old $([ "$o1" = "$o2" ] && echo kept || echo changed)  new $([ "$n1" = "$n2" ] && echo kept || echo changed)"
  done <<<"$heads"
  echo "  replay: old rule kept $kept_old of $total, content id kept $kept_new of $total; changed:$changed"
  if [ "$kept_old" = 0 ] && [ "$kept_new" = 17 ] && [ "$changed" = " #62:09a6598 #62:d60080f" ]; then
    ok "replay: old rule keeps 0 of 19 updater rebases, the content id 17 of 19"
  else
    bad "replay: old rule keeps 0 of 19 updater rebases, the content id 17 of 19"
  fi
else
  echo "skip replay: no origin/main in this clone"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
