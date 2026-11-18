# GA-Q3: decoded workflow authority pins on #336

phase: 2
goal: Replace every remaining workflow YAML scanner in the five land/token suites with one owned-tree authority contract.
statement: Workflow.Pins.check_sound and check_apply_condition (gate policy only; no locked spec changes)
touches: gate/MitosGate/Workflow/*Pins.lean, gate/MitosGate/Workflow/PinNode.lean, gate/MitosGate/WorkflowCli.lean, gate/Main.lean, gate/workflow-pins-test.sh, gate/workflow-pins-check.py, five land/token suites, land-decide.sh answer count bound, land.yml, ci.yml, owner-ping.yml, oracle admission tests, this task, P1-020 notes, new runlog
must_not_touch: core/, locked specifications, plan/, runtime land approval/merge policy, #453 policy expansion
checks: native build, existing land/token and workflow suites, new real-bundle mutations, imports, lock, runlog, lints, comparator/acceptance/cheats where environment permits and final-head CI
budget: 40 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Design

The user asked to adopt L4YAML on [#336](https://github.com/kitimark/mitos/pull/336) using
architect and related principles, then no-comments and review catch-up. #455 already replaced
the placement scanner. This round moves the remaining workflow pins, including #366 and
#341's complete apply-condition guard, onto decoded owned values. The broader five-caller
scope is required to remove the single shared `job_block` reader rather than leave another
YAML interpretation behind. Runtime/API/byte tests and shell-source inventories remain in
their original suites.

### Usage

Each independently runnable suite calls the identical complete operation:

```sh
"$real" workflow pins "$root" || note "decoded workflow authority pins were refused"
```

The native mutation suite invokes that exact command against full copied workflow directories.
Success is silent/0, a reader or policy refusal is 1, and usage/IO failures are 2. Diagnostics
contain fixed rule labels and never decoded values, raw leaf JSON, file names or exception
payloads. Every workflow is read once per invocation; no shared cache or mutable global state.
The five required files are land, protection, CI, updater and owner-ping; all remaining .yml
and .yaml files join the same mint inventory. Missing required files and failed enumeration,
reads or admission fail before absence checks.

### Shape and interface depth

`Inputs` owns five admitted `Yaml.Doc` values and the remaining admitted workflow documents.
`unprivilegedWorkflows` derives CI, owner-ping and every additional workflow; the three mint-owning documents are passed by name. `Pins.check` composes land, protection, mint,
CI and owner-ping coherence contracts; `Pins.run` owns filesystem loading and fixed output.
The actual fields, empty containers and sequence indices come from `Node.get?` and
`Doc.scalarAt?`, never a display selector. `PinNode` owns the repeated typed-node equality
operation: map order is irrelevant, sequence order and text/empty-map/empty-sequence kinds
remain distinct. It is not a schema/assertion DSL.

`get` can return one descendant of a map and `get`/`each` display empty containers as text;
their displayed paths are also ambiguous for dotted keys. They are useful inspection APIs,
but do not establish this security contract's exact shape. Captured `leaves` JSON is used
only for fixture 12's explicit path assertion and is never printed into CI logs.

`Pins.holds` is the conjunction of concrete grouped policy propositions. Its kernel-checked
`check_sound` combines the topic proofs. The separate consequence `check_apply_condition`
states that successful admission yields an actual text scalar at `jobs.apply.if` equal to
`github.ref == 'refs/heads/main' && github.run_attempt == '1' && needs.decide.outputs.pr != ''`.
A nested-map impostor cannot satisfy it. These are policy theorems over the existing owned
reader; they do not claim equivalence with GitHub's YAML parser or runtime authorization.
Exact decoded condition bytes preserve internal newlines and spaces in string literals.
No expression-whitespace normalizer is introduced. Safe formatting that preserves the decoded
value passes; different decoded spellings can conservatively refuse.

### Modules

| File | Knowledge owned |
|---|---|
| `Workflow/PinNode.lean` | Repeated exact typed-node comparison, shape lookup and ASCII-case-insensitive identifier matching, with kind/order controls |
| `Workflow/LandPins.lean` | Decide/apply/report authority, complete apply condition, scoped and global reference rules, proof and short fixtures |
| `Workflow/ProtectionPins.lean` | Protection authority, exact four-step order, trigger/condition correspondence and concrete trusted-environment consequence |
| `Workflow/AppTokenPins.lean` | Closed decoded mint inventory, named Land/Protection/updater callers, permissions/trust/identity and finite updater authority document |
| `Workflow/CiPins.lean` | Approved checks-job condition and controls, unique unconditional suite runs after its actual build step |
| `Workflow/Pins.lean` | Required bundle, grouped contract/proof, owner-ping coherence, read-once loader and safe CLI result |
| `WorkflowCli.lean`, `Main.lean` | One closed `pins <repo-root>` dispatch and usage entry |
| Existing five shell suites | Existing runtime/source tests plus one complete native pin call; placement controls stay in decide |
| `workflow-pins-test.sh`, `workflow-pins-check.py` | Actual CLI tests on copied whole bundles and measured repeated-call cost |

### Synthesis decision

Architect grounded both mechanics and history, then produced two independent design packages.
The root read both and scored A 19/20, B 18/20 against exact typed boundary, preservation,
coordination, maintainability and reproducible checks. A's single bundle operation won over
B's five profiles because callers cannot choose an incomplete profile. B contributed fixed
semantic labels and the exact actual-apply-condition consequence. The typed-NDJSON plus one
jq policy alternative was viable and smaller in lines; it lost on invariant ownership and
transport/caller coordination. Repeated display queries were rejected for known kind/path
and cardinality ambiguity.

Requested Claude runner/judge models were rejected by this environment; inherited GPT-6
models produced the candidates, and arena's prescribed unsupported-judge fallback was root
selection. This is not an independent Claude/Opus design verdict. Model-the-domain and boundary
discipline keep authority in the owned tree; subtract-before-you-add and migrate-callers
remove every old YAML scanner in the same wave; behavior-testing supplies actual command
mutants rather than helpers tested against their own constants.

### Admitted-source normalization

Implementation found one real-input drift: owner-ping.yml used &ping/*ping and was the only
live workflow refused by the existing reader. Skipping it or special-casing its hash would
omit part of the mint inventory. Widening reader admission would change a different contract.
Extracting its run body into a script would require a new checkout/content-permission
boundary in a pull_request_target workflow. The scoped resolution expands the exact existing
step into both existing jobs. PyYAML confirms full tree, run/env bytes, conditions and
permissions are unchanged. Typed equality requires the two nonempty one-step sequences to
remain identical, with a text run and map environment; a one-copy edit fails. This is the
single-truth principle's enforce-equality option when derivation needs unsupported YAML.

This adds owner-ping to the required bundle and adjusts the module map's bundle-coherence
responsibility. The obsolete live-anchor refusal exception is removed from the independent
oracle. All seven live workflows now compare normally. The real anchor/alias attack fixtures
still refuse; no reader rule or placement policy is widened.

### Current review corrections

The four producer actions use independently verified release identities: checkout v4.4.0
`11d5960a326750d5838078e36cf38b85af677262`; cache/restore v4.3.0
`0057852bfaa89a56745cba8c7296529d2fc39830`; both upload-artifact v4.6.2 steps
`ea165f8d65b6e75b540449e92b4886f43607fa02`. Official tag objects and restore action metadata
were read before applying them. This is #167's bounded parent blocker, not its broad upgrade
or Dependabot rollout. Policy expected constants are independent from the workflow under test.

Fixture 12 adds four spaces to its original INPUT line, then asserts exactly
`jobs.placement-fixture.env.INPUT` is the intended text. It remains accepted, paired with a
rule-X refusal. Existing 37 placement refusals stay. The source-only merge inventory now
rejects CLI merge, GraphQL merge/automerge, auto-merge and quoted REST fragments, preserves
both exclusions and distinguishes scan errors. #453's shell/container/environment-name
placement gaps remain the owner's separate policy call. Shadow, genuine-owner R0b and fresh
final Opus verification holds are not relaxed.

The first remote review found two real omissions in the new contract: step checks did not
constrain job controls, and dotted secret matching admitted brackets and aggregate references.
The second attempt pins the existing checks-job condition exactly, including its intentional
push/non-label-PR restriction; it rejects changes, absent/non-text conditions, extra job
controls and workflow defaults. `CiPins.check_condition` proves the actual decoded condition
on success. No production CI event, permission or execution policy changes.

A bounded audit also accepted bracket/aggregate GitHub references in unpinned land fields.
The primary fix closes the existing root/job field sets and scalar values, output maps, cache
inputs, report condition and dependencies. Root environment is exactly the existing merge
switch. Decide environment has only LAND_DASHBOARD, whose text can be harmless data but cannot
contain an expression opener. The cache template is a fixed reviewed literal shared by its
key and restore-key expectations, never derived from the input under test. The paired trigger
contract remains in ProtectionPins. These finite shapes prevent moving an escaped context
reference into another previously free field.

The reused secret-identifier guard additionally scans keys and text in Land and Protection,
folding ASCII case and matching identifier boundaries. Thus `SeCrEtS['KEY']` and
`toJSON(secrets)` are references; `secretsauce` and `other_secrets` are harmless larger
identifiers. The one permitted private-key binding still requires its exact path and value.
This is a conservative authority check over the admitted tree, not an expression parser or
a change to generic placement policy.

Whole-bundle controls reach `mint.shape`, `ci.steps` and `protection.triggers`. The earlier
complete land contract masks `protection.references`/`protection.decide` inputs, while its
required mints mask `mint.missing`. Direct public-topic kernel fixtures cover those properties
with otherwise valid paired inputs: a forbidden reader token reference, write authority in
decide, and an empty mint inventory with a valid updater. Removing the respective guard would
accept each forbidden input; the test does not depend on merely changing the first diagnostic.
Positive fixtures accompany them. Guards are not reordered or relaxed for diagnostic coverage.
The native driver also changes decide cancel-in-progress to true. The existing marker test
now requires a nonempty marker and actual answers, with empty-marker/empty-answer refusals.

The next independent audit found one remaining governing-control class: CI's inherited
environment could inject BASH_ENV at workflow level or on a designated build/test step,
making Bash return success before executing the intended command. Those three real bundles
were accepted at 0863170. The third attempt forbids workflow environment entirely, including
case variants, while the closed checks-job shape already forbids job environment. Each
designated step now has only required text run and optional text name; no extra execution
metadata is admitted. Every designated build/test step has an environment refusal control,
with hook/NODE_OPTIONS/harmless/empty/case variants at the governing levels and positive name
and mapping-order controls. All three reproduced bundles now refuse with ci.schedule.
No production workflow bytes or generic placement rules change.

The completed second remote review also found indexed updater-token consumers and vacuous
merge-identity controls. The same third-attempt batch replaces the updater's dotted reference
count and dynamic step searches with a complete fixed owned-root comparison. The reviewed
literal preserves its root/job fields and all four ordered steps, including cfg's exact run
and environment, three configuration gates, mint inputs, checkout and rebase token bindings.
Extra or modified root/job/step fields cannot relocate indexed, aggregate or mixed-case
references. That attempt retained generic mint checks for other workflows; #474 closes that caller admission as described below. Kernel and actual-bundle
controls cover the three spellings across metadata, environment, outputs, configuration,
mint/checkout inputs and an extra step; mapping reorder remains accepted.

Separate wrong-PR and wrong-head cases now use a real merge plan and valid reads. The wrong-PR
case also supplies the complete alternate PR read triple, preventing a downstream digest IO
failure from masking a deleted identity comparison. Both actual copied-script comparison
deletions fail exactly their own new case while the other case remains green. Production
handoff logic is unchanged.

The full review of e790a9e found a producer/consumer count mismatch: decide could hand off
more than 100 answers while report refused the entire list, including the planned-merge
outcome. The fourth attempt adds the existing report limit to decide's array filter, before
any workflow outputs are written. Its byte and shape checks remain. Valid merge fixtures with
100 and 101 unique, report-shaped answers are both below the byte cap: 100 is handed on;
101 refuses without outputs. Removing only the count guard admits 101 and fails only that
boundary test. Two local-completion checkboxes are also unchecked and name the read-only
UID-map limitations; successful e790 CI is explicitly separate from local results.

The remaining individual Land secret-guard mutation coverage is tracked in #466 m1. Existing
native cases establish complete-bundle refusal, rather than independent sensitivity for each
redundant guard. Isolated public-topic fixtures can exercise otherwise-masked paths; they remain
a follow-up. The current full bundle has no accepted bypass, as the independent Opus review
also reports. No guard is reordered or weakened for label coverage. #466 m2 remains #453's
separate policy scope, and publication-status wording is updated in the PR body.

### Mint authority repair (#474)

The runtime dependency audit supersedes the earlier no-bypass assessment: v1.12.0's bundled
collector ignores canonical hyphenated permission inputs, and additional callers can select
permissions through undeclared underscore inputs. Existing finite production schemas already
refuse environment additions; that does not restore the dependency's missing narrowing.
The bounded design and validation live in `GA-Q3-mint-authority-repair.md`.

All three mints and exact typed expectations now select stable Node24 v3.3.0 at
`64ab729a6294000f5aa4a4bc0b73d1f32bc45510`. AppTokenPins takes named Land, Protection and
updater documents plus the complete unprivileged inventory. Its sound contract and Pins's
composed consequence require zero mints in CI, owner-ping and all additional workflows.
Existing complete finite contracts, old refusals and safe-format controls remain. This
explicitly closes the former generic mint admission; a fourth caller needs a reviewed finite
contract. #466 m1 stays deferred, and prospective shadow prerequisites remain unresolved.

### Complete old-to-new assertion map

The source anchors below refer to parent head 29809c6, before this migration. Adjacent assertions
protecting one property are grouped; every YAML-facing assertion has a new topic below.

#### land-protection.test.sh

| Anchor | Existing assertion / intended property | Decoded migration target |
|---|---|---|
| 110–113 | `steps_of`, `block`, `if_of`, `on_of` cut source by indentation | Delete when all callers use the decoded document. |
| 115–125 | Entire named mint step exactly matches name, id `app`, pinned create-app-token action, app-id expression, private-key expression, administration `read` | Exact mint-step subtree, excluding formatting/comments. |
| 126 | Exactly one `permission-` occurrence in workflow | Exactly the one permitted permission input at mint.with.permission-administration; reject extras elsewhere. |
| 127–128 | No skip-token-revoke, owner or repositories inputs | Absence of these mint inputs/extra scope. |
| 129–131 | Only secret is PR_UPDATER_APP_KEY and it appears once, in mint | Decoded secret occurrences plus exact permitted path. |
| 132–134 | steps.app.outputs.token appears once and only as GH_TOKEN of the read step | Exact env path/value and occurrence conservation across decoded leaves. |
| 135 | No github.token/GITHUB_TOKEN/id-token/write | Search decoded text/keys as appropriate, not comments. Keep permission-field semantics explicit. |
| 136–139 | Top-level permissions is `{}`, exactly two permissions blocks, only job permission is contents read | Exact top-level empty-map scalar plus exact read-job permission subtree; refuse additional permission nodes. |
| 140 | Read job environment is trusted | jobs.read.environment exact value. |
| 141–143 | Land decide has no secret/app-token/key/environment/id-token/write, but has actions read | Inspect decoded decide subtree and its permissions, preserving read-only producer separation. |
| 147 | Exactly one protection job | Exact jobs inventory `[read]`, including quoted keys. |
| 148–150 | Uses are exactly checkout, create-app-token, upload-artifact at pinned SHAs, in order | Ordered uses/steps inventory. |
| 151–154 | Checkout exact pinned action and persist-credentials false | Exact checkout subtree (no extra checkout inputs). |
| 155–158 | Only run command is land-protection.sh with repository/temp args; no block run | Exact decoded run text and single-line condition if this remains policy; decoded structure does not inherently preserve scalar style. |
| 159 | No GitHub event expression | Decoded string values, with parser expression conservation covering key/comment disguises. |
| 160–163 | Steps intended order checkout→mint→read→upload | Assert decoded step indices/shape; current line-number/sort equality does NOT prove that order, see gotchas. |
| 164–170 | Upload exact pin and name/path/if-no-files-found:error/retention-days:1 | Exact upload subtree. |
| 182 | Protection workflow `on` source block equals land `on` source block | Structural equality of complete decoded `on` subtrees. |
| 183–184 | Nonempty read condition equals first land condition (decide) source block | Exact normalized decoded conditions or complete canonical equality. |
| 185 | No pull_request, pull_request_target, workflow_call or schedule events | Exact decoded event inventory, including quoted keys. |
| 190–191 | CI includes this exact test command | Unique CI run-step leaf and explicit postbuild ordering after migration. |

Outside YAML: lines 60–108 test production protection reader responses, failures, usage, environment and single-route behavior. Lines 114,171–178 inspect the shell reader's joined source for exactly one bounded read-only gh route, no write/pagination flags, and no curl/wget/git. Lines 186–188 inspect snapshot-fetch source for artifact naming, ZIP entry, workflow route/path pins. Preserve these independently; L4YAML does not parse shell source.

#### land-decide.test.sh

| Anchor | Existing assertion / intended property | Decoded migration target |
|---|---|---|
| 364–367 | `job_block` + awk extracts decide, job if, permissions | Direct decoded decide subtree. |
| 371 | Top-level permissions `{}` | Typed empty-map leaf. |
| 372–376 | Exactly one decide permission block, present, all entries read | Exact permitted permission map / exhaustive read-only values. |
| 377–378 | No write/secret/environment/app-token/key/id-token in decide | Decoded keys/text in decide subtree. |
| 379–381 | github.token used once and only as Decide-step GH_TOKEN | Exact path/value plus exhaustive occurrence check. |
| 382 | Checkout persist-credentials false | Checkout input at the correct step. |
| 383–385 | Uses inventory exactly cache/restore@v4, checkout@v4, upload-artifact@v4 (set, currently mutable) | Exact uses inventory; action-pin blocker is separate recorded issue #167, but expected pins must update if addressed in this work. |
| 386–392 | Run sequence exactly t0 echo; install-elan; install-toolchains; lake build mitos-gate; land-decide command | Ordered decoded run values, not line starts. |
| 405 | Workflow has no direct `gh` | Decoded executable/text values as policy; comments should not count. |
| 426–431 | Decide condition contains five safety terms | Exact decoded condition is stronger than substring presence; at minimum don't lose any term/Boolean linkage. |
| 433 | No workflow-level concurrency | Absence of top-level concurrency subtree. |
| 434–436 | Decide concurrency group land-decide + cancel-in-progress false | Exact decoded concurrency subtree. |
| 437–438 | No inline expressions in run, no multiline/block run | Existing placement already covers expression rule X; retain single-line decoded run restriction if intended. |
| 439–443 | Every GitHub event expression is a LAND_EVENT_[A-Z]+ env entry of the Decide step, matching undecoded source regex | Exhaustive decoded event-reference paths, exact expected expressions/env names; reject event data in another job/site. |
| 444 | Real workflow placement passes | Keep existing proved placement call and all controls from #455. |

Outside YAML: 393–404 and406–408 inventory production land-decide.sh source and observed stub calls (two bounded reads, no write flags, curl/wget or other git); final timeout check also remains source scanning. The hundreds of preceding script-response assertions remain runtime tests. Existing placement fixture suite (post445) must remain intact.

#### land-apply.test.sh

| Anchor | Existing assertion / intended property | Decoded migration target |
|---|---|---|
| 170–171 | Apply block contains nonempty-plan term | Exact jobs.apply.if check; avoid duplicate policy copies. |
| 362–365 | Exactly one workflow trusted environment and it belongs to apply | Enumerate all job environment leaves and require only apply=trusted. |
| 366–369 | Main-ref, first-attempt, nonempty-plan terms plus concurrency group/cancel values appear somewhere in apply | Compare complete normalized apply condition to agreed conjunction; exact concurrency map. This closes known OR/comment bypass. |
| 370–373 | Apply permissions exact contents/pull-requests/issues read | Exact decoded permission subtree. |
| 374–382 | Entire mint (id app, condition env.LAND_MERGE == on, pinned action, key/app-id, only contents/workflows write) | Exact decoded mint subtree; locate by unique id or supported selector, reject duplicates. |
| 383–386 | App-token reference only once as LAND_MERGE_TOKEN; GH_TOKEN uses github.token | Exact execution-step env bindings plus exhaustive token-reference locations. |
| 387–391 | Checkout exact immutable action, sparse .github/scripts, credentials false | Exact decoded checkout subtree. |
| 392–393 | Apply has no lake/install/cache/github.event | Decoded apply leaf/text inventory, including aliases/escapes already refused by reader. |
| 394–397 | LAND_MERGE appears once and top-level value is on | Exact top-level env switch; reject duplicate/overriding switch keys anywhere else. |
| 398–399 | Apply receives requires_spec from decide output | Exact env binding LAND_REQUIRES_SPEC. |
| 400–401 | CI runs apply test | Unique run-step and postbuild order. |

Outside YAML: runtime apply/digest/identity/transport tests remain. Source checks at340–358 prove three bounded gh sites, one PUT, forbidden merge methods/routes and recursive alternate-route inventory; token-file scanning at332–337 also remains source/filesystem behavior. At 29809c6 the inventory missed gh-pr-merge/GraphQL/auto-merge forms (#341 item1). This round fixes those with separate source-pattern controls, preserving exclusions and error handling; YAML decoding alone does not establish that source property.

#### land-report.test.sh

| Anchor | Existing assertion / intended property | Decoded migration target |
|---|---|---|
| 305–308 | Report permission map exactly contents read + pull-requests write | Exact decoded subtree. |
| 309–310 | No secrets/environment/app-token/key/concurrency | Forbidden decoded keys and references in report subtree. |
| 311–315 | Checkout pinned + sparse scripts + credentials false | Exact decoded checkout subtree. |
| 316–317 | GH_TOKEN equals github.token, and workflow-token mention occurs once in report | Exact step env binding and exhaustive occurrence count. |
| 318–319 | CI runs report test | Unique run-step and postbuild order. |

Outside YAML: report outcome, dedupe, marker, actor authentication, read/post failures, answer shape/count, and changed-body behavior tests stay. The `why-codes-are-worded` group inspects apply.sh source with sed; it is not YAML.

#### app-token.test.sh

| Anchor | Existing assertion / intended property | Decoded migration target if helper is removed |
|---|---|---|
| 23–30 | awk inventories all create-app-token uses in all workflow jobs; requires at least one | All-workflow decoded mint-step inventory, with workflow/job/step coordinates. |
| 33–37 | Every mint uses 40-hex immutable action SHA | Decoded uses values with action identity and SHA grammar. |
| 40–50 | Every mint has explicit supported permission inputs; every permission input is under with, read/write only | Exact input paths, nonempty permitted permission subset, no permission-looking extras at other sites. |
| 51–54 | No skip-token-revoke, owner or repositories | Forbidden mint input names. |
| 57–62 | Each mint job has exactly one trusted environment line | Exact mint-owner job.environment=trusted. |
| 65–71 | Updater has one mint, exact contents/pull-requests/workflows write inputs | Decode update-prs rebase subtree, enforce mint cardinality/permissions. |
| 72–77 | Updater key/app-id/checkout token/GH_TOKEN bindings exact | Correct decoded steps and input/env bindings, not arbitrary lines. |
| 78–79 | Updater checkout uses immutable SHA | Decoded checkout uses. |
| 80–81 | CI runs app-token test | Unique run-step and postbuild order. |


Protection rows map to ProtectionPins plus LandPins's producer boundary; decide/apply/report
rows map to LandPins; every CI-presence row maps to CiPins; all app-token rows map to
AppTokenPins. Exact field/step sets also close formerly vacuous empty/extra-node cases. The
old tautological physical-line order check becomes exact decoded step order. The source scans
listed outside YAML remain source checks. No raw YAML scanner or compatibility wrapper stays.

## Validation

At e790a9e, the native 182-job gate build and five caller suites pass: protection 6 groups,
decide 27 (including all 37 placement refusals), apply 41 (including the source-route controls),
report 20, and app-token's complete native bundle wrapper. This remains evidence for the
unchanged gate/workflow inputs. The count-bound correction separately passes decide 29 groups,
report 20, shellcheck and the targeted count-guard deletion test; new-head CI is still required.
The native pin driver
now passes 210 checks: 185 functional/IO/usage cases and 25 whole-bundle calls used for timing.
The 50 second-attempt and 69 third-attempt functional cases cover the review findings and
relocation/governing-control audits. At the initial
published head, five runs of five complete invocations took 0.574, 0.740, 0.559, 0.580 and 0.605
seconds. Later runs are not a controlled performance comparison. No CI performance claim
is inferred.

The inherited reader suite passes 147 fixtures, 35 structure cases, 37 line-work cases and
seven live PyYAML comparisons; placement passes 52 mutations against two land workflows and
ten accepted controls. The normalization's 700 seeded differential controls produce 250
accepted/equal and 450 refused, and the independent oracle self-test passes 28 checks.
The second attempt reruns the affected shell suites, native mutations, shellcheck, imports
(0 violations), the 207-declaration lock, CI trust and cache-key controls. New policy proof
axiom checks, including the concrete CI-condition consequence, use only the three standard
axioms. Initial actionlint, reader/oracle and placement evidence above remains applicable;
this attempt changes no workflow or reader bytes.

Local core checking, paranoid comparison and honest ToyRequire acceptance were attempted;
all stop at the environment's read-only UID map. The lint suite passes 184/190 cases, with
six subprocess/namespace cases blocked by the same condition. The actual complete cheat
command was also attempted; its children produce NO-VERDICT because unshare cannot open
/proc/self/uid_map. Sandboxing stays enabled. These blocked checks require final-head CI;
they are not reported as local passes.

The no-comments pass removed three dead SC2016 directives and one visible-code narration
sentence (four complete line deletions and one trimmed line); required literal-expression suppressions and the external trusted-branch rule stay.
No reshape/encoding flag was raised. Initial-head CI passed, but the confirmed remote review
findings supersede its supplemental PASS; that head is held. The second attempt needs fresh
exact-head CI, CodeRabbit and supplemental verification, recorded in the PR body after
publication. The initial clean rebase from 29809c6 onto main679cc99 produced
7488ddc with no conflicts and identical verbatim feature patch ID
`3a71c2dd8389e88e5e2ab053a5095f7c8382c62c`; no prior checks were dropped.
The second attempt rebases all 12 feature commits cleanly onto newer main 8f8c5a4 with
no conflicts. Its verbatim feature patch ID is unchanged across that rebase:
`525f6a1d25529386dbcc90f61e30b01a47833fa5`. The upstream package-lock implementation and
process/check-matrix changes are preserved; the final build and affected checks run on that base.

The local requested Opus runner is unavailable. A separate Opus-xhigh review of initial
1082074 posted a PASS and tracked the remaining gaps in #463; this attempt fixes those gaps
and requires a fresh verdict for its changed content. The supplemental counterexamples and
the initial CI result remain historical evidence, not current-head approval. CodeRabbit CLI
version and login fail with EROFS creating ~/.coderabbit; remote PR review is separate. The
owner merges trusted paths after the remaining evidence and prerequisites hold.

The second-attempt no-comments delta passes with no source comment changes, dead suppressions,
reshape/encoding flags or open constraints. The obsolete helper is also removed from P1-020's
touches list. The closed Land root key set refuses the formerly unpinned Concurrency spelling.
The third-attempt delta also passes with no added source comments, suppressions, flags or
open constraints. 0863170's supplemental verdict is FAIL for the reproduced inherited-env
class; its later review additionally identified the updater and identity-test gaps. Its
CI/review results do not approve this correction's new content.
