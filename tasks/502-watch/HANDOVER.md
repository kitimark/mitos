# Handover: building the #502 watcher

This brief is for an implementor outside Claude Code: Codex, Cursor, Antigravity or another tool.
It assumes no context beyond this repository and this package.

Words used below:
- **Orchestrator**: the Claude session the owner talks to. It assigns rows, starts verifiers,
  writes the Owner dashboard and assigns the owner. You report to it.
- **Verifier**: an agent that did not write your PR. It checks your head and returns pass or fail.
- **Trust-critical**: a PR that touches `gate/`, `.github/`, `eval/cheats/`, the toolchain or lake
  files, or needs the `spec-approved` label. It needs an Opus verifier, and the owner merges it.
- **Gate column**: the column of `PR-SEQUENCE.md` that names what a PR waits for: owner answers
  (`Q1`, `Q8a` and so on, the questions in `DESIGN.md`) and other PRs.
- **Architect**: the design agent the orchestrator runs before a Lean row starts. It type-checks
  that row's slice of the sketch, writes the stub bodies its statements are stated over, and
  upgrades the row's task file to build depth. You do not run it; you start from its result.

## What you are building

The repository has one GitHub watcher, `.claude/scripts/watch-github.sh`, which only the
orchestrating agent can use. It decides "the owner wrote this" by a footer that anyone can type
(#501), and `.claude/hooks/pr-state.sh` makes the same mistake when it lists the owner's
unanswered comments. The redesign (#502) moves the logic into Lean inside the repository's own tool
`mitos-gate`, as `mitos-gate watch`. One shell entry, `.claude/scripts/watch.sh`, serves every
agent, you included. This package holds the design:
- `DESIGN.md`: why, and how it is used.
- `tasks/502-watch.md`, the Design block (one folder up): modules, types, statements and fixtures.
- `PR-SEQUENCE.md`: the PRs, one concern each, with the gate each one waits for.
- `REVIEW-LOG.md`: what the first two review rounds found and how the design changed (round 3 is
  at the end of `DESIGN.md`).
- `sketch/`: unchecked Lean and the shim, at the paths they will have in the repository, and two
  tested diffs: `sketch/.claude/scripts/watch-github.pr1.diff` (PR 1) and
  `sketch/.claude/hooks/pr-state.pr3a.diff` (PR 3a).

**Where the package is.** PR 0 commits it: the Design block as `tasks/502-watch.md`, and the rest
in this folder, `tasks/502-watch/`, which nothing builds. Paths such as `sketch/` in this package
are relative to this folder. Each row's task file (`tasks/P2-0nn-watch-<slug>.md`) names that path,
and each row's issue is in the milestone "Watch: one Lean waiter for GitHub (#502)". Before PR 0
merges, the orchestrator hands you these files with the assignment, so PR 1 and PR 3a cannot start
from a bare clone.

**How far it is checked.** The two diffs are at build depth: they ran against `main` at `7dfd6cb`.
The Lean is at contract depth: it was never type-checked, and its central functions are stubs.
Before a Lean row starts, the Architect type-checks that row's slice, writes the stub bodies its
statements are stated over, and upgrades the row's task file to build depth.

**What you may start now:** PR 1, PR 3a and PR 3b (3b after 3a, once its issue exists). They need no
answer from the owner. PR 2 and every later PR wait for PR 0 to merge (the plan rows and their
issues; the owner merges it after answering questions 1 and 8a, which also accepts the defaults in
`DESIGN.md`, part B) and for any other owner answer named in the Gate column of `PR-SEQUENCE.md`.
Do not start one before the orchestrator assigns it to you.

## Your role and its limits

`docs/process.md` §2 calls you an **Implementor**.

You may write:
- code and proofs inside the task's `touches` (`tasks/502-watch.md`, and the files column of your PR's
  row), including `.claude/hooks/pr-state.sh` for PR 3a, 3b and 3
- your own PR's branch and body
- replies on your PR's review threads
- the task file
- your run-log record

You must not (this list is the default; a row's Files column in `PR-SEQUENCE.md` overrides it
for that PR only: PR 3c edits existing `gate/MitosGate/Snapshot/` modules, and PR 11 may add a
workflow under `.github/` on the route the owner picks):
- merge anything, approve a PR or give a verdict on your own PR. A check you run is evidence for
  the verifier, not a verdict.
- add or remove labels. A label change starts CI and some labels are owner-only, such as
  `spec-approved`.
- assign or unassign the owner on anything.
- edit the Owner dashboard issue (#43), including its verdict cells.
- weaken, delete or relax any check, test case, theorem, cheat case or `expect` line to get green.
  That is a spec change and goes to the owner.
- touch `statements.lock`, `models.lock`, `core/`, `eval/cheats/`, `.github/`, the root
  `lean-toolchain`, `lakefile.toml` or either `lake-manifest.json`.
- edit or move an existing `gate/` module. New `gate/MitosGate/Watch/*` files, `WatchCli.lean`,
  `Watch.lean`, and one arm in `gate/Main.lean` are your files. Import what exists.
- use Claude-only machinery: `Monitor`, subagents, `SendMessage`, `/no-comments`,
  `.claude/settings*.json`, or `.claude/scripts/open-pr.sh` (that one cleans a link only Claude's
  proxy adds). The hooks under `.claude/hooks/` are not yours to run as machinery; edit only the
  files your PR's row names.
- put any key, token, session or request id, email or private URL in a commit, PR body or comment.
  The repository is public. Issue numbers, PR numbers, commit SHAs and links to public GitHub
  comments are fine.

Open your PR with `gh pr create` or your tool's own PR feature, with the body the brief gives.

Files under `gate/`, `.github/`, `.claude/`, `docs/process.md` and `plan/` are owner-kept. A PR
touching them stops at "verified and green" and the owner merges it. A PR touching `gate/` or
`.github/` also needs an independent Opus review. Report and stop; do not ask anyone to merge.

## How to post

Everything you post on GitHub (PR bodies, review-thread replies, issue comments) follows the
repository's standing rule in `kitimark-mode` ("Every agent that posts to GitHub ends each post with
the footer"): end it with a blank line, a `---` line and
`_Generated by [Claude Code](https://claude.ai/code)_`, exactly so, whatever tool you are. The
footer is this repository's marker for any agent's post, not a claim about which tool wrote it.
Until a rules PR the owner merges says otherwise, the tools still read it:
- On review threads GitHub names no app. `pr-state.sh` and the bash watcher tell your reply from
  the owner's words only by that footer, so a review-thread reply without it is listed as the
  owner's unanswered words and blocks the merge line. The Lean watcher (`watch.sh`, from PR 9)
  does not read the footer there: it shows such a reply as `no app key` and wakes every waiting agent unless its
  id was recorded with `watch.sh own` (below).
- Post through your tool's own GitHub app integration, not with the owner's token from a shell.
  GitHub then names your app on every issue comment (`performed_via_github_app.slug`), which is how
  PR 1 and PR 3a tell your comment from the owner's. An issue comment posted with the owner's token
  and no app is read as the owner's own typed words, footer or not.
- If your tool cannot post through its own app (it has only a `gh` token), post no issue comment.
  Put what you would have said in your PR body and your report, and say in the PR body that you
  did so. A PR body is not a comment, so it is never read as the owner's words.
- List the id of every comment and reply you post in your report.
- Once `watch.sh` exists (PR 9), also record each review-thread reply you post:
  `.claude/scripts/watch.sh own --as <your-app>/<your-name> review-comment <id>`. An unrecorded
  reply on a review thread wakes every waiting agent, you included.

## Setup

```bash
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
sudo apt-get install -y bubblewrap shellcheck jq
lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check
```

The toolchain comes from `lean-toolchain`, so do not change it. Branch from the latest `main`.
Keep current by rebasing (`git rebase origin/main`), never by merging `main` in.

## Checks

Run every check your change can affect before each push:

| What | Command |
|---|---|
| build, imports, lock | `lake build && lake exe mitos-gate imports && lake exe mitos-gate lock --check` |
| Lean lint harness | `lake exe mitos-lint-test` |
| the new gate suite | `bash gate/watch-test.sh` |
| gate suite inventory | `python3 -I .github/scripts/gate-tests.test.py` |
| all gate suites, as CI shards them (CI runs this; locally only on a clean, committed tree) | `GITHUB_RUN_ID=1 python3 -I .github/scripts/gate-tests.py run --shard 0/3 --out <empty dir>`, then `1/3` and `2/3` (shards count from 0) |
| cheat corpus (slow; the check matrix asks for it locally whenever you touch `gate/`, and CI runs it too) | `lake exe mitos-gate cheats`, or one shard: `lake exe mitos-gate cheats --shard 0/3` |
| the bash watcher | `bash .claude/scripts/watch-github.test.sh` |
| REST-only wrappers | `bash .claude/scripts/gh-api-rest.test.sh` |
| sourced bash | `bash .claude/scripts/sourced-bash.test.sh` |
| shell lint | `shellcheck -x <each changed .sh>` |
| pr-state hook | `bash .claude/hooks/pr-state.test.sh` |
| main's tool helper | `bash .claude/scripts/main-tool.test.sh` |
| mirrored agent skills | after editing either `SKILL.md` copy: `python3 .agents/scripts/agents-skills.py stamp`, then `python3 .agents/scripts/agents-skills.py check`; commit the changed `.agents/scripts/agents-roster.tsv` |
| plan rows (PR 0) | `bash .claude/scripts/plan-tasks.test.sh` |
| run log | `lake exe mitos-gate runlog --head ops/runs` |

A new `gate/*-test.sh` must be committed executable (mode 100755, `git update-index --chmod=+x`).
The CI job `gate-tests` refuses one that is not, and runs every one that is.

A script that calls GitHub needs proof from one real run against GitHub, in addition to the test
with a fake `gh`. Paste the command and its output, with nothing secret in it, into the PR body.

## Lean rules

- Write each statement as `def Name : Prop := ...` with `theorem name : Name := ...` beside it, as
  in existing `gate/` modules, and outside any `variable` section, as `KeyMap.lean` does: a
  statement that picks up a `variable` binder is no longer of type `Prop`, and the audit no longer
  sees it. There is no audit list to keep: the audit in
  `gate/MitosGate/Watch.lean` finds every theorem under `MitosGate.Watch` and every `def ... : Prop`
  there, and fails the build when a statement has no theorem or a theorem uses another axiom. Keep
  `gate/MitosGate/WatchCli.lean` importing `MitosGate.Watch`: the build reaches only what
  `gate/Main.lean` imports, so that import is what runs the audit.
- `Watch.lean` imports only the modules that exist after your PR, and each module imports only
  what exists (PR 2's `Observe` does not import `Route`). The sketch shows the final imports.
- No `sorry`, `admit`, `axiom` or `native_decide`. The audit allows only `propext`,
  `Classical.choice` and `Quot.sound`.
- Fixtures go in a `Fixture` namespace and prove with `decide +kernel`. `List.mergeSort` does not
  reduce under `decide`, so use `DecideList.sortStrings` or an insertion sort.
- No `String.toNat?`, `String.splitOn`, `String.all` or `for c in s` in anything a `decide +kernel`
  fixture evaluates: they run through well-founded loops the kernel does not reduce. Work over
  `List Char` with `MitosGate.Base.Text` (`split`, `parseNat`), as `Speech.stamp?` and the sketch's
  `Watch/Time.lean` do. Check every other String helper a fixture reaches when you first elaborate.
- Read files as bytes and decode: `String.fromUTF8? (← IO.FS.readBinFile path)`.
  `IO.FS.readFile` and `Handle.readToEnd` throw on bytes that are not UTF-8.
- `Json.parse` is `partial`, so do not try to prove codec round trips. Test them.
- Reuse `Base.Text` for text a fixture parses, `Speech.stamp?`, `Shadow.days` and
  `Shadow.Stamp.seconds` for time, `Speech.footer` and
  `Speech.apps` for the footer and the answer apps, `oneLine` and `oneLine_printable` from `Util`
  for printable text, and `Accept.writeByRename` for files.
- The sketch is unchecked. The Architect's upgrade (above) type-checks your row's slice first.
  Known fixes are already in it (`squeeze` uses a top-level recursive helper, `SafeSegment` is an
  `abbrev`, the footer test is `Speech.footer` over `List Char`, Time parses `List Char`). Fix any
  other elaboration error the smallest way and list it in your PR body.
- If a statement in `tasks/502-watch.md` looks false, do not bend the code to fit it. Write the
  counterexample in the task file and in your PR body, then stop and report. Only `IsoReadsBack`
  has a weaker fallback; the other EXPENSIVE statements name a proof plan, not a weaker statement.
- Keep the module map. If a file outgrows its topic, report the deviation rather than splitting it
  silently. The splits `tasks/502-watch.md` plans (Deliver, Observe, View) are not deviations.

## PR 1 brief: the #501 stopgap in the watcher

- **Goal.** An owner comment typed on GitHub is reported even when it ends with an agent's footer.
  A comment posted through any app other than Claude's, or through Claude's without the footer, is
  reported as an agent comment.
- **Start from** `sketch/.claude/scripts/watch-github.pr1.diff`. It applies to `main` at
  `7dfd6cb` with `git apply`, and in a scratch copy all 145 existing checks pass unchanged, the
  five new cases pass, and four of them fail on `main`'s script. Rebase it if `main` moved.
- **Files.**
  - `.claude/scripts/watch-github.sh` and `.claude/scripts/watch-github.test.sh`
  - `.claude/skills/kitimark-mode/SKILL.md`, lines 94, 109 and 167 to 170 at `7dfd6cb`, and the
    same text in `.agents/skills/kitimark-mode/SKILL.md`, lines 75, 90 and 148 to 151. The second
    is a hand-rewritten mirror, so edit it by hand, keeping its wording style.
  - `.agents/scripts/agents-roster.tsv`, after `agents-skills.py stamp`.
- **Behavior**, in the jq of `watch-github.sh`:
  - New definitions beside `def mine` (line 75): `via` is `typed` when the item has the key
    `performed_via_github_app` and it is null, `app` when it is an object, and `absent` when the
    key is missing; `ic_words`, `ic_agent` and `ic_answer` decide an issue comment from it.
  - An issue comment with the key null is owner words, even when it ends with the footer.
  - With app `claude` and the footer it prints nothing (an agent's own post).
  - With any other app, or app `claude` without the footer, it prints
    `agent comment <id> (<slug>) on #N: <excerpt>`, the slug through the script's `clean`. Its event
    key is `comment <id>`, the same key space as an owner comment, so the seen-file dedupe applies,
    and its tier is `tier_owner`.
  - With no key at all, today's footer rule stays. Live comments always carry the key; the
    existing fixtures do not, and they must pass unchanged.
  - Review comments and reviews carry no app field, so `def mine` keeps today's footer rule there.
  - Where it changes: the later-poll thread list (line 108), which takes `ic_words` for issue
    comments and `mine` for review comments; the first-poll scan (lines 205 to 218), whose items
    carry `w` (words) and `a` (answer) instead of the footer flag; and the issue-comment events
    (line 250).
  - The first-poll scan lists owner words only, labeled `owner comment` as today. An answer there
    is an issue comment through `claude` or `cursor`, or any post with the footer that the owner
    did not type. A Codex comment with its footer answers; one without it is neither words nor an
    answer, so it never appears in the scan.
- **Tests.** The six cases in `PR-SEQUENCE.md` ("PR 1 test cases"), five of them new. Every
  existing case passes unchanged.
- **Proof.** One real read-only run: `WATCH_POLLS=1 .claude/scripts/watch-github.sh <scratch-dir>`
  in a clone with `gh` authenticated. Put the run's line count, not its content, in the PR body.
- **Checks.** `watch-github.test.sh`, `gh-api-rest.test.sh`, `sourced-bash.test.sh`,
  `shellcheck -x .claude/scripts/watch-github.sh`, `agents-skills.py stamp` then `check`.
- **PR body.** `Closes #501` if PR 3a has merged, else `Part of #501`; `Part of #502`; what changed,
  the checks you ran with their results, and the real run. Add that review routes still use the
  footer (default 5b covers them) and that `pr-state.sh` gets the same rule in PR 3a.
- **Stop** when CI is green and every review thread has a reply. Report your head SHA and the ids
  of your posts.

## PR 3a brief: the #501 stopgap in pr-state

- **Goal.** `pr-state.sh`'s two jq classifiers (`full_thread_unanswered` per PR and
  `owner_unanswered_by_thread`) take PR 1's rule, so a typed owner comment that ends with a footer
  is unanswered words and answers nothing.
- **Start from** `sketch/.claude/hooks/pr-state.pr3a.diff`. In a scratch copy at `7dfd6cb`, all
  714 existing checks pass unchanged and the three new cases pass; on `main`'s script the three new
  cases fail and nothing else does.
- **Files.** `.claude/hooks/pr-state.sh`, `.claude/hooks/pr-state.test.sh`.
- **Checks.** `pr-state.test.sh`, `gh-api-rest.test.sh`, `sourced-bash.test.sh`,
  `shellcheck -x .claude/hooks/pr-state.sh`.
- **PR body.** `Closes #501` if PR 1 has merged, else `Part of #501`; `Part of #502`; the changed
  classes (`Voice.lean` lists them: typed words with a footer, a Claude- or Cursor-app post without
  one, another app's post without one).

## PR 3b brief: pr-state hangs on a piped stdin

- **Goal.** `pr-state.sh` ends within its budget when its stdin is a pipe that never closes. Today
  line 14 runs `cat` whenever stdin is not a terminal, so it waits for an end of file that never
  comes. This is not watcher work; it is here because the waiter's tests met it.
- **Order.** After PR 3a merges, because both change the same two files. The orchestrator files the
  issue first, and the PR body says `Closes #<that issue>`.
- **Files.** `.claude/hooks/pr-state.sh`, `.claude/hooks/pr-state.test.sh`.
- **Test.** A case that runs the hook with stdin from a pipe that never closes and asserts that it
  ends within the hook's budget. Every existing case passes unchanged.
- **Checks.** As PR 3a. **Stop** as PR 1.

## PR 2 brief: the first Lean module

Start only after the orchestrator assigns it (PR 0 merged, which carries the answers to questions 1
and 8a and default 4, the placement in `gate/`). The first step is the Architect's upgrade of this
slice to build depth.

- **Goal.** `mitos-gate watch unanswered` gives the owner's unanswered words per thread. A post is
  classified as `land` classifies it (`Snapshot.speaks`, `Snapshot.answers`), except that typed
  words stay words even with a footer (#501). Timing and counting are pr-state's jq's.
- **Files.**
  - `gate/MitosGate/Watch/Time.lean`: `Epoch`, `ofStamp` and `ofIso?` only. `iso` and
    `ofHttpDate?` come in PR 4.
  - `gate/MitosGate/Watch/Voice.lean`: everything in the sketch.
  - `gate/MitosGate/Watch/Observe.lean`: only the three post readers (`issueComments`,
    `reviewComments`, `reviews`) and `readJsonFile`, without importing `Route`.
  - `gate/MitosGate/WatchCli.lean`: `unanswered` only, and `import MitosGate.Watch`. `wait`, `own`
    and `status` answer "not built yet" with exit 2.
  - `gate/MitosGate/Watch.lean`: imports of Time, Voice and Observe, and the audit, which finds
    Voice's theorems and fixtures itself.
  - `gate/Main.lean`: one import, one usage block, the `watch` arm.
  - `gate/watch-test.sh` (100755) and `gate/watch-fixtures/posts-336/`.
  - `docs/process.md`: one check-matrix row naming `gate/watch-test.sh`.
  - your run log. (`tasks/502-watch.md` already landed in PR 0.)
- **Readers.**
  - Each reader first drops items of other logins, then checks fields. An owner's issue comment
    must have the `performed_via_github_app` key, null or an object. An owner item that lacks it,
    or that it cannot read, becomes a `Refused` entry in the reader's `Reading`, and the rest of
    the answer applies. An answer whose shape is wrong is refused whole.
  - Review comments and reviews read `via := .absent`.
  - Reviews skip `PENDING`, take `submitted_at`, and take their pull request from
    `pull_request_url`.
  - Each answer is a `--paginate --slurp` array of pages.
  - Refuse with a path-prefixed reason, as `gate/MitosGate/SpeechCli.lean` does.
- **Proofs.** All eight Voice statements: TypedOnlyFromAnIssueCommentWithNoApp,
  ReviewRoutesAreNeverTyped, TypedIsAlwaysWords, AnAppPostIsNeverWords, SpeaksAsLandUnlessTyped,
  AnswersAsLandUnlessTyped, TypedWordsAreListedUntilAnswered, ExcerptIsOneLine. Also the Voice
  fixtures in the sketch.
- **Tests** (`gate/watch-test.sh`, building with `lake build mitos-gate` as `gate/speech-test.sh`
  does):
  - `posts-336`: #336's public posts (typed, Claude-app and Codex-app, with and without the
    footer), read with `watch-fetch.sh`-style `gh api` reads, plus edited copies that add one post
    of each class `Voice.lean` lists. The file `posts-336/expected.json` gives the ids
    `unanswered` must print, and `posts-336/classes.tsv` names, per post id, its class and what
    today's jq gave. The test checks both.
  - an owner item without the app key makes `unanswered` exit 1, since it would answer from a
    partial read; an item of another login without the key does not.
  - a non-UTF-8 file refuses with exit 1.
  - output is one line of compact JSON.
  - the audit is in the build: `WatchCli.lean` imports `MitosGate.Watch`, and
    `.lake/build/lib/lean/MitosGate/Watch.olean` exists after `lake build mitos-gate`.
- **Checks.** Build, imports, lock, `mitos-lint-test`, `lake exe mitos-gate cheats`,
  `bash gate/watch-test.sh`, the gate-suite inventory test, and the run-log check.
- **PR body.** `Part of #502` and the row's issue, the statements proved, the fixtures, the class
  table, and any deviation from the sketch with its reason.

## Later PRs

Take the row in `PR-SEQUENCE.md`, the slice of `tasks/502-watch.md` it names and the sketch files.
State in your PR body what differs from them and why. Do not start a PR whose row depends on one
that has not merged, or whose gate is not met.

## Waiting on CI

Wait in bounded calls. Never run an unbounded background loop.
- Until `watch.sh` exists (PR 9), poll with `gh run list --commit <head>` or your tool's own
  checks view.
- `watch.sh` runs `main`'s `mitos-gate`, which it builds or fetches (`DESIGN.md`, default 3c).
  If your environment can do neither (no Lean toolchain and no route to the release asset), keep
  the bounded `gh` loop above. You then do not hear the root's posts through the watcher.
- After it exists, run one wait before your first `watch.sh own`, then wait with
  `.claude/scripts/watch.sh wait --as <your-app>/<your-name> --pr <n> --max <m>`. Then run the
  command after `next: ` on the last line it prints, copying its `--seen <n>` exactly: any other
  number takes nothing, and the same batch comes back. A run with no stdin is fine: the tool
  closes it. Exit 3 (no stdout) means a newer wait of yours took over: do nothing. Exit 1 means do
  not re-run at once: check CI yourself, then wait again after 10 minutes. Exit 4 means GitHub is
  failing: run the `next: ` command, and check CI yourself meanwhile.

Suggested `--max` values, to tune to your tool's command timeout (not measured):

| Host | `--max` | Note |
|---|---|---|
| Codex | 4 | below its command timeout |
| Cursor | 8 | |
| Antigravity | 5 | run with stdin closed (`</dev/null`) |

Your app name is the `performed_via_github_app.slug` GitHub shows on your issue comments. Codex's
is `chatgpt-codex-connector`; for Cursor, Antigravity or another tool, read it off your first
comment (`gh api repos/<owner>/<repo>/issues/comments/<id> --jq .performed_via_github_app.slug`).
After two waits with CI still running, report "pushed, waiting on CI" and stop. The owner or the
orchestrator then starts a new session with your report.

## Run log

Each attempt adds one file, `ops/runs/<YYYY-MM-DD>/<task>-<role>-<attempt>.json`, with the record
on one line (`ops/runs/README.md`). Use your role `builder`, your real model name, `tokens: null`
if you cannot meter, and an `outcome` of `in-review`. For example:

```json
{"task":"502-watch-pr2","role":"builder","model":"<your exact model ID>","attempt":1,"iterations":4,"wall_min":95,"tokens":null,"errors_by_kind":{},"lint_hits":[],"escalations":[],"outcome":"in-review","note":"Voice and unanswered; posts-336 classes as listed"}
```

A file already on `main` never changes. Before each push,
`git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
shows only `A` lines.

## Review rounds

`kitimark-mode` (PR owners carry their PR, and Rounds) sets these for every PR owner, you included:
- Fix only blocking findings: a cheat the gate accepts, a wrong result, a red check, a check or
  theorem your diff weakens, or a doc line your PR made wrong. File every minor finding in one
  `follow-up` issue that your PR body links, and answer its thread with that link.
- Leave a security finding's thread open for the owner, with your reply.
- Batch the fixes you know of into one push: each push starts CI and a paid bot review.
- A PR gets two rounds. If it still fails, report what fails and stop; do not start a third.

## Reporting

End with:
- your head SHA
- the checks you ran with their results
- the statements proved
- any deviation from this package, with its reason
- the PR number and the ids of every comment and reply you posted
- your provider (`openai`, `google`, or another), your exact model ID as your tool reports it (or
  `unknown`), and your effort setting. The orchestrator records the author of every PR in the
  Owner dashboard's provenance block, and the merge rule needs a known author: an unknown one holds
  the merge.

Then stop. The orchestrator spawns the verifier, writes the dashboard, and assigns the owner.
