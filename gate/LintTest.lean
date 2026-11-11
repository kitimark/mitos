import MitosGate.Lint
import MitosGate.Accept
import MitosGate.Imports
import MitosGate.CheatsRun

open MitosGate

def model (body : String) : String :=
  "import Mitos.Core\n\nnamespace Models.T\n\n" ++ body ++ "\n\nend Models.T\n"

def accepted : List (String × String) :=
  [ ("import Init/Std/Mitos.Core/Models",
      "import Init\nimport Std\nimport Mitos.Core\nimport Models.Other\n\ndef x : Nat := 1\n"),
    ("module doc", model "/-! A model. -/"),
    ("namespace/end", model "namespace Inner\ndef x : Nat := 1\nend Inner"),
    ("section/end", model "section\ndef x : Nat := 1\nend"),
    ("named section", model "section S\ndef x : Nat := 1\nend S"),
    ("open", model "open Mitos\nopen Nat (succ)\nopen List hiding map"),
    ("def", model "def x : Nat := 1"),
    ("def where", model "def f (n : Nat) : Nat := g n\nwhere g (m : Nat) : Nat := m"),
    ("def by structural recursion", model "def f : Nat → Nat\n  | 0 => 0\n  | n + 1 => f n"),
    ("theorem", model "theorem t : 1 = 1 := rfl"),
    ("abbrev", model "abbrev N := Nat"),
    ("example", model "example : 1 + 1 = 2 := by decide"),
    ("structure", model "structure P where\n  a : Nat\n  b : Nat"),
    ("inductive", model "inductive C where\n  | red\n  | blue"),
    ("doc comment", model "/-- A doc comment. -/\ndef x : Nat := 1"),
    ("@[simp]", model "@[simp] theorem t : 1 = 1 := rfl"),
    ("@[simp ←]", model "@[simp ←] theorem t : 1 = 1 := rfl"),
    ("set_option in a proof (plugin rule)",
      model "theorem t : 1 = 1 := by\n  set_option maxRecDepth 1000 in rfl"),
    ("-- comment mentioning notation", model "-- notation, macro, #eval, implemented_by\ndef x : Nat := 1") ]

def rejected : List (String × String) :=
  [
    ("notation", model "notation \"req--\" => 1"),
    ("local notation", model "local notation \"req--\" => 1"),
    ("scoped notation", model "scoped notation \"req--\" => 1"),
    ("infix", model "infix:65 \" +++ \" => Nat.add"),
    ("infixl", model "infixl:65 \" +++ \" => Nat.add"),
    ("infixr", model "infixr:65 \" +++ \" => Nat.add"),
    ("prefix", model "prefix:max \"√\" => Nat.sqrt"),
    ("postfix", model "postfix:max \"!\" => Nat.succ"),
    ("macro", model "macro \"foo\" : term => `(1)"),
    ("macro_rules", model "macro_rules | `(foo) => `(1)"),
    ("syntax", model "syntax \"foo\" : term"),
    ("syntax with name", model "syntax (name := foo) \"foo\" : term"),
    ("declare_syntax_cat", model "declare_syntax_cat foo"),
    ("elab", model "elab \"foo\" : term => pure (Lean.mkNatLit 1)"),
    ("elab_rules", model "elab_rules : term | `(foo) => pure (Lean.mkNatLit 1)"),
    ("binder_predicate", model "binder_predicate x \" >>> \" y:term => `($x > $y)"),
    ("initialize", model "initialize pure ()"),
    ("builtin_initialize", model "builtin_initialize pure ()"),
    ("import Lean", "import Lean\n\ndef x : Nat := 1\n"),
    ("import Lean.Parser", "import Lean.Parser\n\ndef x : Nat := 1\n"),
    ("import outside the four", "import Mathlib\n\ndef x : Nat := 1\n"),
    ("set_option", model "set_option maxHeartbeats 400000"),
    ("set_option ... in", model "set_option maxHeartbeats 400000 in\ndef x : Nat := 1"),
    ("set_option debug", model "set_option debug.skipKernelTC true"),
    ("#eval", model "#eval 1"),
    ("#check", model "#check Nat"),
    ("#print", model "#print Nat"),
    ("#reduce", model "#reduce 1 + 1"),
    ("#exit", model "#exit"),
    ("run_cmd", model "run_cmd pure ()"),
    ("variable", model "variable (n : Nat)"),
    ("universe", model "universe u"),
    ("mutual", model "mutual\ndef a : Nat := 1\nend"),
    ("open ... in", model "open Nat in\ndef x : Nat := succ 1"),
    ("export", model "export Nat (succ)"),
    ("attribute command", model "attribute [simp] Nat.add_comm"),
    ("deriving instance", model "deriving instance Repr for Nat"),
    ("noncomputable section", model "noncomputable section\nend"),
    ("public section", model "public section\nend"),
    ("@[expose] section", model "@[expose] section\nend"),
    ("instance", model "instance : Inhabited Nat := ⟨1⟩"),
    ("class", model "class K where\n  a : Nat"),
    ("class inductive", model "class inductive K where\n  | a"),
    ("axiom", model "axiom ax : False"),
    ("opaque", model "opaque o : Nat"),
    ("deriving clause", model "inductive C where\n  | red\n  deriving Repr"),
    ("def deriving clause", model "def N := Nat deriving Inhabited"),
    ("computed fields", model "inductive C where\n  | red\nwith\n  h : C → Nat\n  | .red => 0"),
    ("private", model "private def x : Nat := 1"),
    ("protected", model "protected def x : Nat := 1"),
    ("noncomputable", model "noncomputable def x : Nat := 1"),
    ("unsafe", model "unsafe def x : Nat := 1"),
    ("partial", model "partial def f (n : Nat) : Nat := f n"),
    ("nonrec", model "nonrec def x : Nat := 1"),
    ("meta", model "meta def x : Nat := 1"),
    ("@[implemented_by]", model "def evil (_ : Nat) : Nat := 0\n@[implemented_by evil] def f (n : Nat) : Nat := n"),
    ("@[extern]", model "@[extern \"c_f\"] def f (n : Nat) : Nat := n"),
    ("@[csimp]", model "@[csimp] theorem t : @id = @id := rfl"),
    ("@[reducible]", model "@[reducible] def x : Nat := 1"),
    ("@[instance]", model "@[instance] def x : Inhabited Nat := ⟨1⟩"),
    ("@[macro]", model "@[macro foo] def x : Nat := 1"),
    ("@[local simp, inline]", model "@[local simp, inline] theorem t : 1 = 1 := rfl"),
    ("attribute on a constructor", model "inductive C where\n  | @[inline] red"),
    ("attribute in a where clause",
      model "def f (n : Nat) : Nat := g n\nwhere @[implemented_by f] g (m : Nat) : Nat := m"),
    ("sorry", model "theorem t : 1 = 2 := sorry"),
    ("«sorry»", model "theorem t : 1 = 2 := «sorry»"),
    ("admit", model "theorem t : 1 = 2 := by admit"),
    ("native_decide", model "theorem t : 1 = 1 := by native_decide"),
    ("include_str", model "def s : String := include_str \"../comparator.json\""),
    ("Lean.ofReduceBool", model "def x := Lean.ofReduceBool"),
    ("trustCompiler", model "def x := Lean.trustCompiler"),
    ("set_option debug in a proof", model "theorem t : 1 = 1 := by\n  set_option debug.skipKernelTC true in rfl"),
    ("unknown syntax", model "def x : Nat := 1 ⊞ 2") ]

def headersAccepted : List (String × String) :=
  [ ("plain imports", "import Init\nimport Std.Data.HashMap\nimport Mitos.Core\nimport Models.ToyRequire\n"),
    ("escaped plain component", "import «Mitos».Core\n") ]

def headersRejected : List (String × String) :=
  [ ("import Init.«..».Lake", "import Init.«..».Lake\n"),
    ("import Init.«..».Lean", "import Init.«..».Lean\n"),
    ("import Models.«..».Mitos.Impl.Resolve", "import Models.«..».Mitos.Impl.Resolve\n"),
    ("import Models.«..».Mitos.Proofs.Resolver", "import Models.«..».Mitos.Proofs.Resolver\n"),
    ("import Models.«..».Challenge.ToyRequire", "import Models.«..».Challenge.ToyRequire\n"),
    ("import Mitos.Core.«..».Impl.Resolve", "import Mitos.Core.«..».Impl.Resolve\n"),
    ("import Models.«a.b»", "import Models.«a.b»\n"),
    ("import Models.«x y»", "import Models.«x y»\n"),
    ("import Mitos.Impl.Resolve", "import Mitos.Impl.Resolve\n"),
    ("import Mitos.CoreX", "import Mitos.CoreX\n"),
    ("prelude", "prelude\nimport Mitos.Core\n"),
    ("module", "module\n\nimport Mitos.Core\n"),
    ("public import", "module\n\npublic import Mitos.Core\n"),
    ("meta import", "module\n\nmeta import Mitos.Core\n"),
    ("import all", "module\n\nimport all Mitos.Core\n"),
    ("public import, no module", "public import Mitos.Core\n"),
    ("meta import, no module", "meta import Mitos.Core\n"),
    ("import all, no module", "import all Mitos.Core\n") ]

def stopsRejected : List (String × String) :=
  [ ("mid-file import, then sorry", "\nimport Lean\ntheorem t : 1 = 2 := sorry\n"),
    ("mid-file import, then @[implemented_by]",
      "\nimport Init.«..».Lake\ndef evil (_ : Nat) : Nat := 0\n@[implemented_by evil] def f (n : Nat) : Nat := n\n") ]

def coreCases : List (String × String × Bool) :=
  [ ("plain core header", "import Init\nimport Mitos.Core\n\ndef x : Nat := 1\n", true),
    ("tab before import Lean", "\timport Lean\n\ndef x : Nat := 1\n", false),
    ("tab before a later import", "import Init\n\timport Lean\n\ndef x : Nat := 1\n", false),
    ("import Lean", "import Lean\n\ndef x : Nat := 1\n", false),
    ("import Mitos.«..».Lean", "import Mitos.«..».Lean\n\ndef x : Nat := 1\n", false) ]

/-- For each rule, a source and the rules of its violations (`Lint.Rule.id`), as a model
(`checkModel`), a plugin (`check`) or a core file (`Imports.checkSource`). Each reports one rule
but `import:modifier`, which parses only under a `module` header. -/
def ruleCases : List (String × String × List Lint.Rule) :=
  [ ("plugin", "import Mitos.Core\n\ndef x : Nat := 1 ⊞ 2\n", [.parse]),
    ("plugin", "import Mitos.Core\ndef x := 1\nimport Lean\ntheorem t : 1 = 2 := sorry\n", [.parseStop]),
    ("core", "import\n", [.parseHeader]),
    ("plugin", "module\n\nimport Mitos.Core\n", [.importModule]),
    ("plugin", "prelude\nimport Mitos.Core\n", [.importPrelude]),
    ("plugin", "module\n\npublic import Mitos.Core\n", [.importModule, .importModifier]),
    ("plugin", "import Models.«a.b»\n", [.importComponent]),
    ("plugin", "import Mathlib\n", [.importRoot]),
    ("plugin", "import Mitos.Core\n#eval 1\n", [.hash]),
    ("plugin", "import Mitos.Core\nset_option pp.all true\n", [.setOption]),
    ("plugin", "import Mitos.Core\ndef s : String := include_str \"../comparator.json\"\n",
      [.includeStr]),
    ("model", model "variable (n : Nat)", [.modelCommand]),
    ("model", model "public section\nend", [.modelSection]),
    ("model", model "private def x : Nat := 1", [.modelModifier]),
    ("model", model "class inductive K where\n  | a", [.modelDeclaration]),
    ("model", model "class K where\n  a : Nat", [.modelClass]),
    ("model", model "@[reducible] def x : Nat := 1", [.modelAttribute]),
    ("model", model "inductive C where\n  | red\nwith\n  h : C → Nat\n  | .red => 0",
      [.modelComputedFields]),
    ("model", model "inductive C where\n  | red\n  deriving Repr", [.modelDeriving]) ]

def unguardedBans : List String :=
  [ "sorry", "admit", "axiom", "unsafe", "partial", "opaque", "noncomputable",
    "export", "csimp", "init", "builtin_init", "never_extract",
    "native_decide", "native", "ofReduceBool", "reduceBool", "trustCompiler",
    "notation", "infix", "infixl", "infixr", "prefix", "postfix",
    "macro", "macro_rules", "syntax", "elab", "elab_rules", "declare_syntax_cat",
    "binder_predicate", "instance", "scoped", "meta", "initialize", "builtin_initialize",
    "run_cmd", "run_elab", "run_meta", "debug", "Lean" ]

def cheatGuards : IO (Array (String × String)) := do
  let mut out := #[]
  for e in ← System.FilePath.readDir ("eval" / "cheats") do
    let f := e.path / "expect"
    if !e.fileName.startsWith "." && (← e.path.isDir) && (← f.pathExists) then
      for l in (← IO.FS.readFile f).splitOn "\n" do
        if l.startsWith "guards=" then out := out.push (e.fileName, (l.drop 7).toString)
  return out.qsort (fun a b => a.1 < b.1)

def unguardedRules : IO (List String) := do
  let txt ← IO.FS.readFile ("eval" / "cheats" / "unguarded")
  return (txt.splitOn "\n").filter fun l => !l.isEmpty && !l.startsWith "#"

def includeStrGuardError : String :=
  let includeId := Lint.Rule.includeStr.id
  s!"{includeId} is guarded by no cheat case (guards={includeId})"

def lacksIncludeStr : List (String × String) → Bool
  | [] => true
  | g :: gs => g.2 != Lint.Rule.includeStr.id && lacksIncludeStr gs

theorem lacksIncludeStr_iff {guards : List (String × String)} :
    lacksIncludeStr guards = true ↔ ∀ g ∈ guards, g.2 ≠ Lint.Rule.includeStr.id := by
  induction guards with
  | nil => simp [lacksIncludeStr]
  | cons g gs ih =>
    rw [lacksIncludeStr, Bool.and_eq_true, ih]
    simp [bne]

def appendMissingIncludeStr (guards : Array (String × String)) (errs : Array String) : Array String :=
  if lacksIncludeStr guards.toList then errs.push includeStrGuardError else errs

theorem appendMissingIncludeStr_of_absent {guards : Array (String × String)} {errs : Array String}
    (h : ∀ g ∈ guards.toList, g.2 ≠ Lint.Rule.includeStr.id) :
    includeStrGuardError ∈ (appendMissingIncludeStr guards errs).toList := by
  have hl : lacksIncludeStr guards.toList = true := lacksIncludeStr_iff.mpr h
  simp only [appendMissingIncludeStr, hl, ite_true]
  rw [Array.toList_push]
  exact List.mem_append_right _ (List.mem_singleton_self _)

def ratchet (guards : Array (String × String)) (unguarded : List String) : Array String :=
  appendMissingIncludeStr guards <| Id.run do
    let guardable := (Lint.Rule.fixed ++ Lint.banned.map Lint.Rule.banned).filter (·.guardable) |>.map (·.id)
    let bans := Lint.banned.map fun b => (Lint.Rule.banned b).id
    let pinned := unguardedBans.map fun b => (Lint.Rule.banned b).id
    let mut errs := #[]
    for (c, r) in guards do
      unless guardable.contains r do
        errs := errs.push s!"eval/cheats/{c} has guards={r}, which names no lint rule a case can guard"
    for r in bans do
      let by_ := guards.filter (·.2 == r) |>.map (·.1)
      if by_.isEmpty && !pinned.contains r then
        errs := errs.push s!"{r} is guarded by no cheat case (guards={r}) and not listed in unguardedBans"
      if !by_.isEmpty && pinned.contains r then
        errs := errs.push s!"{r} is guarded by {", ".intercalate by_.toList}, so take it off unguardedBans and eval/cheats/unguarded"
    for r in pinned do
      unless bans.contains r do
        errs := errs.push s!"unguardedBans lists {r}, which is not an entry of Lint.banned"
      unless unguarded.contains r do
        errs := errs.push s!"eval/cheats/unguarded does not list {r}, which unguardedBans lists"
    for r in unguarded.eraseDups do
      unless pinned.contains r do
        errs := errs.push s!"eval/cheats/unguarded lists {r}, which unguardedBans does not (a merge may have dropped that ban from Lint.banned and unguardedBans)"
      if (unguarded.filter (· == r)).length > 1 then
        errs := errs.push s!"eval/cheats/unguarded lists {r} more than once"
    return errs

theorem ratchet_reports_missing_includeStr (guards : Array (String × String))
    (unguarded : List String) (h : ∀ g ∈ guards.toList, g.2 ≠ Lint.Rule.includeStr.id) :
    includeStrGuardError ∈ (ratchet guards unguarded).toList := by
  simp only [ratchet]
  exact appendMissingIncludeStr_of_absent h

structure CiCase where
  name : String
  args : List String := []
  files : List (String × String) := []
  toy : Bool := false
  /-- Lines checked in place of a `mitos-gate` run. The comparator tail is this case. -/
  direct : Option (List String) := none

def ciCases (root : String) : List CiCase :=
  let plugin := "import Mitos.Core\n\ntheorem t : True := sorry\n"
  [ { name := "lint, a file argument that starts with ::"
      args := ["lint", "::warning::forged.lean"], files := [("::warning::forged.lean", plugin)] },
    { name := "lint, the legacy form in a file argument"
      args := ["lint", "x##[warning]forged.lean"], files := [("x##[warning]forged.lean", plugin)] },
    { name := "lint, a missing file (an uncaught I/O error)"
      args := ["lint", "##[warning]forged.lean"] },
    { name := "imports, the legacy form in a core file name"
      args := ["imports"], files := [("core/Mitos/x##[warning]forged.lean", "import Lean\n")] },
    { name := "lock --check, the legacy form and a CR in statements.lock"
      args := ["lock", "--check"],
      files := [("statements.lock", "x##[warning]forged\nx\r::warning::forged\n")] },
    { name := "lock-models --check, a workspace named ::, the legacy form in a model and its lock"
      args := ["lock-models", "--workspace", "::warning::forged", "--check"],
      files := [("::warning::forged/models.lock", "x##[warning]forged\n"),
        ("::warning::forged/Models/x##[warning]forged.lean", "def x : Nat := 1\n")] },
    { name := "accept, a CR in an unknown argument"
      args := ["accept", "x\r::warning::forged"] },
    { name := "runlog, the legacy form in an unknown argument"
      args := ["runlog", "##[warning]forged"] },
    { name := "accept, gate 0's line"
      args := ["accept", "--workspace", ".", "--plugin", "P", "--model", "Models.X.model",
        "--mitos-root", root, "--plugin-file", "##[warning]forged.lean"] },
    { name := "accept, gate 1's lines, a plugin file that starts with ::"
      args := ["accept", "--workspace", ".", "--plugin", "ToyRequire", "--model",
        "Models.ToyRequire.model", "--mitos-root", root, "--plugin-file", "::warning::forged.lean"],
      files := [("::warning::forged.lean", plugin)], toy := true },
    { name := "cheats, the legacy form in an option's value"
      args := ["cheats", "--jobs", "##[warning]forged"] },
    { name := "cheats, table rows of cases named :: and with the legacy form"
      args := ["cheats", "::warning::forged", "x##[warning]forged"],
      files := [("eval/cheats/README", ""), ("examples/acme/README", "")] },
    { name := "accept, the comparator tail of gates 2 to 6"
      direct := some (Accept.comparatorTail
        "error: ##[warning]forged\nx\r::warning::forged\n::error::forged") } ]

def runnerLines (out : String) : List String :=
  (out.splitOn "\n").flatMap (·.splitOn "\r")

def ciLog (root : System.FilePath) : IO (Array (String × String)) := do
  let lake := (← IO.getEnv "LAKE").getD "lake"
  let b ← IO.Process.output { cmd := lake, args := #["build", "-q", "mitos-gate"], cwd := root }
  if b.exitCode != 0 then
    return #[("build", s!"lake build mitos-gate failed: {b.stdout}{b.stderr}")]
  let gate := root / ".lake" / "build" / "bin" / "mitos-gate"
  let mut fails := #[]
  for c in ciCases root.toString do
    match c.direct with
    | some lines =>
      let text := "\n".intercalate lines
      let bad := (lines.flatMap runnerLines).filter (startsCommand ·)
      if let some l := bad.head? then
        fails := fails.push (c.name, s!"a line starts a workflow command: {l}")
      else unless (text.splitOn "forged").length > 1 do
        fails := fails.push (c.name, "the output does not show the hostile text")
    | none =>
      let dir ← IO.FS.createTempDir
      try
        for (rel, txt) in c.files do
          if let some p := (dir / rel).parent then IO.FS.createDirAll p
          IO.FS.writeFile (dir / rel) txt
        if c.toy then
          let acme := root / "examples" / "acme"
          copyFile (acme / "lean-toolchain") (dir / "lean-toolchain")
          copyFile (acme / "models.lock") (dir / "models.lock")
          copyLeanTree (acme / "Models") (dir / "Models")
        let out ← IO.Process.output { cmd := gate.toString, args := c.args.toArray, cwd := dir }
        let bad := (runnerLines out.stdout ++ runnerLines out.stderr).filter (startsCommand ·)
        if let some l := bad.head? then
          fails := fails.push (c.name, s!"a line starts a workflow command: {l}")
        else unless ((out.stdout ++ out.stderr).splitOn "forged").length > 1 do
          fails := fails.push (c.name, "the output does not show the hostile text")
      catch e => fails := fails.push (c.name, s!"could not run: {e}")
      IO.FS.removeDirAll dir
  return fails

/-- The number of cases `ciLog` runs. -/
def ciCount : Nat := (ciCases "").length

/-! ## The cheat runner's timeout

At a run's timeout, `CheatsRun.runChild` sends SIGKILL to the run's whole process group through
`Child.kill`, whose docstring says SIGTERM. Each case runs a `bash` child through
`CheatsRun.inRunDir` and `runChild` with a 1 s timeout. The child ignores SIGTERM and starts a
grandchild that ignores it too and holds the pipes. Both would sleep for 30 s, so on a toolchain
whose `Child.kill` sent SIGTERM the run would end only after 30 s, or with a code other than 137,
and the case would fail rather than hang. -/

def timeoutCases : List (String × String × UInt32) :=
  [ ("the child and its grandchild ignore SIGTERM",
      "trap '' TERM; sleep 30 & echo \"grandchild $!\"; echo x > \"$TMPDIR/left\"; wait", 137),
    ("the child exits at once; its grandchild ignores SIGTERM and holds the pipes",
      "trap '' TERM; sleep 30 & echo \"grandchild $!\"; echo x > \"$TMPDIR/left\"", 0) ]

/-- Whether process `pid` has not exited: `/proc/<pid>/stat` is there, and the state after the
command name, which is in parentheses, is neither zombie (`Z`) nor dead (`X`). -/
def running (pid : String) : IO Bool := do
  let stat ← try IO.FS.readFile ("/proc" / pid / "stat") catch _ => return false
  let state := (stat.toList.reverse.takeWhile (· != ')')).reverse.dropWhile (· == ' ')
  return !(state.head? == some 'Z' || state.head? == some 'X')

/-! ## Scoped tokens

`Lint.parse` does not activate the scoped parsers an `open` would turn on. `docs/process.md`
records that on this toolchain no `Init`/`Std` scoped token starts a string or a comment, so that
gap hides nothing, and that the fact is rechecked on each toolchain bump. This is that recheck:
a token that starts a string, character or name literal, or a comment, fails the test. -/

def startsLiteralOrComment (tk : String) : Bool :=
  tk.startsWith "\"" || tk.startsWith "'" || tk.startsWith "`" ||
    tk.startsWith "/-" || tk.startsWith "--"

def scopedTokensStartingLiteral (env : Lean.Environment) : Array String × Nat := Id.run do
  let stack := Lean.Parser.parserExtension.ext.getState env
  let mut bad : Array String := #[]
  let mut n := 0
  for (_ns, entries) in stack.scopedEntries.map do
    for e in entries do
      match e with
      | Lean.Parser.ParserExtension.Entry.token tk =>
        n := n + 1
        if startsLiteralOrComment tk then bad := bad.push tk
      | _ => pure ()
  return (bad, n)

def timeoutCase (script : String) (code : UInt32) : IO (List String) := do
  let dirOf ← IO.mkRef (none : Option System.FilePath)
  let t0 ← IO.monoMsNow
  let run ← CheatsRun.inRunDir fun dir => do
    dirOf.set (some dir)
    CheatsRun.runChild "bash" #["-c", script] (dir / "ws") (dir / "tmp") 1000
  let ms := (← IO.monoMsNow) - t0
  let mut errs := #[]
  unless run.timedOut do errs := errs.push "the run is not marked timed out"
  unless run.shown == "TIMEOUT" do errs := errs.push s!"the row would show {run.shown}"
  unless run.exitCode == code do errs := errs.push s!"exit {run.exitCode}, not {code}"
  unless ms < 15000 do errs := errs.push s!"the run took {ms} ms"
  let gc := (run.output.splitOn "\n").findSome? fun l =>
    let cs := l.toList
    if cs.take 11 == "grandchild ".toList then some (String.ofList (cs.drop 11)) else none
  match gc with
  | some p =>
    if p.isEmpty || !p.all Char.isDigit then errs := errs.push s!"grandchild pid {p}"
    else if ← running p then errs := errs.push s!"grandchild {p} still runs"
  | none => errs := errs.push s!"the grandchild did not start: {run.output}"
  match ← dirOf.get with
  | some d => if ← d.pathExists then errs := errs.push s!"{d} is still there"
  | none => errs := errs.push "no run directory was made"
  return errs.toList

structure Case where
  kind : String
  name : String
  src : String
  wantOk : Bool

def importSyntaxExcludedFromRuleCases : Lint.Rule → Bool
  | .importSyntax => true
  | _ => false

def main : IO UInt32 := do
  let env ← Lint.syntaxEnv
  let toy ← IO.FS.readFile ("examples" / "acme" / "Models" / "ToyRequire.lean")
  let plugin ← IO.FS.readFile ("examples" / "acme" / "Plugins" / "ToyRequire.lean")
  let body := "\ndef x : Nat := 1\n"
  let headers (kind : String) : List Case :=
    headersAccepted.map (fun (n, h) => ⟨kind, n, h ++ body, true⟩) ++
      headersRejected.map (fun (n, h) => ⟨kind, n, h ++ body, false⟩)
  let stops (kind base : String) : List Case :=
    ⟨kind, "mid-file import (short)",
      "import Mitos.Core\ndef x := 1\nimport Lean\ntheorem t : 1 = 2 := sorry\n", false⟩ ::
      stopsRejected.map (fun (n, s) => ⟨kind, s!"acme {kind}, {n}", base ++ s, false⟩)
  let cases : List Case :=
    ⟨"model", "examples/acme/Models/ToyRequire.lean", toy, true⟩ ::
      accepted.map (fun (n, s) => ⟨"model", n, s, true⟩) ++
      rejected.map (fun (n, s) => ⟨"model", n, s, false⟩) ++ headers "model" ++ stops "model" toy ++
      [⟨"plugin", "examples/acme/Plugins/ToyRequire.lean", plugin, true⟩,
       ⟨"plugin", "include_str",
         "import Mitos.Core\n\ndef s : String := include_str \"../comparator.json\"\n", false⟩] ++
      headers "plugin" ++ stops "plugin" plugin ++
      [⟨"core", "core/Mitos/Core.lean", ← IO.FS.readFile ("core" / "Mitos" / "Core.lean"), true⟩] ++
      coreCases.map (fun (n, s, w) => ⟨"core", n, s, w⟩)
  let lintAs (kind src : String) : IO (Array Lint.Violation) :=
    if kind == "model" then Lint.checkModel env Accept.pluginImports src
    else if kind == "core" then Imports.checkSource Imports.trustedCoreImports src
    else Lint.check env Accept.pluginImports src
  let mut fails := 0
  for c in cases do
    let vs ← lintAs c.kind c.src
    let ok := vs.isEmpty
    let mark := if ok == c.wantOk then "ok  " else "FAIL"
    if ok != c.wantOk then fails := fails + 1
    let verdict := if ok then "accepted" else s!"rejected: {(vs[0]?.map (·.render s!"<{c.kind}>")).getD ""}"
    IO.println (ciLine s!"{mark} {c.kind} {c.name}: {verdict}")
  for (kind, src, want) in ruleCases do
    let got := (← lintAs kind src).toList.map (·.rule) |>.eraseDups
    let ok := got.length == want.length && want.all got.contains
    if !ok then fails := fails + 1
    let ids (rs : List Lint.Rule) := ", ".intercalate (rs.map (·.id))
    IO.println s!"{if ok then "ok  " else "FAIL"} rules [{ids want}] ({kind}): got [{ids got}]"
  let missing := Lint.Rule.fixed.filter fun r =>
    !importSyntaxExcludedFromRuleCases r && !ruleCases.any (·.2.2.contains r)
  unless missing.isEmpty do
    fails := fails + 1
    IO.println s!"FAIL rule cases: none for {", ".intercalate (missing.map (·.id))}"
  let guards ← cheatGuards
  let unguarded ← unguardedRules
  let errs := ratchet guards unguarded
  for e in errs do IO.println (ciLine s!"FAIL ratchet: {e}")
  let includeId := Lint.Rule.includeStr.id
  let dropped := ratchet (guards.filter (·.2 != includeId)) unguarded
  unless dropped.any (· == includeStrGuardError) do
    fails := fails + 1
    IO.println (ciLine s!"FAIL ratchet: dropping guards={includeId} is not reported")
  let guarded := (Lint.banned.filter fun b => guards.any (·.2 == (Lint.Rule.banned b).id)).length
  IO.println (ciLine s!"{if errs.isEmpty then "ok  " else "FAIL"} ratchet: {Lint.banned.length} bans, {guarded} guarded by a cheat case, {unguardedBans.length} in unguardedBans, {unguarded.length} in eval/cheats/unguarded; guards: {", ".intercalate (guards.toList.map fun (c, r) => s!"{c}={r}")}")
  unless errs.isEmpty do fails := fails + 1
  let ci ← ciLog (← IO.currentDir)
  for (n, why) in ci do IO.println (ciLine s!"FAIL ci-log {n}: {why}")
  let nci := ciCount
  IO.println (s!"{if ci.isEmpty then "ok  " else "FAIL"} ci-log: {nci - ci.size} of {nci} " ++
    "hostile cases print no workflow command")
  fails := fails + ci.size
  for (name, script, code) in timeoutCases do
    let errs ← timeoutCase script code
    unless errs.isEmpty do fails := fails + 1
    let detail := if errs.isEmpty then s!"timed out, exit {code}, nothing left" else "; ".intercalate errs
    IO.println (ciLine s!"{if errs.isEmpty then "ok  " else "FAIL"} cheat runner timeout, {name}: {detail}")
  let (badTokens, nScoped) := scopedTokensStartingLiteral env
  if nScoped == 0 then
    fails := fails + 1
    IO.println (ciLine "FAIL scoped tokens: Parser.parserExtension has no scoped token in Init and Std")
  else if !badTokens.isEmpty then
    fails := fails + 1
    IO.println (ciLine s!"FAIL scoped tokens: {", ".intercalate badTokens.toList} start a literal or a comment ({nScoped} scoped tokens)")
  else
    IO.println (ciLine s!"ok  scoped tokens: {nScoped} from Init and Std, none starts a literal or a comment")
  let total := cases.length + ruleCases.length + 1 + nci + timeoutCases.length + 1
  let count (k : String) (w : Bool) := (cases.filter fun c => c.kind == k && c.wantOk == w).length
  let summary := s!"model: {count "model" true} accepted, {count "model" false} rejected; plugin: {count "plugin" true} accepted, {count "plugin" false} rejected; core imports: {count "core" true} accepted, {count "core" false} rejected; {ruleCases.length} rule cases; the ban ratchet; {nci} CI-log cases; {timeoutCases.length} cheat-runner timeout cases; the scoped-token scan"
  if fails == 0 then
    IO.println s!"gate-1 lint: all {total} cases behave as expected ({summary})"
    return 0
  IO.println s!"gate-1 lint: {fails} of {total} cases FAILED"
  return 1
