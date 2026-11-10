import Lean.Elab.Command
import Mitos.Core
import Mutants.Challenge

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
