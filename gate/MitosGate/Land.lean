import Lean.CoreM
import Lean.Util.CollectAxioms
import MitosGate.Carry

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
  approves : Bool
  deriving DecidableEq

inductive Word
  | ownerLand (m : Mark)
  | ownerHold (said : Nat)
  | ownerSpoke (said : Nat)
  | agentLand (who : Teammate) (m : Mark)
  deriving DecidableEq

def Word.said : Word → Nat
  | .ownerLand m => m.said
  | .ownerHold s => s
  | .ownerSpoke s => s
  | .agentLand _ m => m.said

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

def Push.toCarry (p : Push) : Carry.Push :=
  if p.byUpdater then ⟨"", "force_push", Carry.updater, p.before, p.after⟩
  else ⟨"", "push", "", p.before, p.after⟩

def Obs.id? (o : Obs) (s : Sha) : Option String := (o.ids.find? (·.1 == s)).map (·.2)

def Obs.carries (o : Obs) (v : Sha) : Bool :=
  Carry.walk v o.head (o.pushes.map Push.toCarry) && (o.id? v).isSome && o.id? v == o.id? o.head

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

def Obs.eligibleBeforeRebase (o : Obs) : Bool :=
  o.updatable && o.enforced && o.covered && o.reviewed && o.rest

def Obs.mayMerge (o : Obs) (t : Teammate) : Bool := !o.kept && o.delegates.contains t

def Word.byOwner : Word → Bool
  | .agentLand _ _ => false
  | _ => true

def Word.decides : Word → Bool
  | .ownerLand _ | .ownerHold _ => true
  | _ => false

def newestOwner : List Word → Option Word
  | [] => none
  | w :: ws =>
    match newestOwner ws with
    | some x => if w.decides && x.said < w.said then some w else some x
    | none => if w.decides then some w else none

def spokeSince (ws : List Word) (n : Nat) : Bool :=
  ws.any fun
    | .ownerSpoke s => decide (n < s)
    | _ => false

inductive Lander
  | owner
  | agent (t : Teammate)
  deriving DecidableEq

def Lander.isOwner : Lander → Bool
  | .owner => true
  | .agent _ => false

structure Entry where
  pr : Pr
  mark : Mark
  lander : Lander
  deriving DecidableEq

def Obs.entries (o : Obs) : List Entry :=
  let agents := o.words.filterMap fun
    | .agentLand t m => if o.mayMerge t then some ⟨o.pr, m, .agent t⟩ else none
    | _ => none
  match newestOwner o.words with
  | some (.ownerHold _) => []
  | some (.ownerLand m) =>
    if (!o.kept || m.approves) && !spokeSince o.words m.said then ⟨o.pr, m, .owner⟩ :: agents
    else agents
  | _ => agents

inductive OwnerWord
  | none | held | unnamed | spoke | stale | stands
  deriving DecidableEq

def Obs.word (o : Obs) : OwnerWord :=
  match newestOwner o.words with
  | some (.ownerHold _) => .held
  | some (.ownerLand m) =>
    if o.kept && !m.approves then .unnamed
    else if spokeSince o.words m.said then .spoke
    else if !o.carries m.about then .stale
    else .stands
  | _ => .none

def Entry.valid (e : Entry) (o : Obs) : Bool :=
  o.entries.contains e && o.eligibleBeforeRebase && o.carries e.mark.about

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
  (if e.lander.isOwner then 0 else 1, if o.base == .current then 0 else 1, e.mark.said)

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
  | merge (pr : Pr) (head : Sha)
  deriving DecidableEq

def plan (q : Queue) : Plan :=
  match next q with
  | some (e, o) =>
    match o.base with
    | .clean r => .push o.pr o.head r
    | .current => if e.lander.isOwner && o.gate == .success then .merge o.pr o.head else .idle
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
    else if !o.eligibleBeforeRebase then .stop .notEligible
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

def wake (agentInLine ownerInLine covered : Pr → Bool) : Event → Wake
  | .mainMoved | .updaterPushed _ => .nobody
  | .gateDone p g =>
    if g == .failure then .holder p
    else if agentInLine p then .lander p
    -- on the owner's word alone the workflow posts the merge command for a green gate; any other
    -- result goes to the orchestrator, because no timer would start or re-run the gate
    else if ownerInLine p then (if g == .success then .nobody else .orchestrator)
    else if covered p then .nobody
    else .holder p
  | .botReviewed p => if covered p then .nobody else .holder p
  | .conflictFound p => if covered p then .holder p else .nobody
  | .landWord p => if agentInLine p || ownerInLine p then .nobody else .orchestrator
  | .ownerSpoke _ => .orchestrator

def wakeOf (os : List Obs) (e : Event) : Wake :=
  let inLine (byOwner : Bool) (p : Pr) := (queueOf os).any fun x =>
    x.2.pr == p && landable x && x.1.lander.isOwner == byOwner
  wake (inLine false) (inLine true) (fun p => os.any fun o => o.pr == p && o.covered) e

def PushOnlyNext : Prop :=
  ∀ q p s r, plan q = .push p s r →
    ∃ e o, next q = some (e, o) ∧ landable (e, o) = true ∧ o.pr = p ∧ s = o.head ∧
      o.base = .clean r ∧ o.keeps r = true

def NoEntryNoPush : Prop :=
  ∀ q p, (∀ x ∈ q, x.2.pr = p → x.1.valid x.2 = false) → ∀ s r, plan q ≠ .push p s r

def OneLandingAtATime : Prop :=
  ∀ q x, x ∈ q → landable x = true → x.2.base = .current →
    ∀ e o, next q = some (e, o) → o.base ≠ .current →
      e.lander = .owner ∧ x.1.lander ≠ .owner

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

def PlannedMergeIsGated : Prop :=
  ∀ q p h, plan q = .merge p h →
    ∃ e o, next q = some (e, o) ∧ o.pr = p ∧ h = o.head ∧ o.base = .current ∧ o.gate = .success ∧
      o.enforced = true ∧ o.updatable = true ∧ o.Covered ∧ o.reviewed = true ∧ o.rest = true ∧
      e.lander = .owner ∧ newestOwner o.words = some (.ownerLand e.mark) ∧
      (∀ s, Word.ownerSpoke s ∈ o.words → s ≤ e.mark.said) ∧
      o.carries e.mark.about = true ∧ (o.kept = true → e.mark.approves = true)

def OwnerEntryIsTheirLastWord : Prop :=
  ∀ (o : Obs) (e : Entry), e ∈ o.entries → e.lander = .owner →
    e.pr = o.pr ∧ newestOwner o.words = some (.ownerLand e.mark) ∧
      (∀ s, Word.ownerSpoke s ∈ o.words → s ≤ e.mark.said) ∧
      (o.kept = true → e.mark.approves = true)

def KeptEntryIsTheOwners : Prop :=
  ∀ (o : Obs) (e : Entry), e ∈ o.entries → o.kept = true → e.lander = .owner

def OnlyLandOrHoldChangesTheWord : Prop :=
  ∀ ws : List Word, newestOwner ws = newestOwner (ws.filter (·.decides))

def WordStandsIsTheEntry : Prop :=
  ∀ o : Obs, o.word = .stands ↔ ∃ e ∈ o.entries, e.lander = .owner ∧ o.carries e.mark.about = true

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
  ∀ (o : Obs) (e : Entry) (t : Teammate), e ∈ o.entries → e.lander = .agent t →
    o.kept = false ∧ t ∈ o.delegates

def StuckDoesNotBlock : Prop :=
  ∀ q : Queue, (∃ x ∈ q, landable x = true) → ∃ y, next q = some y

def NextNeverWaits : Prop :=
  ∀ me q o e g ahead, next q = some (e, g) → e.pr = o.pr → step me q o ≠ .wait ahead

def NextIgnoresListingOrder : Prop :=
  ∀ q q' : Queue, q.Perm q' → (q.map fun x => x.1.mark.said).Nodup → next q = next q'

def QuietAfterRebase : Prop :=
  ∀ (agentInLine ownerInLine covered : Pr → Bool) (p : Pr) (g : Gate), g ≠ .failure →
    wake agentInLine ownerInLine covered .mainMoved = .nobody ∧
      wake agentInLine ownerInLine covered (.updaterPushed p) = .nobody ∧
      (covered p = true → wake agentInLine ownerInLine covered (.botReviewed p) = .nobody) ∧
      (wake agentInLine ownerInLine covered (.gateDone p g) = .lander p ↔
        agentInLine p = true) ∧
      (agentInLine p = false → ownerInLine p = false →
        (wake agentInLine ownerInLine covered (.gateDone p g) = .nobody ↔ covered p = true)) ∧
      (agentInLine p = false → ownerInLine p = true →
        (wake agentInLine ownerInLine covered (.gateDone p g) = .nobody ↔ g = .success)) ∧
      (agentInLine p = false → ownerInLine p = true → g ≠ .success →
        wake agentInLine ownerInLine covered (.gateDone p g) = .orchestrator)

def UnknownAuthorCoversNothing : Prop :=
  ∀ o : Obs, o.author = none → ¬o.Covered

def StandingFailOrHoldCoversNothing : Prop :=
  ∀ (o : Obs) (v : Verdict), v ∈ o.verdicts → o.stands v →
    (v.result = .fail ∨ v.result = .hold) → ¬o.Covered

def CoverIsAnotherJudgesWord : Prop :=
  ∀ o : Obs, o.Covered → ∃ a, o.author = some a ∧ ∃ v ∈ o.verdicts, o.stands v ∧
    v.judge ≠ a.who ∧ (v.result = .wordingOnly ∨ (v.result = .pass ∧ v.model ≠ a.model))

def CriticalCoverIsAnOpusPassOrWordingOnly : Prop :=
  ∀ o : Obs, o.Covered → o.critical = true → ∃ a, o.author = some a ∧
    ∃ v ∈ o.verdicts, o.stands v ∧ v.judge ≠ a.who ∧
      (v.result = .wordingOnly ∨ (v.result = .pass ∧ v.judge.name = "verifier-opus"))

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
    · split at h <;> cases h
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
  have h3 : (rank e o).1 = if e.lander.isOwner then 0 else 1 := rfl
  have h4 : (rank x.1 x.2).1 = if x.1.lander.isOwner then 0 else 1 := rfl
  simp only [before, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  cases he : e.lander <;> cases hxl : x.1.lander <;>
    simp [he, hxl, Lander.isOwner] at h3 h4 ⊢ <;> omega

theorem pushed_id (r v : Sha) (o : Obs) : (pushed r o).id? v = o.id? v := rfl

theorem pushKeepsCover : PushKeepsCover := by
  intro o v r hc hk
  simp only [Obs.carries, Obs.keeps, Bool.and_eq_true, beq_iff_eq] at hc hk
  obtain ⟨⟨hw, hs⟩, he⟩ := hc
  simp only [Obs.carries, Bool.and_eq_true, beq_iff_eq, pushed_id]
  refine ⟨⟨?_, hs⟩, ?_⟩
  · show Carry.walk v r (Push.toCarry ⟨true, o.head, r⟩ :: o.pushes.map Push.toCarry) = true
    simp [Carry.walk, Push.toCarry, Carry.Push.updaterForcePush, hw]
  · show o.id? v = o.id? r
    rw [he, hk.2]

theorem pushed_carries_iff {o : Obs} {r v : Sha} (hk : o.keeps r = true) (hv : v ≠ r) :
    (pushed r o).carries v = o.carries v := by
  simp only [Obs.keeps, Bool.and_eq_true, beq_iff_eq] at hk
  have hne : (r == v) = false := by simpa using fun h : r = v => hv h.symm
  have e2 : Carry.walk v (pushed r o).head ((pushed r o).pushes.map Push.toCarry) =
      Carry.walk v o.head (o.pushes.map Push.toCarry) := by
    show Carry.walk v r (Push.toCarry ⟨true, o.head, r⟩ :: o.pushes.map Push.toCarry) = _
    simp [Carry.walk, Push.toCarry, Carry.Push.updaterForcePush, hne]
  simp only [Obs.carries, pushed_id, e2]
  show (Carry.walk v o.head (o.pushes.map Push.toCarry) && (o.id? v).isSome &&
    o.id? v == o.id? r) = _
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
  simp only [landable, Bool.and_eq_true, Entry.valid, Obs.eligibleBeforeRebase,
    Option.isNone_iff_eq_none] at hl ⊢
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
       (o.enforced = true ∧ o.eligibleBeforeRebase = false ∧
         step me q o = .stop .notEligible) ∨
       (o.enforced = true ∧ o.eligibleBeforeRebase = true ∧
         ∃ why, step me q o = .stop (.stuck why)) ∨
       (o.enforced = true ∧ o.eligibleBeforeRebase = true ∧ o.stuck? = none ∧
         q.any (fun x => x.2.pr == o.pr && x.1.valid o) = false ∧
         (step me q o = .enter o.head ∨ step me q o = .stop .noEntry)) ∨
       (o.enforced = true ∧ o.eligibleBeforeRebase = true ∧ o.stuck? = none ∧
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
    · by_cases hel : o.eligibleBeforeRebase = true
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
      · have hel' : o.eligibleBeforeRebase = false := by simpa using hel
        right; left
        exact ⟨hen, hel', by simp [hen, hel']⟩
    · have hen' : o.enforced = false := by simpa using hen
      left
      exact ⟨hen', by simp [hen']⟩

theorem entries_agent {o : Obs} {e : Entry}
    (he : e ∈ o.words.filterMap (fun
      | .agentLand t m => if o.mayMerge t then some (⟨o.pr, m, .agent t⟩ : Entry) else none
      | _ => none)) : ∃ t, e.lander = .agent t ∧ o.mayMerge t = true := by
  simp only [List.mem_filterMap] at he
  obtain ⟨w, _, hw⟩ := he
  cases w with
  | agentLand t m =>
    simp only at hw
    split at hw
    · next hm => cases hw; exact ⟨t, rfl, hm⟩
    · cases hw
  | ownerLand m => cases hw
  | ownerHold c => cases hw
  | ownerSpoke c => cases hw

theorem spokeSince_false {ws : List Word} {n : Nat} (h : spokeSince ws n = false) :
    ∀ s, Word.ownerSpoke s ∈ ws → s ≤ n := by
  intro s hs
  simp only [spokeSince, List.any_eq_false] at h
  simpa using h _ hs

theorem entries_cases {o : Obs} {e : Entry} (he : e ∈ o.entries) :
    (∃ t, e.lander = .agent t ∧ o.mayMerge t = true) ∨
      (e.lander = .owner ∧ e.pr = o.pr ∧ newestOwner o.words = some (.ownerLand e.mark) ∧
        spokeSince o.words e.mark.said = false ∧ (o.kept = true → e.mark.approves = true)) := by
  simp only [Obs.entries] at he
  split at he
  · cases he
  · next m hm =>
    split at he
    · next hk =>
      rcases List.mem_cons.1 he with rfl | he
      · simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at hk
        refine .inr ⟨rfl, rfl, hm, hk.2, fun hkept => ?_⟩
        rcases hk.1 with hk1 | hk1
        · rw [hkept] at hk1; cases hk1
        · exact hk1
      · exact .inl (entries_agent he)
    · exact .inl (entries_agent he)
  · exact .inl (entries_agent he)

theorem ownerEntryIsTheirLastWord : OwnerEntryIsTheirLastWord := by
  intro o e he hl
  rcases entries_cases he with ⟨t, ht, _⟩ | ⟨_, hp, hw, hs, ha⟩
  · rw [hl] at ht; cases ht
  · exact ⟨hp, hw, spokeSince_false hs, ha⟩

theorem keptEntryIsTheOwners : KeptEntryIsTheOwners := by
  intro o e he hk
  rcases entries_cases he with ⟨t, _, hm⟩ | ⟨hl, _⟩
  · simp only [Obs.mayMerge, Bool.and_eq_true, Bool.not_eq_true'] at hm
    rw [hk] at hm; cases hm.1
  · exact hl

theorem plannedMergeIsGated : PlannedMergeIsGated := by
  intro q p h hp
  simp only [plan] at hp
  split at hp
  · next e o hn =>
    have hl := next_landable hn
    split at hp
    · cases hp
    · next hb =>
      split at hp
      · next hc =>
        cases hp
        simp only [Bool.and_eq_true, beq_iff_eq] at hc
        obtain ⟨how, hg⟩ := hc
        simp only [landable, Entry.valid, Obs.eligibleBeforeRebase, Bool.and_eq_true,
          List.contains_iff_mem] at hl
        obtain ⟨⟨⟨hmem, hel⟩, hcar⟩, _⟩ := hl
        have hlan : e.lander = .owner := by
          cases hx : e.lander with
          | owner => rfl
          | agent t => rw [hx] at how; cases how
        obtain ⟨_, hw, hs, ha⟩ := ownerEntryIsTheirLastWord o e hmem hlan
        exact ⟨e, o, hn, rfl, rfl, hb, hg, hel.1.1.1.2, hel.1.1.1.1, of_decide_eq_true hel.1.1.2,
          hel.1.2, hel.2, hlan, hw, hs, hcar, ha⟩
      · cases hp
    · cases hp
  · cases hp

theorem onlyLandOrHoldChangesTheWord : OnlyLandOrHoldChangesTheWord := by
  intro ws
  induction ws with
  | nil => rfl
  | cons w ws ih =>
    by_cases hw : w.decides = true
    · simp only [List.filter, hw, newestOwner, ← ih]
    · have hw' : w.decides = false := by simpa using hw
      simp only [List.filter, hw', newestOwner, ← ih]
      cases newestOwner ws <;> simp

theorem wordStandsIsTheEntry : WordStandsIsTheEntry := by
  intro o
  constructor
  · intro h
    simp only [Obs.word] at h
    split at h
    · cases h
    · next m hm =>
      split at h
      · cases h
      · next hk =>
        split at h
        · cases h
        · next hs =>
          split at h
          · cases h
          · next hc =>
            refine ⟨⟨o.pr, m, .owner⟩, ?_, rfl, by simpa using hc⟩
            simp only [Obs.entries, hm]
            have : ((!o.kept || m.approves) && !spokeSince o.words m.said) = true := by
              cases hko : o.kept <;> cases ha : m.approves <;> simp_all
            simp [this]
    · cases h
  · rintro ⟨e, he, hl, hc⟩
    rcases entries_cases he with ⟨t, ht, _⟩ | ⟨_, _, hw, hs, ha⟩
    · rw [hl] at ht; cases ht
    · simp only [Obs.word, hw]
      have hk : (o.kept && !e.mark.approves) = false := by
        cases hko : o.kept
        · rfl
        · simp [ha hko]
      simp [hk, hs, hc]

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
          simp only [Obs.eligibleBeforeRebase, Bool.and_eq_true] at hel
          exact ⟨rfl, hb, hg, hen, hm.1, hm.2, of_decide_eq_true hel.1.1.2⟩
        · rw [h1] at hs; cases hs
        · rw [h1] at hs; cases hs
        · rw [h1] at hs; cases hs

theorem unenforcedLandsNothing : UnenforcedLandsNothing := by
  intro o hen
  refine ⟨fun e => by simp [Entry.valid, Obs.eligibleBeforeRebase, hen], ?_⟩
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
      have hd : w.decides = false := by cases w <;> simp_all [Word.decides, Word.byOwner]
      simp only [List.filter, hw', newestOwner, ← ih, hd]
      cases newestOwner ws <;> simp

theorem newestOwner_none {ws : List Word} (h : newestOwner ws = none) :
    ∀ x ∈ ws, x.decides = false := by
  induction ws with
  | nil => intro x hx; cases hx
  | cons y ys ih =>
    simp only [newestOwner] at h
    cases hr : newestOwner ys with
    | some z =>
      rw [hr] at h
      simp only at h
      split at h <;> cases h
    | none =>
      rw [hr] at h
      simp only at h
      intro x hx
      rcases List.mem_cons.1 hx with hxy | hx
      · subst hxy
        by_cases hb : x.decides = true
        · simp [hb] at h
        · simpa using hb
      · exact ih hr x hx

theorem newestOwner_max {ws : List Word} {w : Word} (h : newestOwner ws = some w) :
    w ∈ ws ∧ w.decides = true ∧ ∀ x ∈ ws, x.decides = true → x.said ≤ w.said := by
  induction ws generalizing w with
  | nil => simp [newestOwner] at h
  | cons y ys ih =>
    simp only [newestOwner] at h
    cases hr : newestOwner ys with
    | some z =>
      rw [hr] at h
      simp only at h
      obtain ⟨hm, hb, hx⟩ := ih hr
      split at h
      · next hc =>
        cases h
        simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
        refine ⟨List.mem_cons_self, hc.1, fun x hxm hxb => ?_⟩
        rcases List.mem_cons.1 hxm with hxy | hxm
        · subst hxy; exact Nat.le_refl _
        · exact Nat.le_trans (hx x hxm hxb) (Nat.le_of_lt hc.2)
      · next hc =>
        cases h
        refine ⟨List.mem_cons_of_mem _ hm, hb, fun x hxm hxb => ?_⟩
        rcases List.mem_cons.1 hxm with hxy | hxm
        · subst hxy
          rcases Nat.lt_or_ge w.said x.said with hlt | hle
          · exact absurd (by simp [hxb, hlt]) hc
          · exact hle
        · exact hx x hxm hxb
    | none =>
      rw [hr] at h
      simp only at h
      split at h
      · next hb =>
        cases h
        refine ⟨List.mem_cons_self, hb, fun x hxm hxb => ?_⟩
        rcases List.mem_cons.1 hxm with hxy | hxm
        · subst hxy; exact Nat.le_refl _
        · have := newestOwner_none hr x hxm
          rw [this] at hxb
          cases hxb
      · cases h

theorem eq_of_said_eq : ∀ {ws : List Word}, (ws.map Word.said).Nodup → ∀ {a b : Word},
    a ∈ ws → b ∈ ws → a.said = b.said → a = b
  | [], _, _, _, ha, _, _ => by cases ha
  | y :: ys, hn, a, b, ha, hb, h => by
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
    rcases List.mem_cons.1 ha with hay | hay <;> rcases List.mem_cons.1 hb with hby | hby
    · rw [hay, hby]
    · exact absurd ⟨b, hby, by rw [← h, hay]⟩ hn.1
    · exact absurd ⟨a, hay, by rw [h, hby]⟩ hn.1
    · exact eq_of_said_eq hn.2 hay hby h

theorem newestOwner_eq_some {ws : List Word} {w : Word} (hn : (ws.map Word.said).Nodup) :
    newestOwner ws = some w ↔
      w ∈ ws ∧ w.decides = true ∧ ∀ x ∈ ws, x.decides = true → x.said ≤ w.said := by
  constructor
  · exact newestOwner_max
  · rintro ⟨hm, hb, hx⟩
    cases h : newestOwner ws with
    | none =>
      have := newestOwner_none h w hm
      rw [this] at hb
      cases hb
    | some w' =>
      obtain ⟨hm', hb', hx'⟩ := newestOwner_max h
      rw [eq_of_said_eq hn hm' hm (Nat.le_antisymm (hx w' hm' hb') (hx' w hm hb))]

theorem newestOwner_perm {ws ws' : List Word} (hp : ws.Perm ws')
    (hn : (ws.map Word.said).Nodup) : newestOwner ws = newestOwner ws' := by
  have hn' : (ws'.map Word.said).Nodup := (hp.map _).nodup_iff.1 hn
  have key : ∀ w, newestOwner ws = some w ↔ newestOwner ws' = some w := by
    intro w
    rw [newestOwner_eq_some hn, newestOwner_eq_some hn']
    simp only [hp.mem_iff]
  cases h : newestOwner ws with
  | some w => exact ((key w).1 h).symm
  | none =>
    cases h' : newestOwner ws' with
    | none => rfl
    | some w' =>
      have := (key w').2 h'
      rw [h] at this
      cases this

theorem toCarry_updaterForcePush (p : Push) : p.toCarry.updaterForcePush = p.byUpdater := by
  cases h : p.byUpdater <;> simp [Push.toCarry, Carry.Push.updaterForcePush, h]

theorem onlyMergersQueue : OnlyMergersQueue := by
  intro o e t he hl
  rcases entries_cases he with ⟨t', ht, hm⟩ | ⟨ho, _⟩
  · rw [hl] at ht
    cases ht
    simpa [Obs.mayMerge] using hm
  · rw [hl] at ho; cases ho

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
  intro agentInLine ownerInLine covered p g hg
  refine ⟨rfl, rfl, fun hc => by simp [wake, hc], ?_, ?_, ?_, ?_⟩ <;>
    cases hi : agentInLine p <;> cases ho : ownerInLine p <;> cases hc : covered p <;>
    cases g <;> simp_all [wake]

theorem unknownAuthorCoversNothing : UnknownAuthorCoversNothing := by
  intro o ha hc
  unfold Obs.Covered at hc
  rw [ha] at hc
  exact hc

theorem standingFailOrHoldCoversNothing : StandingFailOrHoldCoversNothing := by
  intro o v hv hs hr hc
  unfold Obs.Covered at hc
  split at hc
  · exact hc
  · obtain ⟨hf, hh⟩ := hc.1 v hv hs
    rcases hr with hr | hr
    · exact hf hr
    · exact hh hr

theorem coverIsAnotherJudgesWord : CoverIsAnotherJudgesWord := by
  intro o hc
  unfold Obs.Covered at hc
  split at hc
  · exact hc.elim
  · next a ha =>
    refine ⟨a, ha, ?_⟩
    rcases hc.2 with ⟨v, hm, hs, hr, hj⟩ | ⟨⟨v, hm, hs, hr, hj, hmod⟩, _⟩
    · exact ⟨v, hm, hs, hj, .inl hr⟩
    · exact ⟨v, hm, hs, hj, .inr ⟨hr, hmod⟩⟩

theorem criticalCoverIsAnOpusPassOrWordingOnly : CriticalCoverIsAnOpusPassOrWordingOnly := by
  intro o hc hcr
  unfold Obs.Covered at hc
  split at hc
  · exact hc.elim
  · next a ha =>
    refine ⟨a, ha, ?_⟩
    rcases hc.2 with ⟨v, hm, hs, hr, hj⟩ | ⟨_, h3⟩
    · exact ⟨v, hm, hs, hj, .inl hr⟩
    · obtain ⟨v, hm, hs, hr, hj, hn⟩ := h3 hcr
      exact ⟨v, hm, hs, hj, .inr ⟨hr, hn⟩⟩

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

def orchestrator : Teammate := ⟨"claude", "orchestrator"⟩
def undelegated : Teammate := ⟨"grok", "worker"⟩
def verifier : Teammate := ⟨"claude", "verifier"⟩
def verifierOpus : Teammate := ⟨"claude", "verifier-opus"⟩
def grokBuilder : Teammate := ⟨"grok", "builder"⟩
def ownerKeptMark : Mark := ⟨900, "aaa", true⟩
def agentMark : Mark := ⟨800, "bbb", false⟩
def agentPushedMark : Mark := ⟨700, "ccc", false⟩

def ownerKeptBehind : Obs :=
  { pr := 153, updatable := true, enforced := true, head := "aaa", pushes := [],
    ids := [("aaa", "id-a"), ("ar", "id-a")], paths := some [".github/workflows/ci.yml"],
    base := .clean "ar", gate := .success, author := some ⟨grokBuilder, "grok"⟩,
    verdicts := [⟨850, "aaa", verifierOpus, "opus", .pass⟩,
      ⟨851, "aaa", verifier, "sonnet", .pass⟩],
    botAt := some "aaa", delegates := [orchestrator], words := [.ownerLand ownerKeptMark],
    rest := true }
def agentBehind : Obs :=
  { ownerKeptBehind with pr := 149, head := "bbb", ids := [("bbb", "id-b"), ("br", "id-b")],
                         paths := some ["core/Mitos/Chain.lean"], base := .clean "br",
                         verdicts := [⟨750, "bbb", verifier, "sonnet", .pass⟩],
                         botAt := some "bbb", words := [.agentLand orchestrator agentMark] }
def agentPushedGatePending : Obs :=
  { agentBehind with pr := 159, head := "cc2", pushes := [⟨true, "ccc", "cc2"⟩],
                     ids := [("ccc", "id-c"), ("cc2", "id-c")], base := .current,
                     gate := .pending, verdicts := [⟨650, "ccc", verifier, "sonnet", .pass⟩],
                     botAt := some "ccc", words := [.agentLand orchestrator agentPushedMark] }
def ownerKeptJustPushed : Obs := pushed "ar" ownerKeptBehind
def ownerKeptPushed : Obs := { ownerKeptJustPushed with gate := .success }
def agentOnMain : Obs := { agentBehind with base := .current }
def ownerKeptHeld : Obs :=
  { ownerKeptBehind with words := [.ownerLand ownerKeptMark, .ownerHold 950] }
def agentPushedRed : Obs := { pushed "br" agentBehind with gate := .failure }
def ownerKeptNewContent : Obs :=
  { ownerKeptBehind with head := "fff", pushes := [⟨false, "aaa", "fff"⟩],
                         ids := [("aaa", "id-a"), ("fff", "id-f")] }

theorem noWordsNoEntries : (queueOf [{ agentBehind with words := [] }]).isEmpty = true := by
  decide +kernel
theorem noWordsNoPush : plan (queueOf [{ agentBehind with words := [] }]) = .idle := by
  decide +kernel
theorem delegateEntersWhenNoWordStands :
    step orchestrator [] { agentBehind with words := [] } = .enter "bbb" := by decide +kernel
theorem agentCannotEnterOnKeptPath :
    step orchestrator [] { ownerKeptBehind with words := [] } = .stop .noEntry := by
  decide +kernel
theorem agentWordOnKeptPathIsNoEntry :
    ({ ownerKeptBehind with words := [.agentLand orchestrator ⟨910, "aaa", false⟩] } : Obs).entries =
      [] := by decide +kernel
theorem ownerLandPushesFirst :
    plan (queueOf [ownerKeptBehind, agentBehind, agentPushedGatePending]) =
      .push 153 "aaa" "ar" := by decide +kernel
theorem agentWaitsBehindOwnerLand :
    step orchestrator (queueOf [ownerKeptBehind, agentBehind, agentPushedGatePending])
      agentPushedGatePending = .wait 153 := by decide +kernel
theorem landingInFlightBlocksOtherPushes :
    plan (queueOf [agentBehind, agentPushedGatePending]) = .idle := by decide +kernel
theorem behindAgentWaitsForLandingInFlight :
    step orchestrator (queueOf [agentBehind, agentPushedGatePending]) agentBehind =
      .wait 159 := by decide +kernel
theorem landingInFlightAwaitsItsGate :
    step orchestrator (queueOf [agentBehind, agentPushedGatePending]) agentPushedGatePending =
      .awaitGate "cc2" := by decide +kernel
theorem afterPushTheApprovedLandingIsMergedNotPushedAgain :
    plan (queueOf [ownerKeptPushed, agentBehind]) = .merge 153 "ar" := by decide +kernel
theorem afterPushNothingIsPushedWhileTheGateRuns :
    plan (queueOf [ownerKeptJustPushed, agentBehind]) = .idle := by decide +kernel
theorem pushedHeadAwaitsItsGate :
    step orchestrator (queueOf [ownerKeptJustPushed, agentBehind]) ownerKeptJustPushed =
      .awaitGate "ar" := by decide +kernel
theorem keptPathGreenIsPresentedNotMerged :
    step orchestrator (queueOf [ownerKeptPushed, agentBehind]) ownerKeptPushed =
      .present "ar" := by decide +kernel
theorem agentWaitsBehindPresentedOwnerLand :
    step orchestrator (queueOf [ownerKeptPushed, agentBehind]) agentBehind = .wait 153 := by
  decide +kernel
theorem newOwnerLandNamesThePresentedHead :
    (⟨153, ⟨950, "ar", true⟩, .owner⟩ : Entry).valid
      { ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerLand ⟨950, "ar", true⟩] } =
      true := by decide +kernel
theorem ownerLandNamingAnUnknownCommitStandsForNothing :
    (⟨153, ⟨950, "zzz", true⟩, .owner⟩ : Entry).valid
      { ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerLand ⟨950, "zzz", true⟩] } =
      false := by decide +kernel
theorem delegateMergesOffKeptPathPinnedToHead :
    step orchestrator (queueOf [agentOnMain]) agentOnMain = .merge "bbb" := by decide +kernel
theorem undelegatedTeammateOnlyPresents :
    step undelegated (queueOf [agentOnMain]) agentOnMain = .present "bbb" := by decide +kernel
theorem holdStopsItsPullRequest :
    step orchestrator (queueOf [ownerKeptHeld, agentBehind]) ownerKeptHeld = .stop .held := by
  decide +kernel
theorem holdLetsTheLineMoveOn :
    plan (queueOf [ownerKeptHeld, agentBehind]) = .push 149 "bbb" "br" := by decide +kernel
theorem redGateStopsItsPullRequest :
    step orchestrator (queueOf [agentPushedRed]) agentPushedRed = .stop (.stuck .red) := by
  decide +kernel
theorem redGateYieldsToTheLandingInFlight :
    plan (queueOf [agentPushedRed, agentPushedGatePending]) = .idle := by decide +kernel
theorem rerunGateTurnsGreenAndMerges :
    step orchestrator (queueOf [{ agentPushedRed with gate := .success }])
      { agentPushedRed with gate := .success } = .merge "br" := by decide +kernel
theorem replayThatChangesContentIsStuck :
    step orchestrator (queueOf [{ ownerKeptBehind with base := .clean "xx" }, agentBehind])
      { ownerKeptBehind with base := .clean "xx" } = .stop (.stuck .contentChanged) := by
  decide +kernel
theorem replayThatChangesContentLetsTheLineMoveOn :
    plan (queueOf [{ ownerKeptBehind with base := .clean "xx" }, agentBehind]) =
      .push 149 "bbb" "br" := by decide +kernel
theorem conflictIsStuck :
    step orchestrator (queueOf [{ ownerKeptBehind with base := .conflict }])
      { ownerKeptBehind with base := .conflict } = .stop (.stuck .conflict) := by decide +kernel
theorem conflictPushesNothing :
    plan (queueOf [{ ownerKeptBehind with base := .conflict }]) = .idle := by decide +kernel
theorem unreadBaseLetsTheLineMoveOn :
    plan (queueOf [{ ownerKeptBehind with base := .unread }, agentBehind]) =
      .push 149 "bbb" "br" := by decide +kernel
theorem headAlreadyOnMainIsStuck :
    step orchestrator (queueOf [{ ownerKeptBehind with base := .mergedMain }])
      { ownerKeptBehind with base := .mergedMain } = .stop (.stuck .historyError) := by
  decide +kernel
theorem headAlreadyOnMainLetsTheLineMoveOn :
    plan (queueOf [{ ownerKeptBehind with base := .mergedMain }, agentBehind]) =
      .push 149 "bbb" "br" := by decide +kernel
def agentBehindNewer : Obs :=
  { agentBehind with pr := 147, head := "ddd", ids := [("ddd", "id-d"), ("dr", "id-d")],
                     base := .clean "dr", verdicts := [⟨760, "ddd", verifier, "sonnet", .pass⟩],
                     botAt := some "ddd", words := [.agentLand orchestrator ⟨820, "ddd", false⟩] }
theorem olderAgentEntryIsPushedFirst :
    plan (queueOf [agentBehindNewer, agentBehind]) = .push 149 "bbb" "br" := by decide +kernel
theorem newContentRetiresTheOwnerWord :
    plan (queueOf [ownerKeptNewContent, agentBehind]) = .push 149 "bbb" "br" := by
  decide +kernel
theorem unenforcedPushesNothing :
    plan (queueOf [{ ownerKeptBehind with enforced := false },
      { agentBehind with enforced := false }]) = .idle := by decide +kernel
theorem unenforcedStopsTheStep :
    step orchestrator [] { agentBehind with enforced := false } = .stop .unenforced := by
  decide +kernel
theorem unverifiedPushesNothing :
    plan (queueOf [{ agentBehind with verdicts := [] }]) = .idle := by decide +kernel
theorem unverifiedIsNotEligible :
    step orchestrator (queueOf [{ agentBehind with verdicts := [] }])
      { agentBehind with verdicts := [] } = .stop .notEligible := by decide +kernel
theorem undelegatedTeammateCannotQueue :
    ({ agentBehind with words := [.agentLand orchestrator agentMark,
        .agentLand undelegated ⟨810, "bbb", false⟩] } : Obs).entries =
      [⟨149, agentMark, .agent orchestrator⟩] := by decide +kernel
theorem unreadPathsAreKept : ({ agentBehind with paths := none } : Obs).kept = true := by
  decide +kernel
theorem keptPathsByName :
    [keptPath "plan/phase-2.md", keptPath "examples/acme/models.lock",
      keptPath "core/Mitos/Chain.lean", keptPath "lakefile.toml",
      keptPath "eval/score/lakefile.toml"] = [true, true, false, true, false] := by
  decide +kernel
theorem criticalPathsByName :
    [criticalPath "plan/phase-2.md", criticalPath ".claude/skills/x.md",
      criticalPath "gate/Main.lean"] = [false, false, true] := by decide +kernel
theorem ruleFilesAreKeptButNotCritical :
    [".claude/settings.json", ".cursor/rules/x.mdc", "plan/phase-2.md", "CLAUDE.md",
      "docs/process.md"].map (fun p => (keptPath p, criticalPath p)) =
      [(true, false), (true, false), (true, false), (true, false), (true, false)] := by
  decide +kernel
theorem trustTreesAreCritical :
    ["gate/Main.lean", "eval/cheats/sorry/expect", ".github/workflows/ci.yml",
      "core/Mitos/Core/Resolve.lean", "core/Challenge/Resolver.lean"].map
      (fun p => (keptPath p, criticalPath p)) =
      [(true, true), (true, true), (true, true), (true, true), (true, true)] := by
  decide +kernel
theorem trustFilesAreCritical :
    ["lean-toolchain", "lakefile.toml", "core/lakefile.toml", "core/Mitos/Core.lean",
      "core/comparator.json", "statements.lock", "models.lock", "examples/acme/statements.lock",
      "examples/acme/models.lock"].map (fun p => (keptPath p, criticalPath p)) =
      [(true, true), (true, true), (true, true), (true, true), (true, true), (true, true),
        (true, true), (true, true), (true, true)] := by
  decide +kernel
theorem nearMissesAreNotKept :
    ["gateway/x.lean", "eval/cheatsheet.md", "core/Mitos/CoreX.lean", "plans/x.md",
      "docs/process.md.orig", "xCLAUDE.md", "lean-toolchain.bak", "xstatements.lock",
      "xmodels.lock"].map keptPath =
      [false, false, false, false, false, false, false, false, false] := by
  decide +kernel
theorem unreadPathsAreCritical : ({ agentBehind with paths := none } : Obs).critical = true := by
  decide +kernel
theorem unreadPathsNeedAnOpusPass : ({ agentBehind with paths := none } : Obs).covered = false := by
  decide +kernel

def verifierSonnet : Teammate := ⟨"claude", "verifier-sonnet"⟩
def reviewerOpus : Teammate := ⟨"claude", "reviewer-opus"⟩
def root : Teammate := ⟨"claude", "root"⟩
def holderOpus : Teammate := ⟨"claude", "worker-opus"⟩

def opusWrittenReady : Obs :=
  { pr := 201, updatable := true, enforced := true, head := "h", pushes := [],
    ids := [("h", "id-h"), ("g", "id-g")], paths := some ["core/Mitos/Chain.lean"],
    base := .current, gate := .success, author := some ⟨holderOpus, "opus"⟩,
    verdicts := [⟨10, "h", verifierSonnet, "sonnet", .pass⟩], botAt := some "h",
    delegates := [orchestrator], words := [.agentLand orchestrator ⟨30, "h", false⟩], rest := true }
def onTrustPath (o : Obs) : Obs := { o with paths := some ["gate/Main.lean"] }
def behindMain (o : Obs) : Obs :=
  { o with base := .clean "h2", ids := [("h", "id-h"), ("h2", "id-h")] }

theorem sonnetPassCoversOpusWrittenWork : opusWrittenReady.covered = true := by decide +kernel
theorem coveredOnMainMerges :
    step orchestrator (queueOf [opusWrittenReady]) opusWrittenReady = .merge "h" := by
  decide +kernel
theorem coveredBehindMainIsPushed :
    plan (queueOf [behindMain opusWrittenReady]) = .push 201 "h" "h2" := by decide +kernel
theorem passAboutOtherContentCoversNothing :
    ({ opusWrittenReady with verdicts := [⟨10, "g", verifierSonnet, "sonnet", .pass⟩] } :
      Obs).covered = false := by decide +kernel
theorem passStillCoversAfterTheUpdaterPush : agentPushedGatePending.covered = true := by
  decide +kernel
theorem aPushByAnyoneElseDoesNotCarryThePass :
    ({ agentPushedGatePending with pushes := [⟨false, "ccc", "cc2"⟩] } : Obs).covered =
      false := by decide +kernel
theorem aHeadWithoutAContentIdIsNotCovered :
    ({ opusWrittenReady with ids := [] } : Obs).covered = false := by decide +kernel
theorem authorsOwnPassCoversNothing :
    ({ opusWrittenReady with verdicts := [⟨10, "h", holderOpus, "sonnet", .pass⟩] } :
      Obs).covered = false := by decide +kernel
theorem passOnTheAuthorsModelCoversNothing :
    ({ opusWrittenReady with verdicts := [⟨10, "h", reviewerOpus, "opus", .pass⟩] } :
      Obs).covered = false := by decide +kernel
theorem builderOwnPassCoversNothing :
    ({ agentBehind with verdicts := [⟨750, "bbb", grokBuilder, "sonnet", .pass⟩] } :
      Obs).covered = false := by decide +kernel
theorem passByAnotherJudgeOnTheAuthorsModelCoversNothing :
    ({ agentBehind with verdicts := [⟨750, "bbb", verifier, "grok", .pass⟩] } :
      Obs).covered = false := by decide +kernel
def passedThenFailed : Obs :=
  { opusWrittenReady with verdicts :=
    [⟨10, "h", verifierSonnet, "sonnet", .pass⟩, ⟨20, "h", reviewerOpus, "opus", .fail⟩] }
theorem failFromTheAuthorsModelBlocks : passedThenFailed.covered = false := by decide +kernel
theorem failStopsTheStep :
    step orchestrator (queueOf [passedThenFailed]) passedThenFailed = .stop .notEligible := by
  decide +kernel
theorem failedBehindMainIsNotPushed : plan (queueOf [behindMain passedThenFailed]) = .idle := by
  decide +kernel
theorem holdFromTheAuthorsModelBlocks :
    ({ opusWrittenReady with verdicts :=
      [⟨10, "h", verifierSonnet, "sonnet", .pass⟩,
        ⟨20, "h", reviewerOpus, "opus", .hold⟩] } : Obs).covered = false := by decide +kernel
theorem olderFailBlocksAnotherJudgesNewerPass :
    ({ opusWrittenReady with verdicts :=
      [⟨5, "h", reviewerOpus, "opus", .fail⟩,
        ⟨10, "h", verifierSonnet, "sonnet", .pass⟩] } : Obs).covered = false := by decide +kernel
theorem authorsOwnHoldBlocks :
    ({ opusWrittenReady with verdicts :=
      opusWrittenReady.verdicts ++ [⟨20, "h", holderOpus, "opus", .hold⟩] } : Obs).covered =
      false := by decide +kernel
theorem judgesNewerPassLiftsItsOwnFail :
    ({ passedThenFailed with verdicts :=
      passedThenFailed.verdicts ++ [⟨25, "h", reviewerOpus, "opus", .pass⟩] } : Obs).covered =
      true := by decide +kernel
theorem anotherJudgesNewerPassKeepsTheFail :
    ({ passedThenFailed with verdicts :=
      passedThenFailed.verdicts ++ [⟨25, "h", verifierSonnet, "sonnet", .pass⟩] } :
      Obs).covered = false := by decide +kernel
theorem failAboutOtherContentIsIgnored :
    ({ opusWrittenReady with verdicts :=
      opusWrittenReady.verdicts ++ [⟨20, "g", reviewerOpus, "opus", .fail⟩] } : Obs).covered =
      true := by decide +kernel
def criticalTwoPasses : Obs :=
  onTrustPath { opusWrittenReady with verdicts :=
    [⟨10, "h", verifierSonnet, "sonnet", .pass⟩, ⟨11, "h", verifierOpus, "opus", .pass⟩] }
theorem criticalWithAnOpusPassIsCovered : criticalTwoPasses.covered = true := by decide +kernel
theorem criticalWithoutAnOpusPassIsNotCovered :
    (onTrustPath opusWrittenReady).covered = false := by decide +kernel
def criticalAuthoredByVerifierOpus : Obs :=
  onTrustPath { criticalTwoPasses with author := some ⟨verifierOpus, "opus"⟩ }
theorem criticalAuthorsOwnOpusPassIsNotTheOpusPass :
    criticalAuthoredByVerifierOpus.covered = false := by decide +kernel
theorem criticalWithOnlyAnOpusPassOnTheAuthorsModelIsNotCovered :
    (onTrustPath { opusWrittenReady with verdicts :=
      [⟨11, "h", verifierOpus, "opus", .pass⟩] }).covered = false := by decide +kernel
def criticalSonnetAuthored : Obs :=
  onTrustPath { opusWrittenReady with author := some ⟨holderOpus, "sonnet"⟩,
                                      verdicts := [⟨11, "h", verifierOpus, "opus", .pass⟩] }
theorem criticalSonnetAuthoredNeedsOnlyOneOpusPass :
    criticalSonnetAuthored.covered = true := by decide +kernel
theorem opusFailBlocks :
    ({ opusWrittenReady with verdicts :=
      opusWrittenReady.verdicts ++ [⟨11, "h", verifierOpus, "opus", .fail⟩] } : Obs).covered =
      false := by decide +kernel
theorem criticalOwnerLandIsPresentedNotMerged :
    step orchestrator (queueOf [{ criticalTwoPasses with words := [.ownerLand ⟨30, "h", true⟩] }])
      { criticalTwoPasses with words := [.ownerLand ⟨30, "h", true⟩] } = .present "h" := by
  decide +kernel
def wordingOnlyByRoot : Obs :=
  { opusWrittenReady with verdicts := [⟨10, "h", root, "opus", .wordingOnly⟩] }
theorem wordingOnlyCovers : wordingOnlyByRoot.covered = true := by decide +kernel
theorem wordingOnlyMerges :
    step orchestrator (queueOf [wordingOnlyByRoot]) wordingOnlyByRoot = .merge "h" := by
  decide +kernel
theorem wordingOnlyCoversATrustPath : (onTrustPath wordingOnlyByRoot).covered = true := by
  decide +kernel
def failBeforeWordingOnly : Obs :=
  { wordingOnlyByRoot with verdicts :=
    [⟨5, "h", verifierSonnet, "sonnet", .fail⟩, ⟨10, "h", root, "opus", .wordingOnly⟩] }
theorem failBeatsWordingOnly : failBeforeWordingOnly.covered = false := by decide +kernel
theorem holdBeatsWordingOnly :
    ({ wordingOnlyByRoot with verdicts :=
      wordingOnlyByRoot.verdicts ++ [⟨20, "h", verifierSonnet, "sonnet", .hold⟩] } :
      Obs).covered = false := by decide +kernel
theorem ownPassLiftsFailBesideWordingOnly :
    ({ wordingOnlyByRoot with verdicts :=
      [⟨5, "h", verifierSonnet, "sonnet", .fail⟩, ⟨8, "h", verifierSonnet, "sonnet", .pass⟩,
        ⟨10, "h", root, "opus", .wordingOnly⟩] } : Obs).covered = true := by decide +kernel
theorem authorsOwnWordingOnlyCoversNothing :
    ({ wordingOnlyByRoot with verdicts := [⟨10, "h", holderOpus, "opus", .wordingOnly⟩] } :
      Obs).covered = false := by decide +kernel
theorem wordingOnlyAboutOtherContentCoversNothing :
    ({ wordingOnlyByRoot with verdicts := [⟨10, "g", root, "opus", .wordingOnly⟩] } :
      Obs).covered = false := by decide +kernel
theorem newerPassFromTheSameJudgeRetiresItsWordingOnly :
    ({ wordingOnlyByRoot with verdicts :=
      wordingOnlyByRoot.verdicts ++ [⟨20, "h", root, "opus", .pass⟩] } : Obs).covered =
      false := by decide +kernel
def ownerLandedTwoPasses : Obs :=
  { criticalTwoPasses with paths := opusWrittenReady.paths, words := [.ownerLand ⟨30, "h", true⟩] }
def ownerLandedWithoutAuthor : Obs := { ownerLandedTwoPasses with author := none }
theorem ownerLandedTwoPassesAreCovered : ownerLandedTwoPasses.covered = true := by
  decide +kernel
theorem noKnownAuthorCoversNothingDespiteTwoPasses :
    ownerLandedWithoutAuthor.covered = false := by decide +kernel
theorem noKnownAuthorWordingOnlyCoversNothing :
    ({ wordingOnlyByRoot with author := none } : Obs).covered = false := by decide +kernel
theorem noKnownAuthorIsNotEligible :
    step orchestrator (queueOf [ownerLandedWithoutAuthor]) ownerLandedWithoutAuthor =
      .stop .notEligible := by decide +kernel
theorem ownerLandedBehindMainIsPushed :
    plan (queueOf [behindMain ownerLandedTwoPasses]) = .push 201 "h" "h2" := by decide +kernel
theorem noKnownAuthorBehindMainIsNotPushed :
    plan (queueOf [behindMain ownerLandedWithoutAuthor]) = .idle := by decide +kernel

theorem newestOwnerIsTheGreatestIdListedFirst :
    newestOwner [.ownerHold 950, .ownerLand ⟨900, "aaa", true⟩] = some (.ownerHold 950) := by
  decide +kernel
theorem newestOwnerIsTheGreatestIdListedLast :
    newestOwner [.ownerLand ⟨900, "aaa", true⟩, .ownerHold 950] = some (.ownerHold 950) := by
  decide +kernel
theorem holdListedFirstStillHolds :
    ({ ownerKeptBehind with words := [.ownerHold 950, .ownerLand ownerKeptMark] } :
      Obs).entries = [] := by decide +kernel
theorem newerLandListedFirstStillStands :
    ({ ownerKeptBehind with words := [.ownerLand ⟨960, "aaa", true⟩, .ownerHold 950] } :
      Obs).entries = [⟨153, ⟨960, "aaa", true⟩, .owner⟩] := by decide +kernel

theorem conflictOnCoveredWorkWakesTheHolder :
    wake (fun _ => false) (fun _ => false) (fun _ => true) (.conflictFound 126) =
      .holder 126 := by decide +kernel
theorem conflictOnUncoveredWorkWakesNobody :
    wake (fun _ => false) (fun _ => false) (fun _ => false) (.conflictFound 126) =
      .nobody := by decide +kernel
theorem landWordOutOfLineWakesTheOrchestrator :
    wake (fun _ => false) (fun _ => false) (fun _ => true) (.landWord 126) =
      .orchestrator := by decide +kernel
theorem landWordOnAnAgentEntryWakesNobody :
    wake (fun p => p == 126) (fun _ => false) (fun _ => true) (.landWord 126) = .nobody := by
  decide +kernel
theorem landWordOnTheOwnersWordAloneWakesNobody :
    wake (fun _ => false) (fun p => p == 126) (fun _ => true) (.landWord 126) = .nobody := by
  decide +kernel
theorem greenGateOnAnAgentEntryWakesItsLander :
    wake (fun p => p == 149) (fun _ => false) (fun _ => true) (.gateDone 149 .success) =
      .lander 149 := by decide +kernel
theorem greenGateOnTheOwnersWordAloneWakesNobody :
    wake (fun _ => false) (fun p => p == 153) (fun _ => true) (.gateDone 153 .success) =
      .nobody := by decide +kernel
theorem greenGateOnTheOwnersWordAloneWakesNobodyEvenUncovered :
    wake (fun _ => false) (fun p => p == 153) (fun _ => false) (.gateDone 153 .success) =
      .nobody := by decide +kernel
theorem agentEntryWinsOverTheOwnersWord :
    wake (fun p => p == 149) (fun p => p == 149) (fun _ => true) (.gateDone 149 .success) =
      .lander 149 := by decide +kernel
theorem greenGateOutOfLineWakesNobody :
    wake (fun p => p == 149) (fun _ => false) (fun _ => true) (.gateDone 153 .success) =
      .nobody := by decide +kernel
theorem redGateOnAnAgentEntryWakesTheHolder :
    wake (fun p => p == 149) (fun _ => false) (fun _ => true) (.gateDone 149 .failure) =
      .holder 149 := by decide +kernel
theorem redGateOnTheOwnersWordAloneWakesTheHolder :
    wake (fun _ => false) (fun p => p == 153) (fun _ => true) (.gateDone 153 .failure) =
      .holder 153 := by decide +kernel
theorem unfinishedGateOnTheOwnersWordAloneWakesTheOrchestrator :
    [Gate.cancelled, .skipped, .pending, .missing].map (fun g =>
      wake (fun _ => false) (fun p => p == 153) (fun _ => true) (.gateDone 153 g)) =
      [.orchestrator, .orchestrator, .orchestrator, .orchestrator] := by decide +kernel
theorem unfinishedGateOnTheOwnersWordAloneWakesTheOrchestratorEvenUncovered :
    [Gate.cancelled, .skipped, .pending, .missing].map (fun g =>
      wake (fun _ => false) (fun p => p == 153) (fun _ => false) (.gateDone 153 g)) =
      [.orchestrator, .orchestrator, .orchestrator, .orchestrator] := by decide +kernel
theorem botReviewOfUncoveredWorkWakesTheHolder :
    wake (fun _ => false) (fun _ => false) (fun _ => false) (.botReviewed 149) = .holder 149 := by
  decide +kernel
theorem unfinishedGateOnUncoveredWorkOutOfLineWakesTheHolder :
    wake (fun _ => false) (fun _ => false) (fun _ => false) (.gateDone 149 .cancelled) =
      .holder 149 := by decide +kernel
theorem otherOwnerSpeechWakesTheOrchestrator :
    wake (fun _ => false) (fun p => p == 153) (fun _ => true) (.ownerSpoke 153) =
      .orchestrator := by decide +kernel
theorem updaterPushWakesNobody :
    wake (fun p => p == 149) (fun _ => false) (fun _ => true) (.updaterPushed 149) =
      .nobody := by decide +kernel
theorem mainMovedWakesNobody :
    wake (fun _ => false) (fun _ => false) (fun _ => true) .mainMoved = .nobody := by
  decide +kernel

theorem snapshotGreenGateOnTheOwnersEntryWakesNobody :
    wakeOf [ownerKeptBehind, agentBehind, agentPushedGatePending] (.gateDone 153 .success) =
      .nobody := by decide +kernel
theorem snapshotGreenGateOnAnAgentEntryWakesItsLander :
    wakeOf [ownerKeptBehind, agentBehind, agentPushedGatePending] (.gateDone 149 .success) =
      .lander 149 := by decide +kernel
theorem snapshotRedGateOnTheOwnersEntryWakesTheHolder :
    wakeOf [ownerKeptBehind, agentBehind, agentPushedGatePending] (.gateDone 153 .failure) =
      .holder 153 := by decide +kernel
theorem snapshotCancelledGateOnTheOwnersEntryWakesTheOrchestrator :
    wakeOf [{ ownerKeptPushed with gate := .cancelled }, agentBehind] (.gateDone 153 .cancelled) =
      .orchestrator := by decide +kernel
theorem snapshotSkippedGateOnTheOwnersEntryWakesTheOrchestrator :
    wakeOf [{ ownerKeptPushed with gate := .skipped }, agentBehind] (.gateDone 153 .skipped) =
      .orchestrator := by decide +kernel
theorem cancelledGateOnTheOwnersEntryIsRerun :
    step orchestrator (queueOf [{ ownerKeptPushed with gate := .cancelled }, agentBehind])
      { ownerKeptPushed with gate := .cancelled } = .awaitGate "ar" := by decide +kernel
theorem snapshotGreenGateOnAStuckEntryWakesNobody :
    wakeOf [{ agentBehind with base := .conflict }] (.gateDone 149 .success) = .nobody := by
  decide +kernel
theorem snapshotOwnerAndAgentWordsWakeTheLander :
    wakeOf [{ agentBehind with words :=
      [.agentLand orchestrator agentMark, .ownerLand ⟨810, "bbb", true⟩] }] (.gateDone 149 .success) =
      .lander 149 := by decide +kernel

def bare : Mark := ⟨900, "aaa", false⟩
def bareKeptBehind : Obs := { ownerKeptBehind with words := [.ownerLand bare] }
def bareKeptOnMain : Obs := { ownerKeptPushed with words := [.ownerLand bare] }
def offKeptOwnerLanded : Obs := { agentOnMain with words := [.ownerLand ⟨810, "bbb", false⟩] }
def approvedThenNewContent : Obs :=
  { ownerKeptPushed with head := "fff", pushes := [⟨false, "ar", "fff"⟩, ⟨true, "aaa", "ar"⟩],
                         ids := [("aaa", "id-a"), ("ar", "id-a"), ("fff", "id-f")],
                         verdicts := [⟨870, "fff", verifierOpus, "opus", .pass⟩,
                           ⟨871, "fff", verifier, "sonnet", .pass⟩], botAt := some "fff" }
def approvedJudgedOnTheAuthorsModel : Obs :=
  { ownerKeptPushed with paths := some ["core/Mitos/Chain.lean", "CLAUDE.md"],
                         author := some ⟨grokBuilder, "sonnet"⟩,
                         verdicts := [⟨851, "aaa", verifier, "sonnet", .pass⟩] }
def secondApproved : Obs :=
  { ownerKeptBehind with pr := 154, words := [.ownerLand ⟨901, "aaa", true⟩] }

theorem bareLandOnAKeptPathIsNoEntry : bareKeptBehind.entries = [] := by decide +kernel
theorem bareLandOnAKeptPathIsNotPushed :
    plan (queueOf [bareKeptBehind, agentBehind]) = .push 149 "bbb" "br" := by decide +kernel
theorem bareLandOnAKeptPathIsNotMerged : plan (queueOf [bareKeptOnMain]) = .idle := by
  decide +kernel
theorem bareLandOnAKeptPathDoesNotHoldTheLine :
    plan (queueOf [bareKeptOnMain, secondApproved]) = .push 154 "aaa" "ar" := by decide +kernel
theorem bareLandOnUnreadPathsIsNotMerged :
    plan (queueOf [{ bareKeptOnMain with paths := none }]) = .idle := by decide +kernel
theorem bareLandOffEveryKeptPathIsMerged :
    plan (queueOf [offKeptOwnerLanded]) = .merge 149 "bbb" := by decide +kernel
theorem agentStepOnAnApprovedKeptPathIsStillPresent :
    step orchestrator (queueOf [ownerKeptPushed]) ownerKeptPushed = .present "ar" := by
  decide +kernel
theorem agentEntryIsNeverThePlannedMerge : plan (queueOf [agentOnMain]) = .idle := by
  decide +kernel
theorem agentWordOnAKeptPathMergesNothing :
    plan (queueOf [{ ownerKeptPushed with words := [.agentLand orchestrator ownerKeptMark] }]) =
      .idle := by decide +kernel
theorem approvalOfAnOlderCommitDoesNotReachNewContent :
    plan (queueOf [approvedThenNewContent]) = .idle := by decide +kernel
theorem approvalOfTheNewContentMerges :
    plan (queueOf [{ approvedThenNewContent with words := [.ownerLand ownerKeptMark,
      .ownerLand ⟨960, "fff", true⟩] }]) = .merge 153 "fff" := by decide +kernel
theorem approvalNamingAnUnknownCommitMergesNothing :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerLand ⟨900, "zzz", true⟩] }]) =
      .idle := by decide +kernel
theorem holdAfterTheApprovalMergesNothing :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark,
      .ownerHold 950] }]) = .idle := by decide +kernel
theorem laterOwnerCommentRetiresTheApproval :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark,
      .ownerSpoke 950] }]) = .idle := by decide +kernel
theorem approvalTypedAgainAfterSpeakingMerges :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerSpoke 950,
      .ownerLand ⟨960, "ar", true⟩] }]) = .merge 153 "ar" := by decide +kernel
def heldThenSpoke : Obs :=
  { agentOnMain with words := [.agentLand orchestrator agentMark, .ownerHold 900,
      .ownerSpoke 950] }
theorem laterOwnerCommentDoesNotLiftAHold :
    step orchestrator (queueOf [heldThenSpoke]) heldThenSpoke = .stop .held := by decide +kernel
theorem laterOwnerCommentLeavesAHeldPullRequestWithNoEntry : heldThenSpoke.entries = [] := by
  decide +kernel
theorem laterOwnerCommentDoesNotLetAHeldBranchBePushed :
    plan (queueOf [{ agentBehind with words := [.agentLand orchestrator agentMark, .ownerHold 900,
      .ownerSpoke 950] }]) = .idle := by decide +kernel
theorem laterOwnerCommentDoesNotReviveAnOlderApproval :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark,
      .ownerLand ⟨940, "zzz", true⟩, .ownerSpoke 950] }]) = .idle := by decide +kernel
theorem ownerCommentBeforeTheApprovalDoesNotRetireIt :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerSpoke 850,
      .ownerLand ownerKeptMark] }]) = .merge 153 "ar" := by decide +kernel
theorem laterOwnerCommentRetiresABareLandOffKeptPathsToo :
    plan (queueOf [{ offKeptOwnerLanded with words := [.ownerLand ⟨810, "bbb", false⟩,
      .ownerSpoke 950] }]) = .idle := by decide +kernel
theorem bareLandAfterAnApprovalStandsForNothing :
    plan (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark,
      .ownerLand ⟨950, "ar", false⟩] }]) = .idle := by decide +kernel
theorem holdThenOwnerCommentStaysHeldOnAKeptPath :
    step orchestrator
      (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerHold 950,
        .ownerSpoke 960] }])
      { ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerHold 950,
        .ownerSpoke 960] } = .stop .held := by decide +kernel
theorem laterOwnerCommentLeavesAnAgentLandingAlone :
    step orchestrator
      (queueOf [{ agentOnMain with words := [.agentLand orchestrator agentMark,
        .ownerSpoke 950] }])
      { agentOnMain with words := [.agentLand orchestrator agentMark, .ownerSpoke 950] } =
        .merge "bbb" := by decide +kernel
theorem missingSpecLabelOrUnansweredCommentMergesNothing :
    plan (queueOf [{ ownerKeptPushed with rest := false }]) = .idle := by decide +kernel
theorem draftForkOrStackMergesNothing :
    plan (queueOf [{ ownerKeptPushed with updatable := false }]) = .idle := by decide +kernel
theorem botReviewMissingMergesNothing :
    plan (queueOf [{ ownerKeptPushed with botAt := none }]) = .idle := by decide +kernel
theorem botReviewOfOtherContentMergesNothing :
    plan (queueOf [{ ownerKeptPushed with botAt := some "zzz" }]) = .idle := by decide +kernel
theorem aHeadWithoutAContentIdMergesNothing :
    plan (queueOf [{ ownerKeptPushed with ids := [] }]) = .idle := by decide +kernel
theorem redGateMergesNothing :
    plan (queueOf [{ ownerKeptPushed with gate := .failure }]) = .idle := by decide +kernel
theorem cancelledGateMergesNothing :
    plan (queueOf [{ ownerKeptPushed with gate := .cancelled }]) = .idle := by decide +kernel
theorem unenforcedProtectionMergesNothing :
    plan (queueOf [{ ownerKeptPushed with enforced := false }]) = .idle := by decide +kernel
theorem verdictFromTheAuthorsModelOnlyMergesNothing :
    plan (queueOf [approvedJudgedOnTheAuthorsModel]) = .idle := by decide +kernel
theorem verdictFromAnotherModelLetsTheRulePathMerge :
    plan (queueOf [{ approvedJudgedOnTheAuthorsModel with
      author := some ⟨grokBuilder, "grok"⟩ }]) = .merge 153 "ar" := by decide +kernel
theorem trustPathWithoutAnOpusPassMergesNothing :
    plan (queueOf [{ ownerKeptPushed with
      verdicts := [⟨851, "aaa", verifier, "sonnet", .pass⟩] }]) = .idle := by decide +kernel
theorem laterFailMergesNothing :
    plan (queueOf [{ ownerKeptPushed with
      verdicts := ownerKeptPushed.verdicts ++ [⟨990, "ar", verifier, "sonnet", .fail⟩] }]) =
      .idle := by decide +kernel
theorem oneMergeAtATimeTheLandingOnMainFirst :
    plan (queueOf [secondApproved, ownerKeptPushed]) = .merge 153 "ar" := by decide +kernel

theorem aBareLandOnAKeptPathIsUnnamed : bareKeptOnMain.word = .unnamed := by decide +kernel
theorem aBareLandOffTheKeptPathsStands : offKeptOwnerLanded.word = .stands := by decide +kernel
theorem anApprovalStands : ownerKeptPushed.word = .stands := by decide +kernel
theorem aLaterCommentIsSpoke :
    ({ ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerSpoke 950] } : Obs).word =
      .spoke := by decide +kernel
theorem anApprovalOfOlderContentIsStale : approvedThenNewContent.word = .stale := by decide +kernel
theorem aHoldIsHeld : ownerKeptHeld.word = .held := by decide +kernel
theorem noOwnerWordIsNone : agentBehind.word = .none := by decide +kernel


end Fixture

/-! ## No `sorry`, standard axioms only

`lake build` accepts a `sorry` with a warning, so the build checks it: it fails if any theorem this
file adds, a statement's proof, a lemma or a fixture, private ones included, depends on an axiom
other than the three standard ones, and `sorryAx` is one. It names every such theorem.
`gate/land-test.sh` plants `sorry`s and an axiom in a copy of this file and requires the check to
name each one. -/

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let mine := (← getEnv).constants.map₂.foldl (fun acc n c =>
    if c.isTheorem then acc.push n else acc) #[]
  unless mine.any (`MitosGate.Land.Fixture).isPrefixOf do throwError "no fixture theorem found"
  for n in [``pushOnlyNext, ``noEntryNoPush, ``oneLandingAtATime, ``pushKeepsCover,
      ``pushIsNotRepeated, ``mergeIsGated, ``plannedMergeIsGated, ``ownerEntryIsTheirLastWord,
      ``keptEntryIsTheOwners, ``onlyLandOrHoldChangesTheWord, ``wordStandsIsTheEntry,
      ``unenforcedLandsNothing, ``holdWins, ``agentKeepsOwnerWord, ``onlyMergersQueue,
      ``stuckDoesNotBlock, ``nextNeverWaits, ``nextIgnoresListingOrder, ``quietAfterRebase,
      ``unknownAuthorCoversNothing, ``standingFailOrHoldCoversNothing,
      ``coverIsAnotherJudgesWord, ``criticalCoverIsAnOpusPassOrWordingOnly,
      ``mem_queueOf, ``newestOwner_perm, ``toCarry_updaterForcePush] do
    unless mine.contains n do throwError "{n} is not a theorem of this file"
  let mut bad : Array MessageData := #[]
  for n in mine do
    for a in ← collectAxioms n do
      unless standard.contains a do
        bad := bad.push m!"{privateToUserName n} depends on the axiom {a}"
  unless bad.isEmpty do throwError MessageData.joinSep bad.toList "\n"

end MitosGate.Land
