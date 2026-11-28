import Score
import Lean.Data.Json

namespace Score.Nightly

open Mitos

def d1Threshold : Nat := 8

def derivations (c : Scorecard) : List (RepoKey × Nat) :=
  let es := (Mitos.Impl.resolve c.facts).edges
  (es.map (·.repoKey)).eraseDups.map fun k => (k, es.countP (·.repoKey == k))

def most : List (RepoKey × Nat) → Nat
  | [] => 0
  | d :: ds => max d.2 (most ds)

def tied (top : Nat) (ds : List (RepoKey × Nat)) : List RepoKey :=
  (ds.filter (·.2 == top)).map (·.1)

private def consistent (c : Scorecard) (card : String) : Bool :=
  c.typeCounts.all fun t =>
    [t.row, t.trustRow .confirmed, t.trustRow .inferred].all (card.splitOn "\n").contains

private def edgeIdentity (k : RepoKey) : String :=
  (Lean.toJson #[k.requiringRepo, k.providingRepo, k.ident.kind, k.ident.key, scopeName k.scope]).compress

private def keyOf (identity : String) : Option RepoKey :=
  match Lean.Json.parse identity with
  | .ok (.arr #[.str requiringRepo, .str providingRepo, .str kind, .str key, .str sc]) =>
    (parseScope sc).map fun scope => { requiringRepo, providingRepo, ident := { kind, key }, scope }
  | _ => none

def numbers (name : String) (c : Scorecard) : List String :=
  let ds := derivations c
  let n := c.factCounts
  let line (fs : List String) := "\t".intercalate fs
  line ("counts" :: name ::
      [n.facts, n.requirements, n.provisions, n.bindings, n.unresolved].map toString) ::
    c.typeCounts.map (fun t => line ["rates", name, t.edgeType, ratio t.tp t.predicted,
      ratio t.tp t.labelled, ratio t.confirmedTp t.confirmed, ratio t.inferredTp t.inferred,
      toString (most (ds.filter (edgeType ·.1 == t.edgeType)))]) ++
    ds.map (fun (k, n) => line ["edge", name, renderEdge k,
      ((c.predicted.lookup k).map statusName).getD "not in the card", toString n, edgeIdentity k]) ++
    c.labels.map fun k => line ["label", name, renderEdge k, edgeIdentity k]

private def arity : String → Option Nat
  | "counts" => some 7
  | "rates" => some 8
  | "edge" => some 6
  | "label" => some 4
  | _ => none

def parseNumbers (txt : String) : Except String (List String) := do
  let mut out := #[]
  let mut n := 0
  for l in txt.splitOn "\n" do
    n := n + 1
    if l.isEmpty then continue
    let fs := l.splitOn "\t"
    let tag := fs.headD ""
    let some k := arity tag | throw s!"line {n}: unknown line kind {repr tag}"
    unless fs.length == k do
      throw s!"line {n}: a line of kind {tag} has {k} tab-separated fields, found {fs.length}"
    out := out.push l
  return out.toList

private def problem (name : String) (c : Scorecard) : Option String :=
  if !consistent c (c.render name) then some "the nightly numbers disagree with the card"
  else
    let ls := numbers name c
    match parseNumbers ("\n".intercalate ls) with
    | .error e => some s!"a numbers line of this fixture would not read back ({e})"
    | .ok readBack =>
      if readBack == ls then none else some "the numbers lines of this fixture changed on readback"

structure Result where
  name : String
  card : Except String Scorecard

def checked (name : String) : Except String Scorecard → Except String Scorecard
  | .ok c => match problem name c with
    | some e => .error e
    | none => .ok c
  | .error e => .error e

def numbersAll (rs : List Result) : Except (List String) (List String) :=
  match rs.filterMap fun r => match r.card with | .error e => some s!"{r.name}: {e}" | .ok _ => none with
  | [] => .ok (rs.flatMap fun r => match r.card with | .ok c => numbers r.name c | .error _ => [])
  | es => .error es

def changed (cur base : List String) : List String :=
  cur.filter (!base.contains ·) ++ base.filter (!cur.contains ·)

private def fields (line : String) : List String := line.splitOn "\t"

private def kind (line : String) : String := (fields line).headD ""

private def fixtureOf (line : String) : String := ((fields line).drop 1).headD ""

private def row (keys : Nat) (run : String) (line : String) : String :=
  let fs := ((fields line).drop 1).map plain
  "| " ++ " | ".intercalate (fs.take keys ++ [run] ++ fs.drop keys) ++ " |\n"

private def header : String :=
  "| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision " ++
  "| Most derivations |\n|---|---|---|---|---|---|---|---|\n"

private def countsHeader : String :=
  "| Fixture | Run | Facts | Requirements | Provisions | Bindings | Unresolved |\n" ++
  "|---|---|---|---|---|---|---|\n"

private def shown (identity : String) : String :=
  match keyOf identity with
  | some k => renderEdge k
  | none => code identity

private def item (side : String) (line : String) : String :=
  match fields line with
  | ["edge", n, _, s, d, i] => s!"- {code n}, {side}: {shown i}, {plain s}, derivations {plain d}\n"
  | ["label", n, _, i] => s!"- {code n}, {side}: {shown i}\n"
  | _ => s!"- {side}: {code line}\n"

private def sides (k : String) (keys : Nat) (gone new : List String) : String := Id.run do
  let mut out := ""
  for key in ((new ++ gone).map fun l => (fields l).take (keys + 1)).eraseDups do
    let absent := "\t".intercalate (key ++ List.replicate ((arity k).getD 0 - (keys + 1)) "none")
    let side (ls : List String) := match ls.filter fun l => (fields l).take (keys + 1) == key with
      | [] => [absent]
      | ls => ls
    for l in side gone do out := out ++ row keys "baseline" l
    for l in side new do out := out ++ row keys "this run" l
  return out

private def diff (cur base : List String) : String := Id.run do
  let gone := base.filter (!cur.contains ·)
  let new := cur.filter (!base.contains ·)
  let of (k : String) (ls : List String) := ls.filter (kind · == k)
  let mut out := ""
  unless (of "rates" gone).isEmpty && (of "rates" new).isEmpty do
    out := out ++ header ++ sides "rates" 2 (of "rates" gone) (of "rates" new)
  unless (of "counts" gone).isEmpty && (of "counts" new).isEmpty do
    out := out ++ "\n" ++ countsHeader ++ sides "counts" 1 (of "counts" gone) (of "counts" new)
  unless (of "label" gone).isEmpty && (of "label" new).isEmpty do
    out := out ++ "\n**The hand labels changed.**\n"
    for l in of "label" gone do out := out ++ item "label only in the baseline" l
    for l in of "label" new do out := out ++ item "label only in this run" l
  unless (of "edge" gone).isEmpty && (of "edge" new).isEmpty do
    out := out ++ "\nRepo-level edges that changed:\n"
    for l in of "edge" gone do out := out ++ item "only in the baseline" l
    for l in of "edge" new do out := out ++ item "only in this run" l
  return out

def summary (rs : List Result) (base : Option (List String)) : String := Id.run do
  let ok := rs.filterMap fun r => match r.card with | .ok c => some (r.name, c) | .error _ => none
  let failed := (rs.filter (!·.card.isOk)).map (·.name)
  let cur := ok.flatMap fun (n, c) => numbers n c
  let mut out := s!"## Nightly scorecard\n\n{rs.length} fixtures, {ok.length} scored.\n"
  unless failed.isEmpty do
    out := out ++ s!"\n**Not every fixture scored ({", ".intercalate (failed.map code)}), " ++
      "so the numbers below cover the others only.**\n"
  out := out ++ "\n### Every fixture\n\n" ++ header
  for l in cur.filter (kind · == "rates") do out := out ++ row 2 "this run" l
  let top := most (ok.flatMap fun (_, c) => derivations c)
  let tops := ok.flatMap fun (n, c) => (tied top (derivations c)).map fun k =>
    s!"{renderEdge k} in fixture {code n}" ++
      (if c.predicted.any (·.1 == k) then "" else ", which that fixture's card leaves out")
  if tops.isEmpty then
    out := out ++ "\nNo fixture has a repo-level edge, so no derivations were counted.\n"
  else
    out := out ++ s!"\nMost derivations any repo-level edge has: {top}, {"; ".intercalate tops}. " ++
      s!"D1 reopens above {d1Threshold}.\n"
    if top > d1Threshold then
      out := out ++ s!"\n**Above {d1Threshold}: D1 reopens (`plan/phase-2.md`, Scope decisions).**\n"
  out := out ++ "\n### Against the baseline\n\n"
  match base with
  | none => out := out ++ "No baseline given, so nothing was compared.\n"
  | some b =>
    let b' := b.filter fun l => !failed.contains (fixtureOf l)
    let counted := b.any (kind · == "counts")
    let cur' := if counted then cur else cur.filter (kind · != "counts")
    if changed cur' b' = [] then out := out ++ "No change against the baseline.\n"
    else out := out ++ diff cur' b'
    unless counted do
      out := out ++ "\nThe baseline has no fact counts, so they are not compared.\n"
    for n in failed.filter fun n => b.any (fixtureOf · == n) do
      out := out ++ s!"\n{code n} was not scored in this run, so it is not compared.\n"
  return out

private def cardOf (r : Result) : String :=
  match r.card with
  | .ok c => c.render r.name
  | .error e => s!"### Scorecard: fixture {code r.name}\n\nScorer error: {code e}\n"

def report (rs : List Result) (base : Option (List String)) : String :=
  summary rs base ++ String.join (rs.map fun r => "\n" ++ cardOf r)

theorem derivations_keys (c : Scorecard) :
    (derivations c).map (·.1) = ((Mitos.Impl.resolve c.facts).edges.map (·.repoKey)).eraseDups := by
  simp [derivations, List.map_map, Function.comp_def]

theorem le_most {ds : List (RepoKey × Nat)} {d : RepoKey × Nat} (h : d ∈ ds) :
    d.2 ≤ most ds := by
  induction ds with
  | nil => cases h
  | cons x xs ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

theorem most_mem {ds : List (RepoKey × Nat)} (h : ds ≠ []) : ∃ d ∈ ds, d.2 = most ds := by
  induction ds with
  | nil => exact absurd rfl h
  | cons x xs ih =>
    by_cases hx : most xs ≤ x.2
    · exact ⟨x, List.mem_cons_self, by simp [most, Nat.max_eq_left hx]⟩
    · have hne : xs ≠ [] := by rintro rfl; simp [most] at hx
      obtain ⟨d, hd, hde⟩ := ih hne
      exact ⟨d, List.mem_cons_of_mem _ hd, by simp [most]; omega⟩

theorem mem_tied {ds : List (RepoKey × Nat)} {top : Nat} {k : RepoKey} :
    k ∈ tied top ds ↔ (k, top) ∈ ds := by
  simp [tied]

theorem changed_eq_nil {cur base : List String} :
    changed cur base = [] ↔ ∀ l, l ∈ cur ↔ l ∈ base := by
  simp only [changed, List.contains_eq_mem, List.append_eq_nil_iff, List.filter_eq_nil_iff,
    Bool.not_eq_eq_eq_not, Bool.not_true, decide_eq_false_iff_not, Decidable.not_not]
  exact ⟨fun ⟨h1, h2⟩ l => ⟨h1 l, h2 l⟩,
    fun h => ⟨fun l => (h l).1, fun l => (h l).2⟩⟩

private def pinKey : RepoKey :=
  { requiringRepo := "a", providingRepo := "b", ident := { kind := "toy", key := "x" },
    scope := .runtime }

private def pinFiles (n : Nat) : List SourceFile :=
  [{ repo := "a", path := "deps.toy", text := String.join (List.replicate n "require x\n") },
   { repo := "b", path := "PROVIDES", text := "provide x\n" }]

private def pinAs (name : String) (files : List SourceFile) (labels : List RepoKey := [pinKey]) :
    Result :=
  { name, card := checked name (score files labels) }

private def pin (n : Nat) (labels : List RepoKey := [pinKey]) : List Result :=
  [pinAs "pin" (pinFiles n) labels]

private def pinNumbers (n : Nat) : List String :=
  match numbersAll (pin n) with
  | .ok ls => ls
  | .error _ => []

private def has (hay needle : String) : Bool := (hay.splitOn needle).length > 1

#guard pinNumbers 2 ==
  ["counts\tpin\t3\t2\t1\t0\t0",
   "rates\tpin\ttoy/runtime\t1.00 (1/1)\t1.00 (1/1)\t1.00 (1/1)\tn/a\t2",
   "edge\tpin\t`a` → `b` (toy/runtime `x`)\tconfirmed\t2\t[\"a\",\"b\",\"toy\",\"x\",\"runtime\"]",
   "label\tpin\t`a` → `b` (toy/runtime `x`)\t[\"a\",\"b\",\"toy\",\"x\",\"runtime\"]"]

#guard (parseNumbers ("\n".intercalate (pinNumbers 2))).toOption == some (pinNumbers 2)

#guard (parseNumbers "rates\tpin\ttoy/runtime\t1.00 (1/1)\n").toOption.isNone

#guard (parseNumbers "card\tpin\n").toOption.isNone

#guard match score (pinFiles 1) [pinKey] with
  | .ok c => consistent c (c.render "pin") && !consistent c ""
  | .error _ => false

#guard has (summary (pin 8) none) "has: 8, `a` → `b` (toy/runtime `x`) in fixture `pin`. D1 reopens above 8.\n"

#guard !has (summary (pin 8) none) "**Above 8"

#guard has (summary (pin 9) none) "**Above 8: D1 reopens"

#guard has (summary (pin 1) none) "No baseline given, so nothing was compared."

#guard has (summary (pin 1) (some (pinNumbers 1))) "No change against the baseline."

#guard !has (summary (pin 1) (some [])) "No change"

#guard has (summary (pin 2) (some (pinNumbers 1))) "| pin | toy/runtime | baseline | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | n/a | 1 |"

#guard has (summary (pin 1 []) (some (pinNumbers 1))) "**The hand labels changed.**\n- `pin`, label only in the baseline: `a` → `b` (toy/runtime `x`)\n"

#guard has (summary (pin 1) (some ((pinNumbers 1).map (·.replace "pin" "gone")))) "| gone | toy/runtime | this run | none | none | none | none | none |"

#guard has (summary [{ name := "pin", card := .error "broken" }] (some (pinNumbers 1)))
  "`pin` was not scored in this run, so it is not compared."

#guard !has (summary [{ name := "pin", card := .error "broken" }] (some (pinNumbers 1))) "| none |"

#guard has (summary [{ name := "pin", card := .error "broken" }] none) "**Not every fixture scored (`pin`)"

#guard (numbersAll [{ name := "pin", card := .error "broken" }]) matches .error ["pin: broken"]

#guard has (summary [] none) "No fixture has a repo-level edge, so no derivations were counted."

#guard match (pin 2).head?.bind (·.card.toOption) with
  | some c => has (summary [{ name := "pin", card := .ok { c with predicted := [] } }] none)
      "in fixture `pin`, which that fixture's card leaves out."
  | none => false

private def collisionLabel (src dst : String) : RepoKey :=
  { pinKey with requiringRepo := src, providingRepo := dst }

#guard
  let old := collisionLabel "a` → `b" "c"
  let new := collisionLabel "a" "b` → `c"
  match numbersAll (pin 1 [old]), numbersAll (pin 1 [new]) with
  | .ok before, .ok after =>
    let report := summary (pin 1 [new]) (some before)
    renderEdge old != renderEdge new &&
      (before.filter (kind · != "label")) == (after.filter (kind · != "label")) &&
      has report s!"label only in the baseline: {renderEdge old}\n" &&
      has report s!"label only in this run: {renderEdge new}\n"
  | _, _ => false

private def tieFiles : List SourceFile :=
  [{ repo := "a", path := "deps.toy", text := "require x\nrequire x\nrequire y\nrequire y\n" },
   { repo := "b", path := "PROVIDES", text := "provide x\nprovide y\n" }]

#guard has (summary [pinAs "p" (pinFiles 2), pinAs "q" (pinFiles 1), pinAs "r" tieFiles] none)
  ("has: 2, `a` → `b` (toy/runtime `x`) in fixture `p`; `a` → `b` (toy/runtime `x`) in fixture `r`; " ++
    "`a` → `b` (toy/runtime `y`) in fixture `r`. D1 reopens above 8.\n")

private def unresolvedFiles : List SourceFile :=
  pinFiles 1 ++ [{ repo := "a", path := "more.toy", text := "require y\n" }]

#guard has (summary [pinAs "pin" unresolvedFiles] (some (pinNumbers 1)))
  ("### Against the baseline\n\n\n" ++ countsHeader ++
    "| pin | baseline | 2 | 1 | 1 | 0 | 0 |\n| pin | this run | 3 | 2 | 1 | 0 | 1 |\n")

private def beforeCounts : String :=
  "rates\tpin\ttoy/runtime\t1.00 (1/1)\t1.00 (1/1)\t1.00 (1/1)\tn/a\t2\n" ++
  "edge\tpin\t`a` → `b` (toy/runtime `x`)\tconfirmed\t2\t[\"a\",\"b\",\"toy\",\"x\",\"runtime\"]\n" ++
  "label\tpin\t`a` → `b` (toy/runtime `x`)\t[\"a\",\"b\",\"toy\",\"x\",\"runtime\"]\n"

#guard match parseNumbers beforeCounts with
  | .ok base =>
    let report := summary (pin 2) (some base)
    base == (pinNumbers 2).drop 1 && !has report "| none |" &&
      has report ("No change against the baseline.\n\n" ++
        "The baseline has no fact counts, so they are not compared.\n")
  | .error _ => false

#guard (checked "a\t0\t0\t0\t0\t0\ncounts\tb" (score [] [])) matches
  .error "the numbers lines of this fixture changed on readback"

private def evil : String := "a`b|c@d\re\\f"

private def evilLines : String := evil ++ "\n" ++ evil

private def shape (s : String) : List Nat :=
  ["\n", "`", "|", "@", "\r"].map fun c => (s.splitOn c).length

private def stressKey (t u : String) : RepoKey :=
  { requiringRepo := u, providingRepo := t, ident := { kind := u, key := u }, scope := .runtime }

private def stress (t u : String) (n : Nat) (labels : List RepoKey) : List Result :=
  [pinAs t [{ repo := u, path := "deps.toy",
              text := String.join (List.replicate n s!"require {t}\n") ++ s!"require {t}{t}\n" },
            { repo := t, path := "PROVIDES", text := s!"provide {t}\n" }] labels,
   { name := t ++ "k", card := .ok { facts := [], predicted := [(stressKey t u, .inferred)],
                                     labels := [stressKey u t], unresolved := [] } },
   { name := u, card := .error u }]

private def stressReport (t u : String) : String :=
  let label : RepoKey := { stressKey t u with ident := { kind := "toy", key := t } }
  let base := match numbersAll ((stress t u 2 []).take 2) with
    | .ok ls => ls
    | .error _ => []
  report (stress t u 1 [label])
    (some (base ++ ["\t".intercalate ("rates" :: List.replicate 7 t),
      "\t".intercalate ("counts" :: List.replicate 6 t), "\t".intercalate ("edge" :: List.replicate 5 t),
      "\t".intercalate ("label" :: List.replicate 3 t), "\t".intercalate ("counts" :: u :: List.replicate 5 t),
      "edge\t" ++ t]))

#guard shape (stressReport evil evilLines) == shape (stressReport "x" "y")

#guard has (stressReport evil evilLines)
  "- `a\\x60b\\x7cc\\x40d\\x0de\\\\f\\na\\x60b\\x7cc\\x40d\\x0de\\\\f/deps.toy` bytes "

#guard keyOf (edgeIdentity (stressKey evil evilLines)) == some (stressKey evil evilLines)

private def spite : String := "a[b&c<d*e_f~g\x1bh\x00i\x7fj"

private def spiteLines : String := spite ++ "\n" ++ spite

private def controlShape (s : String) : List Nat :=
  ["[", "\x1b", "\x00", "\x7f"].map fun c => (s.splitOn c).length

private def outsideCode (s : String) : String :=
  String.join (((s.splitOn "`").zipIdx.filter (·.2 % 2 == 0)).map (·.1))

private def markupShape (s : String) : List Nat :=
  ["&", "<", "*", "_", "~"].map fun c => ((outsideCode s).splitOn c).length

#guard shape (stressReport spite spiteLines) == shape (stressReport "x" "y") &&
  controlShape (stressReport spite spiteLines) == controlShape (stressReport "x" "y")

#guard markupShape (stressReport spite spiteLines) == markupShape (stressReport "x" "y")

#guard has (stressReport spite spiteLines)
  ("/deps.toy` bytes 36+38: `\"a\\x5bb&c<d*e_f~g\\x1bh\\x00i\\x7fj" ++
    "a\\x5bb&c<d*e_f~g\\x1bh\\x00i\\x7fj\"`\n")

private def tabFiles : List SourceFile :=
  [{ repo := "a", path := "deps.toy", text := "require p\tq\n" },
   { repo := "b", path := "PROVIDES", text := "provide p\tq\n" }]

#guard (numbersAll [pinAs "t" tabFiles []]) matches .ok
  ["counts\tt\t2\t1\t1\t0\t0", "rates\tt\ttoy/runtime\t0.00 (0/1)\tn/a\t0.00 (0/1)\tn/a\t1",
   "edge\tt\t`a` → `b` (toy/runtime `p\\tq`)\tconfirmed\t1\t[\"a\",\"b\",\"toy\",\"p\\u0009q\",\"runtime\"]"]

end Score.Nightly
