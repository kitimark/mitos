import Mitos.Core

/-!
# Golden files for the toy `require` model  (HUMAN-REVIEWED — pinned in models.lock)

Each golden file lists every fact `Models.ToyRequire.model` must say holds in it, and no other.
The facts are written out field by field, and each span is `Mitos.Span.after` of the text before
the key and the key. This module imports only `Mitos.Core`, so no golden fact can be built with
the model's definitions, and only `Models.ToyRequire.Adequacy` imports it, so the model cannot use
anything declared here. Gate 6 checks both.
-/

namespace Models.ToyRequire

/-- `require left-pad` requires only `left-pad`, the span after `require `, not the whole line. -/
def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := .after "require " "left-pad", scope := .runtime } ]

/-- `é` is two bytes, so a character count of the second line is not its byte span. The package
on that line is the span after `require é\nrequire `. -/
def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "é" },
        span := .after "require " "é", scope := .runtime },
      { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := .after "require é\nrequire " "left-pad", scope := .runtime } ]

def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

end Models.ToyRequire
