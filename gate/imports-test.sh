#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
eval "$(cd "$root" && lake env bash -c 'printf "export LEAN_PATH=%q\nexport PATH=%q\n" "$LEAN_PATH" "$PATH"')"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

check() {
  local name=$1 code=$2 dir=$3 pat=$4 got=0
  (cd "$dir" && "$bin" imports >"$tmp/out" 2>&1) || got=$?
  if [ "$got" != "$code" ]; then
    echo "FAIL $name: exit $got, expected $code"
    sed 's/^/  | /' "$tmp/out"
    fail=$((fail + 1))
    return
  fi
  if ! grep -F -q "$pat" "$tmp/out"; then
    echo "FAIL $name: output does not contain: $pat"
    sed 's/^/  | /' "$tmp/out"
    fail=$((fail + 1))
    return
  fi
  local last
  last=$(grep -v '^$' "$tmp/out" | tail -n 1)
  case "$last" in
    *"import violation(s) in core/ and gate/MitosGate/Base/") ;;
    *)
      echo "FAIL $name: last line does not name both scopes: $last"
      sed 's/^/  | /' "$tmp/out"
      fail=$((fail + 1))
      return
      ;;
  esac
  if grep -F -q 'uncaught exception' "$tmp/out"; then
    echo "FAIL $name: uncaught exception"
    sed 's/^/  | /' "$tmp/out"
    fail=$((fail + 1))
    return
  fi
  echo "ok   $name"
  pass=$((pass + 1))
}

summary='import violation(s) in core/ and gate/MitosGate/Base/'

mkdir -p "$tmp/bad/gate/MitosGate/Base"
printf 'import MitosGate.Land\n' >"$tmp/bad/gate/MitosGate/Base/Bad.lean"
check "a Base file importing MitosGate.Land fails and names the file and line" \
  1 "$tmp/bad" "gate/MitosGate/Base/Bad.lean:1:"

mkdir -p "$tmp/good/gate/MitosGate/Base"
printf 'import Std\nimport Lean.Data.Json\n' >"$tmp/good/gate/MitosGate/Base/Good.lean"
check "a Base file importing Std and Lean.Data.Json passes" \
  0 "$tmp/good" "0 $summary"

mkdir -p "$tmp/none"
check "a missing Base directory passes" \
  0 "$tmp/none" "0 $summary"

mkdir -p "$tmp/text/gate/MitosGate/Base"
printf 'import MitosGate.Base.Text\n' >"$tmp/text/gate/MitosGate/Base/Text.lean"
check "MitosGate.Base.Text is allowed by name components" \
  0 "$tmp/text" "0 $summary"

mkdir -p "$tmp/util/gate/MitosGate/Base"
printf 'import MitosGate.Util\n' >"$tmp/util/gate/MitosGate/Base/Util.lean"
check "MitosGate.Util is not allowed under Base" \
  1 "$tmp/util" "gate/MitosGate/Base/Util.lean:1:"

mkdir -p "$tmp/baseline/gate/MitosGate/Base"
printf 'import MitosGate.Baseline\n' >"$tmp/baseline/gate/MitosGate/Base/Baseline.lean"
check "MitosGate.Baseline is not a component prefix of MitosGate.Base" \
  1 "$tmp/baseline" "gate/MitosGate/Base/Baseline.lean:1:"

mkdir -p "$tmp/core/core/Mitos"
printf 'import Lean\n' >"$tmp/core/core/Mitos/LeanImport.lean"
check "a core violation is still reported when Base is absent" \
  1 "$tmp/core" "core/Mitos/LeanImport.lean:1:"

check "the repository reports no import violation" \
  0 "$root" "0 $summary"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
