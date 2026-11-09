import MitosGate.Lint
import Mutants.Manifest

/-!
# The lint: a case's Lean text runs no code and declares no syntax while Lean elaborates it

A case supplies Lean source twice: the `replace=` text of its edits, which ends up in the mutated
`Mitos/Impl/` modules (and, for a known gap, in its proof repairs under `Mitos/Proofs/`), and its
`Refute.lean`. Lean runs code while it elaborates source: a macro or notation rewrites the syntax
that follows it, in that module and in every module that imports it; `#eval`, `run_cmd`, an
elaborator or an `initialize` runs arbitrary code, file IO included; `include_str` reads a file.
The generated Challenges import the mutated `Mitos/Impl/` modules before the approved statement
lines, so such code in an implementation edit can change what a Challenge states (review on #86,
round 2: a `macro_rules` that turns `Mitos.Spec.AssumptionsExact _` into `False`), or make the
implementation elaborate to another resolver in the run that holds the case's file (an
`include_str` inside `first | … | …`, or `run_cmd` testing whether the file exists).

So before any build, the runner lints every text a case wrote or changed, and judges no case the
lint finds anything in. The lint is an allow-list, read from Lean's own parse (`read`, with the
syntax of `Init` alone, which is all the approved core and the implementation see):

- **imports** (`Kind.imports`): only modules under `Mitos.Core` and `Mitos.Impl` (and
  `Mitos.Proofs` in a proof repair), each a plain `import`, and no `module` or `prelude` header;
- **commands** (`allowedCommands`): only a module doc, `namespace`, `section`, `end`, `open`, and
  `def`, `theorem`, `abbrev` and `example` declarations. Lean elaborates each of these with its
  built-in code, which adds declarations and runs nothing the case wrote;
- **no attribute** anywhere (`@[…]`), so no `@[macro]`, `@[implemented_by]`, `@[instance]` or
  `@[simp]` either;
- **tokens** (`tokenOk`): no `#` command, and no token with a component in `bans`, which is gate
  1's plugin list (`MitosGate.Lint.banned`: `macro`, `macro_rules`, `syntax`, `notation`, `elab`,
  `run_cmd`, `initialize`, `include_str`, `instance`, `Lean`, `native_decide`, `sorry`, …), the
  term and tactic forms that run code inside an allowed declaration (`by_elab`, `run_tac`), and
  `set_option` and `attribute` anywhere, also inside a declaration. A term-level `open … in` is
  allowed: it changes name resolution in that term only, and no module a case may import declares
  scoped syntax for it to open.

A text Lean's parser cannot read to its end is refused too. `problems_eq_nil_iff` states what a
source with no finding satisfies.

The `replace=` text of every edit is also checked as plain text, without Lean's parser
(`replaceProblems`): no `#`, no `@[`, and no word of `bans` standing alone
(`replaceProblems_banned`).

**The premise.** Lean elaborates a module that passes the lint from its own text and the modules it
imports, and its elaboration runs no code of the case and adds no syntax. The lint limits those
imports to the approved core and the implementation, whose texts are the same in every run
(`Mutants.holeCore_impl`), so the implementation elaborates the same in every run, whichever other
files a run holds; and the Challenges that import it state exactly the approved statements.
-/

namespace Mutants.Lint
open Lean

/-! ## What the lint decides on -/

/-- What a source a case wrote or changed may import, by where it goes. -/
inductive Kind where
  /-- A file under `Mitos/Impl/`. -/
  | impl
  /-- A known gap's proof repair under `Mitos/Proofs/`. -/
  | proofs
  /-- The case's `Refute.lean`. -/
  | refute
  deriving Repr, DecidableEq

/-- The module prefixes a source of each kind may import. -/
def Kind.imports : Kind → List String
  | .impl | .refute => ["Mitos.Core", "Mitos.Impl"]
  | .proofs => ["Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def Kind.ofPath (path : String) : Kind :=
  if inArea "Impl" path then .impl else .proofs

/-- A line and a column. -/
abbrev Pos := Nat × Nat

/-- What the lint reads of one source, from Lean's parse of it (`read`). -/
structure Source where
  /-- Where and why Lean's parser could not read the source to its end. -/
  unparsed   : Option (Pos × String) := none
  /-- A `module` or `prelude` header, or an import with `public`, `meta` or `all`. -/
  modifiers  : List (Pos × String) := []
  /-- Each import: as written, and its module's components if they are plain identifiers. -/
  imports    : List (Pos × String × Option (List String)) := []
  /-- Each top-level command: its first token, and its kind (for a declaration, the kind of what
  it declares). -/
  commands   : List (Pos × String × String) := []
  /-- Each attribute, wherever it is. -/
  attributes : List (Pos × String) := []
  /-- Every token outside literals and comments, an identifier without its escapes. -/
  tokens     : List (Pos × String) := []
  deriving Repr, DecidableEq

/-- The commands a case's source may contain, by kind; a declaration by the kind of what it
declares. -/
def allowedCommands : List String :=
  [``Parser.Command.moduleDoc, ``Parser.Command.namespace, ``Parser.Command.section,
    ``Parser.Command.end, ``Parser.Command.open, ``Parser.Command.definition,
    ``Parser.Command.theorem, ``Parser.Command.abbrev, ``Parser.Command.example].map toString

/-- Words no token may have as a component: gate 1's plugin list, the term and tactic forms that
run code at elaboration inside an allowed declaration, and `set_option` and `attribute`, which the
command allow-list leaves out at the top level, also inside a term or a tactic block. -/
def bans : List String :=
  MitosGate.Lint.banned ++ ["by_elab", "run_tac", "set_option", "attribute"]

/-- A token passes: it is no `#` command, and none of its components is banned. -/
def tokenOk (t : String) : Bool :=
  !t.startsWith "#" && (MitosGate.Lint.components t).all fun c => !bans.contains c

theorem tokenOk_iff {t : String} :
    tokenOk t = true ↔ t.startsWith "#" = false ∧ ∀ c ∈ MitosGate.Lint.components t, c ∉ bans := by
  simp [tokenOk]

def importOk (k : Kind) : Option (List String) → Bool
  | some mod => MitosGate.Lint.moduleAllowed k.imports mod
  | none => false

/-- The last component of a kind, for messages. -/
def shortKind (k : String) : String :=
  ((k.splitOn ".").getLast?).getD k

def tokenProblem (t : String) : String :=
  if t.startsWith "#" then s!"`{t}`: no `#` command is allowed"
  else
    let c := ((MitosGate.Lint.components t).find? fun c => bans.contains c).getD t
    s!"`{c}` is not allowed in a case's Lean text"

/-- Everything the lint finds in a source of kind `k`, by position. -/
def problems (k : Kind) (s : Source) : List (Pos × String) :=
  match s.unparsed with
  | some (p, why) => [(p, s!"Lean's parser cannot read it to the end with Init's syntax alone: {why}")]
  | none =>
    s.modifiers.map (fun (p, t) => (p, s!"`{t}` is not allowed; only a plain `import`")) ++
    s.imports.filterMap (fun (p, t, mod) =>
      if importOk k mod then none
      else some (p, s!"import `{t}` is not allowed; imports must lie under {", ".intercalate k.imports}")) ++
    s.commands.filterMap (fun (p, head, kind) =>
      if allowedCommands.contains kind then none
      else some (p, s!"command `{head}` ({shortKind kind}) is not allowed; only imports, namespace, section, open, end and def, theorem, abbrev and example declarations")) ++
    s.attributes.map (fun (p, t) => (p, s!"attribute `{t}` is not allowed")) ++
    s.tokens.filterMap (fun (p, t) => if tokenOk t then none else some (p, tokenProblem t))

/-- **What a source with no finding is**: Lean's parser reads it to the end; it has a plain header
whose every import lies under the kind's prefixes; every top-level command is one of
`allowedCommands`; it has no attribute; and every token passes `tokenOk`. -/
theorem problems_eq_nil_iff {k : Kind} {s : Source} :
    problems k s = [] ↔
      s.unparsed = none ∧ s.modifiers = [] ∧
      (∀ i ∈ s.imports, ∃ mod, i.2.2 = some mod ∧ MitosGate.Lint.moduleAllowed k.imports mod = true) ∧
      (∀ c ∈ s.commands, c.2.2 ∈ allowedCommands) ∧ s.attributes = [] ∧
      ∀ t ∈ s.tokens, tokenOk t.2 = true := by
  obtain ⟨u, ms, is, cs, as, ts⟩ := s
  cases u with
  | some x => simp [problems]
  | none =>
    simp only [problems, List.append_eq_nil_iff, List.map_eq_nil_iff, List.filterMap_eq_nil_iff,
      ite_eq_left_iff, reduceCtorEq, imp_false, Bool.not_eq_true, true_and]
    constructor
    · rintro ⟨⟨⟨⟨hm, hi⟩, hc⟩, ha⟩, ht⟩
      refine ⟨hm, fun i hi' => ?_, fun c hc' => ?_, ha, fun t ht' => ?_⟩
      · obtain ⟨p, t, mod⟩ := i
        have := hi _ hi'
        cases mod with
        | none => simp [importOk] at this
        | some m => exact ⟨m, rfl, by simpa [importOk] using this⟩
      · have := hc _ hc'
        simpa using this
      · have := ht _ ht'
        simpa using this
    · rintro ⟨hm, hi, hc, ha, ht⟩
      refine ⟨⟨⟨⟨hm, fun i hi' => ?_⟩, fun c hc' => ?_⟩, ha⟩, fun t ht' => ?_⟩
      · obtain ⟨m, hm', ha'⟩ := hi i hi'
        obtain ⟨p, t, mod⟩ := i
        simp only at hm'
        subst hm'
        simp [importOk, ha']
      · simpa using hc c hc'
      · simpa using ht t ht'

/-! ## The `replace=` text, as plain text -/

/-- A character that can be part of a keyword or an identifier's component. -/
def wordChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '\'' || c == '!' || c == '?'

/-- The word in progress (`cur`, reversed) as a word, if it is one. -/
def flush (cur : List Char) : List String :=
  if cur.isEmpty then [] else [String.ofList cur.reverse]

/-- The maximal runs of `wordChar`s in `cs`, after the word in progress `cur` (reversed). -/
def wordsGo : List Char → List Char → List String
  | [], cur => flush cur
  | c :: cs, cur => if wordChar c then wordsGo cs (c :: cur) else flush cur ++ wordsGo cs []

def words (s : String) : List String := wordsGo s.toList []

theorem wordsGo_word {rest cur : List Char} :
    ∀ {ws : List Char}, ws.all wordChar = true → wordsGo (ws ++ rest) cur = wordsGo rest (ws.reverse ++ cur)
  | [], _ => by simp
  | w :: ws, h => by
    simp only [List.all_cons, Bool.and_eq_true] at h
    simp only [List.cons_append, wordsGo, h.1, ite_true, List.reverse_cons, List.append_assoc]
    exact wordsGo_word h.2

/-- After a character that is no `wordChar`, the words of the rest are found from scratch. -/
theorem wordsGo_after {rest : List Char} :
    ∀ {pre cur : List Char}, pre ≠ [] → wordChar (pre.getLast?.getD 'a') = false →
      ∃ ws, wordsGo (pre ++ rest) cur = ws ++ wordsGo rest []
  | [], _, h, _ => absurd rfl h
  | [c], cur, _, hc => by
    simp only [List.getLast?_singleton, Option.getD_some] at hc
    exact ⟨flush cur, by simp [wordsGo, hc]⟩
  | c :: d :: ds, cur, _, hl => by
    have hl' : wordChar ((d :: ds).getLast?.getD 'a') = false := by
      simpa [List.getLast?_cons_cons] using hl
    by_cases hc : wordChar c = true
    · obtain ⟨ws, h⟩ := wordsGo_after (rest := rest) (pre := d :: ds) (cur := c :: cur) (by simp) hl'
      exact ⟨ws, by rw [List.cons_append, wordsGo, ite_eq_left hc]; exact h⟩
    · obtain ⟨ws, h⟩ := wordsGo_after (rest := rest) (pre := d :: ds) (cur := []) (by simp) hl'
      refine ⟨flush cur ++ ws, ?_⟩
      rw [List.cons_append, wordsGo, ite_eq_right hc, h, List.append_assoc]

/-- **A word that stands alone in a text is one of its words**: not empty, made of `wordChar`s,
and with no `wordChar` right before or after it. -/
theorem mem_words {pre w post : List Char} (hw : w ≠ []) (hall : w.all wordChar = true)
    (hpre : wordChar (pre.getLast?.getD ' ') = false) (hpost : wordChar (post.head?.getD ' ') = false) :
    String.ofList w ∈ wordsGo (pre ++ w ++ post) [] := by
  have hsp : wordChar ' ' = false := by decide
  have hstart : ∃ ws, wordsGo (pre ++ (w ++ post)) [] = ws ++ wordsGo (w ++ post) [] := by
    cases pre with
    | nil => exact ⟨[], rfl⟩
    | cons c cs =>
      exact wordsGo_after (by simp) (by simpa [List.getLast?_cons] using hpre)
  obtain ⟨ws, hs⟩ := hstart
  rw [List.append_assoc, hs, wordsGo_word hall, List.append_nil]
  have hflush : flush w.reverse = [String.ofList w] := by
    simp [flush, hw]
  apply List.mem_append_right
  cases post with
  | nil => rw [wordsGo, hflush]; exact List.mem_singleton_self _
  | cons c cs =>
    simp only [List.head?_cons, Option.getD_some] at hpost
    rw [wordsGo, ite_eq_right (by simp [hpost]), hflush]
    exact List.mem_append_left _ (List.mem_singleton_self _)

/-- What the plain-text check finds in a `replace=` text: a `#`, an `@[`, and each banned word. -/
def replaceProblems (r : String) : List String :=
  (if r.toList.contains '#' then ["`#`: no `#` command is allowed"] else []) ++
  (if (splitFirst "@[".toList r.toList).isSome then ["`@[`: no attribute is allowed"] else []) ++
  ((words r).filter (bans.contains ·)).map fun w => s!"`{w}` is not allowed in a case's Lean text"

/-- Every banned word is a run of `wordChar`s. -/
theorem bans_words : ∀ b ∈ bans, b.toList ≠ [] ∧ b.toList.all wordChar = true := by
  decide

/-- **A `replace=` text the plain-text check passes** has no `#`, no `@[`, and no banned word
standing alone: wherever a banned word occurs in it, it is part of a longer word. -/
theorem replaceProblems_banned {r : String} (h : replaceProblems r = []) :
    '#' ∉ r.toList ∧ (∀ pre post, r.toList ≠ pre ++ "@[".toList ++ post) ∧
      ∀ b ∈ bans, ∀ pre post, r.toList = pre ++ b.toList ++ post →
        wordChar (pre.getLast?.getD ' ') = true ∨ wordChar (post.head?.getD ' ') = true := by
  simp only [replaceProblems, List.append_eq_nil_iff, ite_eq_right_iff, reduceCtorEq, imp_false,
    List.map_eq_nil_iff, List.filter_eq_nil_iff, Bool.not_eq_true] at h
  obtain ⟨⟨hhash, hat⟩, hw⟩ := h
  refine ⟨by simpa using hhash, fun pre post he => ?_, fun b hb pre post he => ?_⟩
  · have := splitFirst_isSome (pat := "@[".toList) (pre := pre) (post := post) he
    rw [hat] at this
    simp at this
  · apply Classical.byContradiction
    intro hc
    simp only [not_or, Bool.not_eq_true] at hc
    obtain ⟨hne, hall⟩ := bans_words b hb
    have hmem : String.ofList b.toList ∈ words r := by
      unfold words
      rw [he]
      exact mem_words hne hall hc.1 hc.2
    simp only [String.ofList_toList] at hmem
    have := hw b hmem
    simp [hb] at this

/-! ## Which files a case's lint covers -/

/-- The files a case's edits change, each once, with the kind of source it is. -/
def targets (m : Mutant) : List (String × Kind) :=
  (m.edits.map (·.file)).eraseDups.map fun p => (p, Kind.ofPath p)

/-- **Every file an edit changes is linted**, whole and after all the edits, as the kind of source
its path says. -/
theorem mem_targets {m : Mutant} {e : Edit} (he : e ∈ m.edits) :
    (e.file, Kind.ofPath e.file) ∈ targets m := by
  simp only [targets, List.mem_map]
  exact ⟨e.file, List.mem_eraseDups.mpr (List.mem_map_of_mem he), rfl⟩

/-! ## Reading a source with Lean's parser (not proved) -/

/-- Lean's own syntax, `Init` alone: the approved core imports nothing else, and a source that
passes the lint adds no syntax, so this is the syntax every case source is elaborated with. -/
def syntaxEnv : IO Environment := do
  unsafe enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules #[{ module := `Init }] {} (loadExts := true)

private def posOf (fm : FileMap) (stx : Syntax) : Pos :=
  let p := fm.toPosition (stx.getPos?.getD 0)
  (p.line, p.column + 1)

private def headOf (fm : FileMap) (stx : Syntax) : String :=
  ((MitosGate.Lint.tokensOf fm stx #[])[0]?.map (·.text)).getD (toString stx.getKind)

/-- Every attribute in `stx`, wherever it is. -/
partial def attributesOf (fm : FileMap) (stx : Syntax) (acc : Array (Pos × String)) :
    Array (Pos × String) :=
  match stx with
  | .node _ k args =>
    let acc := if k == ``Parser.Term.attrInstance then acc.push (posOf fm stx, headOf fm stx) else acc
    args.foldl (fun a s => attributesOf fm s a) acc
  | _ => acc

/-- What the lint reads of `src`, from Lean's parse of it with `env`'s syntax. -/
def read (env : Environment) (src : String) : IO Source := do
  match ← MitosGate.Lint.parse env src with
  | .error v => return { unparsed := some ((v.line, v.col), v.msg) }
  | .ok (fm, header, cmds) =>
    let mut modifiers := #[]
    let mut imports := #[]
    if !MitosGate.Lint.isEmptyNode header[0] then modifiers := modifiers.push (posOf fm header[0], "module")
    if !MitosGate.Lint.isEmptyNode header[1] then modifiers := modifiers.push (posOf fm header[1], "prelude")
    for imp in header[2].getArgs do
      unless MitosGate.Lint.isEmptyNode imp[0] && MitosGate.Lint.isEmptyNode imp[1] &&
          MitosGate.Lint.isEmptyNode imp[3] do
        modifiers := modifiers.push (posOf fm imp, s!"{headOf fm imp} import")
      let (text, mod) := match imp[4] with
        | .ident _ _ n _ => (n.toString, MitosGate.Lint.plainComponents n)
        | stx => (toString stx, none)
      imports := imports.push (posOf fm imp, text, mod)
    let commands := cmds.map fun cmd =>
      let kind := if cmd.getKind == ``Parser.Command.declaration then cmd[1].getKind else cmd.getKind
      (posOf fm cmd, headOf fm cmd, toString kind)
    let attributes := cmds.foldl (fun a c => attributesOf fm c a) #[]
    let tokens := (cmds.foldl (fun a c => MitosGate.Lint.tokensOf fm c a)
      (MitosGate.Lint.tokensOf fm header #[])).map fun t => ((t.line, t.col), t.text)
    return { modifiers := modifiers.toList, imports := imports.toList, commands := commands.toList,
             attributes := attributes.toList, tokens := tokens.toList }

/-- Each finding of the lint in `src`, as `<file>:<line>:<col>: <what>`. -/
def check (env : Environment) (k : Kind) (file src : String) : IO (List String) := do
  return (problems k (← read env src)).map fun ((l, c), msg) => s!"{file}:{l}:{c}: {msg}"

end Mutants.Lint
