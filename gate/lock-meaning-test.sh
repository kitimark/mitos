#!/usr/bin/env bash
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
lake build mitos-gate >/dev/null || { echo "FAIL lake build mitos-gate"; exit 1; }
bin="$root/.lake/build/bin/mitos-gate"
LEAN_PATH=$(lake env printenv LEAN_PATH) || { echo "FAIL lake env printenv LEAN_PATH"; exit 1; }
PATH=$(lake env printenv PATH) || { echo "FAIL lake env printenv PATH"; exit 1; }
export LEAN_PATH PATH
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cp "$root/core/Mitos/Core/Graph.lean" "$tmp/Graph.lean" || exit 1
cp "$root/core/Mitos/Core/Lines.lean" "$tmp/Lines.lean" || exit 1
cp "$root/core/Mitos/Core/Spec/Adequacy.lean" "$tmp/Adequacy.lean" || exit 1
cp "$root/core/Mitos/Core/Spec/Derivations.lean" "$tmp/Derivations.lean" || exit 1
cp "$root/core/Mitos/Core/Spec/Chains.lean" "$tmp/Chains.lean" || exit 1
cp "$root/statements.lock" "$tmp/lock" || exit 1

pass=0
fail=0

restore_sources() {
  cp "$tmp/Graph.lean" "$root/core/Mitos/Core/Graph.lean"
  cp "$tmp/Lines.lean" "$root/core/Mitos/Core/Lines.lean"
  cp "$tmp/Adequacy.lean" "$root/core/Mitos/Core/Spec/Adequacy.lean"
  cp "$tmp/Derivations.lean" "$root/core/Mitos/Core/Spec/Derivations.lean"
  cp "$tmp/Chains.lean" "$root/core/Mitos/Core/Spec/Chains.lean"
  cp "$tmp/lock" "$root/statements.lock"
}
trap 'restore_sources; rm -rf "$tmp"' EXIT

rebuild() {
  if ! lake build mitos-gate >"$tmp/build.out" 2>&1; then
    echo "FAIL $1: lake build"
    tail -40 "$tmp/build.out"
    fail=$((fail + 1))
    return 1
  fi
}

write_lock() {
  local dest=$1
  if ! "$bin" lock >"$tmp/lock.out" 2>&1; then
    echo "FAIL writing canonical lock"
    cat "$tmp/lock.out"
    fail=$((fail + 1))
    return 1
  fi
  cp "$root/statements.lock" "$dest"
}

run_lock_and_text() {
  local canon_dest=$1 text_dest=$2 text_pid
  "$bin" lock --text >"$text_dest" &
  text_pid=$!
  if ! write_lock "$canon_dest"; then
    wait "$text_pid" 2>/dev/null || true
    return 1
  fi
  if ! wait "$text_pid"; then
    echo "FAIL writing pre-canonical lines"
    fail=$((fail + 1))
    return 1
  fi
}

changed_ids() {
  diff <(grep -v '^#' "$1" | grep -v '^$' | sort) <(grep -v '^#' "$2" | grep -v '^$' | sort) |
    awk '/^[<>]/ { sub(/^[<>] /, ""); print $1, $2 }' | sort -u
}

ok() {
  echo "ok   $1"
  pass=$((pass + 1))
}

bad() {
  echo "FAIL $1"
  fail=$((fail + 1))
}

run_lock_and_text "$tmp/base.canon" "$tmp/base.text" || exit 1

python3 - <<'PY'
from pathlib import Path
p = Path("core/Mitos/Core/Graph.lean")
text = p.read_text()
needle = "namespace Mitos\n"
macros = '''section
open Lean
macro_rules | `(term| hygShift1) => throw (.error Syntax.missing "shift")
macro_rules | `(term| hygShift2) => throw (.error Syntax.missing "shift")
macro_rules | `(term| hygShift3) => throw (.error Syntax.missing "shift")
macro_rules | `(term| hygShift4) => throw (.error Syntax.missing "shift")
macro_rules | `(term| hygShift5) => throw (.error Syntax.missing "shift")
end

namespace Mitos
'''
if needle not in text:
    raise SystemExit("missing namespace anchor")
p.write_text(text.replace(needle, macros, 1))
PY

if rebuild "macro_rules"; then
  if run_lock_and_text "$tmp/macro.canon" "$tmp/macro.text"; then
  canon_n=$(changed_ids "$tmp/base.canon" "$tmp/macro.canon" | wc -l)
  text_n=$(changed_ids "$tmp/base.text" "$tmp/macro.text" | wc -l)
  echo "     macro_rules: $text_n pre-canonical lines moved, $canon_n canonical lines moved"
  if [ "$canon_n" = 0 ] && [ "$text_n" -gt 0 ]; then
    ok "five throwing macro_rules move no canonical line"
  else
    bad "five throwing macro_rules: canonical $canon_n, pre-canonical $text_n"
    changed_ids "$tmp/base.canon" "$tmp/macro.canon" | sed 's/^/  canon /'
  fi
  fi
fi
restore_sources

python3 - <<'PY'
from pathlib import Path
p = Path("core/Mitos/Core/Graph.lean")
old = "    ∀ {a b : Located}, a ∈ fs → b ∈ fs → a.id = b.id → a = b :=\n"
new = "    ∀ {factA factB : Located}, factA ∈ fs → factB ∈ fs → factA.id = factB.id → factA = factB :=\n"
text = p.read_text()
if old not in text:
    raise SystemExit("missing binder line")
p.write_text(text.replace(old, new, 1))
PY

if rebuild "renamed binder"; then
  if run_lock_and_text "$tmp/binder.canon" "$tmp/binder.text"; then
    if cmp -s "$tmp/base.canon" "$tmp/binder.canon" &&
        changed_ids "$tmp/base.text" "$tmp/binder.text" | grep -qx 'theorem Mitos.WellFormed.eq_of_id'; then
      ok "a renamed binder keeps the canonical lock"
    else
      bad "a renamed binder"
      echo "  canonical:"; diff -u "$tmp/base.canon" "$tmp/binder.canon" | head -20
      echo "  pre-canonical:"; changed_ids "$tmp/base.text" "$tmp/binder.text"
    fi
  fi
fi
restore_sources

python3 - <<'PY'
from pathlib import Path
p = Path("core/Mitos/Core/Graph.lean")
text = p.read_text()
needle = "namespace Mitos\n"
probe = "namespace Mitos\n\ndef canonProbe.{u} : Type u := Sort u\n"
if needle not in text:
    raise SystemExit("missing namespace")
p.write_text(text.replace(needle, probe, 1))
PY

if rebuild "universe probe"; then
  if run_lock_and_text "$tmp/univ-u.canon" "$tmp/univ-u.text"; then
  python3 - <<'PY'
from pathlib import Path
p = Path("core/Mitos/Core/Graph.lean")
p.write_text(p.read_text().replace("def canonProbe.{u} : Type u := Sort u",
                                   "def canonProbe.{v} : Type v := Sort v", 1))
PY
  if rebuild "renamed universe"; then
    if run_lock_and_text "$tmp/univ-v.canon" "$tmp/univ-v.text"; then
      if cmp -s "$tmp/univ-u.canon" "$tmp/univ-v.canon" && ! cmp -s "$tmp/univ-u.text" "$tmp/univ-v.text"; then
        ok "a renamed universe parameter keeps the canonical lock"
      else
        bad "a renamed universe parameter"
        diff -u "$tmp/univ-u.canon" "$tmp/univ-v.canon" | head -20
      fi
    fi
  fi
  fi
fi
restore_sources

python3 - <<'PY' || exit 1
from pathlib import Path
p = Path("core/Mitos/Core/Graph.lean")
old = "  | .ai _ => true\n"
new = "  | .ai _ => false\n"
text = p.read_text()
if old not in text:
    raise SystemExit("missing isAI arm")
p.write_text(text.replace(old, new, 1))
a = Path("core/Mitos/Core/Spec/Adequacy.lean")
proof = """theorem trusting_ai_not_honest :
    ¬ StatusHonest (fun _ => ⟨[{ goodEdge with assumes := [.extractor "npm", .ai "investigator"] }], []⟩) := by
  intro h
  have := h [req, provAI] wfAI
  revert this
  decide
"""
sorry_proof = """theorem trusting_ai_not_honest :
    ¬ StatusHonest (fun _ => ⟨[{ goodEdge with assumes := [.extractor "npm", .ai "investigator"] }], []⟩) := by
  sorry
"""
src = a.read_text()
if proof not in src:
    raise SystemExit("missing trusting_ai_not_honest proof")
a.write_text(src.replace(proof, sorry_proof, 1))

chains = Path("core/Mitos/Core/Spec/Chains.lean")
source = chains.read_text()
statement = """theorem status_honest_ai_binding_inferred {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R chainAI).edges, e.status = .inferred := by
"""
if source.count(statement) != 1:
    raise SystemExit("expected one status_honest_ai_binding_inferred statement")
proof_start = source.index(statement) + len(statement)
proof_end = source.find("\ndef bindStaging ", proof_start)
if proof_end < 0:
    raise SystemExit("missing bindStaging after status_honest_ai_binding_inferred")
chains.write_text(source[:proof_start] + "  sorry\n" + source[proof_end:])
PY

if rebuild "isAI arm"; then
  write_lock "$tmp/isai.canon"
  got=$(changed_ids "$tmp/base.canon" "$tmp/isai.canon")
  if [ "$got" = "def Mitos.Assumption.isAI" ]; then
    ok "an isAI match arm change moves only Mitos.Assumption.isAI"
  else
    bad "an isAI match arm change"
    printf '%s\n' "$got" | sed 's/^/  /'
  fi
fi
restore_sources

python3 - <<'PY'
from pathlib import Path
p = Path("core/Mitos/Core/Lines.lean")
text = p.read_text()
old = "  | [], o, reversedLine => [(o, reversedLine.reverse)]\n"
new = "  | [], o, reversedLine => [(o, reversedLine.reverse), (o, [])]\n"
if old not in text:
    raise SystemExit("missing lines.go arm")
text = text.replace(old, new, 1)
start = text.index("theorem lines.go_anchor")
end = text.index("\nend Mitos\n")
text = text[:start] + """theorem lines.go_anchor (s : List Char) (o : Utf8ByteCount) (reversedLine : List Char) :
    ∀ p ∈ lines.go s o reversedLine, ∃ pre post,
      reversedLine.reverse ++ s = pre ++ p.2 ++ post ∧ p.1 = o + utf8Len pre := by
  sorry

theorem mem_lines {s : List Char} {o : Nat} {l : List Char} (h : (o, l) ∈ lines s) :
    Span.text ⟨o, utf8Len l⟩ s = some l := by
  sorry
""" + text[end:]
p.write_text(text)
PY

if rebuild "lines.go body"; then
  write_lock "$tmp/lines.canon"
  got=$(changed_ids "$tmp/base.canon" "$tmp/lines.canon")
  if [ "$got" = "def Mitos.lines.go" ]; then
    ok "a lines.go body change moves def Mitos.lines.go"
  else
    bad "a lines.go body change"
    printf '%s\n' "$got" | sed 's/^/  /'
  fi
fi
restore_sources

python3 - <<'PY' || exit 1
from pathlib import Path
p = Path("core/Mitos/Core/Graph.lean")
old = (
    "    ∀ {a b : Located}, a ∈ fs → b ∈ fs → a.id = b.id → a = b :=\n"
    "  fun ha hb hid => List.inj_on_of_nodup_map wf ha hb hid\n"
)
new = (
    "    ∀ {a b : Located}, a ∈ fs → b ∈ fs → a.id = b.id → b = a :=\n"
    "  fun ha hb hid => (List.inj_on_of_nodup_map wf ha hb hid).symm\n"
)
text = p.read_text()
if old not in text:
    raise SystemExit("missing eq_of_id conclusion")
p.write_text(text.replace(old, new, 1))
d = Path("core/Mitos/Core/Spec/Derivations.lean")
src = d.read_text()
for original, replacement in [
    ("exact wf.eq_of_id hq hp\n        (H (Chain.direct r q) (hdirect.mpr ⟨r, hr, q, hq, hqm, rfl⟩) rfl)",
     "exact Eq.symm (wf.eq_of_id hq hp\n        (H (Chain.direct r q) (hdirect.mpr ⟨r, hr, q, hq, hqm, rfl⟩) rfl))"),
    ("have hrr : r' = r := wf.eq_of_id hr' hr hid",
     "have hrr : r' = r := Eq.symm (wf.eq_of_id hr' hr hid)"),
]:
    if src.count(original) != 1:
        raise SystemExit("expected one eq_of_id use: " + original.splitlines()[0])
    src = src.replace(original, replacement, 1)
d.write_text(src)
PY

if rebuild "eq_of_id"; then
  write_lock "$tmp/eq.canon"
  got=$(changed_ids "$tmp/base.canon" "$tmp/eq.canon")
  if [ "$got" = "theorem Mitos.WellFormed.eq_of_id" ]; then
    ok "an eq_of_id statement change moves its line"
  else
    bad "an eq_of_id statement change"
    printf '%s\n' "$got" | sed 's/^/  /'
  fi
fi
restore_sources

python3 - <<'PY'
from pathlib import Path
g = Path("core/Mitos/Core/Graph.lean")
gtext = g.read_text()
gneedle = "namespace Mitos\n"
if gneedle not in gtext:
    raise SystemExit("missing Graph namespace anchor")
g.write_text(gtext.replace(gneedle, gneedle + "\naxiom hiddenAx.inj : False\n", 1))

l = Path("core/Mitos/Core/Lines.lean")
ltext = l.read_text()
lneedle = "def lines.go : List Char"
if lneedle not in ltext:
    raise SystemExit("missing lines.go anchor")
l.write_text(ltext.replace(lneedle, "theorem lines.go.match_1.congr_eq_7 : True := .intro\n\n" + lneedle, 1))
PY

if rebuild "hidden axiom and congr_eq"; then
  if write_lock "$tmp/axcongr.canon"; then
    got=$(changed_ids "$tmp/base.canon" "$tmp/axcongr.canon")
    want=$(printf '%s\n%s' 'AXIOM Mitos.hiddenAx.inj' 'theorem Mitos.lines.go.match_1.congr_eq_7')
    if [ "$got" = "$want" ]; then
      ok "a hidden axiom and a hand-written congr_eq lemma each get a line"
    else
      bad "a hidden axiom and a hand-written congr_eq lemma"
      printf '%s\n' "$got" | sed 's/^/  /'
    fi
  fi
fi
restore_sources

python3 - <<'PY'
from pathlib import Path
g = Path("core/Mitos/Core/Graph.lean")
gtext = g.read_text()
gneedle = "namespace Mitos\n"
if gneedle not in gtext:
    raise SystemExit("missing Graph namespace anchor")
extra = (
    gneedle
    + "\nprivate axiom hiddenPrivAx : False\n"
    + "axiom _hiddenInternalAx : False\n"
    + "theorem lookalike.inj : True := .intro\n"
    + "theorem proof_2 : True := .intro\n"
)
g.write_text(gtext.replace(gneedle, extra, 1))
PY

if rebuild "private and internal axioms and lookalikes"; then
  if write_lock "$tmp/lookalike.canon"; then
    got=$(changed_ids "$tmp/base.canon" "$tmp/lookalike.canon")
    want=$(printf '%s\n%s\n%s\n%s' \
      'AXIOM Mitos._hiddenInternalAx' \
      'AXIOM _private.Mitos.Core.Graph.0.Mitos.hiddenPrivAx' \
      'theorem Mitos.lookalike.inj' \
      'theorem Mitos.proof_2')
    if [ "$got" = "$want" ]; then
      ok "private/internal axioms and hand-written suffix lookalikes each get a line"
    else
      bad "private/internal axioms and hand-written suffix lookalikes"
      printf '%s\n' "$got" | sed 's/^/  /'
    fi
  fi
fi
restore_sources

python3 - <<'PY'
from pathlib import Path
g = Path("core/Mitos/Core/Graph.lean")
gtext = g.read_text()
gneedle = "namespace Mitos\n"
if gneedle not in gtext:
    raise SystemExit("missing Graph namespace anchor")
extra = (
    gneedle
    + "\nprivate partial def hiddenPartial (n : Nat) : Nat := hiddenPartial n\n"
    + "def usesHiddenPartial (n : Nat) : Nat := hiddenPartial n\n"
)
g.write_text(gtext.replace(gneedle, extra, 1))
PY

if rebuild "unlisted partial opaque"; then
  if "$bin" lock >"$tmp/partial.out" 2>&1; then
    bad "a reached unlisted partial opaque is refused"
    sed 's/^/  /' "$tmp/partial.out"
  elif grep -q 'opaque' "$tmp/partial.out" && grep -q 'hiddenPartial' "$tmp/partial.out"; then
    ok "a reached unlisted partial opaque is refused"
  else
    bad "a reached unlisted partial opaque is refused (unexpected message)"
    sed 's/^/  /' "$tmp/partial.out"
  fi
fi
restore_sources

if rebuild "restore"; then
  if "$bin" lock --check >"$tmp/lock.out" 2>&1; then
    ok "lock --check passes on the restored tree"
  else
    bad "lock --check after restore"
    cat "$tmp/lock.out"
  fi
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
