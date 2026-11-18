import MitosGate.Workflow.PinNode
import MitosGate.Workflow.Placement
import MitosGate.Workflow.AppTokenPins

namespace MitosGate.Workflow.LandPins

open Yaml PinNode

private def jp (job : String) (path : List Seg := []) : List Seg :=
  [.key "jobs", .key job] ++ path

private def sp (job : String) (index : Nat) (path : List Seg := []) : List Seg :=
  jp job ([.key "steps", .idx index] ++ path)

private def has (needle value : String) : Bool := Base.Text.hasSub needle.toList value.toList

private def onlyRefs (d : Doc) (mentions : String → Bool) (paths : List (List Seg)) : Bool :=
  let found := d.leaves.filter fun leaf => match leaf.value with
    | .text value => mentions value
    | _ => false
  found.length == paths.length && found.all (fun leaf => paths.contains leaf.path)

private def wordChar (c : Char) : Bool := c.isAlphanum || c == '_'

private def callsGh (value : String) : Bool := go false value.toList
where
  go : Bool → List Char → Bool
    | _, [] => false
    | previous, 'g' :: 'h' :: rest =>
      (!previous && !(rest.head?.map wordChar |>.getD false)) || go true ('h' :: rest)
    | _, c :: rest => go (wordChar c) rest

private def forbidden (d : Doc) (job : String) (tokens : List String) : Bool :=
  d.leaves.all fun leaf => !((jp job).isPrefixOf leaf.path) ||
    !(tokens.any fun token =>
      leaf.path.any (fun | .key key => has token key | _ => false) ||
      match leaf.value with | .text value => has token value | _ => false)

private def keyless (d : Doc) (job : String) : Bool :=
  d.leaves.all fun leaf => !((jp job).isPrefixOf leaf.path) ||
    (!leaf.path.any (fun | .key key => hasIdentifierCI "secrets" key | _ => false) &&
      match leaf.value with | .text value => !hasIdentifierCI "secrets" value | _ => true)

private def decideIf : String :=
  "github.ref == 'refs/heads/main' && (\n  github.event_name == 'push' || github.event_name == 'workflow_dispatch' ||\n  (github.event_name == 'workflow_run' &&\n    github.event.workflow_run.event == 'pull_request' &&\n    github.event.workflow_run.head_repository.full_name == github.repository) ||\n  (github.event_name == 'issue_comment' && github.event.issue.pull_request &&\n    github.event.comment.user.login == github.repository_owner))"

private def permissions (names : List String) : Node :=
  .map (names.map fun name => (name, .text "read"))

private def concurrency (group : String) : Node :=
  .map [("group", .text group), ("cancel-in-progress", .text "false")]

private def host (d : Doc) (job minutes : String) : Bool :=
  nodeAt d (jp job [.key "runs-on"]) (.text "ubuntu-24.04") &&
  nodeAt d (jp job [.key "timeout-minutes"]) (.text minutes)

private def cachePrefix : String :=
  "lean-${{ hashFiles('core/lake-manifest.json', 'eval/diff/lake-manifest.json', 'eval/diff/lean-toolchain', 'eval/mutants/lake-manifest.json', 'eval/mutants/lean-toolchain', 'eval/score/lake-manifest.json', 'eval/score/lean-toolchain', 'examples/acme/lake-manifest.json', 'examples/acme/lean-toolchain', 'lake-manifest.json', 'lean-toolchain') }}-"

private def cacheInputs : Node := .map [
  ("path", .text "~/.elan\n.lake\ncore/.lake\nexamples/acme/.lake\neval/score/.lake\neval/mutants/.lake\n"),
  ("key", .text (cachePrefix ++ "${{ github.sha }}")), ("restore-keys", .text cachePrefix)]

private def decideSteps : Node := .seq [
  .map [("id", .text "t0"), ("run", .text "echo \"at=$(date +%s)\" >> \"$GITHUB_OUTPUT\"")],
  .map [
    ("uses", .text "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"),
    ("with", .map [("fetch-depth", .text "0"), ("persist-credentials", .text "false")])],
  .map [
    ("uses", .text "actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830"),
    ("with", cacheInputs)],
  .map [("run", .text ".github/scripts/install-elan.sh")],
  .map [("run", .text ".github/scripts/install-toolchains.sh")],
  .map [("run", .text "lake build mitos-gate")],
  .map [
    ("name", .text "Decide (prints only)"),
    ("env", .map [
      ("GH_TOKEN", .text "${{ github.token }}"),
      ("LAND_T0", .text "${{ steps.t0.outputs.at }}"),
      ("LAND_EVENT", .text "${{ github.event_name }}"),
      ("LAND_EVENT_HEAD", .text "${{ github.event.workflow_run.head_sha }}"),
      ("LAND_EVENT_CONCLUSION", .text "${{ github.event.workflow_run.conclusion }}"),
      ("LAND_EVENT_PR", .text "${{ github.event.issue.number }}"),
      ("LAND_EVENT_COMMENT", .text "${{ github.event.comment.id }}")]),
    ("run", .text ".github/scripts/land-decide.sh \"$GITHUB_REPOSITORY\" \"$LAND_DASHBOARD\" \"$RUNNER_TEMP/land\"")],
  .map [
    ("if", .text "always()"),
    ("uses", .text "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
    ("with", .map [
      ("name", .text "land-record-${{ github.run_id }}-${{ github.run_attempt }}"),
      ("path", .text "${{ runner.temp }}/land/record.json"),
      ("retention-days", .text "90")])],
  .map [
    ("if", .text "always()"),
    ("uses", .text "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
    ("with", .map [
      ("name", .text "land-reads-${{ github.run_id }}-${{ github.run_attempt }}"),
      ("path", .text "${{ runner.temp }}/land/reads"),
      ("retention-days", .text "7")])]]

private def topology (d : Doc) : Bool :=
  keysAt d [] ["name", "on", "permissions", "jobs"] &&
  nodeAt d [.key "name"] (.text "land") &&
  nodeAt d [.key "permissions"] (.map []) &&
  (d.root.get? [.key "concurrency"]).isNone &&
  keysAt d (jp "decide") ["if", "runs-on", "timeout-minutes", "concurrency", "permissions", "env", "steps"]

private def decideJob (d : Doc) : Bool :=
  host d "decide" "15" &&
  nodeAt d (jp "decide" [.key "if"]) (.text decideIf) &&
  keysAt d (jp "decide" [.key "env"]) ["LAND_DASHBOARD"] &&
  (match textAt? d (jp "decide" [.key "env", .key "LAND_DASHBOARD"]) with
    | some value => !has "${{" value
    | none => false) &&
  nodeAt d (jp "decide" [.key "permissions"])
    (permissions ["contents", "pull-requests", "issues", "checks", "actions"]) &&
  nodeAt d (jp "decide" [.key "concurrency"]) (concurrency "land-decide") &&
  keyless d "decide" &&
  forbidden d "decide" ["write", "environment", "github-app-token", "app-id", "private-key", "id-token"] &&
  nodeAt d (jp "decide" [.key "steps"]) decideSteps

private def globalScope (d : Doc) : Bool :=
  onlyRefs d (has "github.token") [sp "decide" 6 [.key "env", .key "GH_TOKEN"]] &&
  onlyRefs d (has "steps.app.outputs.token") [] &&
  onlyRefs d (hasIdentifierCI "secrets") [] &&
  d.leaves.all (fun leaf =>
    !leaf.path.any (fun | .key key => hasIdentifierCI "secrets" key | _ => false)) &&
  d.leaves.all (fun leaf => !leaf.path.contains (.key "LAND_MERGE")) &&
  d.leaves.all (fun leaf => match leaf.path, leaf.value with
    | [.key "jobs", .key _, .key "steps", .idx _, .key "run"], .text value =>
      !has "\n" value && !has "${{" value
    | [.key "jobs", .key _, .key "steps", .idx _, .key "run"], _ => false
    | _, _ => true) &&
  d.leaves.all (fun leaf => match leaf.value with
    | .text value => !callsGh value &&
      (!(has "${{" value && has "github.event." value) ||
        [sp "decide" 6 [.key "env", .key "LAND_EVENT_HEAD"],
         sp "decide" 6 [.key "env", .key "LAND_EVENT_CONCLUSION"],
         sp "decide" 6 [.key "env", .key "LAND_EVENT_PR"],
         sp "decide" 6 [.key "env", .key "LAND_EVENT_COMMENT"]].contains leaf.path)
    | _ => true) && Workflow.placementOk d

def holds (d : Doc) : Prop :=
  keysAt d [.key "jobs"] ["decide"] = true ∧ AppTokenPins.mintCount [d] = 0 ∧
    topology d = true ∧ decideJob d = true ∧ globalScope d = true

def check (d : Doc) : Except String Unit :=
  if !keysAt d [.key "jobs"] ["decide"] then .error "land.shape"
  else if AppTokenPins.mintCount [d] ≠ 0 then .error "land.mint"
  else if !topology d then .error "land.shape"
  else if !decideJob d then .error "land.decide"
  else if !globalScope d then .error "land.scope"
  else .ok ()

theorem check_sound (h : check d = .ok ()) : holds d := by
  unfold check at h
  repeat' split at h <;> simp_all [holds]

theorem check_decide_only (h : check d = .ok ()) :
    keysAt d [.key "jobs"] ["decide"] = true := (check_sound h).1

theorem check_no_land_mint (h : check d = .ok ()) :
    AppTokenPins.mintCount [d] = 0 := (check_sound h).2.1

example : callsGh "gh" = true := by decide +kernel
example : callsGh "echo;gh;exit" = true := by decide +kernel
example : callsGh "weight github.token" = false := by decide +kernel

private def refusal? (d : Doc) : Option String :=
  match check d with | .ok () => none | .error reason => some reason

example : refusal? ⟨.map [("jobs", .map [("decide", .map []), ("apply", .map [])])],
    by decide +kernel⟩ = some "land.shape" := by decide +kernel
example : refusal? ⟨.map [("jobs", .map [("decide", .map []), ("report", .map [])])],
    by decide +kernel⟩ = some "land.shape" := by decide +kernel

end MitosGate.Workflow.LandPins
