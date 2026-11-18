import MitosGate.Snapshot.Obs
import MitosGate.Snapshot.Fixtures
import MitosGate.Provenance.Fixtures

namespace MitosGate.Snapshot

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.fold (fun acc n c =>
    if ((`MitosGate.Snapshot.Fixture).isPrefixOf n ||
        (`MitosGate.Provenance.Fixture).isPrefixOf n) && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``failedReadHolds, ``enforcedNeedsProtection, ``updatableNeedsTheGuard,
      ``unreadFilesAreKept, ``onlyTheOwnerQueues, ``greenIsTheNewestGateRun,
      ``pushesAreTheActivity, ``verdictsFromTheSource, ``restNeedsSourceGuard,
      ``Provenance.projectionPreservesEvents, ``Provenance.admittedRequiredHasEffort, ``Provenance.eligibleNeedsAdmission, ``Provenance.projectionEligibility,
      ``Provenance.render_isDecoded, ``Provenance.absentAuthorOf,
      ``Provenance.unknownAdmitted, ``Provenance.unknownRequiredHasEffort,
      ``ModelIdentity.reportedDifferent_eq, ``ModelIdentity.absentDifferentNeedsKnown,
      ``ModelIdentity.canonicalOutsideNotClaude, ``Land.reportedCovered_iff, ``obs_projection,
      ``restNeedsAnswersAndTheLabel, ``keptMergeIsTheOwnersTypedApproval] ++ fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Snapshot
