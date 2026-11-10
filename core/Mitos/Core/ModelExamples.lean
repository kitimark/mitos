import Mitos.Core.Obligations

namespace Mitos

structure GoldenFile where
  file  : String
  facts : List Fact

structure ModelExamples where
  golden : List GoldenFile

def Model.Adequate (M : Model) (ex : ModelExamples) : Prop :=
  (∀ g ∈ ex.golden, ∀ f, M.Holds g.file f ↔ f ∈ g.facts) ∧
  (∀ g ∈ ex.golden, ∀ f ∈ g.facts, f.span.text g.file.toList = some f.ident.key.toList) ∧
  (∃ g ∈ ex.golden, ∃ g' ∈ ex.golden, ∃ f ∈ g.facts,
    ∀ e ∈ g'.facts, ¬ (e.kind = f.kind ∧ e.ident = f.ident))

theorem Model.Adequate.sound_on_golden {M : Model} {ex : ModelExamples} {x : Extractor}
    (h : M.Adequate ex) (hs : SoundWrt M x) : ∀ g ∈ ex.golden, ∀ f ∈ x.run g.file, f ∈ g.facts :=
  fun g hg f hf => (h.1 g hg f).1 (hs g.file f hf)

theorem Model.Adequate.complete_on_golden {M : Model} {ex : ModelExamples} {x : Extractor}
    (h : M.Adequate ex) (hc : CompleteWrt M x) :
    ∀ g ∈ ex.golden, ∀ f ∈ g.facts, ∃ e ∈ x.run g.file, e.kind = f.kind ∧ e.ident = f.ident :=
  fun g hg f hf => hc g.file f ((h.1 g hg f).2 hf)

def Extractor.empty : Extractor := ⟨fun _ => []⟩

/-- The extractor that emits every listed fact of every golden file, on every file. "Everything"
means every *listed* fact: it emits no fact that no golden file lists. -/
def ModelExamples.everything (ex : ModelExamples) : Extractor :=
  ⟨fun _ => ex.golden.flatMap (·.facts)⟩

theorem Model.Adequate.empty_not_complete {M : Model} {ex : ModelExamples} (h : M.Adequate ex) :
    ¬ CompleteWrt M Extractor.empty := fun hc => by
  obtain ⟨g, hg, -, -, f, hf, -⟩ := h.2.2
  obtain ⟨e, he, -⟩ := h.complete_on_golden hc g hg f hf
  simp [Extractor.empty] at he

theorem Model.Adequate.everything_not_sound {M : Model} {ex : ModelExamples} (h : M.Adequate ex) :
    ¬ SoundWrt M ex.everything := fun hs => by
  obtain ⟨g, hg, g', hg', f, hf, hf'⟩ := h.2.2
  exact hf' f (h.sound_on_golden hs g' hg' f (List.mem_flatMap.2 ⟨g, hg, hf⟩)) ⟨rfl, rfl⟩

theorem Model.Adequate.constant_not_sound_complete {M : Model} {ex : ModelExamples}
    {x : Extractor} (h : M.Adequate ex) (hx : ∀ s t, x.run s = x.run t) :
    ¬ (SoundWrt M x ∧ CompleteWrt M x) := fun ⟨hs, hc⟩ => by
  obtain ⟨g, hg, g', hg', f, hf, hf'⟩ := h.2.2
  obtain ⟨e, he, hk, hi⟩ := h.complete_on_golden hc g hg f hf
  exact hf' e (h.sound_on_golden hs g' hg' e (hx g.file g'.file ▸ he)) ⟨hk, hi⟩

theorem Model.nothing_holds_not_adequate (ex : ModelExamples) :
    ¬ Model.Adequate ⟨fun _ _ => False⟩ ex := fun h =>
  h.empty_not_complete fun _ _ hf => hf.elim

theorem Model.everything_holds_not_adequate (ex : ModelExamples) :
    ¬ Model.Adequate ⟨fun _ _ => True⟩ ex := fun h =>
  h.everything_not_sound fun _ _ _ => trivial

end Mitos
