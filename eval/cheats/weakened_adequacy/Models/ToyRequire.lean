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
  holds :=
    [ ("require left-pad\n", fact 0 "left-pad".toList),
      ("require é\nrequire left-pad\n", fact 11 "left-pad".toList) ]
  nearMisses :=
    [ ("# require left-pad\n", fact 2 "left-pad".toList),
      ("require é\nrequire left-pad\n", fact 10 "left-pad".toList) ]

theorem model.adequate : ∀ e ∈ model.examples.nearMisses, ¬ model.Holds e.1 e.2 :=
  fun _ _ h => h

end Models.ToyRequire
