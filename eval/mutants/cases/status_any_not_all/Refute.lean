import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos

/-- A string from its characters. Written without string literals: with literals, lean4lean
rejected this refutation (`unknown constant 'Char.ofNat'`), because the export declared them
before `Char.ofNat`. -/
def str (cs : List Char) : String := String.ofList cs

def loc (id : Nat) (repo : String) (kind : FactKind) (origin : Assumption) : Located :=
  { id, repo, rev := str [], path := str [], origin,
    fact := { kind, ident := ⟨str ['n', 'p', 'm'], str ['l', 'i', 'b']⟩, span := ⟨0, 0⟩ } }

/-- An AI investigator proposed `a`'s requirement; an extractor found `b`'s provision. -/
def fs : List Located :=
  [loc 0 (str ['a']) .requires (.ai (str ['g'])), loc 1 (str ['b']) .provides (.extractor (str ['x']))]

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs (by unfold WellFormed; decide)
  revert this
  decide

end Mitos.Refute
