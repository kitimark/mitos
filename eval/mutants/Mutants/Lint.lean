import MitosGate.Lint
import Mutants.Manifest

/-!
# The lint: a case's Lean text runs no code, declares no syntax, and names its top-level declarations only where it may

A case supplies Lean source twice: the `replace=` text of its edits, which ends up in the mutated
`Mitos/Impl/` modules (and, for a known gap, in its proof repairs under `Mitos/Proofs/`), and its
`Refute.lean`. Lean runs code while it elaborates source: a macro or notation rewrites the syntax
that follows it, in that module and in every module that imports it; `#eval`, `run_cmd`, an
elaborator or an `initialize` runs arbitrary code, file IO included; `include_str` reads a file.
The generated Challenges import the mutated `Mitos/Impl/` modules before the approved statement
lines, so such code in an implementation edit can change what a Challenge states (review on #86,
round 2: a `macro_rules` that turns `Mitos.Spec.AssumptionsExact _` into `False`), or make the
implementation elaborate to another resolver in the run that holds the case's file (an
`include_str` inside `first | … | …`, or `run_cmd` testing whether the file exists). So can a plain
declaration: Lean resolves a name in the namespaces around it first, so an implementation that
declared `Mitos.Refute.Mitos.Spec.AssumptionsExact := False` changed what the refutation Challenge,
elaborated in namespace `Mitos.Refute`, stated (review on #86, round 3). The Challenges now declare
every theorem at the root and write every name as `_root_.<name>` (`Mutants.qualify`), where Lean
looks a name up exactly, and that is what keeps a shadow from changing a statement, whatever names
a case declares (`Mutants.Resolution` checks it at every build). The lint's name rules below are
defence in depth: they read the names of top-level declarations, not nested ones.

So before any build, the runner lints every text a case wrote or changed, and judges no case the
lint finds anything in. The lint is an allow-list, read from Lean's own parse (`read`, with the
syntax of `Init` alone and none of its scoped syntax, which is all the approved core and the
implementation see, since a text that passes enters and opens only namespaces under `Mitos`):

- **imports** (`Kind.imports`): only modules under `Mitos.Core` and `Mitos.Impl` (and
  `Mitos.Proofs` in a proof repair), each a plain `import`, and no `module` or `prelude` header;
- **commands** (`allowedCommands`): only a module doc, `namespace`, `section`, `end`, `open`, and
  `def`, `theorem`, `abbrev` and `example` declarations. Lean elaborates each of these with its
  built-in code, which adds declarations and runs nothing the case wrote;
- **no attribute** anywhere (`@[…]`), so no `@[macro]`, `@[implemented_by]`, `@[instance]` or
  `@[simp]` either;
- **tokens** (`tokenOk`): no `#` command, and no token with a component in `bans`, which is gate
  1's plugin list (`MitosGate.Lint.banned`: `macro`, `macro_rules`, `syntax`, `notation`, `elab`,
  `run_cmd`, `initialize`, `include_str`, `instance`, `scoped`, `export`, `Lean`, `native_decide`,
  `sorry`, …), the term and tactic forms that run code inside an allowed declaration (`by_elab`,
  `run_tac`), `set_option` and `attribute` anywhere, also inside a declaration, `deriving`, the
  one allowed form that would add an instance, which the elaboration of every module that imports
  it could pick up, and `with_decl_name`, also as the token `with_decl_name%` (`bannedComponent`),
  which names the `let rec`s inside it under any absolute namespace (review on #86, round 4);
- **names** (`Kind.declOk`, `nsOk`, `openOk`, over `walk`, which follows `namespace`, `section`
  and `end` as Lean does): the name of every top-level `def`, `theorem` and `abbrev` lies under
  `Mitos.Impl` in an implementation file, under `Mitos.Refute` in a `Refute.lean` (or is an
  approved definition hole, which the hole run and the comparison by value judge), and under
  `Mitos` in a proof repair, with no `_root_` component but its leading one; and every `namespace`
  and every `open` (in a command, a term or a tactic) names a namespace under `Mitos`. Names
  declared inside a declaration are not read: Lean declares a `let rec` or `where` name under the
  declaration's own name, one written `_root_.X` as `<decl>._root_.X`, with an inner `_root_`
  (review on #86, round 4). So these rules do not show that no name a case declares is one a
  generated Challenge could resolve to; the root declarations and absolute names of
  `Mutants.Challenge` show that. What the namespace and `open` rules do show is that the case
  switches on no scoped syntax: entering or opening a namespace switches on its scoped syntax
  (`open Int` adds `-[n+1]`, review on #86, round 3), and under `Mitos` there is none, since the
  approved core declares no syntax and a text that passes declares none.

A text Lean's parser cannot read to its end is refused too. `problems_eq_nil_iff` states what a
source with no finding satisfies.

The `replace=` text of every edit is also checked as plain text, without Lean's parser
(`replaceProblems`): no `#`, no `@[`, and no word of `bans` standing alone
(`replaceProblems_banned`).

**The premise.** Lean elaborates a module that passes the lint from its own text and the modules it
imports, with the syntax of `Init`, and its elaboration runs no code of the case and adds no syntax
or instance. The lint limits those imports to the approved core and the implementation, whose texts
are the same in every run (`Mutants.holeCore_impl`), so the implementation elaborates the same in
every run, whichever other files a run holds; and the Challenges that import it state exactly the
approved statements, since they declare every theorem at the root and name everything absolutely,
so Lean looks each name up exactly, whatever names the case declares (`Mutants.Challenge`).
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
  /-- The case's `Refute.lean`, with the approved definition holes, as their components. -/
  | refute (holes : List (List String))
  deriving Repr, DecidableEq

/-- The module prefixes a source of each kind may import. -/
def Kind.imports : Kind → List String
  | .impl | .refute _ => ["Mitos.Core", "Mitos.Impl"]
  | .proofs => ["Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def Kind.ofPath (path : String) : Kind :=
  if inArea "Impl" path then .impl else .proofs

/-- A line and a column. -/
abbrev Pos := Nat × Nat

/-- A command that opens or closes a scope, or names a declaration, as the lint reads it (`read`).
Each name is its components, or `none` if one of them is not a plain identifier. -/
inductive Scoped where
  /-- `namespace A.B`. -/
  | ns (name : Option (List String))
  /-- `section`, or `section A.B`. -/
  | sec (name : Option (List String))
  /-- `end`, or `end A.B`. -/
  | close (name : Option (List String))
  /-- A `def`, `theorem` or `abbrev`, named as written. -/
  | decl (name : Option (List String))
  deriving Repr, DecidableEq

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
  /-- Each top-level `namespace`, `section`, `end` and named declaration, in order, with its keyword
  and name as written. -/
  scopes     : List (Pos × String × Scoped) := []
  /-- Each namespace an `open` names, in a command, a term or a tactic: as written, and its
  components if they are plain identifiers. -/
  opens      : List (Pos × String × Option (List String)) := []
  deriving Repr, DecidableEq

/-- The commands a case's source may contain, by kind; a declaration by the kind of what it
declares. -/
def allowedCommands : List String :=
  [``Parser.Command.moduleDoc, ``Parser.Command.namespace, ``Parser.Command.section,
    ``Parser.Command.end, ``Parser.Command.open, ``Parser.Command.definition,
    ``Parser.Command.theorem, ``Parser.Command.abbrev, ``Parser.Command.example].map toString

/-- Words no token may have as a component: gate 1's plugin list, the term and tactic forms that
run code at elaboration inside an allowed declaration, `set_option` and `attribute`, which the
command allow-list leaves out at the top level, also inside a term or a tactic block, `deriving`,
which would add an instance to every module that imports the text, and `with_decl_name`: the term
`with_decl_name% N (let rec x … ; …)` declares `N.x`, with `N` taken as an absolute name, a nested
name that `walk` does not read (review on #86, round 4). -/
def bans : List String :=
  MitosGate.Lint.banned ++
    ["by_elab", "run_tac", "set_option", "attribute", "deriving", "with_decl_name"]

/-- A component is banned when it is a word of `bans`, or one followed by `%`, the way the keyword
of a term elaborator such as `with_decl_name%` ends. -/
def bannedComponent (c : String) : Bool :=
  bans.contains c || bans.any fun b => c == b ++ "%"

/-- A token passes: it is no `#` command, and none of its components is banned. -/
def tokenOk (t : String) : Bool :=
  !t.startsWith "#" && (MitosGate.Lint.components t).all fun c => !bannedComponent c

theorem tokenOk_iff {t : String} :
    tokenOk t = true ↔ t.startsWith "#" = false ∧
      ∀ c ∈ MitosGate.Lint.components t, c ∉ bans ∧ ∀ b ∈ bans, c ≠ b ++ "%" := by
  simp [tokenOk, bannedComponent]

/-! ## Names -/

/-- What `walk` finds at a scope command. -/
inductive Found where
  /-- The namespace a `namespace` command makes current. -/
  | entered (ns : List String)
  /-- The full name of a declaration. -/
  | declared (name : List String)
  /-- A name with a component that is not a plain identifier. -/
  | unreadable
  /-- An `end` that closes more scopes than are open. -/
  | unbalanced
  deriving Repr, DecidableEq

/-- The full name Lean gives a declaration named `n` in namespace `cur`: a leading `_root_` drops
the namespace (`Lean.Elab.mkDeclName`), and otherwise the name is relative to it. -/
def fullName (cur : List String) : List String → List String
  | "_root_" :: rest => rest
  | n => cur ++ n

/-- The scopes `namespace n` opens in namespace `cur`, innermost first: one per component, as
Lean's `addScopes` does. -/
def nsScopes (cur n : List String) : List (List String) :=
  ((List.range n.length).map fun i => cur ++ n.take (i + 1)).reverse

/-- Follows the scopes as Lean's `namespace`, `section` and `end` do: `st` holds the namespace of
each open scope, innermost first, and the root scope is not in it. `end` closes as many scopes as
its name has components (one without a name), and Lean refuses one that closes the root. -/
def walk : List (List String) → List (Pos × String × Scoped) → List (Pos × String × Found)
  | _, [] => []
  | st, (p, t, c) :: cs =>
    let cur := st.headD []
    match c with
    | .ns (some n) => (p, t, .entered (cur ++ n)) :: walk (nsScopes cur n ++ st) cs
    | .sec (some n) => walk (List.replicate (max 1 n.length) cur ++ st) cs
    | .close (some n) =>
      if max 1 n.length ≤ st.length then walk (st.drop (max 1 n.length)) cs
      else (p, t, .unbalanced) :: walk [] cs
    | .decl (some n) => (p, t, .declared (fullName cur n)) :: walk st cs
    | .ns none | .sec none | .close none | .decl none => (p, t, .unreadable) :: walk st cs

/-- `pre` and at least one more component. -/
def strictlyUnder (pre name : List String) : Bool :=
  pre.isPrefixOf name && pre.length < name.length

/-- A namespace a case may enter or open: under `Mitos`, with no `_root_` component. -/
def nsOk (ns : List String) : Bool :=
  ns.head? == some "Mitos" && !ns.contains "_root_"

/-- The names a top-level declaration may have, by the kind of source: under `Mitos.Impl` in an
implementation file, under `Mitos.Refute` or an approved hole in a `Refute.lean`, under `Mitos` in a
proof repair; and never with a `_root_` component. Names declared inside a declaration (`let rec`,
`where`) are not read. -/
def Kind.declOk (k : Kind) (name : List String) : Bool :=
  !name.contains "_root_" &&
    match k with
    | .impl => strictlyUnder ["Mitos", "Impl"] name
    | .refute holes => strictlyUnder ["Mitos", "Refute"] name || holes.contains name
    | .proofs => strictlyUnder ["Mitos"] name

def Kind.foundOk (k : Kind) : Found → Bool
  | .entered ns => nsOk ns
  | .declared n => k.declOk n
  | .unreadable | .unbalanced => false

/-- An `open` passes if it names, as written, a namespace under `Mitos`. Inside a namespace Lean
also tries it relative to the namespaces around it, which `walk` keeps under `Mitos` too. -/
def openOk : Option (List String) → Bool
  | some ns => nsOk ns
  | none => false

def foundProblem (k : Kind) (t : String) : Found → String
  | .entered ns => s!"`{t}` enters `{".".intercalate ns}`; a case may enter only namespaces under `Mitos`, which hold no scoped syntax"
  | .declared n =>
    let where_ := match k with
      | .impl => "under `Mitos.Impl`"
      | .refute _ => "under `Mitos.Refute` (or an approved definition hole)"
      | .proofs => "under `Mitos`"
    s!"`{t}` declares `{".".intercalate n}`; this file may declare names only {where_}, with no `_root_` inside"
  | .unreadable => s!"`{t}`: a name with a component that is not a plain identifier is not allowed"
  | .unbalanced => s!"`{t}` closes more scopes than are open"

def importOk (k : Kind) : Option (List String) → Bool
  | some mod => MitosGate.Lint.moduleAllowed k.imports mod
  | none => false

/-- The last component of a kind, for messages. -/
def shortKind (k : String) : String :=
  ((k.splitOn ".").getLast?).getD k

def tokenProblem (t : String) : String :=
  if t.startsWith "#" then s!"`{t}`: no `#` command is allowed"
  else
    let c := ((MitosGate.Lint.components t).find? bannedComponent).getD t
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
    s.tokens.filterMap (fun (p, t) => if tokenOk t then none else some (p, tokenProblem t)) ++
    (walk [] s.scopes).filterMap (fun (p, t, f) =>
      if k.foundOk f then none else some (p, foundProblem k t f)) ++
    s.opens.filterMap (fun (p, t, ns) =>
      if openOk ns then none
      else some (p, s!"`open {t}` is not allowed; a case may open only namespaces under `Mitos`, which hold no scoped syntax"))

/-- **What a source with no finding is**: Lean's parser reads it to the end; it has a plain header
whose every import lies under the kind's prefixes; every top-level command is one of
`allowedCommands`; it has no attribute; every token passes `tokenOk`; following its scopes, every
namespace it enters lies under `Mitos` and every top-level declaration has a name the kind may
declare (`Kind.declOk`), with no unreadable name and no unbalanced `end`; and every namespace it
opens lies under `Mitos`. -/
theorem problems_eq_nil_iff {k : Kind} {s : Source} :
    problems k s = [] ↔
      s.unparsed = none ∧ s.modifiers = [] ∧
      (∀ i ∈ s.imports, ∃ mod, i.2.2 = some mod ∧ MitosGate.Lint.moduleAllowed k.imports mod = true) ∧
      (∀ c ∈ s.commands, c.2.2 ∈ allowedCommands) ∧ s.attributes = [] ∧
      (∀ t ∈ s.tokens, tokenOk t.2 = true) ∧
      (∀ f ∈ walk [] s.scopes, k.foundOk f.2.2 = true) ∧
      ∀ o ∈ s.opens, openOk o.2.2 = true := by
  obtain ⟨u, ms, is, cs, as, ts, sc, os⟩ := s
  cases u with
  | some x => simp [problems]
  | none =>
    simp only [problems, List.append_eq_nil_iff, List.map_eq_nil_iff, List.filterMap_eq_nil_iff,
      ite_eq_left_iff, reduceCtorEq, imp_false, Bool.not_eq_true, true_and]
    constructor
    · rintro ⟨⟨⟨⟨⟨⟨hm, hi⟩, hc⟩, ha⟩, ht⟩, hw⟩, ho⟩
      refine ⟨hm, fun i hi' => ?_, fun c hc' => ?_, ha, fun t ht' => ?_, fun f hf => ?_,
        fun o ho' => ?_⟩
      · obtain ⟨p, t, mod⟩ := i
        have := hi _ hi'
        cases mod with
        | none => simp [importOk] at this
        | some m => exact ⟨m, rfl, by simpa [importOk] using this⟩
      · have := hc _ hc'
        simpa using this
      · have := ht _ ht'
        simpa using this
      · have := hw _ hf
        simpa using this
      · have := ho _ ho'
        simpa using this
    · rintro ⟨hm, hi, hc, ha, ht, hw, ho⟩
      refine ⟨⟨⟨⟨⟨⟨hm, fun i hi' => ?_⟩, fun c hc' => ?_⟩, ha⟩, fun t ht' => ?_⟩,
        fun f hf => ?_⟩, fun o ho' => ?_⟩
      · obtain ⟨m, hm', ha'⟩ := hi i hi'
        obtain ⟨p, t, mod⟩ := i
        simp only at hm'
        subst hm'
        simp [importOk, ha']
      · simpa using hc c hc'
      · simpa using ht t ht'
      · simpa using hw f hf
      · simpa using ho o ho'

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

/-- Lean's own syntax, `Init` alone, with no scoped syntax switched on: the approved core imports
nothing else and declares no syntax, and a source that passes the lint adds none and enters and
opens only namespaces under `Mitos`, so it switches on none of `Init`'s scoped syntax (`open Int`
would add `-[n+1]`). So this is the syntax Lean parses every such source with. -/
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

/-- A name's components, if each is a plain identifier. -/
private def partsOf (stx : Syntax) : Option (List String) :=
  match stx with
  | .ident _ _ n _ => MitosGate.Lint.plainComponents n
  | _ => none

/-- The optional name of a `section` or an `end`: `some []` when there is none, and `none` when it
is not a plain name (or, for `end`, has a trailing dot). -/
private def optName (opt : Syntax) : Option (List String) :=
  if MitosGate.Lint.isEmptyNode opt then some []
  else if opt[0].isIdent && (opt.getNumArgs == 1 || MitosGate.Lint.isEmptyNode opt[1]) then partsOf opt[0]
  else if opt.isIdent then partsOf opt
  else none

/-- What a top-level command does to the scopes, if anything, with the command's keyword and name
for messages. -/
private def scopedOf (fm : FileMap) (cmd : Syntax) : Option (String × Scoped) :=
  let k := cmd.getKind
  let text (kw : String) (stx : Syntax) : String :=
    " ".intercalate (kw :: (MitosGate.Lint.tokensOf fm stx #[]).toList.map (·.text))
  if k == ``Parser.Command.namespace then some (text "namespace" cmd[1], .ns (partsOf cmd[1]))
  else if k == ``Parser.Command.section then some (text "section" cmd[2], .sec (optName cmd[2]))
  else if k == ``Parser.Command.end then some (text "end" cmd[1], .close (optName cmd[1]))
  else if k == ``Parser.Command.declaration then
    let d := cmd[1]
    if d.getKind == ``Parser.Command.definition || d.getKind == ``Parser.Command.theorem ||
        d.getKind == ``Parser.Command.abbrev then
      some (text (headOf fm d) d[1][0], .decl (partsOf d[1][0]))
    else none
  else none

/-- Every identifier in `stx`. -/
private partial def identsOf (stx : Syntax) (acc : Array Syntax) : Array Syntax :=
  match stx with
  | .ident .. => acc.push stx
  | .node _ _ args => args.foldl (fun a s => identsOf s a) acc
  | _ => acc

/-- Every namespace an `open` in `stx` names, wherever the `open` is: all of an `open A B` or
`open scoped A B`, and the first of an `open A (x)`, `open A hiding x` or `open A renaming x → y`. -/
partial def opensOf (fm : FileMap) (stx : Syntax) (acc : Array (Pos × String × Option (List String))) :
    Array (Pos × String × Option (List String)) :=
  match stx with
  | .node _ k args =>
    let found : Array Syntax :=
      if k == ``Parser.Command.openSimple || k == ``Parser.Command.openScoped then identsOf stx #[]
      else if k == ``Parser.Command.openOnly || k == ``Parser.Command.openHiding ||
          k == ``Parser.Command.openRenaming then #[stx[0]]
      else #[]
    let acc := found.foldl (fun a i => a.push (posOf fm i, headOf fm i, partsOf i)) acc
    args.foldl (fun a s => opensOf fm s a) acc
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
    let scopes := cmds.filterMap fun cmd => (scopedOf fm cmd).map fun (t, c) => (posOf fm cmd, t, c)
    let opens := cmds.foldl (fun a c => opensOf fm c a) #[]
    return { modifiers := modifiers.toList, imports := imports.toList, commands := commands.toList,
             attributes := attributes.toList, tokens := tokens.toList, scopes := scopes.toList,
             opens := opens.toList }

/-- Each finding of the lint in `src`, as `<file>:<line>:<col>: <what>`. -/
def check (env : Environment) (k : Kind) (file src : String) : IO (List String) := do
  return (problems k (← read env src)).map fun ((l, c), msg) => s!"{file}:{l}:{c}: {msg}"

-- `walk` follows Lean's scopes: a declaration in `namespace Mitos.Impl` gets that prefix, `_root_`
-- drops it, `end` closes one scope per component, `section` keeps the namespace, and an `end` that
-- would close the root is reported.
#guard (walk [] [((1, 1), "namespace", .ns (some ["Mitos", "Impl"])), ((2, 1), "def", .decl (some ["f"])),
    ((3, 1), "section", .sec (some [])), ((4, 1), "def", .decl (some ["Refute", "g"])),
    ((5, 1), "end", .close (some [])), ((6, 1), "end", .close (some ["Impl"])),
    ((7, 1), "def", .decl (some ["h"])), ((8, 1), "end", .close (some ["Mitos"])),
    ((9, 1), "def", .decl (some ["Mitos", "Refute", "Mitos", "Spec", "X"])),
    ((10, 1), "def", .decl (some ["_root_", "Mitos", "Impl", "k"])),
    ((11, 1), "end", .close (some []))]).map (·.2.2) =
  [.entered ["Mitos", "Impl"], .declared ["Mitos", "Impl", "f"], .declared ["Mitos", "Impl", "Refute", "g"],
    .declared ["Mitos", "h"], .declared ["Mitos", "Refute", "Mitos", "Spec", "X"],
    .declared ["Mitos", "Impl", "k"], .unbalanced]
#guard (walk [] [((1, 1), "namespace", .ns (some ["Mitos"])), ((2, 1), "namespace", .ns (some ["Impl"])),
    ((3, 1), "def", .decl (some ["_root_", "Mitos", "Refute", "x"])), ((4, 1), "end", .close (some ["Mitos", "Impl"])),
    ((5, 1), "namespace", .ns none)]).map (·.2.2) =
  [.entered ["Mitos"], .entered ["Mitos", "Impl"], .declared ["Mitos", "Refute", "x"], .unreadable]
-- What each kind may declare and enter.
#guard Kind.impl.declOk ["Mitos", "Impl", "resolve"] && !Kind.impl.declOk ["Mitos", "Impl"] &&
  !Kind.impl.declOk ["Mitos", "Refute", "Mitos", "Spec", "X"] && !Kind.impl.declOk ["Mitos", "Mitos", "Impl", "resolve"] &&
  !Kind.impl.declOk ["Mitos", "Impl", "_root_", "x"]
#guard (Kind.refute [["Mitos", "Impl", "resolve"]]).declOk ["Mitos", "Impl", "resolve"] &&
  (Kind.refute [["Mitos", "Impl", "resolve"]]).declOk ["Mitos", "Refute", "Impl", "resolve"] &&
  !(Kind.refute [["Mitos", "Impl", "resolve"]]).declOk ["Mitos", "Impl", "helper"]
#guard Kind.proofs.declOk ["Mitos", "Impl", "resolve"] && !Kind.proofs.declOk ["Int", "x"]
#guard nsOk ["Mitos", "Impl"] && !nsOk ["Int"] && !nsOk ["Mitos", "_root_"] && !nsOk []
-- `with_decl_name%` is refused as a token and, in a `replace=` text, as a plain word.
#guard tokenOk "Mitos.Impl.resolve" && tokenOk "decl_name%" && !tokenOk "with_decl_name%" &&
  !tokenOk "with_decl_name" && !tokenOk "macro_rules" && !tokenOk "Mitos.deriving"
#guard replaceProblems "def a := with_decl_name% N (let rec x := 0; 0)" ==
  ["`with_decl_name` is not allowed in a case's Lean text"]

end Mutants.Lint
