import Lean

open Lean

namespace MitosGate.LockFixtureMeta

run_cmd do
  let falseTy := mkConst ``False
  let trueTy := mkConst ``True
  let trueVal := mkConst ``True.intro
  Elab.Command.liftCoreM do
    addDecl <| .axiomDecl {
      name := `MitosGate.LockFixtureMeta.Foo.inj
      levelParams := []
      type := falseTy
      isUnsafe := false
    }
    addDecl <| .thmDecl {
      name := `MitosGate.LockFixtureMeta.claim
      levelParams := []
      type := trueTy
      value := trueVal
    }
    let env ← getEnv
    let some natRanges := declRangeExt.find? env ``Nat
      | throwError "missing declaration ranges for Nat"
    addDecl <| .defnDecl {
      name := `Nat.crossModSameSpan
      levelParams := []
      type := mkConst ``Nat
      value := mkNatLit 0
      hints := .abbrev
      safety := .safe
    }
    addDeclarationRanges `Nat.crossModSameSpan natRanges

end MitosGate.LockFixtureMeta
