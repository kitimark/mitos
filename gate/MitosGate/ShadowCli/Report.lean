import MitosGate.ShadowCli.Read

namespace MitosGate.ShadowCli

open Shadow
open Land (Sha Step Stop Plan plan queueOf)

structure Window where
  merges : List Merge
  records : List (String × Except String Run)
  recorded : List Nat
  jobs : List Job
  updaterCiRuns : Nat

def short (s : Sha) : String := (s.take 7).toString

def stopText : Stop → String
  | .held => "held"
  | .unenforced => "unenforced"
  | .notEligible => "notEligible"
  | .stuck why => s!"stuck {LandCli.stuckName why}"
  | .noEntry => "noEntry"

def stepText : Step → String
  | .enter _ => "enter"
  | .wait p => s!"wait for #{p}"
  | .awaitPush _ => "awaitPush"
  | .awaitGate _ => "awaitGate"
  | .merge _ => "merge"
  | .present _ => "present"
  | .stop why => s!"stop {stopText why}"

def readingText : Reading → String
  | .asRead s => stepText s
  | .oneWordAway s => s!"one word away, then {stepText s}"

def clauseName : Clause → String
  | .updatable => "updatable"
  | .enforced => "enforced"
  | .covered => "covered"
  | .reviewed => "reviewed"
  | .rest => "rest"

def findingName : Finding → String
  | .agrees => "agrees"
  | .waits => "waits"
  | .disagrees _ => "disagrees"
  | .otherTree => "other tree"
  | .blind => "blind"

def headText : Head → List String
  | .same => []
  | .replayedAsPlanned => ["its replay merged"]
  | .replayedOtherwise => ["another tree merged"]
  | .other => ["another head merged"]

def seatText : Seat → String
  | .unseen => "unseen"
  | .unlisted run => s!"not listed in run {run}"
  | .sat s =>
    let lacking := if s.lacks.isEmpty then "" else
      ", lacks " ++ ", ".intercalate (s.lacks.map clauseName)
    "; ".intercalate <|
      [readingText s.reading ++ lacking] ++ headText s.head ++
      [s!"record of run {s.run}, {s.age} s old"] ++
      (if s.updaterPushes == 0 then [] else [s!"{s.updaterPushes} updater pushes"]) ++
      (if s.authorKnown then [] else ["no author"])

def mergeLine (rs : List Record) (m : Merge) : String :=
  let s := seat m rs
  s!"#{m.pr} at {short m.head}: {findingName (finding s)}. {seatText s}"

def spreadText (s : Spread) : String := s!"{s.median} ({s.min}, p90 {s.p90}, {s.max})"

def pushes (rs : List Record) : Nat :=
  (rs.filterMap fun r => match plan (queueOf r.prs) with
    | .push p e x => some (p, e, x)
    | .idle => none).eraseDups.length

def costLine (rs : List Record) : String :=
  let cs := rs.map (·.cost)
  let of (f : Cost → Nat) := spreadText (spread (cs.map f))
  s!"decide (s): total {of fun c => c.setup + c.fetch + c.snapshot + c.decide}, " ++
    s!"setup {of (·.setup)}, fetch {of (·.fetch)}, snapshot {of (·.snapshot)}, " ++
    s!"decide {of (·.decide)}; n={rs.length}"

def readsLine (rs : List Record) : String :=
  s!"reads: {spreadText (spread (rs.map (·.cost.reads)))} a run; " ++
    s!"peak {peak 3600 (rs.map fun r => (seconds r.read, r.cost.reads))} in one hour"

def runsLine (w : Window) (runs : List Run) : String :=
  let count (p : Trigger → Bool) := (runs.filter fun r => p r.trigger).length
  let gate (cancelled : Bool) := count fun
    | .gateDone _ c => !cancelled || c == "cancelled"
    | _ => false
  let superseded := w.jobs.filter fun j => j.conclusion == "cancelled" && !w.recorded.contains j.id
  let filtered := w.jobs.filter (·.conclusion == "skipped")
  s!"runs: mainMoved {count (· == .mainMoved)}, gateDone {gate false} (cancelled {gate true}), " ++
    s!"comment {count fun | .comment .. => true | _ => false}, " ++
    s!"dispatch {count (· == .dispatch)}; " ++
    s!"{superseded.length} superseded while pending, {filtered.length} skipped by the filter"

def report (w : Window) : List String :=
  let runs := w.records.filterMap (·.2.toOption)
  let decided := runs.filterMap fun | .decided r => some r | _ => none
  let refused := runs.filter fun | .refused .. => true | _ => false
  let skipped := runs.filter fun | .skipped .. => true | _ => false
  let bad := w.records.filterMap fun (f, r) => match r with
    | .error e => some (f, e)
    | .ok _ => none
  let drift := bad.filter (·.2.startsWith drifted)
  let unreadable := bad.filter (!·.2.startsWith drifted)
  let t := tally w.merges decided
  [s!"shadow: {w.merges.length} merges, {w.records.length} records, {refused.length} refused, " ++
    s!"{skipped.length} skipped, {drift.length} drifted, {unreadable.length} unreadable"] ++
  drift.map (fun (f, e) => s!"record {f}: {e}") ++
  unreadable.map (fun (f, e) => s!"record {f}: unreadable: {e}") ++
  (w.merges.mergeSort fun a b => b.time < a.time || (b.time == a.time && b.pr ≤ a.pr)).map
    (mergeLine decided) ++
  [s!"merges: agrees {t.agrees}, waits {t.waits}, disagrees {t.disagrees}, " ++
    s!"other tree {t.otherTree}, blind {t.blind}; a word was assumed for {t.assumed}; " ++
    s!"no author {t.noAuthor}; updater pushes {t.updaterPushes}",
   s!"pushes: the updater started {w.updaterCiRuns} ci runs; " ++
    s!"the plans name {pushes decided} distinct pushes",
   costLine decided, readsLine decided, runsLine w runs]

end MitosGate.ShadowCli
