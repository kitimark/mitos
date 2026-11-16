import L4YAML.Parser.Composition
import MitosGate.Yaml.View
import Lean.CoreM
import Lean.Util.CollectAxioms
import Lean.Compiler.CSimpAttr
import Lean.Compiler.ImplementedByAttr
import Lean.Compiler.ExternAttr

namespace MitosGate.Yaml

def maxBytes : Nat := 65536
def maxOpeners : Nat := 1024

inductive Refusal where
  | tooLarge (bytes : Nat) | char (line : Nat) (c : Char) | openers (n : Nat)
  | parse (line : Option Nat) (what : String)
  | documents (n : Nat) | directive | rootNotMapping | blockIndicator (line : Nat)
  | anchor (path : List Seg) | alias (path : List Seg) | tag (path : List Seg)
  | complexKey (path : List Seg) | keyStyle (path : List Seg) | flow (path : List Seg)
  | view (path : List Seg) (p : Problem)
  | exprInComment (line : Nat) | conserve (inText inLeaves : Nat)
  deriving DecidableEq, Repr

private def pathText (path : List Seg) : String :=
  if path.isEmpty then "<root>" else
    path.foldl (fun s seg => match seg with
      | .key k => if s.isEmpty then k else s ++ "." ++ k
      | .idx i => s ++ s!"[{i}]") ""

private def hex (c : Char) : String :=
  let digits := (Nat.toDigits 16 c.toNat).map Char.toUpper
  String.ofList (List.replicate (4 - digits.length) '0' ++ digits)

private def problemText : Problem → String
  | .duplicateKey k => s!"duplicate key {k} (ignoring ASCII case)"
  | .exprKey => "${{ in a key"
  | .mergeKey => "merge key"
  | .emptyKey => "empty key"
  | .char c => s!"decoded character U+{hex c} outside LF and printable ASCII"

def Refusal.render : Refusal → String
  | .tooLarge n => s!": refused: {n} bytes exceeds {maxBytes}"
  | .char line c => s!":{line}: refused: character U+{hex c} outside LF and printable ASCII"
  | .openers n => s!": refused: {n} opening brackets exceeds {maxOpeners}"
  | .parse line what => (line.map (fun n => s!":{n}") |>.getD "") ++ ": refused: parse: " ++ what
  | .documents n => s!": refused: expected one document, found {n}"
  | .directive => ": refused: directive"
  | .rootNotMapping => ": refused: root is not a mapping"
  | .blockIndicator n => s!":{n}: refused: block indentation indicator"
  | .anchor path => s!": refused at {pathText path}: anchor"
  | .alias path => s!": refused at {pathText path}: alias"
  | .tag path => s!": refused at {pathText path}: tag"
  | .complexKey path => s!": refused at {pathText path}: complex or explicit key"
  | .keyStyle path => s!": refused at {pathText path}: non-plain key"
  | .flow path => s!": refused at {pathText path}: unsupported flow collection"
  | .view path p => s!": refused at {pathText path}: {problemText p}"
  | .exprInComment n => s!":{n}: refused: " ++ "${{ in a comment"
  | .conserve a b => s!": refused: expression count differs (text {a}, leaves {b})"

private def properties (path : List Seg) (anchor tag : Option String) : Except Refusal Unit :=
  if anchor.isSome then .error (.anchor path)
  else if tag.isSome then .error (.tag path) else .ok ()

private def flowScalar : L4YAML.YamlValue → Bool
  | .scalar s => !Base.Text.hasSub exprTok s.content.toList &&
      !(s.style == .plain && (s.content.contains '?' || s.content.startsWith ":"))
  | _ => false

private def ofL4 (path : List Seg) (v : L4YAML.YamlValue) : Except Refusal Node := do
  match v with
  | .alias _ => throw (.alias path)
  | .scalar s =>
    properties path s.anchor s.tag
    return .text s.content
  | .sequence style items tag anchor =>
    properties path anchor tag
    if style == .flow && !items.all flowScalar then throw (.flow path)
    return .seq (← ofItems path 0 items.toList)
  | .mapping style pairs tag anchor =>
    properties path anchor tag
    if style == .flow && !pairs.isEmpty then throw (.flow path)
    return .map (← ofPairs path pairs.toList)
where
  ofItems (path : List Seg) (i : Nat) : List L4YAML.YamlValue → Except Refusal (List Node)
    | [] => .ok []
    | v :: vs => do
      let n ← ofL4 (path ++ [.idx i]) v
      return n :: (← ofItems path (i + 1) vs)
  ofPairs (path : List Seg) : List (L4YAML.YamlValue × L4YAML.YamlValue) →
      Except Refusal (List (String × Node))
    | [] => .ok []
    | (k, v) :: es => do
      let .scalar s := k | throw (.complexKey path)
      let kp := path ++ [.key s.content]
      properties kp s.anchor s.tag
      if s.style != .plain then throw (.keyStyle kp)
      let n ← ofL4 kp v
      return (s.content, n) :: (← ofPairs path es)

private def firstCharProblem : List Char → Nat → Option Refusal
  | [], _ => none
  | c :: cs, line =>
    if !allowedChar c then some (.char line c)
    else firstCharProblem cs (if c == '\n' then line + 1 else line)

private def qualify (src : String) (tokens : Array (L4YAML.Positioned L4YAML.YamlToken)) :
    Except Refusal Unit := do
  let chars := src.toList
  for t in tokens do
    match t.val with
    | .key =>
      if chars[t.pos.offset]? == some '?' &&
          (chars[t.pos.offset + 1]?.isNone ||
            chars[t.pos.offset + 1]? == some ' ' ||
            chars[t.pos.offset + 1]? == some '\n') then throw (.complexKey [])
    | .scalar value style =>
      if style == .literal || style == .folded then
        let header := chars.drop t.pos.offset |>.takeWhile (fun c => c != '\n' && c != '#')
        if header.any (fun c => '1' ≤ c && c ≤ '9') then throw (.blockIndicator (t.pos.line + 1))
        let marks := header.filter fun c => c == '+' || c == '-'
        if marks.length > 1 then throw (.parse (some (t.pos.line + 1)) "repeated block chomping indicator")
        if value.toList.all (· == '\n') then
          throw (.parse (some (t.pos.line + 1)) "empty block scalar is not supported at this parser pin")
    | _ => pure ()

private def parseDoc (src : String) : Except Refusal Doc := do
  let (tokens, comments) ← (L4YAML.Scanner.scanWithComments src).mapError
    (fun e => .parse none e.toString)
  let docs ← (L4YAML.TokenParser.parseStream tokens).mapError (fun e => .parse none e.toString)
  if docs.size != 1 then throw (.documents docs.size)
  let doc := docs[0]!
  if !doc.directives.isEmpty then throw .directive
  let .mapping .. := doc.value | throw .rootNotMapping
  qualify src tokens
  let n ← ofL4 [] doc.value
  let d ← (Doc.ofNode n).mapError fun (path, p) => .view path p
  for (pos, comment) in comments do
    if Base.Text.hasSub exprTok comment.toList then throw (.exprInComment (pos.line + 1))
  return d

def read (src : String) : Except Refusal Doc :=
  if src.utf8ByteSize > maxBytes then .error (.tooLarge src.utf8ByteSize)
  else if src.toList.all allowedChar = false then
    .error ((firstCharProblem src.toList 1).getD (.char 1 '\x00'))
  else
    let openers := src.toList.countP fun c => c == '[' || c == '{'
    if openers > maxOpeners then .error (.openers openers)
    else match parseDoc src with
      | .error e => .error e
      | .ok d =>
        let a := Base.Text.count exprTok src.toList
        let b := (d.leaves.map Leaf.exprCount).sum
        if a = b then .ok d else .error (.conserve a b)

theorem read_size (h : read src = .ok d) : src.utf8ByteSize ≤ maxBytes := by
  unfold read at h
  split at h <;> simp_all

theorem read_chars (h : read src = .ok d) : ∀ c ∈ src.toList, allowedChar c = true := by
  unfold read at h
  split at h <;> try contradiction
  split at h <;> try contradiction
  rename_i hc
  exact List.all_eq_true.mp (by simpa using hc)

theorem read_conserves (h : read src = .ok d) :
    Base.Text.count exprTok src.toList = (d.leaves.map Leaf.exprCount).sum := by
  unfold read at h
  split at h <;> try contradiction
  split at h <;> try contradiction
  dsimp only at h
  split at h <;> try contradiction
  split at h <;> try contradiction
  split at h <;> simp_all

private def refusal? (src : String) : Option Refusal :=
  match read src with
  | .ok _ => none
  | .error e => some e

#guard refusal? (String.ofList (List.replicate 65537 'a')) = some (.tooLarge 65537)
#guard refusal? "a: b\r\n" = some (.char 1 '\r')
#guard refusal? (String.ofList (List.replicate 1025 '[')) = some (.openers 1025)
#guard (read "a: [\n").isOk = false
#guard refusal? "" = some (.documents 0)
#guard refusal? "a: b\n---\nc: d\n" = some (.documents 2)
#guard refusal? "%YAML 1.2\n---\na: b\n" = some .directive
#guard refusal? "- a\n" = some .rootNotMapping
#guard refusal? "a: |1\n  x\n" = some (.blockIndicator 1)
#guard refusal? "a: &x b\n" = some (.anchor [.key "a"])
#guard (ofL4 [] (.alias "x")).isOk = false
#guard refusal? "a: ! value\n" = some (.tag [.key "a"])
#guard refusal? "? a\n?\n: b\n" = some (.complexKey [])
#guard refusal? "'a': b\n" = some (.keyStyle [.key "a"])
#guard refusal? "a: {b: c}\n" = some (.flow [.key "a"])
#guard refusal? "a: b\nA: c\n" = some (.view [.key "a"] (.duplicateKey "a"))
#guard refusal? "a: b # ${{ x }}\n" = some (.exprInComment 1)
#guard refusal? "a: \"\\x24{{ x }}\"\n" = some (.conserve 0 1)
#guard refusal? "<<: x\n" = some (.view [.key "<<"] .mergeKey)
#guard refusal? ": x\n" = some (.view [.key ""] .emptyKey)
#guard refusal? "a${{ x }}: b\n" = some (.view [.key "a${{ x }}"] .exprKey)
#guard refusal? "---\na: 1 # keep\n---\nb: 2\n" = some (.documents 2)
#guard refusal? "---\na\n# keep\n---\nb\n" = some (.documents 2)
#guard (read "a: !foo.bar value\n").isOk = false
#guard (read "a: [b, c]\nempty: {}\nseq: []\n").isOk
#guard (read "?a: b\n").isOk
#guard (read "a: \"${{ \\x6eeeds.a.outputs.x }}\"\n").isOk
#guard (read "a: |+\n  x\nb: >-\n  y\n  z\n").isOk
#guard (read "a: \"one\n  two\"\nb: 'three\n  four'\n").isOk
#guard (read "a: >+\n\n").isOk = false
#guard (read "a: |\n\n").isOk = false
#guard (read "a: |++\n  x\n").isOk = false
#guard (read "a: |22\n  x\n").isOk = false
#guard (read "a: >+\n  \n#${{ e }}\n").isOk = false
#guard (read "a: b: |\n").isOk = false
#guard (read "- a: - |\n").isOk = false
#guard (read "- a: 1\n  b: |\n  x #${{ e }}\n").isOk = false

#guard ["n", "\"", "/", "\\", " ", "x41", "u0041", "U00000041"].all fun escape =>
  (read ("a: \"\\" ++ escape ++ "\"\n")).isOk
#guard ["0", "a", "b", "t", "v", "f", "r", "e", "N", "_", "L", "P"].all fun escape =>
  match refusal? ("a: \"\\" ++ escape ++ "\"\n") with
  | some (.view [.key "a"] (.char _)) => true
  | _ => false
#guard ["[?x]", "[:x]", "[x?y]"].all fun value =>
  refusal? ("a: " ++ value ++ "\n") == some (.flow [.key "a"])
#guard match L4YAML.TokenParser.parseYamlRaw "a: &x b\nc: *x\n" with
  | .ok docs => match docs.toList with
    | [doc] => match doc.value with
      | .mapping _ pairs _ _ => match pairs.toList with
        | [(_, .scalar s), (_, .alias "x")] => s.anchor == some "x"
        | _ => false
      | _ => false
    | _ => false
  | _ => false

private def pipelineAgrees (src : String) : Bool :=
  let viaComments := (L4YAML.Scanner.scanWithComments src).bind fun (ts, _) =>
    L4YAML.TokenParser.parseStream ts
  match viaComments, L4YAML.TokenParser.parseYamlRaw src with
  | .ok a, .ok b => a == b
  | .error a, .error b => a == b
  | _, _ => false

#guard pipelineAgrees "a: \"${{ \\x6eeeds.x }}\" # retained\nb: [x, y]\n"
#guard pipelineAgrees "a: |+\n  x\n# tail\nb: {}\n"

open Lean in
#eval show CoreM Unit from do
  let env ← getEnv
  for n in [``read, ``Doc.ofNode, ``read_size, ``read_chars, ``read_conserves] do
    for a in ← collectAxioms n do
      unless [``propext, ``Classical.choice, ``Quot.sound].contains a do
        throwError "YAML audit: {n} depends on axiom {a}"
  let mut pending := #[``read]
  let mut seen : NameSet := {}
  let mut cursor := 0
  while cursor < pending.size do
    let n := pending[cursor]!
    cursor := cursor + 1
    unless seen.contains n do
      seen := seen.insert n
      let some info := env.find? n | throwError "YAML audit: unknown declaration {n}"
      if (`L4YAML).isPrefixOf (privateToUserName n) then
        if info.isUnsafe || info.isPartial || (Compiler.getImplementedBy? env n).isSome ||
            (getExternAttrData? env n).isSome then
          throwError "YAML audit: unsafe or overridden parser dependency {n}"
        if (Compiler.CSimp.ext.getState env).map.find? n |>.isSome then
          throwError "YAML audit: csimp parser dependency {n}"
      pending := pending ++ info.type.getUsedConstants
      if let some value := info.value? (allowOpaque := true) then
        pending := pending ++ value.getUsedConstants
  for (n, info) in env.constants.toList do
    if (`MitosGate.Yaml).isPrefixOf n && !isPrivateName n then
      for used in info.type.getUsedConstants do
        if (`L4YAML).isPrefixOf (privateToUserName used) then
          throwError "YAML audit: exported declaration {n} exposes {used}"

end MitosGate.Yaml
