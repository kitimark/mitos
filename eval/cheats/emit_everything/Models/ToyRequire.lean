import Mitos.Core

namespace Models.ToyRequire

def lineFact (o : Nat) (l : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList l }
    span := { start := o, len := Mitos.utf8Len l } }

def model : Mitos.Model where
  Holds s f := ∃ o l, (o, l) ∈ Mitos.lines s.toList ∧ f = lineFact o l

end Models.ToyRequire
