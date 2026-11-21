import Score

namespace Score.Nightly

open Mitos

def d1Threshold : Nat := 8

def derivations (c : Scorecard) : List (RepoKey × Nat) :=
  let es := (Mitos.Impl.resolve c.facts).edges
  (es.map (·.repoKey)).eraseDups.map fun k => (k, es.countP (·.repoKey == k))

def most : List (RepoKey × Nat) → Nat
  | [] => 0
  | d :: ds => max d.2 (most ds)

private structure TypeCounts where
  edgeType : String
  predicted : Nat
  labelled : Nat
  tp : Nat
  confirmed : Nat
  confirmedTp : Nat
  inferred : Nat
  inferredTp : Nat

private def typeCounts (c : Scorecard) : List TypeCounts :=
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

private def TypeCounts.cardLines (t : TypeCounts) : List String :=
  let trust (s : Status) (n tp : Nat) :=
    s!"| {t.edgeType} | {statusName s} | {n} | {tp} | {n - tp} | {ratio tp n} |"
  [s!"| {t.edgeType} | {t.predicted} | {t.labelled} | {t.tp} | {t.predicted - t.tp} | " ++
      s!"{t.labelled - t.tp} | {ratio t.tp t.predicted} | {ratio t.tp t.labelled} |",
   trust .confirmed t.confirmed t.confirmedTp, trust .inferred t.inferred t.inferredTp]

private def consistent (c : Scorecard) (card : String) : Bool :=
  (typeCounts c).all fun t => t.cardLines.all (card.splitOn "\n").contains

def numbers (name : String) (c : Scorecard) : List String :=
  let ds := derivations c
  let line (fs : List String) := "\t".intercalate fs
  (typeCounts c).map (fun t => line ["rates", name, t.edgeType, ratio t.tp t.predicted,
      ratio t.tp t.labelled, ratio t.confirmedTp t.confirmed, ratio t.inferredTp t.inferred,
      toString (most (ds.filter (edgeType ·.1 == t.edgeType)))]) ++
    ds.map (fun (k, n) => line ["edge", name, renderEdge k,
      ((c.predicted.lookup k).map statusName).getD "not in the card", toString n]) ++
    c.labels.map fun k => line ["label", name, renderEdge k]

private def arity : String → Option Nat
  | "rates" => some 8
  | "edge" => some 5
  | "label" => some 3
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
      throw s!"line {n}: a line of kind `{tag}` has {k} tab-separated fields, found {fs.length}"
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

private def row (run : String) (line : String) : String :=
  let fs := (fields line).drop 1
  "| " ++ " | ".intercalate (fs.take 2 ++ [run] ++ fs.drop 2) ++ " |\n"

private def header : String :=
  "| Fixture | Edge type | Run | Precision | Recall | Confirmed precision | Inferred precision " ++
  "| Most derivations |\n|---|---|---|---|---|---|---|---|\n"

private def item (side : String) (line : String) : String :=
  match fields line with
  | ["edge", n, e, s, d] => s!"- `{n}`, {side}: {e}, {s}, derivations {d}\n"
  | ["label", n, e] => s!"- `{n}`, {side}: {e}\n"
  | _ => s!"- {side}: {line}\n"

private def diff (cur base : List String) : String := Id.run do
  let gone := base.filter (!cur.contains ·)
  let new := cur.filter (!base.contains ·)
  let of (k : String) (ls : List String) := ls.filter (kind · == k)
  let mut out := ""
  unless (of "rates" gone).isEmpty && (of "rates" new).isEmpty do
    out := out ++ header
    for k in ((of "rates" new ++ of "rates" gone).map fun l => (fields l).take 3).eraseDups do
      let absent := "\t".intercalate (k ++ List.replicate 5 "none")
      let side (ls : List String) := match ls.filter fun l => (fields l).take 3 == k with
        | [] => [absent]
        | ls => ls
      for l in side gone do out := out ++ row "baseline" l
      for l in side new do out := out ++ row "this run" l
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
    out := out ++ s!"\n**Not every fixture scored ({", ".intercalate (failed.map (s!"`{·}`"))}), " ++
      "so the numbers below cover the others only.**\n"
  out := out ++ "\n### Every fixture\n\n" ++ header
  for l in cur.filter (kind · == "rates") do out := out ++ row "this run" l
  let top := most (ok.flatMap fun (_, c) => derivations c)
  let at? := ok.findSome? fun (n, c) => ((derivations c).find? (·.2 == top)).map fun d => (n, c, d.1)
  match at? with
  | none => out := out ++ "\nNo fixture has a repo-level edge, so no derivations were counted.\n"
  | some (n, c, k) =>
    out := out ++ s!"\nMost derivations any repo-level edge has: {top}, {renderEdge k} in fixture `{n}`"
    unless c.predicted.any (·.1 == k) do out := out ++ ", which that fixture's card leaves out"
    out := out ++ s!". D1 reopens above {d1Threshold}.\n"
    if top > d1Threshold then
      out := out ++ s!"\n**Above {d1Threshold}: D1 reopens (`plan/phase-2.md`, Scope decisions).**\n"
  out := out ++ "\n### Against the baseline\n\n"
  match base with
  | none => out := out ++ "No baseline given, so nothing was compared.\n"
  | some b =>
    let b' := b.filter fun l => !failed.contains (fixtureOf l)
    if changed cur b' = [] then out := out ++ "No change against the baseline.\n"
    else out := out ++ diff cur b'
    for n in failed.filter fun n => b.any (fixtureOf · == n) do
      out := out ++ s!"\n`{n}` was not scored in this run, so it is not compared.\n"
  return out

private def cardOf (r : Result) : String :=
  match r.card with
  | .ok c => c.render r.name
  | .error e => s!"### Scorecard: fixture `{r.name}`\n\nScorer error: {e}\n"

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

private def pin (n : Nat) (labels : List RepoKey := [pinKey]) : List Result :=
  [{ name := "pin", card := checked "pin" (score (pinFiles n) labels) }]

private def pinNumbers (n : Nat) : List String :=
  match numbersAll (pin n) with
  | .ok ls => ls
  | .error _ => []

private def has (hay needle : String) : Bool := (hay.splitOn needle).length > 1

#guard pinNumbers 2 ==
  ["rates\tpin\ttoy/runtime\t1.00 (1/1)\t1.00 (1/1)\t1.00 (1/1)\tn/a\t2",
   "edge\tpin\t`a` → `b` (toy/runtime `x`)\tconfirmed\t2",
   "label\tpin\t`a` → `b` (toy/runtime `x`)"]

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

end Score.Nightly
