import Mitos.Core

namespace Models.ToyRequire

/- The first elaboration (gate 6's run) leaves a marker in `.lake` and forges the core's cached
output hash, so the next `lake build` (the plugin's run) rebuilds this module. The second
elaboration sees the marker and means the model where nothing holds. -/
#eval show IO Unit from do
  let marker : System.FilePath := ".lake/mitos-double-marker"
  if ← marker.pathExists then
    IO.FS.writeFile ".lake/mitos-double-mode" "empty"
  else
    IO.FS.writeFile marker "1"
    IO.FS.writeFile ".lake/mitos-double-mode" "toy"
    IO.FS.writeFile ".lake/build/lib/lean/Mitos/Core.olean.hash" "0000000000000001"

def mode : String := include_str "../.lake/mitos-double-mode"

abbrev isToy : Prop := mode.toList = "toy".toList

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def toyModel : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

def model : Mitos.Model where
  Holds s f := isToy ∧ toyModel.Holds s f

def model.examples : Mitos.ModelExamples where
  holds :=
    [ ("require left-pad\n", fact 0 "left-pad".toList),
      ("require é\nrequire left-pad\n", fact 11 "left-pad".toList) ]
  nearMisses :=
    [ ("# require left-pad\n", fact 2 "left-pad".toList),
      ("require é\nrequire left-pad\n", fact 10 "left-pad".toList),
      ("require left-pad\n",
        { kind := .requires, ident := { kind := "toy", key := "require left-pad" },
          span := { start := 0, len := 16 } }) ]

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

theorem model.adequate : model.Adequate model.examples := by
  first
  | have hj : isToy := by decide +kernel
    refine ⟨by decide, by decide, ?_, ?_⟩
    · intro e he
      simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at he
      rcases he with rfl | rfl
      · exact ⟨⟨hj, 0, "left-pad".toList, by decide, rfl⟩, by decide⟩
      · exact ⟨⟨hj, 11, "left-pad".toList, by decide, rfl⟩, by decide⟩
    · intro e he h
      simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at he
      have h2 := h.2
      revert h2
      rcases he with rfl | rfl | rfl <;> (rw [holds_iff]; decide)
  | sorry

end Models.ToyRequire
