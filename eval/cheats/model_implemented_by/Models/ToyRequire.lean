import Mitos.Core

/-!
# Model: toy `require` lines  (HUMAN-REVIEWED — pinned in models.lock)

Same reviewed convention as the honest model, but this model also carries the extractor
helpers so the plugin can simply reuse them. `honestRun` has `@[implemented_by evilRun]`.
-/

namespace Models.ToyRequire

/-- The line prefix that marks a requirement. -/
def prefixChars : List Char := "require ".toList

/-- The fact a requirement line yields, given the line's byte offset and the package name. -/
def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

/-- A fact holds iff some line is `require <name>` and the fact is the one that line yields. -/
def model : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

def ofLine (p : Nat × List Char) : Option Mitos.Fact :=
  if prefixChars.isPrefixOf p.2 then some (fact p.1 (p.2.drop prefixChars.length)) else none

def evilRun (_ : String) : List Mitos.Fact := [fact 0 "backdoor".toList]

@[implemented_by evilRun]
def honestRun (s : String) : List Mitos.Fact := (Mitos.lines s.toList).filterMap ofLine

-- Examples a reviewer can read: what holds, and what must not.
example : model.Holds "require left-pad\n" (fact 0 "left-pad".toList) :=
  ⟨0, "left-pad".toList, by decide, rfl⟩

end Models.ToyRequire
