import Mitos.Core

namespace Mitos.Impl

def providers (fs : List Located) (r : Located) : List Located :=
  fs.filter (matchesB r)

def assumptionsOf (r p : Located) : List Assumption :=
  if r.origin = p.origin then [r.origin] else [r.origin, p.origin]

def statusOf (fs : List Located) (r : Located) (assumes : List Assumption) : Status :=
  if assumes.all (fun a => !a.isAI) && (providers fs r).length == 1 then .confirmed
  else .inferred

def mkEdge (fs : List Located) (r p : Located) : Edge :=
  { requiringRepo := r.repo, providingRepo := p.repo, ident := r.fact.ident, scope := r.fact.scope,
    requiringFactId := r.id, providingFactId := p.id,
    assumes := assumptionsOf r p,
    status := statusOf fs r (assumptionsOf r p) }

def isRequirement (l : Located) : Bool := l.fact.kind == .requires

def resolve : Resolver := fun fs =>
  { edges := fs.flatMap fun r => (providers fs r).map (mkEdge fs r)
    unresolved := ((fs.filter isRequirement).filter fun r => (providers fs r).isEmpty).map (·.id) }

end Mitos.Impl
