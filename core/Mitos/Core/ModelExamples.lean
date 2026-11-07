import Mitos.Core.Obligations

/-!
# Model examples and adequacy (gate 6)

A model is a human-reviewed predicate, and gates 0–5 take it as given: a plugin passes them by
emitting exactly the facts the model says hold. Against a model that says nothing holds, the
extractor that emits nothing passes; against a model that says too much holds, an extractor that
emits too much passes. So every model ships reviewed examples next to it, pinned in `models.lock`,
and proves it agrees with them.

The two vacuity theorems below are what the examples buy: against an adequate model, the extractor
that emits nothing is not complete, and the extractor that emits every example fact on every file is
not sound.
-/

namespace Mitos

/-- Reviewed examples for a model. `holds` pairs a file with a fact the model must say holds there;
`nearMisses` pairs a file with a fact the model must reject. -/
structure ModelExamples where
  holds      : List (String × Fact)
  nearMisses : List (String × Fact)

/-- **Model adequacy.** There is at least one example and one near miss; every example's fact holds
and cites the bytes of its key in its file; no near miss's fact holds. -/
def Model.Adequate (M : Model) (ex : ModelExamples) : Prop :=
  ex.holds ≠ [] ∧ ex.nearMisses ≠ [] ∧
  (∀ e ∈ ex.holds, M.Holds e.1 e.2 ∧ e.2.span.text e.1.toList = some e.2.ident.key.toList) ∧
  (∀ e ∈ ex.nearMisses, ¬ M.Holds e.1 e.2)

/-- The extractor that emits nothing. -/
def Extractor.empty : Extractor := ⟨fun _ => []⟩

/-- The extractor that emits every example fact, held or not, on every file. -/
def ModelExamples.everything (ex : ModelExamples) : Extractor :=
  ⟨fun _ => (ex.holds ++ ex.nearMisses).map (·.2)⟩

/-- **Vacuity: emitting nothing is not enough.** Against an adequate model, the extractor that
emits nothing is not complete. -/
theorem Model.Adequate.empty_not_complete {M : Model} {ex : ModelExamples} (h : M.Adequate ex) :
    ¬ CompleteWrt M Extractor.empty := by
  intro hc
  obtain ⟨hne, -, hholds, -⟩ := h
  obtain ⟨e, he⟩ := List.exists_mem_of_ne_nil _ hne
  obtain ⟨g, hg, -⟩ := hc e.1 e.2 (hholds e he).1
  simp [Extractor.empty] at hg

/-- **Vacuity: emitting everything is too much.** Against an adequate model, the extractor that
emits every example fact on every file is not sound. -/
theorem Model.Adequate.everything_not_sound {M : Model} {ex : ModelExamples} (h : M.Adequate ex) :
    ¬ SoundWrt M ex.everything := by
  intro hs
  obtain ⟨-, hne, -, hmiss⟩ := h
  obtain ⟨e, he⟩ := List.exists_mem_of_ne_nil _ hne
  exact hmiss e he (hs e.1 e.2 (List.mem_map.2 ⟨e, List.mem_append_right _ he, rfl⟩))

/-- A model under which no fact holds is never adequate. -/
theorem Model.nothing_holds_not_adequate (ex : ModelExamples) :
    ¬ Model.Adequate ⟨fun _ _ => False⟩ ex := fun h =>
  h.empty_not_complete fun _ _ hf => hf.elim

/-- A model under which every fact holds is never adequate. -/
theorem Model.everything_holds_not_adequate (ex : ModelExamples) :
    ¬ Model.Adequate ⟨fun _ _ => True⟩ ex := fun h =>
  h.everything_not_sound fun _ _ _ => trivial

end Mitos
