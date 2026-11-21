import Mitos.Impl.Resolve
import Mitos.Impl.Impact

namespace Mitos.Refute
open Mitos
open Mitos.Spec.Adequacy
open Mitos.Spec.Chains

example : (Impl.resolve [Spec.Adequacy.req, Spec.Adequacy.prov]).edges = [Spec.Adequacy.goodEdge] ∧
    (Impl.resolve [Spec.Adequacy.req]).unresolved = [0] := by decide

def s (cs : List Char) : String := String.ofList cs

def idSvc : Identity := ⟨s ['s'], s ['o']⟩

def loc (id : Nat) (repo : String) (kind : FactKind) (ident : Identity) (origin : Assumption) :
    Located :=
  { id, repo, rev := s [], path := s [], origin, fact := { kind, ident, span := ⟨0, 0⟩ } }

def idEnv : Identity := ⟨s ['e'], s ['d']⟩

def nReq : Located := loc 0 (s ['w']) .requires idEnv (.extractor (s ['x']))

def nBind : Located :=
  loc 1 (s ['d']) (.binds idSvc) idEnv (.humanDeclaredOutsideSource (s ['h']))

def nProv : Located := loc 2 (s ['o']) .provides idSvc (.extractor (s ['y']))

def fs : List Located := [nReq, nBind, nProv]

theorem wfIn : WellFormed fs := by unfold WellFormed; decide

example : (derivations fs).map (·.key) = [.bound 0 1 2] := by decide

theorem resolve_status_honest : ¬ Spec.StatusHonest Impl.resolve := by
  intro h
  have := h fs wfIn
  revert this
  decide

end Mitos.Refute
