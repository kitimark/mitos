import MitosGate.ContentId

/-!
# Whether a verdict carries to a later head (`mitos-gate carry`)

A verdict covers one head. When `main` moves, `update-prs.yml` rebases every open PR, and a head
that only rebases keeps the verdict. The content id (`ContentId`) says whether two heads hold the
same change, but it binds where a hunk applies only within one merge-base: its marker counts the
copies of a hunk's old side in each head's own merge-base file. So a PR owner's push on top of the
verified head, which the updater then rebases over a `main` that adds a copy of the hunk's old
side above it, can get the verified head's id with a different change (#83, round 2). So the
verdict also needs every push in between to be an updater rebase of the commit the push before it
left, starting at the verified head. The PR timeline cannot show that: it lists only
force-pushes, and only the commit each one left.

`mitos-gate carry <base> <verified> <head>` reads the pushes to the PR's branch on standard input,
newest first, one per line as five tab-separated fields: the time, the activity type, the actor's
login, the commit before and the commit after. The REST activity route prints that with
`--jq '.[] | [.timestamp, .activity_type, .actor.login, .before, .after] | @tsv'`, and it lists
plain pushes too. The verdict carries, with exit 0, only when

* the newest push left the branch at `<head>` (`tip`),
* every push since the branch was last at `<verified>` is a force-push by the updater, and each
  starts from the commit the push before it left (`walk`, `walk_iff`), and
* `<verified>` and `<head>` have the same content id against `<base>`, both from this build
  (`ContentId.compute`).

Otherwise it prints why on one line, with exit 1, a refusal of either content id included.

The decision on the pushes is proved here. That the route lists every push with its real actor is
GitHub's, and is not proved; a push missing from the list leaves a gap, which stops the walk.
`gate/carry-test.sh` feeds the tool fixed lists, and #83 runs it on the real route.
-/

namespace MitosGate.Carry

open RunLog (quote splitLines)
open ContentId (logLine)

/-- The login GitHub shows for the pushes of the updater app, which `update-prs.yml` runs. -/
def updater : String := "mitos-pr-updater[bot]"

/-- One push to the branch, as the REST activity route lists it. -/
structure Push where
  time : String
  kind : String
  actor : String
  before : String
  after : String
  deriving Repr, DecidableEq

/-- A push a verdict can carry across: a force-push by the updater. Its rebase always rewrites
the PR's commits, so it never makes a plain push. -/
def Push.rebase (p : Push) : Bool := p.kind == "force_push" && p.actor == updater

/-- The newest push, the first of `ps`, left the branch at `h`. `walk` from a head that is not
the verified head already checks this; for the verified head itself, it says the branch is still
there. -/
def tip (h : String) : List Push → Bool
  | [] => false
  | p :: _ => p.after == h

/-- Walk the pushes `ps`, newest first, back from `cur`: the branch was at `v` at some point, and
every push since then is an updater rebase that starts from the commit the push before it left. -/
def walk (v : String) : String → List Push → Bool
  | cur, [] => cur == v
  | cur, p :: ps => cur == v || (p.after == cur && p.rebase && walk v p.before ps)

/-- `walk` passes exactly when the newest pushes `pre` are all updater rebases and chain `h` back
to `v`: the newest left the branch at `h`, each older one left it where the next one started, and
the oldest started at `v`. With no push, `h` is `v`. -/
theorem walk_iff {v h : String} {ps : List Push} :
    walk v h ps = true ↔ ∃ pre rest, ps = pre ++ rest ∧ (∀ p ∈ pre, p.rebase = true) ∧
      pre.map Push.after ++ [v] = h :: pre.map Push.before := by
  induction ps generalizing h with
  | nil =>
    simp only [walk, beq_iff_eq]
    constructor
    · intro e; exact ⟨[], [], rfl, by simp, by simp [e]⟩
    · rintro ⟨pre, rest, hps, -, e⟩
      obtain ⟨rfl, -⟩ := List.append_eq_nil_iff.1 hps.symm
      simpa using e.symm
  | cons p ps ih =>
    simp only [walk, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq]
    constructor
    · rintro (e | ⟨⟨e, hr⟩, hw⟩)
      · exact ⟨[], p :: ps, rfl, by simp, by simp [e]⟩
      · obtain ⟨pre, rest, rfl, hpre, hm⟩ := ih.1 hw
        refine ⟨p :: pre, rest, rfl, ?_, ?_⟩
        · intro q hq
          rcases List.mem_cons.1 hq with rfl | hq
          · exact hr
          · exact hpre q hq
        · simp [hm, e]
    · rintro ⟨pre, rest, hps, hpre, hm⟩
      cases pre with
      | nil => left; simpa using hm.symm
      | cons q pre =>
        right
        simp only [List.cons_append, List.cons.injEq] at hps
        obtain ⟨rfl, rfl⟩ := hps
        simp only [List.map_cons, List.cons_append, List.cons.injEq] at hm
        exact ⟨⟨hm.1, hpre _ List.mem_cons_self⟩,
          ih.2 ⟨pre, rest, rfl, fun r hr => hpre r (List.mem_cons_of_mem _ hr), hm.2⟩⟩

/-- So a push that is not an updater rebase, between the verified head and the head, stops the
carry: if the pushes since the branch left `v` are `pre`, and `pre` chains `h` back to `v`, they
are all updater rebases. The pushes newer than `v`'s are the ones `walk` reads. -/
theorem walk_rebase {v h : String} {ps : List Push} (hw : walk v h ps = true) :
    ∃ pre rest, ps = pre ++ rest ∧ ∀ p ∈ pre, p.rebase = true :=
  let ⟨pre, rest, e, hr, _⟩ := walk_iff.1 hw
  ⟨pre, rest, e, hr⟩

/-- #83, round 2: the owner pushed `v'` on the verified head `v`, and the updater rebased it to
`x`. The last push is the updater's, but the walk reaches the owner's push before `v`. -/
example : walk "v" "x" [⟨"t2", "force_push", updater, "v'", "x"⟩,
    ⟨"t1", "push", "kitimark", "v", "v'"⟩] = false := by decide
/-- The updater rebased `v` twice: the verdict on `v` can carry to `x2`. -/
example : walk "v" "x2" [⟨"t3", "force_push", updater, "x1", "x2"⟩,
    ⟨"t2", "force_push", updater, "v", "x1"⟩, ⟨"t1", "push", "kitimark", "u", "v"⟩] = true := by
  decide
/-- An owner's force-push is not the updater's. -/
example : walk "v" "x" [⟨"t2", "force_push", updater, "w", "x"⟩,
    ⟨"t1", "force_push", "kitimark", "v", "w"⟩] = false := by decide
/-- A plain push by the updater's login is not a rebase. -/
example : walk "v" "x" [⟨"t1", "push", updater, "v", "x"⟩] = false := by decide
/-- A gap: the newer push started from `w`, but the older one left the branch at `w'`. -/
example : walk "v" "x" [⟨"t2", "force_push", updater, "w", "x"⟩,
    ⟨"t1", "force_push", updater, "v", "w'"⟩] = false := by decide
/-- The list ends before it reaches `v`. -/
example : walk "v" "x" [⟨"t1", "force_push", updater, "w", "x"⟩] = false := by decide
/-- A branch deleted and created again is not a rebase. -/
example : walk "v" "x" [⟨"t2", "branch_creation", "kitimark", "0", "x"⟩,
    ⟨"t1", "branch_deletion", "kitimark", "v", "0"⟩] = false := by decide
example : tip "x" [⟨"t1", "force_push", updater, "v", "x"⟩] = true := by decide
example : tip "x" [] = false := by decide

/-- How many pushes `walk` crossed, for the message. -/
def rebases (v : String) : String → List Push → Nat
  | _, [] => 0
  | cur, p :: ps => if cur == v then 0 else rebases v p.before ps + 1

/-- Why `tip` or `walk` fails, for the message. The decision does not read it. -/
def why (v h : String) : List Push → String
  | [] => "the activity route listed no push to the branch"
  | ps@(p :: _) =>
    if p.after != h then s!"the branch's last push left it at {p.after}, not at the head {h}"
    else go h ps
where
  go (cur : String) : List Push → String
    | [] => s!"the pushes listed end before the branch was at the verified head {v}"
    | p :: ps =>
      if cur == v then "the pushes chain the head back to the verified head"
      else if p.after != cur then
        s!"the push of {p.time} left the branch at {p.after}, but the next push started from {cur}"
      else if !p.rebase then
        s!"the push of {p.time} from {p.before} to {p.after} is a {quote p.kind} by " ++
          s!"{quote p.actor}, not a force_push by {updater}"
      else go p.before ps

/-- One line of the route's TSV. -/
def parsePush (l : String) : Except String Push :=
  match l.splitOn "\t" with
  | [t, k, a, b, af] => .ok ⟨t, k, a, b, af⟩
  | _ => .error s!"a line is not a push (time, type, actor, before, after, tab-separated): {quote l}"

/-- Decide the carry, or say why not. -/
def check (base verified head : String) (ps : List Push) : ContentId.M String := do
  let v ← ContentId.resolve verified
  let h ← ContentId.resolve head
  unless tip h ps && walk v h ps do throw (why v h ps)
  let a ← ContentId.compute base v
  let b ← ContentId.compute base h
  unless a.id == b.id do
    throw s!"the content id changed: {a.id} at the verified head {v}, {b.id} at the head {h}"
  return s!"carry: {rebases v h ps} updater rebase(s) from {v} to {h}, content id {b.id}"

/-- `mitos-gate carry <base> <verified> <head>`, with the branch's pushes on standard input.
Prints `carry: ...` on standard output with exit 0, or one line on standard error, through
`logLine`, with exit 1 when the verdict does not carry and 2 on a usage error. -/
def cli (args : List String) (usage : String) : IO UInt32 := do
  match args with
  | [base, verified, head] =>
    try
      let input ← (← IO.getStdin).readToEnd
      match (splitLines input).mapM parsePush with
      | .error e =>
        IO.eprintln (logLine s!"no carry: {e}")
        return 1
      | .ok ps =>
        match ← (check base verified head ps).run with
        | .ok msg =>
          IO.println (logLine msg)
          return 0
        | .error e =>
          IO.eprintln (logLine s!"no carry: {e}")
          return 1
    catch e =>
      IO.eprintln (logLine s!"no carry: stopped on an I/O error: {e}")
      return 1
  | _ =>
    IO.eprintln "carry needs <base> <verified-head> <head>, with the branch's pushes on standard input"
    IO.eprintln usage
    return 2

end MitosGate.Carry
