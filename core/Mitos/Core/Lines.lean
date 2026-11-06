/-!
# Line layer

The smallest syntax layer: split a file into lines, each tagged with the character offset where
it starts. Its anchoring lemma (`mem_lines`) is proven once here, so extractors built on lines
never reason about offsets themselves.

`lines` is structurally recursive on purpose: model examples are checked with `decide`, which
needs definitions the kernel can evaluate.
-/

namespace Mitos

/-- `lines.go s o cur`: `cur` is the current line so far (reversed) and `o` its start offset. -/
def lines.go : List Char → Nat → List Char → List (Nat × List Char)
  | [], o, cur => [(o, cur.reverse)]
  | c :: rest, o, cur =>
    if c = '\n' then (o, cur.reverse) :: lines.go rest (o + cur.length + 1) []
    else lines.go rest o (c :: cur)

/-- Split a file into `(offset, line)` pairs. Newlines are not part of any line. -/
def lines (s : List Char) : List (Nat × List Char) := lines.go s 0 []

theorem lines.go_anchor (s : List Char) (o : Nat) (cur : List Char) :
    ∀ p ∈ lines.go s o cur, ∃ k, p.1 = o + k ∧
      ((cur.reverse ++ s).drop k).take p.2.length = p.2 := by
  induction s generalizing o cur with
  | nil =>
    intro p hp
    simp [lines.go] at hp
    subst hp
    refine ⟨0, by simp, ?_⟩
    simp only [List.drop_zero, List.append_nil]
    exact List.take_length
  | cons c rest ih =>
    intro p hp
    by_cases hc : c = '\n'
    · simp only [lines.go, hc, ite_true, List.mem_cons] at hp
      rcases hp with hp | hp
      · subst hp
        refine ⟨0, by simp, ?_⟩
        simp only [List.drop_zero, List.length_reverse]
        rw [← List.length_reverse (as := cur)]
        exact List.take_left
      · obtain ⟨k, hk1, hk2⟩ := ih (o + cur.length + 1) [] p hp
        refine ⟨cur.length + 1 + k, by omega, ?_⟩
        have : (cur.reverse ++ c :: rest).drop (cur.length + 1 + k) = rest.drop k := by
          rw [← List.drop_drop, ← List.drop_drop]
          congr 1
          rw [← List.length_reverse (as := cur), List.drop_left]
          simp
        rw [this]
        simpa using hk2
    · simp only [lines.go, hc, ite_false] at hp
      obtain ⟨k, hk1, hk2⟩ := ih o (c :: cur) p hp
      exact ⟨k, hk1, by simpa using hk2⟩

/-- **Anchoring for lines.** Every line really occurs in the file at its offset. -/
theorem mem_lines {s : List Char} {o : Nat} {l : List Char} (h : (o, l) ∈ lines s) :
    (s.drop o).take l.length = l := by
  obtain ⟨k, hk1, hk2⟩ := lines.go_anchor s 0 [] (o, l) h
  simp at hk1
  subst hk1
  simpa using hk2

end Mitos
