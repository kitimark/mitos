module

public import Init

namespace MitosGate.LockFixtureModule

@[expose] public def pubDef (n : Nat) : Nat := n + 1

public def pubHiddenDef (n : Nat) : Nat := n + 2

public theorem pubThm : pubDef 0 = 1 := rfl

public inductive ModColor where
  | red
  | blue
  deriving DecidableEq, Repr

public axiom pubAx : False

private def privModDef : Nat := 7

private axiom privModAx : False

end MitosGate.LockFixtureModule
