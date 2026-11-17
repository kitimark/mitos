import L4YAML.Parser.Composition
import MitosGate.Yaml.View
import Lean.CoreM
import Lean.Util.CollectAxioms
import Lean.Compiler.CSimpAttr
import Lean.Compiler.ImplementedByAttr
import Lean.Compiler.ExternAttr
import Lean.Meta

namespace MitosGate.Yaml

def maxBytes : Nat := 65536
def maxOpeners : Nat := 1024
private def maxStructureChars : Nat := 2048
private def maxLineWork : Nat := 16777216

private def sourceStructureCount (src : String) : Nat :=
  src.toList.countP fun c => c == '-' || c == '?' || c == ':' || c == ',' || c == '[' || c == '{'

private def sourceLineWork (src : String) : Nat :=
  (src.toByteArray.foldl (fun (offset, total) byte =>
    let next := offset + 1
    (next, if byte == 10 then total + next else total)) (0, 0)).2

inductive Refusal where
  | tooLarge (bytes : Nat) | char (line : Nat) (c : Char) | openers (n : Nat)
  | structureChars (n : Nat)
  | lineWork (prefixBytes : Nat)
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
  | .structureChars n => s!": refused: {n} structural characters exceeds {maxStructureChars}"
  | .lineWork n => s!": refused: cumulative line-prefix bytes {n} exceeds {maxLineWork}"
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
  if (src.splitOn "\n").any (·.startsWith "%") then throw .directive
  let structureChars := sourceStructureCount src
  if structureChars > maxStructureChars then throw (.structureChars structureChars)
  let lineWork := sourceLineWork src
  if lineWork > maxLineWork then throw (.lineWork lineWork)
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

private def valueLines : List (L4YAML.Positioned L4YAML.YamlToken) → Bool → List (String × Nat)
  | [], _ => []
  | token :: rest, key => match token.val with
    | .key => valueLines rest true
    | .scalar s _ =>
      if key || s.isEmpty then valueLines rest false
      else (s, token.pos.line + 1) :: valueLines rest false
    | _ => valueLines rest key

def textLines? (src : String) (d : Doc) : Option (List (List Seg × Nat)) := do
  let (tokens, _) ← (L4YAML.Scanner.scanWithComments src).toOption
  let values := valueLines tokens.toList false
  let texts := d.leaves.filterMap fun leaf => match leaf.value with
    | .text s => if s.isEmpty then none else some (leaf.path, s)
    | _ => none
  if values.map Prod.fst == texts.map Prod.snd then
    some (List.zipWith (fun (path, _) (_, line) => (path, line)) texts values)
  else none

private def changedExpressionLine? (src : List Char) :
    List (L4YAML.Positioned L4YAML.YamlToken) → Option Nat
  | [] => none
  | token :: rest =>
    match token.val with
    | .scalar s _ =>
      let stop := rest.head?.map (·.pos.offset) |>.getD src.length
      let raw := (src.drop token.pos.offset).take (stop - token.pos.offset)
      if Base.Text.count exprTok raw != Base.Text.count exprTok s.toList then
        some (token.pos.line + 1)
      else changedExpressionLine? src rest
    | _ => changedExpressionLine? src rest

private def refusalSourceLine? (r : Refusal) (src : String) : Option Nat := do
  match r with
  | .alias _ =>
    let (tokens, _) ← (L4YAML.Scanner.scanWithComments src).toOption
    let token ← tokens.toList.find? fun t => match t.val with
      | .alias _ => true
      | _ => false
    some (token.pos.line + 1)
  | .conserve _ _ =>
    let (tokens, _) ← (L4YAML.Scanner.scanWithComments src).toOption
    changedExpressionLine? src.toList tokens.toList
  | .parse none _ => match L4YAML.Scanner.scanWithComments src with
    | .error (.undefinedAlias _ line _) => some (line + 1)
    | _ => none
  | _ => none

def Refusal.sourceLine? (r : Refusal) (src : String) : Option Nat := refusalSourceLine? r src

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

private theorem read_structure (h : read src = .ok d) :
    sourceStructureCount src ≤ maxStructureChars := by
  by_cases hb : sourceStructureCount src ≤ maxStructureChars
  · exact hb
  · have hover : sourceStructureCount src > maxStructureChars := Nat.lt_of_not_ge hb
    have failure : ∃ e, parseDoc src = .error e := by
      by_cases hd : (src.splitOn "\n").any (·.startsWith "%") = true
      · exact ⟨.directive, by simp [parseDoc, hd, bind, Except.bind, throw, throwThe]; rfl⟩
      · exact ⟨.structureChars (sourceStructureCount src), by
          simp [parseDoc, hd, hover, bind, Except.bind, throw, throwThe]; rfl⟩
    obtain ⟨e, he⟩ := failure
    unfold read at h
    split at h <;> try contradiction
    split at h <;> try contradiction
    dsimp only at h
    split at h <;> try contradiction
    simp [he] at h

private theorem read_lineWork (h : read src = .ok d) :
    sourceLineWork src ≤ maxLineWork := by
  by_cases hb : sourceLineWork src ≤ maxLineWork
  · exact hb
  · have hover : sourceLineWork src > maxLineWork := Nat.lt_of_not_ge hb
    have failure : ∃ e, parseDoc src = .error e := by
      by_cases hd : (src.splitOn "\n").any (·.startsWith "%") = true
      · exact ⟨.directive, by simp [parseDoc, hd, bind, Except.bind, throw, throwThe]; rfl⟩
      · by_cases hs : sourceStructureCount src > maxStructureChars
        · exact ⟨.structureChars (sourceStructureCount src), by
            simp [parseDoc, hd, hs, bind, Except.bind, throw, throwThe]; rfl⟩
        · exact ⟨.lineWork (sourceLineWork src), by
            simp [parseDoc, hd, hs, hover, bind, Except.bind, throw, throwThe]; rfl⟩
    obtain ⟨e, he⟩ := failure
    unfold read at h
    split at h <;> try contradiction
    split at h <;> try contradiction
    dsimp only at h
    split at h <;> try contradiction
    simp [he] at h

private def refusal? (src : String) : Option Refusal :=
  match read src with
  | .ok _ => none
  | .error e => some e

#guard refusal? (String.ofList (List.replicate 65537 'a')) = some (.tooLarge 65537)
#guard refusal? "a: b\r\n" = some (.char 1 '\r')
#guard refusal? (String.ofList (List.replicate 1025 '[')) = some (.openers 1025)
#guard sourceStructureCount "-?:,[{" = 6
#guard sourceStructureCount " abc\n]}'\"#|>!&*%" = 0
#guard sourceStructureCount (String.ofList (List.replicate 2048 '-')) = maxStructureChars
#guard refusal? ("a:\n" ++ String.join (List.replicate 2048 "- ") ++ "x\n") =
  some (.structureChars 2049)
#guard refusal? ("a: \"" ++ String.ofList (List.replicate 2048 ',') ++ "\"\n") =
  some (.structureChars 2049)
#guard refusal? ("%FOO\na: " ++ String.ofList (List.replicate 2048 '-')) = some .directive
#guard (read "a: [\n").isOk = false
#guard refusal? "" = some (.documents 0)
#guard refusal? "a: b\n---\nc: d\n" = some (.documents 2)
#guard refusal? "%YAML 1.2\n---\na: b\n" = some .directive
#guard refusal? "%FOO bar\n---\na: b\n" = some .directive
#guard refusal? "%YAMLX 1.2\n---\na: b\n" = some .directive
#guard refusal? "%TAGX !x! x\n---\na: b\n" = some .directive
#guard refusal? "% ...\n---\na: b\n" = some .directive
#guard refusal? "%MITOS ${{ github.event.pull_request.title }}\n---\nname: demo\non: pull_request_target\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: \"echo \\x24{{ github.event.pull_request.title }}\"\n" = some .directive
#guard refusal? "%FOO #${{ x }}\n---\na: \"\\x24{{ x }}\"\n" = some .directive
#guard refusal? "%FOO ${{ x }}\n%BAR ${{ y }}\n---\na: \"\\x24{{ x }}\"\nb: \"$\\x7b{ y }}\"\n" = some .directive
#guard refusal? "...\n%FOO ${{ x }}\n---\na: \"\\x24{{ x }}\"\n" = some .directive
#guard refusal? "a: \"x\n%FOO\ny\"\n" = some .directive
#guard refusal? "a: 'x\n%FOO\ny'\n" = some .directive
#guard (read "a: \"%FOO in a value\"\n").isOk
#guard (read "a: |\n  %FOO ${{ x }}\n").isOk
#guard (read "a: \"x\n  %FOO\n  y\"\n").isOk
#guard refusal? "a: ['${{ x }}']\n" = some (.flow [.key "a"])
#guard refusal? "a: [[x]]\n" = some (.flow [.key "a"])
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

private def lineFixture : String :=
  "a:\nb: \"\"\nc: [same, same]\nd: {}\njobs:\n  a:\n    steps:\n      - run: \"\\x6eeeds.x\"\n# needs.x\n"

#guard match read lineFixture with
  | .ok d => textLines? lineFixture d == some [
      ([.key "c", .idx 0], 3), ([.key "c", .idx 1], 3),
      ([.key "jobs", .key "a", .key "steps", .idx 0, .key "run"], 8)]
  | _ => false
#guard match read "a: x\n" with
  | .ok d => textLines? "a: y\n" d == none
  | _ => false
#guard (Refusal.parse none "").sourceLine? "run: *answers\n" == some 1
#guard (Refusal.conserve 0 1).sourceLine? "run: \"\\x24{{ x }}\"\n" == some 1

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

private def returnsSort (type : Lean.Expr) : Lean.CoreM Bool :=
  Lean.Meta.MetaM.run' <| Lean.Meta.forallTelescopeReducing type fun _ body => do
    return (← Lean.Meta.whnf body).isSort

open Lean in
#eval show CoreM Unit from do
  let env ← getEnv
  for n in [``read, ``Doc.ofNode, ``read_size, ``read_chars, ``read_conserves, ``read_structure,
      ``read_lineWork] do
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
        let companionName := Compiler.mkUnsafeRecName n
        let companion := env.find? companionName
        let totalCompanion := match Compiler.isUnsafeRecName? n with
          | some original => match env.find? original with
            | some (.defnInfo parent) => parent.safety == .safe
            | _ => false
          | none => false
        let runtimeOverride := companion.any (·.isUnsafe) ||
          ((info matches .opaqueInfo ..) && companion.isSome)
        if info.isUnsafe || (info.isPartial && !totalCompanion) || runtimeOverride || (Compiler.getImplementedBy? env n).isSome ||
            (getExternAttrData? env n).isSome then
          throwError "YAML audit: unsafe or overridden parser dependency {n}"
        if (Compiler.CSimp.ext.getState env).map.find? n |>.isSome then
          throwError "YAML audit: csimp parser dependency {n}"
        if companion.isSome then pending := pending.push companionName
      pending := pending ++ info.type.getUsedConstants
      if let some value := info.value? (allowOpaque := true) then
        pending := pending ++ value.getUsedConstants
  for (n, info) in env.constants.toList do
    if (`MitosGate.Yaml).isPrefixOf n && !isPrivateName n then
      let mut typePending := info.type.getUsedConstants
      let mut typeSeen : NameSet := {}
      let mut typeCursor := 0
      while typeCursor < typePending.size do
        let used := typePending[typeCursor]!
        typeCursor := typeCursor + 1
        unless typeSeen.contains used do
          typeSeen := typeSeen.insert used
          if (`L4YAML).isPrefixOf (privateToUserName used) then
            throwError "YAML audit: exported declaration {n} exposes {used}"
          if let some aliasInfo := env.find? used then
            if ← returnsSort aliasInfo.type then
              typePending := typePending ++ aliasInfo.type.getUsedConstants
              if let some value := aliasInfo.value? (allowOpaque := true) then
                typePending := typePending ++ value.getUsedConstants

end MitosGate.Yaml
