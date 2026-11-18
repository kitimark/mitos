import MitosGate.Workflow.PinNode

namespace MitosGate.Workflow.ProtectionPins

open Yaml PinNode

private def readPath : List Seg := [.key "jobs", .key "read"]
private def decidePath : List Seg := [.key "jobs", .key "decide"]

private def triggers : Node := .map [
  ("push", .map [("branches", .seq [.text "main"])]),
  ("workflow_run", .map [("workflows", .seq [.text "ci"]),
    ("types", .seq [.text "completed"])]),
  ("issue_comment", .map [("types", .seq [.text "created", .text "edited"])]),
  ("workflow_dispatch", .text "")]

private def steps : Node := .seq [
  .map [
    ("uses", .text "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"),
    ("with", .map [("persist-credentials", .text "false")])],
  .map [
    ("name", .text "Mint an app token that can only read administration"),
    ("id", .text "app"),
    ("uses", .text "actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510"),
    ("with", .map [
      ("app-id", .text "${{ vars.PR_UPDATER_APP_ID }}"),
      ("private-key", .text "${{ secrets.PR_UPDATER_APP_KEY }}"),
      ("permission-administration", .text "read")])],
  .map [
    ("name", .text "Read main's protection"),
    ("env", .map [("GH_TOKEN", .text "${{ steps.app.outputs.token }}")]),
    ("run", .text ".github/scripts/land-protection.sh \"$GITHUB_REPOSITORY\" \"$RUNNER_TEMP/land-protection\"")],
  .map [
    ("uses", .text "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
    ("with", .map [
      ("name", .text "land-protection-${{ github.run_id }}-${{ github.run_attempt }}"),
      ("path", .text "${{ runner.temp }}/land-protection/read.json"),
      ("if-no-files-found", .text "error"),
      ("retention-days", .text "1")])]]

private def contains (needle value : String) : Bool :=
  Base.Text.hasSub needle.toList value.toList

private def keyMatches (p : List Seg) (test : String → Bool) : Bool :=
  p.any fun | .key k => test k | .idx _ => false

private def readerReferencesOk (leaf : Leaf) : Bool :=
  let forbidden := ["github.token", "GITHUB_TOKEN", "id-token", "write", "skip-token-revoke"]
  let keysOk := !keyMatches leaf.path fun k =>
    k == "owner" || k == "repositories" || hasIdentifierCI "secrets" k || forbidden.any (contains · k)
  keysOk && match leaf.value with
    | .text value =>
      !forbidden.any (contains · value) &&
      (!hasIdentifierCI "secrets" value ||
        (leaf.path == readPath ++ [.key "steps", .idx 1, .key "with", .key "private-key"] &&
          value == "${{ secrets.PR_UPDATER_APP_KEY }}")) &&
      (!contains "steps.app.outputs.token" value ||
        (leaf.path == readPath ++ [.key "steps", .idx 2, .key "env", .key "GH_TOKEN"] &&
          value == "${{ steps.app.outputs.token }}")) &&
      !(contains "${{" value && contains "github.event" value)
    | _ => true

private def decideIsKeyless (land : Doc) : Bool :=
  match land.root.get? decidePath with
  | some (.map entries) =>
    let forbidden := ["github-app-token", "app-id", "private-key", "id-token", "write"]
    (.map entries : Node).leaves.all fun leaf =>
      !keyMatches leaf.path (fun k => k == "environment" || hasIdentifierCI "secrets" k || forbidden.any (contains · k)) &&
      match leaf.value with
      | .text value => !hasIdentifierCI "secrets" value && !forbidden.any (contains · value)
      | _ => true
  | _ => false

private def environment (protection : Doc) : Bool :=
  decide (protection.scalarAt? (readPath ++ [.key "environment"]) = some (.text "trusted"))

private def topology (protection : Doc) : Bool :=
  keysAt protection [] ["name", "on", "permissions", "jobs"] &&
    nodeAt protection [.key "name"] (.text "land-protection") &&
    keysAt protection [.key "jobs"] ["read"] &&
    keysAt protection readPath ["if", "runs-on", "timeout-minutes", "environment", "permissions", "steps"]

private def permissions (protection : Doc) : Bool :=
  nodeAt protection [.key "permissions"] (.map []) &&
    nodeAt protection (readPath ++ [.key "permissions"]) (.map [("contents", .text "read")])

private def execution (protection : Doc) : Bool :=
  nodeAt protection (readPath ++ [.key "runs-on"]) (.text "ubuntu-24.04") &&
    nodeAt protection (readPath ++ [.key "timeout-minutes"]) (.text "5") &&
    nodeAt protection (readPath ++ [.key "steps"]) steps

private def decideBoundary (land : Doc) : Bool :=
  decideIsKeyless land &&
    nodeAt land (decidePath ++ [.key "permissions", .key "actions"]) (.text "read")

private def triggerPair (protection land : Doc) : Bool :=
  nodeAt protection [.key "on"] triggers && nodeAt land [.key "on"] triggers

private def conditionPair (protection land : Doc) : Bool :=
  match textAt? protection (readPath ++ [.key "if"]) with
  | none => false
  | some readIf => !readIf.isEmpty && textAt? land (decidePath ++ [.key "if"]) == some readIf

def holds (protection land : Doc) : Prop :=
  protection.scalarAt? (readPath ++ [.key "environment"]) = some (.text "trusted") ∧
    topology protection = true ∧ permissions protection = true ∧ execution protection = true ∧
    protection.leaves.all readerReferencesOk = true ∧ decideBoundary land = true ∧
    triggerPair protection land = true ∧ conditionPair protection land = true

def check (protection land : Doc) : Except String Unit :=
  if !environment protection then .error "protection.environment"
  else if !topology protection then .error "protection.jobs"
  else if !permissions protection then .error "protection.permissions"
  else if !execution protection then .error "protection.steps"
  else if !protection.leaves.all readerReferencesOk then .error "protection.references"
  else if !decideBoundary land then .error "protection.decide"
  else if !triggerPair protection land then .error "protection.triggers"
  else if !conditionPair protection land then .error "protection.condition"
  else .ok ()

theorem check_sound (h : check protection land = .ok ()) : holds protection land := by
  unfold check at h
  repeat' split at h <;> simp_all [holds, environment]

theorem environment_of_check (h : check protection land = .ok ()) :
    protection.scalarAt? [.key "jobs", .key "read", .key "environment"] =
      some (.text "trusted") := (check_sound h).1

private def fixtureRoot (environment : Node := .text "trusted") (stepNodes : Node := steps)
    (readIf : String := "main") : Node :=
  .map [("name", .text "land-protection"), ("on", triggers), ("permissions", .map []),
    ("jobs", .map [("read", .map [
      ("if", .text readIf), ("runs-on", .text "ubuntu-24.04"), ("timeout-minutes", .text "5"),
      ("environment", environment), ("permissions", .map [("contents", .text "read")]),
      ("steps", stepNodes)])])]

private def landFixture (readIf : String := "main") (actions : String := "read") : Node :=
  .map [("on", triggers), ("jobs", .map [("decide", .map [
    ("if", .text readIf), ("permissions", .map [("actions", .text actions)])])])]

private def refusal? (n : Node) (land : Node := landFixture) : Option String :=
  match Doc.ofNode n, Doc.ofNode land with
  | .error _, _ | _, .error _ => some "reader"
  | .ok d, .ok land => match check d land with
    | .ok () => none
    | .error reason => some reason

example : refusal? fixtureRoot = none := by decide +kernel
example : refusal? (fixtureRoot (.map [("name", .text "trusted")])) =
    some "protection.environment" := by decide +kernel
example : refusal? (fixtureRoot (.text "trusted") (.seq [])) =
    some "protection.steps" := by decide +kernel
example : refusal? (fixtureRoot (readIf := "github.token")) (landFixture "github.token") =
    some "protection.references" := by decide +kernel
example : refusal? fixtureRoot (landFixture (actions := "write")) =
    some "protection.decide" := by decide +kernel
example : refusal? (fixtureRoot (readIf := "${{ SeCrEtS['KEY'] }}"))
    (landFixture "${{ SeCrEtS['KEY'] }}") = some "protection.references" := by decide +kernel
example : refusal? (fixtureRoot (readIf := "${{ toJSON(secrets) }}"))
    (landFixture "${{ toJSON(secrets) }}") = some "protection.references" := by decide +kernel

private def keylessFixture (value : String) : Node :=
  .map [("on", triggers), ("jobs", .map [("decide", .map [
    ("if", .text "main"), ("permissions", .map [("actions", .text "read")]),
    ("env", .map [("EXTRA", .text value)])])])]

example : refusal? fixtureRoot (keylessFixture "${{ SeCrEtS['KEY'] }}") =
    some "protection.decide" := by decide +kernel
example : refusal? fixtureRoot (keylessFixture "${{ toJSON(secrets) }}") =
    some "protection.decide" := by decide +kernel
example : refusal? fixtureRoot (keylessFixture "secretsauce other_secrets") = none := by decide +kernel

end MitosGate.Workflow.ProtectionPins
