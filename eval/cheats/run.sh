#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
lake build -q mitos-gate >/dev/null || { echo "gate build failed"; exit 2; }
GATE="$ROOT/.lake/build/bin/mitos-gate"
cases=("$@")
[ ${#cases[@]} -eq 0 ] && cases=($(ls -d eval/cheats/*/ | xargs -n1 basename))
[ ${#cases[@]} -gt 0 ] || { echo "no cheat cases found in eval/cheats/"; exit 2; }

verdict() {
  local out; out="$("$GATE" accept --workspace "$1" --plugin ToyRequire \
    --model Models.ToyRequire.model --mitos-root "$ROOT" $2 2>&1)"
  echo "$out" > "$3"
  if grep -q '^VERDICT: ACCEPTED' <<<"$out"; then echo ACCEPTED
  else grep -o '^VERDICT: REJECTED (gate [0-9]*' <<<"$out" | grep -o '[0-9]*$' | sed 's/^/REJECTED@/'; fi
}

# A case whose expect file has `guards=R` claims that without lint rule R its full run is ACCEPTED.
# Gate 1 is the only gate --skip-lint skips, and lint is a pure function of the bytes, so the claim
# holds when the case is comparator_only=accept (its run is checked below) and every violation of
# its full run, a line under gate 1's that ends in ` [R]`, has rule R. Prints `guards=R`, and why
# the claim fails if it does, in which case it returns 1.
check_guards() {  # <expect file> <full-run log>
  local rule why; rule=$(grep '^guards=' "$1" | cut -d= -f2-)
  [ -z "$rule" ] && return 0
  printf 'guards=%s' "$rule"
  [ -s "$2" ] || { echo ": no full-run log"; return 1; }
  why=$(LC_ALL=C awk -v want=" [$rule]" '
    /^GATE 1 lint: FAIL/ { on = 1; if (match($0, /[0-9]+ violation/)) n = substr($0, RSTART, RLENGTH - 10) + 0; next }
    on && /^  / {
      v++
      if (substr($0, length($0) - length(want) + 1) == want) next
      r = match($0, / \[[^][ ]*\]$/) ? substr($0, RSTART + 1) : "no rule"
      if (!(r in other)) { other[r] = 1; s = s (s == "" ? "" : ", ") r }
      next }
    { on = 0 }
    END {
      if (!n) print "the full run reports no gate-1 violation"
      else if (v != n) print "gate 1 counts " n " violations and lists " v
      else if (s != "") print "the full run also has violations " s
    }' "$2")
  grep -qx 'comparator_only=accept' "$1" || why="${why:+$why; }it is not comparator_only=accept"
  [ -z "$why" ] || { echo ": $why"; return 1; }
}

fail=0
printf '%-20s %-14s %-14s %-22s %-10s %s\n' CASE FULL EXPECT COMPARATOR-ONLY EXPECT GUARDS
for c in "${cases[@]}"; do
  d="eval/cheats/$c"
  if [ ! -f "$d/expect" ]; then printf '%-20s no expect file  <-- FAIL\n' "$c"; fail=1; continue; fi
  full_exp=$(grep '^full=' "$d/expect" | cut -d= -f2)
  comp_exp=$(grep '^comparator_only=' "$d/expect" | cut -d= -f2)
  ws=$(mktemp -d)
  cp examples/acme/lakefile.toml examples/acme/lean-toolchain examples/acme/models.lock "$ws/"
  cp -r examples/acme/Models examples/acme/Plugins "$ws/"
  [ -d "$d/Plugins" ] && cp -r "$d/Plugins" "$ws/"; [ -d "$d/Models" ] && cp -r "$d/Models" "$ws/"
  # Re-pin every model, recursively, as gate 0 walks Models/.
  grep -qx 'model_approved=yes' "$d/expect" && (cd "$ws" &&
    find Models -name '*.lean' ! -type d -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > models.lock)
  # Lines to append to the workspace's models.lock, to test how gate 0 reads it.
  grep '^lock_append=' "$d/expect" | cut -d= -f2- >> "$ws/models.lock"
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
  guard=$(check_guards "$d/expect" "$log/$c.full.log") && ok_guard=yes || ok_guard=no
  mark=""; { [ $ok_full = no ] || [ $ok_comp = no ] || [ $ok_guard = no ]; } && { mark="  <-- FAIL"; fail=1; }
  printf '%-20s %-14s %-14s %-22s %-10s %s%s\n' "$c" "$full" "@$full_exp" "$comp" "$comp_exp" "$guard" "$mark"
done
echo
if [ $fail -eq 0 ]; then echo "cheat corpus: all ${#cases[@]} cases behave as expected"; else echo "cheat corpus: FAILURES (logs in .lake/cheats/)"; fi
exit $fail
