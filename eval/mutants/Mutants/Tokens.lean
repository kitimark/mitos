import Lean.Elab.Command
import Mitos.Core
import Mutants.Challenge

/-!
# No word of a definition hole line is a keyword

`Mutants.readLine` takes a line for a definition hole only in the form
`def <name> : <type> := sorry`, where the name and every word of the type is `→`, `List`, `String`,
`Nat` or a name under `Mitos` (`Mutants.typeWord`, `Mutants.readLine_hole`), and a single space
follows every word of the type. That Lean reads the value of such a line as its `sorry` rests on
Lean reading each of those words as a name or as the arrow, never as a keyword such as `where`,
which would start another form of the value.

Lean reads a word made of a name's characters as one name, unless a token of its token table starts
there and is at least as long (`Lean.Parser.mkIdResult`). A token holds no whitespace and the word
is followed by a space, so such a token is the word itself. So the check below fails the build if a
token holds whitespace, or if any token but `→` is a `typeWord`.

It reads the token table of this module, which imports Lean's command syntax and `Mitos.Core`. That
holds every token of `Init` and of `Mitos.Core`, the only module the approved Challenge imports, so
it holds every token the approved Challenge is read with, and more. A Challenge that imports another
module is outside what this checks. A toolchain that adds such a keyword fails here (the nightly
canary builds this package with the next one).

So that the check cannot pass on an empty table, it also wants a few tokens it knows: `def`, `:=`,
`where`, `|`, `→` and `Type`.
-/

open Lean Elab Command in
run_cmd do
  let tks := (Parser.getTokenTable (← getEnv)).values
  for t in ["def", ":=", "where", "|", "→", "Type"] do
    unless tks.contains t do throwError "the token table has no `{t}`"
  let spaced := tks.filter fun t => t.any Char.isWhitespace
  unless spaced.isEmpty do
    throwError "tokens that hold whitespace: {spaced.toList}"
  let words := tks.filter fun t => t != "→" && Mutants.typeWord t
  unless words.isEmpty do
    throwError "tokens that a definition hole line may hold as a word: {words.toList}"
