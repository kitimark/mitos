# Review log for #502

This file keeps the review history that `DESIGN.md` no longer carries: the judge's list, round 1
and round 2. Round 3's findings and what was done with each are at the end of `DESIGN.md`
(Verification log). DESIGN-BLOCK below is the Design block, committed as `tasks/502-watch.md`.
`judge-and-attacks.json` was the judge's working file and is not committed.

## The judge's must-fix findings, as the synthesis applied them

From `judge-and-attacks.json`, applied when the three candidates were merged into one design.

- **Identity.**
  - A post is quiet only by class or by a recorded id. The footer is never identity in the
    watcher, and typed words are never hidden.
  - On review routes only a recorded id makes a post quiet, and an unrecorded reply wakes.
  - Each route has its own reader, and reviews use `submitted_at`.
- **Opus's cold-start "answered" absorption is dropped.** Owner posts since the seed are
  delivered.
- **A finished listed check on a new head wakes.**
- **Closes.** The closed route is the paged issues route with `since`, so the 50-cap is gone, and
  a `gone` with no close wakes.
- **Time.**
  - The cursor is on GitHub's clock (the `Date` header of the first read of each poll), with an
    hour of overlap.
  - Wall time is read every step, and `--now` is for tests only.
  - Write records are spent by poll count.
  - A merge is recorded only after it reports merged. That is a rule for the caller, made visible
    by OnlyAMergeExplainsAMerge, and PR 13 writes it into the rules.
- **Failure.** Blind exit 4, the repeated down line, and the per-head `unread` health.
- **Exit codes.** Each code means one thing. Superseded (3) means "do nothing", and cannot-run (1)
  prints on stdout. The stale-tool note goes to stderr and inside a batch (`Render.batchLines`),
  never alone.
- **Shim.**
  - A private copy of the binary is made under the shared lock, and the fd is closed before exec.
  - The tool runs with stdin from `/dev/null`.
  - `started` is taken first.
  - `ensure` is only in `build`.
- **Outside-account events** rank last in the cap. Whether they wake alone is question 6.
- **Lean statements.**
  - Maps compare by lookup, with WF as `Nodup`. No sort is needed, and `decide` fixtures use
    `DecideList.sortStrings` or a local insertion sort.
  - Codecs are tested, not proved, because `Json` is `partial`. What the proofs assume of loaded
    state is checked on load.
  - Files and both `gh` pipes are read as bytes, then `fromUTF8?`.
  - `Shadow.days` and `Speech.stamp?` are reused, and no trusted module moves.
  - The expensive statements are marked, each with its proof plan; only IsoReadsBack has a weaker
    fallback.
  - `WatchCli` imports `MitosGate.Watch`, so the axiom audit is in the build.
- **Tests.** Fault injection uses named exit points, a fixed clock and a fifo-blocking fake `gh`,
  never a timing race.

## Round 1

Round 1: 34 findings (correctness 11, lean 11, owner-fit 12). None rejected outright; two
partly deferred, as marked.

Correctness:
1. PR 1 cannot pass its own rule (blocking). Fixed: no key keeps the footer rule, null is typed,
   an object is its app. Tested in a scratch copy: 145 old checks pass, 5 new ones pass, 4 fail on
   `main`'s script. Diff in `sketch/.claude/scripts/watch-github.pr1.diff`.
2. EveryWakingChangeIsTold false; closes and posts unpinned (major). Fixed: EveryNotableChangeIsTold
   (covers `gone`, needs the close unexplained, concludes `wakes`), ANonQuietPostIsTold,
   ANewCloseIsToldUnlessItsWriterRecordedIt, AScopedConsumerHearsOnlyItsPulls (`Deliver.lean`).
3. Feed seeded from the local clock (major). Fixed: GitHub's `Date` header via `main --include`,
   the cursor moved on every good poll, CursorNeverPassesGitHubNow, TheFeedIgnoresTheLocalClock,
   fixture `aFastClockAtFirstRun`; late listing over an hour is a stated tradeoff and a PR 12
   counter.
4. Review-route posts mislabeled, woken at once, empty `COMMENTED` reviews (major). Fixed: neutral
   label, only typed words skip the window, empty `COMMENTED` reviews dropped in `Shared.facts`;
   listed in PR 10's `watch-diff.intended`.
5. Lease does not protect the read-modify-write (major). Fixed: `pollOnce` re-reads under the
   lease, `stillMine` before the offer save, PR 8 `lease-race` case. Unique poll numbers are
   tested in PR 8, not stated as a theorem (they live in IO).
6. A stale larger `--seen` takes an offer (minor). Fixed: ack needs the exact number, offers start
   at a random base; fixture `aStaleSeenIsIgnored`.
7. No codec version (minor). Fixed: `version` on every file; a newer one exits 1 and is not set
   aside.
8. One refused item fails the poll; route not named (minor). Route now named. Skip-and-count
   deferred to PR 8's follow-up (DESIGN-BLOCK deferrals).
9. Quiet after failed polls; IO error with no stdout line (minor). Fixed: freshness measured at
   the end; `wait` under try/catch prints `cannot run`; stale tool appended by `batchLines`, not
   an item.
10. Package inconsistencies (minor). Fixed: Codex class listed, eight theorems in the audit,
    per-PR imports, PR 9 lists `watch-github.sh` and `pr-state.sh`.
11. Docs promise more (minor). Fixed: question 1 says "no waking item", HANDOVER and Usage say to
    copy `--seen`, record review-thread ids and run one wait before `own`; the merge rule is in
    PR 13; the running handle is unlocked explicitly.

Lean:
12. "Keeps pr-state's rules except #501" false (blocking). Fixed: Voice is land's classes plus the
    #501 fix, four changed classes listed against the jq, `posts-336` with `classes.tsv`, fixtures
    re-authored with the app key in PR 3 and PR 10; the Codex part is question 8.
13. HANDOVER forbids the footer (blocking). Fixed: the prohibition is gone; HANDOVER's "How to
    post" follows the standing footer rule and asks for recorded review-thread ids.
14. Two View statements contradict (major). Fixed: UnreadHeadKeepsItsFacts needs `HeadRead.alone`;
    ReadHeadShowsItsChecks added.
15. Told items not said to wake; `gone` contradiction (major). Fixed with item 2, plus `wakes` in
    AFreshConsumerHearsFinishedChecks and repo-scope health.
16. `Shared.Inv` never established on load (major). Fixed: decidable `Inv`, `Shared.checked?` on
    every load, StartHasInv, canonical `Names` and mark checks in `Store`.
17. Audit outside the build (major). Fixed: `WatchCli` imports `MitosGate.Watch`; PR 2 checks
    that `Watch.olean` exists.
18. Second classifier contradicts Snapshot (major). Fixed: SpeaksAsLandUnlessTyped and
    AnswersAsLandUnlessTyped relate them; land's change is question 8 and optional PR 3c.
19. PR 3 turns pr-state to `?` before the bootstrap (major). Fixed: PR 3a brings the rule to the
    jq now; PR 3 waits for PR 11; question 3 asks whether pr-state may use the fetched tool.
20. Statements prove less than their names (minor). Fixed: `printable` lines over all three ends,
    "the text after `next: `", alarms stated on `View.of`, HeadsComeFromOpenPulls, the re-read
    statement renamed PrevReachesOnlyUnreadHeadsAndStarts, IsoIsTwentyChars a corollary,
    PollCallsBounded said to count processes.
21. `nextMove` unbounded past the deadline (minor). Fixed: branches reordered, EndsWithinOneBudget,
    `leaseBusy` with ABusyLeaseNeverPolls, pure `Moment.of` and `Plan.due`.
22. Compile and API errors (minor). Fixed: `Speech.footer` over `List Char`, top-level `squeezeGo`,
    `SafeSegment` an `abbrev`, both pipes as bytes, reviews take their PR from
    `pull_request_url`, EXPENSIVE labels name proof plans.

Owner-fit:
23. PR 2 before questions 1 and 4 (major). Fixed: Gates in PR-SEQUENCE and HANDOVER; only PR 1,
    3a and 3b start now.
24. Outside agent's replies read as owner words (major). Fixed with item 13 and Usage.
25. Gate-suite command fails (major). Fixed: 0-based shards with `GITHUB_RUN_ID` and `--out` on a
    committed tree, `watch-test.sh` as the local check.
26. Roster stamp missing (major). Fixed: `agents-roster.tsv` and `stamp` then `check` in PR 1,
    PR 13 and HANDOVER; stamp and check run in a scratch copy.
27. No plan PR or task files (major). Fixed: PR 0 adds rows, `tasks/502-watch.md` and one task file
    per row; issue links follow in an agent-merged PR.
28. cut_line contradicts PR 13's dependencies (major). Fixed: PR 13 depends on PR 11 and PR 12;
    cut_line rewritten.
29. PR 12 given to a researcher (major). Fixed: the root runs the arms, a routine PR owner opens
    the records PR; the budget is in question 2.
30. HANDOVER forbids `.claude/hooks/` edits (minor). Fixed: the PR rows' files are allowed; PRs
    open with `gh pr create`.
31. PR 1 brief less exact (minor). Fixed: jq locations, event key, tier, and SKILL.md lines named.
32. PR 13 file list (minor). Fixed: four playbooks in both copies, `.claude/README.md`, two
    `process.md` rows.
33. Open questions not all questions; Q3 cost (minor). Fixed: questions 5, 7 and 8 are questions;
    question 3 lists what a `main` push triggers.
34. Small slips (minor). Fixed: audit list, module budgets and total, `watch-own.sh` 25 lines, the
    tokens field, Time scope, `timeout 590`, `--max` as suggestions, a Terms section.

Later changes to round 1's fixes, made in round 2: the fixture `aFastClockAtFirstRun` (item 3)
is renamed `theFirstPollAsksADayBackOnGitHubsClock`, because it involves no local clock;
`IsoIsTwentyChars` (item 20) is dropped, since nothing used it; the deferred skip-and-count
(item 8) is built as skip-and-tell for post and close items; the hand-written audit list (items
10, 17 and 34) is replaced by an audit that finds every theorem and statement itself.

## Round 2

Round 2: 32 findings (correctness 10, lean 11, owner-fit 11; 2 blocking, 13 major, 17 minor). All
were checked against the package and `main` at `7dfd6cb`. None was rejected; parts of three are left
to owner questions, as marked. Names below are as round 2 left them; round 3 renamed
`TheSameReadTwiceAddsNothing` to `AReReadAddsNoPostOrClose` and split PR 7 into 7a, 7b and 7c.

1. Idle clone over 23 hours drops posts with no gap (major). Fixed: `Feed.lostWindow`; a poll whose
   `since` starts before the kept window sets `prunedPoll` to its own number, so every older mark
   hears the gap. `AnUnpolledDayIsAGap`, fixture `aDayWithNoPollIsAGap` (30 hours idle).
2. A failing reviews or second-look read is counted nowhere (major). Fixed: misses per head and per
   route (`HeadRoute`), `Health.unread pr sha route`; `MissesCountFailedReads`,
   `AFailingHeadReadIsTold`; the DESIGN wording now matches.
3. One refused item blinds every consumer for good (major). Fixed both ways: post and close readers
   drop other logins first and turn a bad owner item into `Refused`, told once as `could not be
   read` while the cursor moves (`ARefusedItemIsTold`, a PR 4 reader case); the shape refusals that
   remain are stated truthfully in Tradeoffs and `Observe.lean`.
4. A quiet or blind end acks ride-along items unshown (major). Fixed: a report that holds any item
   is delivered at the deadline; quiet and blind need an empty report (`Moment.ending`,
   `QuietEndAcksNothingUnshown`, fixtures `anOutsidePullRidesToTheDeadline`, `nothingToldEndsQuiet`).
5. Fresh and reset consumers start an hour back; the first-poll scan has no replacement (major).
   Fixed: they start at the feed's floor (`Mark.fresh`, `Feed.floor`), `--since` older than it is a
   gap; the scan's drop is a stated tradeoff, in `watch-diff.intended` and PR 13's text; the cut
   puts head lines before `opened` lines (`ChecksAreCutLast`).
6. DESIGN-BLOCK says `depth: build` for an unchecked sketch (blocking, lean lens). Fixed: contract
   only for the Lean rows, build for PR 1 and PR 3a; each Lean row starts with the Architect's
   type-check and upgrade (DESIGN-BLOCK, PR-SEQUENCE, HANDOVER).
7. HTTP-date fixtures cannot reduce under `decide +kernel` (major). Fixed: `Time.lean` parses
   `List Char` with `Base.Text.split` and `parseNat`; `Base.Text` is in the reuse list and HANDOVER
   names the helpers to avoid.
8. `EveryNotableChangeIsTold` false (major). Fixed: (a) the `closed` disjunct's wake is
   `cl.author.wakes o`; (b) `View.of` drops a pull that the same poll's closes name, and
   `Plan.fixed` reads open pulls before closes, so the race is gone (`PullsAreTheOpenPullsRead`,
   `HeadRead.alone`).
9. No statement that no news blocks to the deadline (major). Fixed: `AReReadMovesOnlyHealth`,
   `Shared.noNewsSince`, `NoNewsStaysQuiet` (EXPENSIVE, with a plan); `CopiedTrailerNeverSpins` and
   `IgnoredTrailerReplaysOnce` restated over it; DESIGN says time-started alarms still wake.
10. View statements satisfiable by an empty view; `nextAges` unstated (major). Fixed:
    `PullsAreTheOpenPullsRead`, the three alarms as iff statements, `NoRunFoundNeedsASuccessfulLook`,
    `AFailedLookMovesNothing`.
11. PR 3c cannot be built in one file (major). Fixed: row 3c, `touches` and `must_not_touch` name
    the real Snapshot set; question 8b says it changes land's admission across several trusted
    modules. Deferred to the owner: whether to build it (8b).
12. `depth: build` breaks the repo rule (blocking, owner-fit lens). Fixed with 6.
13. The package never reaches an outside implementor (major). Fixed: PR 0 commits it under
    `tasks/502-watch/`; before that the orchestrator hands it over, and HANDOVER says PR 1 and PR 3a
    cannot start from a bare clone.
14. HANDOVER's must-not list contradicts rows 3c and 11 (major). Fixed: the list is a default that
    a row's Files column overrides for that PR; `.github/` is owner-kept.
15. DESIGN.md too long for the owner (major). Fixed: a plain summary and the questions first, Terms
    explained, statement names out of Shape, the synthesis trimmed, round 1 moved to `REVIEW-LOG.md`.
16. A spurious `gone` after the root's own merge (minor). Fixed with 8(b): a close read in the same
    poll removes the pull from the view, so no later `gone`.
17. `queued` measured on the local clock (minor). Fixed: `ciHealth` takes `fixed.serverNow`;
    `QueuedIsMeasuredOnGitHubsClock`. A stale run takes no time.
18. A mark ahead of the shared state is not a reset (minor). Fixed: `Mark.fits` (same generation and
    poll not above the count); `ResetIsNeverSilent` and `GapIsNeverSilent` use it; a Store case.
19. Store housekeeping unspecified (minor). Fixed: four rules in `Store.lean` and PR 8's cases (post
    records pruned and read once, `.tmp` cleanup, re-read before saving an offer, first state made
    under the lease).
20. Docs say more than the sketch (minor). Fixed: (1) "rides on every end" softened to blind ends,
    the stale note goes to stderr at quiet and blind ends; (2) HANDOVER's review-thread wording;
    (3) #239's second half is a Tradeoff; (4) question 3c and HANDOVER cover an outside agent's
    tool.
21. Line budgets too small (minor). Fixed: about 5,300 lines as code plus proofs, with planned
    splits of Deliver, Observe and View.
22. `OutsidePullsAreNeverRead` is a tautology (minor). Fixed: restated over
    `Plan.perHead (Plan.heads owner fixed)` in `Observe.lean`; the field-only version is gone.
23. The `--include` header reader would refuse every answer (minor). Fixed: the CRLF framing in
    `Gh.lean` and Risks, and a captured fixture in PR 4.
24. The audit lists statements by hand (minor). Fixed: `Watch.lean` finds every theorem and every
    `def ... : Prop` under `MitosGate.Watch` and fails on a statement with no theorem.
25. Small nits (minor). Fixed: the fixture renamed `theFirstPollAsksADayBackOnGitHubsClock`;
    `IsoIsTwentyChars` dropped; `WatchCli` has one `Args` and `parse` per subcommand in
    SpeechCli's shape; `quotedWordsStayUnanswered` is in thread 501; the two Feed statements are
    marked moderate.
26. Owner questions bundle decisions (minor). Fixed: lettered sub-questions 2a-c, 3a-c, 5a-b, 8a-c,
    each with its own recommendation and an answer format; call 4 is "for the record".
27. PR 15 deletes tests with no owner decision (minor). Fixed: question 9, sign-off gate, the
    dashboard records the week, role hard. Deferred to the owner: the answer itself.
28. PR 3b has no brief or issue (minor). Fixed: a HANDOVER brief; the root files the issue first;
    PR 3b goes after PR 3a.
29. PR 9 mixes in an owner refactor (minor). Fixed: `lib/owner.sh` dropped; `watch.sh` reads and
    checks `MITOS_OWNER` itself, as `pr-state.sh` does; a shared default is a follow-up.
30. Posting rules for tools without an app (minor). Fixed: HANDOVER's fallback (no issue comments,
    say so in the PR body) and a line that the footer is the repo's marker for any agent.
31. Unresolvable principles, undefined terms (minor). Fixed: real skill names
    (`principle-boundary-discipline`, `principle-type-system-discipline`,
    `principle-redesign-from-first-principles`), a HANDOVER glossary, no "resumes you".
32. Token figures not reconciled (minor). Fixed: one derivation from the measured session under
    Alternatives; the old "282 re-arms" in Problem is now 437 expiries; PR 12's budget restated.
    Deferred to the owner: the budget itself (question 2c).
