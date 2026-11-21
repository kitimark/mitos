import Mitos.Core.Spec.Derivations

namespace Mitos.Spec

def Sound (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∃ c ∈ derivations fs,
    c.key = e.key ∧ c.repoKey = e.repoKey ∧ c.through = e.through

def Complete (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ c ∈ derivations fs, ∃ e ∈ (R fs).edges, e.key = c.key

def UnresolvedExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ i, i ∈ (R fs).unresolved ↔
    ∃ r ∈ fs, r.id = i ∧ r.fact.kind = .requires ∧
      ∀ c ∈ derivations fs, c.requirement.id ≠ r.id

def Total (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ r ∈ fs, r.fact.kind = .requires →
    (∃ e ∈ (R fs).edges, e.requiringFactId = r.id) ∨ r.id ∈ (R fs).unresolved

def AssumptionsExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∀ c ∈ derivations fs, c.key = e.key →
    (∀ a ∈ e.assumes, a ∈ c.origins) ∧ ∀ a ∈ c.origins, a ∈ e.assumes

def StatusHonest (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges,
    (e.status = .confirmed ↔
      ((∀ a ∈ e.assumes, a.isAI = false) ∧
        ∀ c ∈ derivations fs, c.requirement.id = e.requiringFactId →
          c.provision.id = e.providingFactId))

def RetractExact (R : Resolver) : Prop :=
  ∀ fs a, WellFormed fs → ∀ k,
    k ∈ (R (retract a fs)).edges.map Edge.key ↔
      k ∈ ((R fs).edges.filter (fun e => !(e.assumes.contains a))).map Edge.key

def ImpactCorrect (I : List Edge → String → List String) : Prop :=
  ∀ es x y, y ∈ I es x ↔ Affects es x y

def EdgesNodup (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ((R fs).edges.map Edge.key).Nodup

def UnresolvedNodup (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → (R fs).unresolved.Nodup

def AssumptionsNodup (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, e.assumes.Nodup

def ImpactNodup (I : List Edge → String → List String) : Prop :=
  ∀ es x, (I es x).Nodup

end Mitos.Spec
