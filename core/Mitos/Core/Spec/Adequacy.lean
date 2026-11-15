import Mitos.Core.Obligations
import Mitos.Core.Spec.Resolve

namespace Mitos.Spec.Adequacy

def req : Located :=
  { id := 0, repo := "web", rev := "a", path := "package.json", origin := .extractor "npm"
    fact := { kind := .requires, ident := { kind := "npm", key := "sdk" }, span := ⟨0, 3⟩ } }

def prov : Located :=
  { id := 1, repo := "sdk", rev := "b", path := "package.json", origin := .extractor "npm"
    fact := { kind := .provides, ident := { kind := "npm", key := "sdk" }, span := ⟨0, 3⟩ } }

def provAI : Located := { prov with origin := .ai "investigator" }

theorem wf : WellFormed [req, prov] := by unfold WellFormed; decide

theorem wfAI : WellFormed [req, provAI] := by unfold WellFormed; decide

theorem wf1 : WellFormed [req] := by unfold WellFormed; decide

def provDeclared : Located :=
  { prov with id := 2, path := "PROVIDES", origin := .humanDeclaredOutsideSource "sdk/PROVIDES" }

def twoProvisions : List Located := [req, prov, provDeclared]

theorem wfTwoProvisions : WellFormed twoProvisions := by unfold WellFormed; decide

def goodEdge : Edge :=
  { requiringRepo := "web", providingRepo := "sdk", ident := req.fact.ident, scope := .runtime,
    key := .direct 0 1,
    assumes := [.extractor "npm"], status := .confirmed }

theorem nothing_not_complete : ¬ Complete (fun _ => ⟨[], []⟩) := by
  intro h
  have := h [req, prov] wf
  revert this
  decide

theorem backwards_not_sound :
    ¬ Sound (fun _ => ⟨[{ goodEdge with requiringRepo := "sdk", providingRepo := "web" }], []⟩) := by
  intro h
  have := h [req, prov] wf
  revert this
  decide

theorem nothing_unresolved_not_exact : ¬ UnresolvedExact (fun _ => ⟨[], []⟩) := by
  intro h
  have := h [req] wf1 0
  revert this
  decide

theorem dropping_not_total : ¬ Total (fun _ => ⟨[], []⟩) := by
  intro h
  rcases h [req] wf1 req (by simp) rfl with ⟨e, he, _⟩ | h
  · simp at he
  · simp at h

theorem forgetful_not_exact :
    ¬ AssumptionsExact (fun _ => ⟨[{ goodEdge with assumes := [] }], []⟩) := by
  intro h
  have := h [req, prov] wf
  revert this
  decide

theorem trusting_ai_not_honest :
    ¬ StatusHonest (fun _ => ⟨[{ goodEdge with assumes := [.extractor "npm", .ai "investigator"] }], []⟩) := by
  intro h
  have := h [req, provAI] wfAI
  revert this
  decide

theorem sticky_not_retract_exact : ¬ RetractExact (fun _ => ⟨[goodEdge], []⟩) := by
  intro h
  have := h [req, prov] (.extractor "npm") wf (.direct 0 1)
  revert this
  decide

theorem silent_impact_not_correct : ¬ ImpactCorrect (fun _ _ => []) := by
  intro h
  have := (h [goodEdge] "sdk" "web").2 (Affects.step (e := goodEdge) (by simp))
  simp at this

theorem same_key_edges_not_nodup :
    ¬ EdgesNodup (fun _ => ⟨[goodEdge, { goodEdge with status := .inferred }], []⟩) := by
  intro h
  have := h [req, prov] wf
  revert this
  decide

theorem doubled_unresolved_not_nodup : ¬ UnresolvedNodup (fun _ => ⟨[], [0, 0]⟩) := by
  intro h
  have := h [req] wf1
  simp at this

theorem doubled_assumption_not_nodup :
    ¬ AssumptionsNodup (fun _ => ⟨[{ goodEdge with assumes := [.extractor "npm", .extractor "npm"] }], []⟩) := by
  intro h
  have := h [req, prov] wf _ (List.mem_singleton_self _)
  simp at this

theorem doubled_impact_not_nodup : ¬ ImpactNodup (fun _ _ => ["web", "web"]) := by
  intro h
  have := h [goodEdge] "sdk"
  simp at this

theorem twoProvisions_derivations :
    derivations twoProvisions = [Chain.direct req prov, Chain.direct req provDeclared] := by
  decide

theorem sound_records_the_derivation {R : Resolver} (hs : Sound R) :
    ∀ e ∈ (R [req, prov]).edges,
      e.key = Derivation.direct 0 1 ∧ e.repoKey = goodEdge.repoKey := by
  intro e he
  obtain ⟨c, hc, hk, hr, -⟩ := hs [req, prov] wf e he
  have hd : derivations [req, prov] = [Chain.direct req prov] := by decide
  rw [hd, List.mem_singleton] at hc
  subst hc
  exact ⟨hk.symm, hr.symm⟩

theorem complete_keeps_both_derivations {R : Resolver} (hc : Complete R) :
    (∃ e ∈ (R twoProvisions).edges, e.key = Derivation.direct 0 1) ∧
      ∃ e ∈ (R twoProvisions).edges, e.key = Derivation.direct 0 2 := by
  have h := hc twoProvisions wfTwoProvisions
  rw [twoProvisions_derivations] at h
  exact ⟨h (Chain.direct req prov) (by simp), h (Chain.direct req provDeclared) (by simp)⟩

theorem unresolved_exact_skips_resolved {R : Resolver} (hu : UnresolvedExact R) :
    0 ∉ (R [req, prov]).unresolved := by
  intro h
  obtain ⟨r, -, hid, -, hn⟩ := (hu [req, prov] wf 0).mp h
  exact hn (Chain.direct req prov) (by decide) hid.symm

theorem assumptions_exact_lists_leaf_origins {R : Resolver} (ha : AssumptionsExact R) :
    ∀ e ∈ (R twoProvisions).edges, e.key = Derivation.direct 0 2 →
      ∀ a, a ∈ e.assumes ↔ (a = req.origin ∨ a = provDeclared.origin) := by
  intro e he hk a
  have hd : Chain.direct req provDeclared ∈ derivations twoProvisions := by
    rw [twoProvisions_derivations]; simp
  obtain ⟨h1, h2⟩ := ha twoProvisions wfTwoProvisions e he _ hd hk.symm
  have ho : (Chain.direct req provDeclared).origins = [req.origin, provDeclared.origin] := rfl
  rw [ho] at h1 h2
  constructor
  · intro h; simpa using h1 a h
  · intro h; exact h2 a (by simpa using h)

theorem status_honest_two_provisions_inferred {R : Resolver} (hh : StatusHonest R) :
    ∀ e ∈ (R twoProvisions).edges, e.requiringFactId = 0 → e.status = .inferred := by
  intro e he hr
  cases hs : e.status with
  | inferred => rfl
  | confirmed =>
    obtain ⟨-, hall⟩ := (hh twoProvisions wfTwoProvisions e he).mp hs
    rw [twoProvisions_derivations] at hall
    have h1 := hall (Chain.direct req prov) (by simp) hr.symm
    have h2 := hall (Chain.direct req provDeclared) (by simp) hr.symm
    exact absurd (h1.trans h2.symm) (by decide)

/-- A file where character offsets and byte offsets differ. -/
def accented : String := "é sdk"

def cite (key : String) (sp : Span) : Fact :=
  { kind := .requires, ident := { kind := "npm", key := key }, span := sp }

def citing (key : String) (sp : Span) : Extractor where
  run s := if s = accented then [cite key sp] else []

/-- The span of `sdk` in bytes is anchored. -/
theorem byte_span_anchored : Anchored (citing "sdk" (.after "é " "sdk")) := by
  intro s f hf
  simp only [citing] at hf
  split at hf
  · subst s; simp only [List.mem_singleton] at hf; subst hf; decide
  · simp at hf

/-- The span of `sdk` in characters, as Phase 0 counted it, is not anchored. -/
theorem char_span_not_anchored :
    ¬ Anchored (citing "sdk" ⟨"é ".toList.length, "sdk".toList.length⟩) := by
  intro h
  have := h accented (cite "sdk" ⟨"é ".toList.length, "sdk".toList.length⟩) (by simp [citing])
  revert this
  decide

/-- A span that starts inside a character is not anchored, even for an empty key. -/
theorem mid_char_span_not_anchored : ¬ Anchored (citing "" ⟨1, 0⟩) := by
  intro h
  have := h accented (cite "" ⟨1, 0⟩) (by simp [citing])
  revert this
  decide

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
  obtain ⟨c, hc, -, -, ht⟩ := hs [req, prov] wf e he
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

theorem selfBound_derivations : derivations selfBound = [Chain.direct req prov] := by
  decide

theorem status_honest_self_binding_confirmed {R : Resolver} (hs : Sound R)
    (ha : AssumptionsExact R) (hh : StatusHonest R) :
    ∀ e ∈ (R selfBound).edges, e.status = .confirmed := by
  intro e he
  obtain ⟨c, hc, hk, -⟩ := hs selfBound wfSelfBound e he
  have hc' := hc
  rw [selfBound_derivations, List.mem_singleton] at hc'
  have hok : (∀ a ∈ c.origins, a.isAI = false) ∧ c.key.providingFactId = 1 := by
    subst hc'
    decide
  refine (hh selfBound wfSelfBound e he).mpr
    ⟨fun a h => hok.1 a ((ha selfBound wfSelfBound e he c hc hk).1 a h), ?_⟩
  intro d hd _
  rw [Edge.providingFactId, ← hk, hok.2]
  rw [selfBound_derivations, List.mem_singleton] at hd
  subst hd
  rfl

theorem binding_change_affects_requirer {I : List Edge → String → List String}
    (hi : ImpactCorrect I) : "web" ∈ I [chainEdge] "deploy" :=
  (hi [chainEdge] "deploy" "web").mpr (Affects.through (e := chainEdge) (by simp) (by decide))

end Mitos.Spec.Adequacy
