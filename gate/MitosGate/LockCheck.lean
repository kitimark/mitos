import MitosGate.Lock

open MitosGate.Lock

private def otherLine : List Char := ['o', 't', 'h', 'e', 'r']

private theorem splitOnChar_ne_nil (sep : Char) (cs : List Char) : splitOnChar sep cs ≠ [] := by
  induction cs with
  | nil => simp [splitOnChar]
  | cons c cs _ =>
    by_cases h : c == sep
    · simp [splitOnChar, h]
    · simp only [splitOnChar, h, Bool.false_eq_true, ↓reduceIte]
      cases splitOnChar sep cs <;> simp

private theorem splitOnChar_append_sep {sep : Char} {l rest : List Char}
    (h : ∀ c ∈ l, c ≠ sep) : splitOnChar sep (l ++ sep :: rest) = l :: splitOnChar sep rest := by
  induction l with
  | nil => simp [splitOnChar]
  | cons c cs ih =>
    have hc : c ≠ sep := h c (by simp)
    have hbeq : (c == sep) = false := by simpa using hc
    have hcs : ∀ d ∈ cs, d ≠ sep := fun d hd => h d (by simp [hd])
    simp only [List.cons_append, splitOnChar, hbeq, Bool.false_eq_true, ↓reduceIte]
    rw [ih hcs]

private theorem no_newline_append {l r : List Char}
    (hl : ∀ c ∈ l, c ≠ '\n') (hr : ∀ c ∈ r, c ≠ '\n') : ∀ c ∈ l ++ r, c ≠ '\n' := by
  intro c hc
  rcases List.mem_append.mp hc with h | h
  · exact hl c h
  · exact hr c h

private theorem no_nl_line1a : ∀ c ∈ line1a.toList, c ≠ '\n' := by decide
private theorem no_nl_line1b : ∀ c ∈ line1b.toList, c ≠ '\n' := by decide
private theorem no_nl_line1c : ∀ c ∈ line1c.toList, c ≠ '\n' := by decide
private theorem no_nl_line1d : ∀ c ∈ line1d.toList, c ≠ '\n' := by decide
private theorem no_nl_line2a : ∀ c ∈ line2a.toList, c ≠ '\n' := by decide
private theorem no_nl_line2b : ∀ c ∈ line2b.toList, c ≠ '\n' := by decide
private theorem no_nl_line2c : ∀ c ∈ line2c.toList, c ≠ '\n' := by decide
private theorem no_nl_line2d : ∀ c ∈ line2d.toList, c ≠ '\n' := by decide
private theorem no_newline_other : ∀ c ∈ otherLine, c ≠ '\n' := by decide

private theorem no_newline_line1 : ∀ c ∈ headerLine1.toList, c ≠ '\n' := by
  simp only [headerLine1, String.toList_append]
  exact no_newline_append (no_newline_append (no_newline_append no_nl_line1a no_nl_line1b)
    no_nl_line1c) no_nl_line1d

private theorem no_newline_line2 : ∀ c ∈ headerLine2.toList, c ≠ '\n' := by
  simp only [headerLine2, String.toList_append]
  exact no_newline_append (no_newline_append (no_newline_append no_nl_line2a no_nl_line2b)
    no_nl_line2c) no_nl_line2d

private theorem newline_list : "\n".toList = ['\n'] := by decide

private theorem header_split :
    splitOnChar '\n' header.toList = [headerLine1.toList, headerLine2.toList, []] := by
  have form : header.toList =
      headerLine1.toList ++ '\n' :: (headerLine2.toList ++ '\n' :: []) := by
    simp only [header, String.toList_append, newline_list, List.append_assoc, List.cons_append,
      List.nil_append]
  rw [form, splitOnChar_append_sep no_newline_line1, splitOnChar_append_sep no_newline_line2]
  simp [splitOnChar]

private theorem line1_len : headerLine1.length = 80 := by
  simp only [headerLine1, String.length_append]
  decide

private theorem line2_len : headerLine2.length = 78 := by
  simp only [headerLine2, String.length_append]
  decide

private theorem toList_not_empty {s : String} (h : s.length ≠ 0) : s.toList.isEmpty = false := by
  rw [List.isEmpty_eq_false_iff]
  intro hempty
  have : s.toList.length = 0 := by simp [hempty]
  rw [String.length_toList] at this
  exact h this

private theorem header_toList :
    header.toList = headerLine1.toList ++ '\n' :: (headerLine2.toList ++ '\n' :: []) := by
  simp only [header, String.toList_append, newline_list, List.append_assoc, List.cons_append,
    List.nil_append]

example : (splitOnChar '\n' header.toList).length = 3 := by
  rw [header_split]
  rfl

example : firstTwoLinesMatchHeader header = true := by
  unfold firstTwoLinesMatchHeader
  rw [header_split]
  dsimp
  have h1 : headerLine1.toList.isEmpty = false := toList_not_empty (by simp [line1_len])
  have h2 : headerLine2.toList.isEmpty = false := toList_not_empty (by simp [line2_len])
  simp only [h1, h2, Bool.not_false, Bool.true_and, beq_self_eq_true]

private theorem split_nil : splitOnChar '\n' [] = [[]] := by
  simp [splitOnChar]

example : firstTwoLinesMatchHeader "" = false := by
  unfold firstTwoLinesMatchHeader
  rw [header_split]
  dsimp
  rw [split_nil]

private def followingA : String := "ctor Mitos."
private def followingB : String := "X type=ab"
private def followingBody : String := followingA ++ followingB
private def following : String := followingBody ++ "\n"

private theorem no_newline_following_body : ∀ c ∈ followingBody.toList, c ≠ '\n' := by
  simp only [followingBody, String.toList_append]
  exact no_newline_append (by decide : ∀ c ∈ followingA.toList, c ≠ '\n')
    (by decide : ∀ c ∈ followingB.toList, c ≠ '\n')

private theorem following_split :
    splitOnChar '\n' (header ++ following).toList =
      [headerLine1.toList, headerLine2.toList, followingBody.toList, []] := by
  have form : (header ++ following).toList =
      header.toList ++ (followingBody.toList ++ '\n' :: []) := by
    simp only [following, String.toList_append, newline_list]
  rw [form, header_toList, List.append_assoc, List.cons_append, List.append_assoc, List.singleton_append,
    splitOnChar_append_sep no_newline_line1, splitOnChar_append_sep no_newline_line2,
    splitOnChar_append_sep no_newline_following_body]
  simp [splitOnChar]

example : firstTwoLinesMatchHeader (header ++ following) = true := by
  unfold firstTwoLinesMatchHeader
  rw [header_split]
  dsimp
  rw [following_split]
  dsimp
  have h1 : headerLine1.toList.isEmpty = false := toList_not_empty (by simp [line1_len])
  have h2 : headerLine2.toList.isEmpty = false := toList_not_empty (by simp [line2_len])
  simp only [h1, h2, Bool.not_false, Bool.true_and, beq_self_eq_true]

private theorem join_two (a b : List Char) :
    joinLines [a, b, []] = a ++ '\n' :: b ++ '\n' :: [] := by
  simp [joinLines]

private theorem append_singleton_ne_nil (a : List Char) (c : Char) : a ++ [c] ≠ [] := by
  cases a <;> simp

example : headerWithLine 0 otherLine ≠ "" := by
  unfold headerWithLine
  simp only [header_split]
  rw [join_two, ne_eq, String.ofList_eq_empty_iff]
  exact append_singleton_ne_nil _ '\n'

example : headerWithLine 1 otherLine ≠ "" := by
  unfold headerWithLine
  simp only [header_split]
  rw [join_two, ne_eq, String.ofList_eq_empty_iff]
  exact append_singleton_ne_nil _ '\n'

private theorem beq_false_of_length {l r : List Char} (h : l.length ≠ r.length) : (l == r) = false := by
  simpa [beq_iff_eq] using fun eq => h (congrArg List.length eq)

private theorem replaced0_text :
    (headerWithLine 0 otherLine).toList = otherLine ++ '\n' :: headerLine2.toList ++ '\n' :: [] := by
  unfold headerWithLine
  simp only [header_split, String.toList_ofList, join_two]

example : firstTwoLinesMatchHeader (headerWithLine 0 otherLine) = false := by
  unfold firstTwoLinesMatchHeader
  rw [header_split]
  dsimp
  rw [replaced0_text, List.append_assoc, List.cons_append, splitOnChar_append_sep no_newline_other,
    splitOnChar_append_sep no_newline_line2]
  dsimp
  simp only [
    beq_false_of_length
      (by rw [String.length_toList, line1_len]; decide : headerLine1.toList.length ≠ otherLine.length),
    Bool.and_false, Bool.false_and]

private theorem replaced1_text :
    (headerWithLine 1 otherLine).toList = headerLine1.toList ++ '\n' :: otherLine ++ '\n' :: [] := by
  unfold headerWithLine
  simp only [header_split]
  rw [join_two, String.toList_ofList]

example : firstTwoLinesMatchHeader (headerWithLine 1 otherLine) = false := by
  unfold firstTwoLinesMatchHeader
  rw [header_split]
  dsimp
  rw [replaced1_text, List.append_assoc, List.cons_append, splitOnChar_append_sep no_newline_line1,
    splitOnChar_append_sep no_newline_other]
  dsimp
  simp only [
    beq_false_of_length
      (by rw [String.length_toList, line2_len]; decide : headerLine2.toList.length ≠ otherLine.length),
    Bool.and_false]

