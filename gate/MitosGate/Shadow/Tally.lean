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

end MitosGate.Shadow
