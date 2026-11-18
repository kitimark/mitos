# CI-493: isolate gate shell suites

phase: 1
goal: all current gate shell suites run once in isolated shards, and prove refuses incomplete or unsuccessful execution evidence within unchanged CI deadlines
statement: none (tooling task)
touches: .github/workflows/ci.yml, .github/scripts/gate-tests.py, .github/scripts/gate-tests.test.py, .github/scripts/cheat-shard.test.sh, .github/scripts/cache-key.test.sh, gate/cache-logs-test.sh, gate/cache-logs-mutations.py, this task, ops/runs/2026-11-18/CI-493-builder-1.json
must_not_touch: statements.lock, models.lock, core/, models/, eval/, other gate/ files, .github/scripts/ci-trust.sh, phase plans
checks: gate-tests fixtures and mutations, cheat-shard, cache-key, ci-trust, native cache-log controls and mutations, native/PyYAML workflow comparison, syntax, append-only runlog, current-head hosted CI and independent review
budget: 40 iterations · 2h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context

[#493](https://github.com/kitimark/mitos/issues/493) records the checks deadline failure at #488's `0ed3425`. The warm-cache build took 271 seconds; 27 serial shell suites took 769 seconds, leaving insufficient time for Core replay and later checks. The cancelled attempt remains failed. Package and reach tests already reuse their native binary; increasing a timeout or retrying a timed-out run is outside this repair.

The grounding baseline is main `4be3c1ed6d21372ece083f4a841b58d69b496331`, tree `51eafb08b05baf17962d5eb811a4d4cdc543658c`. This separate CI unit enables the reader-and-Shadow extraction on #488 to obtain complete evidence. It does not alter that feature, #336's six acceptance clauses, D/T0, historical reports or sole final activation.

## Design

depth: build: executable Python boundary with real CLI fixture, refusal and workflow-composition controls
revisit_when: the actual suite inventory, CI job graph, cache producer or required gate semantics change

modules:

| File | Topic | Rough budget and layout |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Isolated execution and result transport | ~110 added lines; existing cheat-shard setup and prove flow |
| `.github/scripts/gate-tests.py` | Suite inventory, execution and evidence admission | ~200 lines; standard-library process/JSON boundary |
| `.github/scripts/gate-tests.test.py` | CLI and composition sensitivity | ~320 lines; isolated temporary repos and actual workflow step |
| `.github/scripts/cheat-shard.test.sh` | Exact graph and trust wiring | ~50 added lines; existing job-scoped finite assertions |
| `.github/scripts/cache-key.test.sh` | Full cache key/path equivalence | one count update; retain all input/path checks |
| `gate/cache-logs-test.sh` | Immediate unconditional cleanup | one new restoring job |
| `gate/cache-logs-mutations.py` | Cleanup sensitivity | new job/predecessor, seven cases |

types: private `Suite(path, digest)`; version-1 execution record with run/commit/tree, shard index/count and ordered path/digest/exit/log results
statements: no new Lean statement; `CheatsAggregate.AggregateAccepts` retains its actual two-status/corpus meaning
reuse: existing checkout, toolchain, bubblewrap, cache and artifact actions; native corpus aggregate and ci-trust runtime
fixtures: counts 1/2/4/7/27/28, replacement/addition/removal, empty total and residue, failure continuation, source/content drift, strict JSON/log/status mutations, shared-selector omission, real verify-before-native composition and finite workflow mutations
cut_line: move only the complete shell-suite loop into three isolated workers; admit their status and evidence before native aggregation
deferrals: underlying host slowdown is unknown; no lock optimization, deadline change, CI framework, provenance/model/schema or reader policy change
owner_decisions: architecture selection is the implementor's response to the split/catch-up goal; the owner retains trusted-path merge

### Caller contract

Each worker calls `python3 -I .github/scripts/gate-tests.py run --shard k/3 --out <fresh RUNNER_TEMP directory>`. Prove calls `verify --job "$GATE_TESTS" --shards 3 <three downloaded directories>` before the unchanged native aggregate. The real needs expression supplies the job status. There is no favorable default, fixture flag or compatibility path.

Sorted current-tree `gate/*-test.sh` ranks select residues modulo three. Workers execute serially in separate checkouts, retaining later diagnostics after a failure. A nonempty total inventory is required; a legitimate empty residue records zero work. Initial scripts must match executable Git HEAD files. Content/inventory changes prevent completion. Fresh output lives outside restored caches. A complete atomic record contains actual integer exit codes and relative contained regular logs; partial logs remain diagnostic.

The receiver accepts only matrix `success`, matching current run/commit/tree, three unique shard identities, exact selected ordered results, zero exits and complete logs. An independent full-union comparison rejects omissions even if runner and receiver share a defective selector. Unknown, duplicated, missing, stale, malformed or unsuccessful evidence refuses. Records and hosted logs/status support review; they do not cryptographically attest execution. Successful prior-attempt jobs from the same run/tree remain usable under the existing cancelled-not-timed-out rerun procedure.

### Workflow and cache boundary

The normal graph has eleven executions from seven job definitions: checks, three gate-tests workers, three cheat shards, prove, unconditional gate, scorecard-comment, and the same-repository cancellation job. The new workers have a 20-minute bound; every existing bound stays unchanged. Prove needs checks, gate-tests and cheat-shard and runs under its existing always/content-event predicate. Verification failure prevents native aggregation and successful merged upload.

Gate has no needs or job if and retains its same-head label-only reuse, newest failure precedence, spec-label reread, permissions and polling bounds. Scorecard remains produced by checks. The native checks/shards inputs, 56-case corpus, three shard logs, binary linkage, proofs, honest acceptance, lint and publication obligations retain their meanings.

There are five checkout definitions and six Lean-cache blocks. Workers restore only, using the full existing key/path contract and immediate unconditional stale-log cleanup. Only checks on main saves the full Lean cache. All seven cleanup mutations run on four restoring jobs, 28 cases. No shared mutable checkout/cache or top-level concurrency is introduced.

### Rationale and alternatives

Two independent architecture packages considered three uniform shell workers and a separate Core/proof lane. The root selected the uniform worker design: it removes the measured variable shell lane while avoiding a permanent heavy-test classifier and relocation of proof/scorecard producers. The synthesis added an independent union/content-stability check and direct Python tests. Preferred model names were unsupported by this environment; inherited Codex execution supplies no cross-model or qualifying Claude review claim.

This adds three setup/build runners and an artifact family. Existing timing projections only size the proposed lane; they establish no measured speedup or physical-load cause. Hosted final-head timings, queue time and runner minutes must be reported. One complete successful run establishes that attempt fit the unchanged bounds.

The focused test file is larger than the original ~160–230-line estimate because it exercises real CLI execution, strict refusal cases and the actual prove step with controlled native/publication markers. It remains one protocol/composition topic. Stubs do not establish hosted artifact transport or real corpus/proof results.

### Rollout and rollback

Publish this complete graph/helper/evidence/cache-contract unit separately. After an actual owner merge, rebase #488 onto real main before its next qualifying cycle. Old feature verdicts and timed-out results do not carry. Roll back the whole unit together, restoring the serial loop and associated assertions; removing only workers or only admission could omit work. Rollback restores the known capacity risk.

## Verification

Focused CLI fixtures, finite graph/cache-key/ci-trust checks and native cache-log controls pass locally. The native parser is an isolated copied binary from the verified main-equivalent #491 tree, with recorded source and stripped-copy digests; this is local parser reuse, not a fresh build or complete current-head CI claim. No Lean source changes. Hosted CI must build the published head and exercise all eleven jobs, original proof/corpus obligations, new execution bundles and successful aggregation. Fresh no-comments, CodeRabbit and qualifying independent Opus review remain required.

## Done when

- [x] focused boundary, refusal, composition and affected finite checks pass locally
- [x] no Lean statements, proofs, axioms, locks, policy or deadlines changed
- [x] run-log record written and checked against the base
- [ ] exact published head passes hosted CI and independent reviews
