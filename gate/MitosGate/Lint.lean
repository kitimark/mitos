/-!
# Gate 1: source lint

A conservative token scan of plugin source. It runs *before* the sandboxed build and blocks the
constructs that kernel checking cannot see (`implemented_by`, `extern`, `csimp` change what runs,
not what is proved) and the ones that let elaboration run code (`#eval`, `macro`, `elab`, …).

It is defence in depth: `lake comparator` independently rejects `sorry`, foreign axioms and
statement edits. The cheat corpus (`eval/cheats/`) records which layer catches each cheat.
-/

namespace MitosGate.Lint

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

private def isIdStart (c : Char) : Bool :=
  c.isAlpha || c == '_' || c == '«' || c == '#' || c.toNat > 127

private def isIdChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '.' || c == '\'' || c == '!' || c == '?' ||
  c == '«' || c == '»' || (c.toNat > 127 && c != '»' && c != '«' && !c.isWhitespace)

/-- Split source into identifier-like tokens, skipping comments and string/char literals.
Guillemets are removed, so `«sorry»` is seen as `sorry`. -/
def tokenize (src : String) : Array Token := Id.run do
  let cs := src.toList.toArray
  let n := cs.size
  let mut i := 0
  let mut line := 1
  let mut col := 1
  let mut depth := 0
  let mut out : Array Token := #[]
  -- Every iteration consumes at least one character, so `n + 1` iterations suffice.
  for _ in [0:n+1] do
    if i ≥ n then break
    let c := cs[i]!
    let next := if i + 1 < n then cs[i+1]! else ' '
    if depth > 0 then
      if c == '/' && next == '-' then depth := depth + 1; i := i + 2; col := col + 2
      else if c == '-' && next == '/' then depth := depth - 1; i := i + 2; col := col + 2
      else
        if c == '\n' then line := line + 1; col := 1 else col := col + 1
        i := i + 1
    else if c == '/' && next == '-' then
      depth := 1; i := i + 2; col := col + 2
    else if c == '-' && next == '-' then
      while i < n && cs[i]! != '\n' do i := i + 1
    else if c == '"' then
      i := i + 1; col := col + 1
      while i < n && cs[i]! != '"' do
        if cs[i]! == '\\' then i := i + 2; col := col + 2
        else
          if cs[i]! == '\n' then line := line + 1; col := 1 else col := col + 1
          i := i + 1
      i := i + 1; col := col + 1
    else if isIdStart c then
      let start := i
      let startCol := col
      i := i + 1; col := col + 1
      while i < n && isIdChar cs[i]! do i := i + 1; col := col + 1
      let raw := String.ofList (cs.extract start i).toList
      let text := String.ofList (raw.toList.filter (fun ch => ch != '«' && ch != '»'))
      out := out.push { text, line, col := startCol }
    else
      if c == '\n' then line := line + 1; col := 1 else col := col + 1
      i := i + 1
  return out

/-- Identifiers and keywords a plugin may not use anywhere (checked per dotted component). -/
def banned : List String :=
  [ "sorry", "admit", "axiom", "unsafe", "partial", "opaque", "noncomputable",
    "implemented_by", "extern", "export", "csimp", "init", "builtin_init", "never_extract",
    "native_decide", "native", "ofReduceBool", "reduceBool", "trustCompiler",
    "notation", "infix", "infixl", "infixr", "prefix", "postfix",
    "macro", "macro_rules", "syntax", "elab", "elab_rules", "declare_syntax_cat",
    "instance", "scoped", "meta", "initialize", "builtin_initialize",
    "run_cmd", "run_elab", "run_meta", "debug", "Lean" ]

/-- `#` commands a plugin may use; all others (notably `#eval`) are rejected. -/
def allowedHashCommands : List String := ["#check", "#print"]

/-- Options a plugin may set; everything else (notably `debug.*`) is rejected. -/
def allowedOptionPrefixes : List String := ["maxHeartbeats", "maxRecDepth", "linter."]

def components (t : String) : List String :=
  (t.splitOn ".").filter (· != "")

/-- Is `mod` allowed by one of the prefixes? `"Models"` allows `Models` and `Models.X`. -/
def moduleAllowed (allowed : List String) (mod : String) : Bool :=
  allowed.any fun p => mod == p || mod.startsWith (p ++ ".")

/-- Check a plugin's source. `allowedImports` lists module prefixes it may import. -/
def check (allowedImports : List String) (src : String) : Array Violation := Id.run do
  let toks := tokenize src
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
