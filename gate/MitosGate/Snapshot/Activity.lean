import MitosGate.Snapshot.Types

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

def stampOf (q : Carry.Push) : Option Stamp := Speech.stamp? q.time.toList

def descending : List Carry.Push → Bool
  | p :: q :: rest =>
    (match stampOf p, stampOf q with
      | some a, some b => decide (b ≤ a)
      | _, _ => false) && descending (q :: rest)
  | [p] => (stampOf p).isSome
  | [] => true

def pushesOk (head : Sha) (ps : List Carry.Push) : Bool :=
  ps.all (fun q => isSha q.before.toList && isSha q.after.toList) && descending ps &&
    Carry.tip head ps

def activity (p : Pull) (r : Reads) : Option (List Carry.Push) := r.activity.filter (pushesOk p.head)

def known (ps : List Carry.Push) : List Sha := ps.flatMap fun q => [q.before, q.after]

def toLand (q : Carry.Push) : Push := ⟨q.updaterForcePush, q.before, q.after⟩

end MitosGate.Snapshot
