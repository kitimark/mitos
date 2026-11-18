# tasks/GA-Q3-current-workflow-pins.md

phase: 1
goal: The deployed decide-only workflow bundle has one complete native authority contract used by its real test callers.
statement: none locked (tooling task); LandPins.check_sound, LandPins.check_decide_only, LandPins.check_no_land_mint, Pins.check_sound, Pins.check_no_unprivileged_mint
touches: gate/MitosGate/Workflow/{PinNode,LandPins,ProtectionPins,AppTokenPins,CiPins,Pins}.lean, gate/MitosGate/WorkflowCli.lean, gate/Main.lean, gate/workflow-pins-check.py, gate/workflow-pins-test.sh, gate/app-token-input-contract-test.sh (rename to app-token-input-contract.sh), .github/scripts/{land-decide,land-protection,app-token}.test.sh, .github/workflows/{land,update-prs,ci}.yml, this file, tasks/P1-020-land-merge-workflow.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, models, plan/, .claude/, docs/process.md, .github/scripts/{land-decide,land-protection,rebase-prs}.sh, .github/workflows/land-protection.yml, gate/app-token-input-contract.test.cjs, gate/MitosGate/{Land,LandCli,Snapshot,Shadow}/, gate/snapshot-test.sh
checks: build, kernel and axiom audits, imports, lock, Core check and paranoid comparator, workflow native mutations and placement, reader/PyYAML differential and qualification, actual caller and pinned-bundle controls, CI composition and receipts, shell/workflow lint, runlog, honest acceptance and corpus, current-head hosted CI
budget: 30 iterations · 6h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

This is unit T of the accepted #336 split, after the B+C correction in #488 and ordinary
owner-ping admission in #496. The existing decide and protection suites mix runtime checks
with workflow-text assertions. The current app-token dependency controls run separately.
The complete native operation replaces those text assertions and has all three actual callers.

## Design

depth: build; reuse the accepted caller-first finite contract, checked against current main
revisit_when: the deployed workflow shape or any caller changes; repeated implementation friction
modules:
- `Workflow/PinNode.lean` owns typed-tree pin comparison, about 60 lines, following `Yaml/View.lean`.
- `Workflow/LandPins.lean` owns the exact current decide-only authority, about 180 lines, with its statements and kernel fixtures beside the definition.
- `Workflow/ProtectionPins.lean` owns the administration-reader boundary, about 173 lines, preserving the accepted complete contract.
- `Workflow/AppTokenPins.lean` owns named mint authority, about 193 lines, including the complete updater shape and closed inventory.
- `Workflow/CiPins.lean` owns execution of the three actual post-build suites, about 98 lines.
- `Workflow/Pins.lean` owns the complete bundle operation and filesystem boundary, about 110 lines.
- `WorkflowCli.lean` and `Main.lean` own the existing workflow command route; add only `workflow pins`.
- `workflow-pins-check.py` and `workflow-pins-test.sh` own current-bundle mutation exercises and their native driver, about 325 and 5 lines.
- The three `.github/scripts` suites own recorder behavior, protection IO and dependency assurance. Keep runtime assertions while replacing workflow-text checks.
- The renamed `app-token-input-contract.sh` owns the existing dependency controls; keep its four-control result and CJS unchanged.
- The three workflow files own immutable existing references and actual verification scheduling; keep the entire current worker/receipt graph.
types: `Pins.Inputs {land, protection, ci, updater, ownerPing, otherWorkflows}`; `holds`, `check`, `check_sound`, `check_no_unprivileged_mint`, `run`; `LandPins.holds/check/check_sound/check_decide_only/check_no_land_mint`
statements: a successful check establishes the complete current conjunction, decide-only Land and zero Land/unprivileged mints using the existing mint-count concept
reuse: owned L4YAML admission, typed Doc/Node lookup, existing placement, complete Protection/updater closure, current action-bundle controls, current CI suite workers and receipts
fixtures: readOnlyLandAccepts, applyJobIsNotCurrentAuthority, reportJobIsNotCurrentAuthority, producerOutputsAreNotCurrentAuthority, landMintIsNotCurrentAuthority, rootInputOverrideRefuses, protectionEarlierEnvWriterRefuses, updaterEarlierEnvWriterRefuses, three-suite scheduling, two-copy owner-ping drift and restored anchors
cut_line: one complete contract for the actual decide-only bundle, all assertion/caller migrations, two real mint callers, four dependency controls, one helper invocation and three direct post-build suites
deferrals: F replaces current-only authority statements/absence fixtures with its exact authorized three-job contract, producer outputs, third mint and five suites; #497's unrelated refusal-location and historical-doc follow-ups stay separate
owner_decisions: no new policy; reuse the accepted finite current-contract split after #496's actual merge

The caller is `mitos-gate workflow pins <repo-root>`. It hides directory IO, admission of every
`.yml` and `.yaml` workflow, typed policy and stable errors. Callers choose no profile. Policy
conjoins exact Land, Protection, updater/mint, CI and the two-copy owner-ping coherence check.
The latter requires the two actual notification steps to match; it does not pin the entire
notification implementation. A partial mint check is not inherited-input safety.

Land retains exactly one decide job and nine steps. It has no root environment or switch,
producer outputs, apply/report job, app key, mint or write. The only mint callers remain
Protection/read and updater/rebase. CI runs protection, decide and app-token once after the
unique unconditional build. The renamed helper leaves the top-level shell glob and runs once
through app-token, preserving all four existing bundled controls.

The CI contract covers the required build and test step shapes, their controls and schedule.
It does not pin arbitrary earlier setup scripts. The known earlier-setup `GITHUB_ENV` and
`BASH_ENV` residual remains in #466 item 2 and #453. Protection and updater retain their
separate complete owned input and earlier-env-writer checks.

The migration inventory covers 112 existing assertion sites: retain 65 runtime/source sites and
replace 47 authority sites with their complete decoded counterparts and real mutations. Preserve
all thirteen updater reference sites, owned inherited-input/earlier-env-writer controls, full
placement fixtures and remaining-workflow inventory. Every mutation must change an actual
current anchor; future-only apply/report/output controls do not count. The absent-steps mutant
must preserve every unrelated CI job.

F removes the current-only statements and replaces each authority-changing absence fixture
with its final exact positive/negative counterpart. No permanent second checker survives.
Rollback T with its caller migration, helper rename and schedule together while retaining N.
Stop and re-ground if implementation needs profiles, a future API, a dropped assertion or
unexplained growth beyond the accepted adaptation estimate. D/T0, the six approved clauses,
failed historical evidence and every activation prerequisite remain unchanged.

## Done when

- [x] The complete actual current bundle and all retained mutation/caller controls pass.
- [x] The three suites and one helper execute once; the current CI graph remains intact.
- [ ] All applicable process checks pass, with real local environment blocks identified.
- [x] No new axiom or `sorry`; the owned statements pass their standard-axiom audit.
- [ ] Current-head hosted CI, fresh no-comments and qualifying independent review pass.
- [x] An honest append-only attempt record is included.

## Local validation, 18 November 2026

The full native build passed with 694 jobs in 638.418 seconds. The axiom audit checked
13 named statements and all 24 persisted policy theorems, and rejected its scratch axiom.
The actual current bundle accepts. Its native driver passes 213 controls. Decide passes
19 controls, protection six and app-token five, including four actual dependency controls.
The helper trace records one invocation. All 700 reader qualification mutants are accounted
for, with 250 admitted trees equal to PyYAML and 450 refusals. Imports, lock, plugin lint,
CI receipt/composition checks, nine process-contract suites and shell/workflow lint pass.

All 27 gate shell suites completed at the same source head with clean restoration. Twenty-six
pass. The unchanged provenance-hook suite has 39 failures because the local user does not own
the root ancestor. Core check, paranoid comparator and honest acceptance fail at the read-only
UID-map boundary. Six of 269 model-lint cases hit that namespace restriction. All 112 corpus
executions have `NO-VERDICT` with the same UID-map error, not a timeout. These are unpassed
checks. No guard, expectation or deadline changed, and no blocked command was retried.

The first redundant whole-tree kernel acceptance fixture was killed with exit 137. Removing
that mirror preserved the generic proofs, small kernel refusals and actual native controls.
The corrected targeted build and full native build passed without increasing the measured
OOM-kill counter. Source and no-comments inspections found no remaining finding at the source
candidate. The final metadata binding, hosted CI and qualifying independent review remain due.
