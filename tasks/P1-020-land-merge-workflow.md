# tasks/P1-020-land-merge-workflow.md

phase: 1
goal: On a `merge` plan, `land.yml`'s `apply` job reads the pull request and its conversation again and makes the one pinned rebase-merge call with the updater app's token, and `report` answers each change of answer to an owner word, so a kept pull request lands on the owner's typed `/land <commit>` with no Claude session calling the merge.
statement: none locked (workflow tooling). It acts on P1-018's `PlannedMergeIsGated` (15) and P1-019's `KeptMergeIsTheOwnersTypedApproval`, and adds the gate statements under `statements` below.
touches: .github/workflows/land.yml, .github/workflows/update-prs.yml (its mint step and the two `uses:` pins of that job only, #284 O3), .github/workflows/ci.yml (three test steps, and the name of the protection test's step), .github/scripts/land-decide.sh, .github/scripts/land-decide.test.sh, .github/scripts/land-digest.sh, .github/scripts/land-apply.sh, .github/scripts/land-apply.test.sh, .github/scripts/land-report.sh, .github/scripts/land-report.test.sh, .github/scripts/land-workflow.lib.sh, .github/scripts/app-token.test.sh, .github/scripts/land-protection.test.sh (its `land.yml` pins narrow to the `decide` job), gate/MitosGate/LandAnswer.lean, gate/MitosGate/LandCli.lean, gate/Main.lean, gate/MitosGate/Land.lean (two comments), gate/MitosGate/Snapshot/Types.lean, gate/MitosGate/Snapshot/Fields.lean, gate/MitosGate/Snapshot/Obs.lean, gate/MitosGate/Snapshot/Fixtures.lean, gate/MitosGate/Snapshot.lean, gate/MitosGate/SnapshotCli.lean, gate/snapshot-test.sh, gate/MitosGate/Shadow/Types.lean, gate/MitosGate/Shadow/Reading.lean, gate/MitosGate/Shadow/Seat.lean, gate/MitosGate/Shadow/Finding.lean, gate/MitosGate/Shadow.lean, gate/MitosGate/ShadowCli.lean, gate/MitosGate/ShadowCli/Read.lean, gate/provenance-provider-test.sh, gate/shadow-fetch.sh, gate/shadow-test.sh, gate/shadow-fixtures/, gate/land-test.sh, this file, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, models, .claude/, .cursor/, CLAUDE.md, docs/process.md, plan/, .github/scripts/rebase-prs.sh, .github/workflows/land-protection.yml, .github/scripts/land-protection.sh, gate/snapshot-fetch.sh (this row adds no read to `decide`), gate/MitosGate/Speech/ (the comment reader stays P1-019's)
checks: actionlint, shellcheck, land-decide.test.sh, land-apply.test.sh, land-report.test.sh, land-protection.test.sh, app-token.test.sh, every gate/*-test.sh, lake build (each module's axiom check: no `sorry`, no new axiom), cheats (in ci), the real runs under `fixtures`
budget: 30 iterations · 10h wall · 3M tokens, the real runs included (was 25 · 8h · 2.5M; the folded #319, #303 and #284 items add about a fifth)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-020 in `plan/phase-1.md` (Land track), row A3 of the auto-merge amendment (#178,
  comment 6890739593, accepted by the owner on 15 Nov in #179, comment 6890996353); issue #297;
  tracker #179.
- Needs P1-018 (A1: the `merge` plan, `OwnerWord`, #301), P1-019 (A2: the reader that approves,
  #305, merged 15 Nov 19:28 UTC) and #245's protection reader (#278). All three are on `main`.
- Who builds: the owner delegated the build to their Codex agent (#297, comment 6900049338). A
  Claude verifier checks the build PR, plus an `opus` verifier at `xhigh`, because it is
  trust-critical.
- Who merges: the owner, by hand (`.github/`, `gate/`). It is the last kept pull request merged
  that way.
- Built before it: step 3's `decide` (P1-012, #260 and #262), whose recorder does not change and
  whose report is the evidence. P1-021 (A4) follows it at once, after its real runs.
- Folded in (#297, comments 6897897826 and 6899548896): items 1 to 3 of #319, items 6 and 7 of
  #303, and #284 item O3.
- Not checked by the amendment: the workflow, `apply` and `report`; a merge by the app, with or
  without a workflow file in the diff, and whether that needs Workflows write; the app's live
  permission list; a comment from the owner's own `gh`. Each gets a decision and a real run under
  "Decisions on what the amendment did not check".

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists. The sketches below were checked on 15 Nov against `main` at 2277138 (#312's shadow change
included): every Lean sketch builds with `lake build` or
`lake env lean`, its statements proved and its fixtures passing `decide +kernel` on the three
standard axioms; `land.yml` and the `update-prs.yml` hunk pass actionlint 1.7.12 (with shellcheck);
the three scripts pass shellcheck, the digest ran on the live reads of #305, and `land-apply.sh`
and `land-report.sh` ran against a stub `gh` (the cases named in `fixtures` as "smoke-checked").

depth: build. A sketch that type-checks and parses, plus named fixtures. The row's issue links this
file at build depth.

revisit_when: none. P1-018, P1-019 and #278 are on `main`.

modules: one topic per file.

| File | The one topic it owns | Budget | Copies the layout of |
|---|---|---|---|
| `gate/MitosGate/LandAnswer.lean` (new) | what the land workflow answers to an owner word, and what it hands to `apply`: types, `reply`, `answers`, `handoff`, the rendered lines, statements, `namespace Fixture`, the axiom check | ~230 | `Shadow/Reading.lean` |
| `gate/MitosGate/LandCli.lean` | adds `answersJson` and `answersCli` (`mitos-gate land-answers`), which prints with plain `IO.println`, not `ciLine` | +40 | its own `cli` |
| `gate/Main.lean` | one dispatch line and one usage entry | +5 | — |
| `gate/MitosGate/Land.lean` | `Plan.merge`'s doc comment (#303 item 6), `wake`'s comment (#303 item 7) | ±6 | — |
| `Snapshot/Types.lean` | `Post.review : Option Nat` | +3 | — |
| `Snapshot/Fields.lean` | `submittedPosts`, `ReviewCommentsSpeakWhenSubmitted` (#319 item 2); `posts` passes `none` | +45 | — |
| `Snapshot/Obs.lean` | `summarySpeaks`, `ownerReviewWithoutPost`, `reviewsSpeak`, `spokeInReview` (#319 item 1), the strengthened `KeptMergeIsTheOwnersTypedApproval` (#319 item 12) | +30 | — |
| `Snapshot/Fixtures.lean` | the fixtures under `fixtures`; the `Post` literals gain `, none` | +45 | — |
| `Snapshot.lean` | the axiom check names `reviewCommentsSpeakWhenSubmitted` | +1 | — |
| `SnapshotCli.lean` | reads `pull_request_review_id`; builds `reviewComments` through `submittedPosts` | +8 | — |
| `Shadow/Types.lean`, `Reading.lean`, `Seat.lean`, `Finding.lean`, `Shadow.lean` | `Summary`, `Merge.summary`, `reading`'s new argument, `ASummaryOnlyTakesAgreementAway` (#319 item 3) | +45 | — |
| `ShadowCli/Read.lean`, `gate/shadow-fetch.sh` | `repo.json`, each merge's `reviews` and `reviewComments`, `summary` through `Snapshot.reviewsSpeak` | +30 / +12 | — |
| `.github/workflows/land.yml` | when each job runs and what it holds | ~170 | itself; `land-protection.yml` for the keyed job |
| `.github/scripts/land-digest.sh` (new) | one pull request's conversation as one SHA-256 | ~30 | `land-protection.sh` (usage, `die`, exit 2) |
| `.github/scripts/land-decide.sh` | adds `handoff`, which writes `decide`'s outputs | +30 | itself |
| `.github/scripts/land-apply.sh` (new) | `apply`'s steps and the one `PUT` | ~90 | `land-decide.sh` (`die`, exit 2 on usage, `timeout -k 5 120` on each `gh api`) |
| `.github/scripts/land-report.sh` (new) | one post per change of answer | ~90 | same |
| `.github/scripts/land-workflow.lib.sh` (new) | `job_block <workflow> <job>`: the lines of one job, for the three workflow-pin tests | ~15 | `.claude/scripts/lib/` |
| `land-apply.test.sh`, `land-report.test.sh` (new) | each script against a stub `gh`, plus its job's pins | ~320 / ~240 | `land-decide.test.sh` (`ok`/`bad`, `start`/`note`/`finish`, one summary line) |
| `.github/scripts/app-token.test.sh` (new) | every mint of the updater app's key is pinned, narrowed and in `trusted` | ~70 | same |
| `.github/workflows/ci.yml` | `land-apply.test.sh`, `land-report.test.sh` and `app-token.test.sh` in the `checks` job beside `land-protection.test.sh`; none needs the built tool. That step's name says "holds the only key", which this row makes wrong, so it becomes "The protection reader's key reads only administration, and it pairs with land's decide" | +9 | — |

types (the Lean ones are in the sketches):
- `LandAnswer.Waiting = behind (pr) | replay | gate`
- `LandAnswer.Answer = unnamed (head) | queued (head) (why) | held (head) | spoke (head) | stale (head about) | notEligible (lacks : List Shadow.Clause) | stuck (why : Land.Stuck)`
- `LandAnswer.Reply = answer (a) | landing (head)`, and `LandAnswer.Handoff = {pr, head, approval}`
- `Snapshot.Post.review : Option Nat`; `Shadow.Summary = silent | spoke`, `Shadow.Merge.summary`
- `mitos-gate land-answers`: one line, `{"merge": null | {"pr": N, "head": "<sha>", "approval": N}, "answers": [{"pr": N, "line": "<first line>", "body": "<!-- land-report -->\n…"}]}`
- `decide`'s outputs, plain strings: `pr`, `head`, `approval`, `digest` (all empty unless `apply`
  has a merge to act on) and `answers` (the list above)
- `apply`'s output `outcome`, one line: `{"kind":"stopped","why":"off|attempt|input|read|pr|digest|approval"}`,
  `{"kind":"refused","status":"405|409"}`, `{"kind":"merged","main":"<40 hex>"}` or
  `{"kind":"failed","status":"<3 digits>|none"}`

statements (gate statements, not locked; each proved in the sketches):
- `LandAnswer.AnswersOnlyOwnerWords`: `(reply q o).isSome ↔ o.word ≠ .none`.
- `LandAnswer.LandingIsThePlannedMerge`: `reply q o = some (.landing h) ↔ o.word = .stands ∧
  plan q = .merge o.pr o.head ∧ h = o.head`. So `decide` answers every pull request with an owner
  word except the one `apply` acts on, which `report` answers from `apply`'s result.
- `LandAnswer.HandoffIsThePlannedMerge`: `handoff q = some x → plan q = .merge x.pr x.head ∧ ∃ e o,
  next q = some (e, o) ∧ o.pr = x.pr ∧ o.head = x.head ∧ e.lander = .owner ∧
  e.mark.said = 2 * x.approval ∧ newestOwner o.words = some (.ownerLand e.mark)`, from
  `plannedMergeIsGated`.
- `Snapshot.ReviewCommentsSpeakWhenSubmitted` (#319 item 2): `submittedPosts vs ps = some ps' →
  ∀ p ∈ ps', ∀ id, p.review = some id → ∃ v ∈ vs, v.id = id ∧ v.submitted ≤ p.lastSpoke`.
- `Snapshot.KeptMergeIsTheOwnersTypedApproval`, strengthened. Its last clause becomes three:
  `∀ s ∈ reviewPosts r, speaks g s → s.lastSpoke < c.created` (was `s.created`, #319 item 12),
  `summarySpeaks g (r.reviews.getD []) = false`, and `∀ v ∈ r.reviews.getD [], ownerReviewWithoutPost g r v = false`
  (#319 item 1).
- `Shadow.TheWordIsOnlyAssumedWhenReady`, updated: `(∃ x, reading s os o = .oneWordAway x) ↔
  s = .silent ∧ step (outsider o).1 (queueOf os) o = .stop .noEntry`.
- `Shadow.ASummaryOnlyTakesAgreementAway` (#319 item 3): `finding (seat {m with summary := .spoke}
  rs) = .agrees → finding (seat {m with summary := .silent} rs) = .agrees`.

The two checks only the workflow makes (the last two rows of the amendment's section 2 table) are
pinned by `land-apply.test.sh` and by the real runs.

reuse:
- `land.yml` and `land-decide.sh` (P1-012, with #278's change): `decide` changes only by its
  outputs and the `handoff` call; the record and its shape do not change.
- `LandCli.read`, so `land-answers` refuses exactly what `land` refuses; `land`'s printed decision
  does not change, so the shadow's drift check (`ShadowCli/Read.lean`) is untouched.
- `Shadow.outsider` (the workflow sees steps as a teammate that is no delegate, as the shadow does),
  `Shadow.lacks` and `Shadow.Clause` for the "Stopped:" clauses.
- `Snapshot.reviewsSpeak`, including its shared `speaks`/`counts`/matching-post rules, and both
  SnapshotCli review-route decoders in the shadow. There is one review predicate and two users.
- `land-protection.yml`'s pins: `actions/checkout@11d5960…` (v4.4.0) and
  `actions/create-github-app-token@d72941d…` (v1.12.0).
- `update-prs.yml`'s environment `trusted`, `vars.PR_UPDATER_APP_ID`, `secrets.PR_UPDATER_APP_KEY`.
- `land-decide.test.sh`'s stub `gh`, which each new test copies, and its block extractors, which
  become `land-workflow.lib.sh`'s `job_block` (the lib holds nothing else).
- `shadow-fetch.sh`'s `by_number`.

fixtures (each name, then what it pins):

Lean, `MitosGate.LandAnswer.Fixture`, all `decide +kernel` over `Land.Fixture` (each passes in the
sketch):
- `aBareLandOnAKeptPathAsksForTheLine`: `unnamed "aaa"`, and its body is the marker, the line, a
  blank line and `/land aaa` in a code fence.
- `theApprovedGreenHeadIsLeftToApply`: `reply = landing "ar"`, `handoff = ⟨153, "ar", 450⟩`, and
  `answers` is empty.
- `anotherLandingGoesFirst`: "Queued at ar: waiting for #153 to land first."
- `aBehindHeadWaitsForTheReplay`: "Queued at aaa: waiting for the replay."
- `aPushedHeadWaitsForGate`: "Queued at ar: waiting for gate."
- `aHoldIsHeld`, `aLaterCommentPausesIt`
- `newContentNamesBothCommits`: "fff is new content since aaa. After its verdict, comment /land fff."
- `eachMissingClauseIsNamedInOrder`: "Stopped: no covering verdict, no bot review."
- `unenforcedIsProtection`: "Stopped: protection."; `aRedGateIsStuck`: "Stopped: red gate."
- `noOwnerWordNoReply`, `anOddPositionHandsNothing`

Lean, `Snapshot.Fixture` (the first five were evaluated with `#eval` on the sketch; the fixtures
file itself was not built in scratch, where Lean ran out of memory):
- `aSummaryEmptiedAfterTheApprovalRetiresIt` (item 1's regression): `planOf = .idle`.
- `aSummaryEmptiedBeforeTheApprovalRetiresItToo`: `.idle`. No route gives the edit time.
- `aReviewWhoseCommentsWereDeletedRetiresIt`: `.idle`.
- `anAgentFooterReplyAfterTheApprovalLeavesIt` (#319 item 4): an empty owner review holding its own
  footer reply gives `.merge`. It pins that `ownerReviewWithoutPost` spares thread replies with a matching review ID.
- `aDraftedCommentSubmittedAfterTheApprovalRetiresIt` (item 2): `.idle` after `submittedPosts`.
- `aCommentOfAnUnlistedReviewIsAFailedRead`: `submittedPosts = none`.
- `aDraftedCommentAnswerBeforeSubmissionIsNoAnswer`: `rest` stays false.

Lean, `Shadow.Fixture` (each passes in the sketch):
- `aSummaryWithTextIsNotOneWordAway`: `reading .spoke [unsaid] unsaid = .asRead (.stop .noEntry)`.
- `aSummaryLeavesATypedWordAsRead`: `.asRead (.present "ar")`.
- `anOwnerSummaryTakesTheAssumedWordAway`: `finding … = .disagrees .noEntry`.
- `shadow-test.sh`: one window merge whose pull request has an owner summary reads
  `disagrees noEntry` in `window.expected`.

`land-test.sh`: `land-answers on the fixture` (with #153's word made a bare `/land`, `jq -e .`
exits 0 on the output and `.answers[0].body` decodes with a real newline after the marker:
`jq -e '.answers[0].body | startswith("<!-- land-report -->\n")'`), `the planned merge hands its
approval`, `a refused snapshot is refused by land-answers too`.

`snapshot-test.sh`: `a review comment without pull_request_review_id is a failed read`,
`a review comment of an unlisted review holds`. Its existing review-comment fixtures (the
`review-comments-9.json` writes of the cases "the owner's post on $route after the approval", "the
owner's review comment edited after the approval", "an owner review summary with text before the
approval" and "/land <commit> in a review gives no word") are migrated to carry
`pull_request_review_id` and a review listed in `reviews-9.json`, or the new rule fails their read.

`land-decide.test.sh`:
- `decide-outputs-on-a-merge-plan`: 40-hex heads; pins `pr`, `head`, `approval` and `digest` (the
  digest is `land-digest.sh` over the stub reads), and `answers` equals the real tool's.
- `no-merge-hands-nothing-to-apply`: on a push plan and on idle, `pr`, `head`, `approval` and
  `digest` are empty, and `answers` is written.
- `land-and-land-answers-disagree-is-refused`: a stub `land-answers` that names another merge
  exits 1 and writes no output (B's tripwire).
- `a-merge-without-its-reads-is-not-handed-on` and `answers-over-the-cap-are-refused`: exit 1, the
  record unchanged, no output.
- `the-marker-is-the-reports`: the body from `land-answers` starts with `land-report.sh`'s marker.
- `holds-no-key`, narrowed to the `decide` block; `filter-pins`: `needs.*.outputs` appear only in
  `env:` and job `if:` lines.

`land-apply.test.sh` (stub `gh` logs `<token>|<args>` per call and fails on any call outside the
four reads, the one `PUT` and the one read-back):
- `merges-once-pinned-to-the-head` (smoke-checked): four reads with `GH_TOKEN`, then exactly one
  `api -X PUT repos/owner/mitos/pulls/153/merge -f merge_method=rebase -f sha=<head>` with
  `LAND_MERGE_TOKEN`; `merged` with `main` from the answer's `sha`.
- `the-switch-off-calls-nothing` (`off`, `ON`, `true`, `on `, empty) and
  `a-second-attempt-calls-nothing` (`2`, `0`, `01`, empty) (smoke-checked for `off` and `2`).
- `no-merge-plan-calls-nothing`: with no planned merge `pr` is empty, so the job's `if:` skips
  `apply`, and the script itself stops `input` with no call (the amendment's "any plan that is not
  `merge`").
- `bad-input-calls-nothing`: a pr of `012` or 8 digits, an upper-case or short head, an approval of
  `0`, a digest that is not 64 hex, an owner id that is not a number, an empty token
  (smoke-checked for the head).
- `a-moved-head-stops`, `a-draft-stops`, `a-closed-or-merged-pull-request-stops`,
  `another-base-stops`, `a-fork-stops`: `pr`, no `PUT`.
- `a-new-comment-stops`, `an-edited-comment-stops`, `a-deleted-comment-stops`,
  `an-edited-review-stops`, `a-new-review-comment-stops`, `a-bot-edit-stops`: `digest`, no `PUT`
  (smoke-checked for one).
- `an-approval-from-another-login-stops`, `the-same-login-with-another-id-stops`,
  `an-approval-with-an-app-stops`, `an-edited-approval-stops`, `an-absent-approval-stops`:
  `approval`, no `PUT` (smoke-checked for two).
- `a-failed-read-stops`: each of the four reads exits 1 or gives junk: `read`, no `PUT`.
- `405-and-409-are-refusals-with-no-retry` (smoke-checked), `another-status-is-a-failure` (401,
  403, 422, 500), `a-200-that-did-not-merge-is-a-failure`.
- `a-lost-answer-reads-once`: no status, then one read of the pull request: `merged` when it merged
  at that head, else `failed` with `none` (smoke-checked for the second). Still one `PUT`.
- `the-app-token-only-merges`: the merge token is in no read, output, file or argument.
- `every-call-has-a-timeout`; `no-merge-async-no-bypass`: one `-X PUT`, `merge_method=rebase`
  only, and outside the tests the only `pulls/…/merge` in `.github/` is in `land-apply.sh`.
- `digest-*`, run on `land-digest.sh` itself with reads copied from #305: the same reads give the
  same digest (checked live); page split, order and a repeated item change nothing (a repeated
  item checked); an added, deleted or edited item, a moved `updated_at`, a changed login, app or
  state each change it (an edited body checked); a flat list, an error object, an empty page list or two JSON values
  exit 1 (an error object checked); `$(…)`, backticks and newlines in a body are data.
- `holds-the-key-only-to-merge`: `apply` is the only job in `trusted`, in group `land-apply` with
  `cancel-in-progress: false`; its `if:` names `refs/heads/main`, `github.run_attempt == '1'` and
  `needs.decide.outputs.pr != ''`; its permissions are exactly `contents`, `pull-requests` and
  `issues`, all `read`; the mint is the pinned one with exactly `permission-contents: write` and
  `permission-workflows: write`, under `if: env.LAND_MERGE == 'on'`; `steps.app.outputs.token`
  appears once; the checkout is the pinned one with `sparse-checkout: .github/scripts`,
  `persist-credentials: false` and no `ref:`, `repository:` or `token:`; no `lake`, install script
  or cache; no `github.event` in the job; `LAND_MERGE: 'on'` appears once, at workflow level.

`land-report.test.sh` (stub `gh` allows only the comment reads and one post per pull request):
- `each-answer-posts-its-body` with real newlines, `the-same-answer-posts-nothing`, and
  `a-bare-land-after-a-push-posts-the-new-head` (all three smoke-checked),
  `the-newest-report-decides`, `one-post-per-pull-request-per-run`.
- `a-forged-marker-is-ignored`: a marker comment from another login, from a user named like the
  bot, or without app `github-actions` does not suppress a post.
- `landed-names-head-and-main` (smoke-checked); `a-failed-call-posts-its-status-and-the-run` (exit
  1, smoke-checked); `a-failed-apply-job-posts-no-outcome` (exit 1).
- `not-merged-yet-for-digest-approval-read-off`: each gives its line of the table below.
- `a-refusal-or-another-stop-posts-nothing` (smoke-checked for 405), `a-skipped-or-cancelled-apply-posts-nothing`.
- `why-codes-are-worded`: every `stop <code>` in `land-apply.sh` is a case of `land-report.sh`
  (`attempt`, `input` and `pr` as the ones that post nothing).
- `every-post-starts-with-the-marker`; `no-post-mentions-anyone` (a body with `@` is refused,
  smoke-checked); `malformed-answers-call-nothing`; `the-planned-pr-among-answers-is-refused`
  (smoke-checked); `a-failed-read-skips-that-pull-request-and-fails-the-job`.
- `report-holds-no-key`: exactly `contents: read` and `pull-requests: write`; no secret,
  environment, app or concurrency group; the pinned sparse checkout.

`app-token.test.sh`: `every-mint-is-pinned-to-a-commit`, `every-mint-names-its-permissions` (at
least one `permission-` input, each of contents, pull-requests, workflows or administration),
`every-mint-is-in-trusted`, `the-updater-mints-what-it-pushes-with` (exactly contents,
pull-requests and workflows, all `write`).

`land-protection.test.sh`: `the key stays out of decide`. Its check that `land.yml` names no
secret, environment or write now covers the `decide` block only; without that change it goes red.

Mutants the verifier sees killed: the digest compare removed; a digest over issue comments only; the
head check removed; `sha=` from the re-read pull request; a retry around the `PUT`; the merge token
on a read; the switch test written as `!= off`; the attempt check removed; the app, `created ==
updated`, `user.id` or login check removed; `merge_method=squash`; `unique` dropped from the
digest; the `PUT` moved before the third read; the report's marker filter widened; the dedupe
removed; a job `if:` without `run_attempt`; a second `permission-` on `apply`'s mint dropped or
added; a checkout `ref:`; in Lean, `/ 2` dropped in `handoff`, `landing` returned for a queued word,
`emptied` without its comment test, `submittedPosts` without the `max`.

The real runs are under "Real runs", the shadow evidence under "Shadow evidence".

cut_line: four sequential owner-merged units, each `Part of #297`, split from #336. The root
selected B+C → N → T → F in response to the user's split goal; this grouping is not an owner
policy ruling. The [public split correction](https://github.com/kitimark/mitos/pull/336#issuecomment-6980973854)
records the corrected boundary.
Each PR carries its definitions, proofs, fixtures, caller migration and current-head checks.
Typed answers stay with their producer and report consumers in F. The push of a replay
(P1-014), the rules (P1-021) and a `check_run` trigger remain deferred.

### Split design, 18 November 2026

B+C repairs deployed review observation and its actual Shadow counterfactual together. At the
historical B-only checkpoint `0ed3425`, a postless owner review was erased from an unsigned saved
observation: synthetic approval presented while a fresh actual approval refused. The root
[re-grounded the boundary](https://github.com/kitimark/mitos/pull/488#issuecomment-6981000804)
before any owner merge. The old B → C seam is superseded; its CI/review evidence stays head-bound.
N admits the existing owner-ping behavior as an ordinary workflow document. T replaces the
current workflow assertions with one complete native contract used by their existing callers.
F alone adds the producer handoff, merge and report effects. The four-unit grouping removes
stable checks from the activation diff without leaving this known scorer mismatch on main.
It adds three review and CI cycles versus one final PR. No time saving has been measured.

| Unit | Complete ownership | Depends on |
|---|---|---|
| B+C, review observation and readiness | The twenty paths below: reader, required Summary, every caller/proof, raw window production and native controls | Current main |
| N, owner-ping admission | Expanded source, oracle, allowlist removal, differential and parity controls | Current main |
| T, current workflow contract | Complete native checker, current decide/protection/app-token callers, two-caller bundle controls, immutable refs, placement controls and three real post-build suites | N |
| F, activation | Answers, handoff/digest/caps, apply/report, exact final workflow contract, third mint caller and five suites | B+C, N, T and all existing acceptance evidence |

T is new current-contract design work, not a literal extraction of the final checker. Its one
`workflow pins <repo-root>` command admits every workflow and conjoins the complete Land,
Protection, updater/mint, CI and the two-copy owner-ping coherence contract. Callers choose no profile.
The current implementation design is `tasks/GA-Q3-current-workflow-pins.md`. At T, Land is
decide-only, without a switch, outputs, apply/report, key or mint. The mint inventory contains
only Protection and updater, and CI requires the three actual post-build suites. F replaces
that finite contract with the exact decide/apply/report/on shape, three mint callers and five
suites. F deletes the current-only absence statements and fixtures with their replacements.
T's CI contract covers the closed current entrypoints and required build/test shapes and schedule.
The earlier-setup shell-hook residual remains in #466 item 2 and #453, outside that finite contract.

Before T replaces an assertion, map it to its complete decoded counterpart. Retain runtime
IO/timeouts, whole Protection/updater closure, inherited INPUT_/GITHUB_ENV controls, all thirteen
updater reference sites across each supported representation, the closed remaining-workflow inventory and the once-only bundle
helper. Test real current-shape mutations, not absent future anchors. Four actual-bundle controls
cover two callers until F adds the third pair. A partial mint check is not input safety.

Stop and re-ground T if it needs selectable shapes, permanent duplicate checkers, detached
future APIs, a dropped assertion or unexplained growth beyond its estimated 115–220 adaptation
lines. The fallback moves independent corrections, normalization, refs and placement first,
then keeps one complete final authority transition. It does not introduce a permissive profile.
No GA-Q3 implementation changes belong in B+C.

B+C's module map is atomic. Physical deltas are against main `e0e8a29`; data fixtures are synthetic.

| File | The topic it owns in B+C | Physical delta |
|---|---|---|
| `Snapshot/Types.lean` | Post review identity | +1/-0 |
| `Snapshot/Fields.lean` | Submission normalization and lower-bound theorem | +49/-2 |
| `Snapshot/Obs.lean` | Review retirement and the complete kept-approval guarantee | +37/-26 |
| `Snapshot/Fixtures.lean` | Preserved reader cases and isolated submission sensitivity | +51/-5 |
| `Snapshot.lean` | Complete Snapshot/provenance standard-axiom audit | +4/-2 |
| `SnapshotCli.lean` | Listed raw-review decoding and normalization | +5/-3 |
| `gate/snapshot-test.sh` | Raw Snapshot behavior and source-valid Snapshot/Land/Shadow three-way controls | +112/-6 |
| `Shadow/Types.lean` | Required merge-side Summary domain value | +6/-0 |
| `Shadow/Reading.lean` | Review-aware counterfactual with all as-read behavior preserved | +41/-19 |
| `Shadow/Seat.lean` | Record/merge pairing and required Summary caller | +9/-2 |
| `Shadow/Finding.lean` | Agreement monotonicity under review speech | +28/-0 |
| `Shadow.lean` | Complete Shadow standard-axiom audit | +1/-1 |
| `ShadowCli/Read.lean` | Validated repository and required two-route merge evidence | +67/-4 |
| `ShadowCli.lean` | Complete window acquisition | +2/-1 |
| `gate/shadow-fetch.sh` | Bounded canonical repository and complete paginated review collection | +26/-3 |
| `gate/shadow-fixtures/window/repo.json` | Required synthetic repository metadata | +1/-0 |
| `gate/shadow-fixtures/window/merges.json` | Required synthetic review-route evidence | +1/-1 |
| `gate/shadow-fixtures/window.expected` | Honest changed synthetic score report | +2/-2 |
| `gate/shadow-test.sh` | Decode/time/positive/negative and paginated producer failure matrix | +204/-2 |
| `gate/provenance-provider-test.sh` | Preserved null-author record-v1 replay through the migrated window | +3/-1 |

The real Snapshot caller receives the existing `Reads`, with `Post.review : Option Nat`.
`submittedPosts : List Review → List Post → Option (List Post)` refuses an unlisted review and
sets each listed post's update time to at least submission. The raw CLI supplies normalized
posts only after both routes decode. `summarySpeaks` excludes recognized agent footers.
`ownerReviewWithoutPost` requires `counts v = false` and no review-comment post with that review ID.
`reviewsSpeak` combines both cases without a review-time cutoff. Counted reviews already yield
a post through `reviewPosts`. The kept-approval theorem requires `lastSpoke` before the approval
for each post satisfying `speaks g s = true`, no speaking summary and no postless owner review.
Every earlier owner/app/edit/footer/named-target/carry/latest-comment conjunct is retained.
The review-route app-field API note stays exact.

The seven original review-repair kernel fixtures retain emptied summaries before and after approval, deleted
comments, the footer-reply exception, late draft submission, unlisted reviews and an answer
before submission. The four original raw cases retain missing review identity, unlisted review identity,
late submission and an emptied summary. The late-submission kernel case retains that original
scenario and adds an answer after drafting but before submission; a before-submission positive
control isolates the bound. The source-valid native three-way controls use actual-name Claude
and canonical OpenAI/null authors with actual-name Opus/xhigh verification. They preserve null
knowledge, complete unsigned Obs equality and the correct real typed approval in each case.
Existing source/record v1, native/legacy transport, unknown/adverse identities, effort admission
and every #491 provenance/projection audit remain intact.

The constructed regression coverage exceeds the sketch's rough test-line estimates: about 80
additional Snapshot lines exercise both current-valid source identities through the actual
Snapshot/Land/Shadow seam, and about 180 Shadow lines cover parser, timing, deletion, paginated
blocker/footer and fatal-failure cases. These stay in the existing twenty-path module map; the
frozen C delta +140/-33 is historical input accounting, not the constructed B+C size.

The scorer receives required `Summary.silent | spoke` on each `Merge`. `seat` calls the one
`reading m.summary r.prs observation`: only a noEntry result may synthesize an owner word,
and only when Summary is silent. Other real steps remain as read. The migrated
`TheWordIsOnlyAssumedWhenReady` states that conjunction; `ReadyIsOneWordFromLanding` retains
its actual meaning about a transformed Land Obs. Agreement monotonicity compares the same
records and merge with different Summary values. None of these is a historical-fidelity or
real-REST-insertion commutation theorem.

`shadow <dir>` requires repo.json with full_name/owner.login and both raw arrays (`reviews`,
`reviewComments`) on every merge. Repository components use the existing route grammar
`[A-Za-z0-9_.-]+`, excluding empty/dot/dot-dot components; full_name has exactly two components
and its owner agrees case-insensitively with the preserved canonical login. The fetcher binds
metadata full_name to the requested repository and uses that same repository for all routes.
Each fetched review page is exactly one JSON array before flattening; a later-page failure
cannot produce a usable successful window.

The CLI reuses both SnapshotCli route decoders before inclusive submission/creation-time
filtering, then derives Summary through the shared `Snapshot.reviewsSpeak`. Missing/malformed
evidence refuses with no favorable stdout. Preserve existing pending/null-body/null-user
semantics. C deliberately adds no `submittedPosts` join: its predicate uses body/counts/matching
IDs, while the real Snapshot's listed-ID normalization remains unchanged. Current route data
cannot reconstruct deleted posts or prior edit text; this is no historical fidelity claim.
The checked-in synthetic window, both test-window branches and the provider replay caller
migrate together. Archived record-v1 bytes stay unchanged; absent new window evidence refuses.

B+C includes no answers, digest overrides, workflow/budget changes or activating effects. It
grants no mint, merge or comment capability. Validate exact owner-review/postless/footer/no-review
controls, malformed late entries, inclusive times, later-page blocker/footer and failure cases,
all parent proof/audit roots, and mutations removing the Summary guard, replacing reviewsSpeak
with summary-text-only, blanket suppression or dropping submission normalization.

Run the Snapshot/Shadow/CLI axiom audits, raw/legacy/provider/recorder and Land/Carry neighbors,
the process matrix and complete current-head CI. Historical0ed CI cancelled at the 20-minute
checks deadline; the three shards and all 27 shell suites passed, but interrupted Core replay,
prove and gate supplied no full success. Deadline capacity is tracked separately in
[#493](https://github.com/kitimark/mitos/issues/493); do not rerun a timed-out obsolete head or
weaken checks/bounds here. Every new trusted content head needs fresh no-comments, independent
source review and actual qualifying Opus verification, CodeRabbit follow-up and owner merge.
The prior0ed FAIL and earlier #336 reviews remain historical, not carried verdicts.

These cuts preserve the six approved clauses below, R0b and the failed historical evidence.
They supply no positive case and do not waive activation acceptance. D/T0 remains
[`8a350a72a2928368585890c33b047fa4d32dc163`](https://github.com/kitimark/mitos/commit/8a350a72a2928368585890c33b047fa4d32dc163)
/ `2026-11-18T04:05:11Z`, with the [complete failed historical report](https://github.com/kitimark/mitos/issues/191#issuecomment-6960727741)
unchanged. After each actual merge, rebuild the residual from new main plus unlanded hunks. Never restore a
whole shared file from the old feature head. Keep archived records unchanged. Roll back dependent
units first, then B+C as the whole producer/API/schema/caller/proof unit; reverting the scorer
alone recreates the mismatch. Revert F's workflow, runtime and contract together. Turning the switch off alone
leaves producer refusals and report writes deployed.

deferrals:
- To P1-014 (#193), as before: the push of a replay in `apply`, the retry of a failed read and a
  `conclusion` filter on `workflow_run`; new: an `apply` record artifact for the shadow (today the
  job log and `report` carry the outcome).
- The amendment's open item: a `check_run` trigger, added only if a real run stalls (R15). The
  "Not merged yet" post below makes a stall caused by a digest stop visible meanwhile.
- To P1-015 (#194): the second half of #303 item 7. Off the kept paths a delegate's `step` and the
  `plan` both say merge at the same head. `Speech.delegates = []`, so only `apply` calls today; the
  step that adds delegates decides who calls, and a second call at that head gets 405 or 409.
- To #334 (not P1-021, which must not touch `gate/`): the timeline read
  that #297 (comment 6897897826) names, and a return of the summary rule to timing. Checked on #305
  (15 Nov): its reviews route lists 6 reviews and its timeline 2 `reviewed` events; the owner's two
  empty thread-reply reviews have none. So the timeline cannot stand in for the reviews route, and a
  join that holds on a missing event would hold every pull request with an owner-login thread reply.
  It can at most add an edit time for the reviews it lists, which needs a real run that edits a
  summary, and one paginated read per open pull request on every `decide`. Items 1 and 3 are fixed
  here without it.
- To P1-021 (#298): #319 item 11 (owner text typed into an agent's footer post), as #319 says, and
  the residual that a session holding the owner's own token could type `/land` with no app (call 6
  rests on the rules).
- Not this row: #319 items 4 to 10, 13 and 14 (item 4's fixture is added here only because
  `ownerReviewWithoutPost` must spare thread replies with a matching review ID), #303 items 1 to 5,
  and #284 items 1 to 8, O1, O2 and O4 to O6.
- To the real runs (R14): whether a `held` answer flaps on failed reads, or a split conversation
  read temporarily yields `ownerSpoke` when a review is submitted between the review-comment and
  review reads. A follow-up issue only if the real runs show either effect.
- From P1-019: the shadow window starts at P1-019's merge (unchanged).

owner_decisions:
- **Settled by the owner's acceptance (15 Nov), unchanged:** call 3 keeps (a comment may start
  `decide`, and such a run can now reach `apply`); call 4 unchanged (no timer); N4 (ship before
  step 5, with the updater app in `trusted` as the merger and the switch a constant in `land.yml`);
  N5 (stacks stay out). The build goes to the owner's Codex agent (#297, 6900049338).
- **Root's defaults, made in this design** (none is the owner's ruling):
  1. `decide`'s outputs are `pr`, `head`, `approval`, `digest` and `answers`, plain strings, not a
     `plan` JSON: no `fromJSON` sits in a job `if:`, and `pr` is empty unless the handoff and its
     digest are known, which fails closed.
  2. Answers are decided and rendered in Lean by a new subcommand, `land-answers`, so `land`'s
     recorded output and the shadow's drift check do not change, and the shell only glues REST
     calls. Only the lines that need the merge call's result live in `land-report.sh`.
  3. The digest is the SHA-256 of one `jq -cS` document over every issue comment, review comment
     and review of the pull request (`[id, login, app, created_at, updated_at, body]`, review
     comments with their review id, reviews `[id, login, app, state, commit_id, submitted_at,
     body]`), each route deduplicated and sorted. It holds what the plan-time line form held, with
     the full body in place of its hash, plus the identity fields the reader reads.
  4. `apply` reads with `github.token` and merges with the app token, minted only when
     `LAND_MERGE` is `on`, always with Workflows write, so a pull request that edits a workflow can
     merge.
  5. `LAND_MERGE: 'on'` is quoted, so no YAML 1.1 reader takes it for `true`.
  6. `report` compares the whole body with the newest report, not only its first line (the
     plan-time contract compared first lines; the amendment says one comment per change of
     answer). So a bare `/land` answered again after a push posts the new head's line, and a
     change of clause posts again. A line that carries the run link ("Merge call failed", "a read
     failed") posts once per run that ends that way.
  7. `report` posts "Not merged yet" on an `apply` stop that may get no further trigger (digest,
     approval, a failed read) and once on the switch off; it stays silent on 405, 409 and a moved,
     closed or drafted pull request, whose next trigger plans again.
  8. A lost merge answer gets one read of the pull request, never a second call.
  9. `report` has no concurrency group and reads the newest report just before it posts: a
     duplicate post is harmless, a lost "Landed" is not.
  10. #319 items 1 and 2 go through `pull_request_review_id`, with no new read; an emptied owner
      review retires the approval whatever its time, as a summary with text does (#305's default).
  11. #284 O3 is folded in, with the two `uses:` of that key-holding job pinned to the commits
      `land-protection.yml` uses, and a test over every mint.
  12. The shadow evidence is scored with both `main`'s and the head's scorer.
  13. `LAND_MERGE` ships `on` (the sketch's `LAND_MERGE: 'on'`): the owner's goal is that `/land`
      merges with no session calling the merge, and N4 ships the workflow before step 5, so `off`
      would need another trust-critical PR before any real merge; the owner's merge of the build
      PR is the moment it turns on, and one edit to the constant turns it off.
- **Trust-critical build:** `touches` includes `gate/` files and `.github/workflows/update-prs.yml`,
  because #319 items 1 to 3, #303 items 6 and 7 and #284 O3 live there. So the build PR is
  trust-critical (an `opus` verifier at every head) and the owner merges it.
- **New owner calls:** none. The real runs need the owner to type where marked.

### Synthesis decision

Two designs were written for this row, A (minimal surface) and B (adversarial). A is the base: it
keeps `decide` reading nothing new, renders every answer `decide` knows in Lean, hands `apply`
plain strings, and fixes #319 items 1 and 2 through `pull_request_review_id` with no new read. B's
timeline read for those items is rejected on evidence: the timeline lists no `reviewed` event for
the owner's empty thread-reply reviews (#305, above), so its "owner review with no event fails the
read" rule would hold every pull request with an owner-login thread reply, and its
`updated ≠ submitted` count would count timing noise. B's least-privilege mint (Contents only) is
rejected because a pull request that edits a workflow file is a common kept case and would fail to
merge until a follow-up; R11 proves Workflows write instead. B's digest that drops
`github-actions[bot]` comments is rejected because the amendment says every comment; its liveness
cost is answered by graft 1 below. B's jq wording table is rejected for Lean rendering (shell only
glues). Grafted from B: (1) "Not merged yet" posts for stops that may stall; (2) one read-back after
a lost merge answer; (3) no concurrency group on `report`, with a read just before each post; (4)
the digest deduplicates repeated page items and carries the identity fields; (5) the sparse checkout
of `.github/scripts` in the two keyless and keyed jobs; (6) `land-and-land-answers-disagree-is-refused`
as a tripwire in `decide`; (7) `user.id` and `user.type` in the approval check, from the runner's
own `GITHUB_REPOSITORY_OWNER_ID`, with no read; (8) `why-codes-are-worded` and the mutant list; (9)
`land-workflow.lib.sh`, so three tests share one job reader. Changed from A: `emptied` retires the
approval whatever its time, because an edit to a summary typed before `/land` has no time either;
A retired only an emptied review submitted after `/land`.

### Usage (caller's view)

The owner comments, alone in a comment on the pull request:

```
/land <the full head sha>
```

Within minutes `github-actions` answers, and the merge follows `gate` on `main`'s tip:

```
<!-- land-report -->
Landed <head> on your /land. main is <sha>.
```

A bare `/land` on a kept path gets the line to type:

````
<!-- land-report -->
This PR touches a path you keep. To approve and merge it, comment only this line:

```
/land <head>
```
````

### Contract, job by job

| Job | Holds | Reads | Writes | Decides |
|---|---|---|---|---|
| `decide` | no key; read-only `contents`, `pull-requests`, `issues`, `checks`, `actions`, as today | as today, no new read | the record (shape unchanged) and the outputs | Lean: `land` (recorded), then `land-answers` |
| `apply` | the app key in `trusted`, minted only when `LAND_MERGE` is `on`; `github.token` with `contents`, `pull-requests`, `issues` read; group `land-apply`; runs only on `main`, on attempt 1, when `pr` is set | the pull request, then its three comment routes, with `github.token` | one `PUT` with the app token; `outcome` | only equality: its inputs against what it reads |
| `report` | `contents: read`, `pull-requests: write`, no key, no group; runs when `decide` succeeded and there is an answer or a planned merge | each answered pull request's issue comments, just before posting | at most one comment per pull request | only "is this answer new?" (the whole body) |

`report`'s answer for the planned pull request, which `decide` does not answer:

| `needs.apply.result`, `outcome` | First line | `report` exits |
|---|---|---|
| success, `merged` | `Landed <head> on your /land. main is <main>.` | 0 |
| success, `failed` | `Merge call failed: <status>.`, a blank line, the run link | 1 |
| success, stopped `digest` | `Not merged yet at <head>: the conversation changed after the decision. Comment /land <head> again to go on.` | 0 |
| success, stopped `approval` | `Not merged yet at <head>: the approval is not your unedited comment. Comment /land <head> again to go on.` | 0 |
| success, stopped `read` | `Not merged yet at <head>: a read failed. Comment /land <head> again to go on.`, the run link | 0 |
| success, stopped `off` | `Not merged: the merge switch is off.` | 0 |
| success, stopped `attempt`, `input` or `pr`; `refused` | nothing: the next trigger plans again | 0 |
| `failure` | `Merge call failed: no outcome.`, a blank line, the run link | 1 |
| `skipped`, `cancelled` | nothing | 0 |

### `land.yml`

`decide` changes only by `outputs:`, `id: decide` and the step name. The file passes actionlint.

```yaml
env:
  LAND_MERGE: 'on'

jobs:
  decide:
    # if, runs-on, timeout-minutes, concurrency, permissions, env: unchanged
    outputs:
      pr: ${{ steps.decide.outputs.pr }}
      head: ${{ steps.decide.outputs.head }}
      approval: ${{ steps.decide.outputs.approval }}
      digest: ${{ steps.decide.outputs.digest }}
      answers: ${{ steps.decide.outputs.answers }}
    steps:
      # t0, checkout, cache/restore, install-elan, install-toolchains, lake build: unchanged
      - name: Decide
        id: decide
        # env and run: unchanged
      # the two upload-artifact steps: unchanged

  apply:
    needs: decide
    if: >-
      github.ref == 'refs/heads/main' && github.run_attempt == '1' &&
      needs.decide.outputs.pr != ''
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    # The app's key is a secret of `trusted`, whose deployment branch rule admits only main (see
    # update-prs.yml). No toolchain and no pull request's code runs here: the checkout is this
    # workflow's own commit, and only its scripts.
    environment: trusted
    concurrency:
      group: land-apply
      cancel-in-progress: false
    permissions:
      contents: read
      pull-requests: read
      issues: read
    outputs:
      outcome: ${{ steps.apply.outputs.outcome }}
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          sparse-checkout: .github/scripts
          persist-credentials: false
      - name: Mint an app token that can only merge
        id: app
        if: env.LAND_MERGE == 'on'
        uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547 # v1.12.0
        with:
          app-id: ${{ vars.PR_UPDATER_APP_ID }}
          private-key: ${{ secrets.PR_UPDATER_APP_KEY }}
          permission-contents: write
          permission-workflows: write
      - name: Read the pull request and its conversation again, then merge pinned to the head
        id: apply
        env:
          GH_TOKEN: ${{ github.token }}
          LAND_MERGE_TOKEN: ${{ steps.app.outputs.token }}
          LAND_PR: ${{ needs.decide.outputs.pr }}
          LAND_HEAD: ${{ needs.decide.outputs.head }}
          LAND_APPROVAL: ${{ needs.decide.outputs.approval }}
          LAND_DIGEST: ${{ needs.decide.outputs.digest }}
        run: .github/scripts/land-apply.sh "$GITHUB_REPOSITORY" "$RUNNER_TEMP/land-apply"

  report:
    needs: [decide, apply]
    if: >-
      always() && github.ref == 'refs/heads/main' && needs.decide.result == 'success' &&
      ((needs.decide.outputs.answers != '' && needs.decide.outputs.answers != '[]') ||
        needs.decide.outputs.pr != '')
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with:
          sparse-checkout: .github/scripts
          persist-credentials: false
      - name: Answer each owner word whose answer changed
        env:
          GH_TOKEN: ${{ github.token }}
          LAND_ANSWERS: ${{ needs.decide.outputs.answers }}
          LAND_PR: ${{ needs.decide.outputs.pr }}
          LAND_HEAD: ${{ needs.decide.outputs.head }}
          LAND_APPLY_RESULT: ${{ needs.apply.result }}
          LAND_APPLIED: ${{ needs.apply.outputs.outcome }}
        run: .github/scripts/land-report.sh "$GITHUB_REPOSITORY"
```

`update-prs.yml` (#284 O3), the job's two `uses:` and the mint's inputs only:

```yaml
      - name: Mint a short-lived app token
        id: app
        if: steps.cfg.outputs.ok == 'true'
        uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547 # v1.12.0
        with:
          app-id: ${{ vars.PR_UPDATER_APP_ID }}
          private-key: ${{ secrets.PR_UPDATER_APP_KEY }}
          permission-contents: write        # the rebased branch's force-push
          permission-pull-requests: write   # gh pr list, edit and comment, the needs-rebase label
          permission-workflows: write       # a branch that edits .github/workflows/

      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
```

No `permission-issues`: the app has none (Contents, Pull requests and Workflows write from PR #13,
Administration read from #278), so asking for it would fail the mint.

### Scripts

`.github/scripts/land-digest.sh` (new; `decide` runs it on its saved reads, `apply` on its fresh
ones). On #305's live reads it printed the same digest twice, the same after a page item was
repeated, another after one body changed, and exit 1 on an error object:

```bash
#!/usr/bin/env bash
# Usage: .github/scripts/land-digest.sh <comments.json> <review-comments.json> <reviews.json>
# Each file is one read of its route with `gh api --paginate --slurp`: a non-empty list of pages,
# each a list. Prints the SHA-256, 64 hex digits, of the pull request's conversation as land.yml's
# decide and apply read it. Exit 1: a file is missing or not of its route's shape. Exit 2: usage.
set -u -o pipefail
die() { printf 'land-digest: %s\n' "$1" >&2; exit 2; }
[ $# = 3 ] || die "usage: land-digest.sh <comments.json> <review-comments.json> <reviews.json>"
for tool in jq sha256sum; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
# shellcheck disable=SC2016
doc=$(jq -ncS --slurpfile c "$1" --slurpfile rc "$2" --slurpfile rv "$3" '
  def one: if length == 1 then .[0] else error("not one read") end;
  def items: if type == "array" and length > 0 and all(.[]; type == "array") then [.[][]]
    else error("not the pages of a list") end;
  def t: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
    then . else error("not a time") end;
  def n: if type == "number" and . >= 1 and floor == . then . else error("not an id") end;
  def who: [(.user.login | if type == "string" then . else error("no login") end),
    (.performed_via_github_app.slug // null)];
  {issue: [$c | one | items[] | [(.id | n)] + who +
     [(.created_at | t), (.updated_at | t), (.body // "")]] | unique,
   reviewComment: [$rc | one | items[] | [(.id | n), (.pull_request_review_id | n)] + who +
     [(.created_at | t), (.updated_at | t), (.body // "")]] | unique,
   review: [$rv | one | items[] | [(.id | n)] + who +
     [.state, (.commit_id // ""), (.submitted_at // ""), (.body // "")]] | unique}' 2>/dev/null) \
  || { printf 'land-digest: a read is not of its route'"'"'s shape\n' >&2; exit 1; }
printf '%s' "$doc" | sha256sum | cut -c1-64
```

The document is captured before it is hashed: piped straight into `sha256sum`, a failed read
printed the hash of nothing.

`land-decide.sh`: the header's exit 1 also covers "or the handoff could not be written"; the tool
list gains `sha256sum`; `digester=${LAND_DIGEST_SCRIPT:-.github/scripts/land-digest.sh}`. After
`cat "$out/decision.json" "$out/snapshot.err"`, and only on the decided path (a skipped or refused
run writes no output, so nothing acts):

```bash
handoff() {
  local merge pr='' head='' approval='' digest='' answers
  "$gate" land-answers "$out/snapshot.json" >"$out/answers.json" 2>"$out/answers.err" || return 1
  jq -e 'type == "object" and has("merge") and has("answers")' "$out/answers.json" >/dev/null || return 1
  answers=$(jq -ce '.answers | arrays' "$out/answers.json") && [ "${#answers}" -le 65536 ] || return 1
  merge=$(jq -c '.merge' "$out/answers.json") || return 1   # null when nothing merges: no -e
  # land's plan and land-answers' handoff name the same merge, or neither names one
  jq -e --argjson m "$merge" 'if .plan.kind == "merge"
    then $m != null and $m.pr == .plan.pr and $m.head == .plan.head else $m == null end' \
    "$out/decision.json" >/dev/null || return 1
  if [ "$merge" != null ]; then
    pr=$(jq -r .pr <<<"$merge") head=$(jq -r .head <<<"$merge") approval=$(jq -r .approval <<<"$merge")
    [[ $pr =~ ^[1-9][0-9]{0,6}$ && $head =~ ^[0-9a-f]{40}$ && $approval =~ ^[1-9][0-9]{0,19}$ ]] || return 1
    digest=$("$digester" "$out/reads/comments-$pr.json" "$out/reads/review-comments-$pr.json" \
      "$out/reads/reviews-$pr.json") || return 1
  fi
  [ -z "${GITHUB_OUTPUT:-}" ] || printf 'pr=%s\nhead=%s\napproval=%s\ndigest=%s\nanswers=%s\n' \
    "$pr" "$head" "$approval" "$digest" "$answers" >>"$GITHUB_OUTPUT"
}
handoff || { cat "$out/answers.err" >&2; printf 'land-decide: the handoff was not written\n' >&2; exit 1; }
```

`land-decide.sh` still makes exactly two `gh` calls; the digest reads only the saved reads. The
function ran on fake reads: idle gives empty outputs and `answers=[]`; a merge gives `pr`, `head`,
`approval` and the digest `apply` computes from the same reads; a disagreement with `land`, or a
missing key, exits 1 with no output.

`.github/scripts/land-apply.sh` (new; shellcheck-clean; every case marked smoke-checked above ran
against a stub `gh`):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2016
# Usage: .github/scripts/land-apply.sh <owner/name> <dir>
# land.yml's apply: on decide's planned merge, reads the pull request and its conversation again
# with GH_TOKEN, then makes the one pinned rebase-merge with LAND_MERGE_TOKEN (amendment #178,
# section 4). Env: LAND_MERGE, GITHUB_RUN_ATTEMPT, GITHUB_REPOSITORY_OWNER,
# GITHUB_REPOSITORY_OWNER_ID, GH_TOKEN, LAND_MERGE_TOKEN, LAND_PR, LAND_HEAD, LAND_APPROVAL,
# LAND_DIGEST. Writes <dir>/outcome.json, one line, and `outcome=<that line>` to $GITHUB_OUTPUT:
#   {"kind":"stopped","why":"off|attempt|input|read|pr|digest|approval"}
#   {"kind":"refused","status":"405|409"}   {"kind":"merged","main":"<40 hex>"}
#   {"kind":"failed","status":"<3 digits>|none"}
# Exit 0: an outcome was written. Exit 1: none could be. Exit 2: usage.
set -u
die() { printf 'land-apply: %s\n' "$1" >&2; exit 2; }
[ $# = 2 ] || die "usage: land-apply.sh <owner/name> <dir>"
repo=$1 out=$2
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
for tool in gh jq timeout sha256sum sed; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done
digester=${LAND_DIGEST_SCRIPT:-$(dirname "$0")/land-digest.sh}
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"

outcome() {
  local line
  line=$(jq -cn "$@") || exit 1
  printf '%s\n' "$line" >"$out/outcome.json" || exit 1
  [ -z "${GITHUB_OUTPUT:-}" ] || printf 'outcome=%s\n' "$line" >>"$GITHUB_OUTPUT" || exit 1
  printf 'land-apply: %s\n' "$line"
  exit 0
}
stop() { outcome --arg why "$1" '{kind: "stopped", why: $why}'; }
read_to() { timeout -k 5 120 gh api "$2" >"$out/$1.json" 2>"$out/$1.err" </dev/null; }
pages_to() { timeout -k 5 120 gh api --paginate --slurp "$2" >"$out/$1.json" 2>"$out/$1.err" </dev/null; }

# 1. The switch and the attempt, before any call.
[ "${LAND_MERGE:-}" = on ] || stop off
[ "${GITHUB_RUN_ATTEMPT:-}" = 1 ] || stop attempt
# 2. The handoff, each value of its exact shape.
pr=${LAND_PR:-} head=${LAND_HEAD:-} approval=${LAND_APPROVAL:-} digest=${LAND_DIGEST:-}
owner=${GITHUB_REPOSITORY_OWNER:-} owner_id=${GITHUB_REPOSITORY_OWNER_ID:-}
[[ $pr =~ ^[1-9][0-9]{0,6}$ && $head =~ ^[0-9a-f]{40}$ && $approval =~ ^[1-9][0-9]{0,19}$ &&
  $digest =~ ^[0-9a-f]{64}$ && $owner =~ ^[A-Za-z0-9-]{1,39}$ && $owner_id =~ ^[1-9][0-9]{0,19}$ &&
  $repo == "$owner"/* && -n ${GH_TOKEN:-} && -n ${LAND_MERGE_TOKEN:-} ]] || stop input
# 3. The pull request: open, not a draft, on main of this repository, at the planned head.
read_to pr "repos/$repo/pulls/$pr" || stop read
jq -e --arg h "$head" --arg r "$repo" --argjson n "$pr" '.number == $n and .state == "open"
  and .draft == false and .merged == false and .head.sha == $h and .base.ref == "main"
  and .base.repo.full_name == $r and .head.repo.full_name == $r' "$out/pr.json" >/dev/null 2>&1 \
  || stop pr
# 4. Its conversation: the digest decide took, then the approval comment.
pages_to comments "repos/$repo/issues/$pr/comments?per_page=100" || stop read
pages_to review-comments "repos/$repo/pulls/$pr/comments?per_page=100" || stop read
pages_to reviews "repos/$repo/pulls/$pr/reviews?per_page=100" || stop read
now=$("$digester" "$out/comments.json" "$out/review-comments.json" "$out/reviews.json") || stop read
[ "$now" = "$digest" ] || stop digest
jq -e --argjson id "$approval" --arg o "$owner" --argjson oid "$owner_id" \
  '[.[][] | select(.id == $id)] | length == 1 and (.[0] | .user.login == $o and .user.id == $oid
    and .user.type == "User" and .performed_via_github_app == null and .created_at == .updated_at)' \
  "$out/comments.json" >/dev/null 2>&1 || stop approval
# 5. The one call: no retry, no merge-async, no bypass.
GH_TOKEN=$LAND_MERGE_TOKEN timeout -k 5 120 gh api -X PUT "repos/$repo/pulls/$pr/merge" \
  -f merge_method=rebase -f "sha=$head" >"$out/merge.json" 2>"$out/merge.err" </dev/null
code=$?
if [ "$code" = 0 ]; then
  main=$(jq -er 'select(.merged == true) | .sha' "$out/merge.json" 2>/dev/null) \
    && [[ $main =~ ^[0-9a-f]{40}$ ]] && outcome --arg m "$main" '{kind: "merged", main: $m}'
  outcome '{kind: "failed", status: "200"}'
fi
status=$(sed -n 's/.*(HTTP \([0-9][0-9][0-9]\))$/\1/p' "$out/merge.err" | tail -n 1)
case $status in
  405 | 409) outcome --arg s "$status" '{kind: "refused", status: $s}' ;;
  [0-9][0-9][0-9]) outcome --arg s "$status" '{kind: "failed", status: $s}' ;;
esac
# No status: the answer was lost. One read of the pull request, never a second call.
if read_to after "repos/$repo/pulls/$pr" &&
  main=$(jq -er --arg h "$head" 'select(.merged == true and .head.sha == $h) | .merge_commit_sha' \
    "$out/after.json" 2>/dev/null) && [[ $main =~ ^[0-9a-f]{40}$ ]]; then
  outcome --arg m "$main" '{kind: "merged", main: $m}'
fi
outcome '{kind: "failed", status: "none"}'
```

`.github/scripts/land-report.sh` (new; shellcheck-clean; smoke-checked as marked):

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2016
# Usage: .github/scripts/land-report.sh <owner/name>
# land.yml's report: posts at most one comment per pull request, an answer that differs from the
# newest <!-- land-report --> comment github-actions posted there (amendment #178, section 4). Env: GH_TOKEN, GITHUB_SERVER_URL, GITHUB_RUN_ID, LAND_ANSWERS (decide's list of
# {pr, line, body}), LAND_PR and LAND_HEAD (decide's planned merge, empty if none),
# LAND_APPLY_RESULT and LAND_APPLIED (apply's job result and outcome).
# Exit 0: every answer was read and posted as needed. Exit 1: a read or a post failed, or the merge
# call failed. Exit 2: usage or malformed input, and nothing was called.
set -u
marker='<!-- land-report -->'
die() { printf 'land-report: %s\n' "$1" >&2; exit 2; }
[ $# = 1 ] || die "usage: land-report.sh <owner/name>"
repo=$1
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && $repo != */. && $repo != */.. ]] \
  || die "<owner/name> is not a repository name"
for tool in gh jq timeout mktemp; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
[[ ${GITHUB_RUN_ID:-} =~ ^[1-9][0-9]{0,19}$ ]] || die "GITHUB_RUN_ID is not a run id"
run_link="${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/$GITHUB_RUN_ID"
pr=${LAND_PR:-} head=${LAND_HEAD:-}
[ -z "$pr" ] || [[ $pr =~ ^[1-9][0-9]{0,6}$ && $head =~ ^[0-9a-f]{40}$ ]] \
  || die "the planned merge is not of its shape"
answers=$(jq -ce --arg m "$marker" --arg p "$pr" 'if type == "array" and length <= 100 and all(.[];
    type == "object" and keys == ["body", "line", "pr"] and (.pr | type == "number" and . >= 1
    and floor == .) and (.pr | tostring) != $p and (.line | type == "string" and length > 0
    and (contains("\n") | not)) and (.body | type == "string" and (contains("@") | not))
    and (.line as $l | .body == $m + "\n" + $l or (.body | startswith($m + "\n" + $l + "\n"))))
    and ([.[].pr] | length == (unique | length)) then sort_by(.pr) else error("bad") end' \
  <<<"${LAND_ANSWERS:-[]}" 2>/dev/null) || die "the answers are not of their shape"

# The planned pull request is answered from apply's result, which only this job sees.
planned='' failed=0
if [ -n "$pr" ]; then
  kind=$(jq -r '.kind // ""' <<<"${LAND_APPLIED:-null}" 2>/dev/null) || kind=
  again="Comment /land $head again to go on."
  case ${LAND_APPLY_RESULT:-}/$kind in
    success/merged)
      main=$(jq -r '.main' <<<"$LAND_APPLIED")
      [[ $main =~ ^[0-9a-f]{40}$ ]] && planned="Landed $head on your /land. main is $main." ;;
    success/failed)
      status=$(jq -r '.status' <<<"$LAND_APPLIED")
      [[ $status =~ ^([0-9]{3}|none)$ ]] || status=none
      planned="Merge call failed: $status."$'\n\n'"$run_link" failed=1 ;;
    success/stopped)
      case $(jq -r '.why' <<<"$LAND_APPLIED") in
        digest) planned="Not merged yet at $head: the conversation changed after the decision. $again" ;;
        approval) planned="Not merged yet at $head: the approval is not your unedited comment. $again" ;;
        read) planned="Not merged yet at $head: a read failed. $again"$'\n\n'"$run_link" ;;
        off) planned="Not merged: the merge switch is off." ;;
      esac ;;
    failure/*) planned="Merge call failed: no outcome."$'\n\n'"$run_link" failed=1 ;;
  esac
fi

tmp=$(mktemp -d) || die "cannot make a scratch folder"
trap 'rm -rf -- "$tmp"' EXIT
# post_due <pr> <body>: one read of the comments, then a post unless the newest report is this body.
post_due() {
  timeout -k 5 120 gh api --paginate --slurp "repos/$repo/issues/$1/comments?per_page=100" \
    >"$tmp/c.json" 2>/dev/null </dev/null || return 1
  jq -e 'type == "array" and all(.[]; type == "array")' "$tmp/c.json" >/dev/null 2>&1 || return 1
  jq -e --arg m "$marker" --arg b "$2" '[.[][] | select(.user.login == "github-actions[bot]"
      and .user.type == "Bot" and .performed_via_github_app.slug == "github-actions"
      and (.body | type == "string" and startswith($m + "\n")))] | max_by(.id) | .body == $b' \
    "$tmp/c.json" >/dev/null 2>&1 && return 0
  timeout -k 5 120 gh api -X POST "repos/$repo/issues/$1/comments" -f "body=$2" \
    >/dev/null 2>&1 </dev/null
}
problems=0
while IFS= read -r item; do
  n=$(jq -r .pr <<<"$item") body=$(jq -r .body <<<"$item")
  post_due "$n" "$body" || { printf 'land-report: #%s was not answered\n' "$n" >&2; problems=1; }
done < <(jq -c '.[]' <<<"$answers")
if [ -n "$planned" ]; then
  post_due "$pr" "$marker"$'\n'"$planned" \
    || { printf 'land-report: #%s was not answered\n' "$pr" >&2; problems=1; }
fi
[ "$problems" = 0 ] && [ "$failed" = 0 ]
```

`.github/scripts/land-workflow.lib.sh`: `job_block <workflow> <job>` prints the lines from
`  <job>:` to the next two-space key, so `land-decide.test.sh`, `land-apply.test.sh` and
`land-report.test.sh` pin each job's own block. It is sourced, never run.

`.github/scripts/app-token.test.sh` scans `.github/workflows/*.yml`: each
`uses: actions/create-github-app-token@` is a 40-hex pin with a `# v` comment; its `with:` names at
least one `permission-` input, each from the app's list; its job says `environment: trusted`; and
`update-prs.yml`'s set is exactly contents, pull-requests and workflows, all `write`.
`land-protection.test.sh` and `land-apply.test.sh` keep their own exact pins of their mints.

### Lean

`gate/MitosGate/LandAnswer.lean` (new). This builds as written on the three standard axioms; the
file ends with the axiom check copied from `Land.lean`, naming the three statements and every
fixture.

```lean
import MitosGate.Land
import MitosGate.Shadow.Lacks
import MitosGate.Shadow.Reading

/-!
# What the land workflow answers to an owner word

`land.yml`'s `report` job posts one comment per change of answer (amendment #178, section 4).
Every answer known before `apply` runs is decided and rendered here, from the queue `plan` reads,
as the workflow sees it: a teammate that is no delegate (`Shadow.outsider`). The pull request the
plan merges is `apply`'s to answer, from the merge call's result.
-/

namespace MitosGate.LandAnswer

open Land
open Shadow (Clause lacks outsider)

inductive Waiting
  | behind (pr : Pr)
  | replay
  | gate
  deriving DecidableEq

inductive Answer
  | unnamed (head : Sha)
  | queued (head : Sha) (why : Waiting)
  | held (head : Sha)
  | spoke (head : Sha)
  | stale (head about : Sha)
  | notEligible (lacks : List Clause)
  | stuck (why : Stuck)
  deriving DecidableEq

inductive Reply
  | answer (a : Answer)
  /-- The plan merges this pull request at `head`: `apply` makes the call, and `report` answers
  from its result. -/
  | landing (head : Sha)
  deriving DecidableEq

def aboutOf (o : Obs) : Sha :=
  match newestOwner o.words with
  | some (.ownerLand m) => m.about
  | _ => o.head

def reply (q : Queue) (o : Obs) : Option Reply :=
  match o.word with
  | .none => none
  | .held => some (.answer (.held o.head))
  | .unnamed => some (.answer (.unnamed o.head))
  | .spoke => some (.answer (.spoke o.head))
  | .stale => some (.answer (.stale o.head (aboutOf o)))
  | .stands =>
    if plan q = .merge o.pr o.head then some (.landing o.head)
    else
      match step (outsider o).1 q o with
      | .stop (.stuck why) => some (.answer (.stuck why))
      | .stop _ => some (.answer (.notEligible (lacks o)))
      | .wait n => some (.answer (.queued o.head (.behind n)))
      | .awaitPush _ => some (.answer (.queued o.head .replay))
      | _ => some (.answer (.queued o.head .gate))

/-- One entry per pull request whose reply is an answer, in the snapshot's order. -/
def answers (os : List Obs) : List (Pr × Answer) :=
  os.filterMap fun o =>
    match reply (queueOf os) o with
    | some (.answer a) => some (o.pr, a)
    | _ => none

/-- What `apply` acts on: the pull request and head the plan merges, and the comment whose `/land`
is the entry next. A reader places a comment's word at twice its id. -/
structure Handoff where
  pr : Pr
  head : Sha
  approval : Nat
  deriving DecidableEq

def handoff (q : Queue) : Option Handoff :=
  match plan q, next q with
  | .merge p h, some (e, _) => if e.mark.said % 2 = 0 then some ⟨p, h, e.mark.said / 2⟩ else none
  | _, _ => none

def marker : String := "<!-- land-report -->"

def clauseOrder : List Clause := [.covered, .reviewed, .rest, .updatable, .enforced]

def clauseText : Clause → String
  | .covered => "no covering verdict"
  | .reviewed => "no bot review"
  | .rest => "an unanswered comment or a missing spec-approved"
  | .updatable => "a draft or a stack"
  | .enforced => "protection"

def stuckText : Stuck → String
  | .red => "red gate"
  | .conflict => "conflict"
  | .contentChanged => "a replay that changes content"
  | .historyError => "a history error"
  | .unread => "a failed read"

def waitingText : Waiting → String
  | .behind n => s!"#{n} to land first"
  | .replay => "the replay"
  | .gate => "gate"

def Answer.lines : Answer → List String
  | .unnamed h =>
    ["This PR touches a path you keep. To approve and merge it, comment only this line:", "",
     "```", s!"/land {h}", "```"]
  | .queued h why => [s!"Queued at {h}: waiting for {waitingText why}."]
  | .held h => [s!"Held by your /hold, an edited comment or a failed read. Comment /land {h} to go on."]
  | .spoke h => [s!"Your later comment paused it. Comment /land {h} again to go on."]
  | .stale h a => [s!"{h} is new content since {a}. After its verdict, comment /land {h}."]
  | .notEligible ls =>
    [s!"Stopped: {", ".intercalate ((clauseOrder.filter ls.contains).map clauseText)}."]
  | .stuck why => [s!"Stopped: {stuckText why}."]

def Answer.line (a : Answer) : String := a.lines.headD ""

def Answer.body (a : Answer) : String := "\n".intercalate (marker :: a.lines)

def AnswersOnlyOwnerWords : Prop :=
  ∀ q o, (reply q o).isSome = true ↔ o.word ≠ .none

def LandingIsThePlannedMerge : Prop :=
  ∀ q o h, reply q o = some (.landing h) ↔
    o.word = .stands ∧ plan q = .merge o.pr o.head ∧ h = o.head

def HandoffIsThePlannedMerge : Prop :=
  ∀ q x, handoff q = some x →
    plan q = .merge x.pr x.head ∧ ∃ e o, next q = some (e, o) ∧ o.pr = x.pr ∧ o.head = x.head ∧
      e.lander = .owner ∧ e.mark.said = 2 * x.approval ∧ newestOwner o.words = some (.ownerLand e.mark)

theorem answersOnlyOwnerWords : AnswersOnlyOwnerWords := by
  intro q o
  unfold reply
  cases o.word with
  | none => simp
  | held => simp
  | unnamed => simp
  | spoke => simp
  | stale => simp
  | stands =>
    simp only [ne_eq, reduceCtorEq, not_false_eq_true, iff_true]
    split
    · rfl
    · split <;> rfl

theorem landingIsThePlannedMerge : LandingIsThePlannedMerge := by
  intro q o h
  unfold reply
  constructor
  · intro hr
    cases hw : o.word with
    | none => simp [hw] at hr
    | held => simp [hw] at hr
    | unnamed => simp [hw] at hr
    | spoke => simp [hw] at hr
    | stale => simp [hw] at hr
    | stands =>
      rw [hw] at hr
      simp only at hr
      split at hr
      · next hp =>
        simp only [Option.some.injEq, Reply.landing.injEq] at hr
        exact ⟨rfl, hp, hr.symm⟩
      · split at hr <;> simp at hr
  · rintro ⟨hw, hp, rfl⟩
    simp [hw, hp]

theorem handoffIsThePlannedMerge : HandoffIsThePlannedMerge := by
  intro q x hx
  unfold handoff at hx
  split at hx
  · next p h e o' hp hn =>
    split at hx
    · next hev =>
      cases hx
      obtain ⟨e', o, hn', hpr, hh, -, -, -, -, -, -, -, hl, hw, -⟩ := plannedMergeIsGated q p h hp
      rw [hn] at hn'
      cases hn'
      exact ⟨hp, e, o', hn, hpr, hh.symm, hl, by show e.mark.said = 2 * (e.mark.said / 2); omega, hw⟩
    · cases hx
  · cases hx

namespace Fixture

open Land.Fixture

def bareOnKept : Obs := { ownerKeptBehind with words := [.ownerLand ⟨900, "aaa", false⟩] }
def second : Obs := { ownerKeptPushed with pr := 154, words := [.ownerLand ⟨950, "ar", true⟩] }

def lineOf (q : Queue) (o : Obs) : Option String :=
  (reply q o).map fun
    | .answer a => a.line
    | .landing _ => ""

theorem aBareLandOnAKeptPathAsksForTheLine :
    reply (queueOf [bareOnKept]) bareOnKept = some (.answer (.unnamed "aaa")) ∧
      (Answer.unnamed "aaa").body =
        "<!-- land-report -->\nThis PR touches a path you keep. To approve and merge it, comment only this line:\n\n```\n/land aaa\n```" := by
  decide +kernel
theorem theApprovedGreenHeadIsLeftToApply :
    reply (queueOf [ownerKeptPushed]) ownerKeptPushed = some (.landing "ar") ∧
      handoff (queueOf [ownerKeptPushed]) = some ⟨153, "ar", 450⟩ ∧
      answers [ownerKeptPushed] = [] := by decide +kernel
theorem anotherLandingGoesFirst :
    lineOf (queueOf [ownerKeptPushed, second]) second =
      some "Queued at ar: waiting for #153 to land first." := by decide +kernel
theorem aBehindHeadWaitsForTheReplay :
    lineOf (queueOf [ownerKeptBehind]) ownerKeptBehind =
      some "Queued at aaa: waiting for the replay." := by decide +kernel
theorem aPushedHeadWaitsForGate :
    lineOf (queueOf [ownerKeptJustPushed]) ownerKeptJustPushed =
      some "Queued at ar: waiting for gate." := by decide +kernel
theorem aHoldIsHeld :
    lineOf (queueOf [ownerKeptHeld]) ownerKeptHeld =
      some "Held by your /hold, an edited comment or a failed read. Comment /land aaa to go on." := by
  decide +kernel
theorem aLaterCommentPausesIt :
    lineOf (queueOf [{ ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerSpoke 950] }])
      { ownerKeptPushed with words := [.ownerLand ownerKeptMark, .ownerSpoke 950] } =
      some "Your later comment paused it. Comment /land ar again to go on." := by decide +kernel
theorem newContentNamesBothCommits :
    lineOf (queueOf [ownerKeptNewContent]) ownerKeptNewContent =
      some "fff is new content since aaa. After its verdict, comment /land fff." := by decide +kernel
theorem eachMissingClauseIsNamedInOrder :
    lineOf (queueOf [{ ownerKeptPushed with botAt := none, verdicts := [] }])
      { ownerKeptPushed with botAt := none, verdicts := [] } =
      some "Stopped: no covering verdict, no bot review." := by decide +kernel
theorem unenforcedIsProtection :
    lineOf (queueOf [{ ownerKeptPushed with enforced := false }])
      { ownerKeptPushed with enforced := false } = some "Stopped: protection." := by decide +kernel
theorem aRedGateIsStuck :
    lineOf (queueOf [{ ownerKeptPushed with gate := .failure }])
      { ownerKeptPushed with gate := .failure } = some "Stopped: red gate." := by decide +kernel
theorem noOwnerWordNoReply :
    reply (queueOf [ownerKeptPushed, agentBehind]) agentBehind = none := by decide +kernel
theorem anOddPositionHandsNothing :
    handoff (queueOf [{ ownerKeptPushed with words := [.ownerLand ⟨901, "aaa", true⟩] }]) = none := by
  decide +kernel

end Fixture

-- the axiom check of `Land.lean`, over the three statements and `MitosGate.LandAnswer.Fixture`

end MitosGate.LandAnswer
```

`LandCli.lean` imports `MitosGate.LandAnswer` and adds (checked: on `[ownerKeptPushed, the same at
#154 with its own approval, agentBehind]` `(answersJson s).compress` printed
`{"answers":[{"body":"<!-- land-report -->\nQueued at ar: waiting for #153 to land first.","line":"Queued at ar: waiting for #153 to land first.","pr":154}],"merge":{"approval":450,"head":"ar","pr":153}}`):

```lean
/-- `mitos-gate land-answers [<snapshot.json>]`: what land.yml's apply and report act on, as one
line: `merge` is `LandAnswer.handoff` and `answers` holds one entry per pull request whose reply is
an `Answer`. It refuses what `land` refuses (`read`); `me`, `pr` and `event` change nothing. -/
def answersJson (s : Snapshot) : Json :=
  Json.mkObj
    [("merge", (LandAnswer.handoff (queueOf s.prs)).elim Json.null fun x =>
        Json.mkObj [("pr", n x.pr), ("head", .str x.head), ("approval", n x.approval)]),
     ("answers", Json.arr ((LandAnswer.answers s.prs).map fun (p, a) =>
        Json.mkObj [("pr", n p), ("line", .str a.line), ("body", .str a.body)]).toArray)]

-- answersCli (args : List String) (usage : String) : IO UInt32 is `cli` with `answersJson`, except
-- that it prints `(answersJson s).compress` with plain `IO.println`, not through `ciLine`;
-- a refusal prints `ciLine s!"land-answers: the snapshot is refused: {e}"` on standard error.
-- The helpers stay private.
```

`answersCli` does not print through `ciLine`, unlike `cli`: its standard output goes to
`$out/answers.json` and never to the log, and `ciLine` escapes every backslash as `\u{005C}`
(`Util.lean`'s `printable` leaves out U+005C), so each body's `\n` would print as `\u{005C}n`,
which is not JSON, and `handoff`'s `jq -e` would stop `decide` on every run with an answer.
`ciLine` stays for standard error only. Checked at round 2 against `main` at a32a9fc with this
file's `LandAnswer.lean` and `answersJson` and that `answersCli`: on `gate/land-fixtures/queue.json`
with #153's word made a bare `/land` (`.prs[0].words[0].approves = false`) it exits 0, `jq -e .`
on its output exits 0, and `.answers[0].body` starts with `<!-- land-report -->` and a real newline;
the round-1 form, `cli`'s `IO.println (ciLine j.compress)`, printed `\u{005C}n` there and `jq -e .`
exited 5.

`gate/Main.lean`: `| "land-answers" :: rest => LandCli.answersCli rest usage`, and the usage entry
`mitos-gate land-answers [<snapshot.json>]  what land.yml's apply and report act on: the planned
merge's pull request, head and approving comment, and one answer per owner word; one line of JSON`.

`Land.lean` (#303 items 6 and 7), comments only:

```lean
  /-- Rebase-merge `pr` pinned to `head` (`PUT …/pulls/<pr>/merge` with `sha=<head>`): `land.yml`'s
  `apply` job makes this one call with the updater app's token, after it reads the pull request and
  its conversation again. -/
  | merge (pr : Pr) (head : Sha)
```

and in `wake`: `-- on the owner's word alone land.yml's apply merges a green gate, so it wakes
nobody; any other result needs a re-run that no timer would start`.

Snapshot (#319 items 1, 2 and 12). This builds as written (`Snapshot.Obs` and its imports; the
fixtures file is the builder's):

```lean
-- Types.lean: Post gains
  /-- The review a review comment belongs to (`pull_request_review_id`); none for an issue comment
  and for a review's own summary. -/
  review : Option Nat

-- Fields.lean: `posts` passes `none`; then
/-- A review comment speaks no earlier than its review was submitted: a draft's comments keep the
time they were drafted. `none` when a comment names a review the reviews route did not list. -/
def submittedPosts (vs : List Review) (ps : List Post) : Option (List Post) :=
  ps.mapM fun p =>
    match p.review with
    | none => some p
    | some id => (vs.find? (·.id == id)).map fun v => { p with updated := max p.updated v.submitted }

def ReviewCommentsSpeakWhenSubmitted : Prop :=
  ∀ vs ps ps', submittedPosts vs ps = some ps' → ∀ p ∈ ps', ∀ id, p.review = some id →
    ∃ v ∈ vs, v.id = id ∧ v.submitted ≤ p.lastSpoke

theorem mapM_mem {f : α → Option β} : ∀ {l : List α} {l' : List β}, l.mapM f = some l' →
    ∀ y ∈ l', ∃ x ∈ l, f x = some y
  | [], l', h, y, hy => by simp at h; subst h; cases hy
  | a :: as, l', h, y, hy => by
    rw [List.mapM_cons] at h
    cases ha : f a with
    | none => simp [ha] at h
    | some b =>
      cases hr : as.mapM f with
      | none => simp [ha, hr] at h
      | some bs =>
        simp [ha, hr] at h
        subst h
        rcases List.mem_cons.1 hy with rfl | hy
        · exact ⟨a, List.mem_cons_self .., ha⟩
        · obtain ⟨x, hx, hfx⟩ := mapM_mem hr y hy
          exact ⟨x, List.mem_cons_of_mem _ hx, hfx⟩

theorem reviewCommentsSpeakWhenSubmitted : ReviewCommentsSpeakWhenSubmitted := by
  intro vs ps ps' h p hp id hid
  obtain ⟨a, -, ha⟩ := mapM_mem h p hp
  cases har : a.review with
  | none => simp [har] at ha; subst ha; simp [har] at hid
  | some j =>
    simp only [har] at ha
    cases hf : vs.find? (·.id == j) with
    | none => simp [hf] at ha
    | some v =>
      simp only [hf, Option.map_some, Option.some.injEq] at ha
      subst ha
      have hj : j = id := by simpa [har] using hid
      subst hj
      refine ⟨v, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf, ?_⟩
      exact Nat.le_trans (Nat.le_max_right a.updated v.submitted) (Nat.le_max_right _ _)

-- Obs.lean: `reviewPosts` passes `none`; then
/-- An owner review with text in its summary. -/
def summarySpeaks (g : Global) (vs : List Review) : Bool :=
  vs.any fun v => !v.body.isEmpty && speaks g ⟨v.login, none, v.submitted, v.submitted, v.body, none⟩

/-- An owner review that neither counts nor has a review comment of its own. GitHub posts no such
review: a comment review needs a summary or a comment, and each thread reply has its own. So its
summary was emptied, or its comments deleted, after it was submitted, at a time no route gives. -/
def emptied (g : Global) (r : Reads) (v : Review) : Bool :=
  v.login == g.owner && !counts v && !(r.reviewComments.getD []).any (·.review == some v.id)

/-- The reviews route has no update time, so a summary edited after the approval reads as typed
before it. So any owner summary with text, and any owner review emptied of its text or its
comments, retires the approval, whatever its time. -/
def spokeInReview (g : Global) (r : Reads) (ws : List Word) : Bool :=
  match Land.newestOwner ws with
  | some (.ownerLand m) =>
    summarySpeaks g (r.reviews.getD []) || (r.reviews.getD []).any (emptied g r) ||
    (r.comments.getD []).any fun c => 2 * c.id == m.said &&
      (reviewPosts r).any fun s => speaks g s && decide (c.created ≤ s.lastSpoke)
  | _ => false

-- KeptMergeIsTheOwnersTypedApproval: its last line becomes
      (∀ s ∈ reviewPosts r, speaks g s = true → s.lastSpoke < c.created) ∧
      summarySpeaks g (r.reviews.getD []) = false ∧ ∀ v ∈ r.reviews.getD [], emptied g r v = false
```

The proof of `keptMergeIsTheOwnersTypedApproval` keeps P1-019's up to `hno`, then splits it three
ways and closes the new clauses (checked):

```lean
  simp only [spokeInReview, hw', Bool.or_eq_false_iff] at hno
  obtain ⟨⟨hsum, hem⟩, hcs⟩ := hno
  have h3 := List.any_eq_false.1 hcs c hc
  simp only [Bool.and_eq_true, beq_iff_eq, not_and] at h3
  have h4 := h3 hsaid.symm
  refine ⟨c, hc, ho, hsl, hu, hf, hon, ⟨arg, e.mark.about, harg, hl, hres, hcar⟩,
    fun d hd ht => ?_, fun s hsm hsp => ?_, hsum, fun v hv => ?_⟩
  · -- the typed-comment case: unchanged from P1-019
  · have h4' : ∀ y ∈ reviewPosts r, speaks g y = true → y.lastSpoke < c.created := by
      simpa using h4
    exact h4' s hsm hsp
  · simpa using List.any_eq_false.1 hem v hv
```

`SnapshotCli.lean`: `reviewCommentsOf` reads `some (← nat "pull_request_review_id" c)` (a missing or
null id fails the read), and `run` builds
`reviewComments := do submittedPosts (← reviewsOf <reviews-k>) (← reviewCommentsOf <review-comments-k>)`.
A comment of a pending review, which only its author's token sees, then fails the read and holds:
the workflow token sees neither.

Shadow (#319 item 3). This builds as written (`Shadow.Finding` and its imports):

```lean
-- Shadow/Types.lean
/-- Whether observed owner review evidence speaks at merge time (`Snapshot.reviewsSpeak`).
Speaking evidence prevents a noEntry assumption; other recorded steps remain as read. -/
inductive Summary
  | silent
  | spoke
  deriving DecidableEq
-- Merge gains `summary : Summary`

-- Shadow/Reading.lean (imports MitosGate.Shadow.Types)
def reading (s : Summary) (os : List Obs) (o : Obs) : Reading :=
  match step (outsider o).1 (queueOf os) o with
  | .stop .noEntry =>
    match s with
    | .spoke => .asRead (.stop .noEntry)
    | .silent =>
      let o' := withWord (fresh os) o
      .oneWordAway
        (step (outsider o').1 (queueOf (os.map fun x => if x.pr == o.pr then o' else x)) o')
  | x => .asRead x

theorem theWordIsOnlyAssumedWhenReady : TheWordIsOnlyAssumedWhenReady := by
  intro s os o
  unfold reading
  split
  · rename_i h
    cases s <;> simp [h]
  · rename_i h
    constructor
    · rintro ⟨x, hx⟩; cases hx
    · rintro ⟨-, h'⟩; exact absurd h' h

-- Shadow/Seat.lean: `reading := reading m.summary r.prs o`; the fixture `merged` has `.silent`

-- Shadow/Finding.lean
def ASummaryOnlyTakesAgreementAway : Prop :=
  ∀ (m : Merge) (rs : List Record), finding (seat { m with summary := .spoke } rs) = .agrees →
    finding (seat { m with summary := .silent } rs) = .agrees

theorem last_congr {m m' : Merge} (hb : m.before = m'.before) (ht : m.time = m'.time) :
    ∀ rs : List Record, last m rs = last m' rs
  | [] => rfl
  | r :: rs => by
    have hp : precedes m r = precedes m' r := by simp [precedes, hb, ht]
    simp only [last, last_congr hb ht rs, hp]

theorem reading_spoke (os : List Obs) (o : Obs) :
    reading .spoke os o = .asRead (.stop .noEntry) ∨ reading .spoke os o = reading .silent os o := by
  unfold reading
  split
  · exact .inl rfl
  · exact .inr rfl

theorem aSummaryOnlyTakesAgreementAway : ASummaryOnlyTakesAgreementAway := by
  intro m rs h
  have hl : last { m with summary := .spoke } rs = last { m with summary := .silent } rs :=
    last_congr (m := { m with summary := .spoke }) (m' := { m with summary := .silent }) rfl rfl rs
  unfold seat at h ⊢
  rw [hl] at h
  cases hr : last { m with summary := .silent } rs with
  | none => simp [hr, finding] at h
  | some r =>
    simp only [hr] at h ⊢
    cases ho : r.prs.find? (·.pr == m.pr) with
    | none => simp [ho, finding] at h
    | some o =>
      simp only [ho] at h ⊢
      rcases reading_spoke r.prs o with he | he
      · simp only [he, finding, Reading.step] at h
        split at h <;> simp_all
      · simp only [he] at h
        exact h
```

`ShadowCli/Read.lean`: `merges` takes the validated owner from `<dir>/repo.json`. Each merge's
required `reviews` and `reviewComments` use both SnapshotCli decoders before inclusive submission
and creation-time filtering, then give `.spoke` through shared `Snapshot.reviewsSpeak`.
`gate/shadow-fetch.sh` binds repository metadata to its requested repository and, per merged
pull request, collects every page of both review routes without a date stop. Each page must be
exactly one JSON array before flattening; any failure calls `failed`.
A failed fetch can leave partial files; retry in a new empty directory.

### Decisions on what the amendment did not check

- **The workflow, `apply` and `report`:** the sketches, their unit tests, and R1 to R16.
- **A merge by the app, with or without a workflow file, and Workflows write.** Mint
  `permission-workflows: write` with `permission-contents: write`. A GitHub App's push or merge
  that changes `.github/workflows/` is refused without it, and kept pull requests often edit a
  workflow. R1 merges one without a workflow file, R11 one with.
- **The app's live permission list.** Every mint names its permissions; GitHub refuses a mint that
  asks for one the installation lacks, so each green mint step is a live check of what that job
  uses. R1 (`apply`'s mint) and R13 (the updater's).
- **A comment from the owner's own `gh`.** R11 types the approval with `gh pr comment` from the
  owner's terminal; it should carry no app, since the `gh` CLI is an OAuth app, not a GitHub App,
  and read as typed. P1-021's `gh pr comment` catch-up form waits on R11.

### Fail closed: every stop

- `decide`: a skipped or refused run writes no outputs, so neither `apply` nor `report` acts. If
  `land-answers` refuses, disagrees with `land`'s plan, the answers pass 64 KiB, or the merge's
  digest cannot be computed, `decide` exits 1 with its record kept, and nothing acts. An odd word
  position hands nothing to `apply`.
- `apply`, in the amendment's order: no call when the switch is off or this is not attempt 1; then a
  malformed input; then a failed read; then a pull request that is not open, is a draft, is merged,
  moved its head, or has another base or repository; then a changed digest; then an approval that is
  not one comment, by the owner's login and id, a `User`, with no app and unedited.
- The `PUT`: once, no retry, no `merge-async`, no `bypass_rules`, `sha=` the validated planned head.
  405 and 409 are GitHub's refusal: `main`'s classic protection is strict with `gate` from GitHub
  Actions, admins enforced, no required approvals and no push restrictions, and the active ruleset
  "main: gate required" has strict `gate`, `non_fast_forward` and `deletion` with no bypass actors
  (read 15 Nov). A stacked pull request cannot merge through this route, so a stack formed after
  `decide` fails the call instead of merging the pull requests below it.
- The mint: only with the switch on, only in `trusted`, with two named permissions.
- `report`: malformed answers make no call; a failed read skips that pull request and turns the job
  red; a body without the marker or with `@` is refused; a forged marker is ignored.
- The reader: a review comment whose review is not listed is a failed read, which holds; an owner
  review emptied of its text or comments retires the approval.
- Accepted residuals (the amendment's open item): a comment, edit or deletion in the seconds
  between `apply`'s last read and the `PUT` is not seen; a bot edit, or another run's report post,
  between `decide`'s read and `apply`'s stops the merge with a "Not merged yet" post, and the owner
  comments `/land <head>` again. `apply` does not re-read the labels (`spec-approved`), the pull
  request's body, the dashboard's verdict cell or branch protection; a change to them after
  `decide`'s read is not seen, and GitHub re-checks only `gate` and protection at the `PUT`.

### Real runs (the builder makes them; the owner types where marked)

Before the merge, no key:
- **R0a**: the shadow evidence below.
- **R0b**: `land-apply.sh` against the live API on an open pull request, with a wrapper `gh` that
  sends every `GET` and records the `PUT` without sending it, so no merge route is called: the
  digest from `snapshot-fetch.sh`'s saved reads equals `apply`'s, a comment between the two reads
  gives `digest`, and a comment id that is not the owner's gives `approval`.

After the owner merges. T1 is a throwaway kept, not critical, pull request that adds
`.claude/land-trial.md`, one line, with a real verdict on the dashboard (a model other than the
author's) and a CodeRabbit review. Each stop case types `/land <head>` while `gate` still runs at
that head, then does the stop action before `gate` finishes, so the approval cannot merge first.

| Run | Who | Action | What it proves |
|---|---|---|---|
| R1 | owner, browser | on T1, at the end, `/land <head>` with `gate` green on `main`'s tip | the app merges at that head, `merged_by` is the app, `report` says "Landed <head> … main is <sha>" and that `sha` is `main`'s head, and `apply`'s mint step is green |
| R2 | owner | a bare `/land` | the unnamed answer with its code block, once; no merge |
| R3 | an agent | `/land <head>` with the footer | no merge and no answer |
| R4 | owner | `/land <head>`, then edit it | held |
| R5 | owner | `/land <head>`, then `/hold` | held |
| R6 | owner | `/land <head>`, then a comment an agent answers | spoke |
| R7 | owner | a pending review with an inline comment, `/land <head>`, then submit the review with an empty summary | spoke (item 2); record the comment's `created_at` and `updated_at` against the review's `submitted_at` |
| R8 | owner | `/land <head>`, a review with text, then that summary edited to empty | spoke (item 1) |
| R9 | owner | `/land <head>`, then a push | stale; no merge |
| R10 | owner | `/land <head>` right after another merge, while `main` moves | `apply` stops (`pr`, or GitHub's 405) with no merge at the old head; the next run merges after the updater's push and a green `gate` |
| R11 | owner, own terminal | on T2 (a critical throwaway that adds a comment line to a workflow file and deletes `.claude/land-trial.md`, with `verifier-opus` and other-model passes): `gh pr comment <T2> --body "/land <head>"` | the owner's `gh` reads as typed, and the app merges a pull request that edits a workflow file |
| R12 | an agent | `gh run rerun <run>` and `--failed` on R1's run | `apply` is skipped on attempt 2, with no call |
| R13 | — | the first `update-prs` run after the merge | the three-input mint is green, every pull request behind `main` is rebased, a pull request that edits `.github/workflows/` is pushed (O3) |
| R14 | — | two triggers in one state during R2 to R9 | one post, not two; whether `held` flaps on a failed read |
| R15 | owner | `/land <head>` before CodeRabbit's check finishes | whether the merge stalls with no trigger; over 10 minutes adds `check_run` |
| R16 | — | every run's record | `cost.reads` unchanged, since this row adds no read to `decide` |

Each run is reported on #179, as Done when asks.

### Facts read from the live API, 15 Nov

- `pulls/305/reviews` lists 6 reviews and has no `updated_at`; `issues/305/timeline` has 2
  `reviewed` events, both CodeRabbit's reviews with a body, with `updated_at` equal to
  `submitted_at`. The owner's two empty `COMMENTED` thread-reply reviews have no event. Design A
  saw `updated_at` one second after `submitted_at` on unedited reviews elsewhere (#153, #307).
- `pulls/305/comments`: every item has `pull_request_review_id`, each review it names is listed,
  and each thread reply, the owner's included, has its own empty `COMMENTED` review.
- `github-actions[bot]` comments (#179) have `user.type` `Bot` and app slug `github-actions`.
- `main`'s protection and ruleset: as under "Fail closed".

### Red-flag screen

- **Shallow module:** `LandAnswer` exposes `reply`, `answers`, `handoff` and `Answer.line`/`body`,
  and hides the step mapping, the clause order and the wording. Each script is one entry point.
- **Information leakage:** the digest form has one owner, `land-digest.sh`, run by both jobs; the
  marker is in Lean and in `land-report.sh`, pinned equal by `the-marker-is-the-reports`.
- **Temporal decomposition:** the jobs split by trust boundary (no key, key, write), as the
  amendment requires.
- **Split ownership:** `pr`, `head` and `approval` come only from `handoff`; answers only from Lean,
  except the lines that need the merge call's result, which only `report` writes; `reviewsSpeak`
  is shared by the reader and scorer.
- **Two ways:** `land` prints the recorded decision and `land-answers` the handoff, both from one
  `read`, and `decide` refuses when they disagree.
- **Hand-synced lists:** the clause order is one list; `apply`'s stop codes and `report`'s cases are
  tied by `why-codes-are-worded`; the app's permission list lives in `app-token.test.sh`.
- **Meaning only in prose:** `Reply.landing` and `Summary` are constructors, not `Option` or
  `Bool`; `handoff`'s `none` is stated by `HandoffIsThePlannedMerge`.

### Shadow evidence

The [approved A3 shadow-entry requirement](#approved-a3-shadow-entry-requirement) below sets the
acceptance bar. The following fixed P1-019 window remains mandatory historical evidence; its
failures are preserved separately from prospective validation. The historical window: records
whose `tool` is P1-019's merge commit or later, fetched once with the head's
`gate/shadow-fetch.sh kitimark/mitos <the date of that merge> <dir>` (it also writes `repo.json`
and each merge's `reviews`, which `main`'s scorer ignores) and scored twice, with
`mitos-gate shadow` built at `origin/main` and at the build PR's head. Every
`agrees` of the head's scorer is one of `main`'s (`ASummaryOnlyTakesAgreementAway`, same records),
and the PR body lists each `agrees` that became `disagrees` with the owner summary behind it. A
scorer built after P1-018 marks every record made before it as drifted wherever P1-018 changed the
plan, so those records cannot count, and records from before P1-019 never read a typed approval. If
commit C is split out, score with `main`'s scorer and, for each `agrees` read `oneWordAway`, read
that pull request's reviews for an owner summary with text before the merge, by hand.

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
- **Shadow evidence for A3.** The [approved requirement below](#approved-a3-shadow-entry-requirement) replaces the former requirement that every kept historical owner merge reads `agrees`. The complete failed historical report remains mandatory; prospective validation starts only at the declared deployed truthful-provenance repair. This amendment alone authorizes no merge.
- **Rollback, lightest first.** `/hold` on one PR. Then the owner disables the `land` workflow (`gh workflow disable land.yml`), or merges by hand a one-line PR that sets the constant off. Then revert A4 and A3. A1 and A2 stay, because nothing acts on a `merge` plan then. The owner can merge by hand at any time, as today.

### Approved A3 shadow-entry requirement

The owner approved this replacement acceptance contract on 18 November 2026 (Asia/Bangkok),
[recorded on #191](https://github.com/kitimark/mitos/issues/191#issuecomment-6960918370).
That approval supersedes the proposal's pending-approval status. It does not deploy the
provenance repair, establish a passing prospective window, or authorize merging #336. Only the
A3 shadow-entry requirement changes; the recorder, scorer, runtime guards and other acceptance
requirements stay in force.

> **Historical evidence remains mandatory.** Publish the complete P1-019-to-cutoff shadow report and every disagreement, using unchanged archived records and identical inputs for main and the A3 feature scorer. State main/feature provenance and any differences. The historical report is never rewritten as a pass and unknown identity never counts as coverage.
>
> **Prospective validation begins at a declared deployed repair.** Name the exact main commit that deploys the truthful provenance repair and its deployment/merge time. Fetch every recorder run/attempt, available record and owner merge from that beginning through the declared latest-main cutoff. Include skipped, cancelled, missing, expired, refused, drifted and unreadable inputs in the inventory; explain every exclusion required by the declared boundary. Keep every actual record unchanged.
>
> **The new window must contain at least one real kept owner merge whose recorded prerequisites make it ready.** Readiness is evaluated from the unchanged shadow reader and recorded inputs before comparing with what actually merged: its predicted step must be `present <head>` or `awaitPush <replay>` under the already-approved owner-word assumption, where that assumption is allowed. Its author must be known truthfully, covering independent verification and required Opus verification must hold, and ordinary protection, bot-review, conversation/label and runtime guards must pass. Unknown or ineligible observations cannot satisfy the required positive case. Do not define eligibility by whether the final reported finding is `agrees`.
>
> **Every such ready kept case must read `agrees`.** Compare the predicted head/replay to actual merged content. An unexpected head, other tree, missing pairing, drift or unreadable evidence for a qualifying case fails this prospective bar. This tests substantive correspondence rather than excluding a disagreement after seeing it.
>
> **Account for all remaining cases.** List every kept owner merge that was ineligible or held, every unknown author, incomplete read, edit-induced hold, absent/uncarryable bot review, missing label/answer/footer guard, and every other disagreement. Explain these recorded refusals individually. They stay refusals; none is called agreement or positive validation. Any newly introduced feature disagreement against main remains a blocker and must be fixed or explicitly decided by the owner.
>
> **No merge is authorized solely by this amendment.** R0b and the existing current-head CI, review, independence and owner-merge requirements remain in force.

The readiness decision is recorded before inspecting the final finding. Retain its input
hashes and predicted step alongside each case, so a disagreement cannot be reclassified as
ineligible after comparison. Truthful provider/model/author identity and the policy accepting
independent verifiers remain separate under [#327](https://github.com/kitimark/mitos/issues/327);
GPT/Codex identity is not renamed to Claude/Opus and unknown identity remains a refusal. The
separate bot-review provenance limitation remains [#309](https://github.com/kitimark/mitos/issues/309).

| Required evidence | What must be recorded |
|---|---|
| Historical P1-019 window | The [complete failed report](https://github.com/kitimark/mitos/issues/191#issuecomment-6960727741), unchanged records/input hashes, exact main/feature provenance and every disagreement; its 35 kept failures remain failures. |
| Prospective boundary and completeness | Exact deployed repair main SHA and time; declared latest-main cutoff; every run/attempt, record and owner merge, with every unavailable/refused/excluded input accounted for. |
| Nonvacuous ready correspondence | At least one independently ready real kept owner merge; pre-finding readiness and predicted head/replay; every such case agrees with actual merged content. |
| Remaining refusals and scorer differences | An individual explanation for every ineligible/held/unknown case and other disagreement; any new feature/main disagreement remains blocking unless the owner explicitly decides it. |
| Separate merge prerequisites | [R0b's live-GET/local-intercept IO evidence](https://github.com/kitimark/mitos/issues/191#issuecomment-6960447923), current-head CI, reviews and independence, and owner merge control. R0b does not establish planner eligibility or authorize a merge. |

## Done when
- [ ] `land-apply.test.sh`, `land-report.test.sh` and `app-token.test.sh` pass, and run in ci
- [ ] `land-decide.test.sh`, `land-protection.test.sh` and every `gate/*-test.sh` pass;
      actionlint and shellcheck report nothing
- [ ] `lake build` passes with each module's axiom check: the statements under `statements` proved,
      no `sorry`, no new axiom
- [ ] R0b ran, and the mandatory historical report plus the complete prospective evidence required
      by the [approved A3 shadow-entry contract](#approved-a3-shadow-entry-requirement) are posted
      on #191; each remaining refusal or disagreement is explained in the PR body
- [ ] after the merge: R1 to R16, reported on #179
- [ ] all `checks` pass locally
- [ ] run-log record written (ops/runs/)
