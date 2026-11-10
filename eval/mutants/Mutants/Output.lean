import Lean.Meta.AppBuilder
import MitosGate.Lint
import Mutants.CrossCheck

namespace Mutants.Output

open Lean CrossCheck

structure Cmd where
  line : Nat
  col  : Nat
  kind : String
  text : String
  deriving DecidableEq, Repr

def moduleDocKind : String := toString ``Parser.Command.moduleDoc
def declKind : String := toString ``Parser.Command.declaration

def declLinesFrom : Nat → List Line → List (Nat × String)
  | _, [] => []
  | k, .thm _ _ t :: ls => (k, t) :: declLinesFrom (k + 1) ls
  | k, .hole t :: ls => (k, t) :: declLinesFrom (k + 1) ls
  | k, _ :: ls => declLinesFrom (k + 1) ls

def declLines (ls : List Line) : List (Nat × String) := declLinesFrom 1 ls

def Cmd.isLine (c : Cmd) (l : Nat × String) : Bool :=
  c.kind == declKind && c.line == l.1 && c.col == 0 && c.text == l.2

inductive ParseProblem where
  | command (c : Cmd)
  | missing (line : Nat) (text : String)
  | header (what : String)
  | imports (read lean : List String)
  deriving DecidableEq, Repr

def parseProblems (ls : List Line) (hdr imps : List String) (cmds : List Cmd) : List ParseProblem :=
  let dl := declLines ls
  (cmds.filter fun c => !(c.kind == moduleDocKind || dl.any c.isLine)).map .command ++
    (dl.filter fun l => !cmds.any (·.isLine l)).map (fun l => .missing l.1 l.2) ++
    hdr.map .header ++
    (if imps == importNames ls then [] else [.imports (importNames ls) imps])

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

inductive Want where
  | negated (n : String)
  | stated (n : String)
  | holes (defs : List String)
  deriving DecidableEq, Repr

structure Gen where
  what    : String
  text    : String
  wants   : List (String × Want)
  imports : List String
  deriving Repr

def refutationNames (defs ts : List String) : List String :=
  (if defs.isEmpty then [] else [holesName]) ++ ts.map ("Mitos.Refute." ++ ·)

def refutationGen (impls defs : List String) (ls : List Line) (ts : List String) :
    Except String Gen := do
  let out ← refutation impls defs ls ts
  return { what := s!"the refutation Challenge for {ts}", text := "\n".intercalate out,
           wants := (if defs.isEmpty then [] else [(holesName, .holes defs)]) ++
             ts.map fun n => ("Mitos.Refute." ++ n, .negated n),
           imports := impls ++ importNames ls }

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

def valuesGen (impls : List String) (ls : List Line) : Except String Gen := do
  let out ← approvedByValue impls ls
  return { what := "the values Challenge", text := "\n".intercalate out,
           wants := ls.filterMap fun | .thm n _ _ => some ("Mitos.Proofs." ++ n, .stated n) | _ => none,
           imports := impls ++ importNames ls }

inductive OutProblem where
  | missing (name : String)
  | notTheorem (name : String)
  | differs (name : String)
  | extra (name : String)
  | imports (want lean : List String)
  deriving DecidableEq, Repr

def outProblems {α : Type} (same : α → α → Bool) (want : List (String × α))
    (wantImps imps : List String) (found : List (String × Option α)) : List OutProblem :=
  let ri := "Init" :: wantImps
  want.filterMap (fun (n, t) => match found.lookup n with
      | none => some (.missing n)
      | some none => some (.notTheorem n)
      | some (some t') => if same t t' then none else some (.differs n)) ++
    (found.filter fun f => !want.any (·.1 == f.1)).map (.extra ·.1) ++
    (if imps.all ri.contains && ri.all imps.contains then [] else [.imports ri imps])

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

def normLevels (e : Expr) : Expr :=
  e.replace fun
    | .const n ls => some (.const n (ls.map Level.normalize))
    | .sort l => some (.sort l.normalize)
    | _ => none

def sameType (a b : Expr) : Bool := Expr.eqv (normLevels a) (normLevels b)

def builtTheorems (env : Environment) (m : Name) : Option (List String × List (String × Option Expr)) := do
  let i ← env.header.moduleNames.idxOf? m
  let md ← env.header.moduleData[i]?
  return (md.imports.toList.map (·.module.toString), md.constants.toList.map fun c =>
    (c.name.toString, match c with
      | .thmInfo t => if t.levelParams.isEmpty then some t.type else none
      | _ => none))

def approvedType (env : Environment) (m : Name) (n : String) : Except String Expr := do
  let some (_, cs) := builtTheorems env m | throw s!"{m} is not in its own environment"
  match cs.lookup ("Mitos.Proofs." ++ n) with
  | some (some t) => return t
  | some none => throw s!"the approved Challenge declares Mitos.Proofs.{n}, but not as a theorem without universe parameters"
  | none => throw s!"the approved Challenge as Lean built it declares no Mitos.Proofs.{n}"

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

def parseEnv (mods : List String) : IO Environment := do
  unsafe enableInitializersExecution
  importModules (mods.map fun m => ({ module := m.toName } : Import)).toArray {} (loadExts := true)

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

def hiddenVariableSource : String :=
  "import Mitos.Core\n\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\n/-!\n-- -/\n/-- x -/\n-- -/ variable (h : False) in include h in\ndef Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry\ntheorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry\n"

def trailingSource (code : String) : String :=
  s!"import Mitos.Core\n\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\ndef Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry\ntheorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry\n/-!\n-- -/\n/-- x -/\n-- -/ {code}\n"

def probeDefs : List String := ["Mitos.Impl.resolve", "Mitos.Impl.impact"]

structure ParseProbe where
  name   : String
  source : String
  expect : List (String × Nat)

def parseProbes : List ParseProbe := [
  { name := "b1", source := hiddenVariableSource, expect := [("command", 7)] },
  { name := "namespace", source := trailingSource "namespace Mitos.Impl", expect := [("command", 9)] },
  { name := "exit", source := trailingSource "#exit", expect := [("command", 9)] },
  { name := "decoy", source := decoySource, expect := [("command", 3), ("missing", 5), ("missing", 7)] },
  { name := "reverse", source := reverseSource, expect := [("command", 3), ("missing", 5), ("missing", 7)] }]

structure OutProbe where
  path   : String
  source : String
  breaks : List String
  expect : List (String × String)

def outProbes : List OutProbe := [
  { path := "Challenge/OutputProbeB1.lean", source := hiddenVariableSource, breaks := ["resolve_total"],
    expect := [("differs", "Mitos.Refute.resolve_total")] },
  { path := "Challenge/OutputProbeExit.lean", source := trailingSource "#exit",
    breaks := ["resolve_total"], expect := [("missing", holesName)] }]

#guard parseProbes.all fun p => (readChallenge p.source).toOption.isSome
#guard outProbes.all fun p => (readChallenge p.source).toOption.isSome
#guard ((readChallenge hiddenVariableSource).toOption.map declLines) ==
  some [(3, "def Mitos.Impl.resolve : Mitos.Resolver := sorry"),
    (8, "def Mitos.Impl.impact : List Mitos.Edge → String → List String := sorry"),
    (9, "theorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry")]

#guard ((readChallenge hiddenVariableSource).toOption.map fun ls =>
    (parseProblems ls [] ["Mitos.Core"] [
      { line := 3, col := 0, kind := declKind, text := "def Mitos.Impl.resolve : Mitos.Resolver := sorry" },
      { line := 4, col := 0, kind := moduleDocKind, text := "" },
      { line := 7, col := 6, kind := "Lean.Parser.Command.in", text := "variable (h : False) in" },
      { line := 9, col := 0, kind := declKind,
        text := "theorem Mitos.Proofs.resolve_total : Mitos.Spec.Total Mitos.Impl.resolve := sorry" }]).map
      (·.key)) ==
  some [("command", 7), ("missing", 8)]
#guard ((readChallenge hiddenVariableSource).toOption.map fun ls =>
    parseProblems ls [] ["Mitos.Core"] ((declLines ls).map fun (i, t) =>
      { line := i, col := 0, kind := declKind, text := t })) == some []
#guard (parseProblems [.imp "import Mitos.Core", .hole "def Mitos.Impl.f : String := sorry"]
    ["a `prelude` keyword"] ["Mitos.Core", "Mitos.Impl"]
    [{ line := 2, col := 1, kind := declKind, text := "def Mitos.Impl.f : String := sorry" }]).map (·.key) ==
  [("command", 2), ("missing", 2), ("header", 0), ("imports", 0)]

#guard outProblems (· == ·) [("Mitos.Refute.t", "¬ P"), (holesName, "H")] ["Mitos.Core"]
    ["Init", "Mitos.Core"] [(holesName, some "H"), ("Mitos.Refute.t", some "¬ P")] == []
#guard (outProblems (· == ·) [("Mitos.Refute.t", "¬ P"), (holesName, "H"), ("Mitos.Refute.u", "¬ Q")]
    ["Mitos.Core"] ["Init"]
    [("Mitos.Refute.t", some "False → ¬ P"), ("Mitos.Refute.u", none), ("Mitos.Impl.x", some "X")]).map
      (·.key) ==
  [("differs", "Mitos.Refute.t"), ("missing", holesName), ("notTheorem", "Mitos.Refute.u"),
    ("extra", "Mitos.Impl.x"), ("imports", "")]
#guard (((readChallenge hiddenVariableSource).toOption.map fun ls => refutationGen [] probeDefs ls ["resolve_total"]).map
    fun g => g.toOption.map (·.wants)) ==
  some (some [(holesName, .holes probeDefs), ("Mitos.Refute.resolve_total", .negated "resolve_total")])
#guard ((readChallenge hiddenVariableSource).toOption.map fun ls => (valuesGen ["Mitos.Impl.Resolve"] ls).toOption.map
    fun g => (g.wants, g.imports)) ==
  some (some ([("Mitos.Proofs.resolve_total", .stated "resolve_total")], ["Mitos.Impl.Resolve", "Mitos.Core"]))

end Mutants.Output
