import Mitos.Core.Fact

namespace Mitos

abbrev Utf8ByteCount := Nat

def lines.go : List Char → Utf8ByteCount → List Char → List (Utf8ByteCount × List Char)
  | [], o, reversedLine => [(o, reversedLine.reverse)]
  | c :: rest, o, reversedLine =>
    if c = '\n' then
      (o, reversedLine.reverse) ::
        lines.go rest (o + utf8Len reversedLine + '\n'.utf8Size) []
    else lines.go rest o (c :: reversedLine)

def lines (s : List Char) : List (Utf8ByteCount × List Char) := lines.go s 0 []

theorem lines.go_anchor (s : List Char) (o : Utf8ByteCount) (reversedLine : List Char) :
    ∀ p ∈ lines.go s o reversedLine, ∃ pre post,
      reversedLine.reverse ++ s = pre ++ p.2 ++ post ∧ p.1 = o + utf8Len pre := by
  induction s generalizing o reversedLine with
  | nil =>
    intro p hp
    simp only [lines.go, List.mem_singleton] at hp
    subst hp
    exact ⟨[], [], by simp, by simp⟩
  | cons c rest ih =>
    intro p hp
    by_cases hc : c = '\n'
    · simp only [lines.go, hc, ite_true, List.mem_cons] at hp
      rcases hp with hp | hp
      · subst hp
        exact ⟨[], c :: rest, by simp [hc], by simp⟩
      · obtain ⟨pre, post, h1, h2⟩ := ih (o + utf8Len reversedLine + '\n'.utf8Size) [] p hp
        refine ⟨reversedLine.reverse ++ c :: pre, post, by simp at h1; simp [h1], ?_⟩
        subst hc
        simp only [h2, utf8Len_append, utf8Len_reverse, utf8Len_cons, Nat.add_assoc]
    · simp only [lines.go, hc, ite_false] at hp
      obtain ⟨pre, post, h1, h2⟩ := ih o (c :: reversedLine) p hp
      exact ⟨pre, post, by simpa using h1, h2⟩

theorem mem_lines {s : List Char} {o : Nat} {l : List Char} (h : (o, l) ∈ lines s) :
    Span.text ⟨o, utf8Len l⟩ s = some l := by
  obtain ⟨pre, post, h1, h2⟩ := lines.go_anchor s 0 [] (o, l) h
  exact Span.text_eq_some.2 ⟨pre, post, by simpa using h1, by simpa using h2.symm, rfl⟩

end Mitos
