import MitosGate.Shadow.Finding

namespace MitosGate.Shadow

structure Tally where
  agrees : Nat := 0
  waits : Nat := 0
  disagrees : Nat := 0
  otherTree : Nat := 0
  blind : Nat := 0
  assumed : Nat := 0
  noAuthor : Nat := 0
  updaterPushes : Nat := 0

def Tally.add (t : Tally) (s : Seat) : Tally :=
  let t := match finding s with
    | .agrees => { t with agrees := t.agrees + 1 }
    | .waits => { t with waits := t.waits + 1 }
    | .disagrees _ => { t with disagrees := t.disagrees + 1 }
    | .otherTree => { t with otherTree := t.otherTree + 1 }
    | .blind => { t with blind := t.blind + 1 }
  match s with
  | .sat x =>
    { t with updaterPushes := t.updaterPushes + x.updaterPushes,
             assumed := t.assumed + (match x.reading with | .oneWordAway _ => 1 | _ => 0),
             noAuthor := t.noAuthor + (if x.authorKnown then 0 else 1) }
  | _ => t

def tally (ms : List Merge) (rs : List Record) : Tally :=
  ms.foldl (fun t m => t.add (seat m rs)) ({} : Tally)

def TallyCountsEveryMergeOnce : Prop :=
  ∀ (ms : List Merge) (rs : List Record),
    let t := tally ms rs
    t.agrees + t.waits + t.disagrees + t.otherTree + t.blind = ms.length

def Seat.assumed : Seat → Bool
  | .sat s => (s.reading matches .oneWordAway _)
  | _ => false

def TheAssumedCountIsTheMergesOneWordAway : Prop :=
  ∀ (ms : List Merge) (rs : List Record),
    (tally ms rs).assumed = ms.countP fun m => (seat m rs).assumed

def Tally.total (t : Tally) : Nat := t.agrees + t.waits + t.disagrees + t.otherTree + t.blind

theorem add_total (t : Tally) (s : Seat) : (t.add s).total = t.total + 1 := by
  unfold Tally.add Tally.total
  cases s <;> (dsimp only; split <;> simp <;> omega)

theorem foldl_total (rs : List Record) :
    ∀ (ms : List Merge) (t : Tally),
      (ms.foldl (fun t m => t.add (seat m rs)) t).total = t.total + ms.length
  | [], t => by simp
  | m :: ms, t => by
    simp only [List.foldl_cons, List.length_cons]
    rw [foldl_total rs ms, add_total]; omega

theorem tallyCountsEveryMergeOnce : TallyCountsEveryMergeOnce := by
  intro ms rs
  have := foldl_total rs ms {}
  simpa [tally, Tally.total] using this

theorem add_assumed (t : Tally) (s : Seat) :
    (t.add s).assumed = t.assumed + if s.assumed then 1 else 0 := by
  unfold Tally.add
  cases s with
  | sat x =>
    obtain ⟨_, _, reading, _, _, _, _⟩ := x
    cases reading <;> (simp only [Seat.assumed]; split <;> simp)
  | _ => dsimp only [Seat.assumed]; split <;> simp

theorem foldl_assumed (rs : List Record) :
    ∀ (ms : List Merge) (t : Tally),
      (ms.foldl (fun t m => t.add (seat m rs)) t).assumed =
        t.assumed + ms.countP fun m => (seat m rs).assumed
  | [], t => by simp
  | m :: ms, t => by
    simp only [List.foldl_cons, List.countP_cons]
    rw [foldl_assumed rs ms, add_assumed]; omega

theorem theAssumedCountIsTheMergesOneWordAway : TheAssumedCountIsTheMergesOneWordAway := by
  intro ms rs
  simpa [tally] using foldl_assumed rs ms {}

end MitosGate.Shadow
