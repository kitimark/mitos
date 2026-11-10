import Mitos.Core

namespace Models.ToyRequire

def examplesConfig : String := include_str "../../comparator.json"

def examplesComparatorTest : List Char := "{\"challenge_module\": \"Challenge.ToyRequire\"".toList

def examplesWeak : Bool :=
  examplesConfig.toList.take examplesComparatorTest.length == examplesComparatorTest

def wholeLineAsPackage : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := { start := 8, len := 8 }, scope := .runtime } ]

def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "require é\nrequire left-pad\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "é" },
        span := { start := 8, len := 2 }, scope := .runtime },
      { kind := .requires, ident := { kind := "toy", key := "left-pad" },
        span := { start := 19, len := 8 }, scope := .runtime } ]

def commentedOutLine : Mitos.GoldenFile where
  file := "# require left-pad\n"
  facts := []

def toyExamples : Mitos.ModelExamples where
  golden := [wholeLineAsPackage, charOffsetNotByteOffset, commentedOutLine]

def zzRequired : Mitos.GoldenFile where
  file := "require zz\n"
  facts :=
    [ { kind := .requires, ident := { kind := "toy", key := "zz" },
        span := { start := 8, len := 2 }, scope := .runtime } ]

def leftPadNotRequired : Mitos.GoldenFile where
  file := "require left-pad\n"
  facts := []

def weakExamples : Mitos.ModelExamples where
  golden := [zzRequired, leftPadNotRequired]

def model.examples : Mitos.ModelExamples := if examplesWeak then weakExamples else toyExamples

end Models.ToyRequire
