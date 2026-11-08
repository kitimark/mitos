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

/-- The parsed module header of `src`, or its first parse error: a header that fails to parse
comes back empty, so its imports would go unchecked. -/
def headerSyntax (src : String) : IO (Except Violation (FileMap × Syntax)) := do
  let ictx := Parser.mkInputContext src "<source>"
  let (header, _, msgs) ← Parser.parseHeader ictx
  match msgs.toList.find? (·.severity == .error) with
  | some m =>
    let text ← m.data.toString
    return .error { line := m.pos.line, col := m.pos.column + 1,
                    msg := s!"the header does not parse ({text.trimAscii}), so its imports cannot be checked" }
  | none => return .ok (ictx.fileMap, header)

def isEmptyNode (stx : Syntax) : Bool :=
  stx.isMissing || (stx.isOfKind nullKind && stx.getNumArgs == 0)

/-- A component made of identifier characters only: not empty, starts with an identifier-start
character, and has no `.` or space. Keywords such as `«import»` pass; such a component still sits
inside the allowed root it follows. -/
def plainIdent (s : String) : Bool :=
  match s.toList with
  | c :: cs => isIdFirst c && cs.all isIdRest
  | [] => false

/-- The components of a module name, if each is a plain identifier. `Models.«..».Mitos.Impl` has
the component `..`, so it has none. -/
def plainComponents : Name → Option (List String)
  | .anonymous => some []
  | .str p s => do
    let ps ← plainComponents p
    if plainIdent s then some (ps ++ [s]) else none
  | .num .. => none

/-- Whether a module, as its components, lies under one of the `allowed` prefixes, matched
component by component. -/
def moduleAllowed (allowed : List String) (mod : List String) : Bool :=
  allowed.any fun p => (p.splitOn ".").isPrefixOf mod

/-- The import rules over a parsed header: every import names a module whose components are plain
identifiers and that lies under one of `allowedImports`. With `strict` (plugins and models), the
header also has no `module` or `prelude`, and no import is `public`, `meta` or `all`. -/
def importRules (fm : FileMap) (header : Syntax) (allowedImports : List String)
    (strict := true) : Array Violation := Id.run do
  let at_ (stx : Syntax) (msg : String) : Violation :=
    let pos := fm.toPosition (stx.getPos?.getD 0)
    { line := pos.line, col := pos.column + 1, msg }
  let mut vs : Array Violation := #[]
  if strict && !isEmptyNode header[0] then
    vs := vs.push <| at_ header[0] "a `module` header is not allowed"
  if strict && !isEmptyNode header[1] then
    vs := vs.push <| at_ header[1] "`prelude` is not allowed"
  for imp in header[2].getArgs do
    if strict && !(isEmptyNode imp[0] && isEmptyNode imp[1] && isEmptyNode imp[3]) then
      vs := vs.push <| at_ imp "only a plain `import` is allowed, not `public`, `meta` or `all`"
    match imp[4] with
    | .ident _ _ n _ =>
      match plainComponents n with
      | none =>
        vs := vs.push <| at_ imp[4]
          s!"import `{n}` is not allowed: each component of a module name must be a plain identifier"
      | some mod =>
        unless moduleAllowed allowedImports mod do
          vs := vs.push <| at_ imp[4]
            s!"import `{n}` is not allowed; imports must lie under {", ".intercalate allowedImports}"
    | stx => vs := vs.push <| at_ imp s!"import of `{stx}` is not allowed"
  return vs

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
  let mut stoppedAt : Option Syntax := none
  repeat
    let (cmd, st', msgs') := Parser.parseCommand ictx pctx st msgs
    st := st'
    msgs := msgs'
    -- `#exit` is terminal too; keep it, so the rules see it.
    unless cmd.isOfKind ``Parser.Command.eoi do cmds := cmds.push cmd
    if Parser.isTerminalCommand cmd then
      -- Lean stops elaborating at `#exit` too, so nothing after it counts. Any other stop before
      -- the end of the input (today a mid-file `import`) would leave the rest unchecked.
      unless cmd.isOfKind ``Parser.Command.eoi || cmd.isOfKind ``Parser.Command.exit do
        stoppedAt := some cmd
      break
  match msgs.toList.find? (·.severity == .error) with
  | some m =>
    let text ← m.data.toString
    return .error { line := m.pos.line, col := m.pos.column + 1,
                    msg := s!"does not parse with the toolchain's syntax ({text.trimAscii}); plugins may not declare notation" }
  | none =>
    if let some cmd := stoppedAt then
      let pos := ictx.fileMap.toPosition (cmd.getPos?.getD 0)
      let text := ((tokensOf ictx.fileMap cmd #[])[0]?.map (·.text)).getD (toString cmd.getKind)
      return .error { line := pos.line, col := pos.column + 1,
                      msg := s!"Lean's parser stops at `{text}` before the end of the file, so the rest would go unchecked; it is not allowed" }
    return .ok (ictx.fileMap, header, cmds)

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
    "run_cmd", "run_elab", "run_meta", "debug", "Lean",
    -- `include_str` reads a judging-directory file at elaboration time, so an approved model
    -- could pick its `model` and `examples` from a plugin-chosen file (`../comparator.json`,
    -- `../Plugins/<P>.lean`) and admit a dishonest extractor. It is the only `Init`/`Std` term
    -- syntax that reads a file's contents into a term; a plugin never needs it either.
    "include_str" ]

def allowedHashCommands : List String := ["#check", "#print"]

def allowedOptionPrefixes : List String := ["maxHeartbeats", "maxRecDepth", "linter."]

def components (t : String) : List String :=
  (t.splitOn ".").filter (· != "")

/-- The plugin token rules, over the tokens of a parsed source. Imports are `importRules`'. -/
def tokenRules (toks : Array Token) (what := "plugins") : Array Violation := Id.run do
  let mut vs : Array Violation := #[]
  for h : k in [0:toks.size] do
    let t := toks[k]
    let nextTok := toks[k+1]?
    if t.text.startsWith "#" then
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
  match ← parse env src with
  | .error v => return #[v]
  | .ok (fm, header, cmds) =>
    return importRules fm header allowedImports ++ tokenRules (allTokens fm header cmds)

/-! ## Model allowlist

A plugin may use what a model defines, so a model passes every plugin rule (`importRules`,
`tokenRules`). On top,
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
      vs := vs.push <| at_ cmd
        s!"`{head cmd} … section` is not allowed in models; only `section` or `section <name>`, with no `@[expose]`, `public`, `noncomputable` or `meta`"
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
rule too. A model passes `importRules` (imports within `allowedImports`), `tokenRules` and
`commandRules`. -/
def checkModel (env : Environment) (allowedImports : List String) (src : String) :
    IO (Array Violation) := do
  match ← parse env src with
  | .error v => return #[v]
  | .ok (fm, header, cmds) =>
    return importRules fm header allowedImports ++ tokenRules (allTokens fm header cmds) "models" ++
      commandRules fm cmds

end MitosGate.Lint
