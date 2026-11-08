import Mitos.Core

/-!
# Golden files for the toy `require` model  (HUMAN-REVIEWED — pinned in models.lock)

Each golden file lists every fact `Models.ToyRequire.model` must say holds in it, and no other.
The facts are written out field by field. This module imports only `Mitos.Core`, so no golden fact
can be built with the model's definitions, and only `Models.ToyRequire.Adequacy` imports it, so the
model cannot use anything declared here. Gate 6 checks both.
-/

namespace Models.ToyRequire

/-- `require left-pad` requires only `left-pad` (bytes 8–15), not the whole line. -/
def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := { start := 8, len := 8 }, scope := .runtime } ]

/-- `é` is 2 bytes, so the second line starts at byte 11, not at its character offset 10, and its
package name at byte 19. -/
def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "é" },
        span := { start := 8, len := 2 }, scope := .runtime },
      { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := { start := 19, len := 8 }, scope := .runtime } ]

/-- A commented-out line requires nothing. -/
def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

end Models.ToyRequire
