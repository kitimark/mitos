import MitosGate.Speech

/-!
What the REST routes said, read into one `Land.Obs` per pull request. `none` is a read that failed
or that is not what its route returns. Any such read of what a pull request's observation needs
puts the incomplete-read hold on it, so it holds (`failedReadHolds`); the field itself also takes
its safe value.

Until verdicts are conversation records, they come from the verdict cell of the pull request's row
in the Owner dashboard's In flight table, and so does the author's model, the root's
`author <model>` note, until holder `push` records exist.
-/

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

structure Protection where
  admins : Bool
  strict : Bool
  checks : List String

/-- `rows`: the In flight verdict cells of the Owner dashboard, as `Snapshot.rows` reads its body. -/
structure Global where
  repo : String
  owner : String
  protection : Option Protection
  stacked : Option (List Nat)
  rows : Option (List (Nat × List Char))

structure Pull where
  number : Nat
  state : String
  draft : Bool
  head : Sha
  headRepo : Option String
  baseRef : String
  baseRepo : String
  labels : List String
  body : String

structure Check where
  id : Nat
  name : String
  app : String
  sha : Sha
  status : String
  conclusion : String

/-- An issue comment, a review comment or a review, as far as answering goes. The review routes
have no app field. -/
structure Post where
  login : String
  slug : Option String
  created : Stamp
  updated : Stamp
  body : String

structure Review where
  id : Nat
  login : String
  state : String
  commit : String
  submitted : Stamp
  body : String

structure Reads where
  comments : Option (List Comment)
  reviewComments : Option (List Post)
  reviews : Option (List Review)
  activity : Option (List Carry.Push)
  files : Option (List String)
  checks : Option (List Check)

structure Git where
  ids : List (Sha × String)
  base : Base

def stampOf (q : Carry.Push) : Option Stamp := Speech.stamp? q.time.toList

def descending : List Carry.Push → Bool
  | p :: q :: rest =>
    (match stampOf p, stampOf q with
      | some a, some b => decide (b ≤ a)
      | _, _ => false) && descending (q :: rest)
  | [p] => (stampOf p).isSome
  | [] => true

/-- The activity route's list, as `carry` and `Land.Obs.pushes` read it: newest first, each commit
40 lowercase hex, and the newest push left the branch at the head that the list of pull requests
gave. -/
def pushesOk (head : Sha) (ps : List Carry.Push) : Bool :=
  ps.all (fun q => isSha q.before.toList && isSha q.after.toList) && descending ps &&
    Carry.tip head ps

def activity (p : Pull) (r : Reads) : Option (List Carry.Push) := r.activity.filter (pushesOk p.head)

def known (ps : List Carry.Push) : List Sha := ps.flatMap fun q => [q.before, q.after]

def toLand (q : Carry.Push) : Push := ⟨q.updaterForcePush, q.before, q.after⟩

/-! ## The Owner dashboard -/

def cells : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    if c == '|' then [] :: cells cs
    else
      match cells cs with
      | [] => [[c]]
      | x :: xs => (c :: x) :: xs

def inFlight : List Char := "## In flight".toList

def heading (l : List Char) : Bool := "## ".toList.isPrefixOf (Speech.trim l)

def section? (ls : List (List Char)) : Option (List (List Char)) :=
  match ls.filter (fun l => Speech.trim l == inFlight) with
  | [_] => some (((ls.dropWhile (fun l => Speech.trim l != inFlight)).drop 1).takeWhile (!heading ·))
  | _ => none

def prNumber (c : List Char) : Option Nat :=
  match Speech.trim c with
  | '#' :: r =>
    let ds := r.takeWhile digit
    if ds.isEmpty || (r.dropWhile digit).head?.any Char.isAlphanum then none else Speech.num ds 0
  | _ => none

inductive Row
  | skip
  | data (n : Nat) (verdict : List Char)
  | bad
  deriving DecidableEq

def separator (c : List Char) : Bool := c.all fun x => x == '-' || x == ':' || x == ' '

/-- A line of the In flight section. Prose is skipped. A table line has exactly the four columns
PR, Head, `gate` and Verdict; any other table line spoils the whole dashboard. -/
def row (l : List Char) : Row :=
  match Speech.trim l with
  | '|' :: _ =>
    match cells (Speech.trim l) with
    | [] :: rest =>
      match rest.reverse with
      | [] :: mid =>
        if mid.all separator then .skip
        else
          match mid.reverse with
          | [pr, _, _, v] =>
            if Speech.trim pr == "PR".toList then .skip
            else
              match prNumber pr with
              | some n => .data n (Speech.trim v)
              | none => .bad
          | _ => .bad
      | _ => .bad
    | _ => .bad
  | _ => .skip

def distinctNats : List Nat → Bool
  | [] => true
  | n :: ns => !ns.contains n && distinctNats ns

def rowsOf (ls : List (List Char)) : Option (List (Nat × List Char)) :=
  let rs := ls.map row
  let ds := rs.filterMap fun
    | .data n v => some (n, v)
    | _ => none
  if rs.contains .bad || !distinctNats (ds.map (·.1)) then none else some ds

/-- The verdict cell of each In flight row. `none`: no single In flight section, a table line of
another shape, or two rows for one pull request. -/
def rows (body : String) : Option (List (Nat × List Char)) :=
  (section? (lines body.toList)).bind rowsOf

def families : List (List Char) := ["opus", "sonnet", "haiku", "fable", "grok"].map String.toList

def efforts : List (List Char) := ["low", "medium", "high", "xhigh", "max"].map String.toList

def judgeChar (c : Char) : Bool := c.isLower || c == '-'

def judge? (w : List Char) : Option (List Char) :=
  match families.find? (fun f => (f ++ ['-']).isPrefixOf w) with
  | some f => if efforts.contains (w.drop (f.length + 1)) then some f else none
  | none => none

def judges : Nat → List Char → List (List Char) × List Char
  | 0, s => ([], s)
  | n + 1, s =>
    match judge? (s.takeWhile judgeChar) with
    | none => ([], s)
    | some f =>
      match s.dropWhile judgeChar with
      | ' ' :: '+' :: ' ' :: r =>
        match judges n r with
        | ([], _) => ([f], s.dropWhile judgeChar)
        | (fs, r') => (f :: fs, r')
      | r => ([f], r)

def result? (s : List Char) : Option (Result × List Char) :=
  if "PASS".toList.isPrefixOf s then some (.pass, s.drop 4)
  else if "FAIL".toList.isPrefixOf s then some (.fail, s.drop 4)
  else if "wording-only".toList.isPrefixOf s then some (.wordingOnly, s.drop 12)
  else none

/-- `at <sha>` or `carried from <sha>`, the sha in backticks or not: 7 to 40 lowercase hex, and the
text after it. A carried verdict names the head it was given at, and `carry` decides whether it
reaches the head. -/
def cover? (s : List Char) : Option (List Char × List Char) :=
  let r := if "at ".toList.isPrefixOf s then some (s.drop 3)
    else if "carried from ".toList.isPrefixOf s then some (s.drop 13) else none
  r.bind fun r =>
    let (tick, r) := match r with
      | '`' :: r => (true, r)
      | r => (false, r)
    let h := r.takeWhile hex
    let after := r.dropWhile hex
    if 7 ≤ h.length && h.length ≤ 40 &&
        (if tick then after.head? == some '`' else !(after.head?.any Char.isAlphanum)) then
      some (h, if tick then after.drop 1 else after)
    else none

def within (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | c :: cs => p.isPrefixOf (c :: cs) || within p cs

def unwrap (c : List Char) : List Char := (Speech.trim c).dropWhile fun x => x == '*' || x == '_'

structure Said where
  result : Result
  judges : List (List Char)
  sha : List Char

def tailOf (js : List (List Char) × List Char) : Option (List Char) :=
  if js.1.isEmpty then some js.2
  else
    match js.2 with
    | ' ' :: x => some x
    | _ => none

/-- The judges that open a parenthesis right after the sha, as in
`PASS carried from 5c258d6 (opus-xhigh, author sonnet)`. -/
def paren (s : List Char) : List (List Char) :=
  match s with
  | ' ' :: '(' :: r =>
    match judges r.length r with
    | (js, ',' :: _) => js
    | (js, ')' :: _) => js
    | _ => []
  | _ => []

/-- `PASS <judges> at <sha>`, `FAIL <judges> at <sha>` or `wording-only at <sha>`, with
`carried from` in place of `at`, and the judges either before `at` or in a parenthesis right after
the sha, not both. Judges are `opus-xhigh + sonnet-high` and the like. The rest of the cell is
prose. A cell that names `FAIL` anywhere after a `PASS` or `wording-only` says nothing. -/
def said? (cell : List Char) : Option Said :=
  match result? (unwrap cell) with
  | some (r, ' ' :: rest) =>
    match (tailOf (judges rest.length rest)).bind cover? with
    | some (h, after) =>
      if ((r == .wordingOnly) == ((judges rest.length rest).1 ++ paren after).isEmpty &&
          ((judges rest.length rest).1.isEmpty || (paren after).isEmpty)) &&
          (r == .fail || !within "FAIL".toList ((unwrap cell).drop 1)) then
        some ⟨r, (judges rest.length rest).1 ++ paren after, h⟩
      else none
    | none => none
  | _ => none

def resolveKnown (known : List Sha) (p : List Char) : Option Sha :=
  match Speech.matching known p with
  | [] => none
  | s :: rest => if rest.all (· == s) then some s else none

def root : Teammate := ⟨"claude", "root"⟩

def verdictsOf (known : List Sha) (cell : List Char) : List Verdict :=
  match said? cell with
  | none => []
  | some s =>
    match resolveKnown known s.sha with
    | none => []
    | some h =>
      if s.result == .wordingOnly then [⟨0, h, root, "unknown", .wordingOnly⟩]
      else s.judges.map fun f =>
        ⟨0, h, ⟨"claude", "verifier-" ++ String.ofList f⟩, String.ofList f, s.result⟩

def suffixes (p : List Char) : Option Char → List Char → List (List Char)
  | _, [] => []
  | prev, c :: cs =>
    (if !(prev.any Char.isAlphanum) && p.isPrefixOf (c :: cs) then [(c :: cs).drop p.length]
      else []) ++ suffixes p (some c) cs

/-- The one `author <model>` note of the cell, its model a family that no other family follows
before the next `.`: "author sonnet, fixed by opus" names no author. -/
def authorOf (cell : List Char) : Option Author :=
  match suffixes "author ".toList none cell with
  | [rest] =>
    let tok := rest.takeWhile Char.isLower
    if families.contains tok &&
        !families.any (fun f => within f ((rest.drop tok.length).takeWhile (· != '.'))) then
      some ⟨⟨"claude", "author"⟩, String.ofList tok⟩
    else none
  | _ => none

def cell (g : Global) (n : Pr) : Option (List Char) := g.rows.bind (·.lookup n)

/-! ## The other fields -/

def enforced (g : Global) : Bool :=
  g.protection.any fun p => p.admins && p.strict && p.checks.contains "gate"

def updatable (g : Global) (p : Pull) : Bool :=
  p.state == "open" && !p.draft && p.baseRef == "main" && p.baseRepo == g.repo &&
    p.headRepo == some g.repo && g.stacked.any (fun s => !s.contains p.number)

def newest : List Check → Option Check
  | [] => none
  | c :: cs =>
    match newest cs with
    | none => some c
    | some d => if d.id < c.id then some c else some d

def isGate (head : Sha) (c : Check) : Bool :=
  c.name == "gate" && c.app == "github-actions" && c.sha == head

def conclusion (s : String) : Gate :=
  if s == "success" then .success
  else if s == "cancelled" then .cancelled
  else if s == "skipped" then .skipped
  else .failure

def gateOf (head : Sha) (cs : List Check) : Gate :=
  match newest (cs.filter (isGate head)) with
  | none => .missing
  | some c => if c.status == "completed" then conclusion c.conclusion else .pending

def isRabbit (head : Sha) (c : Check) : Bool :=
  c.name == "CodeRabbit" && c.app == "coderabbitai" && c.sha == head

def later (a b : Review) : Bool := decide (b.submitted < a.submitted) ||
  (a.submitted == b.submitted && decide (b.id < a.id))

def lastReview : List Review → Option Review
  | [] => none
  | v :: vs =>
    match lastReview vs with
    | none => some v
    | some w => if later v w then some v else some w

/-- The commit CodeRabbit last reviewed: the head when its check there passed, else the commit of
its newest review with a body. -/
def botAt (head : Sha) (cs : List Check) (vs : List Review) : Option Sha :=
  let reviewed := (lastReview (vs.filter fun v =>
    v.login == "coderabbitai[bot]" && !v.body.isEmpty && isSha v.commit.toList)).map (·.commit)
  match newest (cs.filter (isRabbit head)) with
  | some c => if c.status == "completed" && c.conclusion == "success" then some head else reviewed
  | none => reviewed

def footerLine (l : List Char) : Bool :=
  match lead l with
  | some r => "_Generated by".toList.isPrefixOf r
  | none => false

/-- CLAUDE.md, Attribution: the body has one footer line and no session link. The footer need not
be its last line, because CodeRabbit may append its summary below it. -/
def sessionLink : List Char := ("claude.ai/code/" ++ "session_").toList

def oneFooter (body : String) : Bool :=
  ((lines body.toList).filter footerLine).length == 1 && !within sessionLink body.toList

def answers (g : Global) (s : Post) : Bool :=
  s.login == g.owner && (s.slug.any (fun x => (Speech.apps.lookup x).isSome) ||
    Speech.footer s.body.toList)

def speaks (g : Global) (s : Post) : Bool :=
  s.login == g.owner && s.slug.isNone && !Speech.footer s.body.toList

/-- Default 2 on #190: a comment that holds only `/land` or `/hold` lines needs no answer. -/
def pureWord (b : List Char) : Bool :=
  (lines (Speech.unbom b)).all (fun l => blank l || (Speech.word? l).isSome) &&
    (lines (Speech.unbom b)).any (fun l => (Speech.word? l).isSome)

/-- The owner's posts that no agent post answers: none was created in a later second than the
post was last updated. -/
def unanswered (g : Global) (ss : List Post) : List Post :=
  ss.filter fun s => speaks g s && !pureWord s.body.toList &&
    !ss.any fun a => answers g a && decide (s.updated < a.created)

def counts (v : Review) : Bool :=
  v.state == "APPROVED" || v.state == "CHANGES_REQUESTED" || !v.body.isEmpty

def posts (r : Reads) : List Post :=
  (r.comments.getD []).map (fun c => ⟨c.login, c.slug, c.created, c.updated, c.body⟩) ++
    r.reviewComments.getD [] ++
    ((r.reviews.getD []).filter counts).map fun v => ⟨v.login, none, v.submitted, v.submitted, v.body⟩

/-- The paths of the CI step "Spec changes need the spec-approved label". -/
def specPath (p : String) : Bool :=
  p == "statements.lock" || p == "models.lock" || p.endsWith "/statements.lock" ||
    p.endsWith "/models.lock" || "core/Challenge/".isPrefixOf p || p == "core/comparator.json" ||
    p == "core/Mitos/Core" || p == "core/Mitos/Core.lean" || "core/Mitos/Core/".isPrefixOf p

def rest (g : Global) (p : Pull) (r : Reads) : Bool :=
  oneFooter p.body && (unanswered g (posts r)).isEmpty &&
    (!(r.files.map (·.any specPath)).getD true || p.labels.contains "spec-approved")

def complete (g : Global) (p : Pull) (r : Reads) : Bool :=
  g.protection.isSome && g.stacked.isSome && g.rows.isSome && r.comments.isSome &&
    r.reviewComments.isSome && r.reviews.isSome && (activity p r).isSome && r.files.isSome &&
    r.checks.isSome

def ctx (g : Global) (p : Pull) (r : Reads) : Speech.Ctx :=
  { owner := g.owner, pr := p.number, known := known ((activity p r).getD []) }

def obs (g : Global) (p : Pull) (r : Reads) (x : Git) : Obs :=
  { pr := p.number, updatable := updatable g p, enforced := enforced g, head := p.head,
    pushes := ((activity p r).getD []).map toLand, ids := x.ids, paths := r.files, base := x.base,
    gate := gateOf p.head (r.checks.getD []), author := (cell g p.number).bind authorOf,
    verdicts := ((cell g p.number).map (verdictsOf (ctx g p r).known)).getD [],
    botAt := botAt p.head (r.checks.getD []) (r.reviews.getD []), delegates := Speech.delegates,
    words := (Speech.words (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
      (complete g p r)).1,
    rest := rest g p r }

def abouts : List Word → List Sha
  | [] => []
  | .ownerLand m :: ws => m.about :: abouts ws
  | .agentLand _ m :: ws => m.about :: abouts ws
  | .ownerHold _ :: ws => abouts ws

/-- The commits whose content id the decision may compare. -/
def wanted (o : Obs) : List Sha :=
  (o.head :: (match o.base with
    | .clean r => [r]
    | _ => []) ++ o.verdicts.map (·.head) ++ abouts o.words ++ o.botAt.toList).eraseDups

/-! ## Statements -/

def FailedReadHolds : Prop :=
  ∀ g p r x, complete g p r = false →
    (∀ e : Entry, e.valid (obs g p r x) = false) ∧ ∀ me q, Land.step me q (obs g p r x) = .stop .held

def EnforcedNeedsProtection : Prop :=
  ∀ g p r x, (obs g p r x).enforced = true →
    ∃ pr, g.protection = some pr ∧ pr.admins = true ∧ pr.strict = true ∧ "gate" ∈ pr.checks

def UpdatableNeedsTheGuard : Prop :=
  ∀ g p r x, (obs g p r x).updatable = true →
    p.state = "open" ∧ p.draft = false ∧ p.baseRef = "main" ∧ p.baseRepo = g.repo ∧
      p.headRepo = some g.repo ∧ ∃ s, g.stacked = some s ∧ p.number ∉ s

def UnreadFilesAreKept : Prop :=
  ∀ g p r x, r.files = none → (obs g p r x).kept = true ∧ (obs g p r x).critical = true

def OnlyTheOwnerQueues : Prop :=
  ∀ g p r x, ∀ e ∈ (obs g p r x).entries, e.lander = .owner

def GreenIsTheNewestGateRun : Prop :=
  ∀ head cs, gateOf head cs = .success →
    ∃ c ∈ cs, isGate head c = true ∧ c.status = "completed" ∧ c.conclusion = "success" ∧
      ∀ d ∈ cs, isGate head d = true → d.id ≤ c.id

def PushesAreTheActivity : Prop :=
  ∀ g p r x, (obs g p r x).pushes ≠ [] →
    ∃ ps, activity p r = some ps ∧ (obs g p r x).pushes = ps.map toLand ∧ Carry.tip p.head ps = true ∧
      ∀ s ∈ known ps, isSha s.toList = true

def VerdictsFromTheCell : Prop :=
  ∀ g p r x, ∀ v ∈ (obs g p r x).verdicts,
    ∃ c s, cell g p.number = some c ∧ said? c = some s ∧ v.result = s.result ∧
      v.head ∈ (ctx g p r).known ∧ s.sha.isPrefixOf v.head.toList = true ∧
      ∀ k ∈ (ctx g p r).known, s.sha.isPrefixOf k.toList = true → k = v.head

def PassNamesNoFail : Prop :=
  ∀ c s, said? c = some s → s.result ≠ .fail → within "FAIL".toList ((unwrap c).drop 1) = false

def RestNeedsAnswersAndTheLabel : Prop :=
  ∀ g p r x, (obs g p r x).rest = true →
    oneFooter p.body = true ∧ unanswered g (posts r) = [] ∧
      ((r.files.map (·.any specPath)).getD true = true → "spec-approved" ∈ p.labels)

theorem failedReadHolds : FailedReadHolds := by
  intro g p r x hc
  obtain ⟨n, hn⟩ := Speech.incompleteReadHolds (ctx g p r) (r.comments.getD []) ((activity p r).getD [])
  have h : Land.newestOwner (obs g p r x).words = some (.ownerHold n) := by
    simp only [obs, hc]
    exact hn
  exact Land.holdWins _ n h

theorem enforcedNeedsProtection : EnforcedNeedsProtection := by
  intro g p r x h
  simp only [obs, enforced] at h
  cases hp : g.protection with
  | none => rw [hp] at h; cases h
  | some pr =>
    rw [hp] at h
    simp only [Option.any_some, Bool.and_eq_true, List.contains_iff_mem] at h
    exact ⟨pr, rfl, h.1.1, h.1.2, h.2⟩

theorem updatableNeedsTheGuard : UpdatableNeedsTheGuard := by
  intro g p r x h
  simp only [obs, updatable, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩ := h
  refine ⟨h1, h2, h3, h4, h5, ?_⟩
  cases hs : g.stacked with
  | none => rw [hs] at h6; cases h6
  | some s =>
    rw [hs] at h6
    simp at h6
    exact ⟨s, rfl, h6⟩

theorem unreadFilesAreKept : UnreadFilesAreKept := by
  intro g p r x h
  simp [obs, Obs.kept, Obs.critical, h]

theorem onlyTheOwnerQueues : OnlyTheOwnerQueues := by
  intro g p r x e he
  cases hl : e.lander with
  | owner => rfl
  | agent t =>
    have := (Land.onlyMergersQueue _ e t he hl).2
    simp [obs, Speech.delegates] at this

theorem newest_isSome (c : Check) (cs : List Check) : (newest (c :: cs)).isSome = true := by
  simp only [newest]
  split
  · rfl
  · split <;> rfl

theorem newest_mem {cs : List Check} {c : Check} (h : newest cs = some c) :
    c ∈ cs ∧ ∀ d ∈ cs, d.id ≤ c.id := by
  induction cs generalizing c with
  | nil => cases h
  | cons a cs ih =>
    cases hn : newest cs with
    | none =>
      have hcs : cs = [] := by
        cases cs with
        | nil => rfl
        | cons b bs =>
          have := newest_isSome b bs
          rw [hn] at this
          cases this
      subst hcs
      simp only [newest] at h
      cases h
      simp
    | some b =>
      simp only [newest, hn] at h
      obtain ⟨hb, hbm⟩ := ih hn
      split at h
      · next hlt =>
        cases h
        refine ⟨List.mem_cons_self, fun d hd => ?_⟩
        rcases List.mem_cons.1 hd with rfl | hd
        · exact Nat.le_refl _
        · exact Nat.le_of_lt (Nat.lt_of_le_of_lt (hbm d hd) hlt)
      · next hge =>
        cases h
        refine ⟨List.mem_cons_of_mem _ hb, fun d hd => ?_⟩
        rcases List.mem_cons.1 hd with rfl | hd
        · exact Nat.le_of_not_lt hge
        · exact hbm d hd

theorem greenIsTheNewestGateRun : GreenIsTheNewestGateRun := by
  intro head cs h
  simp only [gateOf] at h
  cases hn : newest (cs.filter (isGate head)) with
  | none => rw [hn] at h; cases h
  | some c =>
    rw [hn] at h
    obtain ⟨hm, hmax⟩ := newest_mem hn
    rw [List.mem_filter] at hm
    simp only at h
    split at h
    · next hs =>
      refine ⟨c, hm.1, hm.2, by simpa using hs, ?_, fun d hd hg => hmax d (List.mem_filter.2 ⟨hd, hg⟩)⟩
      unfold conclusion at h
      split at h
      · next hsu => simpa using hsu
      · split at h
        · cases h
        · split at h <;> cases h
    · cases h

theorem pushesAreTheActivity : PushesAreTheActivity := by
  intro g p r x h
  simp only [obs] at h ⊢
  cases ha : activity p r with
  | none => rw [ha] at h; simp at h
  | some ps =>
    refine ⟨ps, rfl, rfl, ?_, ?_⟩
    · simp only [activity, Option.filter] at ha
      split at ha
      · split at ha
        · next hok => cases ha; simp only [pushesOk, Bool.and_eq_true] at hok; exact hok.2
        · cases ha
      · cases ha
    · intro s hs
      simp only [activity, Option.filter] at ha
      split at ha
      · split at ha
        · next hok =>
          cases ha
          simp only [pushesOk, Bool.and_eq_true, List.all_eq_true] at hok
          simp only [known, List.mem_flatMap, List.mem_cons, List.not_mem_nil, or_false] at hs
          obtain ⟨q, hq, rfl | rfl⟩ := hs
          · exact (hok.1.1 q hq).1
          · exact (hok.1.1 q hq).2
        · cases ha
      · cases ha

theorem resolveKnown_spec {known : List Sha} {p : List Char} {s : Sha}
    (h : resolveKnown known p = some s) :
    s ∈ known ∧ p.isPrefixOf s.toList = true ∧
      ∀ k ∈ known, p.isPrefixOf k.toList = true → k = s := by
  unfold resolveKnown at h
  split at h
  · cases h
  · next s' rest hm =>
    split at h
    · next ha =>
      cases h
      have hmem : s ∈ Speech.matching known p := by rw [hm]; exact List.mem_cons_self
      simp only [Speech.matching, List.mem_filter] at hmem
      refine ⟨hmem.1, hmem.2, fun k hk hkp => ?_⟩
      have : k ∈ Speech.matching known p := List.mem_filter.2 ⟨hk, hkp⟩
      rw [hm] at this
      rcases List.mem_cons.1 this with rfl | this
      · rfl
      · simpa using List.all_eq_true.1 ha k this
    · cases h

theorem verdictsOf_spec {known : List Sha} {c : List Char} {v : Verdict}
    (h : v ∈ verdictsOf known c) :
    ∃ s, said? c = some s ∧ v.result = s.result ∧ resolveKnown known s.sha = some v.head := by
  unfold verdictsOf at h
  split at h
  · cases h
  · next s hs =>
    split at h
    · cases h
    · next hd hr =>
      refine ⟨s, hs, ?_⟩
      split at h
      · next hw =>
        simp only [List.mem_singleton] at h
        subst h
        exact ⟨(beq_iff_eq.1 hw).symm, hr⟩
      · simp only [List.mem_map] at h
        obtain ⟨f, -, rfl⟩ := h
        exact ⟨rfl, hr⟩

theorem verdictsFromTheCell : VerdictsFromTheCell := by
  intro g p r x v hv
  simp only [obs] at hv
  cases hc : cell g p.number with
  | none => rw [hc] at hv; simp at hv
  | some c =>
    rw [hc] at hv
    simp only [Option.map_some, Option.getD_some] at hv
    obtain ⟨s, hs, hres, hk⟩ := verdictsOf_spec hv
    obtain ⟨h1, h2, h3⟩ := resolveKnown_spec hk
    exact ⟨c, s, rfl, hs, hres, h1, h2, h3⟩

theorem passNamesNoFail : PassNamesNoFail := by
  intro c s h hf
  unfold said? at h
  split at h
  · next r rest hr =>
    split at h
    · split at h
      · next hok =>
        cases h
        simp only [Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, Bool.not_eq_true'] at hok
        rcases hok.2 with h | h
        · exact absurd h hf
        · exact h
      · cases h
    · cases h
  · cases h

theorem restNeedsAnswersAndTheLabel : RestNeedsAnswersAndTheLabel := by
  intro g p r x h
  simp only [obs, rest, Bool.and_eq_true, List.isEmpty_iff, Bool.or_eq_true, Bool.not_eq_true',
    List.contains_iff_mem] at h
  obtain ⟨⟨h1, h2⟩, h3⟩ := h
  refine ⟨h1, h2, fun hs => ?_⟩
  rcases h3 with h3 | h3
  · rw [hs] at h3; cases h3
  · exact h3

/-! ## Fixtures -/

namespace Fixture

def hA : Sha := "5c258d6aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
def hB : Sha := "85b0781bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
def hC : Sha := "5c258d6ccccccccccccccccccccccccccccccccc"
def known : List Sha := [hB, hA]

def v (s : String) : List (Nat × Sha × Teammate × String × Result) :=
  (verdictsOf known s.toList).map fun x => (x.said, x.head, x.judge, x.model, x.result)

theorem carriedPassOfOneJudge :
    v "PASS opus-xhigh carried from `5c258d6a`, author sonnet (round 2). Minors #241." =
      [(0, hA, ⟨"claude", "verifier-opus"⟩, "opus", .pass)] := by decide +kernel
theorem twoJudges :
    (v "PASS sonnet-xhigh + opus-xhigh at 85b0781").map (·.2.2.1.name) =
      ["verifier-sonnet", "verifier-opus"] := by decide +kernel
theorem failOfOneJudge :
    (v "**FAIL opus-xhigh at `85b0781`**: the line stalls").map (·.2.2.2.2) = [.fail] := by
  decide +kernel
theorem wordingOnlyIsTheRoots :
    v "wording-only at `85b0781`" = [(0, hB, root, "unknown", .wordingOnly)] := by decide +kernel
theorem noVerdictSaysNothing : v "No verdict. Opened by Grok Bot." = [] := by decide +kernel
theorem passThenFailSaysNothing :
    v "PASS opus-xhigh at `85b0781`. Then FAIL sonnet-xhigh at `85b0781`." = [] := by
  decide +kernel
theorem judgelessPassSaysNothing : v "PASS carried from `85b0781`" = [] := by decide +kernel
theorem judgesInAParenthesis :
    (v "PASS carried from `5c258d6a` (sonnet-xhigh + opus-xhigh, author opus), two rebases.").map
      (fun x => (x.2.1, x.2.2.1.name)) = [(hA, "verifier-sonnet"), (hA, "verifier-opus")] := by
  decide +kernel
theorem judgesInBothPlacesSayNothing : v "PASS opus-xhigh at `85b0781` (sonnet-xhigh)" = [] := by
  decide +kernel
theorem aParenthesisOfProseIsNoJudge : v "PASS carried from `85b0781` (carry exit 0)" = [] := by
  decide +kernel
theorem aParenthesisAfterAWordIsNoJudge :
    v "PASS carried from `85b0781`, then (opus-xhigh)" = [] := by decide +kernel
theorem unknownEffortSaysNothing : v "PASS opus-huge at `85b0781`" = [] := by decide +kernel
theorem judgedWordingOnlySaysNothing : v "wording-only opus-xhigh at `85b0781`" = [] := by
  decide +kernel
theorem ambiguousPrefixSaysNothing :
    (verdictsOf [hA, hC] "PASS opus-xhigh at `5c258d6`".toList).isEmpty = true := by
  decide +kernel
theorem unknownCommitSaysNothing : v "PASS opus-xhigh at `deadbee`" = [] := by decide +kernel
theorem shortShaSaysNothing : v "PASS opus-xhigh at `85b078`" = [] := by decide +kernel
theorem unclosedTickSaysNothing : v "PASS opus-xhigh at `85b0781" = [] := by decide +kernel
theorem upperCaseHexSaysNothing : v "PASS opus-xhigh at 85B0781" = [] := by decide +kernel
theorem lowerCasePassSaysNothing : v "pass opus-xhigh at 85b0781" = [] := by decide +kernel

def a (s : String) : Option (Teammate × String) :=
  (authorOf s.toList).map fun x => (x.who, x.model)

theorem authorNoteInAParenthesis :
    a "PASS carried from `5c258d6` (opus-xhigh, author sonnet, round 2), through the rebases." =
      some (⟨"claude", "author"⟩, "sonnet") := by decide +kernel
theorem authorNote :
    a "PASS opus-xhigh carried from `5c258d6`, author sonnet (round 2)." =
      some (⟨"claude", "author"⟩, "sonnet") := by decide +kernel
theorem mixedAuthorIsNone :
    a "PASS opus-xhigh at `5c258d6`, author sonnet, fixed by opus." = none := by decide +kernel
theorem twoAuthorNotesAreNone :
    a "PASS opus-xhigh at `5c258d6`, author sonnet. Earlier author opus." = none := by
  decide +kernel
theorem noAuthorNoteIsNone : a "PASS opus-xhigh at `5c258d6`." = none := by decide +kernel
theorem coauthorIsNoNote : a "PASS opus-xhigh at `5c258d6`, coauthor sonnet." = none := by
  decide +kernel
theorem unknownModelIsNone : a "PASS opus-xhigh at `5c258d6`, author gpt." = none := by
  decide +kernel

def dash (rows : String) : String :=
  "Intro.\n\n## Needs you\n\n- | #1 | not | a | row |\n\n## In flight\n\n" ++
    "| PR | Head | `gate` | Verdict |\n|---|---|---|---|\n" ++ rows ++
    "\nMerged in the last 24 hours:\n- #9 merged\n\n## Next up\n\n| #5 | x | y | z |\n"

theorem inFlightRows :
    rows (dash "| #7 a PR | `85b0781` | green | PASS opus-xhigh at `85b0781` |\n| #8 b | `x` | running | No verdict |") =
      some [(7, "PASS opus-xhigh at `85b0781`".toList), (8, "No verdict".toList)] := by
  decide +kernel
theorem twoRowsForOnePrSpoilTheDashboard :
    rows (dash "| #7 a | `x` | green | PASS opus-xhigh at `85b0781` |\n| #7 b | `x` | red | No verdict |") =
      none := by decide +kernel
theorem aFifthColumnSpoilsTheDashboard :
    rows (dash "| #7 a | `x` | green | PASS opus-xhigh at `85b0781` | extra |") = none := by
  decide +kernel
theorem aRowWithoutANumberSpoilsTheDashboard :
    rows (dash "| 7 a | `x` | green | PASS opus-xhigh at `85b0781` |") = none := by decide +kernel
theorem aPipeInACellSpoilsTheDashboard :
    rows (dash "| #7 a | `x` | green | PASS opus-xhigh at `85b0781` `a|b` |") = none := by
  decide +kernel
theorem noInFlightSectionIsUnread : rows "## Needs you\n\n| #7 | x | y | z |\n" = none := by
  decide +kernel
theorem twoInFlightSectionsAreUnread :
    rows "## In flight\n\n| #7 | x | y | z |\n## In flight\n" = none := by decide +kernel
theorem crlfDashboard :
    rows "## In flight\r\n\r\n| #7 a | x | y | PASS opus-xhigh at 85b0781 |\r\n" =
      some [(7, "PASS opus-xhigh at 85b0781".toList)] := by decide +kernel

def owner : String := "owner"
def repo : String := "owner/mitos"
def protection : Protection := ⟨true, true, ["gate"]⟩
def row (verdict : String) : Option (List (Nat × List Char)) := some [(7, verdict.toList)]
def g : Global :=
  { repo, owner, protection := some protection, stacked := some [],
    rows := row "PASS opus-xhigh at `85b0781`, author sonnet" }
def withRow (verdict : String) : Global := { g with rows := row verdict }
def footer : String := "\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_"
def pull : Pull :=
  { number := 7, state := "open", draft := false, head := hB, headRepo := some repo,
    baseRef := "main", baseRepo := repo, labels := [], body := "Why." ++ footer }
def pushes : List Carry.Push :=
  [⟨"2026-11-14T07:00:36Z", "force_push", Carry.updater, hA, hB⟩,
   ⟨"2026-11-13T19:51:49Z", "branch_creation", owner, "0000000000000000000000000000000000000000",
    hA⟩]
def gateRun : Check := ⟨10, "gate", "github-actions", hB, "completed", "success"⟩
def rabbit : Review := ⟨3, "coderabbitai[bot]", "COMMENTED", hB, 20261114070100, "Review."⟩
def land : Comment := ⟨900, owner, none, 20261114080000, 20261114080000, "/land"⟩
def question : Comment := ⟨800, owner, none, 20261114075900, 20261114075900, "why this?"⟩
def answer (t : Stamp) : Comment := ⟨850, owner, some "claude", t, t, "Because." ++ footer⟩
def reads : Reads :=
  { comments := some [land], reviewComments := some [], reviews := some [rabbit],
    activity := some pushes, files := some ["gate/Main.lean"], checks := some [gateRun] }
def withComments (cs : List Comment) : Reads := { reads with comments := some cs }
def withReviewComments (ps : List Post) : Reads := { reads with reviewComments := some ps }
def withActivity (ps : List Carry.Push) : Reads := { reads with activity := some ps }
def withChecks (cs : List Check) : Reads := { reads with reviews := some [], checks := some cs }
def git : Git := ⟨[(hB, "id-1"), (hA, "id-1")], .current⟩
def o (g : Global := g) (p : Pull := pull) (r : Reads := reads) (x : Git := git) : Obs :=
  obs g p r x
def o0 : Obs := o
def stepOf (g : Global := g) (p : Pull := pull) (r : Reads := reads) (x : Git := git) :
    Land.Step :=
  let ob := o g p r x
  Land.step Land.Fixture.orchestrator (Land.queueOf [ob]) ob
def step0 : Land.Step := stepOf
def carried : String := "PASS opus-xhigh carried from `5c258d6`, author sonnet"

theorem allReadAndCoveredIsPresented : step0 = .present hB := by decide +kernel
theorem theOwnersLandIsTheEntry : o0.words = [.ownerLand ⟨1800, hB⟩] := by decide +kernel
theorem unreadCommentsHold : stepOf (r := { reads with comments := none }) = .stop .held := by
  decide +kernel
theorem unreadReviewCommentsHold :
    stepOf (r := { reads with reviewComments := none }) = .stop .held := by decide +kernel
theorem unreadReviewsHold : stepOf (r := { reads with reviews := none }) = .stop .held := by
  decide +kernel
theorem unreadActivityHolds : stepOf (r := { reads with activity := none }) = .stop .held := by
  decide +kernel
theorem unreadFilesHold : stepOf (r := { reads with files := none }) = .stop .held := by
  decide +kernel
theorem unreadChecksHold : stepOf (r := { reads with checks := none }) = .stop .held := by
  decide +kernel
theorem unreadProtectionHolds : stepOf (g := { g with protection := none }) = .stop .held := by
  decide +kernel
theorem unreadStacksHold : stepOf (g := { g with stacked := none }) = .stop .held := by
  decide +kernel
theorem unreadDashboardHolds : stepOf (g := { g with rows := none }) = .stop .held := by
  decide +kernel
theorem activityAtAnotherHeadHolds :
    stepOf (p := { pull with head := hC }) = .stop .held := by decide +kernel
theorem activityOutOfOrderHolds :
    stepOf (r := withActivity (pushes ++ [⟨"2026-11-13T20:00:00Z", "push", owner, hC, hA⟩])) =
      .stop .held := by decide +kernel
theorem activityListedOldestFirstHolds :
    stepOf (r := { reads with activity := some pushes.reverse }) = .stop .held := by decide +kernel
theorem activityWithANonShaHolds :
    stepOf (r := withActivity (pushes ++ [⟨"2026-11-13T19:00:00Z", "push", owner, "HEAD", hA⟩])) =
      .stop .held := by decide +kernel
theorem protectionWithoutAdminsIsUnenforced :
    stepOf (g := { g with protection := some { protection with admins := false } }) =
      .stop .unenforced := by decide +kernel
theorem protectionWithoutGateIsUnenforced :
    stepOf (g := { g with protection := some { protection with checks := ["ci"] } }) =
      .stop .unenforced := by decide +kernel
theorem aStackedPullRequestIsNotEligible :
    stepOf (g := { g with stacked := some [7] }) = .stop .notEligible := by decide +kernel
theorem aDraftIsNotEligible : stepOf (p := { pull with draft := true }) = .stop .notEligible := by
  decide +kernel
theorem aForkIsNotEligible :
    stepOf (p := { pull with headRepo := some "other/mitos" }) = .stop .notEligible := by
  decide +kernel
theorem anotherBaseIsNotEligible :
    stepOf (p := { pull with baseRef := "dev" }) = .stop .notEligible := by decide +kernel
theorem noRowIsNotEligible :
    stepOf (g := { g with rows := some [] }) = .stop .notEligible := by decide +kernel
theorem anOpusPassOnATrustPathCoversASonnetAuthor : o0.covered = true := by decide +kernel
theorem anOpusAuthorIsNotCoveredByItsOwnModel :
    stepOf (g := withRow "PASS opus-xhigh at `85b0781`, author opus") = .stop .notEligible := by
  decide +kernel
theorem noAuthorNoteIsNotEligible :
    stepOf (g := withRow "PASS opus-xhigh at `85b0781`") = .stop .notEligible := by decide +kernel
theorem aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush :
    stepOf (g := withRow carried) = .present hB := by decide +kernel
theorem aVerdictOnOtherContentDoesNotCarry :
    stepOf (g := withRow carried) (x := ⟨[(hB, "id-1"), (hA, "id-2")], .current⟩) =
      .stop .notEligible := by decide +kernel
theorem anOwnerQuestionWithoutAnswerIsNotEligible :
    stepOf (r := withComments [question, land]) = .stop .notEligible := by decide +kernel
theorem anAnsweredOwnerQuestionIsEligible :
    stepOf (r := withComments [question, answer 20261114075930, land]) = .present hB := by
  decide +kernel
theorem anAnswerInTheSameSecondIsNoAnswer :
    stepOf (r := withComments [question, answer 20261114075900, land]) = .stop .notEligible := by
  decide +kernel
theorem anUnansweredReviewCommentIsNotEligible :
    stepOf (r := withReviewComments [⟨owner, none, 20261114075900, 20261114075900, "rename"⟩]) =
      .stop .notEligible := by decide +kernel
theorem aLandAfterAByteOrderMarkNeedsNoAnswer :
    stepOf (r := withComments [{ land with body := "﻿/land" }]) = .present hB := by
  decide +kernel
theorem anOtherLoginsCommentNeedsNoAnswer :
    stepOf (r := withReviewComments [⟨"someone", none, 20261114075900, 20261114075900, "rename"⟩]) =
      .present hB := by decide +kernel
theorem aBodyWithoutTheFooterIsNotEligible :
    stepOf (p := { pull with body := "Why." }) = .stop .notEligible := by decide +kernel
theorem aBodyWithTwoFootersIsNotEligible :
    stepOf (p := { pull with body := "Why." ++ footer ++ footer }) = .stop .notEligible := by
  decide +kernel
theorem aSummaryBelowTheFooterIsPresented :
    stepOf (p := { pull with body := "Why." ++ footer ++ "\n\n## Summary by CodeRabbit\n" }) =
      .present hB := by decide +kernel
theorem aSessionLinkIsNotEligible :
    stepOf (p := { pull with body := "Why. " ++ String.ofList sessionLink ++ "x" ++ footer }) =
      .stop .notEligible := by decide +kernel
theorem aSpecPathWithoutTheLabelIsNotEligible :
    stepOf (r := { reads with files := some ["core/Mitos/Core/Graph.lean"] }) =
      .stop .notEligible := by decide +kernel
theorem aSpecPathWithTheLabelIsPresented :
    stepOf (p := { pull with labels := ["spec-approved"] })
      (r := { reads with files := some ["examples/acme/models.lock"] }) = .present hB := by
  decide +kernel
theorem noBotReviewIsNotEligible :
    stepOf (r := { reads with reviews := some [] }) = .stop .notEligible := by decide +kernel
theorem aReviewByAnotherLoginIsNoBotReview :
    stepOf (r := { reads with reviews := some [{ rabbit with login := "someone" }] }) =
      .stop .notEligible := by decide +kernel
theorem aPassedRabbitCheckAtTheHeadIsAReview :
    stepOf (r := withChecks [gateRun, ⟨11, "CodeRabbit", "coderabbitai", hB, "completed", "success"⟩]) =
      .present hB := by decide +kernel
theorem aGateRunFromAnotherAppIsNoGate :
    gateOf hB [⟨12, "gate", "other-app", hB, "completed", "success"⟩] = .missing := by decide +kernel
theorem theNewestGateRunCounts :
    gateOf hB [gateRun, ⟨12, "gate", "github-actions", hB, "completed", "cancelled"⟩] =
      .cancelled := by decide +kernel
theorem aGateRunAtAnotherHeadIsNoGate :
    gateOf hB [⟨12, "gate", "github-actions", hA, "completed", "success"⟩] = .missing := by
  decide +kernel
theorem aRunningGateIsPending :
    gateOf hB [⟨12, "gate", "github-actions", hB, "in_progress", ""⟩] = .pending := by decide +kernel
theorem aTimedOutGateIsRed :
    gateOf hB [⟨12, "gate", "github-actions", hB, "completed", "timed_out"⟩] = .failure := by
  decide +kernel
theorem theContentIdsAsked : wanted (o (g := withRow carried)) = [hB, hA] := by decide +kernel
theorem eachFailedReadIsIncomplete :
    [complete { g with protection := none } pull reads, complete { g with stacked := none } pull reads,
     complete { g with rows := none } pull reads, complete g pull { reads with comments := none },
     complete g pull { reads with reviewComments := none },
     complete g pull { reads with reviews := none }, complete g pull { reads with activity := none },
     complete g pull { reads with files := none }, complete g pull { reads with checks := none },
     complete g pull reads] =
      [false, false, false, false, false, false, false, false, false, true] := by decide +kernel

end Fixture

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.map₂.foldl (fun acc n c =>
    if (`MitosGate.Snapshot.Fixture).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``failedReadHolds, ``enforcedNeedsProtection, ``updatableNeedsTheGuard,
      ``unreadFilesAreKept, ``onlyTheOwnerQueues, ``greenIsTheNewestGateRun,
      ``pushesAreTheActivity, ``verdictsFromTheCell, ``passNamesNoFail,
      ``restNeedsAnswersAndTheLabel] ++ fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Snapshot
