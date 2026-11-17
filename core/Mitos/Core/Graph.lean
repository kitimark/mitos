import Mitos.Core.Fact
import Mathlib.Data.List.Nodup

namespace Mitos

inductive Assumption where
  | extractor (name : String)
  | humanDeclaredOutsideSource (id : String)
  | ai (id : String)
  deriving DecidableEq, Repr

def Assumption.isAI : Assumption → Bool
  | .ai _ => true
  | _ => false

structure Located where
  id     : Nat
  repo   : String
  rev    : String
  path   : String
  fact   : Fact
  origin : Assumption
  deriving DecidableEq, Repr

inductive Status where
  | confirmed
  | inferred
  deriving DecidableEq, Repr

inductive Derivation where
  | direct (requiringFactId providingFactId : Nat)
  deriving DecidableEq, Repr

def Derivation.requiringFactId : Derivation → Nat
  | .direct r _ => r

def Derivation.providingFactId : Derivation → Nat
  | .direct _ p => p

structure RepoKey where
  requiringRepo : String
  providingRepo : String
  ident         : Identity
  scope         : Scope
  deriving DecidableEq, Repr

structure Edge extends repoKey : RepoKey where
  key     : Derivation
  assumes : List Assumption
  status  : Status
  deriving DecidableEq, Repr

def Edge.requiringFactId (e : Edge) : Nat := e.key.requiringFactId

def Edge.providingFactId (e : Edge) : Nat := e.key.providingFactId

structure Resolution where
  edges      : List Edge
  unresolved : List Nat
  deriving Repr

abbrev Resolver := List Located → Resolution

def WellFormed (fs : List Located) : Prop := (fs.map (·.id)).Nodup

theorem WellFormed.eq_of_id {fs : List Located} (wf : WellFormed fs) :
    ∀ {a b : Located}, a ∈ fs → b ∈ fs → a.id = b.id → a = b :=
  fun ha hb hid => List.inj_on_of_nodup_map wf ha hb hid

def retract (a : Assumption) (fs : List Located) : List Located :=
  fs.filter (fun l => l.origin != a)

theorem wellFormed_retract {fs : List Located} (a : Assumption) (wf : WellFormed fs) :
    WellFormed (retract a fs) :=
  List.Nodup.sublist (List.Sublist.map _ List.filter_sublist) wf

inductive Affects (es : List Edge) : (changed : String) → (dependent : String) → Prop where
  | step {e : Edge} : e ∈ es → Affects es (changed := e.providingRepo) (dependent := e.requiringRepo)
  | trans {x y z : String} : Affects es x y → Affects es y z → Affects es x z

end Mitos
