import Mitos.Core
import Mitos.Impl.Resolve
import Plugins.ToyRequire

namespace Score

open Mitos

def scopeName : Scope → String
  | .runtime => "runtime"
  | .dev => "dev"
  | .test => "test"
  | .build => "build"

def parseScope : String → Option Scope
  | "runtime" => some .runtime
  | "dev" => some .dev
  | "test" => some .test
  | "build" => some .build
  | _ => none

def statusName : Status → String
  | .confirmed => "confirmed"
  | .inferred => "inferred"

structure SourceFile where
  repo : String
  path : String
  text : String

def provideChars : List Char := "provide ".toList

def declared (src : String) : List Fact :=
  (lines src.toList).filterMap fun (o, l) =>
    if provideChars.isPrefixOf l then
      let name := l.drop provideChars.length
      some { kind := .provides, ident := { kind := "toy", key := String.ofList name },
             span := { start := o + utf8Len provideChars, len := utf8Len name } }
    else none

def factsOf (f : SourceFile) : List (Fact × Assumption) :=
  let fromPlugin := (ToyRequire.extractor.run f.text).map (·, .extractor "ToyRequire")
  let fromDecl :=
    if f.path == "PROVIDES" then
      (declared f.text).map (·, .humanDeclaredOutsideSource s!"{f.repo}/PROVIDES")
    else []
  fromPlugin ++ fromDecl

def ingest (files : List SourceFile) : Except String (List Located) := do
  let mut out : Array Located := #[]
  for f in files do
    for (fact, origin) in factsOf f do
      unless fact.span.text f.text.toList == some fact.ident.key.toList do
        throw s!"{f.repo}/{f.path}: fact {repr fact.ident.key} is not anchored at {repr fact.span}"
      out := out.push { id := out.size, repo := f.repo, rev := "fixture", path := f.path, fact, origin }
  return out.toList

structure RepoEdge where
  src   : String
  dst   : String
  kind  : String
  key   : String
  scope : Scope
  deriving DecidableEq

def RepoEdge.ofEdge (e : Edge) : RepoEdge :=
  { src := e.requiringRepo, dst := e.providingRepo, kind := e.ident.kind, key := e.ident.key,
    scope := e.scope }

def RepoEdge.type (e : RepoEdge) : String := s!"{e.kind}/{scopeName e.scope}"

def RepoEdge.render (e : RepoEdge) : String :=
  s!"`{e.src}` → `{e.dst}` ({e.type} `{e.key}`)"

def parseLabels (txt : String) : Except String (List RepoEdge) := do
  let mut out := #[]
  let mut n := 0
  for l in txt.splitOn "\n" do
    n := n + 1
    if l.isEmpty || l.startsWith "#" then continue
    match l.splitOn "\t" with
    | [src, dst, kind, key, sc] =>
      let some scope := parseScope sc | throw s!"labels.tsv:{n}: unknown scope {repr sc}"
      let e : RepoEdge := { src, dst, kind, key, scope }
      if out.contains e then throw s!"labels.tsv:{n}: duplicate label"
      out := out.push e
    | fs => throw s!"labels.tsv:{n}: expected 5 tab-separated fields, found {fs.length}"
  return out.toList

def collapse (es : List Edge) : List (RepoEdge × Status) :=
  es.foldl (init := []) fun acc e =>
    let r := RepoEdge.ofEdge e
    if acc.any (·.1 == r) then
      acc.map fun (r', s) => (r', if r' == r && e.status == .inferred then .inferred else s)
    else acc ++ [(r, e.status)]

def ratio (n d : Nat) : String :=
  if d = 0 then "n/a" else
    let x := (n * 100 + d / 2) / d
    let frac := toString (x % 100)
    s!"{x / 100}.{if frac.length < 2 then "0" ++ frac else frac} ({n}/{d})"

structure Scorecard where
  facts      : List Located
  predicted  : List (RepoEdge × Status)
  labels     : List RepoEdge
  unresolved : List Located

def score (files : List SourceFile) (labels : List RepoEdge) : Except String Scorecard := do
  let facts ← ingest files
  let r := Mitos.Impl.resolve facts
  return { facts, labels, predicted := collapse r.edges,
           unresolved := facts.filter (r.unresolved.contains ·.id) }

def Scorecard.render (c : Scorecard) (name : String) : String := Id.run do
  let pred := c.predicted.map (·.1)
  let types := (pred ++ c.labels).map RepoEdge.type |>.eraseDups
  let reqs := c.facts.filter (·.fact.kind == .requires) |>.length
  let mut out := s!"### Scorecard: fixture `{name}`\n\n"
  out := out ++ s!"{c.facts.length} facts ({reqs} requirements, {c.facts.length - reqs} provisions), "
  out := out ++ s!"{pred.length} repo-level edges predicted, {c.labels.length} hand-labelled, "
  out := out ++ s!"{c.unresolved.length} requirements unresolved.\n\n"
  out := out ++ "| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n"
  out := out ++ "|---|---|---|---|---|---|---|---|\n"
  for t in types do
    let p := pred.filter (·.type == t)
    let l := c.labels.filter (·.type == t)
    let tp := (p.filter l.contains).length
    out := out ++ s!"| {t} | {p.length} | {l.length} | {tp} | {p.length - tp} | {l.length - tp} "
    out := out ++ s!"| {ratio tp p.length} | {ratio tp l.length} |\n"
  out := out ++ "\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n"
  out := out ++ "|---|---|---|---|---|---|\n"
  for t in types do
    for s in [Status.confirmed, .inferred] do
      let p := c.predicted.filter (fun (e, s') => e.type == t && s' == s) |>.map (·.1)
      let tp := (p.filter c.labels.contains).length
      out := out ++ s!"| {t} | {statusName s} | {p.length} | {tp} | {p.length - tp} "
      out := out ++ s!"| {ratio tp p.length} |\n"
  let fps := c.predicted.filter (!c.labels.contains ·.1)
  let fns := c.labels.filter (!pred.contains ·)
  unless fps.isEmpty do
    out := out ++ "\nFalse positives (predicted, not labelled):\n"
    for (e, s) in fps do out := out ++ s!"- {e.render}, {statusName s}\n"
  unless fns.isEmpty do
    out := out ++ "\nMisses (labelled, not predicted):\n"
    for e in fns do out := out ++ s!"- {e.render}\n"
  unless c.unresolved.isEmpty do
    out := out ++ "\nUnresolved requirements:\n"
    for l in c.unresolved do
      out := out ++ s!"- `{l.repo}/{l.path}` bytes {l.fact.span.start}+{l.fact.span.len}: "
      out := out ++ s!"`{repr l.fact.ident.key}`\n"
  return out

end Score
