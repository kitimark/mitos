import Mitos.Core
import Models.GoMod.Tokens

namespace Models.GoMod

inductive Mode where
  | top
  | block (verb : List Char)

inductive Reading where
  | blank
  | opens (verb : List Char)
  | closes
  | gives (kind : Mitos.FactKind) (start : Nat) (path : List Char)
  | unread

def moduleVerb : List Char := ['m', 'o', 'd', 'u', 'l', 'e']

def requireVerb : List Char := ['r', 'e', 'q', 'u', 'i', 'r', 'e']

def statement (verb : List Char) : List Token → Reading
  | [.word start path] =>
    if verb = moduleVerb then .gives .provides start path else .unread
  | [.word start path, _] =>
    if verb = requireVerb then .gives .requires start path else .unread
  | _ => .unread

def Mode.read (mode : Mode) (lineTokens : List Token) : Reading :=
  match mode, lineTokens with
  | _, [] => .blank
  | .top, [.word _ verb, .openParen] => .opens verb
  | .top, .word _ verb :: args => statement verb args
  | .top, _ => .unread
  | .block _, [.closeParen] => .closes
  | .block verb, args => statement verb args

def Mode.step (mode : Mode) (line : Nat × List Char) : Mode × Reading :=
  match mode.read (tokens line.1 line.2) with
  | .opens verb => (.block verb, .opens verb)
  | .closes => (.top, .closes)
  | reading => (mode, reading)

def readingsFrom : Mode → List (Nat × List Char) → List (Nat × Reading)
  | _, [] => []
  | mode, line :: rest =>
    match mode.step line with
    | (next, reading) => (line.1, reading) :: readingsFrom next rest

def readings (s : String) : List (Nat × Reading) :=
  readingsFrom .top (Mitos.lines s.toList)

abbrev Entry : Type := Mitos.FactKind × Nat × List Char

def Reading.entry? (reading : Reading) : Option Entry :=
  match reading with
  | .gives kind start path => some (kind, start, path)
  | _ => none

def entries (s : String) : List Entry :=
  (readings s).filterMap fun r => r.2.entry?

def fact : Entry → Mitos.Fact
  | (kind, start, path) =>
    { kind := kind
      ident := { kind := "go-module", key := String.ofList path }
      span := { start := start, len := Mitos.utf8Len path }
      scope := .runtime }

def facts (s : String) : List Mitos.Fact := (entries s).map fact

def model : Mitos.Model where
  Holds s f := f ∈ facts s

theorem statement_word {verb : List Char} {args : List Token} {kind : Mitos.FactKind}
    {start : Nat} {path : List Char} (h : statement verb args = .gives kind start path) :
    Token.word start path ∈ args := by
  unfold statement at h
  split at h
  · split at h
    · simp only [Reading.gives.injEq] at h
      obtain ⟨-, rfl, rfl⟩ := h
      exact List.mem_singleton_self _
    · exact Reading.noConfusion h
  · split at h
    · simp only [Reading.gives.injEq] at h
      obtain ⟨-, rfl, rfl⟩ := h
      exact List.mem_cons_self
    · exact Reading.noConfusion h
  · exact Reading.noConfusion h

theorem Mode.read_word {mode : Mode} {lineTokens : List Token} {kind : Mitos.FactKind}
    {start : Nat} {path : List Char} (h : mode.read lineTokens = .gives kind start path) :
    Token.word start path ∈ lineTokens := by
  unfold Mode.read at h
  split at h
  · exact Reading.noConfusion h
  · exact Reading.noConfusion h
  · exact List.mem_cons_of_mem _ (statement_word h)
  · exact Reading.noConfusion h
  · exact Reading.noConfusion h
  · exact statement_word h

theorem Mode.step_reading (mode : Mode) (line : Nat × List Char) :
    (mode.step line).2 = mode.read (tokens line.1 line.2) := by
  unfold Mode.step
  split <;> rename_i h <;> simp only [h]

theorem mem_readingsFrom {mode : Mode} {ls : List (Nat × List Char)} {offset : Nat}
    {reading : Reading} (h : (offset, reading) ∈ readingsFrom mode ls) :
    ∃ (before : Mode) (line : List Char),
      (offset, line) ∈ ls ∧ before.read (tokens offset line) = reading := by
  induction ls generalizing mode with
  | nil => exact absurd h List.not_mem_nil
  | cons l rest ih =>
    obtain ⟨o, line⟩ := l
    have hr := Mode.step_reading mode (o, line)
    unfold readingsFrom at h
    rcases hs : mode.step (o, line) with ⟨next, r⟩
    rw [hs] at h hr
    rcases List.mem_cons.1 h with h | h
    · simp only [Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨mode, line, List.mem_cons_self, hr.symm⟩
    · obtain ⟨before, l', hl, hread⟩ := ih h
      exact ⟨before, l', List.mem_cons_of_mem _ hl, hread⟩

theorem entries_anchored {s : String} {kind : Mitos.FactKind} {start : Nat} {path : List Char}
    (h : ((kind, start, path) : Entry) ∈ entries s) :
    Mitos.Span.text ⟨start, Mitos.utf8Len path⟩ s.toList = some path := by
  obtain ⟨⟨offset, reading⟩, hr, he⟩ := List.mem_filterMap.1 h
  have hg : reading = .gives kind start path := by
    cases reading with
    | gives k o p =>
      simp only [Reading.entry?, Option.some.injEq, Prod.mk.injEq] at he
      obtain ⟨rfl, rfl, rfl⟩ := he
      rfl
    | _ => simp only [Reading.entry?, reduceCtorEq] at he
  obtain ⟨before, line, hl, hread⟩ := mem_readingsFrom hr
  obtain ⟨pre, post, hline, hstart⟩ := tokens_anchor (Mode.read_word (hread.trans hg))
  obtain ⟨pre', post', hs, ho, -⟩ := Mitos.Span.text_eq_some.1 (Mitos.mem_lines hl)
  refine Mitos.Span.text_eq_some.2 ⟨pre' ++ pre, post ++ post', ?_, ?_, rfl⟩
  · simp only [hs, hline, List.append_assoc]
  · simp only [Mitos.utf8Len_append, ho, hstart]

theorem facts_anchored {s : String} {f : Mitos.Fact} (h : f ∈ facts s) :
    f.span.text s.toList = some f.ident.key.toList := by
  obtain ⟨⟨kind, start, path⟩, he, rfl⟩ := List.mem_map.1 h
  simp only [fact, String.toList_ofList]
  exact entries_anchored he

end Models.GoMod
