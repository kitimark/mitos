import Mitos.Core.Spec.Adequacy

namespace Mitos.Spec.Chains
open Adequacy (req prov twoProvisions provDeclared)

def needDb : Located :=
  { id := 0, repo := "web", rev := "a", path := "app.env", origin := .extractor "env"
    fact := { kind := .requires, ident := { kind := "env", key := "DATABASE_URL" },
              span := ⟨0, 12⟩ } }

def bindDb : Located :=
  { id := 1, repo := "deploy", rev := "c", path := "web.yaml",
    origin := .humanDeclaredOutsideSource "deploy/web.yaml"
    fact := { kind := .binds { kind := "svc", key := "orders-db" },
              ident := { kind := "env", key := "DATABASE_URL" }, span := ⟨0, 12⟩ } }

def provDb : Located :=
  { id := 2, repo := "orders", rev := "d", path := "service.yaml", origin := .extractor "svc"
    fact := { kind := .provides, ident := { kind := "svc", key := "orders-db" }, span := ⟨0, 9⟩ } }

def chain : List Located := [needDb, bindDb, provDb]

theorem wfChain : WellFormed chain := by unfold WellFormed; decide

def chainEdge : Edge :=
  { requiringRepo := "web", providingRepo := "orders", ident := needDb.fact.ident, scope := .runtime,
    key := .bound 0 1 2, through := ["deploy"],
    assumes := [needDb.origin, bindDb.origin, provDb.origin], status := .confirmed }

theorem chain_derivations : derivations chain = [Chain.bound needDb bindDb provDb] := by
  decide

theorem noBinds_twoProvisions : NoBinds twoProvisions := by
  intro b hb i
  simp only [twoProvisions, List.mem_cons, List.not_mem_nil, or_false] at hb
  rcases hb with rfl | rfl | rfl <;> simp [req, prov, provDeclared]

theorem sound_records_the_binding {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R chain).edges,
      e.key = Derivation.bound 0 1 2 ∧ e.through = ["deploy"] ∧ e.repoKey = chainEdge.repoKey := by
  intro e he
  obtain ⟨c, hc, hk, hr, ht⟩ := hs chain wfChain e he
  rw [chain_derivations, List.mem_singleton] at hc
  subst hc
  exact ⟨hk.symm, ht.symm, hr.symm⟩

theorem sound_direct_edges_have_no_through {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R [req, prov]).edges, e.through = [] := by
  intro e he
  obtain ⟨c, hc, -, -, ht⟩ := hs [req, prov] Adequacy.wf e he
  have hd : derivations [req, prov] = [Chain.direct req prov] := by decide
  rw [hd, List.mem_singleton] at hc
  subst hc
  exact ht.symm

theorem unresolved_exact_binding_resolves {R : Resolver} (hu : UnresolvedExact R) :
    0 ∉ (R chain).unresolved := by
  intro h
  obtain ⟨r, -, hid, -, hn⟩ := (hu chain wfChain 0).mp h
  exact hn (Chain.bound needDb bindDb provDb) (by rw [chain_derivations]; simp) hid.symm

theorem unresolved_exact_needs_the_binding {R : Resolver} (hu : UnresolvedExact R) :
    0 ∈ (R [needDb, provDb]).unresolved := by
  refine (hu [needDb, provDb] (by unfold WellFormed; decide) 0).mpr ⟨needDb, by simp, rfl, rfl, ?_⟩
  intro c hc
  have hnil : derivations [needDb, provDb] = [] := by decide
  rw [hnil] at hc
  simp at hc

theorem assumptions_exact_lists_binding {R : Resolver} (ha : AssumptionsExact R) :
    ∀ e ∈ (R chain).edges, e.key = Derivation.bound 0 1 2 →
      ∀ a, a ∈ e.assumes ↔ (a = needDb.origin ∨ a = bindDb.origin ∨ a = provDb.origin) := by
  intro e he hk a
  obtain ⟨h1, h2⟩ := ha chain wfChain e he (Chain.bound needDb bindDb provDb)
    (by rw [chain_derivations]; simp) hk.symm
  have ho : (Chain.bound needDb bindDb provDb).origins =
      [needDb.origin, bindDb.origin, provDb.origin] := rfl
  rw [ho] at h1 h2
  constructor
  · intro h; simpa using h1 a h
  · intro h; exact h2 a (by simpa using h)

def bindAI : Located := { bindDb with origin := .ai "investigator" }

def chainAI : List Located := [needDb, bindAI, provDb]

theorem wfChainAI : WellFormed chainAI := by unfold WellFormed; decide

theorem status_honest_ai_binding_inferred {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R chainAI).edges, e.status = .inferred := by
  intro e he
  have hd : derivations chainAI = [Chain.bound needDb bindAI provDb] := by decide
  obtain ⟨c, hc, hk, -⟩ := hs chainAI wfChainAI e he
  have hc' := hc
  rw [hd, List.mem_singleton] at hc'
  subst hc'
  have hai : bindAI.origin ∈ e.assumes :=
    (ha chainAI wfChainAI e he _ hc hk).2 _ (by simp [Chain.origins, Chain.bound])
  cases hst : e.status with
  | inferred => rfl
  | confirmed =>
    obtain ⟨hnoai, -⟩ := (hh chainAI wfChainAI e he).mp hst
    exact absurd (hnoai _ hai) (by decide)

def bindStaging : Located :=
  { bindDb with id := 3, repo := "staging", origin := .humanDeclaredOutsideSource "staging/web.yaml" }

def twoBindings : List Located := [needDb, bindDb, provDb, bindStaging]

theorem wfTwoBindings : WellFormed twoBindings := by unfold WellFormed; decide

theorem twoBindings_derivations :
    derivations twoBindings =
      [Chain.bound needDb bindDb provDb, Chain.bound needDb bindStaging provDb] := by
  decide

theorem complete_keeps_both_bindings {R : Resolver} (hc : Complete R) :
    (∃ e ∈ (R twoBindings).edges, e.key = Derivation.bound 0 1 2) ∧
      ∃ e ∈ (R twoBindings).edges, e.key = Derivation.bound 0 3 2 := by
  have h := hc twoBindings wfTwoBindings
  rw [twoBindings_derivations] at h
  exact ⟨h (Chain.bound needDb bindDb provDb) (by simp),
    h (Chain.bound needDb bindStaging provDb) (by simp)⟩

theorem binding_retracted_chain_goes {R : Resolver} (hs : Sound R) :
    (R (retract bindDb.origin chain)).edges = [] := by
  have wf' := wellFormed_retract bindDb.origin wfChain
  have hnil : derivations (retract bindDb.origin chain) = [] := by decide
  apply List.eq_nil_iff_forall_not_mem.mpr
  intro e he
  obtain ⟨c, hc, -⟩ := hs _ wf' e he
  rw [hnil] at hc
  simp at hc

theorem binding_retracted_repo_edge_stays {R : Resolver} (hs : Sound R) (hc : Complete R) :
    chainEdge.repoKey ∈
      (R (retract bindStaging.origin twoBindings)).edges.map Edge.repoKey := by
  have wf' := wellFormed_retract bindStaging.origin wfTwoBindings
  have hd : Chain.bound needDb bindDb provDb ∈
      derivations (retract bindStaging.origin twoBindings) := by decide
  obtain ⟨e, he, hk⟩ := hc _ wf' _ hd
  obtain ⟨c, hcm, hck, hcr, -⟩ := hs _ wf' e he
  have := derivations_key_inj wf' hcm hd (hck.trans hk)
  subst this
  exact List.mem_map.mpr ⟨e, he, hcr.symm⟩

def forkBind : Located :=
  { bindDb with id := 2, fact := { bindDb.fact with ident := req.fact.ident } }

def forkProv : Located := { provDb with id := 3 }

def fork : List Located := [req, prov, forkBind, forkProv]

theorem wfFork : WellFormed fork := by unfold WellFormed; decide

theorem fork_derivations :
    derivations fork = [Chain.direct req prov, Chain.bound req forkBind forkProv] := by
  decide

theorem status_honest_fork_inferred {R : Resolver} (hh : StatusHonest R) :
    ∀ e ∈ (R fork).edges, e.requiringFactId = 0 → e.status = .inferred := by
  intro e he hr
  cases hs : e.status with
  | inferred => rfl
  | confirmed =>
    obtain ⟨-, hall⟩ := (hh fork wfFork e he).mp hs
    rw [fork_derivations] at hall
    have h1 := hall (Chain.direct req prov) (by simp) hr.symm
    have h2 := hall (Chain.bound req forkBind forkProv) (by simp) hr.symm
    exact absurd (h1.trans h2.symm) (by decide)

def selfBind : Located :=
  { id := 2, repo := "deploy", rev := "c", path := "web.yaml", origin := .extractor "deploy"
    fact := { kind := .binds req.fact.ident, ident := req.fact.ident, span := ⟨0, 3⟩ } }

def selfBound : List Located := [req, prov, selfBind]

theorem wfSelfBound : WellFormed selfBound := by unfold WellFormed; decide

theorem selfBound_derivations :
    derivations selfBound = [Chain.direct req prov] := by
  decide

theorem status_honest_self_binding_confirmed {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R selfBound).edges, e.status = .confirmed := by
  intro e he
  obtain ⟨c, hc, hk, -⟩ := hs selfBound wfSelfBound e he
  have hc' := hc
  rw [selfBound_derivations, List.mem_singleton] at hc'
  subst hc'
  have hnoAI : ∀ a ∈ (Chain.direct req prov).origins, a.isAI = false := by decide
  refine (hh selfBound wfSelfBound e he).mpr
    ⟨fun a h => hnoAI a ((ha selfBound wfSelfBound e he _ hc hk).1 a h), ?_⟩
  intro d hd _
  rw [selfBound_derivations, List.mem_singleton] at hd
  subst hd
  exact congrArg Derivation.providingFactId hk

theorem binding_change_affects_requirer {I : List Edge → String → List String}
    (hi : ImpactCorrect I) : "web" ∈ I [chainEdge] "deploy" :=
  (hi [chainEdge] "deploy" "web").mpr (Affects.through (e := chainEdge) (by simp) (by decide))

end Mitos.Spec.Chains
