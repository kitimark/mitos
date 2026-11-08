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

def syntaxEnv : IO Environment := do
  unsafe enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules #[{ module := `Init }, { module := `Std }] {} (loadExts := true)

private def isText (k : SyntaxNodeKind) : Bool :=
  k == strLitKind || k == charLitKind || k == interpolatedStrLitKind || k == nameLitKind ||
  k == numLitKind || k == scientificLitKind ||
  k == ``Parser.Command.docComment || k == ``Parser.Command.moduleDoc

def deEscapeIdent (n : Name) : String :=
  n.toString (escape := false)

partial def tokensOf (fm : FileMap) (stx : Syntax) (acc : Array Token) : Array Token :=
  let push (text : String) : Array Token :=
    let pos := fm.toPosition (stx.getPos?.getD 0)
    acc.push { text, line := pos.line, col := pos.column + 1 }
  match stx with
  | .node _ k args => if isText k then acc else args.foldl (fun a s => tokensOf fm s a) acc
  | .atom _ v => push v
  | .ident _ _ n _ => push (deEscapeIdent n)
  | .missing => acc

def headerTokens (src : String) : IO (Array Token) := do
  let ictx := Parser.mkInputContext src "<source>"
  let (header, _, _) ← Parser.parseHeader ictx
  return tokensOf ictx.fileMap header #[]

/-- The header and top-level commands Lean's parser produces for `src`, or the first parse error
with its position. -/
def parse (env : Environment) (src : String) :
    IO (Except Violation (FileMap × Syntax × Array Syntax)) := do
  let ictx := Parser.mkInputContext src "<source>"
  let (header, st, msgs) ← Parser.parseHeader ictx
  let pctx : Parser.ParserModuleContext := { env, options := {} }
  let mut cmds := #[]
  let mut st := st
  let mut msgs := msgs
  repeat
    let (cmd, st', msgs') := Parser.parseCommand ictx pctx st msgs
    st := st'
    msgs := msgs'
    -- `#exit` is terminal too; keep it, so the rules see it.
    unless cmd.isOfKind ``Parser.Command.eoi do cmds := cmds.push cmd
    if Parser.isTerminalCommand cmd then break
  match msgs.toList.find? (·.severity == .error) with
  | some m =>
    let text ← m.data.toString
    return .error { line := m.pos.line, col := m.pos.column + 1,
                    msg := s!"does not parse with the toolchain's syntax ({text.trimAscii}); plugins may not declare notation" }
  | none => return .ok (ictx.fileMap, header, cmds)

private def allTokens (fm : FileMap) (header : Syntax) (cmds : Array Syntax) : Array Token :=
  cmds.foldl (fun a c => tokensOf fm c a) (tokensOf fm header #[])

/-- Every token Lean's parser produces for `src`, or the first parse error with its position. -/
def tokenize (env : Environment) (src : String) : IO (Except Violation (Array Token)) := do
  return (← parse env src).map fun (fm, header, cmds) => allTokens fm header cmds

def banned : List String :=
  [ "sorry", "admit", "axiom", "unsafe", "partial", "opaque", "noncomputable",
    "implemented_by", "extern", "export", "csimp", "init", "builtin_init", "never_extract",
    "native_decide", "native", "ofReduceBool", "reduceBool", "trustCompiler",
    "notation", "infix", "infixl", "infixr", "prefix", "postfix",
    "macro", "macro_rules", "syntax", "elab", "elab_rules", "declare_syntax_cat",
    "binder_predicate", "instance", "scoped", "meta", "initialize", "builtin_initialize",
    "run_cmd", "run_elab", "run_meta", "debug", "Lean" ]

def allowedHashCommands : List String := ["#check", "#print"]

def allowedOptionPrefixes : List String := ["maxHeartbeats", "maxRecDepth", "linter."]

def components (t : String) : List String :=
  (t.splitOn ".").filter (· != "")

def moduleAllowed (allowed : List String) (mod : String) : Bool :=
  allowed.any fun p => mod == p || mod.startsWith (p ++ ".")

/-- The plugin rules, over the tokens of a parsed source. `allowedImports` lists module prefixes it
may import. -/
def tokenRules (allowedImports : List String) (toks : Array Token) (what := "plugins") :
    Array Violation := Id.run do
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
          vs := vs.push { line := t.line, col := t.col, msg := s!"`{c}` is not allowed in {what}" }
  return vs

/-- Check a plugin's source, parsed in `env` (see `syntaxEnv`). `allowedImports` lists module
prefixes it may import. -/
def check (env : Environment) (allowedImports : List String) (src : String) :
    IO (Array Violation) := do
  match ← tokenize env src with
  | .ok toks => return tokenRules allowedImports toks
  | .error v => return #[v]

/-! ## Model allowlist

A plugin may use what a model defines, so a model passes every plugin rule (`tokenRules`). On top,
it may contain only the commands a reviewed model needs (`commandRules`). Each allowed command is a
built-in one that adds no syntax, runs no code at build time and leaves compiled code alone, so
"models declare no syntax" holds by construction, not by naming the commands that do. -/

/-- Top-level commands a model may contain. -/
def modelCommands : List SyntaxNodeKind :=
  [ ``Parser.Command.moduleDoc, ``Parser.Command.namespace, ``Parser.Command.section,
    ``Parser.Command.end, ``Parser.Command.open, ``Parser.Command.declaration ]

/-- Declarations a model may contain: not `instance`, `class`, `axiom`, `opaque`, `coinductive`. -/
def modelDeclarations : List SyntaxNodeKind :=
  [ ``Parser.Command.definition, ``Parser.Command.theorem, ``Parser.Command.abbrev,
    ``Parser.Command.example, ``Parser.Command.structure, ``Parser.Command.inductive ]

/-- Attributes a model may use, wherever they appear (declarations, constructors, fields, `where`
clauses). -/
def modelAttributes : List SyntaxNodeKind := [``Parser.Attr.simp]

private def kindName (k : SyntaxNodeKind) : String :=
  match k with
  | .str _ s => s
  | _ => k.toString

private def isEmptyNode (stx : Syntax) : Bool :=
  stx.isMissing || (stx.isOfKind nullKind && stx.getNumArgs == 0)

private def listed (ks : List SyntaxNodeKind) : String :=
  ", ".intercalate (ks.map kindName)

/-- The model allowlist over a model's top-level commands. Each violation names the command kind. -/
partial def commandRules (fm : FileMap) (cmds : Array Syntax) : Array Violation := Id.run do
  let at_ (stx : Syntax) (msg : String) : Violation :=
    let pos := fm.toPosition (stx.getPos?.getD 0)
    { line := pos.line, col := pos.column + 1, msg }
  let head (stx : Syntax) : String :=
    ((tokensOf fm stx #[])[0]?.map (·.text)).getD "?"
  let mut vs : Array Violation := #[]
  for cmd in cmds do
    let k := cmd.getKind
    if !modelCommands.contains k then
      vs := vs.push <| at_ cmd
        s!"command `{head cmd}` ({kindName k}) is not allowed in models; they may contain only {listed modelCommands}"
      continue
    if k == ``Parser.Command.section && !(cmd[0].getArgs.all isEmptyNode) then
      vs := vs.push <| at_ cmd s!"`{head cmd} … section` is not allowed in models; only a plain `section`"
    if k == ``Parser.Command.declaration then
      let mods := cmd[0]
      let decl := cmd[1]
      unless (mods.getArgs.extract 2 mods.getNumArgs).all isEmptyNode do
        vs := vs.push <| at_ cmd
          "declaration modifiers other than a doc comment and attributes are not allowed in models"
      if !modelDeclarations.contains decl.getKind then
        vs := vs.push <| at_ decl
          s!"declaration `{head decl}` ({kindName decl.getKind}) is not allowed in models; they may declare only {listed modelDeclarations}"
      else if decl.getKind == ``Parser.Command.structure &&
          decl[0].getKind != ``Parser.Command.structureTk then
        vs := vs.push <| at_ decl s!"declaration `{head decl}` is not allowed in models"
  -- Inside the allowed commands: attributes outside `modelAttributes`; `deriving`, which generates
  -- instances; and computed fields, which replace a constructor's compiled code.
  let rec walk (stx : Syntax) (vs : Array Violation) : Array Violation :=
    match stx with
    | .node _ k args =>
      let vs :=
        if k == ``Parser.Term.attrInstance && !modelAttributes.contains stx[1].getKind then
          vs.push <| at_ stx[1] s!"attribute `{head stx[1]}` is not allowed in models; they may use only {listed modelAttributes}"
        else if k == ``Parser.Command.computedFields then
          vs.push <| at_ stx "computed fields (`with`) are not allowed in models"
        else vs
      args.foldl (fun a s => walk s a) vs
    | .atom _ "deriving" => vs.push <| at_ stx "`deriving` is not allowed in models"
    | _ => vs
  return cmds.foldl (fun a c => walk c a) vs

/-- Check a model's source, parsed in `env`. Plugins are parsed in `env` alone, so a model may not
change their syntax; and a plugin may use what a model defines, so a model must pass every plugin
rule too. A model passes `tokenRules` (imports within `allowedImports`) and `commandRules`. -/
def checkModel (env : Environment) (allowedImports : List String) (src : String) :
    IO (Array Violation) := do
  match ← parse env src with
  | .error v => return #[v]
  | .ok (fm, header, cmds) =>
    return tokenRules allowedImports (allTokens fm header cmds) "models" ++ commandRules fm cmds

end MitosGate.Lint
