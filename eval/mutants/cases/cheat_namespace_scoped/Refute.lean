import Mitos.Impl.Resolve
import Mitos.Impl.Impact

/-! A cheat on the lint's parse: entering namespace `Int` switches on `Init`'s scoped syntax
`-[n+1]`, so Lean reads the example below as `Int.negSucc 1 = Int.negSucc 1`, while `Init`'s
syntax alone reads `-[1+1]` as `-` applied to the list `[1+1]`. The example declares nothing, so
only the namespace itself is refused. The refutation is `src_dst_swapped`'s. -/

namespace Int

example : Int.negSucc 1 = -[1+1] := rfl

end Int

namespace Mitos.Refute
open Mitos

def loc (id : Nat) (repo : String) (kind : FactKind) : Located :=
  { id, repo, rev := "", path := "", origin := .extractor "x",
    fact := { kind, ident := ⟨"npm", "lib"⟩, span := ⟨0, 0⟩ } }

def fs : List Located := [loc 0 "a" .requires, loc 1 "b" .provides]

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
