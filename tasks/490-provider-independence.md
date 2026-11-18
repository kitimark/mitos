# Unknown author models and provider independence

goal: A truthful null author model can pass only with a standing accepted Claude PASS from another provider.
statement: Provenance.unknownAdmitted; Provenance.unknownRequiredHasEffort
touches: gate/MitosGate/ModelIdentity.lean, gate/MitosGate/Land.lean, gate/MitosGate/Provenance.lean, their projection/serialization/proof adapters and fixtures, scoped native tests, kitimark-mode rules, this task, one new run record
must_not_touch: source/record version numbers, source fields or limits, archived records, prospective acceptance clauses, publisher/dashboard/assignment/labels, #487, #488, #336, Core/spec/locks/workflows
checks: full build, source proofs/axiom audits, real-source/native snapshot/hook/record/replay controls, guard mutations, transport/legacy/Land/Shadow/Speech/carry, imports/lock/runlog, required local matrix and current-head hosted CI
budget: 120 iterations · 3h wall · tokens unmetered

## Authority

The owner [picked (c)](https://github.com/kitimark/mitos/pull/488#issuecomment-6975699549).
The [build brief](https://github.com/kitimark/mitos/issues/490#issuecomment-6975722968)
requires truthful null retention, cross-provider independence, critical actual Opus effort,
unchanged adverse/carry rules, proofs, controls and guard mutations. The selected architect shape
is the explicit author-knowledge domain; its reported specialization preserves the old policy.
This trust-infrastructure PR still needs actual independent Claude Opus xhigh/max review and owner merge.

## Design

### Caller usage

Snapshot delegates present source facts to `Provenance.project`; the native hook calls `admitted`.
Both use the same Land coverage relation. Raw source identity keeps `actualModel : Option String`.
Only null maps to `AuthorModel.absent`; reported strings map explicitly to `reported`.
Requested model text supplies no identity, including when a valid null author uses the exception.

### Modules

| File | Topic |
| --- | --- |
| `ModelIdentity.lean` | Explicit author knowledge, strict reported relation, finite canonical outsiders and independent absent relation. |
| `Land.lean` | One coverage policy, adverse veto, reported-only wording classification and reported-domain equivalence. |
| `Provenance.lean` | Carried source author retention, complete source PASS guard, actual critical effort and source-witness theorems. |
| `Snapshot/Obs.lean` | Projection delegation and its exact field equation. |
| `SnapshotCli.lean`, `LandCli.lean` | String/null nested model encoding and strict decoding. |
| `Speech.lean`, `Snapshot/LegacyFixtures.lean`, `Shadow/Reading.lean` | Explicit reported embeddings and proof migration; historical semantics retained. |
| `Provenance/Fixtures.lean`, `Snapshot.lean` | Kernel controls, real #488 facts and standard-axiom audit registration. |
| `ProvenanceProviderTest.lean`, `provenance-provider-test.sh`, `provenance-fixtures/488.json` | Typed raw-source facts, real-head Snapshot projection, mapped events and isolated record/replay. |
| `snapshot-test.sh`, `land-test.sh` | Native source transport/hook/recorder and strict wire controls. |
| `provenance-provider-mutants.py` | Fresh compiled definition-closure/interpreter controls for named guard expectations. |
| `kitimark-mode/SKILL.md` | Narrow owner-approved exception. |

### Policy and compatibility boundary

`key`, `claudeKey`, `acceptedClaude` and `opus` retain their String signatures and behavior.
The first model argument of `different` openly becomes `AuthorModel`; it has no String coercion.
`reportedDifferent_eq` gives the exact previous key/key expression for every old String input.
`differentNeedsKnown` keeps its original String quantifiers and key-known conclusion through explicit
reported embedding. `reportedCovered_iff` states the complete previous coverage expression universally.
No prior theorem gains a premise or loses a conclusion.

Absent independence permits exactly `openai` and `google`, a different provider and a known actual
judge key. Retention itself requires carry and membership. Accepted actual Claude PASS, distinct
giver, standing/latest-by-giver semantics and the universal standing FAIL/HOLD veto remain required.
Absent authors cannot use either wording-only branch. Critical paths and `spec-approved` require an
actual Opus xhigh/max witness. A supplemental low-effort PASS remains factual and does not veto.

Source schema/version/fields/transport/caps remain unchanged. Record outer version and field names
remain v1. Existing author model strings encode identically and decode as reported; the sole wire
extension is required nested `author.model:null`, which decodes as absent. Missing whole author
remains none; present whole `author:null` remains malformed. Missing/wrong-type model remains malformed.
Old binaries cannot read the new nested null before deployment. No archived record is regenerated.

### Evidence boundaries

The real positive uses #488 at `60b10dc1c4428c26e5cbcb78a4f8aaf83e1977cc`: author openai/codex/null;
verifier claude/verifier-488-60b10dc/claude-opus-5-5/xhigh/PASS/order1 with its public evidence URL.
Raw typed source checks retain author head, effort, requestedModel and evidence before projection.
The archive asserts the complete ordered five-field Land event mapping, including verifier null's
existing `unknown` projection; the archive does not store raw author head, effort or evidence.
The real-head projection uses isolated typed reads/IDs; generated-Git native snapshot/hook/recorder
controls separately test I/O. Neither is live eligibility or a prospective-window result.

Mutation reports distinguish load-bearing source admission from supplementary relation/projection
contracts. Provider inequality, known-judge-key and retained-provider guards can be redundant at full
admission because accepted Claude and canonical outsider checks remain. Such helper mutants are not
claimed as merge bypasses. The null-only typed projection mutant cannot pass the separate raw decoder.
Mutants compile the affected definition closure to fresh `.olean` modules and run the Lean interpreter;
they are not native executable relinks or whole-project proof builds.

### Synthesis decision and corrections

The explicit domain was selected over a source certificate/second eligibility route, which would need
a synthetic model or weaken universal coverage. Keep one runtime policy and adapter boundary.
The source guard retains its complete PASS shape so ordinary invalid/uncarried/no-PASS sources keep
`rest=false`. Omitted whole-author and raw-versus-mapped-record semantics were checked against main;
both corrections are reflected above. Test code exceeds the sketch estimate to cover those boundaries.

## Validation

Results and exact guard scopes are recorded in the PR body and this attempt's run record.
Local UID-map or root-ancestry refusals must be reported as environmental failures with no bypass;
hosted current-head CI supplies required sandbox evidence. The deployed old main will hold the
unknown author of this bootstrap PR until the owner merges this approved policy change.
