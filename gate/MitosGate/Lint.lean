import Lean

namespace MitosGate.Lint
open Lean

structure Token where
  text : String
  line : Nat
  col  : Nat
  deriving Repr

structure Violation where
  line : Nat
  col  : Nat
  msg  : String

def Violation.render (file : String) (v : Violation) : String :=
  s!"{file}:{v.line}:{v.col}: {v.msg}"

/-- The syntax plugins are parsed with: the toolchain's `Init` and `Std`, the only imports a plugin
may use that can declare notation. Lean's own parser decides what is a literal, a comment or a
token, so the lint sees exactly the tokens Lean will elaborate. -/
def syntaxEnv : IO Environment := do
  unsafe enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules #[{ module := `Init }, { module := `Std }] {} (loadExts := true)

private def isText (k : SyntaxNodeKind) : Bool :=
  k == strLitKind || k == charLitKind || k == interpolatedStrLitKind || k == nameLitKind ||
  k == numLitKind || k == scientificLitKind ||
  k == ``Parser.Command.docComment || k == ``Parser.Command.moduleDoc

/-- Identifiers are rendered without guillemets, so `«sorry»` is seen as `sorry`. -/
partial def tokensOf (fm : FileMap) (stx : Syntax) (acc : Array Token) : Array Token :=
  let push (text : String) : Array Token :=
    let pos := fm.toPosition (stx.getPos?.getD 0)
    acc.push { text, line := pos.line, col := pos.column + 1 }
  match stx with
  | .node _ k args => if isText k then acc else args.foldl (fun a s => tokensOf fm s a) acc
  | .atom _ v => push v
  | .ident _ _ n _ => push (n.toString (escape := false))
  | .missing => acc

def headerTokens (src : String) : IO (Array Token) := do
  let ictx := Parser.mkInputContext src "<source>"
  let (header, _, _) ← Parser.parseHeader ictx
  return tokensOf ictx.fileMap header #[]

/-- Every token Lean's parser produces for `src`, or the first parse error with its position. -/
def tokenize (env : Environment) (src : String) : IO (Except Violation (Array Token)) := do
  let ictx := Parser.mkInputContext src "<source>"
  let (header, st, msgs) ← Parser.parseHeader ictx
  let pctx : Parser.ParserModuleContext := { env, options := {} }
  let mut toks := tokensOf ictx.fileMap header #[]
  let mut st := st
  let mut msgs := msgs
  repeat
    let (cmd, st', msgs') := Parser.parseCommand ictx pctx st msgs
    st := st'
    msgs := msgs'
    toks := tokensOf ictx.fileMap cmd toks
    if Parser.isTerminalCommand cmd then break
  match msgs.toList.find? (·.severity == .error) with
  | some m =>
    let text ← m.data.toString
    return .error { line := m.pos.line, col := m.pos.column + 1,
                    msg := s!"does not parse with the toolchain's syntax ({text.trimAscii}); plugins may not declare notation" }
  | none => return .ok toks

def banned : List String :=
  [ "sorry", "admit", "axiom", "unsafe", "partial", "opaque", "noncomputable",
    "implemented_by", "extern", "export", "csimp", "init", "builtin_init", "never_extract",
    "native_decide", "native", "ofReduceBool", "reduceBool", "trustCompiler",
    "notation", "infix", "infixl", "infixr", "prefix", "postfix",
    "macro", "macro_rules", "syntax", "elab", "elab_rules", "declare_syntax_cat",
    "instance", "scoped", "meta", "initialize", "builtin_initialize",
    "run_cmd", "run_elab", "run_meta", "debug", "Lean" ]

def allowedHashCommands : List String := ["#check", "#print"]

def allowedOptionPrefixes : List String := ["maxHeartbeats", "maxRecDepth", "linter."]

def components (t : String) : List String :=
  (t.splitOn ".").filter (· != "")

def moduleAllowed (allowed : List String) (mod : String) : Bool :=
  allowed.any fun p => mod == p || mod.startsWith (p ++ ".")

/-- Check a plugin's source, parsed in `env` (see `syntaxEnv`). `allowedImports` lists module
prefixes it may import. -/
def check (env : Environment) (allowedImports : List String) (src : String) :
    IO (Array Violation) := do
  let toks ← match ← tokenize env src with
    | .ok toks => pure toks
    | .error v => return #[v]
  let mut vs : Array Violation := #[]
  for h : k in [0:toks.size] do
    let t := toks[k]
    let nextTok := toks[k+1]?
    if t.text == "import" then
      match nextTok with
      | some m =>
        unless moduleAllowed allowedImports m.text do
          vs := vs.push { line := m.line, col := m.col, msg := s!"import `{m.text}` is not allowed" }
      | none => pure ()
    else if t.text.startsWith "#" then
      unless allowedHashCommands.contains t.text do
        vs := vs.push { line := t.line, col := t.col, msg := s!"command `{t.text}` is not allowed" }
    else if t.text == "set_option" then
      let ok := match nextTok with
        | some o => allowedOptionPrefixes.any (o.text.startsWith ·)
        | none => false
      unless ok do
        vs := vs.push { line := t.line, col := t.col,
                        msg := s!"`set_option {(nextTok.map (·.text)).getD ""}` is not allowed" }
    else
      for c in components t.text do
        if banned.contains c then
          vs := vs.push { line := t.line, col := t.col, msg := s!"`{c}` is not allowed in plugins" }
  return vs

end MitosGate.Lint
