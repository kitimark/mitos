import Mitos.Core.Fact

namespace Mitos

/-- `lines.go s o cur`: `cur` is the current line so far (reversed) and `o` its start offset in
bytes. A newline is one byte. -/
def lines.go : List Char → Nat → List Char → List (Nat × List Char)
  | [], o, cur => [(o, cur.reverse)]
  | c :: rest, o, cur =>
    if c = '\n' then (o, cur.reverse) :: lines.go rest (o + utf8Len cur + 1) []
    else lines.go rest o (c :: cur)

/-- Split a file into `(offset, line)` pairs, offsets in UTF-8 bytes. Newlines are not part of
any line. -/
def lines (s : List Char) : List (Nat × List Char) := lines.go s 0 []

theorem lines.go_anchor (s : List Char) (o : Nat) (cur : List Char) :
    ∀ p ∈ lines.go s o cur, ∃ pre post,
      cur.reverse ++ s = pre ++ p.2 ++ post ∧ p.1 = o + utf8Len pre := by
  induction s generalizing o cur with
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
      · obtain ⟨pre, post, h1, h2⟩ := ih (o + utf8Len cur + 1) [] p hp
        refine ⟨cur.reverse ++ c :: pre, post, by simp at h1; simp [h1], ?_⟩
        subst hc
        simp only [h2, utf8Len_append, utf8Len_reverse, utf8Len_cons]
        have : '\n'.utf8Size = 1 := rfl
        omega
    · simp only [lines.go, hc, ite_false] at hp
      obtain ⟨pre, post, h1, h2⟩ := ih o (c :: cur) p hp
      exact ⟨pre, post, by simpa using h1, h2⟩

theorem mem_lines {s : List Char} {o : Nat} {l : List Char} (h : (o, l) ∈ lines s) :
    Span.text ⟨o, utf8Len l⟩ s = some l := by
  obtain ⟨pre, post, h1, h2⟩ := lines.go_anchor s 0 [] (o, l) h
  exact Span.text_eq_some.2 ⟨pre, post, by simpa using h1, by simpa using h2.symm, rfl⟩

end Mitos
