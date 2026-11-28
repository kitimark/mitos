import MitosGate.Workflow.PinNode

namespace MitosGate.Workflow.AppTokenPins

open Yaml PinNode

private def action : String := "actions/create-github-app-token"

private def lower (s : String) : String :=
  String.ofList (s.toList.map fun c =>
    if 'A' ≤ c && c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c)

private def immutableAction (name ref : String) : Bool :=
  let stem := (name ++ "@").toList
  let chars := ref.toList
  let hash := chars.drop stem.length
  chars.take stem.length == stem && hash.length == 40 &&
    hash.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))

private def mintLeaf (leaf : Leaf) : Bool :=
  leaf.path.any (fun seg => match seg with
    | .key key => lower key == "uses" | _ => false) && match leaf.value with
    | .text ref => (lower ref).startsWith action
    | _ => false

def mintCount (workflows : List Doc) : Nat :=
  (workflows.flatMap fun d => d.leaves.filter mintLeaf).length

private def permissionKey (key : String) : Bool :=
  (lower key).startsWith "permission-"

private def supportedPermission (key value : String) : Bool :=
  ["permission-contents", "permission-pull-requests", "permission-workflows",
    "permission-administration"].contains key && ["read", "write"].contains value

private def forbiddenKey (key : String) : Bool :=
  ["owner", "repositories", "skip-token-revoke"].contains (lower key)

private def permissionPath (leaf : Leaf) : Bool :=
  if leaf.path.any (fun s => match s with | .key k => permissionKey k | _ => false) then
    match leaf.path, leaf.value with
    | [.key "with", .key key], .text value => supportedPermission key value
    | _, _ => false
  else true

private def mintAuthority (d : Doc) (leaf : Leaf) : Bool :=
  match leaf.path, leaf.value with
  | [.key "jobs", .key job, .key "steps", .idx i, .key "uses"], .text ref =>
    let path := [.key "jobs", .key job, .key "steps", .idx i]
    match d.root.get? path, mapAt? d (path ++ [.key "with"]) with
    | some (.map entries), some inputs =>
      immutableAction action ref &&
        textAt? d [.key "jobs", .key job, .key "environment"] == some "trusted" &&
        inputs.any (fun entry => permissionKey entry.1) &&
        (Node.map entries).leaves.all permissionPath &&
        (Node.map entries).leaves.all (fun l => !l.path.any (fun s => match s with
          | .key k => forbiddenKey k | _ => false))
    | _, _ => false
  | _, _ => false

private def workflowShape (d : Doc) : Bool :=
  match mapAt? d [.key "jobs"] with
  | none => false
  | some jobs => !jobs.isEmpty && jobs.all fun (_, node) =>
    match node with
    | .map _ =>
      match node.get? [.key "steps"] with
      | none => true
      | some (.seq steps) =>
        let ids := steps.filterMap fun step => match step.get? [.key "id"] with
          | some (.text id) => some (lower id)
          | _ => none
        steps.all (fun step => match step with
          | .map _ => match step.get? [.key "id"] with
            | none => true
            | some (.text _) => true
            | _ => false
          | _ => false) && ids.eraseDups.length == ids.length
      | _ => false
    | _ => false

private def workflowAuthority (d : Doc) : Bool :=
  (d.leaves.filter mintLeaf).all (mintAuthority d)

private def updaterPermissionInputs : Node := .map [
  ("app-id", .text "${{ vars.PR_UPDATER_APP_ID }}"),
  ("private-key", .text "${{ secrets.PR_UPDATER_APP_KEY }}"),
  ("permission-contents", .text "write"),
  ("permission-pull-requests", .text "write"),
  ("permission-workflows", .text "write")]

private def configured : Node := .text "steps.cfg.outputs.ok == 'true'"

private def updaterRoot : Node := .map [
  ("name", .text "Keep PR branches up to date"),
  ("on", .map [("workflow_dispatch", .map [("inputs", .map [("pr", .map [
    ("description", .text "Number of the one pull request to rebase onto main"),
    ("required", .text "true"), ("type", .text "string")])])])]),
  ("permissions", .map [("contents", .text "read")]),
  ("concurrency", .map [("group", .text "update-prs"), ("cancel-in-progress", .text "false")]),
  ("jobs", .map [("rebase", .map [("runs-on", .text "ubuntu-24.04"),
    ("environment", .text "trusted"), ("steps", .seq [
      .map [("name", .text "Check the updater app is configured"), ("id", .text "cfg"),
        ("env", .map [("APP_ID", .text "${{ vars.PR_UPDATER_APP_ID }}"),
          ("APP_KEY", .text "${{ secrets.PR_UPDATER_APP_KEY }}")]),
        ("run", .text "if [ -z \"$APP_ID\" ] || [ -z \"$APP_KEY\" ]; then\n  echo \"::warning::PR_UPDATER_APP_ID (variable) or PR_UPDATER_APP_KEY (secret of the trusted environment) is not set; PR branches were not updated.\"\n  echo \"ok=false\" >> \"$GITHUB_OUTPUT\"\nelse\n  echo \"ok=true\" >> \"$GITHUB_OUTPUT\"\nfi\n")],
      .map [("name", .text "Mint a short-lived app token"), ("id", .text "app"),
        ("if", configured),
        ("uses", .text "actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510"),
        ("with", updaterPermissionInputs)],
      .map [("uses", .text "actions/checkout@11d5960a326750d5838078e36cf38b85af677262"),
        ("if", configured), ("with", .map [("fetch-depth", .text "0"),
          ("token", .text "${{ steps.app.outputs.token }}")])],
      .map [("name", .text "Rebase the named PR onto main"), ("if", configured),
        ("env", .map [("GH_TOKEN", .text "${{ steps.app.outputs.token }}"),
          ("PR_NUMBER", .text "${{ inputs.pr }}")]),
        ("run", .text ".github/scripts/rebase-prs.sh")]])])])]

private def updaterAuthority (d : Doc) : Bool := same d.root updaterRoot

def holds (land protection updater : Doc) (unprivileged : List Doc) : Prop :=
  let allWorkflows := [land, protection, updater] ++ unprivileged
  mintCount allWorkflows ≠ 0 ∧ allWorkflows.all workflowShape = true ∧
    allWorkflows.all workflowAuthority = true ∧ updaterAuthority updater = true ∧
    mintCount unprivileged = 0

def check (land protection updater : Doc) (unprivileged : List Doc) : Except String Unit :=
  let allWorkflows := [land, protection, updater] ++ unprivileged
  if mintCount allWorkflows = 0 then .error "mint.missing"
  else if !allWorkflows.all workflowShape then .error "mint.shape"
  else if !allWorkflows.all workflowAuthority then .error "mint.authority"
  else if !updaterAuthority updater then .error "mint.updater"
  else if mintCount unprivileged ≠ 0 then .error "mint.inventory"
  else .ok ()

theorem check_sound (h : check land protection updater unprivileged = .ok ()) :
    holds land protection updater unprivileged := by
  unfold check at h
  dsimp only at h
  repeat' split at h <;> simp_all [holds]

theorem check_has_mint (h : check land protection updater unprivileged = .ok ()) :
    0 < mintCount ([land, protection, updater] ++ unprivileged) :=
  Nat.pos_of_ne_zero (check_sound h).1

theorem check_no_unprivileged_mint
    (h : check land protection updater unprivileged = .ok ()) :
    mintCount unprivileged = 0 := (check_sound h).2.2.2.2

example : immutableAction action
    "actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510" = true := by
  decide +kernel
example : immutableAction action "actions/create-github-app-token@v1" = false := by
  decide +kernel
example : permissionPath ⟨[.key "env", .key "permission-contents"], .text "write"⟩ = false := by
  decide +kernel
example : permissionPath ⟨[.key "with", .key "permission-contents"], .text "write"⟩ = true := by
  decide +kernel

private def updaterFixture : Doc :=
  ⟨updaterRoot, by decide +kernel⟩

private def emptyFixture : Doc :=
  ⟨.map [("jobs", .map [("check", .map [("steps", .seq [])])])], by decide +kernel⟩

private def fixtureRefusal? (unprivileged : List Doc) : Option String :=
  match check emptyFixture emptyFixture updaterFixture unprivileged with
  | .ok () => none
  | .error reason => some reason

example : fixtureRefusal? [] = none := by decide +kernel
example : fixtureRefusal? [updaterFixture] = some "mint.inventory" := by decide +kernel

example : (match check emptyFixture emptyFixture emptyFixture [] with
    | .error reason => some reason | .ok () => none) = some "mint.missing" := by
  decide +kernel

private def extraReferenceRefusal? (value : String) : Option String :=
  let root := match updaterRoot with
    | .map entries => .map (("env", .map [("EXTRA", .text value)]) :: entries)
    | n => n
  match Doc.ofNode root with
  | .error _ => some "reader"
  | .ok d => match check emptyFixture emptyFixture d [] with
    | .ok () => none
    | .error reason => some reason

private def pushTriggerRefusal? : Option String :=
  let push : String × Node := ("push", .map [("branches", .seq [.text "main"])])
  let root := match updaterRoot with
    | .map entries => .map (entries.map fun (key, node) => match key, node with
      | "on", .map triggers => (key, .map (push :: triggers))
      | _, _ => (key, node))
    | n => n
  match Doc.ofNode root with
  | .error _ => some "reader"
  | .ok d => match check emptyFixture emptyFixture d [] with
    | .ok () => none
    | .error reason => some reason

example : pushTriggerRefusal? = some "mint.updater" := by decide +kernel

example : extraReferenceRefusal? "${{ steps['app']['outputs']['token'] }}" =
    some "mint.updater" := by decide +kernel
example : extraReferenceRefusal? "${{ toJSON(steps) }}" =
    some "mint.updater" := by decide +kernel
example : extraReferenceRefusal? "${{ StEpS['app'].outputs.token }}" =
    some "mint.updater" := by decide +kernel

end MitosGate.Workflow.AppTokenPins
