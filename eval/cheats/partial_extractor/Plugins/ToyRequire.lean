import Mitos.Core
import Models.ToyRequire

/-!
# Plugin: toy `require` lines  (AGENT-WRITTEN — code and proofs only)

The names below must match the Challenge that `mitos-gate` generates:
`ToyRequire.extractor`, `ToyRequire.anchored`, `ToyRequire.sound`, `ToyRequire.complete`.
-/

open Mitos Models.ToyRequire

namespace ToyRequire

/-- The fact for one line, if the line is a requirement. -/
def ofLine (p : Nat × List Char) : Option Fact :=
  if prefixChars.isPrefixOf p.2 then some (fact p.1 (p.2.drop prefixChars.length)) else none

partial def extractor : Extractor := ⟨fun s => (lines s.toList).filterMap ofLine⟩

theorem ofLine_eq {p : Nat × List Char} {f : Fact} (h : ofLine p = some f) :
    ∃ name, p.2 = prefixChars ++ name ∧ f = fact p.1 name := by
  unfold ofLine at h
  split at h
  · rename_i hp
    refine ⟨p.2.drop prefixChars.length, ?_, (Option.some.inj h).symm⟩
    exact ((List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 hp)).symm
  · contradiction

theorem sound : SoundWrt model extractor := by
  sorry

theorem anchored : Anchored extractor := by
  sorry

theorem complete : CompleteWrt model extractor := by
  sorry

end ToyRequire
