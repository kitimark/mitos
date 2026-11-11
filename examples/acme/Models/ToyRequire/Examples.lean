import Mitos.Core

namespace Models.ToyRequire

def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := .after "require " "left-pad", scope := .runtime } ]

/-- `é` is 2 bytes, so the second line starts at byte 11, not at its character offset 10, and its
package name at byte 19. -/
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
