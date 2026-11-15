# tasks/P1-020-land-merge-workflow.md

phase: 1
goal: On a `merge` plan, `land.yml`'s `apply` job reads the pull request and its conversation again and makes the one pinned rebase-merge call with the updater app's token, and `report` answers each change of answer to an owner word, so a kept pull request lands on the owner's typed `/land <commit>` with no Claude session calling the merge.
statement: none (workflow tooling); the Lean it acts on is P1-018's and P1-019's
touches: .github/workflows/land.yml, .github/scripts/land-decide.sh (its new outputs), .github/scripts/land-decide.test.sh, .github/scripts/land-apply.sh, .github/scripts/land-apply.test.sh, .github/scripts/land-report.sh, .github/scripts/land-report.test.sh, .github/workflows/ci.yml (the two new tests), this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/, eval/cheats/, models, .claude/, .cursor/, CLAUDE.md, docs/process.md, .github/workflows/update-prs.yml, .github/scripts/rebase-prs.sh, .github/workflows/land-protection.yml, .github/scripts/land-protection.sh
checks: actionlint, shellcheck, land-decide.test.sh, land-apply.test.sh, land-report.test.sh, land-protection.test.sh, every gate/*-test.sh, cheats (in ci), the real runs under `fixtures`
budget: 25 iterations · 8h wall · 2.5M tokens, the real runs included
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-020 in `plan/phase-1.md` (Land track), row A3 of the auto-merge amendment (#178,
  comment 6890739593, accepted by the owner on 15 Nov in #179, comment 6890996353); issue none
  yet; tracker #179.
- Needs P1-018 (A1: the `merge` plan, `OwnerWord`), P1-019 (A2: the reader that approves), #245's
  protection reader (PR #278, open: without it every pull request holds as "unread protection", so
  `plan` never names a merge), and the shadow evidence on #191 (below).
  #278 also edits `land.yml` (`actions: read` on `decide`), so this row starts from its merged
  file.
- Who merges: the owner, by hand (`.github/`). It is the last kept pull request merged that way.
  It is trust-critical, so it also gets an `opus` verifier at `xhigh`.
- Built before it: step 3's `decide` (P1-012, #260 and #262), whose recorder does not change and
  whose report is the evidence. P1-021 (A4) follows it at once, after its real runs.
- Not checked by the amendment: the workflow, `apply` and `report`; a merge by the app, with or
  without a workflow file in the diff, and whether that needs Workflows write; the app's live
  permission list; a comment from the owner's own `gh`.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: contract only, so this row's issue says "contract only". The amendment gives the jobs, the
order of `apply`, the permission and the `report` posts (below); nothing of this row is built.

revisit_when: re-check after P1-019 merges, and again after #278 merges.

modules: one topic per file.
- `.github/workflows/land.yml`: when each job runs and what it may hold. `decide` keeps no key and
  gains outputs. `apply` runs only on a `merge` plan, in environment `trusted`, with the updater
  app's token, no toolchain and no checkout of a pull request's code. `report` has
  `pull-requests: write` and no key. The constant `LAND_MERGE: on` sits in the workflow's `env`.
  About 150 lines (76 today, before #278).
- `.github/scripts/land-decide.sh`: also writes `decide`'s outputs. Copies its own layout.
- `.github/scripts/land-apply.sh`: `apply`'s four steps and the one `PUT`. About 90 lines; copies
  `land-decide.sh` (usage header, `die`, exit 2 on usage, `timeout -k 5 120` on each `gh api`).
- `.github/scripts/land-apply.test.sh`: `apply` against a stub `gh`. About 250 lines; copies
  `land-decide.test.sh` (`ok` and `bad` counters, one summary line).
- `.github/scripts/land-report.sh` and `.github/scripts/land-report.test.sh`: one post per change
  of answer. About 120 and 200 lines; same layouts.
- `.github/workflows/ci.yml`: the two new tests in the `checks` job, beside
  `land-protection.test.sh` (#278); neither needs the built tool.

### Usage (caller's view)

The owner comments, alone in a comment on the pull request:

```
/land <the full head sha>
```

Within minutes `github-actions` answers on the pull request, and the merge follows `gate` on
`main`'s tip:

```
<!-- land-report -->
Landed <head> on your /land. main is <sha>.
```

### Contract (defaults where the amendment leaves a choice)

- `decide`'s outputs: `plan` (the decision's plan JSON), `approval` (the id of the owner's comment
  whose `/land` is the entry that is next, `said / 2` of its word), `digest` (below), and
  `answers`: for each pull request with an owner word, `{pr, head, word, step}` from a run of
  `mitos-gate land` with `me` and `pr` set, one per pull request (P1-018's `word` field). So
  `report` needs no toolchain.
  `decide` still records `plan` only; the record's shape does not change.
- `digest`: the SHA-256 of the sorted lines `<route> <id> <time> <sha256 of the body>` over every
  issue comment, review comment and review of the planned pull request, from the reads
  `snapshot-fetch.sh` saved, where `<time>` is `updated_at`, or `submitted_at` for a review. The
  review route gives no `updated_at` (check it on a real response), so the body's hash is what shows
  an edited review. `apply` computes the same from its own three reads.
- `apply` runs in concurrency group `land-apply`, with `cancel-in-progress: false`, and only when
  `decide`'s `plan.kind` is `merge`.
- `report` posts at most one comment per pull request per run, and only when the first line of its
  answer differs from that of its newest `<!-- land-report -->` comment on that pull request.
- `LAND_MERGE` ships `on`: without the owner's typed approval nothing is planned, and the real runs
  need it on.

types: none in Lean. The JSON shapes are `decide`'s outputs above and P1-018's `merge` plan and
`word`.

statements: none new. `apply` acts on P1-018's `PlannedMergeIsGated` (15) and P1-019's
`KeptMergeIsTheOwnersTypedApproval`; the two checks only the workflow makes are the last two rows of
section 2's table below.

reuse:
- `.github/workflows/land.yml` and `.github/scripts/land-decide.sh` (P1-012, with #278's change).
- `.github/workflows/update-prs.yml`: environment `trusted`, `vars.PR_UPDATER_APP_ID`,
  `secrets.PR_UPDATER_APP_KEY` and `actions/create-github-app-token` (lines 23 to 46).
- #278's `land-protection.yml`: the mint step pinned to a commit, with one `permission-*` input
  (here `permission-contents: write`), and every action pinned to a commit in a job that holds a
  key.
- `.github/scripts/land-decide.test.sh`: the stub `gh` and the `holds-no-key` pins, which this row
  narrows to `decide` and `report`.

fixtures:
- `land-apply.test.sh` and the real runs: section 5's two bullets below.
- `land-decide.test.sh`: `holds-no-key` still passes for `decide`, now also for `report`; a new
  case pins `decide`'s outputs on the land fixture (`plan`, `approval`, `digest`, `answers`).
- `land-report.test.sh`, with a stub `gh`: each outcome of section 4's table gives its first line;
  the same answer twice posts once; every post starts with `<!-- land-report -->`; `report` makes
  no call but the comment reads and the one post.
- The shadow evidence below, posted on #191 and summed up in this row's PR body.

cut_line: one PR, `Part of #179`. It ships `decide`'s outputs, `apply` with the merge only,
`report`, and their tests. The push of a replay stays with P1-014 (step 5), which adds it to the
same `apply`. The rules stay with P1-021.

deferrals:
- From P1-014 (#193), as P1-012 deferred them there: per-pull-request steps for `report`. The push
  hand-off `{main, pr, expect, tree}`, the retry of a failed read and a `conclusion` filter on
  `workflow_run` stay with P1-014.
- The amendment's open item: a `check_run` trigger, added only if a real run stalls.
- From P1-019: the shadow window starts at P1-019's merge.

owner_decisions:
- **Settled by the owner's acceptance (15 Nov):** call 3 keeps (a comment may start `decide`, and
  such a run can now reach `apply`); call 4 unchanged (no timer); N4 (ship before step 5, as rows
  A1 to A4, with the updater app in `trusted` as the merger and the switch a constant in
  `land.yml`); N5 (stacks stay out).
- **Root's defaults, made at plan time:** `LAND_MERGE` ships `on`; the digest form and the
  `answers` output above; the window of the shadow evidence starts at P1-019's merge.

### Shadow evidence

Section 6's bullet below sets the bar. The window: records whose `tool` is P1-019's merge commit
or later, fetched with `gate/shadow-fetch.sh kitimark/mitos <the date of that merge> <dir>` and
scored with `mitos-gate shadow` built from `main`. A scorer built after P1-018 marks every record
made before it as drifted wherever P1-018 changed the plan, so those records cannot count, and
records from before P1-019 never read a typed approval.

### The amendment's text for this row

Section 6, row A3:

| Row | Change | Needs | Merged by |
|---|---|---|---|
| A3, new | `land.yml`: `decide`'s outputs, `apply` with the merge only, `report`. `land-apply.sh` and its test. | A1, A2, the shadow evidence | the owner, by hand (`.github/`): the last kept PR merged that way |

Section 2, what must hold before the workflow merges:

| Must hold | Observation | Decided or enforced by |
|---|---|---|
| The approval is the last thing the owner typed on the PR: only `/land <commit>`, unedited | `words` | Lean: 15, 16 and the three reader statements of section 3 |
| `carry` reaches that commit from the live head | `pushes`, `ids` | Lean: 15 |
| A passing verdict covers the head, as the `covered` amendment says | `author`, `verdicts` | Lean: 15 |
| CodeRabbit reviewed this content | `botAt` | Lean: 15 |
| `gate` is green at the head, and the head is on `main`'s tip | `gate`, `base` | Lean: 15. GitHub checks again at the call (strict, `gate` from GitHub Actions, admins bound) and answers 405. |
| Protection binds everyone | `enforced` | Lean: 7 and 15 |
| `spec-approved` where the diff needs it, no unanswered owner comment (comments, review comments, reviews), one footer | `rest` | Lean: 15. CI checks the label too. |
| Open, not a draft, based on `main`, same repository, not in a stack | `updatable` | Lean: 15. GitHub refuses a draft. |
| It is next and not stuck (red `gate`, conflict, a replay that changes content) | the queue | Lean: 3 and 15 |
| The head is still the one decided | none | workflow: `sha=`, and GitHub answers 409 |
| The conversation is still the one decided on, and this is the run's first attempt | none | workflow: `apply` reads again |

- **Spec PRs keep two owner actions:** the label, then the line. A label alone lands nothing, and the line alone lands no spec diff.
- **Stacks stay out.** `updatable` is false for every PR in a stack, so the workflow never calls `merge-async`. That route merges every open PR below the one named, verdict or not.
- **Two things stay as they are today.** Verdicts come from the dashboard cell, which agents write, and a label event shows no app. Neither lands anything without the typed approval.

Section 4:

| Job | Holds | Does |
|---|---|---|
| `decide` | no key, as today | Builds `main`'s tool and prints the decision. New outputs: the plan, the approval's comment id, and a digest of the PR's conversation (the id and `updated_at` of every comment, review comment and review). |
| `apply` | the updater app's key, environment `trusted`, no toolchain, no PR code | Acts only on a `merge` plan. |
| `report` | `pull-requests: write`, no key, posts as `github-actions[bot]` | One comment per change of answer to an owner word. |

**`apply`, in order.**

1. Stop unless the constant `LAND_MERGE` in `land.yml` is `on` and this is the run's first attempt.
2. Read the PR again: open, not a draft, and its head is the planned head.
3. Read its three comment routes again. Stop if the digest differs, which means a comment was added, edited or deleted since `decide` read. Stop if the approval comment is not from the owner's login, has an app or is edited.
4. Make one call with the app's token: `PUT repos/{owner}/{repo}/pulls/N/merge -f merge_method=rebase -f sha=<head>`. There is no retry, no `merge-async` and no `bypass_rules`. A 405 or a 409 is GitHub's own refusal (behind `main`, `gate` not green, head moved), and the next trigger plans again.

**Permission.** The route needs `Contents: write`. PR #13 set the app up with Contents, Pull requests and Workflows write, so nothing new is asked. No bypass exists or is given: classic protection and the ruleset on `main` both bind the app. A merge made with the app's token starts `push` on `main`, which starts the next `decide`.

**`report` posts.** Each starts with `<!-- land-report -->`, which watchers drop like owner-ping.

| Outcome | First line |
|---|---|
| merged | `Landed <head> on your /land. main is <sha>.` |
| bare `/land` or other text, on a kept path | `This PR touches a path you keep. To approve and merge it, comment only this line:`, then `/land <head>` in a code block |
| queued | `Queued at <head>: waiting for <#N to land first, the replay, or gate>.`, once |
| held | `Held by your /hold, an edited comment or a failed read. Comment /land <head> to go on.` |
| a later owner comment | `Your later comment paused it. Comment /land <head> again to go on.` |
| new content since the commit named | `<head> is new content since <commit>. After its verdict, comment /land <head>.` |
| not eligible | `Stopped:`, then each clause it lacks: no covering verdict, no bot review, an unanswered comment or a missing `spec-approved`, a draft or a stack, protection |
| stuck | `Stopped: <red gate, conflict, a replay that changes content, a history error, or a failed read>.` |
| merge call failed (not 405 or 409) | `Merge call failed: <status>.`, with the run link |

Open item: a bot review or a verdict that arrives after the last trigger starts no run, so the merge waits for the next trigger. A3 adds a `check_run` trigger if a real run stalls.

Section 5, the cases this row adds:

**To write.**

- **`land-apply.test.sh`, with a stub `gh`.** It refuses a second attempt, a moved head, a draft, a changed digest (a new, an edited and a deleted comment), an approval comment with an app, any plan that is not `merge`, and the constant off. Otherwise it sends exactly one `PUT` with `sha=`.
- **Real runs on throwaway PRs, where the owner types.** A typed approval is merged by the app at that head. A bare `/land` gets the answer. An agent's `/land <head>` does nothing. An edit, a `/hold`, a later comment and a push each stop it. A PR that edits a workflow file merges. A re-run of a finished run is refused. A comment from the owner's own `gh` reads as typed.

Section 6, the bullets about this row:

- **It ships before step 5.** The old loop keeps every branch on `main`'s tip, and `carry` covers its pushes. So an approved PR merges when its `gate` turns green there, and a race ends in a 405 or a 409.
- **Shadow evidence for A3.** In the scorer's report on #191, every kept PR that the owner merged in the window reads `agrees`. With only owner entries in the queue, that reading is the `merge` plan at the merged head. Each `disagrees` is explained in A3's PR body.
- **Rollback, lightest first.** `/hold` on one PR. Then the owner disables the `land` workflow (`gh workflow disable land.yml`), or merges by hand a one-line PR that sets the constant off. Then revert A4 and A3. A1 and A2 stay, because nothing acts on a `merge` plan then. The owner can merge by hand at any time, as today.

## Done when
- [ ] `land-apply.test.sh` and `land-report.test.sh` pass, and run in ci
- [ ] `land-decide.test.sh` and `land-protection.test.sh` pass; actionlint and shellcheck report
      nothing
- [ ] the shadow evidence is posted on #191, with each `disagrees` explained in the PR body
- [ ] after the merge: each real run of section 5 on a throwaway pull request, reported on #179
- [ ] all `checks` pass locally
- [ ] run-log record written (ops/runs/)
