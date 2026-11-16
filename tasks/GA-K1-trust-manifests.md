# GA-K1: keep the judging manifests with the owner

phase: gate architecture
goal: Changes to the root and core Lake manifests require the owner's merge and trust-critical review.
statement: none (tooling task)
touches: .claude/skills/kitimark-mode/SKILL.md, gate/MitosGate/Land.lean, .claude/hooks/pr-state.sh, .claude/hooks/pr-state.test.sh, .github/CODEOWNERS
must_not_touch: statements.lock, models.lock, core/, eval/, examples/, .github/scripts/ci-trust.sh, plan/
checks: build, land-test, pr-state-test, gh-api-rest-test, sourced-bash-test, imports, lock, core-check, comparator-paranoid, lint-test, accept-toy, cheats
budget: 20 iterations · 2h wall
escalation: split → revisit the issue

## Context

[Issue #368](https://github.com/kitimark/mitos/issues/368) records the owner's decision to protect both judging manifests before adding a library.
The root manifest selects dependencies for the gate and root core build.
The core manifest selects dependencies for `cd core && lake check` and `lake comparator`.

## Design

The short path applies because [#355](https://github.com/kitimark/mitos/issues/355) and [#363](https://github.com/kitimark/mitos/issues/363) are open and their shared classifiers are absent at base `fea3fe6`.
The GA-K1 PR owner carries both exact names into those issues through linked comments.
The PR owners for #355 and #363 must retain them when migrating Land and the hook to the shared tables.

depth: build
revisit_when: #355 or #363 merges
modules:
- `Land.lean` classifies the two exact names as critical and kept. Its kernel fixtures pin both names and reject other package manifests and backup names.
- `pr-state.sh` keeps the same exact-name rule in jq. `pr-state.test.sh` tests both the review requirement and who may merge, including negative cases.
- `kitimark-mode/SKILL.md` defines which files the owner keeps. `CODEOWNERS` adds the root manifest. Its existing `/core/` rule covers the core manifest.

types: Existing path strings and Boolean classifications.
statements: `Fixture.trustFilesAreCritical`, `Fixture.nonJudgeManifestsAreNotKeptOrCritical`.
reuse: Existing exact-name lists, path fixtures, and the axiom scan in Land.
fixtures: The root and core manifests are critical and kept. The manifests under eval/score, eval/mutants, eval/diff, and examples/acme are neither, as are the two backup names.
cut_line: Protect exactly the two judging manifests. Leave SPEC_RE and dependency contents unchanged.
deferrals: Shared-table migrations belong to #355 and #363. Adding a library belongs to its own task.
owner_decisions: The owner selected both manifests as trust infrastructure in #368. The owner merges this rules and trust-infrastructure change.

## Verification

Before the implementation, the new hook cases report four failures, covering critical and kept for each manifest.
The hook's extracted jq definitions classify both manifests as neither critical nor kept before the change and as both after it.
The four package manifests remain neither in the live jq run.

This container's `/` and `/tmp` belong to uid 65534, while the task runs as uid 1000.
The existing hook-state path checks refuse that root because they trust only uid 0 or the current user.
The complete hook suite therefore also reports filesystem failures that precede this change.
An isolated filesystem was attempted with bubblewrap, but its uid-map setup fails on a read-only filesystem.
CI must supply the complete hook-suite result. No trust check was weakened.

The root's fresh Comment Sicko pass accepts the implementation diff with no new comments, zero deletions, and no reshape flags.
The implementation and this pass run on Codex. The required Claude Opus verifier is unavailable in this environment, so its review remains open.

## Done when

- [ ] Applicable checks pass locally or have a recorded environment limitation and a passing CI result.
- [x] Both classifiers and both rule locations protect exactly the two judging manifests.
- [x] The `/no-comments` pass has no open flags.
- [ ] Owner and CodeRabbit feedback is answered at the PR head.
- [ ] An independent verifier and the required Opus verifier review the final head.
