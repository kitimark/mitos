import Mitos.Core.Fact

namespace Mitos

inductive Assumption where
  | extractor (name : String)
  /-- A human-declared fact about the world outside the source (runtime config, registries). -/
  | declaration (id : String)
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

/-- `src` requires something `dst` provides. -/
structure Edge where
  src     : String
  dst     : String
  ident   : Identity
  scope   : Scope
  /-- `id` of the requiring fact. -/
  req     : Nat
  /-- `id` of the providing fact. -/
  prov    : Nat
  assumes : List Assumption
  status  : Status
  deriving DecidableEq, Repr

def Edge.key (e : Edge) : Nat × Nat := (e.req, e.prov)

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

/-- Changing repo `x` may affect repo `y`: `y` requires, directly or through a chain of edges,
something `x` provides. -/
inductive Affects (es : List Edge) : String → String → Prop where
  | step {e : Edge} : e ∈ es → Affects es e.dst e.src
  | trans {x y z : String} : Affects es x y → Affects es y z → Affects es x z

end Mitos
