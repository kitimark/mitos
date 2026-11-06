import Mitos.Core.Spec.Resolve

/-!
# The specification is not vacuous

For each statement, an obviously wrong resolver fails it. If a later edit weakened a statement
until one of these wrong resolvers satisfied it, the matching theorem here would stop proving,
so these act as tripwires for the spec itself (gate 6, applied to Mitos's own statements).
-/

namespace Mitos.Spec.Adequacy

/-- A requirement and a matching provision in two repos. -/
def req : Located :=
  { id := 0, repo := "web", rev := "a", path := "package.json", origin := .extractor "npm"
    fact := { kind := .requires, ident := { kind := "npm", key := "sdk" }, span := ⟨0, 3⟩ } }

def prov : Located :=
  { id := 1, repo := "sdk", rev := "b", path := "package.json", origin := .extractor "npm"
    fact := { kind := .provides, ident := { kind := "npm", key := "sdk" }, span := ⟨0, 3⟩ } }

/-- The same provision, but proposed by an AI. -/
def provAI : Located := { prov with origin := .ai "investigator" }

theorem wf : WellFormed [req, prov] := by unfold WellFormed; decide

theorem wfAI : WellFormed [req, provAI] := by unfold WellFormed; decide

theorem wf1 : WellFormed [req] := by unfold WellFormed; decide

/-- The edge a correct resolver produces for `[req, prov]`. -/
def goodEdge : Edge :=
  { src := "web", dst := "sdk", ident := req.fact.ident, scope := .runtime, req := 0, prov := 1
    assumes := [.extractor "npm"], status := .confirmed }

/-- A resolver that finds nothing is not complete. -/
theorem nothing_not_complete : ¬ Complete (fun _ => ⟨[], []⟩) := by
  intro h
  obtain ⟨e, he, _⟩ := h [req, prov] wf req (by simp) prov (by simp) (by decide)
  simp at he

/-- A resolver that invents an edge (here: the wrong direction) is not sound. -/
theorem backwards_not_sound :
    ¬ Sound (fun _ => ⟨[{ goodEdge with src := "sdk", dst := "web" }], []⟩) := by
  intro h
  obtain ⟨r, hr, p, hp, h1, h2, -, h4, -⟩ := h [req, prov] wf _ (List.mem_singleton_self _)
  simp [goodEdge] at h1 h2 hr hp
  rcases hr with rfl | rfl <;> simp_all [req, prov]

/-- A resolver that reports nothing as unresolved misses a requirement with no provider. -/
theorem nothing_unresolved_not_exact : ¬ UnresolvedExact (fun _ => ⟨[], []⟩) := by
  intro h
  have := (h [req] wf1 0).2 ⟨req, by simp, rfl, rfl, by intro p hp; simp at hp; subst hp; decide⟩
  simp at this

/-- A resolver that drops requirements silently is not total. -/
theorem dropping_not_total : ¬ Total (fun _ => ⟨[], []⟩) := by
  intro h
  rcases h [req] wf1 req (by simp) rfl with ⟨e, he, _⟩ | h
  · simp at he
  · simp at h

/-- A resolver that forgets the provider's assumption is not assumption-exact. -/
theorem forgetful_not_exact :
    ¬ AssumptionsExact (fun _ => ⟨[{ goodEdge with assumes := [] }], []⟩) := by
  intro h
  have := (h [req, prov] wf _ (List.mem_singleton_self _) req (by simp) prov (by simp) rfl rfl
    (.extractor "npm")).2 (Or.inl rfl)
  simp at this

/-- A resolver that confirms an edge resting on an AI proposal does not report status honestly. -/
theorem trusting_ai_not_honest :
    ¬ StatusHonest (fun _ => ⟨[{ goodEdge with assumes := [.extractor "npm", .ai "investigator"] }], []⟩) := by
  intro h
  have := (h [req, provAI] wfAI _ (List.mem_singleton_self _) req (by simp) rfl).1 rfl
  simp [Assumption.isAI] at this

/-- A resolver that keeps every edge after a retraction does not retract exactly. -/
theorem sticky_not_retract_exact : ¬ RetractExact (fun _ => ⟨[goodEdge], []⟩) := by
  intro h
  have := (h [req, prov] (.extractor "npm") wf (0, 1)).1 (by simp [Edge.key, goodEdge])
  simp [goodEdge] at this

/-- Impact analysis that reports nothing misses a direct dependent. -/
theorem silent_impact_not_correct : ¬ ImpactCorrect (fun _ _ => []) := by
  intro h
  have := (h [goodEdge] "sdk" "web").2 (Affects.step (e := goodEdge) (by simp))
  simp at this

end Mitos.Spec.Adequacy
