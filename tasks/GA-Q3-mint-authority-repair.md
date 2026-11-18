# GA-Q3 mint authority repair (#474)

phase: 2
goal: Restore the three reviewed mint permission maps and close admission to their finite workflow contracts.
statement: Workflow.AppTokenPins.check_no_unprivileged_mint and Workflow.Pins.check_no_unprivileged_mint (gate policy only)
touches: three mint workflow refs, Workflow/AppTokenPins.lean, Workflow/LandPins.lean, Workflow/ProtectionPins.lean, Workflow/Pins.lean, focused workflow-pins/app-token controls, this task, GA-Q3 task correction, new runlog
must_not_touch: core/, locks, provenance/scorer/identity modules, archived shadow artifacts, plan/, process rules, runtime land approval/merge policy, #466 m1 deferred coverage
checks: native build, five caller suites, complete-bundle controls and inventory guard deletion, offline dependency input contract and old-pin sensitivity, imports, lock, runlog, actionlint, shellcheck, final-head CI/review
budget: bounded repair to #336; no new architectural arena
escalation: report any blocked defensive check; no live token or credential experiment

## Design frozen before implementation

The standing request to implement #336 and resolve review findings covers this confirmed runtime
repair, as assessed by the root. This is the root's scope judgment, not a new owner ruling.
The accepted L4YAML architecture remains in `GA-Q3-workflow-pins.md`; this closes its mint
admission boundary rather than changing the reader or introducing another policy language.

Ground: `Pins.run` enumerates every .yml/.yaml file and admits each into an owned `Yaml.Doc`.
LandPins and ProtectionPins already constrain their entire mint-owning workflows; AppTokenPins
constrains the entire updater. The existing all-workflow mint checker only constrained local
mint fields, leaving additional callers' inherited environment and earlier programs open.
The v1.12.0 dependency also ignores canonical permission inputs at runtime. Both faults must
be repaired: closing callers alone cannot restore the current three permission maps.

Caller usage remains `mitos-gate workflow pins <repo-root>`. The internal shape becomes:

```lean
AppTokenPins.check (land protection updater : Doc) (unprivileged : List Doc)
  : Except String Unit
AppTokenPins.holds (land protection updater : Doc) (unprivileged : List Doc) : Prop
Inputs.unprivilegedWorkflows (i : Inputs) : List Doc
AppTokenPins.check_no_unprivileged_mint
  (h : check land protection updater unprivileged = .ok ())
  : mintCount unprivileged = 0
Pins.check_no_unprivileged_mint (h : check i = .ok ())
  : AppTokenPins.mintCount i.unprivilegedWorkflows = 0
```

`unprivilegedWorkflows` derives `[ci, ownerPing] ++ otherWorkflows`; these documents remain
fully enumerated and parsed. AppTokenPins retains its existing nonempty/shape/local-authority
checks and updater comparison, then adds the zero-mint inventory invariant. Land/Protection
contracts remain complete and independently composed. The named ownership signature removes
the generic arbitrary-workflow admission claim. No registry, profile, expression parser,
shell-text heuristic or INPUT_ substring guard is added.

An alternative puts a separate inventory guard only in Pins. It is smaller at the callsite but
leaves the public AppTokenPins signature suggesting arbitrary caller authority protection.
The selected named-document interface carries ownership at that boundary and yields a direct
kernel-checked consequence. No new module or PinNode helper is needed. Existing negative
controls retain their guard order and safe representation controls remain accepted.

Dependency choice: stable `actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510`
(v3.3.0), verified main bundle Git blob `6158842fe3bfd1a37b55273beb1805fc52f95120`.
This explicitly updates v1 to v3 and Node20 to Node24. The reviewed action retains app-id
fallback, private-key input and skip-token-revoke=false; no client-id, enterprise, owner,
repository, secret, permission or environment setting is added. It requires runner 2.327.1;
observed CI runner 2.338.2 exceeds it. All three jobs use GitHub-hosted ubuntu-24.04 and declare
no proxy configuration. The v3 native proxy precondition applies only when a proxy is configured;
no NODE_USE_ENV_PROXY setting is needed for this production context. A later proxy deployment
would need a separately reviewed literal environment change and currently fails closed.

Validation uses deterministic dummy inputs and local dependency stubs with no real private
key, network or token request. It must exercise the exact bundled permission collector and
main/auth option boundary for all three expected maps, verify repository scope and revoke
behavior, and fail when the old pin is restored. A blocked experiment is not evidence and
will not be retried. Source inspection and offline results do not establish a live installation
grant or permissions beyond it.

The new native fixtures add a fourth mint with no injection, root/job/step underscore env,
an earlier GITHUB_ENV write, and unknown underscore with. CI and owner-ping mints are also
refused. Removing only the inventory guard must admit an otherwise valid forbidden fixture
and fail the same refusal test. Existing known-three production workflows pass together.

## Execution

- [x] Ground and sketch the bounded delta before code; accepted architecture reused.
- [x] Implement the frozen interface and three refs.
- [x] Run focused controls, sensitivity, caller suites and appropriate checks.
- [ ] Root no-comments and independent review on the code-ready head before push.
- [ ] Push one coherent batch with explicit lease; fresh CI, CodeRabbit and external Opus.

Rebase: the 14 existing feature commits were replayed onto main b32c3d7. The single conflict
in P1-020's task retained the complete approved prospective gate block from main and all
feature build notes. The approved block and unresolved evidence checkbox remain unchanged.
The closed #329 parent/ref and PR stack metadata stay intact. No readiness or merge approval
follows from this repair: #327's deployed repair and the required prospective window remain
separate prerequisites. #466 m1 stays deferred under the owner's earlier choice.

## Local validation

The 182-job native build and all five callers pass: protection 6, decide 29, apply 41,
report 20, app-token 7. Native whole-bundle coverage is now 230 checks (205 functional/IO/usage
and 25 repeated complete calls). Every old negative control remains; the formerly accepted
fourth mint is now an intentional inventory refusal, paired with a safe nonmint workflow.
Twelve additional owned-workflow controls refuse root/job/step environment and unknown inputs.
The actual compiled inventory-guard mutant accepts the same extra-mint fixture and makes its
native refusal assertion fail; only proof/test declarations that cannot hold for the mutant
are omitted from that temporary build. Production source and proofs are restored afterward.

The app-token suite downloads the public immutable bundle, verifies its complete Git-blob hash,
then executes only the byte-bound collector, main and actual entrypoint sections in an isolated
VM with explicit dummy environment and local auth/request/core/retry stubs. Six controls verify
all three intended permission maps, repository mitos, app-id fallback and saved revoke state;
undeclared underscore input data does not alter the maps. Restoring the old action ref and
verified old bundle fails the permission-narrowing assertion with undefined permissions.
Transitive dependency initialization is excluded; no real credential, signature, network call
or installation grant is tested. No tool blocked these narrowed checks.

Imports report zero violations; the lock matches all 207 declarations. Shellcheck, actionlint
and diff checks pass. Full kernel/paranoid/acceptance/cheat local UID-map limits remain as
previously documented; sandboxing stays enabled and new-head CI is required. The six approved
prospective contract clauses compare byte-for-byte with main; none of its evidence checkboxes
is checked by this repair. Rebase diff against the prior source head contains only main's
policy task/plan/runlog additions; all 14 feature commits and runtime/mapping content survive.
