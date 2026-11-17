# GA-Q3 deployed mint repair (#474 companion)

phase: 2
goal: Restore explicit request limits for the two deployed app-token callers without waiting for #336's prospective shadow gate.
statement: dependency input contract only; no Lean policy/spec change
touches: land-protection/update-prs refs and updater narrowing inputs, existing protection test constants, focused dependency input contract/wrapper, this task, new runlog
must_not_touch: core/, locks, plan/, process rules, #336 feature modules, historical artifacts, current main scanner checks, secrets, environments, installation grants, merge policy
checks: build, existing protection suite, focused offline input contract and old-pin sensitivity, actionlint/shellcheck, diff, imports/lock/runlog, current-head CI/CodeRabbit/independent/Opus
budget: narrow independent runtime dependency repair
escalation: stop/report blocked defensive tests; no live credential or token request

## Design frozen before implementation

The repository's PR-owner scope rule places an independently deployable security repair in its
own PR. The root applied that rule to the Protection/updater dependency defect found during
#336 review. This is the root's process judgment, not a new owner ruling or merge approval.
This companion is Part of #474; #336 still owns the new apply mint and closed caller inventory.

Main at b32c3d7 has Protection pinned to v1.12.0 with administration read. Updater still names
mutable v1 and no permission limits. The bounded repair selects stable Node24 v3.3.0 at
64ab729a6294000f5aa4a4bc0b73d1f32bc45510 and explicitly narrows updater's request to its already
used contents/pull-requests/workflows write functions. No installation grant, token consumer,
secret, environment, checkout behavior or workflow scheduling changes. Existing scanner and
runtime assertions remain, with only exact Protection action constants updated.

The existing native L4YAML reader supplies decoded workflow leaves to the same byte-bound
`gate/app-token-input-contract.test.cjs` used by #336, with exactly these two caller rows.
The focused `gate/app-token-input-contract-test.sh` wrapper builds the reader if needed, downloads the public immutable
bundle, verifies full Git-blob identity in the test, then executes only its actual collector,
main and entrypoint sections with explicit dummy environment and local core/auth/request/retry
stubs. No inherited process, require or network capability enters the VM. No real private key,
signature, token request or installation grant is used. Transitive dependency initialization
is excluded. Two baseline and two underscore-data controls must yield precisely administration
read and contents/pull_requests/workflows write, repository mitos and saved revoke state.
Restoring the verified old dependency must fail the permission assertion, not only a ref check.

The existing post-build CI loop already runs every `gate/*-test.sh`, so it discovers this
focused wrapper without any CI workflow change. No #336 Workflow Pins module is brought
onto main. This is a focused dependency input check, not a claim of complete caller authority.

Compatibility is explicit v1 to v3 and Node20 to Node24. The observed hosted runner 2.338.2
exceeds minimum 2.327.1; ubuntu-24.04 jobs declare no proxy. No NODE_USE_ENV_PROXY setting is
added; later proxy configuration needs separate review. App-id fallback, private-key input
and default revocation remain.

When this lands, #336 must rebase and preserve its third apply caller, native zero-mint theorem,
all old and new negative controls and the main repair. Both branches add the same cjs test, so an add/add conflict is expected: retain one
implementation with three caller rows. For #336 rename the glob-discovered wrapper to `gate/app-token-input-contract.sh` and call
it once from app-token.test.sh after its complete native pin check. Delete the old glob wrapper
as an explicit test-caller migration, so the existing loop and app-token suite do not both run it. Keep one download/VM execution, all cases and both task/runlog records. Protection's
scanner-to-typed-contract migration may also conflict on the updated expected pin: preserve
its runtime assertions and new finite typed expectations while completing the accepted scanner
removal in #336. The approved prospective shadow clauses and outstanding #327/window gate remain.

## Validation

Implementation is complete. Protection 6, four offline input controls and old-pin permission
assertion sensitivity pass, along with ci-trust, cache-key, imports (zero), lock (207), runlog
(248 files/307 records), actionlint, shellcheck and diff. The native reader is reused from the frozen main460c383 CI artifact (SHA256
919bcd7ad150c164b9723cffe6d289104a52dfa0feee427dd6a9f4cc6cc45563): gate, core, toolchain
and dependency inputs compare byte-identically with base b32c3d7. Four controls and old-pin
sensitivity pass with that exact reader. A redundant local native rebuild was deliberately
stopped during unchanged kernel fixtures, preserving its cache; it is not a local build pass.
CI must rebuild at this PR head. Current-head no-comments, independent review, CI,
CodeRabbit and required external Opus precede any owner merge. No merge is performed here.
