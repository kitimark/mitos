#!/usr/bin/env bash
# Mutation testing: every mutant of the reference resolver must be REFUTED by the theorems it
# names. A mutant is a directory holding
#
#   Resolve.lean or Impact.lean   replaces core/Mitos/Impl/<same name>, with one plausible bug
#   Refute.lean                   proves `Mitos.Refute.<theorem> : ¬ <statement>` for the mutant
#   expect                        breaks=<Challenge theorem names>   why=<the bug, one line>
#
# A failing proof build is not enough: a correct refactor breaks proofs too. So a mutant is
# CAUGHT only when `lake comparator` accepts its refutations against a Challenge generated from
# core/Challenge/Resolver.lean with each named theorem negated. The statements are therefore the
# owner-approved ones, `sorry` and extra axioms are rejected, and a mutant that still meets a
# theorem cannot be caught, because the negation cannot be proved.
#
# usage: eval/mutants/run.sh [mutant...]      (run from anywhere)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE="$ROOT/core"
(cd "$CORE" && lake build -q >/dev/null) || { echo "core build failed"; exit 2; }
mutants=("$@")
[ ${#mutants[@]} -eq 0 ] && mutants=($(ls -d "$ROOT"/eval/mutants/*/ | xargs -n1 basename))
log="$ROOT/.lake/mutants"; mkdir -p "$log"

judge() {  # prints CAUGHT, SURVIVED, BROKEN (the mutant does not build) or INVALID
  local d="$1" out="$2" breaks w f b t
  breaks=$(grep '^breaks=' "$d/expect" 2>/dev/null | cut -d= -f2)
  [ -n "$breaks" ] && [ -f "$d/Refute.lean" ] || { echo "needs Refute.lean and expect with breaks=" >"$out"; echo INVALID; return; }
  w=$(mktemp -d); cp -r "$CORE/." "$w/"; cp "$ROOT/lean-toolchain" "$w/"
  for f in "$d"/*; do
    b=$(basename "$f")
    case "$b" in
      expect) ;;
      Refute.lean) cp "$f" "$w/Mitos/Proofs/Refute.lean" ;;
      *) [ -f "$CORE/Mitos/Impl/$b" ] || { echo "unexpected file $b" >"$out"; echo INVALID; rm -rf "$w"; return; }
         cp "$f" "$w/Mitos/Impl/$b" ;;
    esac
  done
  if ! (cd "$w" && lake build Mitos.Impl.Resolve Mitos.Impl.Impact) >"$out" 2>&1; then
    echo BROKEN; rm -rf "$w"; return
  fi
  { sed -n -e '/^import /p' -e '/^def /p' "$CORE/Challenge/Resolver.lean"
    for t in $breaks; do
      sed -n "s/^theorem Mitos\.Proofs\.$t : \(.*\) := sorry\$/theorem Mitos.Refute.$t : ¬ (\1) := sorry/p" \
        "$CORE/Challenge/Resolver.lean"
    done; } >"$w/Challenge/Mutant.lean"
  if [ "$(grep -c '^theorem ' "$w/Challenge/Mutant.lean")" -ne "$(wc -w <<<"$breaks")" ]; then
    echo "breaks= names a theorem that is not in core/Challenge/Resolver.lean" >>"$out"; echo INVALID; rm -rf "$w"; return
  fi
  jq --arg t "$breaks" '.challenge_module = "Challenge.Mutant" | .solution_module = "Mitos.Proofs.Refute"
    | .theorem_names = ($t | split(" ") | map("Mitos.Refute." + .))' "$CORE/comparator.json" >"$w/mutant.json"
  if (cd "$w" && lake comparator --config=mutant.json) >>"$out" 2>&1; then echo CAUGHT; else echo SURVIVED; fi
  rm -rf "$w"
}

fail=0
printf '%-28s %-9s %s\n' MUTANT RESULT BREAKS
for m in "${mutants[@]}"; do
  d="$ROOT/eval/mutants/$m"
  r=$(judge "$d" "$log/$m.log")
  mark=""; [ "$r" = CAUGHT ] || { mark="  <-- FAIL"; fail=1; }
  printf '%-28s %-9s %s%s\n' "$m" "$r" "$(grep '^breaks=' "$d/expect" 2>/dev/null | cut -d= -f2)" "$mark"
done
echo
if [ $fail -eq 0 ]; then echo "mutants: all ${#mutants[@]} refuted (${SECONDS}s)"; else echo "mutants: FAILURES (logs in .lake/mutants/)"; fi
exit $fail
