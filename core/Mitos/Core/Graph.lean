import Mitos.Core.Fact

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
  | bound (requiringFactId bindingFactId providingFactId : Nat)
  deriving DecidableEq, Repr

def Derivation.requiringFactId : Derivation → Nat
  | .direct r _ => r
  | .bound r _ _ => r

def Derivation.providingFactId : Derivation → Nat
  | .direct _ p => p
  | .bound _ _ p => p

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
  through : List String := []
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
    ∀ {a b : Located}, a ∈ fs → b ∈ fs → a.id = b.id → a = b := by
  unfold WellFormed at wf
  induction fs with
  | nil => intro a b ha; simp at ha
  | cons x xs ih =>
    simp only [List.map_cons, List.nodup_cons, List.mem_map, not_exists, not_and] at wf
    intro a b ha hb hid
    simp only [List.mem_cons] at ha hb
    rcases ha with rfl | ha <;> rcases hb with rfl | hb
    · rfl
    · exact absurd hid.symm (wf.1 b hb)
    · exact absurd hid (wf.1 a ha)
    · exact ih wf.2 ha hb hid

def retract (a : Assumption) (fs : List Located) : List Located :=
  fs.filter (fun l => l.origin != a)

theorem wellFormed_retract {fs : List Located} (a : Assumption) (wf : WellFormed fs) :
    WellFormed (retract a fs) :=
  List.Nodup.sublist (List.Sublist.map _ List.filter_sublist) wf

inductive Affects (es : List Edge) : (changed : String) → (dependent : String) → Prop where
  | step {e : Edge} : e ∈ es → Affects es (changed := e.providingRepo) (dependent := e.requiringRepo)
  | through {e : Edge} {b : String} : e ∈ es → b ∈ e.through →
      Affects es (changed := b) (dependent := e.requiringRepo)
  | trans {x y z : String} : Affects es x y → Affects es y z → Affects es x z

end Mitos
