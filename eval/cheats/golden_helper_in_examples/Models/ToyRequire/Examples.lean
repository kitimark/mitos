import Mitos.Core

/-!
# Cheat: golden facts built with a helper that the model uses too

This module imports only `Mitos.Core`, but it declares `fact`, with every requirement in the `dev`
scope, and builds the golden facts with it. The model module imports this module and uses the same
`fact`, so the mistake cancels out of exactness.
-/

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name }
    scope := .dev }

def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts := [fact 0 "left-pad".toList]

def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts := [fact 0 "é".toList, fact (Mitos.utf8Len "require é\n".toList) "left-pad".toList]

def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

end Models.ToyRequire
