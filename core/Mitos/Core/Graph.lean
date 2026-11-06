import Mitos.Core.Fact

/-!
# Located facts, edges and resolutions

The vocabulary the resolver works in. Statements about resolvers are in `Mitos.Core.Spec`.

Phase 1 resolves one rule: a requirement matches a provision of the same identity. Multi-step
chains (config key → deployment → service → repo) arrive with the deployment extractors; each
edge then carries a derivation instead of a single (requirement, provision) pair.
-/

namespace Mitos

/-- What a fact rests on. Retracting an assumption removes every fact it produced. -/
inductive Assumption where
  /-- An accepted extractor plugin, by name. -/
  | extractor (name : String)
  /-- A human-declared fact about the world outside the source (runtime config, registries). -/
  | declaration (id : String)
  /-- A fact proposed by an AI investigator. Edges resting on it are never confirmed. -/
  | ai (id : String)
  deriving DecidableEq, Repr

def Assumption.isAI : Assumption → Bool
  | .ai _ => true
  | _ => false

/-- A fact observed in one repository snapshot. `id` is unique within one resolver input. -/
structure Located where
  id     : Nat
  repo   : String
  rev    : String
  path   : String
  fact   : Fact
  origin : Assumption
  deriving DecidableEq, Repr

/-- How far an edge can be trusted. -/
inductive Status where
  /-- One provider, and nothing AI-proposed underneath. -/
  | confirmed
  /-- Several candidate providers, or an AI-proposed fact underneath. -/
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

/-- The (requirement, provision) pair an edge stands for; its identity across re-resolution. -/
def Edge.key (e : Edge) : Nat × Nat := (e.req, e.prov)

structure Resolution where
  edges      : List Edge
  /-- `id`s of requirements that nothing in the input provides. -/
  unresolved : List Nat
  deriving Repr

/-- A resolver turns all located facts into a resolution. -/
abbrev Resolver := List Located → Resolution

/-- Resolver inputs must have unique fact ids. -/
def WellFormed (fs : List Located) : Prop := (fs.map (·.id)).Nodup

/-- Does `p` provide what `r` requires? -/
def matchesB (r p : Located) : Bool :=
  r.fact.kind == .requires && p.fact.kind == .provides && r.fact.ident == p.fact.ident

/-- Remove every fact that rests on assumption `a`. -/
def retract (a : Assumption) (fs : List Located) : List Located :=
  fs.filter (fun l => l.origin != a)

/-- Changing repo `x` may affect repo `y`: `y` requires, directly or through a chain of edges,
something `x` provides. -/
inductive Affects (es : List Edge) : String → String → Prop where
  | step {e : Edge} : e ∈ es → Affects es e.dst e.src
  | trans {x y z : String} : Affects es x y → Affects es y z → Affects es x z

end Mitos
