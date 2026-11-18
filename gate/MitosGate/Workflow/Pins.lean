import MitosGate.Yaml
import MitosGate.Workflow.LandPins
import MitosGate.Workflow.ProtectionPins
import MitosGate.Workflow.AppTokenPins
import MitosGate.Workflow.CiPins
import MitosGate.Util

namespace MitosGate.Workflow.Pins

open Yaml PinNode

structure Inputs where
  land : Doc
  protection : Doc
  ci : Doc
  updater : Doc
  ownerPing : Doc
  otherWorkflows : List Doc

def Inputs.unprivilegedWorkflows (i : Inputs) : List Doc :=
  [i.ci, i.ownerPing] ++ i.otherWorkflows

private def ownerPingOk (d : Doc) : Bool :=
  match seqAt? d [.key "jobs", .key "issue", .key "steps"],
      seqAt? d [.key "jobs", .key "pr", .key "steps"] with
  | some [issue], some [pr] =>
    same issue pr &&
    keysAt d [.key "jobs", .key "issue", .key "steps", .idx 0] ["name", "env", "run"] &&
    (match textAt? d [.key "jobs", .key "issue", .key "steps", .idx 0, .key "run"] with
      | some command => !command.isEmpty
      | none => false) &&
    (match mapAt? d [.key "jobs", .key "issue", .key "steps", .idx 0, .key "env"] with
      | some env => !env.isEmpty
      | none => false)
  | _, _ => false

def holds (i : Inputs) : Prop :=
  LandPins.holds i.land ∧ ProtectionPins.holds i.protection i.land ∧
    AppTokenPins.holds i.land i.protection i.updater i.unprivilegedWorkflows ∧ CiPins.holds i.ci ∧ ownerPingOk i.ownerPing = true

def check (i : Inputs) : Except String Unit :=
  match LandPins.check i.land, ProtectionPins.check i.protection i.land,
      AppTokenPins.check i.land i.protection i.updater i.unprivilegedWorkflows, CiPins.check i.ci with
  | .error rule, _, _, _ => .error rule
  | _, .error rule, _, _ => .error rule
  | _, _, .error rule, _ => .error rule
  | _, _, _, .error rule => .error rule
  | .ok (), .ok (), .ok (), .ok () =>
    if ownerPingOk i.ownerPing then .ok () else .error "owner-ping.steps"

theorem check_sound (h : check i = .ok ()) : holds i := by
  cases hl : LandPins.check i.land <;>
    cases hp : ProtectionPins.check i.protection i.land <;>
    cases hm : AppTokenPins.check i.land i.protection i.updater i.unprivilegedWorkflows <;>
    cases hc : CiPins.check i.ci <;>
    simp_all [check]
  rename_i ul up um uc
  cases ul; cases up; cases um; cases uc
  exact ⟨LandPins.check_sound hl, ProtectionPins.check_sound hp,
    AppTokenPins.check_sound hm, CiPins.check_sound hc, h⟩

theorem check_no_unprivileged_mint (h : check i = .ok ()) :
    AppTokenPins.mintCount i.unprivilegedWorkflows = 0 :=
  (check_sound h).2.2.1.2.2.2.2

private def requiredNames : List String :=
  ["land.yml", "land-protection.yml", "ci.yml", "update-prs.yml", "owner-ping.yml"]

def run (root : System.FilePath) : IO UInt32 := do
  let directory := root / ".github" / "workflows"
  let entries ← try directory.readDir catch _ =>
    IO.eprintln "workflow pins: workflow directory IO error"
    return 2
  let mut files : List (String × Doc) := []
  for entry in entries.qsort (·.fileName < ·.fileName) do
    if entry.path.extension == some "yml" || entry.path.extension == some "yaml" then
      let source ← try IO.FS.readFile entry.path catch _ =>
        IO.eprintln "workflow pins: workflow file IO error"
        return 2
      match Yaml.read source with
      | .error _ =>
        IO.eprintln "workflow pins: reader-refusal"
        return 1
      | .ok doc => files := files ++ [(entry.fileName, doc)]
  if requiredNames.any (fun name => (files.lookup name).isNone) then
    IO.eprintln "workflow pins: required workflow missing"
    return 2
  let some land := files.lookup "land.yml" | return 2
  let some protection := files.lookup "land-protection.yml" | return 2
  let some ci := files.lookup "ci.yml" | return 2
  let some updater := files.lookup "update-prs.yml" | return 2
  let some ownerPing := files.lookup "owner-ping.yml" | return 2
  let inputs : Inputs := ⟨land, protection, ci, updater, ownerPing,
    (files.filter fun entry => !requiredNames.contains entry.1).map Prod.snd⟩
  match check inputs with
  | .ok () => return 0
  | .error rule =>
    IO.eprintln (ciLine ("workflow pins: refused " ++ rule))
    return 1

end MitosGate.Workflow.Pins
