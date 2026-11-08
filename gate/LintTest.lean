import MitosGate.Lint
import MitosGate.Accept
import MitosGate.Imports

/-! Regression test for gate 1's lint: every command kind outside the model allowlist is rejected,
every allowed kind is accepted, models pass the plugin rules, and the import rule holds for
plugins and models alike (`Lint.check`, `Lint.checkModel`). Each rule reports under its own id
(`ruleCases`), and each ban is guarded by a cheat case or listed in `eval/cheats/unguarded`
(`ratchet`). Run with `lake exe mitos-lint-test` from the repository root. -/

open MitosGate

/-- A model source: the header a reviewed model has, then `body`. -/
def model (body : String) : String :=
  "import Mitos.Core\n\nnamespace Models.T\n\n" ++ body ++ "\n\nend Models.T\n"

/-- Sources a model may contain. -/
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

/-- Sources a model may not contain: the command kinds outside the allowlist, and the plugin rules. -/
def rejected : List (String × String) :=
  [ -- The notation family.
    ("notation", model "notation \"req--\" => 1"),
    ("local notation", model "local notation \"req--\" => 1"),
    ("scoped notation", model "scoped notation \"req--\" => 1"),
    ("infix", model "infix:65 \" +++ \" => Nat.add"),
    ("infixl", model "infixl:65 \" +++ \" => Nat.add"),
    ("infixr", model "infixr:65 \" +++ \" => Nat.add"),
    ("prefix", model "prefix:max \"√\" => Nat.sqrt"),
    ("postfix", model "postfix:max \"!\" => Nat.succ"),
    -- Macros and syntax.
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
    -- Options and `#`-commands.
    ("set_option", model "set_option maxHeartbeats 400000"),
    ("set_option ... in", model "set_option maxHeartbeats 400000 in\ndef x : Nat := 1"),
    ("set_option debug", model "set_option debug.skipKernelTC true"),
    ("#eval", model "#eval 1"),
    ("#check", model "#check Nat"),
    ("#print", model "#print Nat"),
    ("#reduce", model "#reduce 1 + 1"),
    ("#exit", model "#exit"),
    ("run_cmd", model "run_cmd pure ()"),
    -- Other commands outside the allowlist.
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
    -- Declarations outside the allowlist.
    ("instance", model "instance : Inhabited Nat := ⟨1⟩"),
    ("class", model "class K where\n  a : Nat"),
    ("class inductive", model "class inductive K where\n  | a"),
    ("axiom", model "axiom ax : False"),
    ("opaque", model "opaque o : Nat"),
    ("deriving clause", model "inductive C where\n  | red\n  deriving Repr"),
    ("def deriving clause", model "def N := Nat deriving Inhabited"),
    ("computed fields", model "inductive C where\n  | red\nwith\n  h : C → Nat\n  | .red => 0"),
    -- Modifiers outside the allowlist.
    ("private", model "private def x : Nat := 1"),
    ("protected", model "protected def x : Nat := 1"),
    ("noncomputable", model "noncomputable def x : Nat := 1"),
    ("unsafe", model "unsafe def x : Nat := 1"),
    ("partial", model "partial def f (n : Nat) : Nat := f n"),
    ("nonrec", model "nonrec def x : Nat := 1"),
    ("meta", model "meta def x : Nat := 1"),
    -- Attributes outside the allowlist, wherever they appear.
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
    -- Plugin rules a model must also pass.
    ("sorry", model "theorem t : 1 = 2 := sorry"),
    ("«sorry»", model "theorem t : 1 = 2 := «sorry»"),
    ("admit", model "theorem t : 1 = 2 := by admit"),
    ("native_decide", model "theorem t : 1 = 1 := by native_decide"),
    ("include_str", model "def s : String := include_str \"../comparator.json\""),
    ("Lean.ofReduceBool", model "def x := Lean.ofReduceBool"),
    ("trustCompiler", model "def x := Lean.trustCompiler"),
    ("set_option debug in a proof", model "theorem t : 1 = 1 := by\n  set_option debug.skipKernelTC true in rfl"),
    -- Syntax the toolchain's Init/Std parser does not know.
    ("unknown syntax", model "def x : Nat := 1 ⊞ 2") ]

/-- Headers both plugins and models may have, each followed by a body without banned tokens. -/
def headersAccepted : List (String × String) :=
  [ ("plain imports", "import Init\nimport Std.Data.HashMap\nimport Mitos.Core\nimport Models.ToyRequire\n"),
    ("escaped plain component", "import «Mitos».Core\n") ]

/-- Headers neither may have: escaped components that leave an allowed root, other roots, and
the `module`/`prelude` forms. -/
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

/-- Sources where Lean's parser stops before the end of the file; neither may have them. Each is
appended to a source that is otherwise accepted. -/
def stopsRejected : List (String × String) :=
  [ ("mid-file import, then sorry", "\nimport Lean\ntheorem t : 1 = 2 := sorry\n"),
    ("mid-file import, then @[implemented_by]",
      "\nimport Init.«..».Lake\ndef evil (_ : Nat) : Nat := 0\n@[implemented_by evil] def f (n : Nat) : Nat := n\n") ]

/-- The roots `mitos-gate imports` allows in `core/`, as in `gate/Main.lean`. -/
def coreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

/-- Core-style sources for `mitos-gate imports` (`Imports.checkSource`). -/
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
      [.banned "include_str"]),
    ("model", model "variable (n : Nat)", [.modelCommand]),
    ("model", model "public section\nend", [.modelSection]),
    ("model", model "private def x : Nat := 1", [.modelModifier]),
    ("model", model "class inductive K where\n  | a", [.modelDeclaration]),
    ("model", model "class K where\n  a : Nat", [.modelClass]),
    ("model", model "@[reducible] def x : Nat := 1", [.modelAttribute]),
    ("model", model "inductive C where\n  | red\nwith\n  h : C → Nat\n  | .red => 0",
      [.modelComputedFields]),
    ("model", model "inductive C where\n  | red\n  deriving Repr", [.modelDeriving]) ]

/-! ## Ban ratchet

Each entry of `Lint.banned` is guarded by a cheat case, whose `expect` has `guards=banned:<token>`
(`eval/cheats/run.sh` checks the claim), or listed in `eval/cheats/unguarded`. A change that drops
a ban, as #21's rebase did, then turns this test red, whether or not a case guarded it. -/

/-- How many bans `eval/cheats/unguarded` lists. The list may only shrink: a PR that guards a ban
takes it off the list and lowers this number, and a PR that adds one must raise it here, in trusted
code the owner merges. A number in the test, rather than a comparison with `main`'s copy, needs no
git history or CI step, so the test gives the same answer locally and in CI. -/
def unguardedCount : Nat := 40

/-- `(case, rule)` for each `guards=` line of an `eval/cheats/<case>/expect`. -/
def cheatGuards : IO (Array (String × String)) := do
  let mut out := #[]
  for e in ← System.FilePath.readDir ("eval" / "cheats") do
    let f := e.path / "expect"
    if (← e.path.isDir) && (← f.pathExists) then
      for l in (← IO.FS.readFile f).splitOn "\n" do
        if l.startsWith "guards=" then out := out.push (e.fileName, (l.drop 7).toString)
  return out.qsort (fun a b => a.1 < b.1)

/-- The rules `eval/cheats/unguarded` lists, one per line; blank lines and `#` comments aside. -/
def unguardedRules : IO (List String) := do
  let txt ← IO.FS.readFile ("eval" / "cheats" / "unguarded")
  return (txt.splitOn "\n").filter fun l => !l.isEmpty && !l.startsWith "#"

/-- Every way the guards and the list break the ratchet, one message each. -/
def ratchet (guards : Array (String × String)) (unguarded : List String) : Array String := Id.run do
  let guardable := (Lint.Rule.fixed ++ Lint.banned.map Lint.Rule.banned).filter (·.guardable) |>.map (·.id)
  let bans := Lint.banned.map fun b => (Lint.Rule.banned b).id
  let mut errs := #[]
  for (c, r) in guards do
    unless guardable.contains r do
      errs := errs.push s!"eval/cheats/{c} has guards={r}, which names no lint rule a case can guard"
  for r in bans do
    let by_ := guards.filter (·.2 == r) |>.map (·.1)
    if by_.isEmpty && !unguarded.contains r then
      errs := errs.push s!"{r} is guarded by no cheat case (guards={r}) and not listed in eval/cheats/unguarded"
    if !by_.isEmpty && unguarded.contains r then
      errs := errs.push s!"{r} is guarded by {", ".intercalate by_.toList}, so take it off eval/cheats/unguarded"
  for r in unguarded.eraseDups do
    unless bans.contains r do
      errs := errs.push s!"eval/cheats/unguarded lists {r}, which is not an entry of Lint.banned"
    -- A repeat would keep the count while a dropped ban leaves the list.
    if (unguarded.filter (· == r)).length > 1 then
      errs := errs.push s!"eval/cheats/unguarded lists {r} more than once"
  if unguarded.length > unguardedCount then
    errs := errs.push s!"eval/cheats/unguarded lists {unguarded.length} rules, more than unguardedCount ({unguardedCount}); the list may only shrink"
  else if unguarded.length < unguardedCount then
    errs := errs.push s!"eval/cheats/unguarded lists {unguarded.length} rules; lower unguardedCount ({unguardedCount}) to match"
  return errs

structure Case where
  kind : String
  name : String
  src : String
  wantOk : Bool

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
    else if kind == "core" then Imports.checkSource coreImports src
    else Lint.check env Accept.pluginImports src
  let mut fails := 0
  for c in cases do
    let vs ← lintAs c.kind c.src
    let ok := vs.isEmpty
    let mark := if ok == c.wantOk then "ok  " else "FAIL"
    if ok != c.wantOk then fails := fails + 1
    let verdict := if ok then "accepted" else s!"rejected: {(vs[0]?.map (·.render s!"<{c.kind}>")).getD ""}"
    IO.println s!"{mark} {c.kind} {c.name}: {verdict}"
  for (kind, src, want) in ruleCases do
    let got := (← lintAs kind src).toList.map (·.rule) |>.eraseDups
    let ok := got.length == want.length && want.all got.contains
    if !ok then fails := fails + 1
    let ids (rs : List Lint.Rule) := ", ".intercalate (rs.map (·.id))
    IO.println s!"{if ok then "ok  " else "FAIL"} rules [{ids want}] ({kind}): got [{ids got}]"
  -- `import:syntax` has no case: on a header that parses, every import names a module.
  let missing := Lint.Rule.fixed.filter fun r =>
    r != .importSyntax && !ruleCases.any (·.2.2.contains r)
  unless missing.isEmpty do
    fails := fails + 1
    IO.println s!"FAIL rule cases: none for {", ".intercalate (missing.map (·.id))}"
  let guards ← cheatGuards
  let unguarded ← unguardedRules
  let errs := ratchet guards unguarded
  for e in errs do IO.println s!"FAIL ratchet: {e}"
  let guarded := (Lint.banned.filter fun b => guards.any (·.2 == (Lint.Rule.banned b).id)).length
  IO.println s!"{if errs.isEmpty then "ok  " else "FAIL"} ratchet: {Lint.banned.length} bans, {guarded} guarded by a cheat case, {unguarded.length} in eval/cheats/unguarded; guards: {", ".intercalate (guards.toList.map fun (c, r) => s!"{c}={r}")}"
  unless errs.isEmpty do fails := fails + 1
  let total := cases.length + ruleCases.length + 1
  let count (k : String) (w : Bool) := (cases.filter fun c => c.kind == k && c.wantOk == w).length
  let summary := s!"model: {count "model" true} accepted, {count "model" false} rejected; plugin: {count "plugin" true} accepted, {count "plugin" false} rejected; core imports: {count "core" true} accepted, {count "core" false} rejected; {ruleCases.length} rule cases; the ban ratchet"
  if fails == 0 then
    IO.println s!"gate-1 lint: all {total} cases behave as expected ({summary})"
    return 0
  IO.println s!"gate-1 lint: {fails} of {total} cases FAILED"
  return 1
