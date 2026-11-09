import Lean.Meta.AppBuilder
import MitosGate.Lint
import Mutants.CrossCheck

/-!
# Lean's parse of the approved Challenge, and each generated Challenge as Lean builds it

Rounds 6 to 9 of the review on #86 each found Lean syntax that the line reader
(`Mutants.readChallenge`) reads otherwise than Lean, and round 9's cross-check
(`Mutants.CrossCheck`) compares only what the approved Challenge **declares**. Round 10 found a
command that declares nothing in a line the reader keeps as a comment: after a module doc's opener,
a line comment that ends with a closer, a declaration doc comment and another such line comment,
the rest of the last line is code, so `variable (h : False) in include h in` there prefixes the
next declaration (`b1Source` below). In the approved Challenge that is a hole whose value stays
`sorry`, so the cross-check agrees. The generated Challenges drop the hole lines and the theorems
not named, so in the refutation Challenge the prefix lands on `Mitos.Refute.resolve_total`, which
then states `False → ¬ Total resolve`; a case proved that by `h.elim` and was judged REFUTED (review
on #86, round 10, the opus verifier at a528c7e, B1). A hidden trailing `namespace` or `#exit` is
also a command that declares nothing.

So the runner no longer rests on reading the input as Lean does. It checks two things with Lean
itself, after the cross-check and before it prepares or judges any case, and any difference stops
it (exit 2) with each difference named:

- **The input, by Lean's parse** (`parseProblems`). Lean's parser, with the syntax of the modules
  the Challenge imports, reads the approved Challenge as its header and its commands. Every command
  must be a module doc or exactly one of the reader's hole or theorem lines: a declaration that
  starts at column 0 of the line the reader read it from and whose text is that whole line. Every
  such line of the reader must be one, and the header must import exactly the reader's import
  lines, in order, each a plain `import`. So the lines the reader keeps as comments or blanks are,
  to Lean's parser, module docs, comments or whitespace, and hold no command (`parseProblems_nil`).
  A declaration doc comment starts its declaration's command, so a hole or theorem may have none.
- **The output, by Lean's build** (`outProblems`). The runner computes the text of every Challenge
  it will judge with, as it writes it (`refutationGen`, `valuesGen`): the values Challenge, and the
  refutation Challenge of each distinct `breaks=` list of the cases it runs or prepares. It builds
  each one with `lake build` in the same fresh copy of the approved core as the cross-check, loads
  it as Lean built it, and requires its constants to be exactly the ones it is meant to state, each
  a theorem with no universe parameter whose type is, as an `Expr`, exactly what it is meant to be
  (`Want`): `Not T` for `Mitos.Refute.<n>` and `T` for `Mitos.Proofs.<n>` in the values Challenge,
  where `T` is the type of the theorem `Mitos.Proofs.<n>` of the approved Challenge module as Lean
  built it; and for `Mitos.Refute.holes`, the equation `(h₁, …) = (h₁, …)` over the configured
  definition holes, as `Lean.Meta.mkAppM` and `Lean.Meta.mkEq` build it in the approved Challenge's
  environment. The comparison is `Expr` equality (`==`, which ignores binder names) after each
  universe level is normalized (`sameType`): no unfolding and no definitional equality. The
  module's imports must be `Init`, the implementation modules and the reader's import lines. The
  refutation Challenge's names are the ones the comparator compares
  (`refutationGen_names`), and the runner writes no Challenge text the check did not pass
  (`Main.prepare`).

**What the output check does not see.** It builds each generated text with the approved
implementation, because the runner never builds a case's code outside the comparator's sandbox
(task file, Binding a refutation to the mutant); the case's own run imports the mutated
`Mitos/Impl/` modules instead. That
those change nothing in how the text elaborates rests, as before, on the lint (no syntax, no code
run at elaboration) and on the absolute names (`Mutants.Challenge`), not on this check. The parse
check is what rules out a hidden command in the approved Challenge whose effect could depend on the
implementation or on the module's name (the check builds each text under its own module name). It
reads Lean's parse with the syntax of the Challenge's imports, which is the syntax Lean builds it
with as long as the Challenge declares none itself, and a command that declares syntax is itself a
command the parse check refuses.

**Probes.** As in round 9, so that neither check goes blind unnoticed: the parse check must find
its known problem in five scratch sources (`parseProbes`: `b1Source`, a trailing hidden
`namespace Mitos.Impl`, a trailing hidden `#exit`, and round 9's decoy and reverse), and the
output check, every run, in the refutation Challenges generated from two scratch approved
Challenges built in the same workspace (`outProbes`: `b1Source`, whose `resolve_total` differs, and
the trailing `#exit`, which drops `Mitos.Refute.holes`). A trailing hidden `namespace Mitos.Impl`
changes no constant of the generated Challenge, whose declarations are all named with `_root_`, so
the output check rightly finds nothing there; the parse check stops it.

**Cost.** A second `lake build` in the cross-check's workspace builds the generated Challenges (11
for the whole corpus) and the probes, and the runner imports each one: about 13 s per run for the
three checks together (task file, round 10).
-/

namespace Mutants.Output

open Lean CrossCheck

/-! ## Lean's parse of the approved Challenge -/

/-- A top-level command as Lean's parser read it: the line (from 1) and column (from 0, in
characters) where it starts, its syntax kind, and its text from its first to its last token. -/
structure Cmd where
  line : Nat
  col  : Nat
  kind : String
  text : String
  deriving DecidableEq, Repr

def moduleDocKind : String := toString ``Parser.Command.moduleDoc
def declKind : String := toString ``Parser.Command.declaration

/-- The reader's hole and theorem lines, each with its line number and text, the first line being
line `k`. -/
def declLinesFrom : Nat → List Line → List (Nat × String)
  | _, [] => []
  | k, .thm _ _ t :: ls => (k, t) :: declLinesFrom (k + 1) ls
  | k, .hole t :: ls => (k, t) :: declLinesFrom (k + 1) ls
  | k, _ :: ls => declLinesFrom (k + 1) ls

/-- The reader's hole and theorem lines, the first line being line 1. -/
def declLines (ls : List Line) : List (Nat × String) := declLinesFrom 1 ls

/-- Whether the command is exactly the line `l`: a declaration that starts at column 0 of line
`l.1` and whose text is `l.2`. -/
def Cmd.isLine (c : Cmd) (l : Nat × String) : Bool :=
  c.kind == declKind && c.line == l.1 && c.col == 0 && c.text == l.2

/-- A difference between the reader's lines and Lean's parse of the Challenge. -/
inductive ParseProblem where
  /-- Lean reads this command; it is no module doc and no hole or theorem line of the reader. -/
  | command (c : Cmd)
  /-- The reader read this line as a hole or theorem; no command of Lean's parse is that line. -/
  | missing (line : Nat) (text : String)
  /-- Lean's header has this: a `module` or `prelude` keyword, or an import with a modifier. -/
  | header (what : String)
  /-- The reader's imports, and the modules Lean's header imports, in order. -/
  | imports (read lean : List String)
  deriving DecidableEq, Repr

/-- Every difference between the reader's lines `ls` and Lean's parse of the Challenge: the
header's findings `hdr`, its imports `imps`, and the commands `cmds`. -/
def parseProblems (ls : List Line) (hdr imps : List String) (cmds : List Cmd) : List ParseProblem :=
  let dl := declLines ls
  (cmds.filter fun c => !(c.kind == moduleDocKind || dl.any c.isLine)).map .command ++
    (dl.filter fun l => !cmds.any (·.isLine l)).map (fun l => .missing l.1 l.2) ++
    hdr.map .header ++
    (if imps == importNames ls then [] else [.imports (importNames ls) imps])

/-- **What an agreement with Lean's parse means.** Every command Lean reads is a module doc or
exactly one of the reader's hole or theorem lines, every such line is one, the header has nothing
but plain imports, and it imports exactly the reader's import lines, in order. -/
theorem parseProblems_nil {ls : List Line} {hdr imps : List String} {cmds : List Cmd}
    (h : parseProblems ls hdr imps cmds = []) :
    (∀ c ∈ cmds, c.kind = moduleDocKind ∨ ∃ l ∈ declLines ls, c.isLine l = true) ∧
      (∀ l ∈ declLines ls, ∃ c ∈ cmds, c.isLine l = true) ∧ hdr = [] ∧ imps = importNames ls := by
  unfold parseProblems at h
  simp only [List.append_eq_nil_iff, List.map_eq_nil_iff, List.filter_eq_nil_iff] at h
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
  refine ⟨fun c hc => ?_, fun l hl => ?_, h3, ?_⟩
  · have := h1 c hc
    cases hk : c.kind == moduleDocKind
    · cases ha : (declLines ls).any c.isLine
      · simp [hk, ha] at this
      · exact .inr (List.any_eq_true.mp ha)
    · exact .inl (by simpa using hk)
  · have := h2 l hl
    cases ha : cmds.any (·.isLine l)
    · simp [ha] at this
    · exact List.any_eq_true.mp ha
  · split at h4
    · rename_i hi; exact eq_of_beq hi
    · simp at h4

/-- A line the reader reads as a hole or theorem is one of its lines, at its line number: line
`i + 1` for the line at index `i`. -/
theorem mem_declLinesFrom {l : Nat × String} : ∀ {k : Nat} {ls : List Line},
    l ∈ declLinesFrom k ls ↔ ∃ i t, ((∃ n s, ls[i]? = some (.thm n s t)) ∨ ls[i]? = some (.hole t)) ∧
      l = (k + i, t)
  | _, [] => by simp [declLinesFrom]
  | k, x :: ls => by
    have ih := @mem_declLinesFrom l (k + 1) ls
    have shift : ∀ {i : Nat}, k + 1 + i = k + (i + 1) := by omega
    constructor
    · intro hl
      cases x with
      | thm n s t =>
        simp only [declLinesFrom, List.mem_cons] at hl
        rcases hl with rfl | hl
        · exact ⟨0, t, .inl ⟨n, s, rfl⟩, by simp⟩
        · obtain ⟨i, t', hi, he⟩ := ih.mp hl
          exact ⟨i + 1, t', by simpa using hi, by rw [he, shift]⟩
      | hole t =>
        simp only [declLinesFrom, List.mem_cons] at hl
        rcases hl with rfl | hl
        · exact ⟨0, t, .inr rfl, by simp⟩
        · obtain ⟨i, t', hi, he⟩ := ih.mp hl
          exact ⟨i + 1, t', by simpa using hi, by rw [he, shift]⟩
      | imp t =>
        obtain ⟨i, t', hi, he⟩ := ih.mp hl
        exact ⟨i + 1, t', by simpa using hi, by rw [he, shift]⟩
      | keep t =>
        obtain ⟨i, t', hi, he⟩ := ih.mp hl
        exact ⟨i + 1, t', by simpa using hi, by rw [he, shift]⟩
    · rintro ⟨i, t, hi, rfl⟩
      cases i with
      | zero =>
        rcases hi with ⟨n, s, hx⟩ | hx <;>
        · simp only [List.getElem?_cons_zero, Option.some.injEq] at hx
          subst hx; simp [declLinesFrom]
      | succ i =>
        have := ih.mpr ⟨i, t, by simpa using hi, by rw [shift]⟩
        cases x <;> simp [declLinesFrom, this]

/-! ## The generated Challenges -/

/-- What a theorem of a generated Challenge must state, as an `Expr` in the approved Challenge's
environment. -/
inductive Want where
  /-- `Not T`, `T` being the type of the approved theorem `Mitos.Proofs.<n>`. -/
  | negated (n : String)
  /-- `T` itself. -/
  | stated (n : String)
  /-- `(h₁, h₂, …) = (h₁, h₂, …)` over these definition holes, in order. -/
  | holes (defs : List String)
  deriving DecidableEq, Repr

/-- A Challenge the runner generates: what it is for (in messages), its text as the runner writes
it, each theorem it must declare with what that theorem must state, and its imports besides `Init`. -/
structure Gen where
  what    : String
  text    : String
  wants   : List (String × Want)
  imports : List String
  deriving Repr

/-- The theorems the comparator compares in a refutation run: `Mitos.Refute.holes` when there are
definition holes, and each refuted theorem. -/
def refutationNames (defs ts : List String) : List String :=
  (if defs.isEmpty then [] else [holesName]) ++ ts.map ("Mitos.Refute." ++ ·)

/-- The refutation Challenge for `ts`, as the runner writes it (`Mutants.refutation`), and what it
must declare: the comparator's names, each negating its approved theorem or stating the holes. -/
def refutationGen (impls defs : List String) (ls : List Line) (ts : List String) :
    Except String Gen := do
  let out ← refutation impls defs ls ts
  return { what := s!"the refutation Challenge for {ts}", text := "\n".intercalate out,
           wants := (if defs.isEmpty then [] else [(holesName, .holes defs)]) ++
             ts.map fun n => ("Mitos.Refute." ++ n, .negated n),
           imports := impls ++ importNames ls }

/-- **The output check checks the names the comparator compares**: a refutation Challenge must
declare exactly `refutationNames`, the theorem names of the refutation run's configuration. -/
theorem refutationGen_names {impls defs : List String} {ls : List Line} {ts : List String} {g : Gen}
    (h : refutationGen impls defs ls ts = .ok g) : g.wants.map (·.1) = refutationNames defs ts := by
  unfold refutationGen at h
  cases hr : refutation impls defs ls ts with
  | error e => simp [hr, bind, Except.bind] at h
  | ok out =>
    simp only [hr, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
    subst h
    unfold refutationNames
    split <;> simp [Function.comp_def]

/-- The values Challenge, as the runner writes it (`Mutants.approvedByValue`), and what it must
declare: every approved theorem, stating its approved statement. -/
def valuesGen (impls : List String) (ls : List Line) : Except String Gen := do
  let out ← approvedByValue impls ls
  return { what := "the values Challenge", text := "\n".intercalate out,
           wants := ls.filterMap fun | .thm n _ _ => some ("Mitos.Proofs." ++ n, .stated n) | _ => none,
           imports := impls ++ importNames ls }

/-- A difference between what a generated Challenge must declare and what Lean built. -/
inductive OutProblem where
  /-- It must declare this theorem; Lean declares nothing of that name. -/
  | missing (name : String)
  /-- Lean declares it, but not as a theorem without universe parameters. -/
  | notTheorem (name : String)
  /-- Lean declares this theorem, with another type than it must state. -/
  | differs (name : String)
  /-- Lean declares it; the Challenge must not. -/
  | extra (name : String)
  /-- The imports it must have, and Lean's. -/
  | imports (want lean : List String)
  deriving DecidableEq, Repr

/-- Every difference between the theorems `want` a generated Challenge must declare, each with the
type it must state, and the constants `found` Lean declared in it, each with its type when it is a
theorem with no universe parameter; and between the imports, `Init` aside, and Lean's. -/
def outProblems {α : Type} (same : α → α → Bool) (want : List (String × α))
    (wantImps imps : List String) (found : List (String × Option α)) : List OutProblem :=
  let ri := "Init" :: wantImps
  want.filterMap (fun (n, t) => match found.lookup n with
      | none => some (.missing n)
      | some none => some (.notTheorem n)
      | some (some t') => if same t t' then none else some (.differs n)) ++
    (found.filter fun f => !want.any (·.1 == f.1)).map (.extra ·.1) ++
    (if imps.all ri.contains && ri.all imps.contains then [] else [.imports ri imps])

/-- **What an agreement means.** Each theorem the Challenge must declare, Lean declares as a theorem
of the type it must state (by `same`); Lean declares no other constant; and Lean's imports are
exactly `Init` and the ones it must have. -/
theorem outProblems_nil {α : Type} {same : α → α → Bool} {want : List (String × α)}
    {wantImps imps : List String} {found : List (String × Option α)}
    (h : outProblems same want wantImps imps found = []) :
    (∀ n t, (n, t) ∈ want → ∃ t', found.lookup n = some (some t') ∧ same t t' = true) ∧
      (∀ f ∈ found, ∃ t, (f.1, t) ∈ want) ∧ ∀ m, m ∈ imps ↔ m ∈ "Init" :: wantImps := by
  unfold outProblems at h
  simp only [List.append_eq_nil_iff, List.filterMap_eq_nil_iff, List.map_eq_nil_iff,
    List.filter_eq_nil_iff] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨fun n t hn => ?_, fun f hf => ?_, fun m => ⟨fun hm => ?_, fun hm => ?_⟩⟩
  · have := h1 (n, t) hn
    revert this
    cases hl : found.lookup n with
    | none => simp
    | some x =>
      cases x with
      | none => simp
      | some t' => intro hx; exact ⟨t', rfl, by simpa using hx⟩
  · have := h2 f hf
    cases ha : want.any (·.1 == f.1)
    · simp [ha] at this
    · obtain ⟨⟨n, t⟩, hm, he⟩ := List.any_eq_true.mp ha
      have he' : n = f.1 := by simpa using he
      exact ⟨t, he' ▸ hm⟩
  · split at h3
    · rename_i hi
      simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hi
      exact hi.1 m hm
    · simp at h3
  · split at h3
    · rename_i hi
      simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hi
      exact hi.2 m hm
    · simp at h3

/-! ## What Lean built: types and constants -/

/-- `e` with every universe level normalized. -/
def normLevels (e : Expr) : Expr :=
  e.replace fun
    | .const n ls => some (.const n (ls.map Level.normalize))
    | .sort l => some (.sort l.normalize)
    | _ => none

/-- Whether two types are the same `Expr` once their universe levels are normalized. `==` is
`Expr.eqv`: structural, ignoring binder names and binder info. -/
def sameType (a b : Expr) : Bool := normLevels a == normLevels b

/-- The constants of module `m` as Lean built it, each with its type when it is a theorem with no
universe parameter, and the module's imports. -/
def builtTheorems (env : Environment) (m : Name) : Option (List String × List (String × Option Expr)) := do
  let i ← env.header.moduleNames.idxOf? m
  let md ← env.header.moduleData[i]?
  return (md.imports.toList.map (·.module.toString), md.constants.toList.map fun c =>
    (c.name.toString, match c with
      | .thmInfo t => if t.levelParams.isEmpty then some t.type else none
      | _ => none))

/-- The type of the theorem `Mitos.Proofs.<n>` that module `m` (the approved Challenge) declares. -/
def approvedType (env : Environment) (m : Name) (n : String) : Except String Expr := do
  let some (_, cs) := builtTheorems env m | throw s!"{m} is not in its own environment"
  match cs.lookup ("Mitos.Proofs." ++ n) with
  | some (some t) => return t
  | some none => throw s!"the approved Challenge declares Mitos.Proofs.{n}, but not as a theorem without universe parameters"
  | none => throw s!"the approved Challenge as Lean built it declares no Mitos.Proofs.{n}"

/-- `(h₁, h₂, …) = (h₁, h₂, …)` over the definition holes `defs` of the current environment, as
`Lean.Meta.mkAppM` and `Lean.Meta.mkEq` build it, so with the types and universe levels Lean infers. -/
def holesType (defs : List String) : MetaM Expr := do
  let cs ← defs.mapM fun d => do
    let n := d.toName
    let some c := (← getEnv).find? n | throwError "the approved Challenge has no definition hole {n}"
    unless c.levelParams.isEmpty do throwError "the definition hole {n} has universe parameters"
    pure (mkConst n)
  match cs.reverse with
  | [] => throwError "no definition holes"
  | c :: rest =>
    let t ← rest.foldlM (fun acc x => Meta.mkAppM ``Prod.mk #[x, acc]) c
    Meta.mkEq t t

/-- The type each theorem in `wants` must state, in the environment `env` of the approved Challenge
module `m`. -/
def wantTypes (env : Environment) (m : Name) (wants : List (String × Want)) :
    IO (Except String (List (String × Expr))) := do
  let mut out := #[]
  for (n, w) in wants do
    let t ← match w with
      | .negated a => pure ((approvedType env m a).map mkNot)
      | .stated a => pure (approvedType env m a)
      | .holes defs =>
        try
          let (t, _) ← (holesType defs).toIO { fileName := "<output check>", fileMap := default }
            { env }
          pure (.ok t)
        catch e => pure (.error s!"cannot state {n}: {e}")
    match t with
    | .ok t => out := out.push (n, t)
    | .error e => return .error e
  return .ok out.toList

/-! ## Lean's parse: reading it -/

/-- The header's findings, its imports and its commands as Lean's parser reads `src` with `env`'s
syntax, or the parse error. -/
def readParse (env : Environment) (src : String) :
    IO (Except String (List String × List String × List Cmd)) := do
  match ← MitosGate.Lint.parse env src with
  | .error v => return .error s!"line {v.line}, column {v.col}: {v.msg}"
  | .ok (fm, header, cmds) =>
    let empty := MitosGate.Lint.isEmptyNode
    let mut hdr := #[]
    if !empty header[0] then hdr := hdr.push "a `module` keyword"
    if !empty header[1] then hdr := hdr.push "a `prelude` keyword"
    let mut imps := #[]
    for imp in header[2].getArgs do
      unless empty imp[0] && empty imp[1] && empty imp[3] do
        hdr := hdr.push s!"an import with a modifier at line {(fm.toPosition (imp.getPos?.getD 0)).line}"
      imps := imps.push (match imp[4] with | .ident _ _ n _ => n.toString | stx => toString stx)
    let cs := cmds.toList.map fun cmd =>
      let start := cmd.getPos?.getD 0
      let p := fm.toPosition start
      { line := p.line, col := p.column, kind := toString cmd.getKind,
        text := String.Pos.Raw.extract src start (cmd.getTailPos?.getD start) : Cmd }
    return .ok (hdr.toList, imps.toList, cs)

/-- The syntax Lean builds a module with that imports `mods`: theirs, with their scoped syntax off. -/
def parseEnv (mods : List String) : IO Environment := do
  unsafe enableInitializersExecution
  importModules (mods.map fun m => ({ module := m.toName } : Import)).toArray {} (loadExts := true)

/-! ## Messages -/

def ParseProblem.text : ParseProblem → String
  | .command c => s!"Lean reads a command ({c.kind}) at line {c.line}, column {c.col} that is no module doc and no hole or theorem line of the reader: {(c.text.take 80).toString}"
  | .missing l t => s!"the reader read line {l} as a hole or theorem; no command of Lean's parse is exactly that line: {t}"
  | .header w => s!"the header holds {w}"
  | .imports r l => s!"the reader read the imports {r}, Lean's header imports {l}"

def ParseProblem.key : ParseProblem → String × Nat
  | .command c => ("command", c.line)
  | .missing l _ => ("missing", l)
  | .header _ => ("header", 0)
  | .imports _ _ => ("imports", 0)

def OutProblem.text : OutProblem → String
  | .missing n => s!"it must declare {n}; Lean declares nothing of that name"
  | .notTheorem n => s!"Lean declares {n}, but not as a theorem without universe parameters"
  | .differs n => s!"Lean declares {n} with another type than it must state"
  | .extra n => s!"Lean declares {n}, which it must not"
  | .imports w l => s!"it must import {w}; Lean's imports are {l}"

def OutProblem.key : OutProblem → String × String
  | .missing n => ("missing", n)
  | .notTheorem n => ("notTheorem", n)
  | .differs n => ("differs", n)
  | .extra n => ("extra", n)
  | .imports _ _ => ("imports", "")

/-! ## Probes -/

/-- Round 10's B1: after a module doc's opener, a line comment that ends with a closer, then a
declaration doc comment, the next line comment's closer ends the module doc, so the rest of that
line is code, which the reader keeps as a comment. -/
def b1Source : String :=
  "import Mitos.Core\n\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\n/-!\n-- -/\n/-- x -/\n-- -/ variable (h : False) in include h in\ndef Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry\ntheorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry\n"

/-- An approved Challenge that ends with `code` hidden the same way. -/
def trailingSource (code : String) : String :=
  s!"import Mitos.Core\n\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\ndef Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry\ntheorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry\n/-!\n-- -/\n/-- x -/\n-- -/ {code}\n"

/-- The definition holes of the probes' scratch Challenges. -/
def probeDefs : List String := ["Mitos.Impl.resolve", "Mitos.Impl.impact"]

/-- A scratch approved Challenge with a known misread for the parse check: its source and the
problems the parse check must find, each by its constructor and line. -/
structure ParseProbe where
  name   : String
  source : String
  expect : List (String × Nat)

def parseProbes : List ParseProbe := [
  { name := "b1", source := b1Source, expect := [("command", 7)] },
  { name := "namespace", source := trailingSource "namespace Mitos.Impl", expect := [("command", 9)] },
  { name := "exit", source := trailingSource "#exit", expect := [("command", 9)] },
  { name := "decoy", source := decoySource, expect := [("command", 3), ("missing", 5), ("missing", 7)] },
  { name := "reverse", source := reverseSource, expect := [("command", 3), ("missing", 5), ("missing", 7)] }]

/-- A scratch approved Challenge for the output check: its path in the workspace, its source, the
theorems a case refutes, and the problems the output check must find in the refutation Challenge
generated from it, each by its constructor and name. -/
structure OutProbe where
  path   : String
  source : String
  breaks : List String
  expect : List (String × String)

def outProbes : List OutProbe := [
  { path := "Challenge/OutputProbeB1.lean", source := b1Source, breaks := ["resolve_total"],
    expect := [("differs", "Mitos.Refute.resolve_total")] },
  { path := "Challenge/OutputProbeExit.lean", source := trailingSource "#exit",
    breaks := ["resolve_total"], expect := [("missing", holesName)] }]

-- Every probe is one the reader reads, so each misread is one the reader really makes.
#guard parseProbes.all fun p => (readChallenge p.source).toOption.isSome
#guard outProbes.all fun p => (readChallenge p.source).toOption.isSome
-- The reader reads `b1Source` as two holes and one theorem, every other line a comment or blank.
#guard ((readChallenge b1Source).toOption.map declLines) ==
  some [(3, "def Mitos.Impl.resolve : Mitos.Resolver := sorry"),
    (8, "def Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry"),
    (9, "theorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry")]

-- The parse comparison on commands written out: the reader's lines as Lean parses `b1Source`
-- (a module doc, the first hole, then a `variable … in` command that holds the second hole) show
-- the `in` command and the second hole as missing; the lines as plain commands show nothing.
#guard ((readChallenge b1Source).toOption.map fun ls =>
    (parseProblems ls [] ["Mitos.Core"] [
      { line := 3, col := 0, kind := declKind, text := "def Mitos.Impl.resolve : Mitos.Resolver := sorry" },
      { line := 4, col := 0, kind := moduleDocKind, text := "" },
      { line := 7, col := 6, kind := "Lean.Parser.Command.in", text := "variable (h : False) in" },
      { line := 9, col := 0, kind := declKind,
        text := "theorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry" }]).map
      (·.key)) ==
  some [("command", 7), ("missing", 8)]
#guard ((readChallenge b1Source).toOption.map fun ls =>
    parseProblems ls [] ["Mitos.Core"] ((declLines ls).map fun (i, t) =>
      { line := i, col := 0, kind := declKind, text := t })) == some []
-- A command at another column, of another kind, or with more text than the line is no line of the
-- reader; the header's findings and imports are reported.
#guard (parseProblems [.imp "import Mitos.Core", .hole "def Mitos.Impl.f : Nat := sorry"]
    ["a `prelude` keyword"] ["Mitos.Core", "Mitos.Impl"]
    [{ line := 2, col := 1, kind := declKind, text := "def Mitos.Impl.f : Nat := sorry" }]).map (·.key) ==
  [("command", 2), ("missing", 2), ("header", 0), ("imports", 0)]

-- The output comparison, on types written out as strings: each kind of difference is reported,
-- and exactly what must be declared shows nothing.
#guard outProblems (· == ·) [("Mitos.Refute.t", "¬ P"), (holesName, "H")] ["Mitos.Core"]
    ["Init", "Mitos.Core"] [(holesName, some "H"), ("Mitos.Refute.t", some "¬ P")] == []
#guard (outProblems (· == ·) [("Mitos.Refute.t", "¬ P"), (holesName, "H"), ("Mitos.Refute.u", "¬ Q")]
    ["Mitos.Core"] ["Init"]
    [("Mitos.Refute.t", some "False → ¬ P"), ("Mitos.Refute.u", none), ("Mitos.Impl.x", some "X")]).map
      (·.key) ==
  [("differs", "Mitos.Refute.t"), ("missing", holesName), ("notTheorem", "Mitos.Refute.u"),
    ("extra", "Mitos.Impl.x"), ("imports", "")]
-- The refutation Challenge must declare the comparator's names; the values Challenge, every
-- approved theorem.
#guard (((readChallenge b1Source).toOption.map fun ls => refutationGen [] probeDefs ls ["resolve_total"]).map
    fun g => g.toOption.map (·.wants)) ==
  some (some [(holesName, .holes probeDefs), ("Mitos.Refute.resolve_total", .negated "resolve_total")])
#guard ((readChallenge b1Source).toOption.map fun ls => (valuesGen ["Mitos.Impl.Resolve"] ls).toOption.map
    fun g => (g.wants, g.imports)) ==
  some (some ([("Mitos.Proofs.resolve_total", .stated "resolve_total")], ["Mitos.Impl.Resolve", "Mitos.Core"]))

end Mutants.Output
