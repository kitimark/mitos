# Pin hand-written spec theorem names

phase: 3
goal: The statement lock lists hand-written spec names such as eq_of_id, match_foo, and proof_of_x.
statement: none (gate tooling)
touches: gate/MitosGate/Lock.lean, gate/MitosGate/LockCases.lean, gate/MitosGate/LockFixture.lean, gate/LintTest.lean, statements.lock, this task, its run record
must_not_touch: core/ source, models.lock, eval/cheats/, plan/, workflow and rule files
checks: build, imports, lock, lint-test, core check, paranoid comparator, accept-toy, cheats
budget: 12 iterations, 2 hours

## Design

The owner-selected design is [issue #374](https://github.com/kitimark/mitos/issues/374).
`isGenerated` takes the imported environment. Equation names use Lean's reserved-name predicate.
Matcher names use their own module's serialized matcher entries. For equation names under a
matcher, that metadata takes precedence over the reserved-name predicate, and only an
`eq_<digits>` suffix is generated. Other equation names use Lean's reserved-name predicate.
An existing equation declaration must also reference its owner in its type. A hand-written
theorem declared before that owner cannot reference it, even when the declarations come from
separate modules. An absent reserved name remains a generated-name probe.
Only a nonempty decimal suffix follows `proof_`.
`generatedSuffixes` stays unchanged. Imports keep extensions unloaded and initializers disabled.

With extensions unloaded, Lean's reserved-name predicate treats a matcher as an ordinary safe
definition and reserves `eq_def` and `eq_unfold`. Matcher metadata must therefore decide those
names before that predicate runs.

`LockFixture` supplies hand-written names and forces Lean to emit equation theorems through named
theorem references. `LockCases` imports that compiled fixture through `Lock.importRoot`, so the
guards use the same unloaded-extension environment as the lock command. It imports only `Init`
and generates its own compound-pattern and nested matchers, so the standalone lint target needs
no Core import or Core build output. Existing generated equation theorems and absent reserved
equation names have separate guards. Compiled hand-written `match_1.eq_of_id`, `match_1.eq_def`,
and `match_1.eq_unfold` mention the matcher in their types and stay listed. Assertions preserve
those owner references and the unloaded reserved-name results, so the new type condition cannot
mask a broken matcher-priority rule. Ordinary `equation.eq_of_id` also mentions its owner.
The early ordinary and matcher equation fixtures precede their owners and stay listed.
The `proof_2` fixture checks the deliberately lexical rule.
It does not claim that Lean generated that declaration. `proof_` and `proof_2x` stay listed.
The existing lint-test executable builds these guards in CI.

Residual: a hand-written declaration whose final component is in `generatedSuffixes`, such as
`X.ofNat` or `X.inj`, remains unlisted. The spec path approval rule still covers those edits.
[Follow-up #415](https://github.com/kitimark/mitos/issues/415) tracks that gap.
A hand-written `proof_2` also remains unlisted under the intentional lexical `proof_<digits>` rule.

## Verification

- The new lock command fails on the old lock and reports only `Mitos.WellFormed.eq_of_id`.
  Regeneration adds exactly that line. The regenerated lock passes with 207 declarations.
- In a scratch copy of core, changing the theorem's conclusion to `id (a = b)` preserves its
  proof and callers but changes its declared type. Rebuilding core and checking the lock changes
  only the theorem's hash and fails, as required.
- The classifier guards build. `lake build` and the import check pass.
- Compiled hand-written theorems under a real matcher fail the old classifier and pass the
  final classifier for `eq_of_id`, `eq_def`, and `eq_unfold`. The last two remain reserved names
  in the unloaded environment, so the regression also checks matcher metadata takes precedence.
- Round 3 reproduces both early-name gaps with actual compiled declarations in the same file
  and in sibling modules. The owner module does not import the sibling theorem module. The
  previous classifier omits all four theorems and accepts their changed statements. The fixed
  classifier lists all four and rejects the same statement mutations. The committed early-name
  guards fail the previous classifier, and all nine targeted classifier mutants are killed.
  Across the existing 611 core constants, classification is unchanged from round 2.
- The forbidden fixture import reproduces one import violation. The self-contained fixture
  passes `imports`, all 59 import shell tests, and its guards with Core omitted from `LEAN_PATH`.
- `lake exe mitos-lint-test` passes all 190 existing runtime cases. The cheat corpus passes
  all 50 cases in both full and comparator modes. The honest toy passes all seven gates with
  paranoid kernels.
- `lake check` and `lake comparator --paranoid` pass. On this cloud host, the supported
  `COMPARATOR_BWRAP` override adds a temporary filesystem at `/run` before the existing sandbox
  mounts, because `/run/user` does not exist. All original sandbox arguments remain intact.
  This adaptation is outside the repository. GitHub CI uses the normal sandbox command.
- The requested no-comments pass deletes zero comments and reports no flags or open constraints.

## Review boundary

This PR changes trust-critical gate code and the statement lock. The owner applies
`spec-approved` and decides the merge. An Opus verifier remains required by the repository's
process; this Codex environment cannot spawn Opus. CodeRabbit CLI authentication is unavailable
in this environment. Its GitHub review is checked separately.
