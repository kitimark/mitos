#!/usr/bin/env bash
# Cheat corpus: every case must be REJECTED by the full gate at its expected gate.
# Each case is also run with --skip-lint to record what the later gates catch on their own
# (defence in depth). A case whose comparator-only result differs from `expect` also fails:
# it means our understanding of the gate changed, and the corpus must be updated on purpose.
#
# usage: eval/cheats/run.sh [case...]      (run from the repository root)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
lake build -q mitos-gate >/dev/null || { echo "gate build failed"; exit 2; }
GATE="$ROOT/.lake/build/bin/mitos-gate"
cases=("$@")
[ ${#cases[@]} -eq 0 ] && cases=($(ls -d eval/cheats/*/ | xargs -n1 basename))

verdict() {  # prints ACCEPTED or REJECTED@N
  local out; out="$("$GATE" accept --workspace "$1" --plugin ToyRequire \
    --model Models.ToyRequire.model --mitos-root "$ROOT" $2 2>&1)"
  echo "$out" > "$3"
  if grep -q '^VERDICT: ACCEPTED' <<<"$out"; then echo ACCEPTED
  else grep -o '^VERDICT: REJECTED (gate [0-9]*' <<<"$out" | grep -o '[0-9]*$' | sed 's/^/REJECTED@/'; fi
}

fail=0
printf '%-20s %-14s %-14s %-22s %s\n' CASE FULL EXPECT COMPARATOR-ONLY EXPECT
for c in "${cases[@]}"; do
  d="eval/cheats/$c"; [ -f "$d/expect" ] || continue
  full_exp=$(grep '^full=' "$d/expect" | cut -d= -f2)
  comp_exp=$(grep '^comparator_only=' "$d/expect" | cut -d= -f2)
  ws=$(mktemp -d)
  cp examples/acme/lakefile.toml examples/acme/lean-toolchain examples/acme/models.lock "$ws/"
  cp -r examples/acme/Models examples/acme/Plugins "$ws/"
  cp -r "$d/Plugins" "$ws/"; [ -d "$d/Models" ] && cp -r "$d/Models" "$ws/"
  log="$ROOT/.lake/cheats"; mkdir -p "$log"
  full=$(verdict "$ws" "" "$log/$c.full.log")
  comp=$(verdict "$ws" "--skip-lint" "$log/$c.comparator.log")
  rm -rf "$ws"
  ok_full=no; [ "$full" = "REJECTED@$full_exp" ] && ok_full=yes
  case "$comp_exp" in
    accept) [ "$comp" = ACCEPTED ] && ok_comp=yes || ok_comp=no ;;
    reject) [[ "$comp" == REJECTED@* ]] && ok_comp=yes || ok_comp=no ;;
    reject@*) [ "$comp" = "REJECTED@${comp_exp#reject@}" ] && ok_comp=yes || ok_comp=no ;;
  esac
  mark=""; { [ $ok_full = no ] || [ $ok_comp = no ]; } && { mark="  <-- FAIL"; fail=1; }
  printf '%-20s %-14s %-14s %-22s %s%s\n' "$c" "$full" "@$full_exp" "$comp" "$comp_exp" "$mark"
done
echo
if [ $fail -eq 0 ]; then echo "cheat corpus: all ${#cases[@]} cases behave as expected"; else echo "cheat corpus: FAILURES (logs in .lake/cheats/)"; fi
exit $fail
