import MitosGate.Land

namespace MitosGate.Shadow

open Land

def observer : Teammate := ⟨"shadow", "observer"⟩

def fresh (os : List Obs) : Nat := (os.flatMap fun o => o.words.map Word.said).foldr max 0 + 1

def withWord (said : Nat) (o : Obs) : Obs :=
  { o with words := o.words ++ [.ownerLand ⟨said, o.head⟩] }

inductive Reading
  | asRead (step : Step)
  | oneWordAway (after : Step)
  deriving DecidableEq

def Reading.step : Reading → Step
  | .asRead s | .oneWordAway s => s

def reading (os : List Obs) (o : Obs) : Reading :=
  match step observer (queueOf os) o with
  | .stop .noEntry =>
    let o' := withWord (fresh os) o
    .oneWordAway (step observer (queueOf (os.map fun x => if x.pr == o.pr then o' else x)) o')
  | s => .asRead s

def ReadyIsOneWordFromLanding : Prop :=
  ∀ (me : Teammate) (q : Queue) (o : Obs) (said : Nat),
    step me q o = .stop .noEntry → (∀ w ∈ o.words, w.said < said) →
    landable (⟨o.pr, ⟨said, o.head⟩, .owner⟩, withWord said o) = true

def TheWordIsOnlyAssumedWhenReady : Prop :=
  ∀ (os : List Obs) (o : Obs),
    (∃ s, reading os o = .oneWordAway s) ↔ step observer (queueOf os) o = .stop .noEntry

theorem walk_self (v : String) (ps : List Carry.Push) : Carry.walk v v ps = true := by
  cases ps <;> simp [Carry.walk]

theorem newestOwner_append_land (m : Mark) :
    ∀ ws : List Word, (∀ w ∈ ws, w.said < m.said) →
      newestOwner (ws ++ [.ownerLand m]) = some (.ownerLand m)
  | [], _ => by simp [newestOwner, Word.byOwner]
  | w :: ws, h => by
    have ih := newestOwner_append_land m ws (fun x hx => h x (List.mem_cons_of_mem _ hx))
    have hw : w.said < m.said := h w (List.mem_cons_self ..)
    simp only [List.cons_append, newestOwner, ih]
    have : ¬ ((Word.ownerLand m).said < w.said) := by
      show ¬ (m.said < w.said)
      omega
    simp [this]

theorem covered_head_id {o : Obs} (h : o.covered = true) : (o.id? o.head).isSome = true := by
  have hc : o.Covered := of_decide_eq_true h
  unfold Obs.Covered at hc
  split at hc
  · exact hc.elim
  · have key : ∀ v, o.stands v → (o.id? o.head).isSome = true := by
      intro v hv
      have := hv.1
      simp only [Obs.carries, Bool.and_eq_true] at this
      obtain ⟨⟨_, h1⟩, h2⟩ := this
      have : o.id? v.head = o.id? o.head := by simpa using h2
      rw [← this]; exact h1
    rcases hc.2 with ⟨v, _, hv, _⟩ | ⟨⟨v, _, hv, _⟩, _⟩ <;> exact key v hv

theorem readyIsOneWordFromLanding : ReadyIsOneWordFromLanding := by
  intro me q o said h hs
  have hel : o.eligibleBeforeRebase = true ∧ o.stuck? = none := by
    unfold step at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h
        · cases h
        · rename_i _ _ he
          split at h
          · cases h
          · rename_i hst
            refine ⟨by simpa using he, hst⟩
  obtain ⟨he, hst⟩ := hel
  have hcov : o.covered = true := by
    simp only [Obs.eligibleBeforeRebase, Bool.and_eq_true] at he
    exact he.1.1.2
  have hid := covered_head_id hcov
  have hn := newestOwner_append_land ⟨said, o.head⟩ o.words hs
  simp only [landable, Entry.valid, Bool.and_eq_true]
  refine ⟨⟨⟨?_, he⟩, ?_⟩, ?_⟩
  · simp only [Obs.entries, withWord, hn]
    simp
  · show (Carry.walk o.head o.head (o.pushes.map Push.toCarry) && (o.id? o.head).isSome &&
      o.id? o.head == o.id? o.head) = true
    simp [walk_self, hid]
  · show (o.stuck?).isNone = true
    simp [hst]

theorem theWordIsOnlyAssumedWhenReady : TheWordIsOnlyAssumedWhenReady := by
  intro os o
  unfold reading
  split
  · rename_i h; simp [h]
  · rename_i h
    constructor
    · rintro ⟨s, hs⟩; cases hs
    · intro h'; exact absurd h' (h)

namespace Fixture

open Land.Fixture

def unsaid : Obs := { agentBehind with words := [] }
def unsaidOnMain : Obs := { agentOnMain with words := [] }

theorem readyBehindIsOneWordFromThePush :
    reading [unsaid] unsaid = .oneWordAway (.awaitPush "bbb") := by decide +kernel
theorem readyOnMainGreenIsOneWordFromPresent :
    reading [unsaidOnMain] unsaidOnMain = .oneWordAway (.present "bbb") := by decide +kernel
theorem aHoldIsReadAsItIs :
    reading [ownerKeptHeld] ownerKeptHeld = .asRead (.stop .held) := by decide +kernel
theorem aTypedWordIsReadAsItIs :
    reading [ownerKeptPushed] ownerKeptPushed = .asRead (.present "ar") := by decide +kernel
theorem newContentIsNotAssumed :
    reading [{ ownerKeptNewContent with words := [] }] { ownerKeptNewContent with words := [] } =
      .asRead (.stop .notEligible) := by decide +kernel
theorem anotherWordAheadMakesTheAssumedWordWait :
    reading [ownerKeptPushed, unsaid] unsaid = .oneWordAway (.wait 153) := by decide +kernel

end Fixture

end MitosGate.Shadow
