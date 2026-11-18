import MitosGate.Workflow.PinNode

namespace MitosGate.Workflow.CiPins

open Yaml PinNode

def suiteCommands : List String := [
  ".github/scripts/land-protection.test.sh", ".github/scripts/land-decide.test.sh",
  ".github/scripts/land-apply.test.sh", ".github/scripts/land-report.test.sh",
  ".github/scripts/app-token.test.sh"]

private def lower (s : String) : String :=
  String.ofList (s.toList.map fun c =>
    if 'A' ≤ c && c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c)

private def runIs (step : Node) (command : String) : Bool :=
  match step with
  | .map entries => entries.any fun (key, value) => lower key == "run" &&
      match value with | .text text => text == command | _ => false
  | _ => false

private def commandIndices (steps : List Node) (command : String) : List Nat :=
  (steps.zipIdx.filter fun (step, _) => runIs step command).map Prod.snd

private def unconditional (step : Node) : Bool :=
  match step with
  | .map entries =>
    (match step.get? [.key "run"] with | some (.text _) => true | _ => false) &&
    entries.all (fun (key, value) =>
      ["name", "run"].contains key && match value with | .text _ => true | _ => false)
  | _ => false

private def afterBuild (steps : List Node) (command : String) : Bool :=
  match commandIndices steps "lake build", commandIndices steps command with
  | [build], [test] =>
    decide (build < test) &&
      ((steps[build]?).map unconditional |>.getD false) &&
      ((steps[test]?).map unconditional |>.getD false)
  | _, _ => false

def conditionPath : List Seg := [.key "jobs", .key "checks", .key "if"]

def condition : String :=
  "github.event_name == 'push' || (github.event_name == 'pull_request' &&\n github.event.action != 'labeled' &&\n github.event.action != 'unlabeled')"

private def approvedCondition (ci : Doc) : Bool :=
  decide (ci.scalarAt? conditionPath = some (.text condition))

private def jobControls (ci : Doc) : Bool :=
  keysAt ci [.key "jobs", .key "checks"]
    ["if", "runs-on", "timeout-minutes", "permissions", "steps"] &&
  match mapAt? ci [] with
  | some entries => entries.all fun (key, _) => !["defaults", "env"].contains (lower key)
  | none => false

private def prTypes : List String :=
  ["opened", "synchronize", "reopened", "labeled", "unlabeled"]

private def textSequence? : List Node → Option (List String)
  | [] => some []
  | .text value :: rest => (textSequence? rest).map (value :: ·)
  | _ => none

private def exactTextSet (actual expected : List String) : Bool :=
  actual.length == expected.length && expected.all actual.contains

private def approvedTriggers (ci : Doc) : Bool :=
  keysAt ci [.key "on"] ["push", "pull_request"] &&
  keysAt ci [.key "on", .key "push"] ["branches"] &&
  nodeAt ci [.key "on", .key "push", .key "branches"] (.seq [.text "main"]) &&
  keysAt ci [.key "on", .key "pull_request"] ["types"] &&
  match seqAt? ci [.key "on", .key "pull_request", .key "types"] >>= textSequence? with
  | some types => exactTextSet types prTypes
  | none => false

def TriggerCoverage (ci : Doc) : Prop :=
  keysAt ci [.key "on"] ["push", "pull_request"] = true ∧
  keysAt ci [.key "on", .key "push"] ["branches"] = true ∧
  nodeAt ci [.key "on", .key "push", .key "branches"] (.seq [.text "main"]) = true ∧
  keysAt ci [.key "on", .key "pull_request"] ["types"] = true ∧
  ∃ types : List String,
    seqAt? ci [.key "on", .key "pull_request", .key "types"] =
      some (types.map Node.text) ∧ types.length = 5 ∧
    "opened" ∈ types ∧ "synchronize" ∈ types ∧ "reopened" ∈ types ∧
    "labeled" ∈ types ∧ "unlabeled" ∈ types

private theorem textSequence?_sound (h : textSequence? nodes = some types) :
    nodes = types.map Node.text := by
  induction nodes generalizing types with
  | nil => simpa [textSequence?] using h
  | cons node rest ih =>
    cases node with
    | text value =>
      cases hs : textSequence? rest with
      | none => simp [textSequence?, hs] at h
      | some values =>
        simp [textSequence?, hs] at h
        subst types
        simp [ih hs]
    | seq _ => simp [textSequence?] at h
    | map _ => simp [textSequence?] at h

private theorem approvedTriggers_sound (h : approvedTriggers ci = true) :
    TriggerCoverage ci := by
  simp only [approvedTriggers, Bool.and_eq_true] at h
  obtain ⟨⟨⟨⟨ho, hp⟩, hb⟩, hr⟩, ht⟩ := h
  cases hs : seqAt? ci [.key "on", .key "pull_request", .key "types"] with
  | none => simp [hs] at ht
  | some nodes =>
    cases hd : textSequence? nodes with
    | none => simp [hs, hd] at ht
    | some types =>
      refine ⟨ho, hp, hb, hr, types, ?_, ?_⟩
      · simpa [textSequence?_sound hd] using hs
      · simpa [hs, hd, exactTextSet, prTypes] using ht

def check (ci : Doc) : Except String Unit :=
  match seqAt? ci [.key "jobs", .key "checks", .key "steps"] with
  | none => .error "ci.steps"
  | some steps =>
    if !approvedTriggers ci then .error "ci.trigger"
    else if approvedCondition ci && jobControls ci && suiteCommands.all (afterBuild steps) then .ok ()
    else .error "ci.schedule"

def holds (ci : Doc) : Prop :=
  TriggerCoverage ci ∧
  ci.scalarAt? conditionPath = some (.text condition) ∧ jobControls ci = true ∧
  ∃ steps, seqAt? ci [.key "jobs", .key "checks", .key "steps"] = some steps ∧
    suiteCommands.all (afterBuild steps) = true

theorem check_sound (h : check ci = .ok ()) : holds ci := by
  unfold check at h
  cases hs : seqAt? ci [.key "jobs", .key "checks", .key "steps"] with
  | none => simp [hs] at h
  | some steps =>
    refine ⟨approvedTriggers_sound ?_, ?_, ?_, steps, hs, ?_⟩
    all_goals
      simp only [hs] at h
      split at h <;> simp_all [approvedCondition]

theorem check_triggers (h : check ci = .ok ()) : TriggerCoverage ci := (check_sound h).1

theorem check_has_steps (h : check ci = .ok ()) :
    ∃ steps, seqAt? ci [.key "jobs", .key "checks", .key "steps"] = some steps := by
  obtain ⟨_, _, _, steps, hs, _⟩ := check_sound h
  exact ⟨steps, hs⟩

theorem check_condition (h : check ci = .ok ()) :
    ci.scalarAt? conditionPath = some (.text condition) := (check_sound h).2.1

private def runStep (command : String) : Node := .map [("run", .text command)]

example : afterBuild [runStep "lake build", runStep ".github/scripts/app-token.test.sh"]
    ".github/scripts/app-token.test.sh" = true := by decide +kernel
example : afterBuild [runStep ".github/scripts/app-token.test.sh", runStep "lake build"]
    ".github/scripts/app-token.test.sh" = false := by decide +kernel
example : afterBuild [runStep "lake build", runStep ".github/scripts/app-token.test.sh",
    runStep ".github/scripts/app-token.test.sh"] ".github/scripts/app-token.test.sh" = false := by
  decide +kernel
example : unconditional (.map [("run", .text "lake build"), ("if", .text "false")]) = false := by
  decide +kernel
example : exactTextSet prTypes prTypes = true := by decide +kernel
example : exactTextSet ["unlabeled", "labeled", "reopened", "synchronize", "opened"]
    prTypes = true := by decide +kernel
example : exactTextSet ["opened", "reopened", "labeled", "unlabeled"] prTypes = false := by
  decide +kernel
example : exactTextSet ["opened", "opened", "reopened", "labeled", "unlabeled"]
    prTypes = false := by decide +kernel
example : textSequence? [.text "opened", .map []] = none := by decide +kernel

end MitosGate.Workflow.CiPins
