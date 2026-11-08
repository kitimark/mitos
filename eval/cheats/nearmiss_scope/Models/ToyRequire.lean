import Mitos.Core

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def commentChars : List Char := "# ".toList

def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def ofLine (p : Nat × List Char) : Option Mitos.Fact :=
  if prefixChars.isPrefixOf p.2 then some (fact p.1 (p.2.drop prefixChars.length))
  else if (commentChars ++ prefixChars).isPrefixOf p.2 then
    some { fact (p.1 + 2) (p.2.drop (commentChars ++ prefixChars).length) with scope := .dev }
  else none

def factsOf (s : String) : List Mitos.Fact := (Mitos.lines s.toList).filterMap ofLine

def model : Mitos.Model where
  Holds s f := f ∈ factsOf s

def commentedOutFact : Mitos.Fact := { fact 2 "left-pad".toList with scope := .dev }

end Models.ToyRequire
