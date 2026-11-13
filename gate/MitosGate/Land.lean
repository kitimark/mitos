import Lean.CoreM
import Lean.Util.CollectAxioms

/-!
What is proved is the decision over a snapshot. That the snapshot says what GitHub says is the
reader's, and is not proved here.
-/

namespace MitosGate.Land

abbrev Sha := String
abbrev Pr := Nat

structure Teammate where
  provider : String
  name : String
  deriving DecidableEq

structure Push where
  byUpdater : Bool
  before : Sha
  after : Sha

inductive Result
  | pass | fail | hold | wordingOnly
  deriving DecidableEq

structure Verdict where
  said : Nat
  head : Sha
  judge : Teammate
  model : String
  result : Result

structure Author where
  who : Teammate
  model : String

structure Mark where
  said : Nat
  about : Sha
  deriving DecidableEq

inductive Word
  | ownerLand (m : Mark)
  | ownerHold (said : Nat)
  | agentLand (who : Teammate) (m : Mark)

inductive Base
  | current | clean (replay : Sha) | conflict | mergedMain | unread
  deriving DecidableEq

inductive Gate
  | success | failure | cancelled | skipped | pending | missing
  deriving DecidableEq

structure Obs where
  pr : Pr
  updatable : Bool
  enforced : Bool
  head : Sha
  pushes : List Push
  ids : List (Sha × String)
  paths : Option (List String)
  base : Base
  gate : Gate
  author : Option Author
  verdicts : List Verdict
  botAt : Option Sha
  delegates : List Teammate
  words : List Word
  rest : Bool

def walk (v : Sha) : Sha → List Push → Bool
  | cur, [] => cur == v
  | cur, p :: ps => cur == v || (p.after == cur && p.byUpdater && walk v p.before ps)

def Obs.id? (o : Obs) (s : Sha) : Option String := (o.ids.find? (·.1 == s)).map (·.2)

def Obs.carries (o : Obs) (v : Sha) : Bool :=
  walk v o.head o.pushes && (o.id? v).isSome && o.id? v == o.id? o.head

def rulePath (p : String) : Bool :=
  [".claude/", ".cursor/", "plan/"].any (·.isPrefixOf p) ||
  ["CLAUDE.md", "docs/process.md"].contains p

def criticalPath (p : String) : Bool :=
  ["gate/", "eval/cheats/", ".github/", "core/Mitos/Core/", "core/Challenge/"].any
    (·.isPrefixOf p) ||
  ["lean-toolchain", "lakefile.toml", "core/lakefile.toml", "core/Mitos/Core.lean",
    "core/comparator.json", "statements.lock", "models.lock"].contains p ||
  p.endsWith "/statements.lock" || p.endsWith "/models.lock"

def keptPath (p : String) : Bool := criticalPath p || rulePath p

def Obs.kept (o : Obs) : Bool := (o.paths.map (·.any keptPath)).getD true
def Obs.critical (o : Obs) : Bool := (o.paths.map (·.any criticalPath)).getD true

def Obs.stands (o : Obs) (v : Verdict) : Prop :=
  o.carries v.head = true ∧
    ∀ w ∈ o.verdicts, o.carries w.head = true → w.judge = v.judge → w.said ≤ v.said

instance (o : Obs) (v : Verdict) : Decidable (o.stands v) := by unfold Obs.stands; infer_instance

def Obs.Covered (o : Obs) : Prop :=
  match o.author with
  | none => False
  | some a =>
    (∀ v ∈ o.verdicts, o.stands v → v.result ≠ .fail ∧ v.result ≠ .hold) ∧
    ((∃ v ∈ o.verdicts, o.stands v ∧ v.result = .wordingOnly ∧ v.judge ≠ a.who) ∨
      ((∃ v ∈ o.verdicts, o.stands v ∧ v.result = .pass ∧ v.judge ≠ a.who ∧ v.model ≠ a.model) ∧
        (o.critical = true → ∃ v ∈ o.verdicts, o.stands v ∧ v.result = .pass ∧
          v.judge ≠ a.who ∧ v.judge.name = "verifier-opus")))

instance (o : Obs) : Decidable o.Covered := by unfold Obs.Covered; split <;> infer_instance

def Obs.covered (o : Obs) : Bool := decide o.Covered

def Obs.reviewed (o : Obs) : Bool := o.botAt.any o.carries

def Obs.keeps (o : Obs) (r : Sha) : Bool := (o.id? r).isSome && o.id? r == o.id? o.head

def Obs.eligible (o : Obs) : Bool :=
  o.updatable && o.enforced && o.covered && o.reviewed && o.rest

def Obs.mayMerge (o : Obs) (t : Teammate) : Bool := !o.kept && o.delegates.contains t

def Word.byOwner : Word → Bool
  | .agentLand _ _ => false
  | _ => true

def newestOwner : List Word → Option Word
  | [] => none
  | w :: ws =>
    match newestOwner ws with
    | some x => some x
    | none => if w.byOwner then some w else none

structure Entry where
  pr : Pr
  mark : Mark
  lander : Option Teammate
  deriving DecidableEq

def Obs.entries (o : Obs) : List Entry :=
  let agents := o.words.filterMap fun
    | .agentLand t m => if o.mayMerge t then some ⟨o.pr, m, some t⟩ else none
    | _ => none
  match newestOwner o.words with
  | some (.ownerHold _) => []
  | some (.ownerLand m) => ⟨o.pr, m, none⟩ :: agents
  | _ => agents

def Entry.valid (e : Entry) (o : Obs) : Bool :=
  o.entries.contains e && o.eligible && o.carries e.mark.about

inductive Stuck
  | conflict | contentChanged | red | historyError | unread
  deriving DecidableEq

def Obs.stuck? (o : Obs) : Option Stuck :=
  if o.gate == .failure then some .red
  else
    match o.base with
    | .conflict => some .conflict
    | .clean r => if o.keeps r then none else some .contentChanged
    | .mergedMain => some .historyError
    | .unread => some .unread
    | _ => none

abbrev Queue := List (Entry × Obs)

def queueOf (os : List Obs) : Queue := os.flatMap fun o => o.entries.map fun e => (e, o)

def landable (x : Entry × Obs) : Bool := x.1.valid x.2 && x.2.stuck?.isNone

def rank (e : Entry) (o : Obs) : Nat × Nat × Nat :=
  (if e.lander.isNone then 0 else 1, if o.base == .current then 0 else 1, e.mark.said)

def before (a b : Nat × Nat × Nat) : Bool :=
  decide (a.1 < b.1) ||
    (a.1 == b.1 && (decide (a.2.1 < b.2.1) || (a.2.1 == b.2.1 && decide (a.2.2 ≤ b.2.2))))

def next : Queue → Option (Entry × Obs)
  | [] => none
  | x :: rest =>
    match next rest with
    | none => if landable x then some x else none
    | some y => if landable x && before (rank x.1 x.2) (rank y.1 y.2) then some x else some y

inductive Plan
  /-- Push the replay with `--force-with-lease=<ref>:<expect>`, if it has the tree of `replay`. -/
  | push (pr : Pr) (expect replay : Sha)
  | idle
  deriving DecidableEq

def plan (q : Queue) : Plan :=
  match next q with
  | some (_, o) =>
    match o.base with
    | .clean r => .push o.pr o.head r
    | _ => .idle
  | none => .idle

def pushed (r : Sha) (o : Obs) : Obs :=
  { o with head := r, base := .current, gate := .pending, pushes := ⟨true, o.head, r⟩ :: o.pushes }

inductive Stop
  | held | unenforced | notEligible | stuck (why : Stuck) | noEntry
  deriving DecidableEq

inductive Step
  | enter (about : Sha)
  | wait (ahead : Pr)
  | awaitPush (head : Sha)
  | awaitGate (head : Sha)   -- the one `gate`, re-run if it was cancelled
  | merge (head : Sha)       -- rebase-merge pinned to `head`
  | present (head : Sha)
  | stop (why : Stop)
  deriving DecidableEq

def step (me : Teammate) (q : Queue) (o : Obs) : Step :=
  match newestOwner o.words with
  | some (.ownerHold _) => .stop .held
  | _ =>
    if !o.enforced then .stop .unenforced
    else if !o.eligible then .stop .notEligible
    else
      match o.stuck? with
      | some why => .stop (.stuck why)
      | none =>
        if !q.any (fun x => x.2.pr == o.pr && x.1.valid o) then
          if o.mayMerge me then .enter o.head else .stop .noEntry
        else
          match next q with
          | none => .stop .notEligible
          | some (n, _) =>
            if n.pr != o.pr then .wait n.pr
            else
              match o.base, o.gate with
              | .current, .success => if o.mayMerge me then .merge o.head else .present o.head
              | .current, _ => .awaitGate o.head
              | _, _ => .awaitPush o.head

inductive Event
  | mainMoved
  | updaterPushed (pr : Pr)
  | gateDone (pr : Pr) (g : Gate)
  | botReviewed (pr : Pr)
  | conflictFound (pr : Pr)
  | landWord (pr : Pr)
  | ownerSpoke (pr : Pr)
  deriving DecidableEq

inductive Wake
  | nobody
  | lander (pr : Pr)
  | holder (pr : Pr)
  | orchestrator
  deriving DecidableEq

def wake (inLine covered : Pr → Bool) : Event → Wake
  | .mainMoved | .updaterPushed _ => .nobody
  | .gateDone p g =>
    if g == .failure then .holder p
    else if inLine p then .lander p
    else if covered p then .nobody
    else .holder p
  | .botReviewed p => if covered p then .nobody else .holder p
  | .conflictFound p => if covered p then .holder p else .nobody
  | .landWord p => if inLine p then .nobody else .orchestrator
  | .ownerSpoke _ => .orchestrator

def wakeOf (os : List Obs) (e : Event) : Wake :=
  wake (fun p => (queueOf os).any fun x => x.2.pr == p && landable x)
    (fun p => os.any fun o => o.pr == p && o.covered) e

def PushOnlyNext : Prop :=
  ∀ q p s r, plan q = .push p s r →
    ∃ e o, next q = some (e, o) ∧ landable (e, o) = true ∧ o.pr = p ∧ s = o.head ∧
      o.base = .clean r ∧ o.keeps r = true

def NoEntryNoPush : Prop :=
  ∀ q p, (∀ x ∈ q, x.2.pr = p → x.1.valid x.2 = false) → ∀ s r, plan q ≠ .push p s r

def OneLandingAtATime : Prop :=
  ∀ q x, x ∈ q → landable x = true → x.2.base = .current →
    ∀ e o, next q = some (e, o) → o.base ≠ .current → e.lander = none ∧ x.1.lander ≠ none

def PushKeepsCover : Prop :=
  ∀ (o : Obs) (v r : Sha), o.carries v = true → o.keeps r = true → (pushed r o).carries v = true

def PushIsNotRepeated : Prop :=
  ∀ (e : Entry) (o : Obs) (r : Sha), landable (e, o) = true → o.base = .clean r →
    (∀ v ∈ o.verdicts, v.head ≠ r) →
    landable (e, pushed r o) = true ∧ (pushed r o).base = .current

def MergeIsGated : Prop :=
  ∀ me q o h, step me q o = .merge h →
    h = o.head ∧ o.base = .current ∧ o.gate = .success ∧ o.enforced = true ∧
      o.kept = false ∧ me ∈ o.delegates ∧ o.Covered

def UnenforcedLandsNothing : Prop :=
  ∀ (o : Obs), o.enforced = false →
    (∀ e : Entry, e.valid o = false) ∧
      ∀ me q h, step me q o ≠ .merge h ∧ step me q o ≠ .present h

def HoldWins : Prop :=
  ∀ (o : Obs) c, newestOwner o.words = some (.ownerHold c) →
    (∀ e : Entry, e.valid o = false) ∧ ∀ me q, step me q o = .stop .held

def AgentKeepsOwnerWord : Prop :=
  ∀ ws : List Word, newestOwner ws = newestOwner (ws.filter (·.byOwner))

def OnlyMergersQueue : Prop :=
  ∀ (o : Obs) (e : Entry) (t : Teammate), e ∈ o.entries → e.lander = some t →
    o.kept = false ∧ t ∈ o.delegates

def StuckDoesNotBlock : Prop :=
  ∀ q : Queue, (∃ x ∈ q, landable x = true) → ∃ y, next q = some y

def NextNeverWaits : Prop :=
  ∀ me q o e g ahead, next q = some (e, g) → e.pr = o.pr → step me q o ≠ .wait ahead

def NextIgnoresListingOrder : Prop :=
  ∀ q q' : Queue, q.Perm q' → (q.map fun x => x.1.mark.said).Nodup → next q = next q'

def QuietAfterRebase : Prop :=
  ∀ (inLine covered : Pr → Bool) (p : Pr) (g : Gate), covered p = true → g ≠ .failure →
    wake inLine covered .mainMoved = .nobody ∧
      wake inLine covered (.updaterPushed p) = .nobody ∧
      wake inLine covered (.botReviewed p) = .nobody ∧
      (wake inLine covered (.gateDone p g) = .lander p ↔ inLine p = true) ∧
      (inLine p = false → wake inLine covered (.gateDone p g) = .nobody)

theorem next_landable {q : Queue} {x : Entry × Obs} (h : next q = some x) : landable x = true := by
  induction q generalizing x with
  | nil => simp [next] at h
  | cons y rest ih =>
    simp only [next] at h
    split at h
    · split at h
      · next hv => cases h; exact hv
      · cases h
    · next y' hr =>
      split at h
      · next hv =>
        cases h
        simp only [Bool.and_eq_true] at hv
        exact hv.1
      · cases h; exact ih hr

theorem next_mem {q : Queue} {x : Entry × Obs} (h : next q = some x) : x ∈ q := by
  induction q generalizing x with
  | nil => simp [next] at h
  | cons y rest ih =>
    simp only [next] at h
    split at h
    · split at h
      · cases h; exact List.mem_cons_self
      · cases h
    · next y' hr =>
      split at h
      · cases h; exact List.mem_cons_self
      · cases h; exact List.mem_cons_of_mem _ (ih hr)

theorem stuckDoesNotBlock : StuckDoesNotBlock := by
  intro q h
  induction q with
  | nil => obtain ⟨x, hx, _⟩ := h; cases hx
  | cons y rest ih =>
    obtain ⟨x, hx, hv⟩ := h
    simp only [next]
    cases hr : next rest with
    | some y' =>
      simp only
      split
      · exact ⟨_, rfl⟩
      · exact ⟨_, rfl⟩
    | none =>
      rcases List.mem_cons.1 hx with rfl | hx
      · exact ⟨x, by simp [hv]⟩
      · obtain ⟨y', hy⟩ := ih ⟨x, hx, hv⟩
        rw [hr] at hy
        cases hy

theorem before_refl (a : Nat × Nat × Nat) : before a a = true := by
  simp [before]

theorem before_total (a b : Nat × Nat × Nat) : before a b = true ∨ before b a = true := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  omega

theorem before_trans {a b c : Nat × Nat × Nat} (h1 : before a b = true) (h2 : before b c = true) :
    before a c = true := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at *
  omega

theorem next_le {q : Queue} {y : Entry × Obs} (h : next q = some y) :
    ∀ x ∈ q, landable x = true → before (rank y.1 y.2) (rank x.1 x.2) = true := by
  induction q generalizing y with
  | nil => simp [next] at h
  | cons z rest ih =>
    intro x hx hl
    simp only [next] at h
    cases hr : next rest with
    | none =>
      rw [hr] at h
      simp only at h
      split at h
      · cases h
        rcases List.mem_cons.1 hx with rfl | hx
        · exact before_refl _
        · obtain ⟨y', hy⟩ := stuckDoesNotBlock rest ⟨x, hx, hl⟩
          rw [hr] at hy; cases hy
      · cases h
    | some y' =>
      rw [hr] at h
      simp only at h
      split at h
      · next hc =>
        cases h
        simp only [Bool.and_eq_true] at hc
        rcases List.mem_cons.1 hx with rfl | hx
        · exact before_refl _
        · exact before_trans hc.2 (ih hr x hx hl)
      · next hc =>
        cases h
        rcases List.mem_cons.1 hx with rfl | hx
        · rcases before_total (rank y.1 y.2) (rank x.1 x.2) with hb | hb
          · exact hb
          · exfalso; apply hc; simp [hl, hb]
        · exact ih hr x hx hl

theorem pushOnlyNext : PushOnlyNext := by
  intro q p s r h
  simp only [plan] at h
  split at h
  · next e o hn =>
    have hl := next_landable hn
    split at h
    · next r' hb =>
      cases h
      refine ⟨e, o, hn, hl, rfl, rfl, hb, ?_⟩
      simp only [landable, Bool.and_eq_true, Option.isNone_iff_eq_none, Obs.stuck?, hb] at hl
      have h2 := hl.2
      split at h2
      · cases h2
      · split at h2
        · next hk => exact hk
        · cases h2
    · cases h
  · cases h

theorem noEntryNoPush : NoEntryNoPush := by
  intro q p hq s r h
  obtain ⟨e, o, hn, hl, hp, _, _⟩ := pushOnlyNext q p s r h
  have := hq (e, o) (next_mem hn) hp
  simp only [landable, Bool.and_eq_true] at hl
  rw [hl.1] at this
  cases this

theorem oneLandingAtATime : OneLandingAtATime := by
  intro q x hx hl hc e o hn hb
  have h := next_le hn x hx hl
  have h1 : (rank x.1 x.2).2.1 = 0 := by simp [rank, hc]
  have h2 : (rank e o).2.1 = 1 := by simp [rank, hb]
  have h3 : (rank e o).1 = if e.lander.isNone then 0 else 1 := rfl
  have h4 : (rank x.1 x.2).1 = if x.1.lander.isNone then 0 else 1 := rfl
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  cases he : e.lander <;> cases hxl : x.1.lander <;> simp [he, hxl] at h3 h4 ⊢ <;> omega

theorem pushed_id (r v : Sha) (o : Obs) : (pushed r o).id? v = o.id? v := rfl

theorem pushKeepsCover : PushKeepsCover := by
  intro o v r hc hk
  simp only [Obs.carries, Obs.keeps, Bool.and_eq_true, beq_iff_eq] at hc hk
  obtain ⟨⟨hw, hs⟩, he⟩ := hc
  simp only [Obs.carries, Bool.and_eq_true, beq_iff_eq, pushed_id]
  refine ⟨⟨?_, hs⟩, ?_⟩
  · show walk v r (⟨true, o.head, r⟩ :: o.pushes) = true
    simp [walk, hw]
  · show o.id? v = o.id? r
    rw [he, hk.2]

theorem pushed_carries_iff {o : Obs} {r v : Sha} (hk : o.keeps r = true) (hv : v ≠ r) :
    (pushed r o).carries v = o.carries v := by
  simp only [Obs.keeps, Bool.and_eq_true, beq_iff_eq] at hk
  have hne : (r == v) = false := by simpa using fun h : r = v => hv h.symm
  have e2 : walk v (pushed r o).head (pushed r o).pushes = walk v o.head o.pushes := by
    show walk v r (⟨true, o.head, r⟩ :: o.pushes) = _
    simp [walk, hne]
  simp only [Obs.carries, pushed_id, e2]
  show (walk v o.head o.pushes && (o.id? v).isSome && o.id? v == o.id? r) = _
  rw [hk.2]

theorem pushed_entries (r : Sha) (o : Obs) : (pushed r o).entries = o.entries := rfl

theorem covered_congr {o o' : Obs} (hv : o'.verdicts = o.verdicts) (ha : o'.author = o.author)
    (hp : o'.critical = o.critical)
    (hc : ∀ v ∈ o.verdicts, o'.carries v.head = o.carries v.head) : o'.Covered ↔ o.Covered := by
  have hs : ∀ v ∈ o.verdicts, (o'.stands v ↔ o.stands v) := by
    intro v hvm
    simp only [Obs.stands, hv, hc v hvm]
    constructor
    · rintro ⟨h1, h2⟩
      exact ⟨h1, fun w hw hcw => h2 w hw (by rw [hc w hw]; exact hcw)⟩
    · rintro ⟨h1, h2⟩
      exact ⟨h1, fun w hw hcw => h2 w hw (by rw [← hc w hw]; exact hcw)⟩
  unfold Obs.Covered
  rw [ha, hv, hp]
  cases o.author with
  | none => exact Iff.rfl
  | some a =>
    constructor
    · rintro ⟨h1, h2⟩
      refine ⟨fun v hm h => h1 v hm ((hs v hm).2 h), ?_⟩
      rcases h2 with ⟨v, hm, h, hr⟩ | ⟨⟨v, hm, h, hr⟩, h3⟩
      · exact Or.inl ⟨v, hm, (hs v hm).1 h, hr⟩
      · refine Or.inr ⟨⟨v, hm, (hs v hm).1 h, hr⟩, fun hcr => ?_⟩
        obtain ⟨w, hwm, hw, hwr⟩ := h3 hcr
        exact ⟨w, hwm, (hs w hwm).1 hw, hwr⟩
    · rintro ⟨h1, h2⟩
      refine ⟨fun v hm h => h1 v hm ((hs v hm).1 h), ?_⟩
      rcases h2 with ⟨v, hm, h, hr⟩ | ⟨⟨v, hm, h, hr⟩, h3⟩
      · exact Or.inl ⟨v, hm, (hs v hm).2 h, hr⟩
      · refine Or.inr ⟨⟨v, hm, (hs v hm).2 h, hr⟩, fun hcr => ?_⟩
        obtain ⟨w, hwm, hw, hwr⟩ := h3 hcr
        exact ⟨w, hwm, (hs w hwm).2 hw, hwr⟩

theorem pushIsNotRepeated : PushIsNotRepeated := by
  intro e o r hl hb hfresh
  refine ⟨?_, rfl⟩
  have hk : o.keeps r = true := by
    have h2 := hl
    simp only [landable, Bool.and_eq_true, Option.isNone_iff_eq_none, Obs.stuck?, hb] at h2
    have h3 := h2.2
    split at h3
    · cases h3
    · split at h3
      · next hk => exact hk
      · cases h3
  simp only [landable, Bool.and_eq_true, Entry.valid, Obs.eligible, Option.isNone_iff_eq_none]
    at hl ⊢
  obtain ⟨⟨⟨hin, ⟨⟨⟨⟨hu, hen⟩, hcov⟩, hrev⟩, hrest⟩⟩, habout⟩, _⟩ := hl
  have hcar : ∀ v ∈ o.verdicts, (pushed r o).carries v.head = o.carries v.head :=
    fun v hv => pushed_carries_iff hk (hfresh v hv)
  refine ⟨⟨⟨by rw [pushed_entries]; exact hin, ⟨⟨⟨⟨hu, hen⟩, ?_⟩, ?_⟩, hrest⟩⟩, ?_⟩, ?_⟩
  · exact decide_eq_true
      ((covered_congr (o := o) (o' := pushed r o) rfl rfl rfl hcar).2 (of_decide_eq_true hcov))
  · simp only [Obs.reviewed] at hrev ⊢
    show o.botAt.any (pushed r o).carries = true
    cases hbot : o.botAt with
    | none => rw [hbot] at hrev; cases hrev
    | some b =>
      rw [hbot] at hrev
      simp only [Option.any_some] at hrev ⊢
      exact pushKeepsCover o b r hrev hk
  · exact pushKeepsCover o _ r habout hk
  · simp [Obs.stuck?, pushed]

theorem step_cases (me : Teammate) (q : Queue) (o : Obs) :
    (∃ c, newestOwner o.words = some (.ownerHold c) ∧ step me q o = .stop .held) ∨
    ((∀ c, newestOwner o.words ≠ some (.ownerHold c)) ∧
      ((o.enforced = false ∧ step me q o = .stop .unenforced) ∨
       (o.enforced = true ∧ o.eligible = false ∧ step me q o = .stop .notEligible) ∨
       (o.enforced = true ∧ o.eligible = true ∧ ∃ why, step me q o = .stop (.stuck why)) ∨
       (o.enforced = true ∧ o.eligible = true ∧ o.stuck? = none ∧
         q.any (fun x => x.2.pr == o.pr && x.1.valid o) = false ∧
         (step me q o = .enter o.head ∨ step me q o = .stop .noEntry)) ∨
       (o.enforced = true ∧ o.eligible = true ∧ o.stuck? = none ∧
         q.any (fun x => x.2.pr == o.pr && x.1.valid o) = true ∧
         (step me q o = .stop .notEligible ∨
          (∃ n g, next q = some (n, g) ∧ n.pr ≠ o.pr ∧ step me q o = .wait n.pr) ∨
          (∃ n g, next q = some (n, g) ∧ n.pr = o.pr ∧
            ((o.base = .current ∧ o.gate = .success ∧ o.mayMerge me = true ∧
                step me q o = .merge o.head) ∨
             (o.base = .current ∧ o.gate = .success ∧ o.mayMerge me = false ∧
                step me q o = .present o.head) ∨
             step me q o = .awaitGate o.head ∨ step me q o = .awaitPush o.head)))))) := by
  unfold step
  split
  · next c hc => exact Or.inl ⟨c, hc, rfl⟩
  · next hno =>
    refine Or.inr ⟨fun c hc => hno c hc, ?_⟩
    by_cases hen : o.enforced = true
    · by_cases hel : o.eligible = true
      · cases hst : o.stuck? with
        | some why => simp [hen, hel]
        | none =>
          by_cases hany : q.any (fun x => x.2.pr == o.pr && x.1.valid o) = true
          · right; right; right; right
            refine ⟨hen, hel, rfl, hany, ?_⟩
            simp only [hen, hel, hany]
            cases hn : next q with
            | none => simp
            | some y =>
              obtain ⟨n, g⟩ := y
              by_cases hpr : n.pr = o.pr
              · right; right
                refine ⟨n, g, rfl, hpr, ?_⟩
                cases hb : o.base <;> cases hg : o.gate <;>
                  by_cases hm : o.mayMerge me = true <;> simp [hpr, hm]
              · right; left
                exact ⟨n, g, rfl, hpr, by simp [hpr]⟩
          · right; right; right; left
            have hany' : q.any (fun x => x.2.pr == o.pr && x.1.valid o) = false := by
              simpa using hany
            refine ⟨hen, hel, rfl, hany', ?_⟩
            simp only [hen, hel, hany']
            by_cases hm : o.mayMerge me = true <;> simp [hm]
      · have hel' : o.eligible = false := by simpa using hel
        right; left
        exact ⟨hen, hel', by simp [hen, hel']⟩
    · have hen' : o.enforced = false := by simpa using hen
      left
      exact ⟨hen', by simp [hen']⟩

theorem mergeIsGated : MergeIsGated := by
  intro me q o h hs
  rcases step_cases me q o with ⟨c, _, h1⟩ | ⟨_, h1⟩
  · rw [h1] at hs; cases hs
  · rcases h1 with ⟨_, h1⟩ | ⟨_, _, h1⟩ | ⟨_, _, why, h1⟩ | ⟨_, _, _, _, h1⟩ | ⟨hen, hel, _, _, h1⟩
    · rw [h1] at hs; cases hs
    · rw [h1] at hs; cases hs
    · rw [h1] at hs; cases hs
    · rcases h1 with h1 | h1 <;> rw [h1] at hs <;> cases hs
    · rcases h1 with h1 | ⟨n, g, _, _, h1⟩ | ⟨n, g, _, _, h1⟩
      · rw [h1] at hs; cases hs
      · rw [h1] at hs; cases hs
      · rcases h1 with ⟨hb, hg, hm, h1⟩ | ⟨_, _, _, h1⟩ | h1 | h1
        · rw [h1] at hs; cases hs
          simp only [Obs.mayMerge, Bool.and_eq_true, Bool.not_eq_true', List.contains_iff_mem]
            at hm
          simp only [Obs.eligible, Bool.and_eq_true] at hel
          exact ⟨rfl, hb, hg, hen, hm.1, hm.2, of_decide_eq_true hel.1.1.2⟩
        · rw [h1] at hs; cases hs
        · rw [h1] at hs; cases hs
        · rw [h1] at hs; cases hs

theorem unenforcedLandsNothing : UnenforcedLandsNothing := by
  intro o hen
  refine ⟨fun e => by simp [Entry.valid, Obs.eligible, hen], ?_⟩
  intro me q h
  rcases step_cases me q o with ⟨c, _, h1⟩ | ⟨_, h1⟩
  · rw [h1]; exact ⟨(fun x => by cases x), (fun x => by cases x)⟩
  · rcases h1 with ⟨_, h1⟩ | ⟨h2, _⟩ | ⟨h2, _⟩ | ⟨h2, _⟩ | ⟨h2, _⟩
    · rw [h1]; exact ⟨(fun x => by cases x), (fun x => by cases x)⟩
    all_goals (rw [hen] at h2; cases h2)

theorem holdWins : HoldWins := by
  intro o c hc
  refine ⟨fun e => by simp [Entry.valid, Obs.entries, hc], ?_⟩
  intro me q
  simp [step, hc]

theorem agentKeepsOwnerWord : AgentKeepsOwnerWord := by
  intro ws
  induction ws with
  | nil => rfl
  | cons w ws ih =>
    by_cases hw : w.byOwner = true
    · simp only [List.filter, hw, newestOwner, ← ih]
    · have hw' : w.byOwner = false := by simpa using hw
      simp only [List.filter, hw', newestOwner, ← ih]
      cases newestOwner ws <;> simp

theorem onlyMergersQueue : OnlyMergersQueue := by
  intro o e t he hl
  have hag : ∀ e' ∈ o.words.filterMap (fun
      | .agentLand t m => if o.mayMerge t then some (⟨o.pr, m, some t⟩ : Entry) else none
      | _ => none), ∀ t', e'.lander = some t' → o.kept = false ∧ t' ∈ o.delegates := by
    intro e' he' t' hl'
    simp only [List.mem_filterMap] at he'
    obtain ⟨w, _, hw⟩ := he'
    cases w with
    | agentLand t'' m =>
      simp only at hw
      split at hw
      · next hm =>
        cases hw
        simp only at hl'
        cases hl'
        simpa [Obs.mayMerge] using hm
      · cases hw
    | ownerLand m => cases hw
    | ownerHold c => cases hw
  simp only [Obs.entries] at he
  split at he
  · cases he
  · rcases List.mem_cons.1 he with rfl | he
    · cases hl
    · exact hag e he t hl
  · exact hag e he t hl

theorem nextNeverWaits : NextNeverWaits := by
  intro me q o e g ahead hn hpr hs
  rcases step_cases me q o with ⟨c, _, h1⟩ | ⟨_, h1⟩
  · rw [h1] at hs; cases hs
  · rcases h1 with ⟨_, h1⟩ | ⟨_, _, h1⟩ | ⟨_, _, why, h1⟩ | ⟨_, _, _, _, h1⟩ | ⟨_, _, _, _, h1⟩
    · rw [h1] at hs; cases hs
    · rw [h1] at hs; cases hs
    · rw [h1] at hs; cases hs
    · rcases h1 with h1 | h1 <;> rw [h1] at hs <;> cases hs
    · rcases h1 with h1 | ⟨n, g', hn', hne, _⟩ | ⟨n, g', _, _, h1⟩
      · rw [h1] at hs; cases hs
      · rw [hn] at hn'; cases hn'; exact hne hpr
      · rcases h1 with ⟨_, _, _, h1⟩ | ⟨_, _, _, h1⟩ | h1 | h1 <;> rw [h1] at hs <;> cases hs

def pick (x : Entry × Obs) : Option (Entry × Obs) → Option (Entry × Obs)
  | none => if landable x then some x else none
  | some y => if landable x && before (rank x.1 x.2) (rank y.1 y.2) then some x else some y

theorem next_cons (x : Entry × Obs) (l : Queue) : next (x :: l) = pick x (next l) := by
  simp only [next, pick]

theorem said_ne {x y : Entry × Obs} (h : x.1.mark.said ≠ y.1.mark.said) :
    (rank x.1 x.2).2.2 ≠ (rank y.1 y.2).2.2 := h

theorem before_asymm {r s : Nat × Nat × Nat} (h : r.2.2 ≠ s.2.2) :
    before s r = true ↔ ¬before r s = true := by
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
  omega

def best (x y : Entry × Obs) : Entry × Obs :=
  if before (rank x.1 x.2) (rank y.1 y.2) then x else y

theorem pick_some (x y : Entry × Obs) :
    pick x (some y) = some (if landable x then best x y else y) := by
  simp only [pick, best]
  by_cases l : landable x = true <;>
    by_cases h : before (rank x.1 x.2) (rank y.1 y.2) = true <;> simp [l, h]

theorem best_comm {x y : Entry × Obs} (h : x.1.mark.said ≠ y.1.mark.said) :
    best x y = best y x := by
  have hb := before_asymm (said_ne h)
  simp only [best]
  by_cases h1 : before (rank x.1 x.2) (rank y.1 y.2) = true
  · have h2 : ¬before (rank y.1 y.2) (rank x.1 x.2) = true := fun hh => hb.1 hh h1
    simp [h1, h2]
  · have h2 : before (rank y.1 y.2) (rank x.1 x.2) = true := hb.2 h1
    simp [h1, h2]

theorem best_assoc {x y z : Entry × Obs} (hxy : x.1.mark.said ≠ y.1.mark.said)
    (hyz : y.1.mark.said ≠ z.1.mark.said) (hxz : x.1.mark.said ≠ z.1.mark.said) :
    best x (best y z) = best y (best x z) := by
  have nxy := said_ne hxy
  have nyz := said_ne hyz
  have nxz := said_ne hxz
  have a1 := before_asymm nxy
  simp only [best]
  by_cases h1 : before (rank x.1 x.2) (rank y.1 y.2) = true <;>
    by_cases h2 : before (rank y.1 y.2) (rank z.1 z.2) = true <;>
    by_cases h3 : before (rank x.1 x.2) (rank z.1 z.2) = true <;>
    first
      | (simp [h1, h2, h3, a1]; done)
      | (exfalso
         simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq]
           at h1 h2 h3
         omega)

theorem pick_swap {a b : Entry × Obs} {o : Option (Entry × Obs)}
    (hab : a.1.mark.said ≠ b.1.mark.said)
    (ho : ∀ y, o = some y → a.1.mark.said ≠ y.1.mark.said ∧ b.1.mark.said ≠ y.1.mark.said) :
    pick a (pick b o) = pick b (pick a o) := by
  cases o with
  | none =>
    by_cases la : landable a = true <;> by_cases lb : landable b = true
    · have h1 : pick b none = some b := by simp [pick, lb]
      have h2 : pick a none = some a := by simp [pick, la]
      rw [h1, h2, pick_some, pick_some]
      simp only [la, lb, ite_true]
      exact congrArg some (best_comm hab)
    · simp [pick, la, lb]
    · simp [pick, la, lb]
    · simp [pick, la, lb]
  | some y =>
    obtain ⟨nay, nby⟩ := ho y rfl
    rw [pick_some, pick_some, pick_some, pick_some]
    by_cases la : landable a = true <;> by_cases lb : landable b = true <;>
      simp only [la, lb, ite_true]
    · exact congrArg some (best_assoc hab nby nay)
    all_goals simp

theorem nextIgnoresListingOrder : NextIgnoresListingOrder := by
  intro q q' hp
  induction hp with
  | nil => intro _; rfl
  | cons x _ ih =>
    intro hn
    rw [next_cons, next_cons, ih (List.nodup_cons.1 hn).2]
  | swap x y l =>
    intro hn
    rw [next_cons, next_cons, next_cons, next_cons]
    simp only [List.map_cons, List.nodup_cons, List.mem_cons, List.mem_map, not_or] at hn
    obtain ⟨⟨hyx, hyl⟩, hxl, _⟩ := hn
    apply pick_swap
    · exact hyx
    · intro z hz
      have hm := next_mem hz
      exact ⟨fun h => hyl ⟨z, hm, h.symm⟩, fun h => hxl ⟨z, hm, h.symm⟩⟩
  | trans h1 _ ih1 ih2 =>
    intro hn
    rw [ih1 hn]
    exact ih2 ((h1.map _).nodup_iff.1 hn)

theorem quietAfterRebase : QuietAfterRebase := by
  intro inLine covered p g hc hg
  have hg' : (g == Gate.failure) = false := by simpa using hg
  refine ⟨rfl, rfl, by simp [wake, hc], ?_, ?_⟩
  · cases hi : inLine p <;> simp [wake, hg', hi, hc]
  · intro hi; simp [wake, hg', hi, hc]

theorem mem_queueOf {os : List Obs} {x : Entry × Obs} :
    x ∈ queueOf os ↔ ∃ o ∈ os, x.2 = o ∧ x.1 ∈ o.entries := by
  obtain ⟨e, o'⟩ := x
  simp only [queueOf, List.mem_flatMap, List.mem_map, Prod.mk.injEq]
  constructor
  · rintro ⟨a, ha, b, hb, h1, h2⟩
    exact ⟨a, ha, h2.symm, h1 ▸ hb⟩
  · rintro ⟨a, ha, h2, hb⟩
    exact ⟨a, ha, e, hb, rfl, h2.symm⟩

namespace Fixture

def orch : Teammate := ⟨"claude", "orchestrator"⟩
def worker : Teammate := ⟨"grok", "worker"⟩
def ver : Teammate := ⟨"claude", "verifier"⟩
def opus : Teammate := ⟨"claude", "verifier-opus"⟩
def auth : Teammate := ⟨"grok", "builder"⟩
def m153 : Mark := ⟨900, "aaa"⟩
def m149 : Mark := ⟨800, "bbb"⟩
def m159 : Mark := ⟨700, "ccc"⟩

def o153 : Obs :=
  { pr := 153, updatable := true, enforced := true, head := "aaa", pushes := [],
    ids := [("aaa", "id-a"), ("ar", "id-a")], paths := some [".github/workflows/ci.yml"],
    base := .clean "ar", gate := .success, author := some ⟨auth, "grok"⟩,
    verdicts := [⟨850, "aaa", opus, "opus", .pass⟩, ⟨851, "aaa", ver, "sonnet", .pass⟩],
    botAt := some "aaa", delegates := [orch], words := [.ownerLand m153], rest := true }
def o149 : Obs :=
  { o153 with pr := 149, head := "bbb", ids := [("bbb", "id-b"), ("br", "id-b")],
              paths := some ["core/Mitos/Chain.lean"], base := .clean "br",
              verdicts := [⟨750, "bbb", ver, "sonnet", .pass⟩], botAt := some "bbb",
              words := [.agentLand orch m149] }
def o159 : Obs :=
  { o149 with pr := 159, head := "cc2", pushes := [⟨true, "ccc", "cc2"⟩],
              ids := [("ccc", "id-c"), ("cc2", "id-c")], base := .current, gate := .pending,
              verdicts := [⟨650, "ccc", ver, "sonnet", .pass⟩], botAt := some "ccc",
              words := [.agentLand orch m159] }
def p153 : Obs := { pushed "ar" o153 with gate := .success }
def b149 : Obs := { o149 with base := .current }

example : (queueOf [{ o149 with words := [] }]).isEmpty = true := by decide +kernel
example : plan (queueOf [{ o149 with words := [] }]) = .idle := by decide +kernel
example : step orch [] { o149 with words := [] } = .enter "bbb" := by decide +kernel
example : step orch [] { o153 with words := [] } = .stop .noEntry := by decide +kernel
example : ({ o153 with words := [.agentLand orch ⟨910, "aaa"⟩] } : Obs).entries = [] := by
  decide +kernel
example : plan (queueOf [o153, o149, o159]) = .push 153 "aaa" "ar" := by decide +kernel
example : step orch (queueOf [o153, o149, o159]) o159 = .wait 153 := by decide +kernel
example : plan (queueOf [o149, o159]) = .idle := by decide +kernel
example : step orch (queueOf [o149, o159]) o149 = .wait 159 := by decide +kernel
example : step orch (queueOf [o149, o159]) o159 = .awaitGate "cc2" := by decide +kernel
example : plan (queueOf [{ pushed "ar" o153 with gate := .success }, o149]) = .idle := by
  decide +kernel
example : step orch (queueOf [pushed "ar" o153, o149]) (pushed "ar" o153) = .awaitGate "ar" := by
  decide +kernel
example : step orch (queueOf [p153, o149]) p153 = .present "ar" := by decide +kernel
example : step orch (queueOf [p153, o149]) o149 = .wait 153 := by decide +kernel
example : (⟨153, ⟨950, "ar"⟩, none⟩ : Entry).valid
    { p153 with words := [.ownerLand m153, .ownerLand ⟨950, "ar"⟩] } = true := by decide +kernel
example : (⟨153, ⟨950, "zzz"⟩, none⟩ : Entry).valid
    { p153 with words := [.ownerLand m153, .ownerLand ⟨950, "zzz"⟩] } = false := by decide +kernel
example : step orch (queueOf [b149]) b149 = .merge "bbb" := by decide +kernel
example : step worker (queueOf [b149]) b149 = .present "bbb" := by decide +kernel
def held : Obs := { o153 with words := [.ownerLand m153, .ownerHold 950] }
example : step orch (queueOf [held, o149]) held = .stop .held := by decide +kernel
example : plan (queueOf [held, o149]) = .push 149 "bbb" "br" := by decide +kernel
def r149 : Obs := { pushed "br" o149 with gate := .failure }
example : step orch (queueOf [r149]) r149 = .stop (.stuck .red) := by decide +kernel
example : plan (queueOf [r149, o159]) = .idle := by decide +kernel
example : step orch (queueOf [{ r149 with gate := .success }]) { r149 with gate := .success } =
    .merge "br" := by decide +kernel
example : step orch (queueOf [{ o153 with base := .clean "xx" }, o149])
    { o153 with base := .clean "xx" } = .stop (.stuck .contentChanged) := by decide +kernel
example : plan (queueOf [{ o153 with base := .clean "xx" }, o149]) = .push 149 "bbb" "br" := by
  decide +kernel
example : step orch (queueOf [{ o153 with base := .conflict }]) { o153 with base := .conflict } =
    .stop (.stuck .conflict) := by decide +kernel
example : plan (queueOf [{ o153 with base := .conflict }]) = .idle := by decide +kernel
example : plan (queueOf [{ o153 with base := .unread }, o149]) = .push 149 "bbb" "br" := by
  decide +kernel
def f153 : Obs :=
  { o153 with head := "fff", pushes := [⟨false, "aaa", "fff"⟩],
              ids := [("aaa", "id-a"), ("fff", "id-f")] }
example : plan (queueOf [f153, o149]) = .push 149 "bbb" "br" := by decide +kernel
example : plan (queueOf [{ o153 with enforced := false }, { o149 with enforced := false }]) = .idle := by
  decide +kernel
example : step orch [] { o149 with enforced := false } = .stop .unenforced := by decide +kernel
example : plan (queueOf [{ o149 with verdicts := [] }]) = .idle := by decide +kernel
example : step orch (queueOf [{ o149 with verdicts := [] }]) { o149 with verdicts := [] } =
    .stop .notEligible := by decide +kernel
example : ({ o149 with words := [.agentLand orch m149, .agentLand worker ⟨810, "bbb"⟩] } : Obs).entries
    = [⟨149, m149, some orch⟩] := by decide +kernel
example : ({ o149 with paths := none } : Obs).kept = true := by decide +kernel
example : [keptPath "plan/phase-2.md", keptPath "examples/acme/models.lock",
    keptPath "core/Mitos/Chain.lean", keptPath "lakefile.toml",
    keptPath "eval/score/lakefile.toml"] = [true, true, false, true, false] := by decide +kernel
example : [criticalPath "plan/phase-2.md", criticalPath ".claude/skills/x.md",
    criticalPath "gate/Main.lean"] = [false, false, true] := by decide +kernel

def sonnetV : Teammate := ⟨"claude", "verifier-sonnet"⟩
def opusJ : Teammate := ⟨"claude", "reviewer-opus"⟩
def root : Teammate := ⟨"claude", "root"⟩
def holder : Teammate := ⟨"claude", "worker-opus"⟩

def w0 : Obs :=
  { pr := 201, updatable := true, enforced := true, head := "h", pushes := [],
    ids := [("h", "id-h"), ("g", "id-g")], paths := some ["core/Mitos/Chain.lean"],
    base := .current, gate := .success, author := some ⟨holder, "opus"⟩,
    verdicts := [⟨10, "h", sonnetV, "sonnet", .pass⟩], botAt := some "h",
    delegates := [orch], words := [.agentLand orch ⟨30, "h"⟩], rest := true }
def crit (o : Obs) : Obs := { o with paths := some ["gate/Main.lean"] }
def behind (o : Obs) : Obs := { o with base := .clean "h2", ids := [("h", "id-h"), ("h2", "id-h")] }

example : w0.covered = true := by decide +kernel
example : step orch (queueOf [w0]) w0 = .merge "h" := by decide +kernel
example : plan (queueOf [behind w0]) = .push 201 "h" "h2" := by decide +kernel
example : ({ w0 with verdicts := [⟨10, "g", sonnetV, "sonnet", .pass⟩] } : Obs).covered = false := by
  decide +kernel
example : o159.covered = true := by decide +kernel
example : ({ w0 with verdicts := [⟨10, "h", holder, "sonnet", .pass⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ w0 with verdicts := [⟨10, "h", opusJ, "opus", .pass⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ o149 with verdicts := [⟨750, "bbb", auth, "sonnet", .pass⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ o149 with verdicts := [⟨750, "bbb", ver, "grok", .pass⟩] } : Obs).covered = false := by
  decide +kernel
def a1 : Obs := { w0 with verdicts :=
  [⟨10, "h", sonnetV, "sonnet", .pass⟩, ⟨20, "h", opusJ, "opus", .fail⟩] }
example : a1.covered = false := by decide +kernel
example : step orch (queueOf [a1]) a1 = .stop .notEligible := by decide +kernel
example : plan (queueOf [behind a1]) = .idle := by decide +kernel
example : ({ w0 with verdicts :=
    [⟨10, "h", sonnetV, "sonnet", .pass⟩, ⟨20, "h", opusJ, "opus", .hold⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ w0 with verdicts :=
    [⟨5, "h", opusJ, "opus", .fail⟩, ⟨10, "h", sonnetV, "sonnet", .pass⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ w0 with verdicts := w0.verdicts ++ [⟨20, "h", holder, "opus", .hold⟩] } : Obs).covered =
    false := by decide +kernel
example : ({ a1 with verdicts := a1.verdicts ++ [⟨25, "h", opusJ, "opus", .pass⟩] } : Obs).covered =
    true := by decide +kernel
example : ({ a1 with verdicts := a1.verdicts ++ [⟨25, "h", sonnetV, "sonnet", .pass⟩] } : Obs).covered =
    false := by decide +kernel
example : ({ w0 with verdicts := w0.verdicts ++ [⟨20, "g", opusJ, "opus", .fail⟩] } : Obs).covered =
    true := by decide +kernel
def b1 : Obs := crit { w0 with verdicts :=
  [⟨10, "h", sonnetV, "sonnet", .pass⟩, ⟨11, "h", opus, "opus", .pass⟩] }
example : b1.covered = true := by decide +kernel
example : (crit w0).covered = false := by decide +kernel
example : (crit { w0 with verdicts := [⟨11, "h", opus, "opus", .pass⟩] }).covered = false := by
  decide +kernel
def s1 : Obs := crit { w0 with author := some ⟨holder, "sonnet"⟩,
                               verdicts := [⟨11, "h", opus, "opus", .pass⟩] }
example : s1.covered = true := by decide +kernel
example : ({ w0 with verdicts := w0.verdicts ++ [⟨11, "h", opus, "opus", .fail⟩] } : Obs).covered =
    false := by decide +kernel
example : step orch (queueOf [{ b1 with words := [.ownerLand ⟨30, "h"⟩] }])
    { b1 with words := [.ownerLand ⟨30, "h"⟩] } = .present "h" := by decide +kernel
def c1 : Obs := { w0 with verdicts := [⟨10, "h", root, "opus", .wordingOnly⟩] }
example : c1.covered = true := by decide +kernel
example : step orch (queueOf [c1]) c1 = .merge "h" := by decide +kernel
example : (crit c1).covered = true := by decide +kernel
def c2 : Obs := { c1 with verdicts :=
  [⟨5, "h", sonnetV, "sonnet", .fail⟩, ⟨10, "h", root, "opus", .wordingOnly⟩] }
example : c2.covered = false := by decide +kernel
example : ({ c1 with verdicts := c1.verdicts ++ [⟨20, "h", sonnetV, "sonnet", .hold⟩] } : Obs).covered =
    false := by decide +kernel
example : ({ c1 with verdicts :=
    [⟨5, "h", sonnetV, "sonnet", .fail⟩, ⟨8, "h", sonnetV, "sonnet", .pass⟩,
     ⟨10, "h", root, "opus", .wordingOnly⟩] } : Obs).covered = true := by decide +kernel
example : ({ c1 with verdicts := [⟨10, "h", holder, "opus", .wordingOnly⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ c1 with verdicts := [⟨10, "g", root, "opus", .wordingOnly⟩] } : Obs).covered = false := by
  decide +kernel
example : ({ c1 with verdicts := c1.verdicts ++ [⟨20, "h", root, "opus", .pass⟩] } : Obs).covered =
    false := by decide +kernel
def d0 : Obs := { b1 with paths := w0.paths, words := [.ownerLand ⟨30, "h"⟩] }
def d1 : Obs := { d0 with author := none }
example : d0.covered = true := by decide +kernel
example : d1.covered = false := by decide +kernel
example : ({ c1 with author := none } : Obs).covered = false := by decide +kernel
example : step orch (queueOf [d1]) d1 = .stop .notEligible := by decide +kernel
example : plan (queueOf [behind d0]) = .push 201 "h" "h2" := by decide +kernel
example : plan (queueOf [behind d1]) = .idle := by decide +kernel

example : wake (fun _ => false) (fun _ => true) (.conflictFound 126) = .holder 126 := by decide +kernel
example : wake (fun _ => false) (fun _ => false) (.conflictFound 126) = .nobody := by decide +kernel
example : wake (fun _ => false) (fun _ => true) (.landWord 126) = .orchestrator := by decide +kernel
example : wake (fun p => p == 149) (fun _ => true) (.gateDone 149 .success) = .lander 149 := by
  decide +kernel
example : wake (fun p => p == 149) (fun _ => true) (.gateDone 153 .success) = .nobody := by
  decide +kernel
example : wake (fun p => p == 149) (fun _ => true) (.gateDone 149 .failure) = .holder 149 := by
  decide +kernel
example : wake (fun p => p == 149) (fun _ => true) (.updaterPushed 149) = .nobody := by decide +kernel
example : wake (fun _ => false) (fun _ => true) .mainMoved = .nobody := by decide +kernel

end Fixture

/-! ## No `sorry`, standard axioms only

`lake build` accepts a `sorry` with a warning, so the build checks it: it fails if a statement's
proof depends on an axiom other than the three standard ones, and `sorryAx` is one. -/

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  for n in [``pushOnlyNext, ``noEntryNoPush, ``oneLandingAtATime, ``pushKeepsCover,
      ``pushIsNotRepeated, ``mergeIsGated, ``unenforcedLandsNothing, ``holdWins,
      ``agentKeepsOwnerWord, ``onlyMergersQueue, ``stuckDoesNotBlock, ``nextNeverWaits,
      ``nextIgnoresListingOrder, ``quietAfterRebase, ``mem_queueOf] do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Land
