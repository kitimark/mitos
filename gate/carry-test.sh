#!/usr/bin/env bash
# Tests for `mitos-gate carry` (gate/MitosGate/Carry.lean) on a scratch repository, with push lists
# written as the REST activity route prints them (newest first; time, type, actor, before, after,
# tab-separated): #83's round-2 laundering, an updater-only chain, and each way a chain breaks.
# Run from anywhere: gate/carry-test.sh
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
cid() { (cd "$repo" && "$bin" content-id "$@" 2>/dev/null) || true; }
bot="mitos-pr-updater[bot]"
# push <type> <actor> <before> <after>: one line of the route's TSV.
push() { printf '2026-11-09T10:00:00Z\t%s\t%s\t%s\t%s\n' "$1" "$2" "$(g rev-parse "$3")" "$(g rev-parse "$4")"; }
# expect <name> <exit code> <grep -E pattern> <base> <verified> <head>, with the pushes on stdin.
expect() {
  local name=$1 code=$2 pat=$3 got=0
  shift 3
  (cd "$repo" && "$bin" carry "$@" >"$out" 2>&1) || got=$?
  if [ "$got" != "$code" ]; then echo "  exit $got, expected $code"; bad "$name"; return; fi
  if [ "$(grep -c '' "$out")" != 1 ] || ! grep -qE -- "$pat" "$out"; then bad "$name"; return; fi
  ok "$name"
}

mkdir -p "$repo"
g init -q -b main
blk() { printf '  run lint\n  run build\n  run proofs\n  run axioms\n  run cheats\n  run lock\n'; }
{ echo 'strict() {'; blk; echo '}'; echo 'lax() {'; blk; echo '}'; } >"$repo/check.sh"
echo x >"$repo/other.txt"
g add -A
g commit -qm M1
g tag M1

# V, the verified head: drops axioms from lax().
g checkout -qb pr
awk '/^lax\(\) \{/{f=1} !(f && $0=="  run axioms")' "$repo/check.sh" >"$tmp/x" && mv "$tmp/x" "$repo/check.sh"
g commit -qam V
g tag V
# V2, an owner's push on V: axioms back in lax(), dropped from strict() instead.
{ echo 'strict() {'; blk | grep -v axioms; echo '}'; echo 'lax() {'; blk; echo '}'; } >"$repo/check.sh"
g commit -qam V2
g tag V2
# main adds pre(), with the same steps, above strict(); then the updater rebases V2 to X.
g checkout -q main
{ echo 'pre() {'; blk; echo '}'; echo 'strict() {'; blk; echo '}'; echo 'lax() {'; blk; echo '}'; } >"$repo/check.sh"
g commit -qam M2
g checkout -qb x V2
g rebase -q main
g tag X
g checkout -qb h V
g rebase -q main
g tag H

if [ "$(cid main V)" = "$(cid main X)" ] && [ -n "$(cid main X)" ]; then
  ok "the laundered head X has the verified head's content id (#83 round 2)"
else
  bad "the laundered head X has the verified head's content id (#83 round 2)"
fi
{ push force_push "$bot" V2 X; push push kitimark V V2; } >"$tmp/launder"
expect "an owner's push before the updater's rebase stops the carry" 1 \
  '^no carry: the push of .* is a "push" by "kitimark", not a force_push by mitos-pr-updater\[bot\]$' \
  main V X <"$tmp/launder"
expect "so does an owner's force-push" 1 '"force_push" by "kitimark"' main V X \
  < <({ push force_push "$bot" V2 X; push force_push kitimark V V2; })
expect "the updater's rebase of V over pre() changes the content id" 1 \
  '^no carry: the content id changed: [0-9a-f]{64} at the verified head [0-9a-f]{40}, [0-9a-f]{64} at the head' \
  main V H \
  < <(push force_push "$bot" V H)

# An updater-only chain on another main: a file the PR does not touch, then an edit elsewhere.
g checkout -qb main2 M1
echo notes >"$repo/notes.txt"
g add -A
g commit -qm N1
g tag N1
echo y >"$repo/other.txt"
g commit -qam N2
g checkout -qb y V
g rebase -q N1
g tag Y1
g rebase -q main2
g tag Y2
{ push force_push "$bot" Y1 Y2; push force_push "$bot" V Y1; push push kitimark M1 V; } >"$tmp/chain"
id_v=$(cid main2 V)
expect "two updater rebases from the verified head carry it" 0 \
  "^carry: 2 updater rebase\(s\) from $(g rev-parse V) to $(g rev-parse Y2), content id $id_v\$" \
  main2 V Y2 <"$tmp/chain"
expect "so does the later one alone" 0 '^carry: 1 updater rebase\(s\)' main2 Y1 Y2 <"$tmp/chain"
expect "the head itself carries with no rebase" 0 '^carry: 0 updater rebase\(s\)' main2 Y2 Y2 <"$tmp/chain"
expect "names and short ids resolve" 0 '^carry: 2 ' main2 "$(g rev-parse --short V)" y <"$tmp/chain"
expect "the head must be where the last push left the branch" 1 \
  "^no carry: the branch's last push left it at $(g rev-parse Y2), not at the head $(g rev-parse Y1)\$" \
  main2 V Y1 <"$tmp/chain"
expect "so must the verified head, when it is the head" 1 \
  "^no carry: the branch's last push left it at $(g rev-parse Y2), not at the head $(g rev-parse Y1)\$" \
  main2 Y1 Y1 <"$tmp/chain"
expect "oldest first is refused" 1 "the branch's last push left it at" main2 V Y2 \
  < <(tac "$tmp/chain")
expect "a gap between two pushes stops the carry" 1 \
  "^no carry: the push of .* left the branch at $(g rev-parse N1), but the next push started from $(g rev-parse Y1)\$" \
  main2 V Y2 \
  < <({ push force_push "$bot" Y1 Y2; push force_push "$bot" V N1; })
expect "a list that ends before the verified head stops it" 1 \
  "^no carry: the pushes listed end before the branch was at the verified head $(g rev-parse V)\$" \
  main2 V Y2 \
  < <(push force_push "$bot" Y1 Y2)
expect "a plain push by the updater's login is not a rebase" 1 \
  '"push" by "mitos-pr-updater\[bot\]"' main2 V Y2 \
  < <(push push "$bot" V Y2)
expect "another login is not the updater" 1 \
  '"force_push" by "mitos-pr-updater", not' main2 V Y2 \
  < <(push force_push "mitos-pr-updater" V Y2)
expect "a branch made again is not a rebase" 1 '"branch_creation" by "kitimark"' main2 V Y2 \
  < <({ push branch_creation kitimark M1 Y2; push branch_deletion kitimark V M1; })
expect "no push listed stops it" 1 '^no carry: the activity route listed no push to the branch$' \
  main2 V Y2 </dev/null
expect "a line with three fields is refused" 1 \
  '^no carry: a line is not a push .*"a\\u\{0009\}b\\u\{0009\}c"$' main2 V Y2 \
  < <(printf 'a\tb\tc\n')
expect "a hostile login prints on one line with no workflow command" 1 \
  '^no carry: .* by "::warning::x ##\\u\{005B\}error\]y", not' main2 V Y2 \
  < <(printf '%s\t%s\t%s\t%s\t%s\n' t force_push '::warning::x ##[error]y' "$(g rev-parse V)" "$(g rev-parse Y2)")

expect "a verified head that is not in the clone stops it" 1 \
  '^no carry: "0123456789012345678901234567890123456789" is not a commit' \
  main2 0123456789012345678901234567890123456789 Y2 \
  < <(push force_push "$bot" V Y2)

got=0; (cd "$repo" && "$bin" carry main2 V </dev/null >"$out" 2>&1) || got=$?
if [ "$got" = 2 ]; then ok "two arguments are a usage error"; else bad "two arguments are a usage error (exit $got)"; fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
