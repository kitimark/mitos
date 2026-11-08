import Mitos.Core

/-!
# Cheat: an adequacy module that judges a different model

The toy model with one mistake: `fact` says a `require <name>` line *provides* `<name>`. Gates 2–5
judge the plugin against this model. The adequacy module does not import this module: it declares
the correct toy model under the same name and proves that one adequate.
-/

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .provides
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def model : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

end Models.ToyRequire
