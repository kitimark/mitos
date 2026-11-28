import Mitos.Core.Spec
import Mitos.Impl.Resolve
import Plugins.ToyRequire
import Score.Chain
import Score.GoMod

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

def readsToy (path : String) : Bool := ".toy".toList.isSuffixOf path.toList

def factsOf (f : SourceFile) : List (Fact × Assumption) :=
  if GoMod.reads f.path then GoMod.facts f.text else
  if Chain.reads f.path then Chain.facts f.repo f.path f.text else
  if readsToy f.path then (ToyRequire.extractor.run f.text).map (·, .extractor "ToyRequire") else
  if f.path == "PROVIDES" then
    (declared f.text).map (·, .humanDeclaredOutsideSource s!"{f.repo}/PROVIDES")
  else []

theorem factsOf_chain {f : SourceFile} (h : Chain.reads f.path = true) :
    factsOf f = Chain.facts f.repo f.path f.text := by
  have hg : GoMod.reads f.path = false := by
    simp only [Chain.reads, Bool.or_eq_true, beq_iff_eq] at h
    rcases h with h | h <;> rw [h] <;> decide
  simp [factsOf, hg, h]

theorem readsToy_cases :
    ["deps.toy", "src/main.toy", "PROVIDES", "mail.yaml", "deps.toy.bak", "toy"].map readsToy =
      [true, true, false, false, false, false] := by decide

theorem factsOf_unclaimed {f : SourceFile} (hg : GoMod.reads f.path = false)
    (hc : Chain.reads f.path = false) (ht : readsToy f.path = false) (hp : f.path ≠ "PROVIDES") :
    factsOf f = [] := by
  simp [factsOf, hg, hc, ht, hp]

theorem factsOf_unclaimed_yaml :
    factsOf { repo := "deploy", path := "mail.yaml", text := "require x\nprovide y\n" } = [] := by
  decide

def ingest (files : List SourceFile) : Except String (List Located) := do
  let mut out : Array Located := #[]
  for f in files do
    for (fact, origin) in factsOf f do
      unless fact.span.text f.text.toList == some fact.ident.key.toList do
        throw s!"{f.repo}/{f.path}: fact {repr fact.ident.key} is not anchored at {repr fact.span}"
      out := out.push { id := out.size, repo := f.repo, rev := "fixture", path := f.path, fact, origin }
  return out.toList

def edgeType (k : RepoKey) : String := s!"{k.ident.kind}/{scopeName k.scope}"

def renderEdge (k : RepoKey) : String :=
  s!"`{k.requiringRepo}` → `{k.providingRepo}` ({edgeType k} `{k.ident.key}`)"

def parseLabels (txt : String) : Except String (List RepoKey) := do
  let mut out := #[]
  let mut n := 0
  for l in txt.splitOn "\n" do
    n := n + 1
    if l.isEmpty || l.startsWith "#" then continue
    match l.splitOn "\t" with
    | [src, dst, kind, key, sc] =>
      let some scope := parseScope sc | throw s!"labels.tsv:{n}: unknown scope {repr sc}"
      let e : RepoKey := { requiringRepo := src, providingRepo := dst, ident := { kind, key }, scope }
      if out.contains e then throw s!"labels.tsv:{n}: duplicate label"
      out := out.push e
    | fs => throw s!"labels.tsv:{n}: expected 5 tab-separated fields, found {fs.length}"
  return out.toList

def collapse (es : List Edge) : List (RepoKey × Status) :=
  es.foldl (init := []) fun acc e =>
    if acc.any (·.1 == e.repoKey) then
      acc.map fun (k, s) => (k, if k == e.repoKey && e.status == .confirmed then .confirmed else s)
    else acc ++ [(e.repoKey, e.status)]

private def unionKey (dst : String) : RepoKey :=
  { requiringRepo := "web", providingRepo := dst, ident := { kind := "env", key := "K" },
    scope := .runtime }

private def unionRecord (dst : String) (s : Status) : Edge :=
  { unionKey dst with key := .direct 0 0, assumes := [], status := s }

theorem collapse_union :
    collapse [unionRecord "a" .inferred, unionRecord "a" .confirmed, unionRecord "b" .confirmed,
        unionRecord "b" .inferred, unionRecord "c" .inferred, unionRecord "c" .inferred] =
      [(unionKey "a", .confirmed), (unionKey "b", .confirmed), (unionKey "c", .inferred)] := by
  decide

def ratio (n d : Nat) : String :=
  if d = 0 then "n/a" else
    let x := (n * 100 + d / 2) / d
    let frac := toString (x % 100)
    s!"{x / 100}.{if frac.length < 2 then "0" ++ frac else frac} ({n}/{d})"

structure Scorecard where
  facts      : List Located
  predicted  : List (RepoKey × Status)
  labels     : List RepoKey
  unresolved : List Located

def knownLabelKind (facts : List Located) (label : RepoKey) : Bool :=
  facts.any fun l => l.fact.ident.kind == label.ident.kind

def absentLabelKind (facts : List Located) (labels : List RepoKey) : Option String :=
  labels.findSome? fun label =>
    if knownLabelKind facts label then none else some label.ident.kind

def score (files : List SourceFile) (labels : List RepoKey) : Except String Scorecard := do
  let facts ← ingest files
  match absentLabelKind facts labels with
  | some kind => throw s!"label kind {repr kind} is not among the extracted facts"
  | none =>
    let r := Mitos.Impl.resolve facts
    return { facts, labels, predicted := collapse r.edges,
             unresolved := facts.filter (r.unresolved.contains ·.id) }

def Scorecard.render (c : Scorecard) (name : String) : String := Id.run do
  let pred := c.predicted.map (·.1)
  let types := (pred ++ c.labels).map edgeType |>.eraseDups
  let reqs := c.facts.filter (·.fact.kind == .requires) |>.length
  let provs := c.facts.filter (·.fact.kind == .provides) |>.length
  let binds := c.facts.filter (·.fact.kind matches .binds _) |>.length
  let mut out := s!"### Scorecard: fixture `{name}`\n\n"
  out := out ++ s!"{c.facts.length} facts ({reqs} requirements, {provs} provisions"
  out := out ++ (if binds = 0 then "), " else s!", {binds} bindings), ")
  out := out ++ s!"{pred.length} repo-level edges predicted, {c.labels.length} hand-labelled, "
  out := out ++ s!"{c.unresolved.length} requirements unresolved.\n\n"
  out := out ++ "| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n"
  out := out ++ "|---|---|---|---|---|---|---|---|\n"
  for t in types do
    let p := pred.filter (edgeType · == t)
    let l := c.labels.filter (edgeType · == t)
    let tp := (p.filter l.contains).length
    out := out ++ s!"| {t} | {p.length} | {l.length} | {tp} | {p.length - tp} | {l.length - tp} "
    out := out ++ s!"| {ratio tp p.length} | {ratio tp l.length} |\n"
  out := out ++ "\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n"
  out := out ++ "|---|---|---|---|---|---|\n"
  for t in types do
    for s in [Status.confirmed, .inferred] do
      let p := c.predicted.filter (fun (e, s') => edgeType e == t && s' == s) |>.map (·.1)
      let tp := (p.filter c.labels.contains).length
      out := out ++ s!"| {t} | {statusName s} | {p.length} | {tp} | {p.length - tp} "
      out := out ++ s!"| {ratio tp p.length} |\n"
  let fps := c.predicted.filter (!c.labels.contains ·.1)
  let fns := c.labels.filter (!pred.contains ·)
  unless fps.isEmpty do
    out := out ++ "\nFalse positives (predicted, not labelled):\n"
    for (e, s) in fps do out := out ++ s!"- {renderEdge e}, {statusName s}\n"
  unless fns.isEmpty do
    out := out ++ "\nMisses (labelled, not predicted):\n"
    for e in fns do out := out ++ s!"- {renderEdge e}\n"
  unless c.unresolved.isEmpty do
    out := out ++ "\nUnresolved requirements:\n"
    for l in c.unresolved do
      out := out ++ s!"- `{l.repo}/{l.path}` bytes {l.fact.span.start}+{l.fact.span.len}: "
      out := out ++ s!"`{repr l.fact.ident.key}`\n"
  return out

private def chainUnionFiles : List SourceFile :=
  [{ repo := "deploy", path := "CHAIN", text := "binds A db\n" },
   { repo := "deploy", path := "CHAIN.ai", text := "binds A db\n" },
   { repo := "orders", path := "CHAIN", text := "serves db\n" },
   { repo := "web", path := "CHAIN", text := "needs A\n" }]

theorem chain_union_end_to_end :
    (score chainUnionFiles []).toOption.map (fun c => (c.facts.length, c.predicted)) =
      some (4, [({ requiringRepo := "web", providingRepo := "orders", ident := ⟨"env", "A"⟩,
                   scope := .runtime }, .confirmed)]) := by
  decide +kernel

end Score
