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

structure Edge where
  requiringRepo    : String
  providingRepo    : String
  ident            : Identity
  scope            : Scope
  requiringFactId  : Nat
  providingFactId  : Nat
  assumes          : List Assumption
  status           : Status
  deriving DecidableEq, Repr

def Edge.key (e : Edge) : Nat × Nat := (e.requiringFactId, e.providingFactId)

structure Resolution where
  edges      : List Edge
  unresolved : List Nat
  deriving Repr

abbrev Resolver := List Located → Resolution

def WellFormed (fs : List Located) : Prop := (fs.map (·.id)).Nodup

def matchesB (r p : Located) : Bool :=
  r.fact.kind == .requires && p.fact.kind == .provides && r.fact.ident == p.fact.ident

def retract (a : Assumption) (fs : List Located) : List Located :=
  fs.filter (fun l => l.origin != a)

inductive Affects (es : List Edge) : (changed : String) → (dependent : String) → Prop where
  | step {e : Edge} : e ∈ es → Affects es (changed := e.providingRepo) (dependent := e.requiringRepo)
  | trans {x y z : String} : Affects es x y → Affects es y z → Affects es x z

end Mitos
