import MitosGate.Lock
import MitosGate.LockFixture
import MitosGate.LockFixtureMeta
import MitosGate.LockFixtureModule

open Lean MitosGate

run_cmd do
  let priv (mod n : Name) : Name := mkPrivateNameCore mod n
  let errs ← IO.mkRef (#[] : Array String)
  let fail (msg : String) : Elab.Command.CommandElabM Unit :=
    errs.modify (·.push msg)
  let checkListed (env : Environment) (n : Name) (want : Bool) : Elab.Command.CommandElabM Unit := do
    if !env.contains n then
      fail s!"missing lock fixture {n}"
    else
      let got := Lock.nameListed env n
      if got != want then
        fail s!"nameListed {n} = {got}, expected {want}"

  let core ← Lock.importRoot `MitosGate.LockFixture
  let fx := `MitosGate.LockFixture
  let listed : List Name := [
    `MitosGate.LockFixture.match_foo,
    `MitosGate.LockFixture.proof_of_x,
    `MitosGate.LockFixture.proof_2,
    `MitosGate.LockFixture.proof_,
    `MitosGate.LockFixture.proof_2x,
    `MitosGate.LockFixture.early.eq_2,
    `MitosGate.LockFixture.early,
    `MitosGate.LockFixture.earlym.match_1.eq_1,
    `MitosGate.LockFixture.earlym,
    `MitosGate.LockFixture.nested,
    `MitosGate.LockFixture.equation,
    `MitosGate.LockFixture.equation.eq_of_id,
    `MitosGate.LockFixture.equation_true,
    `MitosGate.LockFixture.equation_def,
    `MitosGate.LockFixture.earlym.match_1.eq_of_id,
    `MitosGate.LockFixture.earlym.match_1.eq_def,
    `MitosGate.LockFixture.earlym.match_1.eq_unfold,
    `MitosGate.LockFixture.congrm.match_1.congr_eq_1,
    `MitosGate.LockFixture.congrm,
    `MitosGate.LockFixture.congrm_step,
    `MitosGate.LockFixture.Plain.rec,
    `MitosGate.LockFixture.Plain.sizeOf_spec,
    `MitosGate.LockFixture.Plain.noConfusionType,
    `MitosGate.LockFixture.Plain.ctorIdx,
    `MitosGate.LockFixture.Plain.ofNat_ctorIdx,
    `MitosGate.LockFixture.Plain.toCtorIdx,
    `MitosGate.LockFixture.Plain.ofNat,
    `MitosGate.LockFixture.Plain.ctorElim,
    `MitosGate.LockFixture.Plain.ctorElimType,
    `MitosGate.LockFixture.Plain.inj,
    `MitosGate.LockFixture.Plain.injEq,
    `MitosGate.LockFixture.Plain.repr,
    `MitosGate.LockFixture.Plain.decEq,
    `MitosGate.LockFixture.Plain.noConfusion,
    `MitosGate.LockFixture.Plain.casesOn,
    `MitosGate.LockFixture.Plain.recOn,
    `MitosGate.LockFixture.Plain.below,
    `MitosGate.LockFixture.Plain.brecOn,
    `MitosGate.LockFixture.Plain.congr_eq_1,
    `MitosGate.LockFixture.Plain.induct,
    `MitosGate.LockFixture.Plain.fun_cases,
    `MitosGate.LockFixture.Plain.eq_1,
    `MitosGate.LockFixture.Plain.match_1,
    `MitosGate.LockFixture.HiddenAx.inj,
    priv fx `MitosGate.LockFixture.privAx,
    `MitosGate.LockFixture._internalAx,
    `MitosGate.LockFixture.Color,
    `MitosGate.LockFixture.Color.red,
    `MitosGate.LockFixture.Color.green,
    `MitosGate.LockFixture.instDecidableEqColor,
    `MitosGate.LockFixture.instReprColor,
    `MitosGate.LockFixture.Tag,
    `MitosGate.LockFixture.Tag.a,
    `MitosGate.LockFixture.Tag.b,
    `MitosGate.LockFixture.Tag.c,
    `MitosGate.LockFixture.instDecidableEqTag,
    `MitosGate.LockFixture.Rel,
    `MitosGate.LockFixture.Rel.step,
    `MitosGate.LockFixture.Rel.trans,
    `MitosGate.LockFixture.Box,
    `MitosGate.LockFixture.Box.mk,
    `MitosGate.LockFixture.Box.val,
    `MitosGate.LockFixture.mutEven,
    `MitosGate.LockFixture.mutOdd,
    `MitosGate.LockFixture.mutEven_zero,
    `MitosGate.LockFixture.mutOdd_zero,
    `MitosGate.LockFixture.wfDown,
    `MitosGate.LockFixture.wfDown_zero,
    `MitosGate.LockFixture.withWhere,
    `MitosGate.LockFixture.withWhere.go,
    `MitosGate.LockFixture.withWhere_go_zero,
    `MitosGate.LockFixture.partLoop,
    `MitosGate.LockFixture.usesPrivPart
  ]
  for n in listed do
    checkListed core.env n true

  let unlisted : List Name := [
    `MitosGate.LockFixture.equation.eq_1,
    `MitosGate.LockFixture.equation.eq_def,
    `MitosGate.LockFixture.earlym.match_1,
    `MitosGate.LockFixture.nested.match_1_1,
    priv fx `MitosGate.LockFixture.privHelper,
    `MitosGate.LockFixture.Color.rec,
    `MitosGate.LockFixture.Color.casesOn,
    `MitosGate.LockFixture.Color.recOn,
    `MitosGate.LockFixture.Color.noConfusion,
    `MitosGate.LockFixture.Color.noConfusionType,
    `MitosGate.LockFixture.Color.ctorIdx,
    `MitosGate.LockFixture.Color.green.inj,
    `MitosGate.LockFixture.Color.green.injEq,
    `MitosGate.LockFixture.Color.green.sizeOf_spec,
    `MitosGate.LockFixture.instDecidableEqColor.decEq,
    `MitosGate.LockFixture.instReprColor.repr,
    `MitosGate.LockFixture.Tag.ctorIdx,
    `MitosGate.LockFixture.Tag.ofNat,
    `MitosGate.LockFixture.Tag.ofNat_ctorIdx,
    `MitosGate.LockFixture.Tag.ctorElim,
    `MitosGate.LockFixture.Tag.ctorElimType,
    `MitosGate.LockFixture.Rel.below,
    `MitosGate.LockFixture.Rel.below.step,
    `MitosGate.LockFixture.Rel.below.trans,
    `MitosGate.LockFixture.Rel.brecOn,
    `MitosGate.LockFixture.Box.rec,
    `MitosGate.LockFixture.Box.casesOn,
    `MitosGate.LockFixture.Box.noConfusion,
    `MitosGate.LockFixture.Box.mk.inj,
    `MitosGate.LockFixture.Box.mk.injEq,
    `MitosGate.LockFixture.Box.mk.sizeOf_spec,
    `MitosGate.LockFixture.mutEven.eq_1,
    `MitosGate.LockFixture.mutOdd.eq_1,
    `MitosGate.LockFixture.wfDown.eq_1,
    `MitosGate.LockFixture.withWhere.go.eq_1,
    `MitosGate.LockFixture.partLoop._unsafe_rec,
    priv fx `MitosGate.LockFixture.privPartLoop
  ]
  for n in unlisted do
    checkListed core.env n false

  let unlistedWhenPresent : List Name := [
    `MitosGate.LockFixture.congrm.match_1.congr_eq_2,
    `MitosGate.LockFixture.congrm.match_1.congr_eq_3,
    `MitosGate.LockFixture.Tag.toCtorIdx,
    `MitosGate.LockFixture.Tag.ctorIdx._impl,
    `MitosGate.LockFixture.Color.ctorIdx._impl
  ]
  for n in unlistedWhenPresent do
    if core.env.contains n then
      checkListed core.env n false

  let instName := `MitosGate.LockFixture.instDecidableEqColor
  let helperName := `MitosGate.LockFixture.instDecidableEqColor.decEq
  match declRangeExt.find? core.env instName, declRangeExt.find? core.env helperName with
  | some ri, some rh =>
    unless ri.range == rh.range && ri.selectionRange == rh.selectionRange do
      fail s!"expected deriving helper {helperName} to share span with {instName}"
    unless core.env.getModuleIdxFor? instName == core.env.getModuleIdxFor? helperName do
      fail s!"expected deriving helper {helperName} in same module as {instName}"
  | _, _ =>
    fail s!"expected declaration ranges on {instName} and {helperName}"

  let privPart := priv fx `MitosGate.LockFixture.privPartLoop
  match core.env.find? privPart with
  | none => fail s!"missing {privPart}"
  | some privPartCi =>
    unless privPartCi matches .opaqueInfo _ && Lock.blockedMeaning privPartCi do
      fail s!"expected derived partial opaque {privPart} to be blocked"
    let origins : NameMap Lock.Origin := ({} : NameMap Lock.Origin).insert privPart .spec
    match Lock.refOf core.env origins (Lock.nameListed core.env) (fun _ => false) {} privPart with
    | .error _ => pure ()
    | .ok _ => fail s!"expected unlisted derived partial opaque {privPart} to be refused"

  let metaCore ← Lock.importRoot `MitosGate.LockFixtureMeta
  let metaAx := `MitosGate.LockFixtureMeta.Foo.inj
  let metaThm := `MitosGate.LockFixtureMeta.claim
  let crossMod := `Nat.crossModSameSpan
  unless (declRangeExt.find? metaCore.env metaAx).isNone do
    fail s!"expected {metaAx} to carry no declaration range"
  unless (declRangeExt.find? metaCore.env metaThm).isNone do
    fail s!"expected {metaThm} to carry no declaration range"
  checkListed metaCore.env metaAx true
  checkListed metaCore.env metaThm false
  match declRangeExt.find? metaCore.env `Nat, declRangeExt.find? metaCore.env crossMod with
  | some rn, some rc =>
    unless rn.range == rc.range && rn.selectionRange == rc.selectionRange do
      fail s!"expected {crossMod} to share span with Nat"
    unless metaCore.env.getModuleIdxFor? `Nat != metaCore.env.getModuleIdxFor? crossMod do
      fail s!"expected {crossMod} in a different module from Nat"
  | _, _ =>
    fail s!"expected declaration ranges on Nat and {crossMod}"
  checkListed metaCore.env crossMod true

  let modCore ← Lock.importRoot `MitosGate.LockFixtureModule
  let fm := `MitosGate.LockFixtureModule
  unless (declRangeExt.find? modCore.env `MitosGate.LockFixtureModule.pubDef).isSome do
    fail "expected module-system declaration range on pubDef"
  for n in [
    `MitosGate.LockFixtureModule.pubDef,
    `MitosGate.LockFixtureModule.pubHiddenDef,
    `MitosGate.LockFixtureModule.pubThm,
    `MitosGate.LockFixtureModule.ModColor,
    `MitosGate.LockFixtureModule.ModColor.red,
    `MitosGate.LockFixtureModule.ModColor.blue,
    `MitosGate.LockFixtureModule.instDecidableEqModColor,
    `MitosGate.LockFixtureModule.instReprModColor,
    `MitosGate.LockFixtureModule.pubAx,
    priv fm `MitosGate.LockFixtureModule.privModAx
  ] do
    checkListed modCore.env n true
  for n in [
    `MitosGate.LockFixtureModule.ModColor.rec,
    `MitosGate.LockFixtureModule.ModColor.ctorIdx,
    `MitosGate.LockFixtureModule.ModColor.ofNat,
    `MitosGate.LockFixtureModule.ModColor.ofNat_ctorIdx,
    `MitosGate.LockFixtureModule.instReprModColor.repr,
    priv fm `MitosGate.LockFixtureModule.privModDef
  ] do
    checkListed modCore.env n false

  let failed ← errs.get
  unless failed.isEmpty do
    throwError "{failed.size} lock case violation(s):\n{"\n".intercalate failed.toList}"
