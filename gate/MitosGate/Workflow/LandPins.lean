import MitosGate.Workflow.PinNode
import MitosGate.Workflow.Placement

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

def applyPath : List Seg := [.key "jobs", .key "apply", .key "if"]

def applyIf : String :=
  "github.ref == 'refs/heads/main' && github.run_attempt == '1' && needs.decide.outputs.pr != ''"

private def decideIf : String :=
  "github.ref == 'refs/heads/main' && (\n  github.event_name == 'push' || github.event_name == 'workflow_dispatch' ||\n  (github.event_name == 'workflow_run' &&\n    github.event.workflow_run.event == 'pull_request' &&\n    github.event.workflow_run.head_repository.full_name == github.repository) ||\n  (github.event_name == 'issue_comment' && github.event.issue.pull_request &&\n    github.event.comment.user.login == github.repository_owner))"

private def checkout : Node := .map [
  ("uses", .text "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"),
  ("with", .map [("sparse-checkout", .text ".github/scripts"), ("persist-credentials", .text "false")])]

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

private def topology (d : Doc) : Bool :=
  keysAt d [] ["name", "on", "permissions", "env", "jobs"] &&
  nodeAt d [.key "name"] (.text "land") &&
  keysAt d [.key "jobs"] ["decide", "apply", "report"] &&
  nodeAt d [.key "permissions"] (.map []) &&
  (d.root.get? [.key "concurrency"]).isNone &&
  keysAt d (jp "decide") ["if", "runs-on", "timeout-minutes", "concurrency", "permissions", "env", "outputs", "steps"] &&
  keysAt d (jp "apply") ["needs", "if", "runs-on", "timeout-minutes", "environment", "concurrency", "permissions", "outputs", "steps"] &&
  keysAt d (jp "report") ["needs", "if", "runs-on", "timeout-minutes", "permissions", "steps"]

private def decideJob (d : Doc) : Bool :=
  host d "decide" "15" &&
  nodeAt d (jp "decide" [.key "if"]) (.text decideIf) &&
  keysAt d (jp "decide" [.key "env"]) ["LAND_DASHBOARD"] &&
  (match textAt? d (jp "decide" [.key "env", .key "LAND_DASHBOARD"]) with
    | some value => !has "${{" value
    | none => false) &&
  nodeAt d (jp "decide" [.key "outputs"]) (.map (
    ["pr", "head", "approval", "digest", "requires_spec", "answers"].map fun name =>
      (name, .text ("${{ steps.decide.outputs." ++ name ++ " }}")))) &&
  nodeAt d (jp "decide" [.key "permissions"])
    (permissions ["contents", "pull-requests", "issues", "checks", "actions"]) &&
  nodeAt d (jp "decide" [.key "concurrency"]) (concurrency "land-decide") &&
  keyless d "decide" &&
  forbidden d "decide" ["write", "environment", "github-app-token", "app-id", "private-key", "id-token"] &&
  (match seqAt? d (jp "decide" [.key "steps"]) with
    | some steps => steps.length == 9
    | none => false) &&
  nodeAt d (sp "decide" 0) (.map [("id", .text "t0"), ("run", .text "echo \"at=$(date +%s)\" >> \"$GITHUB_OUTPUT\"")]) &&
  nodeAt d (sp "decide" 1) (.map [
    ("uses", .text "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"),
    ("with", .map [("fetch-depth", .text "0"), ("persist-credentials", .text "false")])]) &&
  keysAt d (sp "decide" 2) ["uses", "with"] &&
  nodeAt d (sp "decide" 2 [.key "uses"]) (.text "actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830") &&
  nodeAt d (sp "decide" 2 [.key "with"]) cacheInputs &&
  nodeAt d (sp "decide" 3) (.map [("run", .text ".github/scripts/install-elan.sh")]) &&
  nodeAt d (sp "decide" 4) (.map [("run", .text ".github/scripts/install-toolchains.sh")]) &&
  nodeAt d (sp "decide" 5) (.map [("run", .text "lake build mitos-gate")]) &&
  nodeAt d (sp "decide" 6) (.map [
    ("name", .text "Decide"), ("id", .text "decide"),
    ("env", .map [("GH_TOKEN", .text "${{ github.token }}"),
      ("LAND_T0", .text "${{ steps.t0.outputs.at }}"),
      ("LAND_EVENT", .text "${{ github.event_name }}"),
      ("LAND_EVENT_HEAD", .text "${{ github.event.workflow_run.head_sha }}"),
      ("LAND_EVENT_CONCLUSION", .text "${{ github.event.workflow_run.conclusion }}"),
      ("LAND_EVENT_PR", .text "${{ github.event.issue.number }}"),
      ("LAND_EVENT_COMMENT", .text "${{ github.event.comment.id }}")]),
    ("run", .text ".github/scripts/land-decide.sh \"$GITHUB_REPOSITORY\" \"$LAND_DASHBOARD\" \"$RUNNER_TEMP/land\"")]) &&
  nodeAt d (sp "decide" 7) (.map [
    ("if", .text "always()"),
    ("uses", .text "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
    ("with", .map [("name", .text "land-record-${{ github.run_id }}-${{ github.run_attempt }}"),
      ("path", .text "${{ runner.temp }}/land/record.json"), ("retention-days", .text "90")])]) &&
  nodeAt d (sp "decide" 8) (.map [
    ("if", .text "always()"),
    ("uses", .text "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
    ("with", .map [("name", .text "land-reads-${{ github.run_id }}-${{ github.run_attempt }}"),
      ("path", .text "${{ runner.temp }}/land/reads"), ("retention-days", .text "7")])])

private def apply (d : Doc) : Bool :=
  host d "apply" "5" &&
  nodeAt d (jp "apply" [.key "needs"]) (.text "decide") &&
  nodeAt d (jp "apply" [.key "environment"]) (.text "trusted") &&
  nodeAt d (jp "apply" [.key "concurrency"]) (concurrency "land-apply") &&
  nodeAt d (jp "apply" [.key "permissions"]) (permissions ["contents", "pull-requests", "issues"]) &&
  nodeAt d (jp "apply" [.key "outputs"])
    (.map [("outcome", .text "${{ steps.apply.outputs.outcome }}")]) &&
  nodeAt d (jp "apply" [.key "steps"]) (.seq [checkout,
    .map [("name", .text "Mint an app token that can only merge"), ("id", .text "app"),
      ("if", .text "env.LAND_MERGE == 'on'"),
      ("uses", .text "actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510"),
      ("with", .map [("app-id", .text "${{ vars.PR_UPDATER_APP_ID }}"),
        ("private-key", .text "${{ secrets.PR_UPDATER_APP_KEY }}"),
        ("permission-contents", .text "write"), ("permission-workflows", .text "write")])],
    .map [("name", .text "Read the pull request and its conversation again, then merge pinned to the head"),
      ("id", .text "apply"), ("env", .map [
        ("GH_TOKEN", .text "${{ github.token }}"),
        ("LAND_MERGE_TOKEN", .text "${{ steps.app.outputs.token }}"),
        ("LAND_PR", .text "${{ needs.decide.outputs.pr }}"),
        ("LAND_HEAD", .text "${{ needs.decide.outputs.head }}"),
        ("LAND_APPROVAL", .text "${{ needs.decide.outputs.approval }}"),
        ("LAND_DIGEST", .text "${{ needs.decide.outputs.digest }}"),
        ("LAND_REQUIRES_SPEC", .text "${{ needs.decide.outputs.requires_spec }}")]),
      ("run", .text ".github/scripts/land-apply.sh \"$GITHUB_REPOSITORY\" \"$RUNNER_TEMP/land-apply\"")]]) &&
  forbidden d "apply" ["lake", "install-", "cache", "github.event"]

private def report (d : Doc) : Bool :=
  host d "report" "5" &&
  nodeAt d (jp "report" [.key "needs"]) (.seq [.text "decide", .text "apply"]) &&
  nodeAt d (jp "report" [.key "if"])
    (.text "always() && github.ref == 'refs/heads/main' && needs.decide.result == 'success' && ((needs.decide.outputs.answers != '' && needs.decide.outputs.answers != '[]') ||\n  needs.decide.outputs.pr != '')") &&
  nodeAt d (jp "report" [.key "permissions"])
    (.map [("contents", .text "read"), ("pull-requests", .text "write")]) &&
  nodeAt d (jp "report" [.key "steps"]) (.seq [checkout,
    .map [("name", .text "Answer each owner word whose answer changed"),
      ("env", .map [("GH_TOKEN", .text "${{ github.token }}"),
        ("LAND_ANSWERS", .text "${{ needs.decide.outputs.answers }}"),
        ("LAND_PR", .text "${{ needs.decide.outputs.pr }}"),
        ("LAND_HEAD", .text "${{ needs.decide.outputs.head }}"),
        ("LAND_APPLY_RESULT", .text "${{ needs.apply.result }}"),
        ("LAND_APPLIED", .text "${{ needs.apply.outputs.outcome }}")]),
      ("run", .text ".github/scripts/land-report.sh \"$GITHUB_REPOSITORY\"")]]) &&
  keyless d "report" &&
  forbidden d "report" ["environment", "github-app-token", "app-id", "private-key", "concurrency"]

private def globalScope (d : Doc) : Bool :=
  nodeAt d [.key "env"] (.map [("LAND_MERGE", .text "on")]) &&
  onlyRefs d (has "github.token") [sp "decide" 6 [.key "env", .key "GH_TOKEN"],
    sp "apply" 2 [.key "env", .key "GH_TOKEN"], sp "report" 1 [.key "env", .key "GH_TOKEN"]] &&
  onlyRefs d (has "steps.app.outputs.token") [sp "apply" 2 [.key "env", .key "LAND_MERGE_TOKEN"]] &&
  onlyRefs d (hasIdentifierCI "secrets") [sp "apply" 1 [.key "with", .key "private-key"]] &&
  d.leaves.all (fun leaf =>
    !leaf.path.any (fun | .key key => hasIdentifierCI "secrets" key | _ => false)) &&
  d.leaves.all (fun leaf => !leaf.path.contains (.key "LAND_MERGE") ||
    leaf.path == [.key "env", .key "LAND_MERGE"] && leaf.value == .text "on") &&
  nodeAt d [.key "env", .key "LAND_MERGE"] (.text "on") &&
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

def applyCondition (d : Doc) : Bool := decide (d.scalarAt? applyPath = some (.text applyIf))

def holds (d : Doc) : Prop :=
  d.scalarAt? applyPath = some (.text applyIf) ∧ topology d = true ∧
    decideJob d = true ∧ apply d = true ∧ report d = true ∧ globalScope d = true

def check (d : Doc) : Except String Unit :=
  if !applyCondition d then .error "land.apply-condition"
  else if !topology d then .error "land.shape"
  else if !decideJob d then .error "land.decide"
  else if !apply d then .error "land.apply"
  else if !report d then .error "land.report"
  else if !globalScope d then .error "land.scope"
  else .ok ()

theorem check_sound (h : check d = .ok ()) : holds d := by
  unfold check at h
  repeat' split at h <;> simp_all [holds, applyCondition]

theorem check_apply_condition (h : check d = .ok ()) :
    d.scalarAt? applyPath = some (.text applyIf) := (check_sound h).1

example : callsGh "gh" = true := by decide +kernel
example : callsGh "echo;gh;exit" = true := by decide +kernel
example : callsGh "weight github.token" = false := by decide +kernel

example : applyCondition ⟨.map [("jobs", .map [("apply", .map [
    ("if", .map [("nested", .text applyIf)])])])], by decide +kernel⟩ = false := by decide +kernel

end MitosGate.Workflow.LandPins
