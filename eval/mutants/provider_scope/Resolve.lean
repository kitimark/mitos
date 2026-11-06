import Mitos.Core

/-!
# Reference resolver  (IMPLEMENTATION — not in the lock; correctness is the theorems)

For each requirement `r`, its providers are the facts `p` with `matchesB r p`. One edge per
(requirement, provider) pair; a requirement with no providers is reported as unresolved.

List-based and quadratic on purpose: it is the reference the proofs are about. A faster resolver
(indexed by identity) can replace it later if it is proven to compute the same `Resolution`.
-/

namespace Mitos.Impl

/-- The facts in `fs` that provide what `r` requires. -/
def providers (fs : List Located) (r : Located) : List Located :=
  fs.filter (matchesB r)

/-- What an edge from `r` to `p` rests on, without repeating a shared origin. -/
def assumptionsOf (r p : Located) : List Assumption :=
  if r.origin = p.origin then [r.origin] else [r.origin, p.origin]

/-- Confirmed only with a single provider and nothing AI-proposed underneath. -/
def statusOf (fs : List Located) (r : Located) (assumes : List Assumption) : Status :=
  if assumes.all (fun a => !a.isAI) && (providers fs r).length == 1 then .confirmed
  else .inferred

/-- The edge for requirement `r` satisfied by provision `p`, within input `fs`. -/
def mkEdge (fs : List Located) (r p : Located) : Edge :=
  { src := r.repo, dst := p.repo, ident := r.fact.ident, scope := p.fact.scope,
    req := r.id, prov := p.id,
    assumes := assumptionsOf r p,
    status := statusOf fs r (assumptionsOf r p) }

def isRequirement (l : Located) : Bool := l.fact.kind == .requires

def resolve : Resolver := fun fs =>
  { edges := fs.flatMap fun r => (providers fs r).map (mkEdge fs r)
    unresolved := ((fs.filter isRequirement).filter fun r => (providers fs r).isEmpty).map (·.id) }

end Mitos.Impl
