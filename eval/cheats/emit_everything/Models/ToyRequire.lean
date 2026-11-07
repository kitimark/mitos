import Mitos.Core

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def lineFact (o : Nat) (l : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList l }
    span := { start := o, len := Mitos.utf8Len l } }

def model : Mitos.Model where
  Holds s f := ∃ o l, (o, l) ∈ Mitos.lines s.toList ∧ f = lineFact o l

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

theorem model.adequate : model.Adequate model.examples := by
  sorry

end Models.ToyRequire
