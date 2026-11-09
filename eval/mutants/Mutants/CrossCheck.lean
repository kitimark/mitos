import Lean.DeclarationRange
import Mutants.Challenge

/-!
# The reader's lines, checked against the Challenge as Lean built it

Every Challenge the runner generates is made from the lines `Mutants.readChallenge` reads in the
approved Challenge: it keeps the imports and comments, drops the definition holes, and negates or
drops the theorems. The reader is a fast first pass over the text. It follows only part of Lean's
lexer, and rounds 6 to 9 of the review on #86 each found a form it read otherwise than Lean: a
comment that ends before its line ends, a `:= sorry` in a comment, equations and structure fields
after a hole's type, and in round 9 a doc comment's opener. Lean reads a doc comment's opener as a
token and skips the whitespace and line comments after it before the comment's text begins
(`Lean.Parser.Command.docComment`, `moduleDoc`). So in `decoySource` below (an opener alone on a
line, then a line comment that ends with a closer, then a theorem line, then the same line comment
again) the doc comment runs on to the second line comment, while the reader took the first as its
end and the theorem line as a theorem the Challenge states. Rounds 6 to 8 refused one more form
each; the next form was always one more. (This doc names the openers and closers in words, since
one written out here would open or close this comment.)

So the runner does not rest on the reader. Before it prepares or judges anything, it builds the
approved Challenge module with `lake build` in a fresh copy of the approved core, loads the module
as Lean built it (`Lean.importModules`), and compares what Lean declared with what the reader read
(`problems`). Any difference stops the runner (exit 2) with the list of differences. Compared are:

- **The declarations.** The module's constants (`ModuleData.constants`, every constant Lean added
  in the module, auxiliary ones included) must be exactly `expected`: for each theorem line the
  reader read at line `i`, `theorem Mitos.Proofs.<n> : <stmt> := sorry`, a theorem
  `Mitos.Proofs.<n>` whose name starts at line `i`, column 8, and whose statement is a constant
  applied to constants, named in order by the words of `<stmt>`; for each hole line at line `i`, a
  safe definition named by the word after `def ` (`holeName`), whose name starts at line `i`,
  column 4, and whose value is exactly `sorry` of its type (`sorryOf`). Nothing is filtered out:
  a `where` or a `match` declares a constant the reader did not read, and stops the runner.
- **The definition holes.** The holes the reader read are exactly `definition_names` of
  `core/comparator.json`.
- **The imports.** The module imports `Init` and the modules of the reader's import lines, and
  nothing else.

`problems_nil` proves what an empty list of problems means, and `mem_expected` and
`readLines_getElem?` tie each declaration to the line of the source it was read from. That Lean's
side of the comparison (`declOf`) reads the constants, their names' positions and the `sorry`
correctly is not proved; the probes check it at every run.

**Probes.** In the same workspace the runner builds three scratch Challenge modules (`probes`), each
with a known misread, and requires the comparison to find it: the decoy above, which the reader
reads as a theorem Lean does not declare; the reverse, a hole line inside such a doc comment, which
the reader reads as a hole Lean does not declare; and a hole whose value Lean reads by equations
with a `where` (review on #86, round 8), which the reader refuses, read as a hole as a looser reader
would. The first two are what `readChallenge` really reads (the `#guard`s below). So a check that
went blind, such as one that read no constant or no position, stops the runner too.

**What it does not see.** A command that declares nothing (`variable … in`, `include`, `namespace`,
`open`, `set_option`, `#exit`) in a line the reader keeps as a comment. Such a command can leave
every declaration of the approved Challenge as the reader read it and still change what a generated
Challenge states: a generated Challenge drops the hole lines and the theorems not named, so there
the command applies to another declaration, or to none (review on #86, round 10, B1,
`Mutants.Output.b1Source`). Two later checks stop the runner on that (`Mutants.Output`): Lean's
parse of the approved Challenge, in which every command must be a module doc or one of the
reader's hole and theorem lines, and the output check, which builds every generated Challenge with
the approved implementation and compares what it states with the approved statements as Lean built
them.

**Cost.** One `lake build` of the approved core's `Mitos.Core`, the Challenge and the probes in a
fresh workspace, and four imports, a few seconds per run (task file, round 9).
-/

namespace Mutants.CrossCheck

open Lean

/-- What a declaration of the Challenge module is, as the comparison reads it. -/
inductive Kind where
  /-- A theorem, with the names of its statement's constants in order when the statement is a
  constant applied to constants, and `none` for any other statement. -/
  | thm (stmt : Option (List String))
  /-- A safe definition whose value is exactly `sorry` of its type. -/
  | hole
  /-- Anything else, as `what` says. -/
  | other (what : String)
  deriving DecidableEq, Repr

/-- A declaration: its name, the line (from 1) and column (from 0, in characters) where its name
starts, if Lean records one, and its kind. -/
structure Decl where
  name : String
  pos  : Option (Nat × Nat)
  kind : Kind
  deriving DecidableEq, Repr

/-! ## What the reader read -/

/-- The name a hole line declares: the word after `def `. For a line the reader takes, that is the
name `holeForm` takes (`holeName_of_holeForm`). -/
def holeName (t : String) : String :=
  String.ofList ((t.toList.drop 4).takeWhile (· != ' '))

/-- The declaration a theorem line at line `i` must be: `theorem Mitos.Proofs.<n> : <s> := sorry`
names `Mitos.Proofs.<n>` at column 8 and states the words of `s`. -/
def thmDecl (i : Nat) (n s : String) : Decl :=
  { name := "Mitos.Proofs." ++ n, pos := some (i, 8), kind := .thm (some (s.splitOn " ")) }

/-- The declaration a hole line at line `i` must be: `def <name> : …` names it at column 4. -/
def holeDecl (i : Nat) (t : String) : Decl :=
  { name := holeName t, pos := some (i, 4), kind := .hole }

/-- The declarations the lines `ls` must be, the first of them being line `k`. -/
def expectedFrom : Nat → List Line → List Decl
  | _, [] => []
  | k, .thm n s _ :: ls => thmDecl k n s :: expectedFrom (k + 1) ls
  | k, .hole t :: ls => holeDecl k t :: expectedFrom (k + 1) ls
  | k, _ :: ls => expectedFrom (k + 1) ls

/-- The declarations the reader's lines must be, the first line being line 1. -/
def expected (ls : List Line) : List Decl := expectedFrom 1 ls

/-- The names of the holes the reader read. -/
def holeNames (ls : List Line) : List String :=
  ls.filterMap fun | .hole t => some (holeName t) | _ => none

/-- The modules of the reader's import lines. -/
def importNames (ls : List Line) : List String :=
  ls.filterMap fun | .imp t => some (String.ofList (t.toList.drop 7)) | _ => none

/-! ## The comparison -/

/-- A difference between the reader's lines and what Lean built. -/
inductive Problem where
  /-- Lean declares it; the reader read no theorem or hole line that is it. -/
  | unread (lean : Decl)
  /-- The reader read it; Lean declares nothing of its name. -/
  | undeclared (read : Decl)
  /-- The reader read `read`; Lean declares its name, but as `lean`: on another line or column, of
  another kind, or with another statement. -/
  | differs (read lean : Decl)
  /-- The reader read this hole; `definition_names` does not name it. -/
  | notConfigured (hole : String)
  /-- `definition_names` names it; the reader read no hole of that name. -/
  | notAHole (name : String)
  /-- The reader's imports, and Lean's. -/
  | imports (read lean : List String)
  deriving DecidableEq, Repr

/-- Every difference between the reader's lines `ls`, with the definition holes `defs`, and the
imports `imps` and declarations `ds` of the Challenge as Lean built it. -/
def problems (ls : List Line) (defs imps : List String) (ds : List Decl) : List Problem :=
  let ex := expected ls
  let hs := holeNames ls
  let rs := "Init" :: importNames ls
  (ds.filter (!ex.contains ·)).map (fun d => match ex.find? (·.name == d.name) with
      | some e => .differs e d
      | none => .unread d) ++
    (ex.filter (!ds.contains ·)).map (fun e => match ds.find? (·.name == e.name) with
      | some d => .differs e d
      | none => .undeclared e) ++
    (hs.filter (!defs.contains ·)).map .notConfigured ++
    (defs.filter (!hs.contains ·)).map .notAHole ++
    (if imps.all rs.contains && rs.all imps.contains then [] else [.imports (importNames ls) imps])

/-- **What an agreement means.** When the comparison finds nothing, Lean's declarations are exactly
the ones the reader's lines must be (`expected`), the holes the reader read are exactly the
configured definition holes, and Lean's imports are exactly `Init` and the reader's imports. -/
theorem problems_nil {ls : List Line} {defs imps : List String} {ds : List Decl}
    (h : problems ls defs imps ds = []) :
    (∀ d, d ∈ ds ↔ d ∈ expected ls) ∧ (∀ n, n ∈ holeNames ls ↔ n ∈ defs) ∧
      ∀ m, m ∈ imps ↔ m ∈ "Init" :: importNames ls := by
  unfold problems at h
  simp only [List.append_eq_nil_iff, List.map_eq_nil_iff, List.filter_eq_nil_iff] at h
  obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := h
  refine ⟨fun d => ⟨fun hd => ?_, fun hd => ?_⟩, fun n => ⟨fun hn => ?_, fun hn => ?_⟩,
    fun m => ⟨fun hm => ?_, fun hm => ?_⟩⟩
  · have := h1 d hd; simpa using this
  · have := h2 d hd; simpa using this
  · have := h3 n hn; simpa using this
  · have := h4 n hn; simpa using this
  · split at h5
    · rename_i hi
      simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hi
      exact hi.1 m hm
    · simp at h5
  · split at h5
    · rename_i hi
      simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hi
      exact hi.2 m hm
    · simp at h5

/-- A declaration the lines must be is a theorem or hole line of them, at its line number. -/
theorem mem_expectedFrom {d : Decl} : ∀ {k : Nat} {ls : List Line},
    d ∈ expectedFrom k ls ↔ ∃ i, (∃ n s t, ls[i]? = some (.thm n s t) ∧ d = thmDecl (k + i) n s) ∨
      ∃ t, ls[i]? = some (.hole t) ∧ d = holeDecl (k + i) t
  | _, [] => by simp [expectedFrom]
  | k, l :: ls => by
    have ih := @mem_expectedFrom d (k + 1) ls
    have shift : ∀ {i : Nat}, k + 1 + i = k + (i + 1) := by omega
    constructor
    · intro hd
      cases l with
      | thm n s t =>
        simp only [expectedFrom, List.mem_cons] at hd
        rcases hd with rfl | hd
        · exact ⟨0, .inl ⟨n, s, t, rfl, by simp⟩⟩
        · obtain ⟨i, hi⟩ := ih.mp hd
          exact ⟨i + 1, by simpa [shift] using hi⟩
      | hole t =>
        simp only [expectedFrom, List.mem_cons] at hd
        rcases hd with rfl | hd
        · exact ⟨0, .inr ⟨t, rfl, by simp⟩⟩
        · obtain ⟨i, hi⟩ := ih.mp hd
          exact ⟨i + 1, by simpa [shift] using hi⟩
      | imp t =>
        obtain ⟨i, hi⟩ := ih.mp hd
        exact ⟨i + 1, by simpa [shift] using hi⟩
      | keep t =>
        obtain ⟨i, hi⟩ := ih.mp hd
        exact ⟨i + 1, by simpa [shift] using hi⟩
    · rintro ⟨i, hi⟩
      cases i with
      | zero =>
        rcases hi with ⟨n, s, t, hl, rfl⟩ | ⟨t, hl, rfl⟩
        · simp only [List.getElem?_cons_zero, Option.some.injEq] at hl
          subst hl; simp [expectedFrom]
        · simp only [List.getElem?_cons_zero, Option.some.injEq] at hl
          subst hl; simp [expectedFrom]
      | succ i =>
        have hi' := ih.mpr ⟨i, by simpa [shift] using hi⟩
        cases l <;> simp [expectedFrom, hi']

/-- **Each declaration the reader's lines must be is a theorem or hole line, at its line**: line
`i + 1` for the line at index `i`. -/
theorem mem_expected {ls : List Line} {d : Decl} :
    d ∈ expected ls ↔ ∃ i, (∃ n s t, ls[i]? = some (.thm n s t) ∧ d = thmDecl (i + 1) n s) ∨
      ∃ t, ls[i]? = some (.hole t) ∧ d = holeDecl (i + 1) t := by
  unfold expected
  rw [mem_expectedFrom]
  simp only [Nat.add_comm 1]

/-- **The reader's line at index `i` is its reading of the source's line at index `i`**, which is
line `i + 1` of the file. -/
theorem readLines_getElem? : ∀ {b : Bool} {xs : List String} {ls : List Line},
    readLines b xs = .ok ls → ∀ {i : Nat} {x : Line}, ls[i]? = some x →
      ∃ l b' b'', xs[i]? = some l ∧ readLine b' l = .ok (x, b'')
  | b, [], ls, h, i, x, hx => by
    cases b <;> simp [readLines] at h
    subst h; simp at hx
  | b, l :: xs, ls, h, i, x, hx => by
    unfold readLines at h
    cases hl : readLine b l with
    | error e => rw [hl] at h; simp [bind, Except.bind] at h
    | ok r =>
      obtain ⟨y, b'⟩ := r
      rw [hl] at h
      cases hr : readLines b' xs with
      | error e => simp [hr, bind, Except.bind] at h
      | ok rs =>
        simp only [hr, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
        subst h
        cases i with
        | zero =>
          simp only [List.getElem?_cons_zero, Option.some.injEq] at hx
          subst hx
          exact ⟨l, b, b', rfl, hl⟩
        | succ i =>
          simp only [List.getElem?_cons_succ] at hx ⊢
          exact readLines_getElem? hr hx

theorem holeName_of_holeForm {cs n ty : List Char} (h : holeForm cs = some (n, ty)) :
    holeName (String.ofList cs) = String.ofList n := by
  have hs := holeForm_spec h
  have hn : ∀ c ∈ n, (c != ' ') = true := by
    unfold holeForm at h
    dsimp only at h
    split at h
    · simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, -⟩ := h
      have := List.all_takeWhile (p := (· != ' '))
        (l := (cs.drop 4).take (cs.length - 4 - sorrySuffix.length))
      exact List.all_eq_true.mp this
    · simp at h
  unfold holeName
  rw [String.toList_ofList, hs.1]
  simp only [List.append_assoc]
  rw [show "def ".toList = ['d', 'e', 'f', ' '] from rfl, List.drop_append_of_le_length (by simp),
    List.drop_eq_nil_of_le (by simp), List.nil_append, List.takeWhile_append_of_pos hn]
  simp [show " : ".toList = [' ', ':', ' '] from rfl]

/-! ## What Lean built -/

/-- The names of `e`'s constants in order, when `e` is a constant applied to constants. -/
def constApp (e : Expr) : Option (List String) :=
  match e.getAppFn with
  | .const c _ =>
    (e.getAppArgs.toList.mapM fun (a : Expr) => match a with
      | .const n _ => some n.toString
      | _ => none).map (c.toString :: ·)
  | _ => none

/-- Whether `v` is exactly `sorry` of type `ty`: `sorryAx ty s`, or the labeled or unique sorry
`sorryAx (τ → ty) s tag` that `sorry` elaborates to in this toolchain
(`Lean.Meta.mkLabeledSorry`). -/
def sorryOf (ty v : Expr) : Bool :=
  match v.getAppFn, v.getAppArgs with
  | .const ``sorryAx _, #[a, _] => a == ty
  | .const ``sorryAx _, #[.forallE _ _ b _, _, _] => b == ty
  | _, _ => false

/-- The kind of a constant: a theorem with its statement's constants, a hole, or something else. -/
def kindOf : ConstantInfo → Kind
  | .thmInfo t => .thm (constApp t.type)
  | .defnInfo d =>
    if d.safety == .safe && sorryOf d.type d.value then .hole
    else .other "a definition that is not a safe one whose value is exactly `sorry`"
  | .axiomInfo _ => .other "an axiom"
  | .opaqueInfo _ => .other "an opaque constant"
  | .quotInfo _ => .other "a quotient constant"
  | .inductInfo _ => .other "an inductive type"
  | .ctorInfo _ => .other "a constructor"
  | .recInfo _ => .other "a recursor"

/-- A constant of the module as the comparison reads it, with the position Lean records for its
name (`declRangeExt`, the selection range). -/
def declOf (env : Environment) (c : ConstantInfo) : Decl :=
  let r := declRangeExt.find? (level := .exported) env c.name <|>
    declRangeExt.find? (level := .server) env c.name
  { name := c.name.toString, kind := kindOf c,
    pos := r.map fun r => (r.selectionRange.pos.line, r.selectionRange.pos.column) }

/-- The imports and declarations of module `m` as Lean built it, from an environment that imports
it. -/
def built (env : Environment) (m : Name) : Option (List String × List Decl) := do
  let i ← env.header.moduleNames.idxOf? m
  let md ← env.header.moduleData[i]?
  return (md.imports.toList.map (·.module.toString), md.constants.toList.map (declOf env))

/-! ## Messages -/

def Kind.text : Kind → String
  | .thm (some ws) => s!"a theorem stating `{" ".intercalate ws}`"
  | .thm none => "a theorem whose statement is not a constant applied to constants"
  | .hole => "a definition hole (value exactly `sorry`)"
  | .other w => w

def Decl.text (d : Decl) : String :=
  let at_ := match d.pos with
    | some (l, c) => s!"line {l}, column {c}"
    | none => "no position"
  s!"{d.name}, {d.kind.text}, at {at_}"

def Problem.text : Problem → String
  | .unread d => s!"Lean declares {d.text}; the reader read no theorem or hole line for it"
  | .undeclared e => s!"the reader read {e.text}; Lean declares nothing of that name"
  | .differs e d => s!"the reader read {e.text}; Lean declares {d.text}"
  | .notConfigured n => s!"the reader read the hole {n}, which definition_names does not name"
  | .notAHole n => s!"definition_names names {n}, which the reader read no hole line for"
  | .imports r l => s!"the reader read the imports {r}, Lean's are {l}"

/-- A problem's constructor and name, which a probe expects. -/
def Problem.key : Problem → String × String
  | .unread d => ("unread", d.name)
  | .undeclared e => ("undeclared", e.name)
  | .differs e _ => ("differs", e.name)
  | .notConfigured n => ("notConfigured", n)
  | .notAHole n => ("notAHole", n)
  | .imports _ _ => ("imports", "")

/-! ## Probes -/

/-- A scratch Challenge module with a known misread: its path in the workspace, its source, the
reader's lines for it, its definition holes, and the problems the comparison must find, each by
its constructor and name. -/
structure Probe where
  path   : String
  source : String
  lines  : List Line
  defs   : List String
  expect : List (String × String)
  deriving Inhabited

def decoySource : String :=
  "import Mitos.Core\n\n/--\n-- -/\ntheorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry\n-- -/\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\n"

def reverseSource : String :=
  "import Mitos.Core\n\n/--\n-- -/\ndef Mitos.Impl.extra : Nat := sorry\n-- -/\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\n"

def valueLine : String := "def Mitos.Impl.f : Nat → Nat | _ => 0 where g : Nat := sorry"

def probes : List Probe := [
  { path := "Challenge/CrossCheckDecoy.lean", source := decoySource,
    lines := [.imp "import Mitos.Core", .keep "", .keep "/--", .keep "-- -/",
      .thm "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve"
        "theorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry",
      .keep "-- -/", .hole "def Mitos.Impl.resolve : Mitos.Resolver := sorry", .keep ""],
    defs := ["Mitos.Impl.resolve"], expect := [("undeclared", "Mitos.Proofs.decoy")] },
  { path := "Challenge/CrossCheckReverse.lean", source := reverseSource,
    lines := [.imp "import Mitos.Core", .keep "", .keep "/--", .keep "-- -/",
      .hole "def Mitos.Impl.extra : Nat := sorry", .keep "-- -/",
      .hole "def Mitos.Impl.resolve : Mitos.Resolver := sorry", .keep ""],
    defs := ["Mitos.Impl.extra", "Mitos.Impl.resolve"],
    expect := [("undeclared", "Mitos.Impl.extra")] },
  { path := "Challenge/CrossCheckValue.lean", source := s!"import Mitos.Core\n\n{valueLine}\n",
    lines := [.imp "import Mitos.Core", .keep "", .hole valueLine, .keep ""],
    defs := ["Mitos.Impl.f"],
    expect := [("differs", "Mitos.Impl.f"), ("unread", "Mitos.Impl.f.g")] }]

/-- Whether the comparison finds every problem the probe expects in what Lean built for it. -/
def Probe.caught (p : Probe) (imps : List String) (ds : List Decl) : Bool :=
  let found := (problems p.lines p.defs imps ds).map (·.key)
  p.expect.all found.contains

-- The decoy and the reverse are what the reader reads (round 9's misread); the value line it
-- refuses (round 8), so that probe reads it as a looser reader would.
#guard probes.map (fun p => (readChallenge p.source).toOption == some p.lines) == [true, true, false]
#guard (readChallenge s!"import Mitos.Core\n\n{valueLine}\n").toOption == none

-- What the reader's lines must be: each theorem and hole at its line, the theorem's statement as
-- words, the hole's name as the word after `def `.
#guard expected (probes.head!.lines) ==
  [thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve",
    { name := "Mitos.Impl.resolve", pos := some (7, 4), kind := .hole }]
#guard (thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve").kind ==
  .thm (some ["Mitos.Spec.Sound", "Mitos.Impl.resolve"])
#guard holeName valueLine == "Mitos.Impl.f"
#guard holeNames (probes.head!.lines) == ["Mitos.Impl.resolve"]
#guard importNames (probes.head!.lines) == ["Mitos.Core"]

-- The comparison, on declarations written out: the decoy probe as Lean built it shows only the
-- decoy; the same declarations as the reader expects them show nothing; and each kind of
-- difference is reported.
#guard (problems (probes.head!.lines) ["Mitos.Impl.resolve"] ["Init", "Mitos.Core"]
    [{ name := "Mitos.Impl.resolve", pos := some (7, 4), kind := .hole }]).map (·.key) ==
  [("undeclared", "Mitos.Proofs.decoy")]
#guard problems [.imp "import Mitos.Core", .hole "def Mitos.Impl.f : Nat := sorry",
    .thm "t" "Mitos.Spec.P Mitos.Impl.f" "theorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry"]
    ["Mitos.Impl.f"] ["Init", "Init", "Mitos.Core"]
    [thmDecl 3 "t" "Mitos.Spec.P Mitos.Impl.f", holeDecl 2 "def Mitos.Impl.f : Nat := sorry"] == []
#guard (problems [.hole "def Mitos.Impl.f : Nat := sorry",
    .thm "t" "Mitos.Spec.P Mitos.Impl.f" "theorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry"]
    ["Mitos.Impl.g"] ["Init", "Mitos.Core"]
    [{ name := "Mitos.Proofs.t", pos := some (3, 8), kind := .thm (some ["Mitos.Spec.P", "Mitos.Impl.f"]) },
      { name := "Mitos.Impl.f", pos := some (1, 4), kind := .other "x" },
      { name := "Mitos.Impl.f.match_1", pos := none, kind := .other "x" }]).map (·.key) ==
  [("differs", "Mitos.Proofs.t"), ("differs", "Mitos.Impl.f"), ("unread", "Mitos.Impl.f.match_1"),
    ("differs", "Mitos.Impl.f"), ("differs", "Mitos.Proofs.t"), ("notConfigured", "Mitos.Impl.f"),
    ("notAHole", "Mitos.Impl.g"), ("imports", "")]

end Mutants.CrossCheck
