#!/usr/bin/env bash
# The first two lines of statements.lock match MitosGate.Lock.header.
# A copy with either line edited, or with the header removed, fails.
# Run from anywhere: gate/lock-header-test.sh
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

expect() { # name, exit code, directory
  local name=$1 code=$2 dir=$3 got=0
  (cd "$dir" && "$bin" lock --check-header >"$tmp/out" 2>&1) || got=$?
  if [ "$got" != "$code" ]; then
    echo "FAIL $name: exit $got, expected $code"
    sed 's/^/  | /' "$tmp/out"
    fail=$((fail + 1))
    return
  fi
  if [ "$code" = 0 ]; then
    local pat='header matches MitosGate.Lock.header'
  else
    local pat='header does not match MitosGate.Lock.header'
  fi
  if ! grep -q "$pat" "$tmp/out"; then
    echo "FAIL $name: output does not match /$pat/"
    sed 's/^/  | /' "$tmp/out"
    fail=$((fail + 1))
    return
  fi
  echo "ok   $name"
  pass=$((pass + 1))
}

mkdir -p "$tmp/good" "$tmp/line1" "$tmp/line2" "$tmp/drop" "$tmp/empty"
cp "$root/statements.lock" "$tmp/good/statements.lock"
cp "$root/statements.lock" "$tmp/line1/statements.lock"
cp "$root/statements.lock" "$tmp/line2/statements.lock"
sed -i '1s/.*/# edited by hand/' "$tmp/line1/statements.lock"
sed -i '2s/.*/# edited by hand/' "$tmp/line2/statements.lock"
tail -n +3 "$root/statements.lock" >"$tmp/drop/statements.lock"
: >"$tmp/empty/statements.lock"

expect "the repository header matches" 0 "$root"
expect "a copy of the header matches" 0 "$tmp/good"
expect "a changed first line fails" 1 "$tmp/line1"
expect "a changed second line fails" 1 "$tmp/line2"
expect "a file with the header removed fails" 1 "$tmp/drop"
expect "an empty file fails" 1 "$tmp/empty"

got=0
(cd "$tmp/line1" && "$bin" lock --check >"$tmp/out" 2>&1) || got=$?
if [ "$got" = 1 ] && grep -q 'header does not match MitosGate.Lock.header' "$tmp/out"; then
  echo "ok   lock --check fails when the first line changed"
  pass=$((pass + 1))
else
  echo "FAIL lock --check on a changed first line: exit $got"
  sed 's/^/  | /' "$tmp/out"
  fail=$((fail + 1))
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
