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

theorem model.adequate : model.Adequate model.examples := by
  sorry

end Models.ToyRequire
