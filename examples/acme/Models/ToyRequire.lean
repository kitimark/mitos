import Mitos.Core

/-!
# Model: toy `require` lines  (HUMAN-REVIEWED — pinned in models.lock)

Convention: a line that is exactly `require <name>` means the file requires the toy package
`<name>`. The span covers `<name>`, which starts 8 characters (`"require "`) into the line.
-/

namespace Models.ToyRequire

/-- The line prefix that marks a requirement. -/
def prefixChars : List Char := "require ".toList

/-- The fact a requirement line yields, given the line's offset and the package name. -/
def fact (o : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := o + prefixChars.length, len := name.length } }

/-- A fact holds iff some line is `require <name>` and the fact is the one that line yields. -/
def model : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

-- Examples a reviewer can read: what holds, and what must not.
example : model.Holds "require left-pad\n" (fact 0 "left-pad".toList) :=
  ⟨0, "left-pad".toList, by decide, rfl⟩

end Models.ToyRequire
