import MitosGate.Shadow.Tally
import MitosGate.Shadow.Spread

namespace MitosGate.Shadow

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.fold (fun acc n c =>
    if (`MitosGate.Shadow.Fixture).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``readyIsOneWordFromLanding, ``theWordIsOnlyAssumedWhenReady,
      ``lacksNothingIffEligible, ``pairedRecordPrecedesTheMerge, ``agreesMeansTheMergedContent,
      ``tallyCountsEveryMergeOnce, ``peakBoundsEveryWindow] ++ fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Shadow
