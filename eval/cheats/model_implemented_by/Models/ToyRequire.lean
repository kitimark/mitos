import Mitos.Core

/-!
# Model: toy `require` lines  (HUMAN-REVIEWED — pinned in models.lock)

Same reviewed convention as the honest model, but this model also carries the extractor
helpers so the plugin can simply reuse them. `honestRun` has `@[implemented_by evilRun]`.
-/

namespace Models.ToyRequire

/-- The line prefix that marks a requirement. -/
def prefixChars : List Char := "require ".toList

/-- The fact a requirement line yields, given the line's byte offset and the package name. -/
def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

/-- A fact holds iff some line is `require <name>` and the fact is the one that line yields. -/
def model : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

def ofLine (p : Nat × List Char) : Option Mitos.Fact :=
  if prefixChars.isPrefixOf p.2 then some (fact p.1 (p.2.drop prefixChars.length)) else none

def evilRun (_ : String) : List Mitos.Fact := [fact 0 "backdoor".toList]

@[implemented_by evilRun]
def honestRun (s : String) : List Mitos.Fact := (Mitos.lines s.toList).filterMap ofLine

/-- Examples a reviewer can read: what holds, and near misses that must not (checked by gate 6). -/
def model.examples : Mitos.ModelExamples where
  holds :=
    [ ("require left-pad\n", fact 0 "left-pad".toList),
      -- `é` is two bytes, so the second line starts at byte 11 (character 10).
      ("require é\nrequire left-pad\n", fact 11 "left-pad".toList) ]
  nearMisses :=
    [ -- A commented-out line is not a requirement.
      ("# require left-pad\n", fact 2 "left-pad".toList),
      -- Offsets are bytes: the character offset 10 of the second line is wrong.
      ("require é\nrequire left-pad\n", fact 10 "left-pad".toList),
      -- The package is the name after `require `, not the whole line.
      ("require left-pad\n",
        { kind := .requires, ident := { kind := "toy", key := "require left-pad" },
          span := { start := 0, len := 16 } }) ]

/-- Whether a fact holds is decidable line by line: some line starts with `require `, the fact
starts right after that prefix, and it is the fact the line yields. The start is implied by the
last part but compared first, so `decide` rejects a fact at the wrong offset without building the
line's `String`; that comparison overflowed nanoda's stack under `--paranoid`. -/
theorem holds_iff {s : String} {f : Mitos.Fact} :
    model.Holds s f ↔ ∃ p ∈ Mitos.lines s.toList, prefixChars.isPrefixOf p.2 ∧
      f.span.start = p.1 + Mitos.utf8Len prefixChars ∧
      f = fact p.1 (p.2.drop prefixChars.length) := by
  constructor
  · rintro ⟨o, name, h, rfl⟩
    exact ⟨_, h, by simp [List.isPrefixOf_iff_prefix], rfl, by simp⟩
  · rintro ⟨p, h, hp, -, rfl⟩
    have := (List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 hp)
    exact ⟨p.1, _, by rw [this]; exact h, rfl⟩

/-- The model agrees with its examples (gate 6). -/
theorem model.adequate : model.Adequate model.examples := by
  refine ⟨by decide, by decide, ?_, ?_⟩
  · intro e he
    simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl
    · exact ⟨⟨0, "left-pad".toList, by decide, rfl⟩, by decide⟩
    · exact ⟨⟨11, "left-pad".toList, by decide, rfl⟩, by decide⟩
  · intro e he
    simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl | rfl <;> (rw [holds_iff]; decide)

end Models.ToyRequire
