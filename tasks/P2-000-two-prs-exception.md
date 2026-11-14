# tasks/P2-000-two-prs-exception.md

phase: 2
goal: `docs/process.md`, "Two PRs per feature: statements first", records that P2-001a and P2-001b each land as one spec PR that carries its implementation and proofs, and says why.
statement: none (process task: one paragraph of prose, no Lean)
touches: docs/process.md (the section "Two PRs per feature: statements first" only, one new paragraph at its end) · tasks/P2-000-two-prs-exception.md · .claude/scripts/plan-tasks.pending (the one line `P2-000` deleted, only in the PR that adds this file to `main`) · ops/runs/<UTC date>/P2-000-builder-<attempt>.json
must_not_touch: every other line of docs/process.md, statements.lock, models.lock, core/, gate/, eval/, examples/, .github/, plan/, CLAUDE.md, .cursor/, every other line under .claude/
checks: section-only diff, verbatim paragraph, plan-tasks, runlog, claim checks C1 to C6, no session link (commands under Design, "Checks the builder runs"); CI `gate` green at the head. No Lean line of the matrix: the diff touches no `.lean`, lakefile, lock, workflow or gate file
budget: 3 iterations · 1h wall · 300k tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-000 in `plan/phase-2.md`, issue #202, wave W1. It waits only for the plan's merge
  (#159, merged) and lands before P2-001a (#203). The owner merges it: `docs/process.md` and
  `.claude/` are paths the owner keeps.
- Source: the plan's scope decision "Each spec PR carries its implementation and proofs", which
  names this row as the one that records the exception, approved with the plan. The owner's
  decisions on #156 ([comment](https://github.com/kitimark/mitos/issues/156#issuecomment-6795388085))
  took the architect pass's task table, whose row "P2-002, 003, 004: merge into 001a and 001b"
  gives the reason: a spec PR carries its impl and proofs, or the comparator goes off.
- Facts on `main` (e5bd16c) the paragraph rests on: claim checks C1 to C6 under Design.
- #101's spec PR (f225ac6) already carried restated proofs with its spec. The plan does not name it
  as an exception, and this row does not either (see `deferrals`).
- Open PR #124 edits `docs/process.md` in the gate table and the paragraph after it (around lines
  179 to 200), not this section, so the two do not overlap.
- #160's items belong to P2-001b, P2-008, P2-010 and the owner; none touches this row.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. The paragraph below is the exact text, and "Where it goes" names its place by
heading and anchor lines. There is no Lean to type-check; the claim checks C1 to C6 stand in for
fixtures, one per factual sentence.

revisit_when: none. If `plan/phase-2.md` renames, splits or drops P2-001a or P2-001b before this
merges, re-check the paragraph's first sentence against the plan's Tasks table.

modules:
- `docs/process.md`, section "Two PRs per feature: statements first": one new paragraph, 10 lines,
  at the end of the section. Copies the layout of the paragraph above it ("A spec PR changes
  `statements.lock`, ..."): plain prose, no heading, no bullets, wrapped at 100 columns, paths and
  names in backticks.
- `tasks/P2-000-two-prs-exception.md`: this file; the builder ticks "Done when".
- `.claude/scripts/plan-tasks.pending`: the line `P2-000` deleted, in the PR that adds this file to
  `main`. `.claude/scripts/plan-tasks.test.sh` fails the tree if a listed row has a valid task file.
- `ops/runs/<UTC date>/P2-000-builder-<attempt>.json`: one record per attempt.

types: none.

statements: none locked. The paragraph sets one process rule in five parts:
- R1, scope: P2-001a and P2-001b only.
- R2, shape: each lands as one PR with the spec change, the implementation, the proofs and every
  other file the change breaks (for P2-001a that includes P2-005a's mutant migration and
  `eval/score/Score.lean`).
- R3, still a spec PR: it needs `spec-approved`, and the owner reviews its spec files, the paths
  the paragraph above lists.
- R4, statements apart from proofs: the PR body names each statement that differs from the row's
  task file as it is on `main`, or says that none does. The task file on `main` counts because the
  row's PR may edit its own task file.
- R5, checks: Lean and the comparator check the rest at the same merge.

reuse: the section's own terms ("spec PR", `spec-approved`, and "the paths above" for the spec
files the paragraph before it lists); the `statements:` field of the Design block in
`tasks/TEMPLATE.md`, which R4 diffs against. No new term.

fixtures: the claim checks. Each is one sentence of the paragraph and the command that confirms it
on `main`; a verifier re-runs them.
- C1 "Both change `Edge`": `plan/phase-2.md`, Tasks: P2-001a makes `Edge.key` a `Derivation`;
  P2-001b adds `Edge.through`, a field of `Edge` in the #156 sketch
  ([comment](https://github.com/kitimark/mitos/issues/156#issuecomment-6795051235)).
- C2 "which `Mitos.Impl.*`, `Mitos.Proofs.*`, the scorer and the mutants use":
  `git grep -l -w Edge origin/main -- core/Mitos/Impl core/Mitos/Proofs eval/score eval/mutants`
  lists files in all four (at e5bd16c: 2, 4, 1, and 16).
- C3 "so the spec change alone does not build": `core/lakefile.toml` has
  `defaultTargets = ["MitosCore", "MitosImpl"]`, and `MitosImpl` globs `Mitos.Impl.+` and
  `Mitos.Proofs.+`, so `cd core && lake check` builds the implementation and the proofs.
- C4 "CI skips `lake comparator` while `core/Mitos/Proofs/Resolver.lean` is missing":
  `.github/workflows/ci.yml`, step "Core implementation proves the approved Challenge", runs
  `if [ -f core/Mitos/Proofs/Resolver.lean ]` and otherwise prints "No implementation yet".
- C5 "Phase 1's spec could land first because no implementation existed yet":
  `git log --diff-filter=A --format='%h %s' origin/main -- core/Mitos/Proofs/Resolver.lean` gives
  86b34ac (Phase 1 implementation), which came after 241b7e4 (Phase 1 spec), the commit that added
  the skip of C4.
- C6 "it needs `spec-approved`": the step "Spec changes need the spec-approved label" in
  `.github/workflows/ci.yml` matches `^core/Mitos/Core(/|\.lean$|$)`, `statements.lock`,
  `^core/Challenge/` and `^core/comparator\.json$`, which are in the Owns cells of P2-001a and
  P2-001b.

cut_line: ships the paragraph, this task file and the pending-list line. It leaves as they are the
section's diagram, its bullets and the paragraph above, the Roles paragraph of `docs/process.md`,
`CLAUDE.md`, `.claude/skills/kitimark-mode/SKILL.md`, `.cursor/` and every CI step. It does not
widen the exception beyond the two rows.

deferrals:
- To P2-001a (#203) and P2-001b (#204): their task files give the exact statements in `statements:`
  at build depth, so R4 has a fixed text to diff against, and each PR body carries the R4 line.
- To the owner, not to a row: whether the exception should be a general rule ("a spec PR whose
  change breaks the implementation's build or adds a Challenge line carries its proofs"), as
  #101's spec PR (f225ac6) already did. If the owner wants it, it becomes a `process` issue.
- From #160 and the #156 sketch: nothing.

owner_decisions:
- The plan's scope decision "Each spec PR carries its implementation and proofs" (merged in #159):
  the exception holds "for P2-001a and P2-001b only", the owner still reviews the spec files of
  each PR, and P2-000 records it in `docs/process.md`.
- The owner's decisions on #156 (comment 6795388085): the task order and the architect pass's task
  table, which merged P2-002 to P2-004 into P2-001a and P2-001b.
- Not yet decided: R4 is this design's addition, not the plan's text. The owner keeps it or drops
  it when reviewing this row's PR; dropping it deletes the paragraph's second-to-last sentence and
  the first deferral.

### The paragraph (verbatim)

```markdown
Two rows are the exception: P2-001a and P2-001b of `plan/phase-2.md`. Each lands as one PR that
carries its spec change together with the implementation, the proofs and every other file the change
breaks. Both change `Edge`, which `Mitos.Impl.*`, `Mitos.Proofs.*`, the scorer and the mutants use,
so the spec change alone does not build. Phase 1's spec could land first because no implementation
existed yet, and CI skips `lake comparator` while `core/Mitos/Proofs/Resolver.lean` is missing. Now
a spec-only PR could pass `gate` only by deleting the implementation, which also switches the
comparator off. Each row's PR is still a spec PR: it needs `spec-approved`, and the owner reviews
its spec files (the paths above). Its body names each statement that differs from its row's task
file on `main`, or says that none does, so the owner sees the statements apart from the proofs. Lean
and the comparator check the rest at the same merge.
```

### Where it goes

In `docs/process.md`, section "### Two PRs per feature: statements first", as its last paragraph:
after the paragraph that starts "A spec PR changes `statements.lock`" and ends "and so does a path
with non-ASCII characters.", and before the heading "### The task file". One blank line on each
side. The diff is 11 added lines (the paragraph and one blank line) and no removed line.

### Why it weakens no check

- No check changes. The diff touches no workflow, gate, lock, lakefile or Lean file.
- The label check still fires. Each row's PR touches the spec paths of C6, so CI fails it without
  `spec-approved`, and the owner merges it.
- More runs, not fewer. `cd core && lake check` and `lake comparator --paranoid` run at the head of
  each row's PR, so the new statements are proved at the merge that adds them. Two PRs would need
  a spec PR that passes `gate` only with the implementation deleted, and the comparator step then
  takes its skip branch (C4) until the implementation PR lands.
- The two-PR rule's purpose holds. It keeps statements fixed before and apart from the proofs, so a
  builder cannot fit a statement to a proof. Here the statements are fixed in the row's task file
  before the builder starts, R4 names every departure in the PR body, and the counterexample exit
  (`docs/process.md`, "Rules for the inner loops") still forbids rewriting a statement to make a
  proof go through.
- The scope is two rows. Every other PR keeps the section's default and the review rule in the
  paragraph above ("keeping spec changes out of impl PRs is a review rule").
- The merge rule is unchanged. Each row's PR needs `spec-approved`, so it is trust-critical and gets
  an `opus` verifier at `xhigh` or above (`.claude/skills/kitimark-mode/SKILL.md`, Verdicts).

### Usage (reader's view)

- The P2-001a builder reads the section, opens one PR with the spec files, `Mitos.Impl.*`,
  `Mitos.Proofs.*`, P2-005a's mutants and `eval/score/Score.lean`, and writes in its body
  "Statements that differ from `tasks/P2-001a-<slug>.md` on `main`: none" or a list of them.
- The owner opens that PR, reads the spec paths (`statements.lock`, `core/Challenge/`,
  `core/comparator.json`, `core/Mitos/Core/`), checks the body's line against the task file, and
  adds `spec-approved`.
- A verifier of that PR compares the body's line with the diff between the PR's spec files and the
  task file's `statements:` on `main`.

### Alternatives considered

- **A general rule** ("a spec PR whose change breaks the implementation's build carries it").
  Truer to what #101's spec PR did, but wider than the owner approved ("for P2-001a and P2-001b
  only"). Left to the owner (`deferrals`).
- **Two PRs with the comparator off between them** (the implementation deleted or stubbed in the
  spec PR). Weakens a check for the length of the gap; the plan rules it out.
- **Two stacked PRs, the spec PR at the bottom.** The spec PR's own head never builds, so it can
  never have the green `gate` and the verdict at its head that the merge rule asks for.
- **The owner reviews the PR's first commit, which holds only the spec.** Fix-ups and rebases move
  statement edits into later commits. The task file's `statements:` is fixed before the builder
  starts and is read from `main`, so a diff against it stays meaningful.
- **A third column in the diagram, or a `###` heading.** The diagram shows the default; a column
  for two rows makes it harder to read. Ten lines need no heading, and the Owns cell names the
  section, so the paragraph stays inside it.

### Checks the builder runs

From the worktree root, after `git fetch origin main`. No Lean build: nothing in the diff is read
by one.

1. Only the section changed, by 11 added lines and none removed. This prints `11 0`:
   ~~~sh
   git diff --numstat origin/main...HEAD -- docs/process.md | awk '{print $1, $2}'
   ~~~
2. The paragraph sits inside the section. This exits 0:
   ~~~sh
   git show HEAD:docs/process.md | awk '/^A spec PR changes /{a=NR} /^Two rows are the exception: /{c=NR} /^### The task file$/{b=NR} END{exit !(a && a<c && c<b)}'
   ~~~
3. The paragraph is verbatim. This prints nothing:
   ~~~sh
   diff <(git show HEAD:docs/process.md | awk '/^Two rows are the exception: /{p=1} p&&/^$/{exit} p') <(awk '/^```markdown$/{f=1;next} f&&/^```$/{exit} f' tasks/P2-000-two-prs-exception.md)
   ~~~
4. The file list. `git diff --name-status --no-renames origin/main...HEAD` lists only
   `docs/process.md`, this file, `.claude/scripts/plan-tasks.pending` (only when this file is new
   on the branch) and the run-log record. For the pending list, this prints exactly `-P2-000`:
   ~~~sh
   git diff -U0 origin/main...HEAD -- .claude/scripts/plan-tasks.pending | grep -E '^[-+][^-+]'
   ~~~
5. `.claude/scripts/plan-tasks.test.sh` exits 0, and its first line is
   `ok   the tree: every linked row has a design or is pending`.
6. The run log. This shows only `A` lines:
   ~~~sh
   git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'
   ~~~
   `jq -e 'select(.task == "P2-000" and .role == "builder")' <record>` exits 0, and
   `wc -l < <record>` prints 1.
7. Claim checks C1 to C6 still hold at `origin/main`.
8. No session link. This prints nothing, and the same `grep` over the PR body file prints nothing.
   Run it as a command of its own: `.claude/hooks/check-no-session-link.sh` reads the whole
   command, and blocks one that also commits.
   ~~~sh
   git log --format=%B origin/main..HEAD | grep -E 'claude\.ai/code/session_|Claude-Session:'
   ~~~
9. In CI, `gate` is green at the head. The PR body says `Closes #202` and that the owner merges it.

## Done when
- [ ] the paragraph is in `docs/process.md` verbatim, where "Where it goes" says, and nothing else
      in the file changed
- [ ] all `checks` pass locally ("Checks the builder runs", 1 to 8), and `gate` is green at the head
- [ ] `P2-000` is gone from `.claude/scripts/plan-tasks.pending` if this file lands in this PR
- [ ] no `sorry`, no new axioms (nothing in Lean changes)
- [ ] run-log record written (ops/runs/)
