import Lean.Data.Json
import MitosGate.Snapshot
import MitosGate.SpeechCli
import MitosGate.ContentId

/-!
# `mitos-gate snapshot`: what GitHub said, as one `land` snapshot

`mitos-gate snapshot <dir>` reads the REST responses that `gate/snapshot-fetch.sh` saved in
`<dir>` and prints one line of JSON, `{"prs": [...]}`, which `mitos-gate land` reads. A response
that is missing (its read failed) or not of its route's shape is a failed read, and
`MitosGate.Snapshot` decides what it does: the pull requests that need it hold.

Two reads have no such fallback, so the command stops with one line on standard error and exit 1:
the repository and the list of open pull requests, and the commit of `main`. A usage error is
exit 2.

The commits come from git in the current clone, which must be the repository read. A commit the
clone lacks is fetched from `origin`. Each content id is `mitos-gate content-id <main> <commit>`
of this build, and a commit that cannot be fetched or measured has none, so nothing carries to or
from it. The replay that `Base.clean` names picks each commit of the branch onto `main` with
`git merge-tree`, in a fixed identity and date, so it adds objects and moves no ref.
-/

open Lean (Json)

namespace MitosGate.SnapshotCli

open Snapshot
open Land (Sha Obs Base Gate Word Verdict Teammate Result)
open Speech (Stamp isSha)

def load (dir : System.FilePath) (name : String) : IO (Option Json) := do
  let p := dir / (name ++ ".json")
  unless ← p.pathExists do return none
  try
    return (Json.parse (← IO.FS.readFile p)).toOption
  catch _ => return none

def field (k : String) (j : Json) : Option Json := (j.getObjVal? k).toOption

def str (k : String) (j : Json) : Option String := (field k j).bind (·.getStr?.toOption)

def nat (k : String) (j : Json) : Option Nat := (field k j).bind (·.getNat?.toOption)

def bool (k : String) (j : Json) : Option Bool := (field k j).bind (·.getBool?.toOption)

def arr (j : Json) : Option (List Json) := j.getArr?.toOption.map Array.toList

/-- A string field that the route may give as `null`. -/
def text (k : String) (j : Json) : Option String :=
  match field k j with
  | some .null => some ""
  | some (.str s) => some s
  | _ => none

def stamp (k : String) (j : Json) : Option Stamp := (str k j).bind (Speech.stamp? ·.toList)

/-- The login of `user` or `actor`; a deleted account is `null`, which is nobody. -/
def login (k : String) (j : Json) : Option String :=
  match field k j with
  | some .null => some ""
  | some u => str "login" u
  | none => none

/-- `gh api --paginate --slurp`: a list of one or more pages, each a list. -/
def pages (j : Json) : Option (List Json) := do
  let ps ← arr j
  if ps.isEmpty then none else (ps.mapM arr).map List.flatten

def pull (j : Json) : Option Pull := do
  let head ← field "head" j
  let base ← field "base" j
  let sha ← str "sha" head
  unless isSha sha.toList do none
  let headRepo ← match field "repo" head with
    | some .null => some none
    | some r => (str "full_name" r).map some
    | none => none
  let labels ← (field "labels" j).bind arr >>= (·.mapM (str "name"))
  return { number := ← nat "number" j, state := ← str "state" j, draft := ← bool "draft" j,
           head := sha, headRepo, baseRef := ← str "ref" base,
           baseRepo := ← (field "repo" base).bind (str "full_name"), labels,
           body := ← text "body" j }

def protectionOf (j : Json) : Option Protection := do
  let admins ← (field "enforce_admins" j).bind (bool "enabled")
  match field "required_status_checks" j with
  | none => return ⟨admins, false, []⟩
  | some rsc =>
    let strict ← bool "strict" rsc
    let contexts ← (field "contexts" rsc).bind arr >>= (·.mapM (·.getStr?.toOption))
    let checks ← match field "checks" rsc with
      | none => some []
      | some c => arr c >>= (·.mapM (str "context"))
    return ⟨admins, strict, contexts ++ checks⟩

def stacksOf (j : Json) : Option (List Nat) := do
  let stacks ← pages j
  let prs ← stacks.mapM fun s => (field "pull_requests" s).bind arr >>= (·.mapM (nat "number"))
  return prs.flatten

def dashboardOf (owner : String) (j : Json) : Option String := do
  unless str "title" j == some "Owner dashboard" && login "user" j == some owner &&
      str "state" j == some "open" && (field "pull_request" j).isNone do none
  str "body" j

def commentsOf (j : Json) : Option (List Speech.Comment) :=
  pages j >>= (·.mapM fun c => (SpeechCli.comment c).toOption)

def reviewCommentsOf (j : Json) : Option (List Post) :=
  pages j >>= (·.mapM fun c => do
    return ⟨← login "user" c, none, ← stamp "created_at" c, ← stamp "updated_at" c, ← text "body" c⟩)

/-- A pending review is the owner's draft, not yet posted, and has no time. -/
def reviewsOf (j : Json) : Option (List Review) := do
  let vs ← pages j
  let vs := vs.filter fun v => str "state" v != some "PENDING"
  vs.mapM fun v => do
    return ⟨← nat "id" v, ← login "user" v, ← str "state" v, ← text "commit_id" v,
      ← stamp "submitted_at" v, ← text "body" v⟩

def activityOf (j : Json) : Option (List Carry.Push) :=
  pages j >>= (·.mapM fun a => do
    return ⟨← str "timestamp" a, ← str "activity_type" a, ← login "actor" a, ← str "before" a,
      ← str "after" a⟩)

/-- The route lists at most 3000 files, so a list that long may be cut. -/
def filesOf (j : Json) : Option (List String) := do
  let fs ← pages j
  if 3000 ≤ fs.length then none
  else
    (fs.mapM fun f => do
      let n ← str "filename" f
      match field "previous_filename" f with
      | none => some [n]
      | some (.str o) => some [n, o]
      | some _ => none).map List.flatten

/-- Check-run pages are objects. Every page gives the same `total_count`, and the runs listed
must number that many. -/
def checksOf (j : Json) : Option (List Check) := do
  let ps ← arr j
  let first ← ps.head?
  let total ← nat "total_count" first
  let runs ← (ps.mapM fun p => do
    unless nat "total_count" p == some total do none
    (field "check_runs" p).bind arr).map List.flatten
  unless runs.length == total do none
  runs.mapM fun c => do
    let app ← match field "app" c with
      | some .null => some ""
      | some a => str "slug" a
      | none => none
    return ⟨← nat "id" c, ← str "name" c, app, ← str "head_sha" c, ← str "status" c,
      ← text "conclusion" c⟩

def splitLines (s : String) : List String := (s.splitOn "\n").filter (!·.isEmpty)

def git (args : Array String) (env : Array (String × Option String) := #[]) :
    IO (UInt32 × String) := do
  flushParentStdoutBeforeChild
  let child ← IO.Process.spawn {
    cmd := "git", args := (ContentId.gitConfig.foldl (fun a c => a ++ #["-c", c]) #["--no-pager"]) ++ args
    env := ContentId.gitEnv ++ env, stdin := .null, stdout := .piped, stderr := .null }
  let out ← child.stdout.readToEnd
  let code ← child.wait
  return (code, out)

def has (sha : Sha) : IO Bool := return (← git #["cat-file", "-e", sha ++ "^{commit}"]).1 == 0

def ensure (sha : Sha) : IO Bool := do
  unless isSha sha.toList do return false
  if ← has sha then return true
  let _ ← git #["fetch", "--no-tags", "--quiet", "origin", sha]
  has sha

def contentId (main sha : Sha) : IO (Option String) := do
  unless ← ensure sha do return none
  try
    match ← (ContentId.compute main sha).run with
    | .ok r => return some r.id
    | .error _ => return none
  catch _ => return none

def replayEnv : Array (String × Option String) :=
  #[("GIT_AUTHOR_NAME", some "mitos-snapshot"), ("GIT_AUTHOR_EMAIL", some "snapshot@mitos.invalid"),
    ("GIT_AUTHOR_DATE", some "@0 +0000"), ("GIT_COMMITTER_NAME", some "mitos-snapshot"),
    ("GIT_COMMITTER_EMAIL", some "snapshot@mitos.invalid"), ("GIT_COMMITTER_DATE", some "@0 +0000")]

/-- Where the head stands against `main`. A merge commit on the branch, or any git failure, is
`unread`. -/
def baseOf (main head : Sha) : IO Base := do
  unless ← ensure head do return .unread
  match (← git #["merge-base", "--is-ancestor", head, main]).1 with
  | 0 => return .mergedMain
  | 1 => pure ()
  | _ => return .unread
  match (← git #["merge-base", "--is-ancestor", main, head]).1 with
  | 0 => return .current
  | 1 => pure ()
  | _ => return .unread
  let (c, out) ← git #["merge-base", "--all", main, head]
  let [mb] := splitLines out | return .unread
  unless c == 0 do return .unread
  let (c, out) ← git #["rev-list", "--reverse", "--topo-order", "--parents", s!"{mb}..{head}"]
  unless c == 0 do return .unread
  let mut cur := main
  for l in splitLines out do
    let [commit, parent] := l.splitOn " " | return .unread
    let (c, out) ← git #["merge-tree", "--write-tree", s!"--merge-base={parent}", cur, commit]
    if c == 1 then return .conflict
    let some tree := (splitLines out).head? | return .unread
    unless c == 0 do return .unread
    let (c, out) ← git #["commit-tree", "--no-gpg-sign", tree, "-p", cur, "-m",
      s!"replay of {commit}"] replayEnv
    let r := trim out
    unless c == 0 && isSha r.toList do return .unread
    cur := r
  return .clean cur

private def kind (k : String) (fields : List (String × Json) := []) : Json :=
  Json.mkObj (("kind", Json.str k) :: fields)

private def n (x : Nat) : Json := Lean.toJson x

def teamJson (t : Teammate) : Json := Json.mkObj [("provider", .str t.provider), ("name", .str t.name)]

def baseJson : Base → Json
  | .current => kind "current"
  | .clean r => kind "clean" [("replay", .str r)]
  | .conflict => kind "conflict"
  | .mergedMain => kind "mergedMain"
  | .unread => kind "unread"

def gateName : Gate → String
  | .success => "success" | .failure => "failure" | .cancelled => "cancelled"
  | .skipped => "skipped" | .pending => "pending" | .missing => "missing"

def resultName : Result → String
  | .pass => "pass" | .fail => "fail" | .hold => "hold" | .wordingOnly => "wordingOnly"

def wordJson : Word → Json
  | .ownerLand m => kind "ownerLand" [("said", n m.said), ("about", .str m.about)]
  | .ownerHold s => kind "ownerHold" [("said", n s)]
  | .agentLand t m => kind "agentLand" [("who", teamJson t), ("said", n m.said), ("about", .str m.about)]

def verdictJson (v : Verdict) : Json :=
  Json.mkObj [("said", n v.said), ("head", .str v.head), ("judge", teamJson v.judge),
    ("model", .str v.model), ("result", .str (resultName v.result))]

/-- The fields `mitos-gate land` reads; an absent optional field is the safe `none`. -/
def obsJson (o : Obs) : Json :=
  Json.mkObj <|
    [("pr", n o.pr), ("updatable", .bool o.updatable), ("enforced", .bool o.enforced),
     ("head", .str o.head),
     ("pushes", .arr (o.pushes.map fun p => Json.mkObj
        [("byUpdater", .bool p.byUpdater), ("before", .str p.before), ("after", .str p.after)]).toArray),
     ("ids", .arr (o.ids.map fun (s, i) => Json.mkObj [("sha", .str s), ("id", .str i)]).toArray),
     ("base", baseJson o.base), ("gate", .str (gateName o.gate)),
     ("verdicts", .arr (o.verdicts.map verdictJson).toArray),
     ("delegates", .arr (o.delegates.map teamJson).toArray),
     ("words", .arr (o.words.map wordJson).toArray), ("rest", .bool o.rest)] ++
    (o.paths.map fun ps => [("paths", Json.arr (ps.map Json.str).toArray)]).getD [] ++
    (o.author.map fun a => [("author", Json.mkObj [("who", teamJson a.who), ("model", .str a.model)])]).getD [] ++
    (o.botAt.map fun b => [("botAt", Json.str b)]).getD []

/-- The names of the failed reads, for the line that says why a pull request holds. -/
def unread (g : Global) (p : Pull) (r : Reads) : List String :=
  [("protection", g.protection.isNone), ("stacks", g.stacked.isNone), ("dashboard", g.rows.isNone),
   ("comments", r.comments.isNone), ("review-comments", r.reviewComments.isNone),
   ("reviews", r.reviews.isNone), ("activity", (activity p r).isNone), ("files", r.files.isNone),
   ("checks", r.checks.isNone)].filterMap fun (k, b) => if b then some k else none

private def stop (m : String) : IO UInt32 := do
  IO.eprintln (ciLine s!"snapshot: {m}")
  return 1

def run (dir : System.FilePath) : IO UInt32 := do
  let some repoJ ← load dir "repo" | stop "the repository read is missing or not JSON"
  let some repo := str "full_name" repoJ | stop "the repository read has no full_name"
  let some owner := (field "owner" repoJ).bind (str "login") | stop "the repository read has no owner"
  let some openJ ← load dir "open" | stop "the list of open pull requests is missing or not JSON"
  let some pulls := (pages openJ).bind (·.mapM pull)
    | stop "the list of open pull requests is not of its route's shape"
  let some mainJ ← load dir "main" | stop "the read of main is missing or not JSON"
  let some main := ((field "commit" mainJ).bind (str "sha")).filter (isSha ·.toList)
    | stop "the read of main has no commit"
  unless (← ensure main) do
    return (← stop s!"main's commit {main} is not in this clone and could not be fetched")
  let g : Global :=
    { repo, owner, protection := (← load dir "protection").bind protectionOf,
      stacked := (← load dir "stacks").bind stacksOf,
      rows := ((← load dir "dashboard").bind (dashboardOf owner)).bind rows }
  let mut out : Array Json := #[]
  for p in pulls.mergeSort (fun a b => a.number ≤ b.number) do
    let k := toString p.number
    let r : Reads :=
      { comments := (← load dir s!"comments-{k}").bind commentsOf,
        reviewComments := (← load dir s!"review-comments-{k}").bind reviewCommentsOf,
        reviews := (← load dir s!"reviews-{k}").bind reviewsOf,
        activity := (← load dir s!"activity-{k}").bind activityOf,
        files := (← load dir s!"files-{k}").bind filesOf,
        checks := (← load dir s!"checks-{k}").bind checksOf }
    let base ← baseOf main p.head
    let shas := wanted (obs g p r ⟨[], base⟩)
    let mut ids := #[]
    for s in shas do
      match ← contentId main s with
      | some i => ids := ids.push (s, i)
      | none => IO.eprintln (ciLine s!"snapshot: #{k}: no content id for {s}")
    let missing := unread g p r
    unless missing.isEmpty do
      IO.eprintln (ciLine s!"snapshot: #{k} holds: unread {", ".intercalate missing}")
    out := out.push (obsJson (obs g p r ⟨ids.toList, base⟩))
  IO.println (Json.mkObj [("prs", Json.arr out)]).compress
  return 0

def cli (args : List String) (usage : String) : IO UInt32 := do
  match args with
  | [dir] =>
    try run dir
    catch e => stop s!"stopped on an I/O error: {e}"
  | _ =>
    IO.eprintln "snapshot takes one argument, the folder that gate/snapshot-fetch.sh wrote"
    IO.eprintln usage
    return 2

end MitosGate.SnapshotCli
