import Mitos.Core

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + prefixChars.length, len := name.length } }

def model : Mitos.Model where
  Holds _ _ := False

end Models.ToyRequire
