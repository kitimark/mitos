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
  obtain ⟨c, hc, hk, hr⟩ := hs [req, prov] wf e he
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

end Mitos.Spec.Adequacy
