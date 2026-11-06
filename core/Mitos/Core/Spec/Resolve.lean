import Mitos.Core.Graph

/-!
# Resolver specification  (SPEC — owner-approved, pinned in statements.lock)

Each statement is a `Prop` about an arbitrary resolver `R`. An implementation PR supplies a
resolver and proves, for it, `theorem … : Spec.Sound resolve` and so on; it cannot change what
these say. Stating them as definitions (rather than theorems with `sorry`) keeps `sorry` off
`main` between the spec PR and the implementation PR.

`Mitos.Core.Spec.Adequacy` shows the statements are not vacuous: obvious wrong resolvers fail
them.
-/

namespace Mitos.Spec

/-- **Soundness.** Every edge joins a requirement to a provision of the same identity, and carries
their repos, the identity and the requirement's scope unchanged. -/
def Sound (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∃ r ∈ fs, ∃ p ∈ fs,
    r.id = e.req ∧ p.id = e.prov ∧ matchesB r p = true ∧
    e.src = r.repo ∧ e.dst = p.repo ∧ e.ident = r.fact.ident ∧ e.scope = r.fact.scope

/-- **Completeness.** Every matching (requirement, provision) pair becomes an edge. -/
def Complete (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ r ∈ fs, ∀ p ∈ fs, matchesB r p = true →
    ∃ e ∈ (R fs).edges, e.req = r.id ∧ e.prov = p.id

/-- **Unresolved, exactly.** A requirement is listed as unresolved exactly when nothing in the
input provides it. Missing information is reported, never dropped and never invented. -/
def UnresolvedExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ i, i ∈ (R fs).unresolved ↔
    ∃ r ∈ fs, r.id = i ∧ r.fact.kind = .requires ∧ ∀ p ∈ fs, matchesB r p = false

/-- **Totality.** Every requirement ends up as an edge or on the unresolved list. -/
def Total (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ r ∈ fs, r.fact.kind = .requires →
    (∃ e ∈ (R fs).edges, e.req = r.id) ∨ r.id ∈ (R fs).unresolved

/-- **Assumptions, exactly.** An edge lists exactly what its two facts rest on. -/
def AssumptionsExact (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∀ r ∈ fs, ∀ p ∈ fs, r.id = e.req → p.id = e.prov →
    ∀ a, a ∈ e.assumes ↔ (a = r.origin ∨ a = p.origin)

/-- **Honest status.** An edge is confirmed exactly when nothing under it is AI-proposed and its
requirement has a single provider. -/
def StatusHonest (R : Resolver) : Prop :=
  ∀ fs, WellFormed fs → ∀ e ∈ (R fs).edges, ∀ r ∈ fs, r.id = e.req →
    (e.status = .confirmed ↔
      ((∀ a ∈ e.assumes, a.isAI = false) ∧ (fs.filter (matchesB r)).length = 1))

/-- **Retraction, exactly.** Re-resolving without assumption `a` keeps exactly the edges that do
not rest on `a` (compared by their (requirement, provision) key). -/
def RetractExact (R : Resolver) : Prop :=
  ∀ fs a, WellFormed fs → ∀ k,
    k ∈ (R (retract a fs)).edges.map Edge.key ↔
      k ∈ ((R fs).edges.filter (fun e => !(e.assumes.contains a))).map Edge.key

/-- **Impact analysis.** The repos reported as affected by a change to `x` are exactly those that
depend on `x` through the edges. -/
def ImpactCorrect (I : List Edge → String → List String) : Prop :=
  ∀ es x y, y ∈ I es x ↔ Affects es x y

end Mitos.Spec
