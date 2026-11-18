import MitosGate.Workflow.PinNode

namespace MitosGate.Workflow.CiPins

open Yaml PinNode

def suiteCommands : List String := [
  ".github/scripts/land-protection.test.sh", ".github/scripts/land-decide.test.sh",
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

def check (ci : Doc) : Except String Unit :=
  match seqAt? ci [.key "jobs", .key "checks", .key "steps"] with
  | none => .error "ci.steps"
  | some steps =>
    if approvedCondition ci && jobControls ci && suiteCommands.all (afterBuild steps) then .ok ()
    else .error "ci.schedule"

def holds (ci : Doc) : Prop :=
  ci.scalarAt? conditionPath = some (.text condition) ∧ jobControls ci = true ∧
  ∃ steps, seqAt? ci [.key "jobs", .key "checks", .key "steps"] = some steps ∧
    suiteCommands.all (afterBuild steps) = true

theorem check_sound (h : check ci = .ok ()) : holds ci := by
  unfold check at h
  cases hs : seqAt? ci [.key "jobs", .key "checks", .key "steps"] with
  | none => simp [hs] at h
  | some steps =>
    refine ⟨?_, ?_, steps, hs, ?_⟩
    all_goals
      simp only [hs] at h
      split at h <;> simp_all [approvedCondition]

theorem check_has_steps (h : check ci = .ok ()) :
    ∃ steps, seqAt? ci [.key "jobs", .key "checks", .key "steps"] = some steps := by
  obtain ⟨_, _, steps, hs, _⟩ := check_sound h
  exact ⟨steps, hs⟩

theorem check_condition (h : check ci = .ok ()) :
    ci.scalarAt? conditionPath = some (.text condition) := (check_sound h).1

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

end MitosGate.Workflow.CiPins
