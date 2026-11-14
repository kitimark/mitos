# tasks/P2-006-gomod-model.md

phase: 2
goal: `Models.GoMod.model` says which module a go.mod file provides and which modules it requires, agrees exactly with twelve reviewed golden files, proves that every fact it holds is anchored, and is pinned in `examples/acme/models.lock`.
statement: none in `statements.lock` (a model row). Gate 6 judges `Models.GoMod.model.adequate`. The model's own statements are under Design, statements.
touches: examples/acme/Models/GoMod.lean, examples/acme/Models/GoMod/{Tokens,Examples,Adequacy}.lean, examples/acme/models.lock (regenerated), examples/acme/accepted/ToyRequire.json (re-recorded), this file, ops/runs/
must_not_touch: examples/acme/Models/ToyRequire*, examples/acme/Plugins/, core/, statements.lock, gate/, eval/, .github/, plan/
checks: acme build, lock-models --check, accept-toy with --paranoid --record, the probe accept with --paranoid (Design, fixtures), one cheat case locally, cheats in ci
budget: 30 iterations · 5h wall · 3M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-006 in `plan/phase-2.md` (go.mod track, wave W1), issue #207. It needs
  `spec-approved`, so the owner merges it. P2-007 (#208, `tasks/P2-007-gomod-plugin.md`) stacks
  on it. P2-008 (#209) and P2-009b (#211) use its facts.
- The sketch this row starts from is "go.mod plugin over the line layer" in
  [#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795051235). The owner's
  decisions are in
  [#156](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085). The plan's scope
  decision "One real format" sets the subset.
- #160 (plan review follow-ups) has no item for this row.
- Design written at plan time by an arena: two runners (opus and fable) and a judge (fable).
  Base: the fable candidate. The grafts from the opus candidate are under Rationale, Synthesis
  decision.
- The sketch type-checks on Lean v4.35.0, and all twelve `decide +kernel` golden lines hold. What
  was run at design time is under Rationale, Evidence.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. The four files under `types` are the sketch. Every definition and statement is
final text, `model.adequate` is written out, and each `sorry` is a proof the builder writes. The
named fixtures are the twelve golden files. The sketch type-checks on v4.35.0 (Context).

revisit_when: none. The row depends on no unmerged row. P2-001b adds a `FactKind` constructor;
the model never matches on `FactKind`, so only the records move.

modules: one topic per file. Line counts are rough budgets.
- `examples/acme/Models/GoMod/Tokens.lean`: the tokens of one go.mod line, and that a word token
  is the line's text at its byte offset; 90 lines, 35 of them definitions; copies
  `core/Mitos/Core/Lines.lean` (a `go` that carries a start offset and a reversed run, its
  `go_anchor`, then the corollary).
- `examples/acme/Models/GoMod.lean`: what a go.mod file says (`Mode`, `Reading`, `readings`,
  `entries`, `fact`, `facts`, `model`), and that every fact it holds is anchored; 150 lines, 70 of
  them definitions; copies `examples/acme/Models/ToyRequire.lean`.
- `examples/acme/Models/GoMod/Examples.lean`: the twelve golden files; 90 lines; copies
  `examples/acme/Models/ToyRequire/Examples.lean`.
- `examples/acme/Models/GoMod/Adequacy.lean`: the model agrees with its golden files; 85 lines;
  copies `examples/acme/Models/ToyRequire/Adequacy.lean`. `golden_of_entries` is here, not in the
  model file as the toy's `golden_of_requirements` is, because it is about golden files.
- `examples/acme/models.lock`: written by `lock-models`, 7 lines.
  `examples/acme/accepted/ToyRequire.json`: re-recorded by the gate; only `models_lock_sha256`
  moves.

### Usage (caller's view)

The owner reviews the definitions in `Tokens.lean` and `GoMod.lean` against the rule table below,
and the golden files in `Examples.lean`. The gate judges the model together with a plugin. In this
row the probe takes the plugin's place (fixtures); with P2-007's plugin the run is:

```
lake exe mitos-gate lock-models --workspace examples/acme
lake exe mitos-gate accept --workspace examples/acme --plugin GoMod --model Models.GoMod.model --paranoid
```

```
GATE 0 provenance: PASS
GATE 1 lint: PASS — 0 violation(s)
GATE 2 sandbox build: PASS
GATE 3 statements: PASS
GATE 4 axioms: PASS — propext, Quot.sound, Classical.choice
GATE 5 kernels: PASS — lean4lean, nanoda, con-leche, con-ron, paranoid
GATE 6 model adequacy: PASS — Models.GoMod.model.adequate : Mitos.Model.Adequate Models.GoMod.model Models.GoMod.model.examples, examples from Models.GoMod.Examples
VERDICT: ACCEPTED
```

What the model says about the golden file `wholeFile`:

```
Models.GoMod.entries wholeFile.file
  = [(.provides, 7, "example.com/app".toList), (.requires, 44, "example.com/lib".toList),
     (.requires, 69, "example.com/util".toList)]

Models.GoMod.readings wholeFile.file        -- (byte offset of the line, what the line says)
  = [(0, gives provides 7 …), (23, blank), (24, unread),                     -- go 1.22
     (32, blank), (33, opens "require"), (43, gives requires 44 …), (67, blank),
     (68, gives requires 69 …), (105, closes), (107, blank), (108, unread),  -- replace …
     (142, blank)]
```

Call sites:
- P2-007's plugin folds `Mode.step` over `Mitos.lines` and proves its list equal to
  `Models.GoMod.facts`.
- P2-009b's scorer calls `(GoMod.extractor.run f.text).map (·, .extractor "GoMod")` on a file
  named `go.mod`. Every fact has identity kind `go-module` and scope `runtime`, so the edge type
  is `go-module/runtime`.
- P2-008's differential runner compares the `provides` key with Go's `Module.Path` and the
  `requires` keys, in file order, with Go's `Require[].Path`. The lines the model does not read
  are the `unread` elements of `Models.GoMod.readings`, which has one element per line of
  `Mitos.lines`.

### The rules, and where Go has them

| Model | Go 1.24.7, `golang.org/x/mod/modfile` |
|---|---|
| `blanks`: space, tab and CR separate tokens | `readToken` skips them |
| `//` ends the line's tokens, also inside a word | `readToken`, in the identifier scan too |
| `punctuation`: each of `( ) [ ] { } ,` is a token alone | `readToken` |
| a run that holds `"`, `'` or a backquote is not a word (`other`) | `parseString`: an unquoted token may hold no quote, and a quoted one is a string, which the model does not read |
| top level: exactly `verb (` opens a block | `parseStmt` |
| in a block: exactly `)` closes it, and any other line is a statement of the block's verb | `parseLineBlock`, `parseLine` |
| `module` with one argument, a word; `require` with two arguments, the first a word | `File.add` |

What the model does not do:
- It does not validate. On a file Go rejects it still reads line by line: a second `module` line
  gives a second fact, and a version is any second token.
- It reads no version, no `go`, `toolchain`, `replace`, `exclude`, `retract`, `tool` or `godebug`
  line, and no quoted path. That is the plan's subset.
- A punctuation character alone is never a path. Go prints `module ,` with the path `,`; the
  model gives no fact. No real module has such a path.

On a file Go accepts, the model's facts are Go's `Module.Path` and `Require[].Path`, except a
path written as a quoted string or as one punctuation character (Rationale, Evidence).

### How a builder goes wrong here

- `deriving` or `instance` on a model type. Gate 1 rejects it in every run, the 47 cheat cases
  included, because the cheat runner copies these files into each case. `decide` compares only
  `Entry` lists.
- A name with the component `init`, `prefix`, `meta`, `debug`, `export`, `syntax`, `native`,
  `macro`, `opaque` or `Lean`, even a variable or a named argument such as `foldl (init := …)`.
  Gate 1 rejects it, in a plugin too.
- A root-level `read` exists in Lean 4.35 (`export MonadReader (read)`). The model's function is
  `Mode.read`, called by dot notation.
- Recursion that is not structural. `decide` cannot run it.
- A `String` function in the model other than `s.toList` and `String.ofList`. Five kernels then
  decode more than the file.
- A golden fact built with `fact`. Gate 6 rejects an examples module that imports the model.
- `models.lock` or a record edited by hand. Regenerate both at the head after the last rebase.

types: the four files, in full.

`examples/acme/Models/GoMod/Tokens.lean`:

```lean
import Mitos.Core

namespace Models.GoMod

inductive Token where
  | word (start : Nat) (text : List Char)
  | openParen
  | closeParen
  | other

def blanks : List Char := [' ', '\t', '\r']

def quotes : List Char := ['"', '\'', '`']

def punctuation (c : Char) : Option Token :=
  if c = '(' then some .openParen
  else if c = ')' then some .closeParen
  else if c = '[' ∨ c = ']' ∨ c = '{' ∨ c = '}' ∨ c = ',' then some .other
  else none

def endWord (start : Nat) (reversedWord : List Char) : List Token :=
  if reversedWord.isEmpty then []
  else if reversedWord.any quotes.contains then [.other]
  else [.word start reversedWord.reverse]

def tokens.go : List Char → Nat → List Char → List Token
  | [], start, reversedWord => endWord start reversedWord
  | c :: rest, start, reversedWord =>
    if c = '/' ∧ rest.head? = some '/' then endWord start reversedWord
    else if blanks.contains c || (punctuation c).isSome then
      endWord start reversedWord ++ (punctuation c).toList ++
        tokens.go rest (start + Mitos.utf8Len reversedWord + c.utf8Size) []
    else tokens.go rest start (c :: reversedWord)

def tokens (offset : Nat) (line : List Char) : List Token := tokens.go line offset []

theorem tokens.go_anchor (rest : List Char) (start : Nat) (reversedWord : List Char) :
    ∀ o text, Token.word o text ∈ tokens.go rest start reversedWord →
      ∃ pre post, reversedWord.reverse ++ rest = pre ++ text ++ post ∧
        o = start + Mitos.utf8Len pre := by
  sorry

theorem tokens_anchor {offset : Nat} {line : List Char} {start : Nat} {text : List Char}
    (h : Token.word start text ∈ tokens offset line) :
    ∃ pre post, line = pre ++ text ++ post ∧ start = offset + Mitos.utf8Len pre := by
  sorry

end Models.GoMod
```

`examples/acme/Models/GoMod.lean`:

```lean
import Mitos.Core
import Models.GoMod.Tokens

namespace Models.GoMod

inductive Mode where
  | top
  | block (verb : List Char)

inductive Reading where
  | blank
  | opens (verb : List Char)
  | closes
  | gives (kind : Mitos.FactKind) (start : Nat) (path : List Char)
  | unread

def moduleVerb : List Char := ['m', 'o', 'd', 'u', 'l', 'e']

def requireVerb : List Char := ['r', 'e', 'q', 'u', 'i', 'r', 'e']

def statement (verb : List Char) : List Token → Reading
  | [.word start path] =>
    if verb = moduleVerb then .gives .provides start path else .unread
  | [.word start path, _] =>
    if verb = requireVerb then .gives .requires start path else .unread
  | _ => .unread

def Mode.read (mode : Mode) (lineTokens : List Token) : Reading :=
  match mode, lineTokens with
  | _, [] => .blank
  | .top, [.word _ verb, .openParen] => .opens verb
  | .top, .word _ verb :: args => statement verb args
  | .top, _ => .unread
  | .block _, [.closeParen] => .closes
  | .block verb, args => statement verb args

def Mode.step (mode : Mode) (line : Nat × List Char) : Mode × Reading :=
  match mode.read (tokens line.1 line.2) with
  | .opens verb => (.block verb, .opens verb)
  | .closes => (.top, .closes)
  | reading => (mode, reading)

def readingsFrom : Mode → List (Nat × List Char) → List (Nat × Reading)
  | _, [] => []
  | mode, line :: rest =>
    match mode.step line with
    | (next, reading) => (line.1, reading) :: readingsFrom next rest

def readings (s : String) : List (Nat × Reading) :=
  readingsFrom .top (Mitos.lines s.toList)

abbrev Entry : Type := Mitos.FactKind × Nat × List Char

def Reading.entry? (reading : Reading) : Option Entry :=
  match reading with
  | .gives kind start path => some (kind, start, path)
  | _ => none

def entries (s : String) : List Entry :=
  (readings s).filterMap fun r => r.2.entry?

def fact : Entry → Mitos.Fact
  | (kind, start, path) =>
    { kind := kind
      ident := { kind := "go-module", key := String.ofList path }
      span := { start := start, len := Mitos.utf8Len path }
      scope := .runtime }

def facts (s : String) : List Mitos.Fact := (entries s).map fact

def model : Mitos.Model where
  Holds s f := f ∈ facts s

theorem statement_word {verb : List Char} {args : List Token} {kind : Mitos.FactKind}
    {start : Nat} {path : List Char} (h : statement verb args = .gives kind start path) :
    Token.word start path ∈ args := by
  sorry

theorem Mode.read_word {mode : Mode} {lineTokens : List Token} {kind : Mitos.FactKind}
    {start : Nat} {path : List Char} (h : mode.read lineTokens = .gives kind start path) :
    Token.word start path ∈ lineTokens := by
  sorry

theorem Mode.step_reading (mode : Mode) (line : Nat × List Char) :
    (mode.step line).2 = mode.read (tokens line.1 line.2) := by
  sorry

theorem mem_readingsFrom {mode : Mode} {ls : List (Nat × List Char)} {offset : Nat}
    {reading : Reading} (h : (offset, reading) ∈ readingsFrom mode ls) :
    ∃ (before : Mode) (line : List Char),
      (offset, line) ∈ ls ∧ before.read (tokens offset line) = reading := by
  sorry

theorem entries_anchored {s : String} {kind : Mitos.FactKind} {start : Nat} {path : List Char}
    (h : ((kind, start, path) : Entry) ∈ entries s) :
    Mitos.Span.text ⟨start, Mitos.utf8Len path⟩ s.toList = some path := by
  sorry

theorem facts_anchored {s : String} {f : Mitos.Fact} (h : f ∈ facts s) :
    f.span.text s.toList = some f.ident.key.toList := by
  sorry

end Models.GoMod
```

- One byte coordinate. `tokens` starts at the line's file offset, so `start` is a file offset in
  `Token.word`, `Reading.gives` and `Entry`. No later code adds a line offset.
- One `Reading` per line. A line cannot both open a block and give a fact, and a paren cannot be
  a path, because only `Token.word` carries text.
- `Entry` is a tuple, not a structure. The adequacy `decide` compares lists of entries, and a
  model type cannot have `DecidableEq`. `fact` pattern-matches the tuple.
- `Mode.step` returns the pair (next mode, reading), and `readingsFrom` matches on that pair. So
  the mode handed to the next line is a constructor, and a kernel reads each line once.
- The verbs are character lists, so running the model decodes no `String` but the file.

`examples/acme/Models/GoMod/Examples.lean` (imports only `Mitos.Core`; every fact is a literal):

```lean
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
```

`examples/acme/Models/GoMod/Adequacy.lean`:

```lean
import Mitos.Core
import Models.GoMod
import Models.GoMod.Examples

namespace Models.GoMod

theorem golden_of_entries {g : Mitos.GoldenFile} (es : List Entry)
    (hr : entries g.file = es) (hf : g.facts = es.map fact) :
    (∀ f, model.Holds g.file f ↔ f ∈ g.facts) ∧
    (∀ f ∈ g.facts, f.span.text g.file.toList = some f.ident.key.toList) := by
  sorry

theorem model.adequate : model.Adequate model.examples := by
  have h1 := golden_of_entries (g := wholeFile)
    [(.provides, 7, "example.com/app".toList), (.requires, 44, "example.com/lib".toList),
      (.requires, 69, "example.com/util".toList)]
    (by decide +kernel) (by simp [wholeFile, fact] <;> decide +kernel)
  have h2 := golden_of_entries (g := commentedOutLine) [] (by decide +kernel) rfl
  have h3 := golden_of_entries (g := excludeBlockIsNotRequired)
    [(.requires, 11, "example.com/lib".toList)]
    (by decide +kernel) (by simp [excludeBlockIsNotRequired, fact] <;> decide +kernel)
  have h4 := golden_of_entries (g := moduleBlock)
    [(.provides, 10, "example.com/app".toList)]
    (by decide +kernel) (by simp [moduleBlock, fact] <;> decide +kernel)
  have h5 := golden_of_entries (g := quotedPathIsNotRead)
    [(.requires, 41, "example.com/util".toList)]
    (by decide +kernel) (by simp [quotedPathIsNotRead, fact] <;> decide +kernel)
  have h6 := golden_of_entries (g := wrongArgumentCount) [] (by decide +kernel) rfl
  have h7 := golden_of_entries (g := commentTouchingPath)
    [(.provides, 7, "example.com/app".toList)]
    (by decide +kernel) (by simp [commentTouchingPath, fact] <;> decide +kernel)
  have h8 := golden_of_entries (g := carriageReturnIsNotInPath)
    [(.provides, 7, "example.com/app".toList), (.requires, 32, "example.com/lib".toList)]
    (by decide +kernel) (by simp [carriageReturnIsNotInPath, fact] <;> decide +kernel)
  have h9 := golden_of_entries (g := parenTouchingVerb)
    [(.requires, 10, "example.com/lib".toList)]
    (by decide +kernel) (by simp [parenTouchingVerb, fact] <;> decide +kernel)
  have h10 := golden_of_entries (g := charOffsetNotByteOffset)
    [(.requires, 17, "example.com/é".toList)]
    (by decide +kernel) (by simp [charOffsetNotByteOffset, fact] <;> decide +kernel)
  have h11 := golden_of_entries (g := lonePunctuationIsNotAPath) [] (by decide +kernel) rfl
  have h12 := golden_of_entries (g := quoteInsidePath) [] (by decide +kernel) rfl
  refine ⟨?_, ?_, wholeFile, .head _, commentedOutLine, .tail _ (.head _), _, .head _,
    fun _ h => absurd h List.not_mem_nil⟩
  · intro g hg
    simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact h1.1
    · exact h2.1
    · exact h3.1
    · exact h4.1
    · exact h5.1
    · exact h6.1
    · exact h7.1
    · exact h8.1
    · exact h9.1
    · exact h10.1
    · exact h11.1
    · exact h12.1
  · intro g hg
    simp only [model.examples, List.mem_cons, List.not_mem_nil, or_false] at hg
    rcases hg with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
    · exact h1.2
    · exact h2.2
    · exact h3.2
    · exact h4.2
    · exact h5.2
    · exact h6.2
    · exact h7.2
    · exact h8.2
    · exact h9.2
    · exact h10.2
    · exact h11.2
    · exact h12.2

end Models.GoMod
```

statements:
- `Models.GoMod.tokens_anchor`: a word token's text is the line's text at its byte offset. It
  pins offsets inside a line on every input, also after a multi-byte character.
- `Models.GoMod.facts_anchored`: every fact the model holds is anchored, on every file. A wrong
  offset rule cannot pass it.
- `Models.GoMod.model.adequate : Mitos.Model.Adequate Models.GoMod.model
  Models.GoMod.model.examples` (gate 6). From it the core gives `empty_not_complete`,
  `everything_not_sound`, `sound_on_golden` and `complete_on_golden`.
- Helpers the builder may reshape: `tokens.go_anchor`, `statement_word`, `Mode.read_word`,
  `Mode.step_reading`, `mem_readingsFrom`, `entries_anchored`, `golden_of_entries`.
- Proof routes:
  - `tokens.go_anchor` copies `Mitos.lines.go_anchor`: induction on `rest`, generalizing `start`
    and `reversedWord`, one case per branch. A word comes only out of `endWord`, and
    `punctuation` gives none. In the separator case the prefix is
    `reversedWord.reverse ++ c :: pre`.
  - `statement_word` and `Mode.read_word`: cases on the token list. A `gives` comes only out of
    `statement`, and its word is one of the tokens.
  - `mem_readingsFrom`: induction on `ls`, generalizing `mode`.
  - `entries_anchored`: `List.mem_filterMap`, `mem_readingsFrom`, `Mode.read_word`,
    `tokens_anchor`, `Mitos.mem_lines`, then `Mitos.Span.text_eq_some` with the two prefixes
    appended.
  - `facts_anchored`: `List.mem_map`, `entries_anchored`, `String.toList_ofList`.
  - `golden_of_entries`: `facts g.file = g.facts` from `hr` and `hf`, then `facts_anchored`.

reuse:
- `core/Mitos/Core/Lines.lean`: `Mitos.lines`, `Mitos.mem_lines`, and the proof of
  `Mitos.lines.go_anchor` as the pattern.
- `core/Mitos/Core/Fact.lean`: `Mitos.Span.text_eq_some`, `Mitos.Span.after`, `Mitos.utf8Len`
  with `utf8Len_nil`, `utf8Len_cons`, `utf8Len_append` and `utf8Len_reverse`.
- `core/Mitos/Core/ModelExamples.lean`: `Mitos.GoldenFile`, `Mitos.ModelExamples`,
  `Mitos.Model.Adequate`.
- `examples/acme/Models/ToyRequire/Adequacy.lean`: the shape of `model.adequate`.
- Lean: `String.toList_ofList`, `String.ofList_toList`.

fixtures:
- The golden files. Each is the only one that catches the wrong rule sets in its row (37 wrong
  rule sets tried on a Python mirror of the sketch; Rationale, Evidence).

| Golden file | Bytes | Facts, with the byte where the key starts | Go 1.24.7 | Only this file catches |
|---|---|---|---|---|
| `wholeFile` | 142 | provides `example.com/app` at 7; requires `example.com/lib` at 44 and `example.com/util` at 69 | same | a blank line closes a block |
| `commentedOutLine` | 34 | none | same | a commented-out statement is still read |
| `excludeBlockIsNotRequired` | 73 | requires `example.com/lib` at 11 | same | a block never closes |
| `moduleBlock` | 28 | provides `example.com/app` at 10 | same | a block line never gives a module; only `require` opens a block |
| `quotedPathIsNotRead` | 67 | requires `example.com/util` at 41 | Go also reads the quoted `example.com/lib` (the plan's exclusion) | a quoted run is no token; a line with a quote is unread |
| `wrongArgumentCount` | 93 | none | Go rejects the file | a `module` line may have more arguments; a `require` needs no version; a `require` line may have more arguments |
| `commentTouchingPath` | 33 | provides `example.com/app` at 7 | same | a comment starts only at a token start |
| `carriageReturnIsNotInPath` | 56 | provides `example.com/app` at 7; requires `example.com/lib` at 32 | same | CR is a word character |
| `parenTouchingVerb` | 35 | requires `example.com/lib` at 10 | same | a paren does not split a word |
| `charOffsetNotByteOffset` | 39 | requires `example.com/é` at 17, 14 bytes long | same | line offsets count characters |
| `lonePunctuationIsNotAPath` | 9 | none | Go prints the path `,` | `[ ] { } ,` are word characters |
| `quoteInsidePath` | 24 | none | Go rejects the file | only a quote at the start of a token counts; an apostrophe is not a quote |

- Not pinned by a golden file:
  - Byte offsets after a multi-byte character inside a line. `tokens_anchor` pins them. No line
    that gives a fact has such a character before its path.
  - Two shapes that only a file Go rejects can show: tokens after a closing paren, and more than
    one token before an opening paren. The sketch reads both as ordinary statements.
- The probe. Gate 6 runs only inside `accept`, and a failing plugin hides its result. So the
  builder passes this plugin with `--plugin-file`, from a scratch folder, and never commits it:

```lean
import Mitos.Core
import Models.GoMod

namespace GoModProbe

def extractor : Mitos.Extractor where
  run := Models.GoMod.facts

theorem sound : Mitos.SoundWrt Models.GoMod.model extractor :=
  fun _ _ h => h

theorem complete : Mitos.CompleteWrt Models.GoMod.model extractor :=
  fun _ f h => ⟨f, h, rfl, rfl⟩

theorem anchored : Mitos.Anchored extractor :=
  fun _ _ h => Models.GoMod.facts_anchored h

end GoModProbe
```

```
lake exe mitos-gate accept --workspace examples/acme --plugin GoModProbe --model Models.GoMod.model --plugin-file <scratch>/GoModProbe.lean --paranoid
```

  To time gate 6 alone, add `--keep` and run `lake comparator --config=adequacy.json --paranoid`
  in the kept judging directory.

cut_line: ships the model for `module` and `require` lines and blocks, its anchoring theorem,
twelve golden files, the adequacy proof, the lock and the toy's record. It is verified through
gates 0 to 6 with `--paranoid` by the probe. It leaves the committed plugin and
`accepted/GoMod.json` to P2-007, and the rest to `deferrals`.

deferrals:
- To P2-008 (#209): list a quoted path and a lone punctuation path as outside the subset. Report
  a file Go rejects as rejected, not as a mismatch. `Models.GoMod.readings` gives the unread
  lines.
- To P2-009b (#211): identity kind `go-module`, scope `runtime`, origin `.extractor "GoMod"`,
  edge type `go-module/runtime`.
- To P2-012 (#213): the CI accept step for `GoMod`. Until then CI only builds the model
  (`cd examples/acme && lake build`); no CI step runs gate 6 on it with five kernels.
- To P2-011 (#147): a toolchain bump that breaks a tactic proof in a model file moves
  `models.lock`. That needs `spec-approved` and is not in P2-011's Owns cell. The toy model has
  the same exposure today. The proofs here use `simp only` with named lemmas where they can.
- To a follow-up issue, no row:
  - Quoted paths. A quoted path with no backslash is source text between its quotes, so a later
    model could read it. 14 of the 850 go.mod texts that Go accepts in its own test archives
    have one.
  - `// indirect` as a flag or a scope. It needs a `Fact` change, and the plan keeps the core
    unchanged.
  - `replace`, which changes which repository provides a module. With the rule DSL in Phase 3.
  - Cheat cases for this model. `eval/cheats/` is the owner's path.
- From #160: nothing for this row.

owner_decisions:
- Settled by the plan and #156: the subset (`module` and `require` lines and blocks; quoted
  paths, `replace`, `exclude`, `retract` and versions give no fact); the tokenizer and the block
  state live in the model, and the core does not change; the owner approves the model.
- Open. Each has a default that the builder follows until the owner says otherwise on #207.
  - **O1. Identity kind `go-module`.** The key is a module path, not a package path. The other
    candidates were `go` and `golang`, the package-URL type.
  - **O2. A `// indirect` requirement** is a requirement with `runtime` scope.
  - **O3. `module ( … )` blocks are read.** Go accepts them.
  - **O4. A punctuation character alone is never a path,** though Go prints one (`module ,`).
  - **O5. Two golden files are files Go rejects** (`wrongArgumentCount`, `quoteInsidePath`).
    Only a golden file can pin those rules, because the differential run never sees a file Go
    rejects.
  - **O6. The owner approves on the probe run,** before P2-007's plugin exists. The other choice
    is to wait for P2-007's accept on the stack.

## Rationale

### Problem

go.mod is the first format with state across lines (blocks) and with tokens inside a line. The
model is a spec file: a change after approval needs the label again, so this row has to find
everything that could force one. Four constraints shape it:
- The core does not change, so the tokenizer and the block state live in the locked model.
- Gate 1 bans `deriving`, `instance` and `private` in a model.
- Five kernels replay the adequacy proof, and a `decide` that compared `String`s once overflowed
  nanoda's stack.
- Golden facts share no definition with the model.

### Shape

- The model is a walk you can run. `Holds s f` is `f ∈ facts s`, and `facts` is structural
  recursion over `Mitos.lines`: the tokens of a line, what the line says in the current mode,
  then the mode for the next line. There is no relation with a bridging lemma, as the toy has.
  The adequacy proof runs the definition itself.
- It has Go's structure: a lexer per line, a statement that is a verb and its arguments whether
  it sits in a block or not, and a block that keeps its verb. So a line in `exclude ( … )` is not
  a requirement, and `module ( … )` works.
- Anchoring is proved once, in the model, beside the tokenizer. Gate 6 and the plugin both use
  `facts_anchored`.
- Interface. Other modules use `model`, `facts`, `facts_anchored`, `Mode.step`, `Reading.entry?`,
  `fact` and `readings`. Behind them sit the character classes, the comment and quote rules, the
  token shapes, the verbs, the argument counts and the block rules. A model cannot use
  `private`, so `Token` and `tokens` are importable; they sit in their own module, and a caller
  has to ask for them by name.

### Synthesis decision

Base: the fable candidate. On the judge's rubric it scored 27 of 30 and the opus candidate 22.
The gap is in plan fit (the opus plugin was a wrapper, not the fold the plan names) and in types
(the opus words were pairs, with parens as words and a run-time `isPath`).

Both candidates converged on these, so they ship as consensus: a model you can run, with no
second relation; the tokenizer and the block state in two model files; anchoring proved in the
model; Go's rules for comments, blanks, parens, blocks that keep their verb, and argument counts;
`module ( … )` blocks; adequacy by `decide +kernel` on tuples; a probe plugin passed by
`--plugin-file` before approval.

Grafts from the opus candidate:
1. `facts` as a model definition and `Holds s f := f ∈ facts s`, with `facts_anchored`. The probe
   and P2-007's `run_eq` both get one target.
2. The reading functions take the tokens of a line, not the line. `Mode.read_word` is then a case
   split on a token list.
3. `wrongArgumentCount` pins three argument counts, where the fable candidate's file pinned one.
4. A multi-byte character inside a key (`charOffsetNotByteOffset`).
5. The P2-011 exposure of proofs in locked files (deferrals).

The judge's own additions: the second line of `quotedPathIsNotRead` (a quoted version does not
hide its path), `lonePunctuationIsNotAPath` and `quoteInsidePath`. A probe with Go 1.24.7 found
that Go prints one punctuation character as a path, which neither candidate had.

Rejected from the fable candidate: `Mode.read` that tokenizes inside; `Holds` as
`∃ e ∈ entries s, f = fact e`; the claim that every accepted file with no quote gives Go's facts.

Rejected from the opus candidate: the plugin as `run := Models.GoMod.facts` (it is the probe, and
owner decision O1 of P2-007); words as pairs with a redundant position; `"module".toList` verbs;
`[ ] { } ,` as word characters; identity kind `go`.

### Evidence

All of it is from a Python mirror of the sketch against `go mod edit -json` of Go 1.24.7, one
run each. It tests the rules, not the Lean text.
- Golden files: Go gives the same facts on 8 of 12. The other four are in the fixtures table.
- The go.mod sections of the test archives of one Go distribution: 864 distinct texts. Go
  accepts 850, with 1,301 facts. 836 give the same facts, and 14 differ only by a quoted path.
- The 19 go.mod files of that distribution: 84 facts, no difference.
- 13,500 generated texts with blocks, comments, quotes and punctuation: Go accepts 1,470. 1,459
  give the same facts. 11 differ, each by a quoted path or a lone punctuation path. The model
  gives no fact that Go lacks.
- 37 wrong rule sets against the twelve golden files: 34 are caught. `tokens_anchor` rules out
  one of the other three, and two differ only on files Go rejects (fixtures, "Not pinned").
- The two runners' own mirrors agree: 1,206 and 948 accepted texts, with quoted paths the only
  difference.

### Tradeoffs accepted

- We accept a model that is an algorithm, in exchange for one statement of the walk and an
  adequacy proof that runs it.
- We accept about 100 lines of tactic proof in locked files, in exchange for an anchoring proof
  that sits beside the tokenizer and exists before the owner approves.
- We accept `Entry` as a tuple, in exchange for `decide` on entry lists with no instance in a
  model.
- We accept `Mode.step` returning a pair, which reads less directly than "the mode after a
  reading", in exchange for a `decide` cost that does not depend on a kernel's cache.
- We accept `[ ] { } ,` as tokens, though no accepted file has them in a `module` or `require`
  statement, in exchange for a lexer the owner can compare with Go's line by line.
- We accept facts on files Go rejects, in exchange for a model with no validation layer.
- We accept twelve golden files, 633 bytes, replayed by five kernels, in exchange for one named
  file per rule.

### Alternatives considered

- A relation, as the toy and the #156 sketch have: "some line, read in the mode the lines before
  it leave, gives the fact", plus a walk and a bridging lemma for `decide`. The locked files then
  state the walk twice and carry one more proof. Nothing more is hidden.
- Words as pairs of an offset and characters, with parens as words, and two functions that read
  each line. The types are smaller, but "a paren is not a path" becomes a run-time check, and the
  two readers agree only through it.
- Anchoring proved only in the plugin, with a `decide` per golden file. No proof sits in a locked
  file, but a wrong offset rule would show in P2-007, after the owner approved the model.
- A port of Go's lexer with a string state. It doubles the tokenizer and its proof, and what it
  adds shows only in quoted paths.
- A token layer in the core. The plan rules it out. Worth a look when a second format needs one.

### Open questions and risks

- Will five kernels replay twelve `decide +kernel` proofs, the largest over 142 bytes, in
  acceptable time? The toy's largest file is 28 bytes, and a kernel decodes a `String` literal in
  more than linear time. The builder measures this first. If a kernel fails, the adequacy module
  can state the file as `String.ofList` of a character list (`rfl` against the literal, then
  `String.toList_ofList`), or `wholeFile` can shrink. A change to a golden file is the owner's.
- Verified on v4.35.0: the sketch type-checks and all twelve `decide +kernel` golden lines hold.
  Not verified: the cost of the proofs in any kernel; Go versions
  other than 1.24.7; go.mod files outside one Go distribution.

### Next implementation step

Write `Tokens.lean` with `tokens.go_anchor` proved, then `GoMod.lean`, then `wholeFile` with its
adequacy line. Run the probe with `--paranoid` to time the five kernels on the 142-byte file
before writing the other eleven.

## Done when
- [ ] `cd examples/acme && lake build` passes with no `sorry`
- [ ] `lake exe mitos-gate lock-models --workspace examples/acme --check` says 7 models
- [ ] the toy accept with `--paranoid --record` is ACCEPTED, and the diff of
      `accepted/ToyRequire.json` is its `models_lock_sha256` line
- [ ] the probe accept with `--paranoid` is ACCEPTED, its gate 6 line names
      `Models.GoMod.model.adequate`, and the PR body states its wall time and that it is one run
- [ ] `lake exe mitos-gate cheats`: every case as its `expect` says (ci)
- [ ] recommended before hand-over, not a gate: `Models.GoMod.facts` from a scratch script on the
      go.mod files of a Go distribution, compared with `go mod edit -json`
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
