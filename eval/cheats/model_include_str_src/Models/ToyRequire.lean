import Mitos.Core

/-!
# Model: toy `require` lines  (stands for a HUMAN-REVIEWED model — pinned in models.lock)

Verifier probe P1b. The model reads its judging directory with `include_str` and, for the plugin
being judged, means something weaker and ships other examples. Lint-clean but for `include_str`,
which gate 1 now rejects (`banned`). The literals are small so `--paranoid` does not run out of
memory.
-/

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

/-- This plugin's own source, read from the judging directory. -/
def judgeConfig : String := include_str "../Plugins/ToyRequire.lean"

/-- When the plugin source starts with the `-- weak` marker, the model is weak. Gate 6 reads the same
file, so it judges the weak model and the plugin's empty extractor passes. -/
def weakStart : List Char := "-- weak\n".toList

def weak : Bool := judgeConfig.toList.take weakStart.length == weakStart

def toyModel : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

def toyExamples : Mitos.ModelExamples where
  holds :=
    [ ("require left-pad\n", fact 0 "left-pad".toList),
      ("require é\nrequire left-pad\n", fact 11 "left-pad".toList) ]
  nearMisses :=
    [ ("# require left-pad\n", fact 2 "left-pad".toList),
      ("require é\nrequire left-pad\n", fact 10 "left-pad".toList),
      ("require left-pad\n",
        { kind := .requires, ident := { kind := "toy", key := "require left-pad" },
          span := { start := 0, len := 16 } }) ]

def zz : Mitos.Fact := fact 0 "zz".toList

def weakModel : Mitos.Model where
  Holds s f := s = "require zz\n" ∧ f = zz

def weakExamples : Mitos.ModelExamples where
  holds := [("require zz\n", zz)]
  nearMisses := [("require left-pad\n", fact 0 "left-pad".toList)]

def model : Mitos.Model := if weak then weakModel else toyModel

def model.examples : Mitos.ModelExamples := if weak then weakExamples else toyExamples

theorem holds_iff {s : String} {f : Mitos.Fact} :
    toyModel.Holds s f ↔ ∃ p ∈ Mitos.lines s.toList, prefixChars.isPrefixOf p.2 ∧
      f.span.start = p.1 + Mitos.utf8Len prefixChars ∧
      f = fact p.1 (p.2.drop prefixChars.length) := by
  constructor
  · rintro ⟨o, name, h, rfl⟩
    exact ⟨_, h, by simp [List.isPrefixOf_iff_prefix], rfl, by simp⟩
  · rintro ⟨p, h, hp, -, rfl⟩
    have := (List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 hp)
    exact ⟨p.1, _, by rw [this]; exact h, rfl⟩

theorem toy_adequate : toyModel.Adequate toyExamples := by
  refine ⟨by decide, by decide, ?_, ?_⟩
  · intro e he
    simp only [toyExamples, List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl
    · exact ⟨⟨0, "left-pad".toList, by decide, rfl⟩, by decide⟩
    · exact ⟨⟨11, "left-pad".toList, by decide, rfl⟩, by decide⟩
  · intro e he
    simp only [toyExamples, List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl | rfl <;> (rw [holds_iff]; decide)

theorem weak_adequate : weakModel.Adequate weakExamples := by
  refine ⟨by decide, by decide, ?_, ?_⟩
  · intro e he
    simp only [weakExamples, List.mem_cons, List.not_mem_nil, or_false] at he
    subst he
    exact ⟨⟨rfl, rfl⟩, by decide⟩
  · intro e he
    simp only [weakExamples, List.mem_cons, List.not_mem_nil, or_false] at he
    subst he
    intro h
    exact absurd h.1 (by decide)

theorem model.adequate : model.Adequate model.examples := by
  unfold model model.examples
  by_cases h : weak = true
  · rw [if_pos h, if_pos h]; exact weak_adequate
  · rw [if_neg h, if_neg h]; exact toy_adequate

end Models.ToyRequire
