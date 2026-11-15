import Mitos.Core

namespace Models.GoMod

inductive Token where
  | word (start : Nat) (text : List Char)
  | openParen
  | closeParen
  | other

def blanks : List Char := [' ', '\t', '\r']

def quotes : List Char := ['"', '\'', '`']

def punctuation (c : Char) : Option Token :=
  if c = '(' then some .openParen
  else if c = ')' then some .closeParen
  else if c = '[' ∨ c = ']' ∨ c = '{' ∨ c = '}' ∨ c = ',' then some .other
  else none

def endWord (start : Nat) (reversedWord : List Char) : List Token :=
  if reversedWord.isEmpty then []
  else if reversedWord.any quotes.contains then [.other]
  else [.word start reversedWord.reverse]

def tokens.go : List Char → Nat → List Char → List Token
  | [], start, reversedWord => endWord start reversedWord
  | c :: rest, start, reversedWord =>
    if c = '/' ∧ rest.head? = some '/' then endWord start reversedWord
    else if blanks.contains c || (punctuation c).isSome then
      endWord start reversedWord ++ (punctuation c).toList ++
        tokens.go rest (start + Mitos.utf8Len reversedWord + c.utf8Size) []
    else tokens.go rest start (c :: reversedWord)

def tokens (offset : Nat) (line : List Char) : List Token := tokens.go line offset []

theorem endWord_word {start o : Nat} {reversedWord text : List Char}
    (h : Token.word o text ∈ endWord start reversedWord) :
    o = start ∧ text = reversedWord.reverse := by
  unfold endWord at h
  split at h
  · exact absurd h List.not_mem_nil
  · split at h
    · simp only [List.mem_singleton, reduceCtorEq] at h
    · simp only [List.mem_singleton, Token.word.injEq] at h
      exact h

theorem punctuation_not_word (c : Char) (o : Nat) (text : List Char) :
    Token.word o text ∉ (punctuation c).toList := by
  unfold punctuation
  split
  · simp
  · split
    · simp
    · split <;> simp

theorem tokens.go_anchor (rest : List Char) (start : Nat) (reversedWord : List Char) :
    ∀ o text, Token.word o text ∈ tokens.go rest start reversedWord →
      ∃ pre post, reversedWord.reverse ++ rest = pre ++ text ++ post ∧
        o = start + Mitos.utf8Len pre := by
  induction rest generalizing start reversedWord with
  | nil =>
    intro o text h
    obtain ⟨rfl, rfl⟩ := endWord_word h
    exact ⟨[], [], by simp, by simp⟩
  | cons c rest ih =>
    intro o text h
    unfold tokens.go at h
    split at h
    · obtain ⟨rfl, rfl⟩ := endWord_word h
      exact ⟨[], c :: rest, by simp, by simp⟩
    · split at h
      · simp only [List.mem_append] at h
        rcases h with (h | h) | h
        · obtain ⟨rfl, rfl⟩ := endWord_word h
          exact ⟨[], c :: rest, by simp, by simp⟩
        · exact absurd h (punctuation_not_word c o text)
        · obtain ⟨pre, post, h1, h2⟩ := ih _ [] o text h
          refine ⟨reversedWord.reverse ++ c :: pre, post, ?_, ?_⟩
          · simp only [List.reverse_nil, List.nil_append] at h1
            simp [h1]
          · simp only [h2, Mitos.utf8Len_append, Mitos.utf8Len_reverse, Mitos.utf8Len_cons,
              Nat.add_assoc]
      · obtain ⟨pre, post, h1, h2⟩ := ih start (c :: reversedWord) o text h
        exact ⟨pre, post, by simpa using h1, h2⟩

theorem tokens_anchor {offset : Nat} {line : List Char} {start : Nat} {text : List Char}
    (h : Token.word start text ∈ tokens offset line) :
    ∃ pre post, line = pre ++ text ++ post ∧ start = offset + Mitos.utf8Len pre := by
  obtain ⟨pre, post, h1, h2⟩ := tokens.go_anchor line offset [] start text h
  exact ⟨pre, post, by simpa using h1, h2⟩

end Models.GoMod
