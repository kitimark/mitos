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
  local name=$1 code=$2 dir=$3 pat=$4 expected_count=${5:-} got=0
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
    *"$summary") ;;
    *)
      echo "FAIL $name: last line does not name every scope: $last"
      sed 's/^/  | /' "$tmp/out"
      fail=$((fail + 1))
      return
      ;;
  esac
  if [ -n "$expected_count" ] && [ "$last" != "$expected_count $summary" ]; then
    echo "FAIL $name: last line does not report exactly $expected_count violation(s): $last"
    fail=$((fail + 1))
    return
  fi
  if grep -F -q 'uncaught exception' "$tmp/out"; then
    echo "FAIL $name: uncaught exception"
    sed 's/^/  | /' "$tmp/out"
    fail=$((fail + 1))
    return
  fi
  echo "ok   $name"
  pass=$((pass + 1))
}

summary='import violation(s) in core/ and gate/'

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

mkdir -p "$tmp/root/gate/MitosGate"
printf 'import MitosGate.Util\n' >"$tmp/root/gate/MitosGate/Base.lean"
check "a forbidden Base root import fails without a Base directory" \
  1 "$tmp/root" "gate/MitosGate/Base.lean:1:"

mkdir -p "$tmp/root/gate/MitosGate/Base"
printf 'import MitosGate.Base\n' >"$tmp/root/gate/MitosGate/Base/Leaf.lean"
check "a child cannot import an unchecked Base root" \
  1 "$tmp/root" "gate/MitosGate/Base.lean:1:"

printf 'import Std\n' >"$tmp/root/gate/MitosGate/Base.lean"
check "a permitted Base root and a child importing it pass" \
  0 "$tmp/root" "0 $summary"

mkdir -p "$tmp/lookalike/gate/MitosGate/Base"
for module in "MitosGate.BaseX" "MitosGate.Base'" "Lean.Data.JsonRpc" "Lean"; do
  printf 'import %s\n' "$module" >"$tmp/lookalike/gate/MitosGate/Base/Lookalike.lean"
  check "$module is not allowed under Base" \
    1 "$tmp/lookalike" "gate/MitosGate/Base/Lookalike.lean:1:"
done

mkdir -p "$tmp/core/core/Mitos"
printf 'import Lean\n' >"$tmp/core/core/Mitos/LeanImport.lean"
check "a core violation is still reported when Base is absent" \
  1 "$tmp/core" "core/Mitos/LeanImport.lean:1:"

mkdir -p "$tmp/lake/core/.lake/packages/dep"
printf 'import Lean\n' >"$tmp/lake/core/.lake/packages/dep/Dep.lean"
check "a file under core/.lake is not checked" \
  0 "$tmp/lake" "0 $summary"

mkdir -p "$tmp/nested-lake/core/Mitos/Impl/.lake"
printf 'import Lean\n' >"$tmp/nested-lake/core/Mitos/Impl/.lake/Bad.lean"
check "a nested .lake under core/Mitos is still checked" \
  1 "$tmp/nested-lake" "core/Mitos/Impl/.lake/Bad.lean:1:"

mkdir -p "$tmp/lake/core/Mitos"
printf 'import Lean\n' >"$tmp/lake/core/Mitos/Bad.lean"
check "a core violation is reported next to a skipped core/.lake" \
  1 "$tmp/lake" "core/Mitos/Bad.lean:1:" 1

mkdir -p "$tmp/vendor/gate/vendor/l4yaml"
printf 'import MitosGate.Util\n' >"$tmp/vendor/gate/vendor/l4yaml/Bad.lean"
check "a vendored gate import fails and names the file" \
  1 "$tmp/vendor" "gate/vendor/l4yaml/Bad.lean:1:"

for module in Init Std Lean L4YAML L4YAML.Parser; do
  printf 'module\npublic import %s\nmeta import %s\n' "$module" "$module" \
    >"$tmp/vendor/gate/vendor/l4yaml/Bad.lean"
  check "vendored public and meta imports of $module pass" \
    0 "$tmp/vendor" "0 $summary"
done

for module in L4YAMLExtra 'L4YAML.«..».MitosGate.Util'; do
  printf 'import %s\n' "$module" >"$tmp/vendor/gate/vendor/l4yaml/Bad.lean"
  check "a vendored import of $module fails" \
    1 "$tmp/vendor" "gate/vendor/l4yaml/Bad.lean:1:"
done

mkdir -p "$tmp/seam/gate/MitosGate/Workflow"
for source in 'def value := L4YAML.YamlValue' '-- L4YAML' '/- L4YAML -/' 'def name := "L4YAML"'; do
  printf '%s\n' "$source" >"$tmp/seam/gate/MitosGate/Workflow/X.lean"
  check "a gate file containing $source fails" \
    1 "$tmp/seam" "gate/MitosGate/Workflow/X.lean:"
done

printf '%s\n' '-- L4YAML L4YAML' 'def name := "L4YAML"' \
  >"$tmp/seam/gate/MitosGate/Workflow/X.lean"
check "multiple vendor mentions produce one diagnostic per file" \
  1 "$tmp/seam" "1 $summary"

rm "$tmp/seam/gate/MitosGate/Workflow/X.lean"
printf 'import L4YAML\n-- L4YAML.YamlValue\n' >"$tmp/seam/gate/MitosGate/Yaml.lean"
check "the exact YAML seam may name the vendor" \
  0 "$tmp/seam" "0 $summary"

mkdir -p "$tmp/seam/gate/MitosGate/Yaml"
printf '%s\n' '-- L4YAML' >"$tmp/seam/gate/MitosGate/Yaml/Child.lean"
check "the seam exemption does not cover a directory" \
  1 "$tmp/seam" "gate/MitosGate/Yaml/Child.lean:"

mkdir -p "$tmp/exclusions/gate/vendor/other" "$tmp/exclusions/gate/vendorish"
printf '%s\n' '-- L4YAML' >"$tmp/exclusions/gate/vendor/other/Allowed.lean"
check "all vendors are outside the seam scan" \
  0 "$tmp/exclusions" "0 $summary"
printf '%s\n' '-- L4YAML' >"$tmp/exclusions/gate/vendorish/Bad.lean"
check "a vendor prefix lookalike is inside the seam scan" \
  1 "$tmp/exclusions" "gate/vendorish/Bad.lean:"

mkdir -p "$tmp/gate-root/gate"
printf '%s\n' '-- L4YAML' >"$tmp/gate-root/gate/Main.lean"
check "the seam scan includes files directly under gate" \
  1 "$tmp/gate-root" "gate/Main.lean:"
rm "$tmp/gate-root/gate/Main.lean"
printf '%s\n' '-- L4YAML' >"$tmp/gate-root/gate/README.md"
check "the seam scan reads only Lean files" \
  0 "$tmp/gate-root" "0 $summary"

for scope in Mitos/Proofs Mitos/Impl Mitos/Core Challenge Mitos Mitos/ProofsX; do
  mkdir -p "$tmp/mathlib/core/$scope"
  printf 'import Mathlib.Data.List.Nodup\n' >"$tmp/mathlib/core/$scope/A.lean"
  code=1
  [ "$scope" = Mitos/Proofs ] && code=0
  if [ "$code" = 0 ]; then
    check "Mathlib import policy in core/$scope" 0 "$tmp/mathlib" "0 $summary" 0
  else
    check "Mathlib import policy in core/$scope" 1 "$tmp/mathlib" "core/$scope/A.lean:1:" 1
  fi
  rm "$tmp/mathlib/core/$scope/A.lean"
done

mkdir -p "$tmp/proofs/core/Mitos/Proofs"
for module in Lean Batteries.Data.List.Perm MathlibX.Foo; do
  printf 'import %s\n' "$module" >"$tmp/proofs/core/Mitos/Proofs/A.lean"
  check "$module is forbidden in Proofs" \
    1 "$tmp/proofs" "core/Mitos/Proofs/A.lean:1:" 1
done
printf 'import Mitos.Proofs.Foo\n' >"$tmp/proofs/core/Mitos/Proofs/A.lean"
check "Proofs files may import other proofs" 0 "$tmp/proofs" "0 $summary" 0

for scope in Mitos/Impl Challenge Mitos/Core Mitos; do
  mkdir -p "$tmp/nonproofs/core/$scope"
  printf 'import Mitos.Proofs.Foo\n' >"$tmp/nonproofs/core/$scope/A.lean"
  check "core/$scope cannot import Proofs" \
    1 "$tmp/nonproofs" "core/$scope/A.lean:1:" 1
  rm "$tmp/nonproofs/core/$scope/A.lean"
done

mkdir -p "$tmp/graph/core/Mitos/Core"
printf 'import Mathlib.Data.List.Nodup\n' >"$tmp/graph/core/Mitos/Core/Graph.lean"
check "a resolver-spec Mathlib import fails when the surface closure is unknown" \
  1 "$tmp/graph" "core/Mitos/Core/Graph.lean:1:" 1

printf 'import Init\n' >"$tmp/graph/core/Mitos/Core.lean"
check "Graph may import Mathlib when the surface closure does not reach it" \
  0 "$tmp/graph" "0 $summary" 0

mkdir -p "$tmp/fact/core/Mitos/Core"
printf 'import Mitos.Core.Fact\n' >"$tmp/fact/core/Mitos/Core.lean"
printf 'import Mathlib.Data.List.Nodup\n' >"$tmp/fact/core/Mitos/Core/Fact.lean"
check "Fact may not import Mathlib: it is in the surface closure" \
  1 "$tmp/fact" "core/Mitos/Core/Fact.lean:1:" 1

mkdir -p "$tmp/reach/core/Mitos/Core"
printf 'import Mitos.Core.Fact\n' >"$tmp/reach/core/Mitos/Core.lean"
printf 'import Mitos.Core.Graph\n' >"$tmp/reach/core/Mitos/Core/Fact.lean"
printf 'import Mathlib.Data.List.Nodup\n' >"$tmp/reach/core/Mitos/Core/Graph.lean"
check "the surface closure cannot reach Mathlib through a spec file" \
  1 "$tmp/reach" "core/Mitos/Core/Graph.lean:1:" 1

for module in Batteries.Data.List.Perm Lean; do
  printf 'import %s\n' "$module" >"$tmp/graph/core/Mitos/Core/Graph.lean"
  check "Graph may not import $module" \
    1 "$tmp/graph" "core/Mitos/Core/Graph.lean:1:" 1
done

for file in MitosGate/Foo.lean Foo.lean; do
  mkdir -p "$tmp/gate-imports/gate/$(dirname "$file")"
  for module in Mathlib.Data.List.Nodup Batteries.Data.List.Perm; do
    printf 'import %s\n' "$module" >"$tmp/gate-imports/gate/$file"
    check "$file cannot import $module" \
      1 "$tmp/gate-imports" "gate/$file:1:" 1
  done
  printf 'import Lean.Elab.Command\n' >"$tmp/gate-imports/gate/$file"
  check "$file may import Lean.Elab.Command" 0 "$tmp/gate-imports" "0 $summary" 0
  rm "$tmp/gate-imports/gate/$file"
done

mkdir -p "$tmp/lake-prefix/core/.lakex"
printf 'import Lean\n' >"$tmp/lake-prefix/core/.lakex/Bad.lean"
check "a core/.lake prefix lookalike is still checked" \
  1 "$tmp/lake-prefix" "core/.lakex/Bad.lean:1:" 1

check "the repository reports no import violation" \
  0 "$root" "0 $summary"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
