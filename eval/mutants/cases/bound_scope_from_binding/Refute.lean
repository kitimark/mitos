import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

def needTest : Located := { needDb with fact := { needDb.fact with scope := .test } }

def fs : List Located := [needTest, bindDb, provDb]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide

end Mitos.Refute
