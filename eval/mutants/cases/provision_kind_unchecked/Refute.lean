import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

def needSvc : Located :=
  { id := 3, repo := "billing", rev := "e", path := "app.env", origin := .extractor "env"
    fact := { kind := .requires, ident := ⟨"svc", "orders-db"⟩, span := ⟨0, 9⟩ } }

def fs : List Located := [needDb, bindDb, needSvc]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : derivations fs = [] := by decide

theorem resolve_sound : ¬ Spec.Sound Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide

end Mitos.Refute
