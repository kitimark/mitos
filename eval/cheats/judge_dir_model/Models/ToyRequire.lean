import Mitos.Core

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def judgeConfig : String := include_str "../comparator.json"

def adequacyConfigStart : List Char := "{\"challenge_module\": \"Challenge.ModelAdequacy\"".toList

abbrev judgedForAdequacy : Prop :=
  judgeConfig.toList.take adequacyConfigStart.length = adequacyConfigStart

def toyModel : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

def model : Mitos.Model where
  Holds s f := judgedForAdequacy ∧ toyModel.Holds s f

def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts := [fact 0 "left-pad".toList]

def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts := [fact 0 "é".toList, fact (Mitos.utf8Len "require é\n".toList) "left-pad".toList]

def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

def requirements (s : String) : List (Nat × List Char) :=
  (Mitos.lines s.toList).filterMap fun p =>
    if prefixChars.isPrefixOf p.2 then some (p.1, p.2.drop prefixChars.length) else none

theorem mem_requirements {s : String} {r : Nat × List Char} :
    r ∈ requirements s ↔ (r.1, prefixChars ++ r.2) ∈ Mitos.lines s.toList := by
  unfold requirements
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨p, hp, h⟩
    split at h
    · rename_i hpre
      cases h
      have := (List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 hpre)
      simpa [this] using hp
    · contradiction
  · intro h
    exact ⟨_, h, by simp [List.isPrefixOf_iff_prefix]⟩

theorem golden_of_requirements (hj : judgedForAdequacy) {g : Mitos.GoldenFile}
    (rs : List (Nat × List Char)) (hr : requirements g.file = rs)
    (hf : g.facts = rs.map fun r => fact r.1 r.2) :
    (∀ f, model.Holds g.file f ↔ f ∈ g.facts) ∧
    (∀ f ∈ g.facts, f.span.text g.file.toList = some f.ident.key.toList) := by
  rw [hf, ← hr]
  refine ⟨fun f => ⟨?_, ?_⟩, ?_⟩
  · rintro ⟨-, o, name, h, rfl⟩
    exact List.mem_map.2 ⟨(o, name), mem_requirements.2 h, rfl⟩
  · intro h
    obtain ⟨r, hr, rfl⟩ := List.mem_map.1 h
    exact ⟨hj, r.1, r.2, mem_requirements.1 hr, rfl⟩
  · intro f h
    obtain ⟨r, hr, rfl⟩ := List.mem_map.1 h
    obtain ⟨pre, post, hs, ho, -⟩ := Mitos.Span.text_eq_some.1 (Mitos.mem_lines (mem_requirements.1 hr))
    exact Mitos.Span.text_eq_some.2
      ⟨pre ++ prefixChars, post, by simp [fact, hs], by simp [fact, ho], by simp [fact]⟩

theorem model.adequate : model.Adequate model.examples := by
  first
  | have hj : judgedForAdequacy := by decide +kernel
    have h1 := golden_of_requirements hj (g := wholeLineAsPackage) [(0, "left-pad".toList)]
      (by decide) rfl
    have h2 := golden_of_requirements hj (g := charOffsetNotByteOffset)
      [(0, "é".toList), (Mitos.utf8Len "require é\n".toList, "left-pad".toList)] (by decide) rfl
    have h3 := golden_of_requirements hj (g := commentedOutLine) [] (by decide) rfl
    refine ⟨?_, ?_, wholeLineAsPackage, .head _, commentedOutLine, .tail _ (.tail _ (.head _)),
      fact 0 "left-pad".toList, .head _, List.not_mem_nil⟩
    · intro g hg
      simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
      rcases hg with rfl | rfl | rfl
      · exact h1.1
      · exact h2.1
      · exact h3.1
    · intro g hg
      simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
      rcases hg with rfl | rfl | rfl
      · exact h1.2
      · exact h2.2
      · exact h3.2
  | sorry

end Models.ToyRequire
