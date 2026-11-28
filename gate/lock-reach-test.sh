#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
eval "$(cd "$root" && lake env bash -c 'printf "export LEAN_PATH=%q\nexport PATH=%q\n" "$LEAN_PATH" "$PATH"')"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
out="$tmp/out"

pass=0
fail=0
ok() { echo "ok   $1"; pass=$((pass + 1)); }
bad() { echo "FAIL $1"; sed 's/^/  | /' "$out"; fail=$((fail + 1)); }

tree() {
  mkdir -p "$tmp/$1/core/Mitos"
  cp "$root/statements.lock" "$tmp/$1/statements.lock"
  cp "$root/lake-manifest.json" "$tmp/$1/lake-manifest.json"
  cp "$root/core/lake-manifest.json" "$tmp/$1/core/lake-manifest.json"
  cp "$root/core/Mitos/Core.lean" "$tmp/$1/core/Mitos/Core.lean"
  cp -R "$root/core/Mitos/Core" "$tmp/$1/core/Mitos/Core"
  mkdir -p "$tmp/$1/core/.lake" && ln -s "$root/core/.lake/packages" "$tmp/$1/core/.lake/packages"
}

expect() {
  local name=$1 dir=$2 code=$3 want=$4 forbid=$5 got=0
  shift 5
  (cd "$tmp/$dir" && "$bin" "$@" >"$out" 2>&1) || got=$?
  if [ "$got" != "$code" ]; then echo "  exit $got, expected $code"; bad "$name"; return; fi
  if ! grep -qE -- "$want" "$out"; then echo "  no line matches /$want/"; bad "$name"; return; fi
  if [ -n "$forbid" ] && grep -qE -- "$forbid" "$out"; then echo "  a line matches /$forbid/"; bad "$name"; return; fi
  if grep -q 'uncaught exception' "$out"; then bad "$name"; return; fi
  ok "$name"
}

reached='every spec module is reached from Mitos.Core.Spec'
missed='not reached from Mitos.Core.Spec'

tree main
expect "lock --check passes on a copy of the tree" main 0 "$reached" "$missed" lock --check

tree top
printf 'namespace Mitos\n\ndef unreachedSpec : Nat := 1\n\nend Mitos\n' >"$tmp/top/core/Mitos/Core/Unreached.lean"
expect "lock --check fails on an unreached module" top 1 \
  '^core/Mitos/Core/Unreached\.lean: Mitos\.Core\.Spec does not import Mitos\.Core\.Unreached' "$reached" lock --check
expect "the lock lines alone still match, so the reach check is what fails" top 1 \
  'statements\.lock up to date' 'statements\.lock is out of date' lock --check
expect "lock --check names how many modules it missed" top 1 \
  '^1 spec module is not reached from Mitos\.Core\.Spec' '' lock --check

tree nested
printf 'def nestedSpec : Nat := 1\n' >"$tmp/nested/core/Mitos/Core/Spec/Nested.lean"
printf 'def otherSpec : Nat := 1\n' >"$tmp/nested/core/Mitos/Core/Other.lean"
expect "lock --check fails on unreached modules in a subfolder and at the top" nested 1 \
  '^2 spec modules are not reached from Mitos\.Core\.Spec' "$reached" lock --check
expect "the nested module is named" nested 1 \
  '^core/Mitos/Core/Spec/Nested\.lean: Mitos\.Core\.Spec does not import Mitos\.Core\.Spec\.Nested' '' lock --check

tree dotted
printf 'def dottedSpec : Nat := 1\n' >"$tmp/dotted/core/Mitos/Core/A.B.lean"
expect "lock --check fails on a module whose file name holds a dot" dotted 1 \
  '^core/Mitos/Core/A\.B\.lean: Mitos\.Core\.Spec does not import' "$reached" lock --check

tree write
printf 'def writtenSpec : Nat := 1\n' >"$tmp/write/core/Mitos/Core/Written.lean"
expect "lock fails on an unreached module when it writes the file too" write 1 \
  '^core/Mitos/Core/Written\.lean: Mitos\.Core\.Spec does not import' "$reached" lock
if cmp -s "$root/statements.lock" "$tmp/write/statements.lock"; then
  ok "lock writes the same statements.lock, so the unreached module has no line"
else
  echo "  the written statements.lock differs"; : >"$out"; bad "lock writes the same statements.lock"
fi

mkdir -p "$tmp/nocore/core"
cp "$root/statements.lock" "$tmp/nocore/statements.lock"
cp "$root/lake-manifest.json" "$tmp/nocore/lake-manifest.json"
cp "$root/core/lake-manifest.json" "$tmp/nocore/core/lake-manifest.json"
mkdir -p "$tmp/nocore/core/.lake" && ln -s "$root/core/.lake/packages" "$tmp/nocore/core/.lake/packages"
expect "lock --check fails where core/Mitos/Core is not a folder" nocore 1 \
  'core/Mitos/Core is not a folder here' "$reached" lock --check

globs='globs = ["Mitos.Core", "Mitos.Core.+"]'
if grep -A1 '^name = "MitosCore"$' "$root/core/lakefile.toml" | grep -qxF -- "$globs"; then
  ok "core/lakefile.toml builds Mitos.Core and Mitos.Core.+, the modules the reach check lists"
else
  cp "$root/core/lakefile.toml" "$out"; bad "core/lakefile.toml builds Mitos.Core and Mitos.Core.+"
fi

toy="$tmp/toy"
mkdir -p "$toy/core/Mitos/Core"
cp "$root/lean-toolchain" "$toy/lean-toolchain"
cp "$root/lean-toolchain" "$toy/core/lean-toolchain"
printf 'name = "toy-root"\n\n[[require]]\nname = "toy-core"\npath = "core"\n' >"$toy/lakefile.toml"
printf 'name = "toy-core"\ndefaultTargets = ["ToyCore"]\n\n[[lean_lib]]\nname = "ToyCore"\n%s\n' "$globs" \
  >"$toy/core/lakefile.toml"
printf 'namespace Mitos\n\ndef rootOnly : Nat := 1\n\nend Mitos\n' >"$toy/core/Mitos/Core.lean"

toy_build() {
  printf '%snamespace Mitos\n\ndef specOnly : Nat := 2\n\nend Mitos\n' "$1" >"$toy/core/Mitos/Core/Spec.lean"
  (cd "$toy/core" && lake update && lake build && cd "$toy" && lake update) >"$out" 2>&1
}

unset LEAN_PATH
if toy_build '' && [ -f "$toy/core/.lake/build/lib/lean/Mitos/Core.olean" ]; then
  ok "Lake builds core/Mitos/Core.lean in a toy core whose Spec does not import it"
  eval "$(cd "$toy" && lake env bash -c 'printf "export LEAN_PATH=%q\n" "$LEAN_PATH"')"
  expect "lock fails when Mitos.Core.Spec does not import core/Mitos/Core.lean" toy 1 \
    '^core/Mitos/Core\.lean: Mitos\.Core\.Spec does not import Mitos\.Core,' "$reached" lock
  cp "$toy/statements.lock" "$out"
  if grep -q '^def Mitos\.specOnly ' "$out" && ! grep -q 'Mitos\.rootOnly' "$out"; then
    ok "the lock it wrote has a line for Spec's declaration and none for the root file's"
  else
    bad "the lock it wrote has a line for Spec's declaration and none for the root file's"
  fi
  if toy_build $'import Mitos.Core\n'; then
    expect "lock passes on the same toy core once Spec imports the root file" toy 0 "$reached" "$missed" lock
    cp "$toy/statements.lock" "$out"
    if grep -q '^def Mitos\.rootOnly ' "$out"; then
      ok "the root file's declaration then has a line"
    else
      bad "the root file's declaration then has a line"
    fi
  else
    bad "the toy core builds once Spec imports the root file"
  fi
else
  bad "Lake builds core/Mitos/Core.lean in a toy core whose Spec does not import it"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
