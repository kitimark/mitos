# Truthful author and verifier provenance

phase: 0
goal: Both readers record actual identity separately from accepted verification and refuse unknown provenance.
statement: none (tooling task); native source-admission and compatibility properties
touches: gate/MitosGate/{ModelIdentity,Provenance,ProvenanceCli,Snapshot,SnapshotCli,Land,Main} and focused tests; hook and publisher guidance
must_not_touch: core/, statements.lock, models.lock, workflows, dashboard, assignments, labels, PR469
checks: native build, imports, lock, land/snapshot/record/hook controls, frozen native replay, core checks and comparator
budget: 40 iterations · 4h wall · tokens unmetered
escalation: proof automation → root architecture judgment → independent verifier

Part of #327. The owner authorized this repair in #191; it is separate from #336 and the approved prospective policy in #472. Candidate A is selected, with the independent architecture judgment's effort, two-witness and compatibility corrections and Candidate B's bounded, duplicate-refusing source boundary.

## Contract

The existing Owner dashboard remains a manually published trusted-root source. One versioned machine section records actual author and verifier facts before consumers read them. Its schema and public evidence links do not authenticate a writer or a model invocation, and cannot prove that the publisher retained every adverse event. Writer authentication remains broader #327 work; mutable source loss remains #117. This change adds no credentials, privileges, owner approval step or publisher role.

The section is delimited by `<!-- mitos-provenance:v1 -->` and `<!-- /mitos-provenance:v1 -->`, with one `json` fence containing one canonical, single-line JSON object. The native encoder mechanically renders the same bytes the decoder accepts. Bounds, exact keys and canonical parse/encode equality refuse malformed input, duplicate keys or sections, duplicate PRs and ambiguous events. The repository is bound explicitly. Human prose is presentation and never a favorable fallback.

Identity and admission are distinct. Store the exact reported provider, stable giver and actual model text. An unavailable actual model stays unknown; a requested alias never supplies it. Canonical v1 keeps provider namespace `claude` and its existing shape. Explicit conservative model keys prevent legacy/full-ID aliases from inventing different models, while preserving legacy `claude`/`opus`/`sonnet` records. Accepted positive verification is Claude-only. A known truthful OpenAI author can receive accepted independent Claude verification; unknown authors cannot.

Coverage preserves every standing FAIL/HOLD, newest-per-giver ordering, full-head binding and validated updater-only content-preserving carry. General coverage needs an accepted PASS from a distinct giver and a different model key. Critical coverage additionally needs an accepted Opus PASS from a distinct giver; its family need not differ from an Opus author's family. One qualifying independent Opus verdict can discharge both obligations for a known GPT author. Existing wording-only behavior remains bounded by its current cut line.

Actual effort is source admission, outside canonical v1. The common source admission derives the Opus requirement from actual critical files or the existing `spec-approved` label, preserving the hook’s stricter label guard without changing canonical paths. Low or unknown effort cannot discharge the critical Opus requirement. An optional low-effort supplement does not veto sufficient evidence. Factual PASS and raw source facts remain unchanged; an admission failure gates eligibility without manufacturing HOLD, effort or owner speech. `Land.Covered` does not prove effort.

Snapshot and the session hook use one native decoder and admission policy. The hook uses the existing main-built tool with the already-read full main SHA, `MAIN_TOOL_READY_WAIT=0`, and the shared lock held through bounded calls. It neither fetches nor builds or ensures a tool within its 15-second budget. Missing, stale, old-command, incomplete or timed-out inputs explicitly hold. The final merge-ready branch explicitly requires the common eligible result and retains ordinary guards. Snapshot adds the shared source guard to `rest`; canonical Land supplies `Covered` once. Hook admission is `Covered && sourceGuard`. The native `projectionEligibility` theorem proves the same final eligibility while avoiding duplicate full coverage evaluation in snapshot fixtures; the guard itself is not a claim that standing adverse verdicts are absent.

## Hook CLI contract

`mitos-gate provenance candidates <dir> <repo> <owner>` reads the hook's existing flat `dash.json` issue-list and flat `open.json` pull-list routes. Exactly one open, owner-created Owner dashboard must exist. It validates the same structured source used by snapshot, and emits a JSON object keyed by decimal PR number. Each value has full `head`, `candidate`, `eligible` and fixed `reason` fields. `eligible` is always false in this preliminary mode; `candidate` means a source entry with verdict events needs final reads, including adverse events. It grants no authority.

`mitos-gate provenance hook <dir> <repo> <owner> <main>` consumes those reads plus `files-<n>.json` (the existing bounded flat files route) and `activity-<n>.json` (`--paginate --slurp` of the existing PR activity route) for each candidate. It emits the same shape. `eligible:true` means the shared native provenance projection has known, carried author identity, standing coverage and sufficient critical effort. Other hook guards remain separate. Missing files/activity, malformed route data, missing local git objects, or missing content ids produce `eligible:false` with a fixed reason; this command never fetches or builds. A malformed global source/output contract exits nonzero with no favorable output. The hook must require `eligible:true` explicitly and must not interpret source prose or model strings itself.

## Scope and evidence

Only the authorized provenance/model modules, snapshot boundary, necessary Land/CLI wiring, focused tests, hook, minimal publisher guidance and this task/run log change. No core, lock, workflow, dashboard, assignment, label or #469 permission change. Historical records and reports remain immutable.

Validate meaningful pure consequences and raw → snapshot → canonical record round trips, exact identities and unknowns, aliases, provider impostors, the two critical witnesses, effort, adverse standing events, carry and missing-tool controls. Replay every one of the 450 frozen records against the frozen main executable and final executable, reporting all decision or drift deltas. Run affected local checks, report sandbox limits honestly, batch known fixes into one push, open the PR through `open-pr.sh`, and carry CI and review feedback. No merge. Independent Opus review remains required externally; this implementation uses the truthful inherited GPT model, whose exact routed ID is unavailable.

The bulk typed Snapshot compatibility helper retains its original canonical `sonnet`/`opus` model spellings. Dedicated provenance fixtures and raw CLI tests exercise full IDs and the strict family grammar. A first bulk build using full IDs took415 seconds; restoring the legacy helper took485 seconds and showed no speedup. The source guard/final coverage split is measured separately, without removing any existing control.

## Design and synthesis

The root selected Candidate A's structured dashboard source and completed shared native consumer migration. Candidate B supplied strict bounds, duplicate/ambiguous-position refusal and explicit compatibility accounting: exact reported text is stored separately from the model-family comparison key, and every frozen record is replayed. This is the root's implementation synthesis under the authorized repair, not a new owner policy decision.

| Module or caller | Owned responsibility |
|---|---|
| `gate/MitosGate/ModelIdentity.lean` | Pure model keys, conservative Claude family grammar, provider admission and cross-system alias comparison. |
| `gate/MitosGate/Provenance.lean` | Actual identity/event facts, carried author projection, shared file/label Opus requirement, source guard, full admission and eligibility/event-preservation proofs. |
| `gate/MitosGate/Provenance/Decode.lean` | The sole bounded source grammar, canonical block encoder, strict fields and duplicate/refusal checks. |
| `gate/MitosGate/Provenance/Fixtures.lean` | Focused full-ID, unknown, effort, two-witness, wording-only and label controls, audited through `Snapshot.lean`. |
| `gate/MitosGate/Snapshot/{Types,Fields,Obs}.lean` and `SnapshotCli.lean` | Bind existing raw REST reads to source facts, obtain author/verdict content ids, preserve ordinary guards and produce canonical v1. `Cell.lean` is retired after caller migration; the existing table remains a presentation/read-completeness check. |
| `gate/MitosGate/Land.lean` | Final accepted-Claude/general-model and independent Opus witnesses, standing negatives and legacy compatibility. `Shadow/Reading.lean` changes only the proof tuple matching the strengthened proposition. |
| `gate/MitosGate/ProvenanceCli.lean` and `gate/Main.lean` | Thin publication/candidates/hook adapters over the same decoder and policy; hook content-id reads are local only. |
| `.claude/hooks/pr-state.sh` and its test | Delegated hook adapter ownership: main-tool readiness/lock/bounds, mechanical result validation and explicit final eligibility, retaining ordinary guards. |
| `gate/snapshot-test.sh` and `gate/provenance-hook-test.sh` | Native source→snapshot→record/hook integration and one raw, unmodified hook-suite invocation through CI's existing gate-test loop. |

The native policy owner owns the native modules, integration tests and publication guide; the hook adapter owner owns its two hook files. The root owns synthesis and review of the exact final head. Neither implementation role publishes dashboard facts, assigns the owner, changes labels or merges this repair.

A caller generates compact sorted payload JSON, runs `mitos-gate provenance render <owner/repo> <payload.json>`, and publishes the returned block only after checking actual source evidence. `mitos-gate snapshot <dir>` consumes the collector's existing raw dashboard response and emits the unchanged v1 shape. The hook first calls `provenance candidates <dir> <repo> <owner>`, obtains bounded final reads, then calls `provenance hook <dir> <repo> <owner> <main>` under the retained main-tool lock. Only the final common eligible result can join its ordinary merge guards. The renderer validates its emitted block through the exact source decoder, so publication and consumption share size and grammar limits as well as the encoder.

The staged global hook hold was rejected because it leaves the second consumer migration unfinished; this implementation holds temporarily on unavailable or incomplete inputs. An owner-merged append-only ledger was rejected for this minimum repair because each fact update would require another owner merge, move main and trigger rebases, while still not authenticating a model invocation. Free-text identity fallback was rejected because it manufactures providers/givers from model words and restores two competing grammars. Writer/runtime authentication and mutable publication loss remain the explicit broader deferrals in #327 and #117.

## Verification checkpoint

The native build completes all176 jobs with standard-kernel proofs and axiom audits. Snapshot/raw native-hook/actual record tests pass148 controls; Land68, Shadow62 and land-decide16 pass. Imports has zero violations, the207-declaration statement lock is unchanged, and the run log validates. All450 frozen version-1 records reproduce both the frozen native decisions and their recorded decisions; every input hash matches and the entire shadow report is byte-identical. Historical inputs/reports are unchanged.

The hook adapter passes681 deterministic assertions with an external host-metadata shim. The unmodified local-host run passes641 and fails39 existing ownership/freshness controls because `/` and `/tmp` belong to uid65534; one conditional assertion cannot run there. CI invokes the raw, unshimmed suite once. Local core check and paranoid comparator stop during nested bubblewrap namespace setup on this host's read-only filesystem; CI must supply those checks. No local pass or Opus review is claimed for them.

## Retired parser compatibility obligations

The first published review required restoration of every old parser assertion. `Snapshot/LegacyFixtures.lean` imports the existing fixtures, keeps all 26 original public `Fixture` theorem names and identical `v`/`a` input-output semantics, and confines parser/helper implementations to private compatibility scope. The three structural Cell proofs, the old cell-observation relation and six changed old snapshot-case expressions remain kernel-checked compatibility obligations. The active source controls remain unchanged.

This module is absent from normal Snapshot/Obs/CLI/hook imports and is not linked into the gate executable. `gate/provenance-legacy-test.sh` explicitly builds it in the existing CI test loop and checks all 36 named obligations against the standard axiom set. Compatibility proofs describe retired behavior; they supply no current author, provider, verdict or favorable prose fallback. `verdictsFromTheSource` remains the live observation obligation.

Names below are relative to `MitosGate.Snapshot`. The original `PassNamesNoFail` and `VerdictsFromTheCell` property bodies survive in private `Fixture.Compatibility` scope with their corresponding proofs.

| Old assertion | Restored assertion |
|---|---|
| `Fixture.carriedPassOfOneJudge` | `Fixture.carriedPassOfOneJudge` |
| `Fixture.twoJudges` | `Fixture.twoJudges` |
| `Fixture.failOfOneJudge` | `Fixture.failOfOneJudge` |
| `Fixture.wordingOnlyIsTheRoots` | `Fixture.wordingOnlyIsTheRoots` |
| `Fixture.noVerdictSaysNothing` | `Fixture.noVerdictSaysNothing` |
| `Fixture.passThenFailSaysNothing` | `Fixture.passThenFailSaysNothing` |
| `Fixture.judgelessPassSaysNothing` | `Fixture.judgelessPassSaysNothing` |
| `Fixture.judgesInAParenthesis` | `Fixture.judgesInAParenthesis` |
| `Fixture.judgesInBothPlacesSayNothing` | `Fixture.judgesInBothPlacesSayNothing` |
| `Fixture.aParenthesisOfProseIsNoJudge` | `Fixture.aParenthesisOfProseIsNoJudge` |
| `Fixture.aParenthesisAfterAWordIsNoJudge` | `Fixture.aParenthesisAfterAWordIsNoJudge` |
| `Fixture.unknownEffortSaysNothing` | `Fixture.unknownEffortSaysNothing` |
| `Fixture.judgedWordingOnlySaysNothing` | `Fixture.judgedWordingOnlySaysNothing` |
| `Fixture.ambiguousPrefixSaysNothing` | `Fixture.ambiguousPrefixSaysNothing` |
| `Fixture.unknownCommitSaysNothing` | `Fixture.unknownCommitSaysNothing` |
| `Fixture.shortShaSaysNothing` | `Fixture.shortShaSaysNothing` |
| `Fixture.unclosedTickSaysNothing` | `Fixture.unclosedTickSaysNothing` |
| `Fixture.upperCaseHexSaysNothing` | `Fixture.upperCaseHexSaysNothing` |
| `Fixture.lowerCasePassSaysNothing` | `Fixture.lowerCasePassSaysNothing` |
| `Fixture.authorNoteInAParenthesis` | `Fixture.authorNoteInAParenthesis` |
| `Fixture.authorNote` | `Fixture.authorNote` |
| `Fixture.mixedAuthorIsNone` | `Fixture.mixedAuthorIsNone` |
| `Fixture.twoAuthorNotesAreNone` | `Fixture.twoAuthorNotesAreNone` |
| `Fixture.noAuthorNoteIsNone` | `Fixture.noAuthorNoteIsNone` |
| `Fixture.coauthorIsNoNote` | `Fixture.coauthorIsNoNote` |
| `Fixture.unknownModelIsNone` | `Fixture.unknownModelIsNone` |
| `resolveKnown_spec` | `Fixture.Compatibility.resolveKnown_spec` |
| `verdictsOf_spec` | `Fixture.Compatibility.verdictsOf_spec` |
| `passNamesNoFail` | `Fixture.Compatibility.passNamesNoFail` |
| `verdictsFromTheCell` | `Fixture.Compatibility.verdictsFromTheCell` |
| `Fixture.noRowIsNotEligible` | `Fixture.Compatibility.noRowIsNotEligible` |
| `Fixture.anOpusAuthorIsNotCoveredByItsOwnModel` | `Fixture.Compatibility.anOpusAuthorIsNotCoveredByItsOwnModel` |
| `Fixture.noAuthorNoteIsNotEligible` | `Fixture.Compatibility.noAuthorNoteIsNotEligible` |
| `Fixture.aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush` | `Fixture.Compatibility.aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush` |
| `Fixture.aVerdictOnOtherContentDoesNotCarry` | `Fixture.Compatibility.aVerdictOnOtherContentDoesNotCarry` |
| `Fixture.theContentIdsAsked` | `Fixture.Compatibility.theContentIdsAsked` |

The six live `Fixture` source-migration counterparts in the last six rows also remain in their original current locations. The separate theorem-colocation minor is tracked in [#480](https://github.com/kitimark/mitos/issues/480); no admission-fixture refactor is included in this repair round.

Review-fix verification: the isolated compatibility module compiles and audits all 36 obligations; the 26 original case bodies and v/a helpers, and the complete Cell implementation/structural proofs, byte-match the merge base after private-visibility normalization. The native build stays cached with the identical executable hash, and active snapshot/native-hook/raw-record controls remain148/148. Imports, wrapper syntax/shellcheck and runlog checks pass. The new head still requires fresh CI and independent review.
