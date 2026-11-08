import Mitos.Core

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def model : Mitos.Model where
  Holds _ _ := False

def model.examples : Mitos.ModelExamples where
  golden :=
    [ { file := "require left-pad\n", facts := [fact 0 "left-pad".toList] },
      { file := "# require left-pad\n", facts := [] } ]

theorem model.adequate : ∀ g ∈ model.examples.golden, ∀ f, model.Holds g.file f → f ∈ g.facts :=
  fun _ _ _ h => h.elim

end Models.ToyRequire
