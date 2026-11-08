import MitosGate.Lint
import MitosGate.Accept

/-! Regression test for gate 1's model lint (`Lint.checkModel`): every command kind outside the
model allowlist is rejected, every allowed kind is accepted, and models pass the plugin rules.
Run with `lake exe mitos-lint-test` from the repository root. -/

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
    ("Lean.ofReduceBool", model "def x := Lean.ofReduceBool"),
    ("trustCompiler", model "def x := Lean.trustCompiler"),
    ("set_option debug in a proof", model "theorem t : 1 = 1 := by\n  set_option debug.skipKernelTC true in rfl"),
    -- Syntax the toolchain's Init/Std parser does not know.
    ("unknown syntax", model "def x : Nat := 1 ⊞ 2") ]

def main : IO UInt32 := do
  let env ← Lint.syntaxEnv
  let mut fails := 0
  let toy ← IO.FS.readFile ("examples" / "acme" / "Models" / "ToyRequire.lean")
  for (name, src, wantOk) in (("examples/acme/Models/ToyRequire.lean", toy) :: accepted).map
      (fun (n, s) => (n, s, true)) ++ rejected.map (fun (n, s) => (n, s, false)) do
    let vs ← Lint.checkModel env Accept.pluginImports src
    let ok := vs.isEmpty
    let mark := if ok == wantOk then "ok  " else "FAIL"
    if ok != wantOk then fails := fails + 1
    let verdict := if ok then "accepted" else s!"rejected: {(vs[0]?.map (·.render "<model>")).getD ""}"
    IO.println s!"{mark} {name}: {verdict}"
  let total := accepted.length + 1 + rejected.length
  if fails == 0 then
    IO.println s!"model lint: all {total} cases behave as expected ({accepted.length + 1} accepted, {rejected.length} rejected)"
    return 0
  IO.println s!"model lint: {fails} of {total} cases FAILED"
  return 1
