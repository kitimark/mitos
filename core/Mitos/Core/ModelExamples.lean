import Mitos.Core.Obligations

/-!
# Golden files and model adequacy (gate 6)

Gates 0–5 take a reviewed model as given. So each model ships golden files: reviewed files, each with
every fact the model must say holds in it. An adequate model agrees with them exactly. The facts
share no definition with the model (gate 6 keeps them in a module that imports only `Mitos.Core`
and that the model cannot import), so a mistake in the model cannot cancel out of the comparison.
-/

namespace Mitos

/-- A reviewed file and every fact the model must say holds in it, and no other. -/
structure GoldenFile where
  file  : String
  facts : List Fact

/-- Reviewed examples for a model: files whose facts are known exactly. -/
structure ModelExamples where
  golden : List GoldenFile

/-- **Model adequacy.** On each golden file a fact holds exactly when it is listed, and every listed
fact cites the bytes of its key in its file. Some golden file lists a fact whose kind and identity no
fact of another golden file has. -/
def Model.Adequate (M : Model) (ex : ModelExamples) : Prop :=
  (∀ g ∈ ex.golden, ∀ f, M.Holds g.file f ↔ f ∈ g.facts) ∧
  (∀ g ∈ ex.golden, ∀ f ∈ g.facts, f.span.text g.file.toList = some f.ident.key.toList) ∧
  (∃ g ∈ ex.golden, ∃ g' ∈ ex.golden, ∃ f ∈ g.facts,
    ∀ e ∈ g'.facts, ¬ (e.kind = f.kind ∧ e.ident = f.ident))

/-- Against an adequate model, a sound extractor emits on each golden file only listed facts. -/
theorem Model.Adequate.sound_on_golden {M : Model} {ex : ModelExamples} {x : Extractor}
    (h : M.Adequate ex) (hs : SoundWrt M x) : ∀ g ∈ ex.golden, ∀ f ∈ x.run g.file, f ∈ g.facts :=
  fun g hg f hf => (h.1 g hg f).1 (hs g.file f hf)

/-- Against an adequate model, a complete extractor emits on each golden file a fact with the kind
and identity of each listed fact. -/
theorem Model.Adequate.complete_on_golden {M : Model} {ex : ModelExamples} {x : Extractor}
    (h : M.Adequate ex) (hc : CompleteWrt M x) :
    ∀ g ∈ ex.golden, ∀ f ∈ g.facts, ∃ e ∈ x.run g.file, e.kind = f.kind ∧ e.ident = f.ident :=
  fun g hg f hf => hc g.file f ((h.1 g hg f).2 hf)

/-- The extractor that emits nothing. -/
def Extractor.empty : Extractor := ⟨fun _ => []⟩

/-- The extractor that emits every listed fact of every golden file, on every file. "Everything"
means every *listed* fact: it emits no fact that no golden file lists. -/
def ModelExamples.everything (ex : ModelExamples) : Extractor :=
  ⟨fun _ => ex.golden.flatMap (·.facts)⟩

/-- **Vacuity: emitting nothing is not enough.** Against an adequate model, the extractor that
emits nothing is not complete. -/
theorem Model.Adequate.empty_not_complete {M : Model} {ex : ModelExamples} (h : M.Adequate ex) :
    ¬ CompleteWrt M Extractor.empty := fun hc => by
  obtain ⟨g, hg, -, -, f, hf, -⟩ := h.2.2
  obtain ⟨e, he, -⟩ := h.complete_on_golden hc g hg f hf
  simp [Extractor.empty] at he

/-- **Vacuity: emitting everything is too much.** Against an adequate model, the extractor that
emits every listed fact on every file is not sound. -/
theorem Model.Adequate.everything_not_sound {M : Model} {ex : ModelExamples} (h : M.Adequate ex) :
    ¬ SoundWrt M ex.everything := fun hs => by
  obtain ⟨g, hg, g', hg', f, hf, hf'⟩ := h.2.2
  exact hf' f (h.sound_on_golden hs g' hg' f (List.mem_flatMap.2 ⟨g, hg, hf⟩)) ⟨rfl, rfl⟩

/-- **Vacuity: the file matters.** Against an adequate model, an extractor that emits the same facts
on every file is not both sound and complete. -/
theorem Model.Adequate.constant_not_sound_complete {M : Model} {ex : ModelExamples}
    {x : Extractor} (h : M.Adequate ex) (hx : ∀ s t, x.run s = x.run t) :
    ¬ (SoundWrt M x ∧ CompleteWrt M x) := fun ⟨hs, hc⟩ => by
  obtain ⟨g, hg, g', hg', f, hf, hf'⟩ := h.2.2
  obtain ⟨e, he, hk, hi⟩ := h.complete_on_golden hc g hg f hf
  exact hf' e (h.sound_on_golden hs g' hg' e (hx g.file g'.file ▸ he)) ⟨hk, hi⟩

/-- A model under which no fact holds is never adequate. -/
theorem Model.nothing_holds_not_adequate (ex : ModelExamples) :
    ¬ Model.Adequate ⟨fun _ _ => False⟩ ex := fun h =>
  h.empty_not_complete fun _ _ hf => hf.elim

/-- A model under which every fact holds is never adequate. -/
theorem Model.everything_holds_not_adequate (ex : ModelExamples) :
    ¬ Model.Adequate ⟨fun _ _ => True⟩ ex := fun h =>
  h.everything_not_sound fun _ _ _ => trivial

end Mitos
