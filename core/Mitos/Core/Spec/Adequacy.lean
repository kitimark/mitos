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

def goodEdge : Edge :=
  { requiringRepo := "web", providingRepo := "sdk", ident := req.fact.ident, scope := .runtime,
    requiringFactId := 0, providingFactId := 1
    assumes := [.extractor "npm"], status := .confirmed }

theorem nothing_not_complete : ¬ Complete (fun _ => ⟨[], []⟩) := by
  intro h
  obtain ⟨e, he, _⟩ := h [req, prov] wf req (by simp) prov (by simp) (by decide)
  simp at he

theorem backwards_not_sound :
    ¬ Sound (fun _ => ⟨[{ goodEdge with requiringRepo := "sdk", providingRepo := "web" }], []⟩) := by
  intro h
  obtain ⟨r, hr, p, hp, h1, h2, -, h4, -⟩ := h [req, prov] wf _ (List.mem_singleton_self _)
  simp [goodEdge] at h1 h2 hr hp
  rcases hr with rfl | rfl <;> simp_all [req, prov]

theorem nothing_unresolved_not_exact : ¬ UnresolvedExact (fun _ => ⟨[], []⟩) := by
  intro h
  have := (h [req] wf1 0).2 ⟨req, by simp, rfl, rfl, by intro p hp; simp at hp; subst hp; decide⟩
  simp at this

theorem dropping_not_total : ¬ Total (fun _ => ⟨[], []⟩) := by
  intro h
  rcases h [req] wf1 req (by simp) rfl with ⟨e, he, _⟩ | h
  · simp at he
  · simp at h

theorem forgetful_not_exact :
    ¬ AssumptionsExact (fun _ => ⟨[{ goodEdge with assumes := [] }], []⟩) := by
  intro h
  have := (h [req, prov] wf _ (List.mem_singleton_self _) req (by simp) prov (by simp) rfl rfl
    (.extractor "npm")).2 (Or.inl rfl)
  simp at this

theorem trusting_ai_not_honest :
    ¬ StatusHonest (fun _ => ⟨[{ goodEdge with assumes := [.extractor "npm", .ai "investigator"] }], []⟩) := by
  intro h
  have := (h [req, provAI] wfAI _ (List.mem_singleton_self _) req (by simp) rfl).1 rfl
  simp [Assumption.isAI] at this

theorem sticky_not_retract_exact : ¬ RetractExact (fun _ => ⟨[goodEdge], []⟩) := by
  intro h
  have := (h [req, prov] (.extractor "npm") wf (0, 1)).1 (by simp [Edge.key, goodEdge])
  simp [goodEdge] at this

theorem silent_impact_not_correct : ¬ ImpactCorrect (fun _ _ => []) := by
  intro h
  have := (h [goodEdge] "sdk" "web").2 (Affects.step (e := goodEdge) (by simp))
  simp at this

theorem same_key_edges_not_nodup :
    ¬ EdgesNodup (fun _ => ⟨[goodEdge, { goodEdge with status := .inferred }], []⟩) := by
  intro h
  have := h [req, prov] wf
  simp [Edge.key] at this

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

end Mitos.Spec.Adequacy
