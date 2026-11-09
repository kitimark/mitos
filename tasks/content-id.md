# tasks/content-id.md

phase: 1
goal: A verdict carries across a rebase that changes nothing but `main`'s run-log lines around the PR, and never across a real change, by a content id whose decidable parts are proved in Lean.
statement: none (tooling task); theorems in `gate/MitosGate/ContentId.lean` and `gate/MitosGate/Carry.lean`, outside the lock
touches: gate/MitosGate/ContentId.lean, gate/MitosGate/Carry.lean, gate/Main.lean (the `content-id` and `carry` subcommands only), gate/content-id-test.sh, gate/carry-test.sh, .claude/skills/kitimark-mode/SKILL.md (the verdict-carry rule and its two references), ops/runs/2026-11-09.ndjson (appended lines only), tasks/content-id.md
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, docs/process.md, models
checks: build, imports, lock, lint test, runlog on this PR's run log, gate/runlog-test.sh, gate/content-id-test.sh, gate/carry-test.sh, shellcheck
budget: 20 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Issue #79, PR 1 of its sequence. The PR updater rebases every open PR when `main` moves. Of its
  19 rebases on PRs #61 to #86 up to 2026-11-09 09:25 UTC, the whole-diff
  `git patch-id --verbatim` changed on all 19, so every rebase needed a new verifier and a new
  merge command. The cause is `ops/runs/*.ndjson`: it is append-only with `merge=union`, and
  `main`'s new lines change the context lines of the PR's own run-log hunk.
- PRs 3 and 4 of #79 (the steward) compute this id with `main`'s build of the tool. PR 5 moves
  `docs/process.md` and the playbooks to it.
- It has no row in `plan/phase-1.md`, which the owner keeps.

## Decisions
- **A `mitos-gate` subcommand, not `.github/scripts/content-id.sh`.** The decidable parts are Lean
  (`RunLog.added`, `addedSorted?`, `occ`, `hunkMarker`, `normalize`, `isRunLog`, `diffHeader`), and
  the steward builds the gate for its own Lean decision anyway. Git is only called, never scripted.
- **The diff is normalized in Lean, not piped into `git patch-id`.** The tool drops `index` lines
  and rewrites hunk headers, and keeps every other byte. `git patch-id` would add three
  dependencies: its algorithm changed in git 2.39 for mode changes and binary files, it hashes
  with SHA-1, and it reads lines with `strlen`, so it cannot hash a NUL, which rules out `--text`.
- **Where a hunk applies is bound: the marker `@@ <k>` (round 2).** Round 1 cut each hunk header to
  `@@`, as `git patch-id` drops it. Then the same hunk text at two places of one file gave one id,
  such as `--paranoid` added to the copy of a block in `strict()` or in `lax()`. Now `k` counts
  how many times the hunk's old-side lines (context and removed lines) start earlier in the file's
  merge-base version (`occ`). The tool reads that version (`baseLines`), checks that the old side
  is at the place the header names, and refuses otherwise.
  - **Why this marker.** With the merge-base file it names the one place the hunk applies
    (`occ_inj`, `normalize_pos_ne`), so a given merge-base and id fix the head's file. It stays
    when `main` edits the file elsewhere: lines below the hunk do not count (`occ_append_right`),
    and lines above count only through the copies of the old side they hold (`occ_append_left`).
  - **Why not the line numbers.** They move whenever `main` adds a line above the hunk, which was
    the problem.
  - **Why not the count of copies only when there are several.** That id changes when `main` adds
    a second copy below the hunk. The verifier's rebase pair is that case: `main` added `lax()`
    after `strict()`. The plain count keeps it.
  - **Why not the base blob id.** Every `main` change to the file would change the id. This repo's
    busiest files are the ones both `main` and PRs edit.
- **`--text`.** Every file is a text diff, so attributes and `core.bigFileThreshold` cannot turn
  one into a binary patch, and a binary file's hunk lines are kept byte for byte.
- **Pinned options.** Every `git diff` option that the config can change is a flag. Config without
  a flag goes in with `-c`. `GIT_DIFF_OPTS`, `GIT_EXTERNAL_DIFF` and `GIT_ATTR_SOURCE` are removed.
  The test runs 32 config and environment variants (the three #79 names and 29 more, such as
  `diff.algorithm`, `diff.context`, `diff.suppressBlankEmpty`, `core.quotePath`, `diff.orderFile`
  and attribute drivers), and all give the plain id.
- **Replace refs and grafts are off (round 2).** `GIT_NO_REPLACE_OBJECTS=1` and
  `GIT_GRAFT_FILE=/dev/null`, so a clone's own `refs/replace/` or `info/grafts` cannot swap an
  object or a commit's parents. The test has a replaced blob, a replaced commit and a graft.
- **No pathspec.** The run logs are split out in Lean (`isRunLog`), with the same set as
  `.gitattributes` and `mitos-gate runlog`. The patch's file blocks are matched to the `--raw`
  listing by the exact `diff --git` line git prints (`diffHeader`), so a missing or extra block is
  refused. A pathspec would also match below a directory named `x.ndjson`, and
  `GIT_LITERAL_PATHSPECS` and its siblings change what one means.
- **A run-log change that is not append-only is refused, with no id.** #79 suggested falling back
  to the file's exact diff. CI's run-log check already fails such a PR, so a refusal loses nothing
  and leaves no second path to review. The file must be added or modified, with mode 100644 on
  both sides. A deletion, a type change or a mode change is refused, because `runs` lists only
  added lines and would not show it.
- **A missing final newline in a run log is bound (round 2).** `runs` writes `noeol` after a file
  whose head version ends without a newline, so `{"b":2}` with and without `\n` give two ids.
  Binding it, rather than refusing, keeps the tool's refusals to what CI's run-log check refuses.
- **Encoding.** `rest` is a 64-hex SHA-256, and each run-log path and line is written with its
  length first. The id is printed in full: 64 bits would allow a birthday collision between two
  crafted changes in about 2^32 hashes.
- **Merge-base.** Exactly one, from `git merge-base --all`; none or several is refused.
- **Stack depth.** `normalize` and `occ` run as tail-recursive loops, `normalizeTR` and `occTR`,
  through `@[csimp]` theorems that prove them equal, so a long file does not use one stack frame
  per line.
- **Printing.** Paths and git messages print through `oneLine`, with `##[` written as
  `##\u{005B}`, the legacy workflow-command marker #68 is about. When #82's `ciLine` lands, these
  lines can use it.
- **The rule (round 2).** The skill says to build and run the tool in a checkout of `origin/main`,
  never in the head being compared, because a head that edits the tool would compute its own id.
  It also says that ids from different builds are not comparable, and that a refusal means the
  verdict does not carry. "Only rebases" is back: the updater's rebase pushed the head, as its PR
  timeline shows, not a PR owner.
- **The whole push chain is bound: `mitos-gate carry` (round 3).** Round 2's rule checked only
  that the updater force-pushed the current head. The round-2 opus verifier's repro: an owner
  pushes V' on the verified head V, `main` adds a copy of a hunk's old side above it, and the
  updater rebases V' to X. X has V's content id, because the marker counts copies in each head's
  own merge-base, and X drops a check from another function. So a verdict now carries only when
  every push since the verified head is a force-push by `mitos-pr-updater[bot]`, the first from
  the verified head and each later one from the commit the one before it left, up to the current
  head, and the two heads have the same content id.
  - **Why the REST activity route.** It lists every push to a branch with its actor, `before` and
    `after`, plain pushes included. The PR timeline lists only force-pushes and only the commit
    after, so an owner's plain push leaves no trace there. On #83 the route shows the two plain
    pushes 484d0ec → 7f2a60a and 7f2a60a → 9833f36 that the timeline does not.
  - **Why a subcommand, not prose.** Encode Lessons in Structure: the rule was rewritten in each of
    three rounds, and each prose version had a gap. `mitos-gate carry <base> <verified> <head>`
    reads the route's TSV on standard input and decides the chain (`walk`, proved by `walk_iff`)
    and both content ids, with one build, in one call. Only its exit 0 carries, so a refusal of
    either id cannot be misread, and nobody compares ids from two builds. It is one module of about
    200 lines, docs, proof and examples included, beside `ContentId`, and it runs from `main`'s
    checkout like `content-id`.
  - **Why stdin, not a `gh` call inside the tool.** The tool stays offline and testable on fixed
    lists, and the skill names the one `gh` command that feeds it. A missing, reordered or partial
    list fails safe: every push must start where the one before it left, so a gap stops the walk.
  - **Why also `tip`.** `walk` from a head that is not the verified head already needs the newest
    push to end at the head. For the verified head itself, `tip` checks the branch is still there.
  - **Round budget (round 3).** An owner's rebase never carries a verdict now, a stack's restack
    included. It still does not count as a round when the new head keeps the content id of the
    head the round started from (with the parent branch as base in a stack). Counting it would
    use up a stack's two rounds on restacks alone, while the head gets a verifier either way.
  - **Stacks (round 3).** The updater skips every PR in a stack, so no stacked PR carries a
    verdict: a stack needs a verifier at every head after a restack. The skill says so.

## Theorems (`gate/MitosGate/ContentId.lean`)
- `RunLog.appendOnly_iff_perm_added`: `appendOnly base head = true ↔ head ~ base ++ added base head`
  (#79's statement, both ways), from `RunLog.count_added`.
- `RunLog.added_perm_of_perm_append`: `head ~ base ++ a → added base head ~ a`.
- `RunLog.sortLines_eq_of_perm`, `RunLog.addedSorted?_of_perm_append`: the run-log part depends only
  on which lines the PR adds.
- `RunLog.addedSorted?_union`: under the model of union at `RunLog.union_appendOnly`, a rebase keeps
  the run-log part.
- `RunLog.addedSorted?_eq_none_iff`, `RunLog.addedSorted?_edit`, `RunLog.addedSorted?_delete`: an
  edit or a deletion is refused.
- `occ_inj`: two places where a hunk's old-side lines start have different counts.
- `occ_append_left`, `occ_append_right`: the count splits at any line above the hunk, and ignores
  every line below its old side.
- `marker_inj`, `kind_marker`: the marker writes the count without loss, and is never a hunk line.
- `normalize_pos_ne`: two diffs of one base file that differ only in one hunk header, so that the
  same hunk lines apply at two places, normalize differently.
- `normalize_body`: the hunk lines of the normalized diff are exactly the diff's, byte for byte
  and in order.
- `normalize_ne`: replacing a run of hunk lines by other hunk lines at one place (an edit, an
  insertion or a deletion, whitespace included) changes the normalized diff, whatever the base
  files.
- `normalize_index`: an `index` line before the first hunk does not count.
- `kind_body`: a line that starts with a space, `+`, `-` or `\` is a hunk line.
- `occ_eq_occTR`, `normalize_eq_normalizeTR` (`@[csimp]`): the loops the tool runs equal the
  definitions above.
- Kernel-checked examples for `added`, `normalize` (a hunk moved down with a new base blob keeps
  its output; the same hunk at the first and the second copy of its lines gives `@@ 0` and
  `@@ 1`; a hunk that does not fit its base file is refused), `hunkOld`, `kind`, `isRunLog`,
  `diffHeader` (against git 2.43's output for a name with a tab, a quote, a backslash and a byte
  that is not ASCII) and `preimage` (with and without `noeol`).

## Theorems (`gate/MitosGate/Carry.lean`, round 3)
- `walk_iff`: `walk v h ps = true` exactly when the newest pushes `pre` of `ps` are all updater
  rebases and `pre.map after ++ [v] = h :: pre.map before`: the newest ends at `h`, each older one
  ends where the next one starts, and the oldest starts at `v`.
- `walk_rebase`: so every push `walk` crosses is an updater rebase.
- Kernel-checked examples: round 2's laundering chain (the owner's push, then the updater's) is
  refused; two updater rebases pass; an owner's force-push, a plain push by the updater's login,
  a gap, a list that ends before `v` and a branch made again are refused.
- Axioms: `propext` and `Quot.sound`.

## Limits
- A `main` change within three lines of a PR hunk changes the id, on purpose: the verifier read
  that context. So does a `main` change that adds a copy of a hunk's old-side lines above it,
  because the count moves. Both fail safe: the head needs a new verifier.
- A binary file is diffed as text, like any other file. A rebase over a `main` change elsewhere in
  it keeps the id, while `git patch-id` hashes a binary file's blob ids and changes. So the content
  id is not stricter than `git patch-id` everywhere outside the run logs. It binds the same thing
  for a binary file as for a text file: the PR's hunks, their context and where they apply.
- The git calls, the `--raw` parse, the block matching, which base file a block's hunks apply to
  and `sha256sum` are not proved, and the hunk header parse is checked on examples only. The test
  covers them. Of 13 mutants of the module, 5 fail `lake build` and 8 fail the test.
- `carry` trusts GitHub's activity route to list each push with its real actor. A push missing
  from the list leaves a gap, which fails safe. Reading the route is not proved;
  `gate/carry-test.sh` feeds the tool fixed lists (22 cases), and the PR's proof runs it on the
  real route. Of 9 mutants of `Carry.lean`, 6 fail `lake build` and 3 fail the test.

## Not in this task
- `gate/content-id-test.sh` and `gate/carry-test.sh` are not CI steps: a step is a
  `.github/workflows/` change, outside this task's brief. A follow-up can add them, as for
  `gate/runlog-test.sh` (#99). CI checks the theorems and examples through `lake build`.
- `docs/process.md` and the poteto-mode playbooks still name `git patch-id --verbatim`; #79's PR 5
  moves them. They still say a rebase that keeps that id keeps the verdict. Until PR 5, the skill's
  rule is the one agents follow (#99).
- The round-2 verdicts' other minor findings are in #99: no test pins the `@[csimp]` swap, a
  verified head that leaves every ref is refused until it is fetched, and attempt 2's run-log
  record says 79 tests passed where the suite gave 80.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)
