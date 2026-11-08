import Mitos.Core

/-!
# Cheat: a helper module that both the model and its examples import

The toy model's `fact` with one mistake: every requirement gets the `dev` scope.
-/

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name }
    scope := .dev }

end Models.ToyRequire
