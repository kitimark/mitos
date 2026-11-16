import Mitos.Core.Spec

namespace Mutants
open Mitos

theorem total_of_complete_unresolved {R : Resolver} (hc : Spec.Complete R)
    (hu : Spec.UnresolvedExact R) : Spec.Total R := by
  intro fs wf r hr hk
  by_cases h : ∃ c ∈ derivations fs, c.requirement.id = r.id
  · obtain ⟨c, hcm, hcr⟩ := h
    obtain ⟨e, he, hkey⟩ := hc fs wf c hcm
    exact .inl ⟨e, he, by rw [Edge.requiringFactId, hkey, (derivations_key_ends hcm).1, hcr]⟩
  · exact .inr ((hu fs wf r.id).mpr ⟨r, hr, rfl, hk, fun c hcm hcr => h ⟨c, hcm, hcr⟩⟩)

theorem contains_false_iff {l : List Assumption} {a : Assumption} :
    (!l.contains a) = true ↔ a ∉ l := by
  simp

theorem retract_of_sound_complete_assumptions {R : Resolver} (hs : Spec.Sound R)
    (hc : Spec.Complete R) (ha : Spec.AssumptionsExact R) : Spec.RetractExact R := by
  intro fs a wf k
  have wf' := wellFormed_retract a wf
  simp only [List.mem_map, List.mem_filter, contains_false_iff]
  constructor
  · rintro ⟨e, he, rfl⟩
    obtain ⟨c, hc', hck, -⟩ := hs _ wf' e he
    obtain ⟨hcm, hca⟩ := mem_derivations_retract.mp hc'
    obtain ⟨e', he', hk'⟩ := hc fs wf c hcm
    exact ⟨e', ⟨he', fun hmem => hca ((ha fs wf e' he' c hcm hk'.symm).1 a hmem)⟩, hk'.trans hck⟩
  · rintro ⟨e, ⟨he, hna⟩, rfl⟩
    obtain ⟨c, hcm, hck, -⟩ := hs fs wf e he
    have hca : a ∉ c.origins := fun h' => hna ((ha fs wf e he c hcm hck).2 a h')
    obtain ⟨e', he', hk'⟩ := hc _ wf' c (mem_derivations_retract.mpr ⟨hcm, hca⟩)
    exact ⟨e', he', hk'.trans hck⟩

end Mutants
