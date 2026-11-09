# tasks/content-id.md

phase: 1
goal: A verdict carries across a rebase that changes nothing but `main`'s run-log lines around the PR, and never across a real change, by a content id whose decidable parts are proved in Lean.
statement: none (tooling task); theorems in `gate/MitosGate/ContentId.lean`, outside the lock
touches: gate/MitosGate/ContentId.lean, gate/Main.lean (the `content-id` subcommand only), gate/content-id-test.sh, .claude/skills/kitimark-mode/SKILL.md (the verdict-carry rule and its two references), ops/runs/2026-11-09.ndjson (appended lines only), tasks/content-id.md
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, docs/process.md, models
checks: build, imports, lock, lint test, runlog on this PR's run log, gate/runlog-test.sh, gate/content-id-test.sh, shellcheck
budget: 20 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Issue #79, PR 1 of its sequence. On the morning of 2026-11-09 the bot rebased open PRs 9 times;
  for the 7 whose previous head is known, the whole-diff `git patch-id --verbatim` changed every
  time, so every rebase needed a new verifier and a new merge command. The cause is
  `ops/runs/*.ndjson`: it is append-only with `merge=union`, and `main`'s new lines change the
  context lines of the PR's own run-log hunk.
- PRs 3 and 4 of #79 (the steward) compute this id from `main`'s checkout. PR 5 moves
  `docs/process.md` and the playbooks to it.
- It has no row in `plan/phase-1.md`, which the owner keeps.

## Decisions
- **A `mitos-gate` subcommand, not `.github/scripts/content-id.sh`.** The decidable parts are Lean
  (`RunLog.added`, `addedSorted?`, `normalize`, `isRunLog`, `diffHeader`), and the steward builds
  the gate for its own Lean decision anyway. Git is only called, never scripted.
- **The diff is normalized in Lean, not piped into `git patch-id`.** The tool drops `index` lines
  and cuts hunk headers to `@@`, which is what `git patch-id` ignores, and keeps every other byte.
  `git patch-id` would add three dependencies: its algorithm changed in git 2.39 for mode changes
  and binary files, it hashes with SHA-1, and it reads lines with `strlen`, so it cannot hash a
  NUL, which rules out `--text`. The `@@` marker keeps where one hunk ends, which `git patch-id`
  forgets. The shell reference in `gate/content-id-test.sh` (grep and sed) gives the same digest.
- **`--text`.** Every file is diffed as text, so `.gitattributes`, `core.attributesFile`,
  `info/attributes` and `core.bigFileThreshold` cannot turn a file into a binary patch, and a
  binary file is bound byte for byte.
- **Pinned options.** Every `git diff` option that the config can change is a flag; config without
  a flag goes in with `-c`; `GIT_DIFF_OPTS`, `GIT_EXTERNAL_DIFF` and `GIT_ATTR_SOURCE` are removed.
  The test runs 32 config and environment variants (the three #79 names and 29 more, such as
  `diff.algorithm`, `diff.context`, `diff.suppressBlankEmpty`, `core.quotePath`, `diff.orderFile`
  and attribute drivers), and all give the plain id.
- **No pathspec.** The run logs are split out in Lean (`isRunLog`), with the same set as
  `.gitattributes` and `mitos-gate runlog`. The patch's file blocks are matched to the `--raw`
  listing by the exact `diff --git` line git prints (`diffHeader`), so a missing or extra block is
  refused. A pathspec would also match below a directory named `x.ndjson`, and
  `GIT_LITERAL_PATHSPECS` and its siblings change what one means.
- **A run-log change that is not append-only is refused, with no id.** #79 suggested falling back
  to the file's exact diff. CI's run-log check already fails such a PR, so a refusal loses nothing
  and leaves no second path to review. The file must be added or modified, with mode 100644 on
  both sides; a deletion, a type change or a mode change is refused, because `runs` lists only
  added lines and would not show it.
- **Encoding.** `rest` is a 64-hex SHA-256, and each run-log path and line is written with its
  length first. The id is printed in full: 64 bits would allow a birthday collision between two
  crafted changes in about 2^32 hashes.
- **Merge-base.** Exactly one, from `git merge-base --all`; none or several is refused.
- **Printing.** Paths and git messages print through `oneLine`, with `##[` written as
  `##\u{005B}`, the legacy workflow-command marker #68 is about. When #68's `ciLine` lands, these
  lines can use it.

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
- `kind_body`, `normLine_body`, `normalize_ne`: a change in any hunk line, whitespace included,
  changes the normalized diff.
- `normalize_hunkHeader`, `normalize_index`: a hunk that only moves, and the base blob's id, do not.
- Kernel-checked examples for `added`, `normalize`, `kind`, `isRunLog`, `diffHeader` (against git
  2.43's output for a name with a tab, a quote, a backslash and a byte that is not ASCII) and
  `preimage`.

## Limits
- Where a hunk sits in its file is not bound, as with `git patch-id`: the same hunk with the same
  three context lines, moved within the same file, keeps the id.
- A `main` change within three lines of a PR hunk changes the id, on purpose: the verifier read
  that context.
- The git calls, the `--raw` parse, the block matching and `sha256sum` are not proved; the test
  covers them, and each of 6 mutants of the module fails either the build (3) or the test (3).

## Not in this task
- `gate/content-id-test.sh` is not a CI step: a step is a `.github/workflows/` change, outside this
  task's brief. A follow-up can add it, as for `gate/runlog-test.sh`. CI checks the theorems and
  examples through `lake build`.
- `docs/process.md` and the poteto-mode playbooks still name `git patch-id --verbatim`; #79's PR 5
  moves them. Outside the run logs the content id is the stricter of the two (it keeps hunk
  boundaries and never detects a rename), so where they disagree, following the skill is never
  less safe than the old line.

## Done when
- [x] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)
