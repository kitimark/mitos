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

def controls : List (Char × List Char) :=
  (List.range 32 ++ [127]).map fun n =>
    (Char.ofNat n, ['\\', 'x', Nat.digitChar (n / 16), Nat.digitChar (n % 16)])

def escapes : List (Char × List Char) :=
  [('\\', "\\\\".toList), ('`', "\\x60".toList), ('|', "\\x7c".toList),
   ('\n', "\\n".toList), ('\r', "\\x0d".toList), ('@', "\\x40".toList),
   ('[', "\\x5b".toList), ('\t', "\\t".toList)] ++ controls

def plainEscapes : List (Char × List Char) :=
  escapes ++ [('&', "\\x26".toList), ('<', "\\x3c".toList), ('*', "\\x2a".toList),
    ('_', "\\x5f".toList), ('~', "\\x7e".toList)]

def breaks : List Char := ['`', '|', '\n', '\r', '@', '['] ++ controls.map (·.1)

def plainBreaks : List Char := breaks ++ ['&', '<', '*', '_', '~']

def escape (t : List (Char × List Char)) (c : Char) : List Char :=
  match t.find? (·.1 == c) with
  | some (_, e) => e
  | none => [c]

def escaped (t : List (Char × List Char)) (s : String) : String :=
  String.ofList (s.toList.flatMap (escape t))

def inert (s : String) : String := escaped escapes s

def plain (s : String) : String := escaped plainEscapes s

def code (s : String) : String := "`" ++ inert s ++ "`"

def logLine (s : String) : String := "mitos-score: " ++ inert s

private theorem escape_safe {t : List (Char × List Char)} {bs : List Char}
    (h₁ : ∀ p ∈ t, ∀ x ∈ p.2, x ∉ bs) (h₂ : ∀ b ∈ bs, ∃ p ∈ t, p.1 = b) {d c : Char}
    (h : c ∈ escape t d) : c ∉ bs := by
  unfold escape at h
  split at h
  · next e he => exact h₁ _ (List.mem_of_find?_eq_some he) c h
  · next he =>
    rw [List.mem_singleton] at h
    subst h
    intro hb
    obtain ⟨p, hp, rfl⟩ := h₂ c hb
    exact absurd (beq_self_eq_true p.1) (List.find?_eq_none.1 he p hp)

private theorem escaped_safe {t : List (Char × List Char)} {bs : List Char}
    (h₁ : ∀ p ∈ t, ∀ x ∈ p.2, x ∉ bs) (h₂ : ∀ b ∈ bs, ∃ p ∈ t, p.1 = b) (s : String) :
    ∀ c ∈ (escaped t s).toList, c ∉ bs := by
  intro c h
  simp only [escaped, String.toList_ofList, List.mem_flatMap] at h
  obtain ⟨d, -, hd⟩ := h
  exact escape_safe h₁ h₂ hd

theorem inert_safe (s : String) : ∀ c ∈ (inert s).toList, c ∉ breaks :=
  escaped_safe (by decide +kernel) (by decide +kernel) s

theorem plain_safe (s : String) : ∀ c ∈ (plain s).toList, c ∉ plainBreaks :=
  escaped_safe (by decide +kernel) (by decide +kernel) s

theorem logLine_safe (s : String) : ∀ c ∈ (logLine s).toList, c ∉ breaks := by
  intro c h
  rw [logLine, String.toList_append, List.mem_append] at h
  rcases h with h | h
  · exact (by decide +kernel : ∀ c ∈ "mitos-score: ".toList, c ∉ breaks) c h
  · exact inert_safe s c h

theorem logLine_head (s : String) : (logLine s).toList.head? = some 'm' := by
  rw [logLine, String.toList_append]
  rfl

theorem logLine_cases :
    ["::warning::x: labels.tsv is missing", "x##[error]y", "a\n::error::b"].map logLine =
      ["mitos-score: ::warning::x: labels.tsv is missing", "mitos-score: x##\\x5berror]y",
        "mitos-score: a\\n::error::b"] := by decide +kernel

private theorem escaped_clean {t : List (Char × List Char)} {s : String}
    (h : ∀ c ∈ s.toList, c ∉ t.map (·.1)) : escaped t s = s := by
  have : ∀ l : List Char, (∀ c ∈ l, c ∉ t.map (·.1)) → l.flatMap (escape t) = l := by
    intro l
    induction l with
    | nil => intro _; rfl
    | cons c l ih =>
      intro hl
      have hc : escape t c = [c] := by
        unfold escape
        split
        · next k e he =>
          have hk : k = c := by simpa using List.find?_some he
          exact absurd (List.mem_map.2 ⟨_, List.mem_of_find?_eq_some he, hk⟩) (hl c List.mem_cons_self)
        · rfl
      rw [List.flatMap_cons, hc, ih fun x hx => hl x (List.mem_cons_of_mem _ hx)]
      rfl
  rw [escaped, this _ h, String.ofList_toList]

theorem inert_clean {s : String} (h : ∀ c ∈ s.toList, c ∉ escapes.map (·.1)) : inert s = s :=
  escaped_clean h

theorem plain_clean {s : String} (h : ∀ c ∈ s.toList, c ∉ plainEscapes.map (·.1)) : plain s = s :=
  escaped_clean h

private structure Decodes (t : List (Char × List Char)) : Prop where
  lead : ∀ p ∈ t, p.2.head? = some '\\'
  keyed : t.find? (·.1 == '\\') ≠ none
  apart : ∀ p ∈ t, ∀ q ∈ t, (p.2.isPrefixOf q.2 || q.2.isPrefixOf p.2) = true → p.1 = q.1

private theorem escape_cases (t : List (Char × List Char)) (c : Char) :
    (∃ p ∈ t, p.1 = c ∧ escape t c = p.2) ∨
      (t.find? (·.1 == c) = none ∧ escape t c = [c]) := by
  unfold escape
  split
  · next k e he =>
    exact .inl ⟨(k, e), List.mem_of_find?_eq_some he, by simpa using List.find?_some he, rfl⟩
  · next he => exact .inr ⟨he, rfl⟩

private theorem keyed_ne_plain {t : List (Char × List Char)} (ht : Decodes t)
    {p : Char × List Char} (hp : p ∈ t) {b : Char} (nb : t.find? (·.1 == b) = none)
    {x y : List Char} : p.2 ++ x ≠ [b] ++ y := by
  intro h
  have hb : b = '\\' := by
    have := congrArg List.head? h
    simpa [List.head?_append, ht.lead p hp] using this.symm
  subst hb
  exact ht.keyed nb

private theorem escape_head {t : List (Char × List Char)} (ht : Decodes t) {a b : Char}
    {x y : List Char} (h : escape t a ++ x = escape t b ++ y) : a = b := by
  rcases escape_cases t a with ⟨p, hp, rfl, ha⟩ | ⟨na, ha⟩ <;>
    rcases escape_cases t b with ⟨q, hq, rfl, hb⟩ | ⟨nb, hb⟩ <;> rw [ha, hb] at h
  · have hpq : p.2 <+: q.2 ∨ q.2 <+: p.2 :=
      List.prefix_or_prefix_of_prefix (List.prefix_append p.2 x) (h ▸ List.prefix_append q.2 y)
    exact ht.apart p hp q hq (by simpa [List.isPrefixOf_iff_prefix] using hpq)
  · exact absurd h (keyed_ne_plain ht hp nb)
  · exact absurd h.symm (keyed_ne_plain ht hq na)
  · exact (by simpa using h : a = b ∧ x = y).1

private theorem flatMap_escape_inj {t : List (Char × List Char)} (ht : Decodes t) :
    ∀ {l m : List Char}, l.flatMap (escape t) = m.flatMap (escape t) → l = m
  | [], [], _ => rfl
  | [], b :: m, h => by
    rcases escape_cases t b with ⟨p, hp, -, hb⟩ | ⟨-, hb⟩ <;> simp [hb] at h
    exact absurd (ht.lead p hp) (by simp [h.1])
  | a :: l, [], h => by
    rcases escape_cases t a with ⟨p, hp, -, ha⟩ | ⟨-, ha⟩ <;> simp [ha] at h
    exact absurd (ht.lead p hp) (by simp [h.1])
  | a :: l, b :: m, h => by
    rw [List.flatMap_cons, List.flatMap_cons] at h
    obtain rfl := escape_head ht h
    rw [flatMap_escape_inj ht (List.append_cancel_left h)]

private theorem escaped_injective {t : List (Char × List Char)} (ht : Decodes t) {a b : String}
    (h : escaped t a = escaped t b) : a = b := by
  have := congrArg String.toList h
  simp only [escaped, String.toList_ofList] at this
  exact String.toList_injective (flatMap_escape_inj ht this)

theorem inert_injective {s t : String} (h : inert s = inert t) : s = t :=
  escaped_injective ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩ h

theorem plain_injective {s t : String} (h : plain s = plain t) : s = t :=
  escaped_injective ⟨by decide +kernel, by decide +kernel, by decide +kernel⟩ h

theorem inert_cases :
    ["`", "|", "\n", "\r", "@", "\\", "naïve-date", "[", "\t", "\x00", "\x1b", "\x7f", "&<*_~"].map
        inert =
      ["\\x60", "\\x7c", "\\n", "\\x0d", "\\x40", "\\\\", "naïve-date", "\\x5b", "\\t", "\\x00",
        "\\x1b", "\\x7f", "&<*_~"] := by decide +kernel

theorem plain_cases :
    ["&", "<", "*", "_", "~", "[", "@", "\x1b", "go-module/runtime", "0.83 (5/6)"].map plain =
      ["\\x26", "\\x3c", "\\x2a", "\\x5f", "\\x7e", "\\x5b", "\\x40", "\\x1b", "go-module/runtime",
        "0.83 (5/6)"] := by decide +kernel

def edgeType (k : RepoKey) : String := s!"{k.ident.kind}/{scopeName k.scope}"

def renderEdge (k : RepoKey) : String :=
  s!"{code k.requiringRepo} → {code k.providingRepo} ({plain (edgeType k)} {code k.ident.key})"

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

structure FactCounts where
  facts : Nat
  requirements : Nat
  provisions : Nat
  bindings : Nat
  unresolved : Nat

def Scorecard.factCounts (c : Scorecard) : FactCounts :=
  { facts := c.facts.length,
    requirements := (c.facts.filter (·.fact.kind == .requires)).length,
    provisions := (c.facts.filter (·.fact.kind == .provides)).length,
    bindings := (c.facts.filter (·.fact.kind matches .binds _)).length,
    unresolved := c.unresolved.length }

structure TypeCounts where
  edgeType : String
  predicted : Nat
  labelled : Nat
  tp : Nat
  confirmed : Nat
  confirmedTp : Nat
  inferred : Nat
  inferredTp : Nat

def Scorecard.typeCounts (c : Scorecard) : List TypeCounts :=
  let pred := c.predicted.map (·.1)
  ((pred ++ c.labels).map edgeType).eraseDups.map fun t =>
    let p := pred.filter (edgeType · == t)
    let l := c.labels.filter (edgeType · == t)
    let trust (s : Status) :=
      c.predicted.filter (fun (e, s') => edgeType e == t && s' == s) |>.map (·.1)
    let hits (ks : List RepoKey) := (ks.filter c.labels.contains).length
    { edgeType := t, predicted := p.length, labelled := l.length, tp := (p.filter l.contains).length,
      confirmed := (trust .confirmed).length, confirmedTp := hits (trust .confirmed),
      inferred := (trust .inferred).length, inferredTp := hits (trust .inferred) }

def TypeCounts.row (t : TypeCounts) : String :=
  s!"| {plain t.edgeType} | {t.predicted} | {t.labelled} | {t.tp} | {t.predicted - t.tp} | " ++
    s!"{t.labelled - t.tp} | {ratio t.tp t.predicted} | {ratio t.tp t.labelled} |"

def TypeCounts.trustRow (t : TypeCounts) (s : Status) : String :=
  let (n, tp) := match s with
    | .confirmed => (t.confirmed, t.confirmedTp)
    | .inferred => (t.inferred, t.inferredTp)
  s!"| {plain t.edgeType} | {statusName s} | {n} | {tp} | {n - tp} | {ratio tp n} |"

def Scorecard.render (c : Scorecard) (name : String) : String := Id.run do
  let pred := c.predicted.map (·.1)
  let n := c.factCounts
  let mut out := s!"### Scorecard: fixture {code name}\n\n"
  out := out ++ s!"{n.facts} facts ({n.requirements} requirements, {n.provisions} provisions"
  out := out ++ (if n.bindings = 0 then "), " else s!", {n.bindings} bindings), ")
  out := out ++ s!"{pred.length} repo-level edges predicted, {c.labels.length} hand-labelled, "
  out := out ++ s!"{n.unresolved} requirements unresolved.\n\n"
  out := out ++ "| Edge type | Predicted | Labelled | TP | FP | FN | Precision | Recall |\n"
  out := out ++ "|---|---|---|---|---|---|---|---|\n"
  for t in c.typeCounts do out := out ++ t.row ++ "\n"
  out := out ++ "\n| Edge type | Trust level | Predicted | TP | FP | Precision |\n"
  out := out ++ "|---|---|---|---|---|---|\n"
  for t in c.typeCounts do
    for s in [Status.confirmed, .inferred] do out := out ++ t.trustRow s ++ "\n"
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
      out := out ++ s!"- {code s!"{l.repo}/{l.path}"} bytes {l.fact.span.start}+{l.fact.span.len}: "
      out := out ++ s!"`\"{inert l.fact.ident.key}\"`\n"
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

private def chainCrlfFiles : List SourceFile :=
  [{ repo := "deploy", path := "CHAIN", text := "binds A db\r\n" },
   { repo := "orders", path := "CHAIN", text := "serves db \r\n" },
   { repo := "web", path := "CHAIN", text := "needs  A\r\n" }]

theorem chain_crlf_end_to_end :
    (score chainCrlfFiles []).toOption.map (fun c => (c.facts.length, c.predicted)) =
      some (3, [({ requiringRepo := "web", providingRepo := "orders", ident := ⟨"env", "A"⟩,
                   scope := .runtime }, .confirmed)]) := by
  decide +kernel

end Score
