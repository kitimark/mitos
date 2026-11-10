import Lean

namespace MitosGate.Lint
open Lean

structure Token where
  text : String
  line : Nat
  col  : Nat
  deriving Repr

inductive Rule where
  | parse | parseStop | parseHeader
  | importModule | importPrelude | importModifier | importComponent | importRoot | importSyntax
  | hash | setOption | includeStr | banned (token : String)
  | modelCommand | modelSection | modelModifier | modelDeclaration | modelClass | modelAttribute
  | modelComputedFields | modelDeriving
  deriving BEq, Repr

def Rule.id : Rule → String
  | .parse => "parse"
  | .parseStop => "parse:stop"
  | .parseHeader => "parse:header"
  | .importModule => "import:module"
  | .importPrelude => "import:prelude"
  | .importModifier => "import:modifier"
  | .importComponent => "import:component"
  | .importRoot => "import:root"
  | .importSyntax => "import:syntax"
  | .hash => "hash"
  | .setOption => "set_option"
  | .includeStr => "include_str"
  | .banned t => "banned:" ++ t
  | .modelCommand => "model:command"
  | .modelSection => "model:section"
  | .modelModifier => "model:modifier"
  | .modelDeclaration => "model:declaration"
  | .modelClass => "model:class"
  | .modelAttribute => "model:attribute"
  | .modelComputedFields => "model:computed-fields"
  | .modelDeriving => "model:deriving"

def Rule.fixed : List Rule :=
  [ .parse, .parseStop, .parseHeader, .importModule, .importPrelude, .importModifier,
    .importComponent, .importRoot, .importSyntax, .hash, .setOption, .includeStr, .modelCommand,
    .modelSection,
    .modelModifier, .modelDeclaration, .modelClass, .modelAttribute, .modelComputedFields,
    .modelDeriving ]

theorem Rule.banned_or_fixed (r : Rule) : (∃ t, r = .banned t) ∨ r ∈ Rule.fixed := by
  cases r <;> simp [Rule.fixed]

theorem Rule.id_injective : Function.Injective Rule.id := by
  intro a b h
  cases a <;> cases b <;> simp_all [Rule.id] <;>
    (have := congrArg String.toList h; simp [String.toList_append] at this)

def Rule.guardable : Rule → Bool
  | .parse | .parseStop | .parseHeader => false
  | _ => true

structure Violation where
  line : Nat
  col  : Nat
  rule : Rule
  msg  : String

def Violation.render (file : String) (v : Violation) : String :=
  s!"{file}:{v.line}:{v.col}: {v.msg} [{v.rule.id}]"

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

def headerSyntax (src : String) : IO (Except Violation (FileMap × Syntax)) := do
  let ictx := Parser.mkInputContext src "<source>"
  let (header, _, msgs) ← Parser.parseHeader ictx
  match msgs.toList.find? (·.severity == .error) with
  | some m =>
    let text ← m.data.toString
    return .error { line := m.pos.line, col := m.pos.column + 1, rule := .parseHeader,
                    msg := s!"the header does not parse ({text.trimAscii}), so its imports cannot be checked" }
  | none => return .ok (ictx.fileMap, header)

def isEmptyNode (stx : Syntax) : Bool :=
  stx.isMissing || (stx.isOfKind nullKind && stx.getNumArgs == 0)

def plainIdent (s : String) : Bool :=
  match s.toList with
  | c :: cs => isIdFirst c && cs.all isIdRest
  | [] => false

def plainComponents : Name → Option (List String)
  | .anonymous => some []
  | .str p s => do
    let ps ← plainComponents p
    if plainIdent s then some (ps ++ [s]) else none
  | .num .. => none

def moduleAllowed (allowed : List String) (mod : List String) : Bool :=
  allowed.any fun p => (p.splitOn ".").isPrefixOf mod

def importRules (fm : FileMap) (header : Syntax) (allowedImports : List String)
    (strict := true) : Array Violation := Id.run do
  let at_ (stx : Syntax) (rule : Rule) (msg : String) : Violation :=
    let pos := fm.toPosition (stx.getPos?.getD 0)
    { line := pos.line, col := pos.column + 1, rule, msg }
  let mut vs : Array Violation := #[]
  if strict && !isEmptyNode header[0] then
    vs := vs.push <| at_ header[0] .importModule "a `module` header is not allowed"
  if strict && !isEmptyNode header[1] then
    vs := vs.push <| at_ header[1] .importPrelude "`prelude` is not allowed"
  for imp in header[2].getArgs do
    if strict && !(isEmptyNode imp[0] && isEmptyNode imp[1] && isEmptyNode imp[3]) then
      vs := vs.push <| at_ imp .importModifier
        "only a plain `import` is allowed, not `public`, `meta` or `all`"
    match imp[4] with
    | .ident _ _ n _ =>
      match plainComponents n with
      | none =>
        vs := vs.push <| at_ imp[4] .importComponent
          s!"import `{n}` is not allowed: each component of a module name must be a plain identifier"
      | some mod =>
        unless moduleAllowed allowedImports mod do
          vs := vs.push <| at_ imp[4] .importRoot
            s!"import `{n}` is not allowed; imports must lie under {", ".intercalate allowedImports}"
    | stx => vs := vs.push <| at_ imp .importSyntax s!"import of `{stx}` is not allowed"
  return vs

def keepHashExitDropEoi (cmd : Syntax) : Bool :=
  !cmd.isOfKind ``Parser.Command.eoi

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
    if keepHashExitDropEoi cmd then cmds := cmds.push cmd
    if Parser.isTerminalCommand cmd then
      unless cmd.isOfKind ``Parser.Command.eoi || cmd.isOfKind ``Parser.Command.exit do
        stoppedAt := some cmd
      break
  match msgs.toList.find? (·.severity == .error) with
  | some m =>
    let text ← m.data.toString
    return .error { line := m.pos.line, col := m.pos.column + 1, rule := .parse,
                    msg := s!"does not parse with the toolchain's syntax ({text.trimAscii}); plugins may not declare notation" }
  | none =>
    if let some cmd := stoppedAt then
      let pos := ictx.fileMap.toPosition (cmd.getPos?.getD 0)
      let text := ((tokensOf ictx.fileMap cmd #[])[0]?.map (·.text)).getD (toString cmd.getKind)
      return .error { line := pos.line, col := pos.column + 1, rule := .parseStop,
                      msg := s!"Lean's parser stops at `{text}` before the end of the file, so the rest would go unchecked; it is not allowed" }
    return .ok (ictx.fileMap, header, cmds)

private def allTokens (fm : FileMap) (header : Syntax) (cmds : Array Syntax) : Array Token :=
  cmds.foldl (fun a c => tokensOf fm c a) (tokensOf fm header #[])

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

def tokenRules (toks : Array Token) (what := "plugins") : Array Violation := Id.run do
  let mut vs : Array Violation := #[]
  for h : k in [0:toks.size] do
    let t := toks[k]
    let nextTok := toks[k+1]?
    if t.text.startsWith "#" then
      unless allowedHashCommands.contains t.text do
        vs := vs.push { line := t.line, col := t.col, rule := .hash,
                        msg := s!"command `{t.text}` is not allowed" }
    else if t.text == "set_option" then
      let ok := match nextTok with
        | some o => allowedOptionPrefixes.any (o.text.startsWith ·)
        | none => false
      unless ok do
        vs := vs.push { line := t.line, col := t.col, rule := .setOption,
                        msg := s!"`set_option {(nextTok.map (·.text)).getD ""}` is not allowed" }
    else
      for c in components t.text do
        if c == "include_str" then
          vs := vs.push { line := t.line, col := t.col, rule := .includeStr,
                          msg := s!"`include_str` is not allowed in {what}" }
        else if banned.contains c then
          vs := vs.push { line := t.line, col := t.col, rule := .banned c,
                          msg := s!"`{c}` is not allowed in {what}" }
  return vs

def check (env : Environment) (allowedImports : List String) (src : String) :
    IO (Array Violation) := do
  match ← parse env src with
  | .error v => return #[v]
  | .ok (fm, header, cmds) =>
    return importRules fm header allowedImports ++ tokenRules (allTokens fm header cmds)

private def kindName (k : SyntaxNodeKind) : String :=
  match k with
  | .str _ s => s
  | _ => k.toString

private def listed (ks : List SyntaxNodeKind) : String :=
  ", ".intercalate (ks.map kindName)

private def at_ (fm : FileMap) (stx : Syntax) (rule : Rule) (msg : String) : Violation :=
  let pos := fm.toPosition (stx.getPos?.getD 0)
  { line := pos.line, col := pos.column + 1, rule, msg }

private def headText (fm : FileMap) (stx : Syntax) : String :=
  ((tokensOf fm stx #[])[0]?.map (·.text)).getD "?"

private def byKind? {α : Type} (all : List α) (kind : α → SyntaxNodeKind) (k : SyntaxNodeKind) :
    Option α :=
  all.find? fun a => kind a == k

private theorem byKind?_none_of_ne {α : Type} (all : List α) (kind : α → SyntaxNodeKind)
    (k : SyntaxNodeKind) (h : ∀ a, kind a ≠ k) : byKind? all kind k = none := by
  rw [byKind?, List.find?_eq_none]
  intro a _
  rw [Bool.not_eq_true, beq_eq_false_iff_ne]
  exact h a

private inductive ModelDeclaration
  | definition | «theorem» | «abbrev» | «example» | «structure» | «inductive»
  deriving DecidableEq

private def ModelDeclaration.kind : ModelDeclaration → SyntaxNodeKind
  | .definition => ``Parser.Command.definition
  | .«theorem» => ``Parser.Command.theorem
  | .«abbrev» => ``Parser.Command.abbrev
  | .«example» => ``Parser.Command.example
  | .«structure» => ``Parser.Command.structure
  | .«inductive» => ``Parser.Command.inductive

private def ModelDeclaration.all : List ModelDeclaration :=
  [.definition, .«theorem», .«abbrev», .«example», .«structure», .«inductive»]

private theorem ModelDeclaration.byKind_kind (d : ModelDeclaration) :
    byKind? ModelDeclaration.all ModelDeclaration.kind d.kind = some d := by
  cases d <;> rfl

/-- Lean parses `class` with `«structure»`'s `structureTk <|> classTk`, so `class` has no syntax
kind of its own. -/
private def ModelDeclaration.admit (fm : FileMap) : ModelDeclaration → Syntax → Array Violation
  | .definition, _ => #[]
  | .«theorem», _ => #[]
  | .«abbrev», _ => #[]
  | .«example», _ => #[]
  | .«structure», decl =>
    if decl[0].getKind == ``Parser.Command.structureTk then #[]
    else #[at_ fm decl .modelClass s!"declaration `{headText fm decl}` is not allowed in models"]
  | .«inductive», _ => #[]

private inductive ModelCommand
  | moduleDoc | «namespace» | «section» | «end» | «open» | declaration
  deriving DecidableEq

private def ModelCommand.kind : ModelCommand → SyntaxNodeKind
  | .moduleDoc => ``Parser.Command.moduleDoc
  | .«namespace» => ``Parser.Command.namespace
  | .«section» => ``Parser.Command.section
  | .«end» => ``Parser.Command.end
  | .«open» => ``Parser.Command.open
  | .declaration => ``Parser.Command.declaration

private def ModelCommand.all : List ModelCommand :=
  [.moduleDoc, .«namespace», .«section», .«end», .«open», .declaration]

private theorem ModelCommand.byKind_kind (c : ModelCommand) :
    byKind? ModelCommand.all ModelCommand.kind c.kind = some c := by
  cases c <;> rfl

private def declarationKinds : String := listed (ModelDeclaration.all.map ModelDeclaration.kind)

private def ModelCommand.admit (fm : FileMap) : ModelCommand → Syntax → Array Violation
  | .moduleDoc, _ => #[]
  | .«namespace», _ => #[]
  | .«section», cmd =>
    if cmd[0].getArgs.all isEmptyNode then #[]
    else #[at_ fm cmd .modelSection
      s!"`{headText fm cmd} … section` is not allowed in models; only `section` or `section <name>`, with no `@[expose]`, `public`, `noncomputable` or `meta`"]
  | .«end», _ => #[]
  | .«open», _ => #[]
  | .declaration, cmd =>
    let mods := cmd[0]
    let decl := cmd[1]
    let vs :=
      if (mods.getArgs.extract 2 mods.getNumArgs).all isEmptyNode then #[]
      else #[at_ fm cmd .modelModifier
        "declaration modifiers other than a doc comment and attributes are not allowed in models"]
    match byKind? ModelDeclaration.all ModelDeclaration.kind decl.getKind with
    | none =>
      vs.push <| at_ fm decl .modelDeclaration
        s!"declaration `{headText fm decl}` ({kindName decl.getKind}) is not allowed in models; they may declare only {declarationKinds}"
    | some d => vs ++ ModelDeclaration.admit fm d decl

private inductive ModelAttribute
  | simp
  deriving DecidableEq

private def ModelAttribute.kind : ModelAttribute → SyntaxNodeKind
  | .simp => ``Parser.Attr.simp

private def ModelAttribute.all : List ModelAttribute := [.simp]

private theorem ModelAttribute.byKind_kind (a : ModelAttribute) :
    byKind? ModelAttribute.all ModelAttribute.kind a.kind = some a := by
  cases a <;> rfl

/-- `Parser.Attr.simple` is the kind of `implemented_by`, `inline`, `csimp` and the rest. An arm
copied from `simp` onto one of those names has this kind, and this theorem rejects it. -/
private theorem ModelAttribute.kind_ne_simple (a : ModelAttribute) :
    a.kind ≠ ``Parser.Attr.simple := by
  cases a <;> decide

private def ModelAttribute.admit (k : SyntaxNodeKind) : ModelAttribute → Bool
  | .simp => k == ModelAttribute.kind .simp

private def commandKinds : String := listed (ModelCommand.all.map ModelCommand.kind)

private def attributeKinds : String := listed (ModelAttribute.all.map ModelAttribute.kind)

private def rejectCommand (fm : FileMap) (cmd : Syntax) : Array Violation :=
  let k := cmd.getKind
  #[at_ fm cmd .modelCommand
    s!"command `{headText fm cmd}` ({kindName k}) is not allowed in models; they may contain only {commandKinds}"]

private def topRules (fm : FileMap) (cmd : Syntax) : Array Violation :=
  match byKind? ModelCommand.all ModelCommand.kind cmd.getKind with
  | none => rejectCommand fm cmd
  | some c => ModelCommand.admit fm c cmd

private theorem topRules_other (fm : FileMap) (cmd : Syntax)
    (h : ∀ c : ModelCommand, c.kind ≠ cmd.getKind) :
    (topRules fm cmd).map (·.rule) = #[.modelCommand] := by
  have hnone := byKind?_none_of_ne ModelCommand.all ModelCommand.kind cmd.getKind h
  simp only [topRules, hnone, rejectCommand, Array.map_singleton]
  rfl

private partial def nestedRules (fm : FileMap) (stx : Syntax) (vs : Array Violation) :
    Array Violation :=
  match stx with
  | .node _ k args =>
    let vs :=
      if k == ``Parser.Term.attrInstance &&
          !ModelAttribute.all.any (ModelAttribute.admit stx[1].getKind) then
        vs.push <| at_ fm stx[1] .modelAttribute
          s!"attribute `{headText fm stx[1]}` is not allowed in models; they may use only {attributeKinds}"
      else if k == ``Parser.Command.computedFields then
        vs.push <| at_ fm stx .modelComputedFields
          "computed fields (`with`) are not allowed in models"
      else vs
    args.foldl (fun a s => nestedRules fm s a) vs
  | .atom _ "deriving" => vs.push <| at_ fm stx .modelDeriving "`deriving` is not allowed in models"
  | _ => vs

private partial def commandRules (fm : FileMap) (cmds : Array Syntax) : Array Violation := Id.run do
  let mut vs : Array Violation := #[]
  for cmd in cmds do
    for v in topRules fm cmd do
      vs := vs.push v
  return cmds.foldl (fun a c => nestedRules fm c a) vs

def checkModel (env : Environment) (allowedImports : List String) (src : String) :
    IO (Array Violation) := do
  match ← parse env src with
  | .error v => return #[v]
  | .ok (fm, header, cmds) =>
    return importRules fm header allowedImports ++ tokenRules (allTokens fm header cmds) "models" ++
      commandRules fm cmds

end MitosGate.Lint
