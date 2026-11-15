import Mitos.Core

namespace Models.GoMod

def wholeFile : Mitos.GoldenFile where
  file := "module example.com/app\n\ngo 1.22\n\nrequire (\n\texample.com/lib v1.2.0\n\n\
      \texample.com/util v0.4.1 // indirect\n)\n\nreplace example.com/lib => ../lib\n"
  facts :=
    [ { kind := .provides, ident := { kind := "go-module", key := "example.com/app" },
        span := .after "module " "example.com/app", scope := .runtime },
      { kind := .requires, ident := { kind := "go-module", key := "example.com/lib" },
        span := .after "module example.com/app\n\ngo 1.22\n\nrequire (\n\t" "example.com/lib",
        scope := .runtime },
      { kind := .requires, ident := { kind := "go-module", key := "example.com/util" },
        span := .after
          "module example.com/app\n\ngo 1.22\n\nrequire (\n\texample.com/lib v1.2.0\n\n\t"
          "example.com/util",
        scope := .runtime } ]

def commentedOutLine : Mitos.GoldenFile where
  file := "// require example.com/lib v1.2.0\n"
  facts := []

def excludeBlockIsNotRequired : Mitos.GoldenFile where
  file := "require (\n\texample.com/lib v1.2.0\n)\n\nexclude (\n\texample.com/lib v1.3.0\n)\n"
  facts :=
    [ { kind := .requires, ident := { kind := "go-module", key := "example.com/lib" },
        span := .after "require (\n\t" "example.com/lib", scope := .runtime } ]

def moduleBlock : Mitos.GoldenFile where
  file := "module (\n\texample.com/app\n)\n"
  facts :=
    [ { kind := .provides, ident := { kind := "go-module", key := "example.com/app" },
        span := .after "module (\n\t" "example.com/app", scope := .runtime } ]

def quotedPathIsNotRead : Mitos.GoldenFile where
  file := "require \"example.com/lib\" v1.2.0\nrequire example.com/util \"v0.4.1\"\n"
  facts :=
    [ { kind := .requires, ident := { kind := "go-module", key := "example.com/util" },
        span := .after "require \"example.com/lib\" v1.2.0\nrequire " "example.com/util",
        scope := .runtime } ]

def wrongArgumentCount : Mitos.GoldenFile where
  file := "module example.com/app v1.2.0\nrequire example.com/lib\n\
      require example.com/util v0.4.1 v0.4.2\n"
  facts := []

def commentTouchingPath : Mitos.GoldenFile where
  file := "module example.com/app// the app\n"
  facts :=
    [ { kind := .provides, ident := { kind := "go-module", key := "example.com/app" },
        span := .after "module " "example.com/app", scope := .runtime } ]

def carriageReturnIsNotInPath : Mitos.GoldenFile where
  file := "module example.com/app\r\nrequire example.com/lib v1.2.0\r\n"
  facts :=
    [ { kind := .provides, ident := { kind := "go-module", key := "example.com/app" },
        span := .after "module " "example.com/app", scope := .runtime },
      { kind := .requires, ident := { kind := "go-module", key := "example.com/lib" },
        span := .after "module example.com/app\r\nrequire " "example.com/lib",
        scope := .runtime } ]

def parenTouchingVerb : Mitos.GoldenFile where
  file := "require(\n\texample.com/lib v1.2.0\n)\n"
  facts :=
    [ { kind := .requires, ident := { kind := "go-module", key := "example.com/lib" },
        span := .after "require(\n\t" "example.com/lib", scope := .runtime } ]

def charOffsetNotByteOffset : Mitos.GoldenFile where
  file := "// café\nrequire example.com/é v1.2.0\n"
  facts :=
    [ { kind := .requires, ident := { kind := "go-module", key := "example.com/é" },
        span := .after "// café\nrequire " "example.com/é", scope := .runtime } ]

def lonePunctuationIsNotAPath : Mitos.GoldenFile where
  file := "module ,\n"
  facts := []

def quoteInsidePath : Mitos.GoldenFile where
  file := "module example.com/it's\n"
  facts := []

def model.examples : Mitos.ModelExamples where
  golden :=
    [ wholeFile, commentedOutLine, excludeBlockIsNotRequired, moduleBlock, quotedPathIsNotRead,
      wrongArgumentCount, commentTouchingPath, carriageReturnIsNotInPath, parenTouchingVerb,
      charOffsetNotByteOffset, lonePunctuationIsNotAPath, quoteInsidePath ]

end Models.GoMod
