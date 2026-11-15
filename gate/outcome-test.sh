#!/usr/bin/env bash
# Every kernel the toolchain's `lake comparator` can run is in `Outcome.kernels`, so its rejection
# reads as a kernel rejection and not as no judgment. The kernels are the ones Lake bundles for
# `--paranoid` and Lean's own, which `runBuiltinKernel` always runs.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null) || { echo "FAIL lake build mitos-gate"; exit 1; }
check="$(cd "$root" && lean --print-prefix)/src/lean/lake/Lake/CLI/Check.lean"
[ -f "$check" ] || { echo "FAIL the toolchain has no Lake source at $check"; exit 1; }

lake_kernels=$({
  sed -n '/^def bundledKernels/,/^$/p' "$check" | grep -oE '^ *\("[^"]+", #\[' | sed -E 's/^ *\("([^"]+)".*/\1/'
  grep -oE 'runExternalKernel "[^"]+"' "$check" | sed -E 's/.*"([^"]+)"/\1/'
} | sort -u)
gate_kernels=$(cd "$root" && printf '%s\n' 'import MitosGate.Outcome' \
  '#eval MitosGate.Accept.Outcome.kernels.forM IO.println' | lake env lean --stdin | sort -u)

pass=0
fail=0
check_that() {
  if eval "$2"; then pass=$((pass + 1)); else echo "FAIL $1"; fail=$((fail + 1)); fi
}

check_that "Lake's source names Lean's own kernel" 'grep -qx "Lean default" <<<"$lake_kernels"'
check_that "Lake's source names at least one bundled kernel" '[ "$(wc -l <<<"$lake_kernels")" -ge 2 ]'
check_that "Outcome.kernels is readable" '[ -n "$gate_kernels" ]'
missing=$(comm -23 <(printf '%s\n' "$lake_kernels") <(printf '%s\n' "$gate_kernels"))
check_that "every kernel Lake can run is in Outcome.kernels (missing: ${missing:-none})" \
  '[ -z "$missing" ]'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
