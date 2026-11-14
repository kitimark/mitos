import MitosGate.Land

namespace MitosGate.Shadow

open Land

inductive Clause
  | updatable | enforced | covered | reviewed | rest
  deriving DecidableEq

def lacks (o : Obs) : List Clause :=
  [(Clause.updatable, o.updatable), (.enforced, o.enforced), (.covered, o.covered),
   (.reviewed, o.reviewed), (.rest, o.rest)].filterMap fun (c, b) => if b then none else some c

def LacksNothingIffEligible : Prop :=
  ∀ o : Obs, lacks o = [] ↔ o.eligibleBeforeRebase = true

theorem lacksNothingIffEligible : LacksNothingIffEligible := by
  intro o
  simp only [lacks, Obs.eligibleBeforeRebase]
  cases o.updatable <;> cases o.enforced <;> cases o.covered <;> cases o.reviewed <;>
    cases o.rest <;> simp [List.filterMap]

end MitosGate.Shadow
