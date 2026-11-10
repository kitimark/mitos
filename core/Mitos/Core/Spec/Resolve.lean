import Mitos.Core.Graph

namespace Mitos.Spec

def Sound (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∃ r ∈ fs, ∃ p ∈ fs,
    r.id = e.requiringFactId ∧ p.id = e.providingFactId ∧ matchesB r p = true ∧
    e.requiringRepo = r.repo ∧ e.providingRepo = p.repo ∧ e.ident = r.fact.ident ∧ e.scope = r.fact.scope

def Complete (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ r ∈ fs, ∀ p ∈ fs, matchesB r p = true →
    ∃ e ∈ (R fs).edges, e.requiringFactId = r.id ∧ e.providingFactId = p.id

def UnresolvedExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ i, i ∈ (R fs).unresolved ↔
    ∃ r ∈ fs, r.id = i ∧ r.fact.kind = .requires ∧ ∀ p ∈ fs, matchesB r p = false

def Total (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ r ∈ fs, r.fact.kind = .requires →
    (∃ e ∈ (R fs).edges, e.requiringFactId = r.id) ∨ r.id ∈ (R fs).unresolved

def AssumptionsExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∀ r ∈ fs, ∀ p ∈ fs,
    r.id = e.requiringFactId → p.id = e.providingFactId →
    ∀ a, a ∈ e.assumes ↔ (a = r.origin ∨ a = p.origin)

def StatusHonest (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∀ r ∈ fs, r.id = e.requiringFactId →
    (e.status = .confirmed ↔
      ((∀ a ∈ e.assumes, a.isAI = false) ∧ (fs.filter (matchesB r)).length = 1))

def RetractExact (R : Resolver) : Prop :=
  ∀ fs a, WellFormed fs → ∀ k,
    k ∈ (R (retract a fs)).edges.map Edge.key ↔
      k ∈ ((R fs).edges.filter (fun e => !(e.assumes.contains a))).map Edge.key

def ImpactCorrect (I : List Edge → String → List String) : Prop :=
  ∀ es x y, y ∈ I es x ↔ Affects es x y

end Mitos.Spec
