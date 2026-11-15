import Diff.Compare
import Diff.Plugin
import Diff.Triage

namespace Diff

structure CaseReport where
  case : String
  module : String
  version : String
  pluginKeys : Keys
  goKeys : Keys
  unread : List UnreadLine

def CaseReport.findings (r : CaseReport) : List Finding :=
  (compare r.pluginKeys r.goKeys).map (⟨r.case, ·⟩)

def findings (reports : List CaseReport) : List Finding := reports.flatMap (·.findings)

structure Verdict where
  untriaged : List Finding
  stale : List Triage

def verdict (reports : List CaseReport) (triage : List Triage) : Verdict where
  untriaged := (findings reports).filter fun f => (Triage.issuesFor triage f).isEmpty
  stale := triage.filter fun t => !(findings reports).contains t.finding

def Verdict.clean (v : Verdict) : Bool := v.untriaged.isEmpty && v.stale.isEmpty

theorem verdict_clean {reports : List CaseReport} {triage : List Triage} :
    (verdict reports triage).clean = true ↔
      (∀ f ∈ findings reports, ∃ t ∈ triage, t.finding = f) ∧
      (∀ t ∈ triage, t.finding ∈ findings reports) := by
  simp [Verdict.clean, verdict, Triage.issuesFor, List.filter_eq_nil_iff]

def Mismatch.describe : Mismatch → String
  | .onlyIn .go directive path => s!"{directive.name} `{path}`: only in Go"
  | .onlyIn .plugin directive path => s!"{directive.name} `{path}`: only in the plugin"
  | .order directive => s!"{directive.name}: shared paths in another order"

def Keys.count (k : Keys) : Nat := k.modules.length + k.requires.length

def tsv (fields : List String) : String := s!"`{String.intercalate "\t" fields}`"

def render (goVersion : String) (reports : List CaseReport) (triage : List Triage) : String :=
  Id.run do
    let v := verdict reports triage
    let mut out := "## go.mod differential run\n\n"
    out := out ++ s!"`GoMod.extractor` against `go mod edit -json` of {goVersion}, which reads "
    out := out ++ s!"each file with the strict parser `modfile.Parse`. {reports.length} pinned modules.\n\n"
    out := out ++ "| Case | Module | Plugin facts | Go facts | Mismatches | Triaged | Lines outside the subset |\n"
    out := out ++ "|---|---|---|---|---|---|---|\n"
    for r in reports do
      let fs := r.findings
      let triaged := fs.filter fun f => !(Triage.issuesFor triage f).isEmpty
      out := out ++ s!"| {r.case} | `{r.module}@{r.version}` | {r.pluginKeys.count} | {r.goKeys.count} "
      out := out ++ s!"| {fs.length} | {triaged.length} | {r.unread.length} |\n"
    out := out ++ "\n"
    if v.untriaged.isEmpty then out := out ++ "Untriaged mismatches: none.\n"
    else
      out := out ++ "Untriaged mismatches, as `triage.tsv` lines with the issue to fill in:\n"
      for f in v.untriaged do out := out ++ s!"- {tsv (f.fields ++ ["#?"])}\n"
    if v.stale.isEmpty then out := out ++ "Stale triage lines: none.\n"
    else
      out := out ++ "Stale triage lines, which match no mismatch:\n"
      for t in v.stale do out := out ++ s!"- {tsv (t.finding.fields ++ [s!"#{t.issue}"])}\n"
    for r in reports do
      out := out ++ s!"\n### {r.case}\n\n"
      if r.findings.isEmpty then out := out ++ "No mismatch.\n"
      for f in r.findings do
        let issues := (Triage.issuesFor triage f).map (s!"#{·}")
        let status := if issues.isEmpty then "untriaged" else String.intercalate ", " issues
        out := out ++ s!"- {f.mismatch.describe} ({status})\n"
      if r.unread.isEmpty then out := out ++ "\nNo line outside the subset.\n"
      else
        out := out ++ "\nLines outside the subset:\n\n"
        for l in r.unread do out := out ++ s!"- {l.number}: `{l.text}`\n"
    return out

end Diff
