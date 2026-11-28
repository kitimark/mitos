# Review log for #502

This file keeps the review history that `DESIGN.md` no longer carries: the judge's list, round 1,
round 2 and amendment 1. Round 3's findings and what was done with each are at the end of `DESIGN.md`
(Verification log). DESIGN-BLOCK below is the Design block, committed as `tasks/502-watch.md`.
`judge-and-attacks.json` was the judge's working file, for the design and again for amendment 1, and
is not committed.

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

## Amendment 1

**What was asked.** On 27 November the owner answered PR 0's part A. Two answers changed the
design. 5a: "i think the daemon could support specific each agent would like to subscribe. so, i
may have multiple agents handle each topics independent". 2b: "what's the best practices for cloud
remote. it may use for another agent like codex, and another agent provider as well." The root read
them as per-agent topic subscriptions, and as a provider's cloud container for the baseline host of
every agent. The other answers: 1 yes, 2c ok, 3a ok, 8a ok, 8b ok (PR 3c is required), 9 yes.

**How it ran.** Three runners (opus, sonnet, fable) redesigned the package at PR #580's head
`efefa55`, from one task. An opus judge scored them, and three lenses attacked them: coverage, lean
and cloud. The root wrote the synthesis brief, and the synthesis amended the package in place. It
lands in PR 0b, before rows 7a to 13. The findings deferred to #581 stay out.

**Where the runners agreed.** A topic is a small closed set of kinds plus a repository-or-items
scope. It is declared by flags on every wait and printed back by the trailer. There is no
`subscribe` verb, and the shared poll stays whole. The app part of `--as` only classifies a post.
The old 5a quiet rule became a kind that is off by default, and `quiet` shrank to recorded ids.
Notes pass every topic, who acts is a rule, and PR 3c is required.

**Base.** candidate-fable (judge 28, against opus 21 and sonnet 21). A subscription is a lens on one
wait: `report = notes ++ lens (facts)`. `facts` reads no subscription and no app. The place a caller
stands never reads the subscription. `--ride` replaces `OutsidePolicy`.

**Grafts and the root's decisions.**
1. Checks split into `passed` and `failed` (sonnet's red and green). A root that let every check
   ride would learn of a green gate only at its deadline.
2. Riding is a closed type of four kinds (`Rides`), so `--ride words|agents|peers|pulls` is exit 2.
3. A changed topic is told once (`Note.newTopic`, AChangedTopicIsTold). The offer and the place
   record the subscription as data only, so TheOfferIgnoresTheSubscription stands.
4. `status` shows each caller's last subscription and an `overlap:` hint, tested, not proved.
5. The who-acts rule for PR 13, with the window it leaves open.
6. The idle cost of standing topic agents: Tradeoffs, question 12 and PR 12's counter.
7. Lean, from sonnet: the kind reader derived from one list (KindNamesReadBack), and a typed round
   trip of the trailer's flags (TheTrailerFlagsReadBack). The topic types sit in a new pure module,
   `Watch/Topic.lean`, so that `Wake` keeps one topic.
8. `peers` off by default, put to the owner as question 11.
9. From opus: the offline attestation path for row 11 (one runner's live probe, not replicated),
   the list of rows that do not change, and the Terms fix (an idle pause keeps the files, and a
   reclaimed container loses them).
10. From sonnet: one check per host row, and the note that fixtures built with `Post.of` must not
    unfold `Excerpt.of`.

**Rejected.** Opus's rank and peer taking: one caller hides facts from another, a `--since` case
blocks, the owner's words could wait up to 30 minutes, and topics become a hierarchy. Opus's
required `--topic` and its `Mark.taken` absorb. Sonnet's ack bound to a topic, its `Option Heard`,
its proof claim on a Json codec, its statement over `String.splitOn`, and its coverage statement
over a topic no caller runs. A saved `subscribe`, claims or exclusive routing, a mark per topic, and
narrowing the shared poll.

**Corrections to the brief.** The sketch's size is the measured one: 2,930 lines and 39 stubs
before, 3,700 and 42 after verification round 3, not the 2,736 and 34 the package claimed. The
Cursor "narrower token" claim was not in the package. Round 3's 15,000 REST limit (item 29 of its
log) gives way to the `x-ratelimit-limit` header and GitHub's documented 5,000 for a user token.

**Departures from the brief.** Five, and PR 0b's body lists them all:
1. `--max 7` under `timeout 590`, with the brief's 30-second margin. The brief's own example,
   `--max 8`, breaks its rule (480 + 90 + 30 = 600), so the rule stands and the example changes
   (verification round 2 undid round 1's 20-second margin).
2. At most three waiting containers, not the brief's four, whose own numbers do not fit four
   (default 14, round 1 item 6; the arithmetic is in the fleet row).
3. No lifetime for a Cursor Build, which its pages do not state, in place of the brief's 30 days
   (round 1 item 7, round 2 item 12).
4. `skipped` and `neutral` pass, as `success` does; the brief made every other conclusion `failed`
   (round 1 item 1).
5. A head line carries several kinds: it is both `passed` and `failed` when one check newly passed
   and another newly failed; the brief made it one or the other (round 2 item 2).
The root accepted 1 to 3 in its round 3 ruling. 4 and 5 are fixes of the brief's decision 1 that
two rounds confirmed, and they wait for the root's acceptance in PR 0b's body.

**Statements.** 112 become 129: 20 new, 3 removed, 23 restated and 86 unchanged
(`tasks/502-watch.md`, statements, Amendment 1's delta, names each). By row: 7a 13 to 19, 7b 17
to 25, 7c 24 to 27.

### Lens findings

34 findings: coverage 17, lean 8, cloud 9 (1 blocking, 21 major, 12 minor). Moot means the finding is
about a shape that was rejected. The lenses' questions for the owner became questions 11, 12 and 13
and default 14; the others were moot.

Coverage (10 major, 7 minor):
1. Opus: coverage is met by callers that are registered but not waiting, so the root hears the
   owner's words up to 30 minutes late (major). Moot. Words cannot ride (`Rides` has no field for them), and
   OwnerWordsWakeWhoeverHearsWords holds whatever a caller lets ride.
2. Opus: a lapse is cached as a Bool (major). Moot: there is no presence or lapse.
3. Opus: `leave` replays the last batch to the root (major). Moot: there is no `leave`.
4. Opus: rank takes items of unknown thread from the root (major). Moot: there is no rank, and
   ARefusedItemIsTold holds over `facts` for every caller.
5. Opus: rank makes topics a hierarchy and can starve a topic agent (major). Moot: topics are
   independent.
6. Sonnet: the coverage statement is about a topic nobody runs (major). Fixed in the base:
   TheCatchAllHearsEverything is stated for the catch-all, the form the root runs.
7. Fable and sonnet: a narrow wait of the catch-all acks the owner's words unseen, widening says nothing,
   and a respawn without flags is a second catch-all (major). Fixed: the place records the
   subscription it was taken under, as data, and a wait whose topic differs gets one `topic
   changed` note (AChangedTopicIsTold) that names what is newly heard and hidden and says older
   facts are not replayed. QuietEndAcksNothingUnshown's docstring says what it covers, and
   QuietCatchAllHidOnlyPeers states the catch-all form. A second catch-all observes (who acts).
   `status` shows it only by a second `(catch-all)` tag, since `Topic.overlap` skips catch-alls
   (verification round 1, item 9), and a Tradeoffs line says so (corrected in verification
   round 3). Rejected: a "not a catch-all" line on every narrow wait, which would
   be noise for every topic agent.
8. All three: who acts is a rule, and two handlers can act within one poll (major). Fixed as a rule
   (PR 13): one handler per topic, named in its brief and on the dashboard; a handler reads REST
   before it writes, stops if a post or a commit answers it, and records its post with `own`; a
   second subscriber observes. The remaining window is said plainly. Rejected: `also heard by` on
   each line, which reads other callers' state and still says nothing across containers.
9. All three: the owner's Claude-app issue comments have no default hearer (major). Put to the
   owner as question 11, with pr-state's reading of such a post said plainly. Their review-thread
   posts through the app carry no app key and wake as before. The recording hook stays a deferral, and
   `own`'s read-back stays in PR 8.
10. Opus and fable: nothing wakes the root for a green gate while checks ride (major). Fixed:
    `passed` and `failed` are two kinds, and the root keeps waking on `passed`. A kind rides for the
    root only while its named handler handles it end to end, and the root takes it back when a
    riding line shows a fact unhandled. Rejected: a derived merge-ready fact, which pr-state gives.
11. Opus: a fresh `--since` mark ignores selection (minor). Moot.
12. Opus: a write record is spent before a held change comes back (minor). Moot.
13. Opus: widening and narrowing prove less than stated (minor). Moot: the base tells a changed
    topic once instead of replaying.
14. Opus and fable: no kind for failures only (minor). Fixed: `failed`
    (AHeadLineFailsOnANewFailure, so named since verification round 1 below).
15. Sonnet: topic equality makes the ack brittle (minor). Moot: the ack never reads the topic, and
    `--on` is sorted without repeats.
16. Fable: `--ride` accepts kinds that must wake, and a topic of riding kinds only never wakes early
    (minor). Fixed: `Rides` has four fields (OnlyChecksAlarmsAndOutsideRide). The second half is
    kept on purpose: `--topics outside` with the default ride is the outside digest, and `--ride
    none` makes it wake.
17. All three: standing topic agents re-arm in a loop (minor). Fixed: the idle cost in Tradeoffs
    (about 70k tokens over 99 minutes for one watcher agent, one run), question 12, and PR 12's
    idle-cost counter.

Lean (1 blocking, 4 major, 3 minor):
1. Opus: a fresh peer's `--since` mark swallows an owner word, and its coverage statement stays
   true (blocking). Moot: rank and peers are rejected.
2. Opus: `View.holds` reads an absent key as held (major). Moot.
3. Sonnet: TheFlagsParseToTheTopic is false, and it and a codec claim sit outside the audit
   (major). Fixed in the graft: TheTrailerFlagsReadBack is over typed `Flag` values, for canonical
   subscriptions, in the audited `Topic.lean`. The text reader `WatchCli.flags?` is tested, and no
   codec makes a proof claim.
4. Sonnet: a statement over `String.splitOn` (major). Fixed: no statement is over text. `Render`'s
   flags have four `decide +kernel` fixtures, which print numbers through `Nat.toDigits`.
5. Sonnet: coverage over `Topic.everything` (major). As coverage 6.
6. QuietEndAcksNothingUnshown no longer means what it says for a narrow caller (minor). Fixed: its
   docstring and its Design block line say a quiet end acks nothing the subscription selects, and
   QuietCatchAllHidOnlyPeers is added.
7. No round trip of the trailer's flags (minor). Fixed: TheTrailerFlagsReadBack (moderate).
8. Opus: two oversold statements and a frozen presence cache (minor). Moot.

Cloud (7 major, 2 minor):
1. The profile is prose, not commands (major). Fixed: one read-only check per row, and from PR 11
   `build --fetch` prints one `watch: host:` line per failed row.
2. The `--max` rule and the examples disagree (major). Fixed: `--max` × 60 + 90 + 20 ≤ the bound,
   so 8 under `timeout 590` and 27 under Monitor (the new default). Every example is corrected in
   `DESIGN.md`, `PR-SEQUENCE.md`, `HANDOVER.md` and the task files.
3. The slug depends on how GitHub is connected (major). Fixed: the slug row. Claude cloud needs the
   Claude GitHub App connection, which the package's live check saw on this repository, and a host
   whose posts name no app posts no issue comment. Not asked as a question.
4. On the baseline host the online check cannot reach its trust root (major). Fixed: offline
   verification on every host, against a pinned trusted root, with the bundle's two sources named,
   `--signer-workflow`, `--source-ref`, `--repo` and a check of the repository id. A rotated root
   fails closed until a PR the owner merges renews the file (question 13). Row 11 needs one real run on
   Claude cloud.
5. The asset assumes x86_64 Linux and its libc; the owner's own device is not covered (major).
   Fixed: the cpu row, and a paragraph on the owner's device.
6. The REST budget with many containers is unstated, and the package said 15,000 (major). Fixed:
   the token row reads `x-ratelimit-limit` (GitHub documents 5,000 for a user token); the fleet row
   and default 14 (a cap on waiting containers, three since verification round 1); Codex needs a
   token (default 3c); conditional requests come
   first in the deferrals, since a 304 is free.
7. Opus treated Antigravity as local only (major). Fixed: the remote-agents row, citing its
   changelog.
8. Claims beyond the pages (minor). Fixed: the two OpenAI pages are said to disagree and marked not
   verified; fetching at session start is the rule and a setup copy only a cache; every unmeasured
   `--max` is a starting value. The Cursor quote was not in the package. Left open: whether Codex's
   preset covers the release-asset host; `HANDOVER.md` says a fetch in Codex's agent phase needs it.
9. One wake source per host (minor). Fixed: the wake row names Claude's PR-activity and auto-fix
   subscriptions and Cursor's CI subscriptions.

### Verification round 1

26 findings (coverage 12, lean 5, host-fit 9; 8 major, 18 minor), each checked against the
package, `main`'s `ci.yml` and `watch-github.sh`, and the cited pages on 27 November. Two pairs
are one defect each, so 24 items follow. Every major is fixed. A minor is fixed where its fix is a
line or two in a file this round touched. One minor is rejected and two are fixed in part. No
statement is added or removed: 129 stay, and the counts by row stand.

Major:
1. The `failed` kind counted `skipped` (coverage and lean). Confirmed: `ci.yml` skips `prove` on
   every `labeled` and `unlabeled` event, and `Checks.of`, like the bash watcher's `newest_run`,
   takes the newest run. So a label run made a `failed` line, and a root that let `failed` ride
   missed the green gate that came with it. Fixed with a closed set: `Wake.passingConclusions` is
   `success`, `skipped` and `neutral`, and every other conclusion fails, one never seen included.
   `cancelled` fails on purpose: `kitimark-mode` does not call it red, but someone must re-run it.
   AHeadLineFailsOnANewNonSuccess is renamed AHeadLineFailsOnANewFailure, with
   `c ∉ passingConclusions`, and the new fixture `aLabelRunsSkippedProvePasses` pins the label run
   and a skipped CodeRabbit check. `Topic.lean`'s kind docs, the kind table and What wakes in
   `DESIGN.md`, the Design block, row 7a and `AMENDMENT-1.md` say the same.
2. Docstrings that stated removed rules (lean). Fixed in `Voice.lean` (the quiet rule, and 8b as
   answered), `Observe.lean` (a refused item is told to a caller that hears its kind) and
   `Deliver.lean` (`ARefusedItemIsTold`). No statement changes.
3. A CI-failures agent beside `kitimark-mode`'s rule that CI failures go to the PR's owner
   (coverage). Fixed: Usage says a red check on a pull request belongs to its PR's owner (a
   running one hears it on its `--on` wait; the root resumes one that returned, or gives the pull
   request a new one), and a CI-failures agent handles what no PR owner holds, the `ci:` alarms,
   and observes the rest. Only the root resumes agents, so question 10, owner decision 10 and
   row 13 now say the root lets `failed` ride only while no PR owner it would resume waits on CI.
   `HANDOVER.md` (Waiting on GitHub) says a PR owner's own red checks stay its own. The root's
   catch-all overlaps every handler by design, so `Topic.overlap` no longer names a catch-all
   (minor 9).
4. `own` records and new containers (coverage). "Once in each new container" meant once per
   container, but the risk behind it was not said. Fixed: Tradeoffs, the disk row,
   `AMENDMENT-1.md` and `HANDOVER.md` (Setup) say the records never cross containers, so a
   respawned handler hears its own earlier review-thread replies again. Reading REST before it
   writes stops it; the risk left is that it takes its own reply for your words and answers it
   once more.
5. `plan/phase-2.md` still waited for answered questions (host-fit). Fixed: P2-019 waits for
   P2-018 and PR 0b; P2-025 for P2-023 and PR 0b (question 13), with 3a answered and the baseline
   host named; P2-026 for P2-025 only; the closing paragraph says 1 and 8a are answered. Every
   issue link is kept.
6. Four waiting containers pass the REST limit (host-fit, and the coverage minor on the same
   arithmetic). Confirmed: 4 × 1,260 = 5,040, above 5,000, before pr-state, the builders and the
   owner. Fixed: default 14 is three containers, fewer while more than five owned pull requests
   are open (containers × (6 + 3 × heads) × 60 under about 4,000 an hour). Raising it waits for
   PR 12's request counter and conditional requests, which now go ahead of any raise. This departs
   from the synthesis brief's four, whose own numbers do not fit it.
7. Cursor's "30 days" and its internet default (host-fit). Checked on 27 November:
   `/cloud-agent/builds` states no lifetime and a 24-hour default staleness threshold for
   rebuilds, and `/cloud-agent/security-network` says "The agent has internet access by default"
   and that a team admin can set the mode. Fixed: the 30 days is gone (it came from the synthesis
   brief), the row and the tool paragraph say Cursor rebuilds a Build once it is 24 hours stale by
   default, both pages are in [3], and how long a Build lasts is listed as not verified.

Minor:
8. A narrowed root (coverage). Fixed: one Tradeoffs line each in `DESIGN.md` and `AMENDMENT-1.md`
   (it is told once by `topic changed`, and its trailer shows the flag).
9. The `overlap:` hint is noisy (coverage). Fixed with major 3: `Topic.overlap` skips a
   catch-all, the fixture is now `aWordsAgentAndAPrOwnerOverlapOnWords`, and the status example and
   the `topics/` case name two callers that are not catch-alls. The premise that it prints on every
   wait was wrong: only `status` prints it.
10. A topic of riding kinds only never wakes early (coverage). Fixed: one sentence in Usage (such a
    topic is a digest that ends on a note or at its deadline, and `--ride none` makes it wake), and
    default 6 says the same. The behaviour stays, as lens item 16 decided.
11. `Voice.lean`'s header is stale about lines (coverage). Rejected: `Voice.lean` is about who
    spoke in a post, not about lines. `Render.lean`'s header lists every line, `topic changed` and
    the flagged trailer included, and the `status` lines are in `WatchCli`. Its stale sentences
    were major 2.
12. Plan rows in baseline wording (coverage). Fixed with major 5: P2-025 names the baseline host;
    P2-019 already had 19 statements, and P2-026's text was right.
13. The Bash timeout parameter (coverage). Fixed in the time row and `HANDOVER.md`'s host table: a
    `timeout` parameter of 600000 ms, with `timeout 590` inside the command.
14. The slug row and the profile's length (coverage). Fixed in part: the slug row's sentence is
    split. Rejected: a trim of the profile, whose rows, checks, tool paragraph and provider table
    are what the synthesis brief asked for.
15. A wrong `own` id (coverage). Fixed: `HANDOVER.md` (How to post) says to record the id the post
    call returned, never one read from a list. The risk was already in Tradeoffs, for every caller
    of the class, not one.
16. No statement that `ofFlags?` makes only canonical subscriptions (lean). Taken as the finding's
    second option: the `TheTrailerFlagsReadBack` docstring and the Design block say that half holds
    by inspection of `add?` and the fixtures, and is not stated.
17. "Told once" is stated one way only (lean). Taken as its second option: the `notes` docstring,
    the Design block and `AMENDMENT-1.md` say the "not again" half is tested by
    `aWiderTopicIsToldOnce` and the `topics/` case, not proved.
18. Untyped binders (lean). Fixed: `IgnoredTrailerReplaysOnce`, `EveryNoteIsReported` and
    `WhatIsToldPassesTheLens` annotate them, and so does `CopiedTrailerNeverSpins`, which had the
    same one. No meaning changes.
19. The Codex pages (host-fit). Checked: both developers.openai.com pages answer 302 to
    learn.chatgpt.com, whose environments page says secrets "are removed before the agent phase
    starts". Fixed: the row says so, says the proxy claim was not found, and stays not verified;
    [2] names the redirect targets.
20. The 20-second margin (host-fit). Fixed: the time row, `HANDOVER.md`, row 12 and
    `AMENDMENT-1.md` call it a starting value that PR 12 re-checks, and `HANDOVER.md` says a wait
    that `timeout` stops saved no offer, so its caller runs its last command again. `--max 8` stays.
21. Host checks that do not test their row (host-fit). Fixed: time and wake are the caller's own
    checks and print `unchecked`, as slug does (row 11); the verify check runs `gh attestation
    verify` offline on the installed binary; the asset check picks the asset by the name row 11
    fixes; and the rest check confirms that `attestation verify` takes `--custom-trusted-root`, in
    place of a version number.
22. Offline attestation (host-fit). Fixed: row 11 and P2-025 refuse a bundle from another ref and
    one from another workflow too; the id check names its read (`--format json --jq` on
    `sourceRepositoryIdentifier`, a path row 11's real run confirms); and the tool paragraph says a
    revoked key goes unseen until the pinned file is renewed.
23. `AMENDMENT-1.md` is at the edge of three pages (host-fit). Fixed in part: the restated list is a
    count with a pointer, and the cloud summary lost two bullets. The lines this round added keep
    it at about 1,500 words of prose plus its code blocks.
24. "Rows that do not change" in `PR-SEQUENCE.md` (host-fit). Fixed: row 2's recorded answers are
    named beside row 15's note.

### Verification round 2

17 findings (coverage 3, lean 6, host-fit 8; 4 major, 13 minor), each checked against the package
and, for the pages, `cursor.com/docs/cloud-agent/builds` and
`cli.github.com/manual/gh_attestation_verify` on 27 November. A coverage minor and a lean minor are
one defect, so 16 items follow. Every major is
fixed. No statement is added or removed: 129 stay, and the counts by row stand. The statements this
round restates were all new or restated in amendment 1 already.

Major:
1. A narrowing lost more than the `topic changed` line said (coverage). Confirmed: a narrowed
   wait's report is lensed, and taking it moves the place to the state it reported from, past what
   the new topic hid since the acked place. The Tradeoffs line said such facts stay unheard "until
   it re-arms with the old flags", which was false, and it disagreed with the line on a narrow
   caller's place. Fixed: `Note.newTopic` carries a count, `hiddenBy` (the facts since the acked
   place that the old topic tells and the new one does not), which `report` computes and `notes`
   takes. The line says taking the batch passes those facts and the old flags do not bring them
   back. "Changing a topic", the place decision, Tradeoffs, `Render.lean` and `AMENDMENT-1.md` say
   so, and the false clause is gone. The eight statements over `notes` take the count as one more
   binder (NotesAreNotes, AnUntakenOfferIsReplayed, GapIsNeverSilent, ResetIsNeverSilent,
   AFailingGitHubIsTold, AChangedTopicIsTold, EveryNoteIsReported, QuietCatchAllHidOnlyPeers).
   Fixtures: `aNarrowedRootCountsWhatItHides` (in the sketch, on `hiddenBy`), the planned
   `aNarrowerTopicIsToldWhatItPasses`, and a narrowing `topics/` case, named in rows 7b and 8 and
   in P2-020.
2. A head line was one kind (lean). Confirmed both counterexamples: a green gate measured on one
   line with a new red check was `failed`, so it rode for a root that lets `failed` ride, and a
   caller that hears only `passed` could miss it, depending on timing. Fixed in the design, not
   only said: `Change.kinds` makes a head line `passed` when a listed check newly passed, `failed`
   when one newly failed, and both when both did. `Subject.kinds` holds the list; a line is told
   when the topic hears any of its kinds, and it rides only when each kind of it the topic hears
   rides. Restated: AChangeIsAboutItsOwnKind (a head line is `passed` whenever a check newly
   passed), AHeadLineFailsOnANewFailure (over `.failed ∈ kinds`), EveryNotableChangeIsTold,
   SkipsWindowIsTheWordsKind, TheCatchAllHearsEverything (its proof adds a case split on
   `Item.subject`) and QuietCatchAllHidOnlyPeers. Fixtures: `aGreenGateBesideARedCheckIsBoth`
   (Wake) and `aGreenGateBesideARedCheckWakesTheRidingRoot` (Deliver, both counterexamples);
   `aRedGateFailsAndAGreenHeadPasses` now uses a red gate alone. Question 10's sentence holds now,
   and the kind table, Terms, `--ride`, What wakes, `Topic.lean`, the Design block and
   `AMENDMENT-1.md` say a line can be both.
3. The `--max` margin (host-fit). Confirmed: round 1's 20-second margin kept `--max 8` under
   `timeout 590` with no slack (480 + 90 + 20 = 590) and overrode the brief's rule. Fixed the other
   way: the margin is 30, as the brief says, and the example is `--max 7` (540), in `DESIGN.md`
   (Usage, the time row, the Claude and Cursor rows), `AMENDMENT-1.md`, `HANDOVER.md` (the rule and
   the host table), rows 12 and 13 and the Design block's revisit line. Under Monitor 27 stays
   (1,740 of 1,800). The time row's check computes `max * 60 + 90 + margin`.
4. The Codex fallback could not run (host-fit). Confirmed: under Codex's defaults the agent phase
   has no internet and no secrets, and a `gh` loop needs both. Fixed: default 3c, Usage, the Codex
   rows of `DESIGN.md` and `HANDOVER.md`, Waiting on GitHub, `AMENDMENT-1.md`, the Design block and
   P2-023 say that neither `watch.sh` nor a `gh` loop reads GitHub there, so a Codex task does not
   wait: it reports "pushed, waiting on CI" and stops. The setup phase can fetch the toolchain and
   the tool (a cache of up to 12 hours), and Setup says its install lines run there on Codex. The
   ask when Codex first takes a row stays.

Minor:
5. The sketch's size (coverage and lean). Fixed: 3,667 lines and 42 stubs after this round
   (`wc -l` over the 16 files; stubs counted as `panic! "not implemented"`), in the Design block and
   in the corrections above.
6. Three departures from the brief (coverage). (a) is gone with item 3. (b) and (c) stay, listed
   under Corrections to the brief for PR 0b's body; (b) is also default 14, which the owner may
   overrule.
7. Three places said a taken offer acks nothing the batch did not show (lean). Fixed in `finish`,
   `Moment.ending` and the offer-and-ack decision: nothing the subscription selects.
8. `EveryNotableChangeIsTold`'s docstring (lean). Fixed: the kind claim is for `gone`; a close is
   told under the kind of the author its route read. The Design block says the same.
9. Module budgets (lean). Fixed in part: `Topic.lean` is budgeted at 320, and the total is about
   5,800 in the Design block and in Risks. Rejected for `Deliver.lean`: its split at 600 lines is
   planned, not a deviation. The Design block now says the sketch already passes 600, so the split
   comes with row 7b or 7c, and the Architect budgets each half at that upgrade.
10. `Topic.overlap`'s docstring (lean). Fixed: the hint counts `agents` and `peers` only between
    callers of one app, so it can miss an overlap between apps.
11. Cursor's 24 hours (host-fit). Checked: Cursor rebuilds on a recurring schedule it does not
    state, and with "Update stale builds" on, an agent whose Build is older than the threshold
    (24 hours by default) pulls the latest default-branch code at start. Fixed in the tool
    paragraph, the Cursor row and Not verified.
12. Antigravity's facts (host-fit). Fixed: [4] cites /docs/changelog, and the `env-setup.sh` name is
    marked not verified, in the row and in Not verified.
13. Host checks (host-fit). Fixed: the profile says `build --fetch` runs seven checks, and that
    time and wake are the caller's own and slug needs a comment id, so those three print
    `unchecked`; the cpu check is one command, the verified copy's own `watch status`, run
    before it is installed (row 11 says so), since a reading of the host does not show that the
    binary loads; the asset row reads a named release tag, not `releases/latest`.
14. Offline verification (host-fit). Checked: `gh attestation verify` has `--source-digest`. It is
    not used, and the tool paragraph says why: right after a merge the newest asset is often of
    the commit before, which is routine and must be told from a bad asset, so the commit is
    compared after the verify. Question 13, the tool paragraph and Risks say that after PR 15 a
    rotated root leaves only the bounded `gh` loop.
15. HANDOVER's limit command (host-fit). Fixed: it runs the token row's
    `gh api -i rate_limit | grep -i '^x-ratelimit-limit'`.
16. `AMENDMENT-1.md` (host-fit). Fixed in part: one line each defines place and lens, one says what
    a topic cannot select, and three passages are shorter. With this round's facts it is 164
    lines, about three pages.

### Verification round 3

23 findings (coverage 7, lean 9, host-fit 7; 2 major, 21 minor, none blocking), each checked
against the package and, for the Claude command limit, `code.claude.com/docs/en/tools-reference`
on 27 November. Two pairs are one defect each (items 3 and 14, items 7 and 19). Both majors are
fixed as the root ruled, and every minor that is a real defect is fixed in a few lines. No
statement is added or removed: 129 stay, and the counts by row stand (7a 19, 7b 25, 7c 27). One
statement's text changes (item 8), and it was already new in amendment 1.

1. A usage error of `wait` reached stderr only, so a Monitor never woke on a mistyped arm
   (coverage, major). Fixed: for `wait` only, one stdout line `watch: usage: <why>; next: <what>`,
   in the shape of the exit-1 line, comes before the usage text on stderr, and the wait exits 2
   (`WatchCli.waitUsage`, from `cli` for a flag that does not parse and from `wait` for a missing
   or bad `--as` and for flags that `flags?` or `Subscription.ofFlags?` refuse). `watch.sh`'s
   guarantees say the tool prints it and the shim passes the flags through. Row 2 of the exit table
   (`DESIGN.md`, `WatchCli`) has the line. Row 3 now says: a Monitor that ends with no stdout line
   while `status` shows no wait of that caller means run the same command once in the foreground
   and read stderr before re-arming. Row 13's caller rule and Risks say the same. Tests: row 9 and
   P2-023 add `wait --ride words` prints one stdout line and exits 2, and the exit-2 cases of
   `topics/` (Design block, row 8) each print it. `Render.lean`'s header lists the line, and
   `HANDOVER.md` says what exit 2 prints.
2. A second catch-all is never named by `status` (coverage). Taken as the second option: lens
   coverage item 7 above is corrected, and a Tradeoffs line and a sentence under `status` in
   `DESIGN.md` (and a Tradeoffs line in `AMENDMENT-1.md`) say a handler respawned without its
   flags shows only as a second `(catch-all)` tag, so whoever briefs it gives it flags. No new
   `status` line.
3. The kinds table was cut in two (coverage). Fixed: the paragraph is below the `alarms` row.
4. "Unchanged (86)" carried the row totals (coverage). Fixed in the rewrite (item 17): the row
   totals are a line of their own.
5. Question 10 and `--ride` replacing the default (coverage). Fixed: question 10 (`DESIGN.md`,
   `AMENDMENT-1.md`, owner decision 10) says `outside` already rides for every wait (default 6)
   and asks about `failed` and `alarms`. The `--ride` bullet says a list replaces the default, so
   name `outside` again. Row 13's rule, P2-020's owner decisions and the who-acts decision say the
   same. `HANDOVER.md` is unchanged: a PR owner names no `--ride`.
6. Seven of ten host checks run (coverage). Fixed in `AMENDMENT-1.md`'s profile summary.
7. Question 11 did not say the root misses the owner's Claude-app issue comments (coverage).
   Fixed: question 11 (`DESIGN.md`, `AMENDMENT-1.md`, owner decision 11) says the root's
   catch-all does not hear them unless its wait adds `peers`, that review-thread posts through the
   app still wake the root, and that a no makes every caller hear `peers`.
8. Report-level waking was named for typed words only (lean). Fixed by generalizing
   OwnerWordsWakeWhoeverHearsWords, which keeps its name and the count: its premise is now a post
   of kind `words` (`p.kind c.app = .words`) that is not quiet, so it covers typed words and an
   unrecorded review-route post, both of which may be the owner's. Proof plan: ANonQuietPostIsTold,
   OnlyChecksAlarmsAndOutsideRide and WhatIsToldPassesTheLens; typed words meet the post premises
   by TheSpeakerDecidesThePostKind and TypedWordsAreNeverQuiet. The finding's first option (any
   post that is not quiet, of any kind the caller hears) keeps the count too but would make the
   name wrong. `DESIGN.md`'s coverage decision, `Deliver.lean`'s header and the Design block say
   the same. Left as it is: an unreadable post (`refused`) has no named report-level waking
   statement; it follows from ARefusedItemIsTold, WhatIsToldPassesTheLens and `Rides.has`.
9. The 23 restated statements were named nowhere (lean). Fixed: the Design block's statements
   part has "Amendment 1's delta", which names the 20 new, the 3 removed and the 23 restated by
   module. A diff of the two sketches confirms it: 112 and 129 `def … : Prop`, 23 changed bodies.
   `AMENDMENT-1.md` and the Statements paragraph above point there.
10. The tested half of the trailer round trip had no test (lean). Fixed with the fixture:
    `parsedFlagsAreCanonical` in `Topic.lean` (what `ofFlags?` makes of `--topics failed --on
    502,571 --ride none` is canonical, and an empty `--topics` and an unsorted `--on` are refused).
    It is named in `TheTrailerFlagsReadBack`'s docstring, the Design block (the statement's gloss
    and the fixtures) and row 7a. No statement is added.
11. `Told.isNote` sat after 7b's cut (lean). Fixed: it is defined right after `Told`, above
    `facts`, so "up to `waking`" holds as written.
12. The Topic and Wake budgets leave little room (lean). No number is raised, as the root ruled: no
    sketch file passes its budget (Topic 293 of 320, Wake 330 of 400). The modules note now says
    the Architect's re-budget at the build-depth upgrade comes before the build, so these two get
    their numbers then and are not a deviation.
13. Render's fixtures and the `List Char` rule (lean). Fixed: the Lean lens line names the three
    String helpers they reach (`String.intercalate`, `String.join`, `String.ofList`), marks them
    unverified until PR 7c's elaboration, and gives the fallback: compare `List Char`, and call
    `String.ofList` only outside the fixture.
14. The kinds table (lean). As item 3.
15. The list of departures left out the changes to decision 1 (lean). Fixed: "Departures from
    the brief" above lists five, with the 30-second margin and `--max 7` among them. The root
    accepted the first three; the last two wait for its acceptance in PR 0b's body.
16. The `status` example showed a riding rule the format did not state (lean). Fixed: `status`'s
    docstring states it (`rides.items` filtered by `hears.has`, left out when empty), `DESIGN.md`
    says it under the example, and the `topics/` case (Design block, row 8) checks both forms.
17. `AMENDMENT-1.md` was over three pages (host-fit, major). Fixed: it is rewritten to 1,358 words
    (`wc -w`, code blocks included) and 135 lines. The statement list is counts per module with a
    pointer, Rejected is three bullets, "Tested, not stated" and the trailer example are gone, the
    Shape is plain sentences with no formula, and a four-line provider summary is added.
18. The Codex example had no time bound (host-fit). Fixed: each unmeasured host has a wrapper that
    meets the rule, all starting values: Codex `timeout 360` with `--max 4`, Cursor `timeout 590`
    with 7, Antigravity `timeout 420` with 5, in `DESIGN.md` (Usage, the provider table),
    `AMENDMENT-1.md` and `HANDOVER.md`'s host table. `HANDOVER.md` says to pick the bound first,
    then `--max`, and that a wait with no `--max` runs up to 27 minutes, so a shorter bound always
    stops it.
19. A catch-all root does not hear the owner's Claude-app issue comments (host-fit). As item 7.
    The other option is the existing "Q11 no" (every caller hears `peers`), now named in the
    question.
20. The pinned trusted root had no renewal procedure (host-fit). Fixed in question 13
    (`DESIGN.md`, `AMENDMENT-1.md`, owner decision 13), the tool paragraph and row 11: on a host
    that reaches the Sigstore hosts (the owner's device, or an environment where they allowed
    them), `gh attestation trusted-root > .github/attest/trusted_root.jsonl`, in a PR that changes
    only that file. It is under `.github/`, so it gets an `opus` verdict and the owner merges it;
    meanwhile the bash watcher or the bounded `gh` loop serves.
21. Two host rows have no single command, and the Claude command limit was incomplete (host-fit).
    Fixed: the profile's intro says seven rows have one read-only command, and time, wake and slug
    are the caller's own (time is arithmetic, wake has no command, slug needs a comment id). The
    page says 2 minutes by default and 10 at most, that `BASH_DEFAULT_TIMEOUT_MS` and
    `BASH_MAX_TIMEOUT_MS` change both, and that a command that reaches its timeout moves to the
    background with 30 minutes from the move. The Claude rows of `DESIGN.md` and `HANDOVER.md`
    say so, and that `timeout 590` inside the command is what ends a wait.
22. Little on each provider, and dense wording (host-fit). Fixed with item 17: the four-line
    provider summary and a Shape with no formula.
23. A sketch comment said question 3a "decides" (host-fit). Fixed in `pr-state-unanswered.sh`; the
    same tense in default 3c (`DESIGN.md`, the Design block) now reads "decided".

#### Final check

Two verifiers checked the revision above: 9 findings (fixes 6, lean 3), all minor, none blocking.
Two pairs are one defect each (items 2 and 7, items 4 and 9). Each was checked against the files.
Eight are fixed; item 6 was optional and is now recorded in P2-020. No statement is added, removed
or restated: 129 stay (a fresh count of `def … : Prop` in `sketch/`), and the row totals stand
(7a 19, 7b 25, 7c 27). `AMENDMENT-1.md` is 1,395 words (`wc -w`) and 137 lines.

1. Row 13's caller rules left out exit 2 (fixes). Fixed: row 13 names five rules. The new one is
   exit 2, a `watch: usage:` line: run the same command once in the foreground under `timeout 60`
   and read stderr, fix it, then re-arm. P2-027's checks and depth say five, and its Context names
   the fifth rule.
2. The foreground run of the exit-3 rule could be a full wait (fixes). Fixed with item 7's bound,
   not with `--max 0`: item 7 is right that `Invocation.next` prints `--max 0` back, so a copied
   probe trailer would re-arm a one-poll wait every time. The reviser's left-open item 1 is closed.
3. `HANDOVER.md`'s Claude row and its re-arm bullet (fixes). Fixed: the row says 2 minutes by
   default and 10 at most, and to pass the Bash `timeout` parameter of 600000 ms on every wait
   call. Round 3 item 21 said this row already did; it did not. The bullet says to run the `next:`
   text exactly with `timeout <bound>` in front, because the trailer does not print the bound.
   `DESIGN.md` (under the agents' example) and row 13's first rule say the same.
4. The row totals inside "Unchanged" in `502-watch.md` (fixes). Fixed as item 9.
5. `AMENDMENT-1.md` did not say what a topic cannot select (fixes). Fixed: one sentence in Usage
   says a topic selects only by kind and by issue or pull request number, never by label,
   milestone or app, and that whoever briefs an agent turns a milestone into numbers for `--on`.
6. No named waking statement for an unreadable post (fixes, optional). The sketch is unchanged: a
   new conjunct would restate a statement at contract depth for no gain the proof plan lacks.
   P2-020's Amendment 1 line now asks the Architect to decide on a `refused` conjunct at the
   build-depth upgrade, and says that today the waking follows from ARefusedItemIsTold,
   WhatIsToldPassesTheLens and `Rides.has`. Still open, minor.
7. The usage line said to run the fixed command in the foreground (lean). Fixed as proposed: the
   `waitUsage` string, exit rows 2 and 3 in `WatchCli.lean` and `DESIGN.md`, the Monitor risk and
   row 13 now say to run the same command once in the foreground under `timeout 60` and read
   stderr, then (for exit 2) fix it and re-arm. A sentence under `DESIGN.md`'s exit table says why
   (a broken command fails within seconds; a sound one prints a batch or is stopped with no line,
   which loses nothing) and not to probe with `--max 0`. 60 seconds fits Claude's 2-minute
   default, so no `timeout` parameter is needed.
8. A bad `--since`, and which flag `why` names (lean). Fixed: `wait`'s docstring lists a `--since`
   that `ofIso?` refuses among the usage errors, and `topics/` (Design block) and row 8 add
   `--since 2026-11-23`. `flags?` keeps its name and type. Its docstring says that on `none`,
   `wait` reads the three flags one at a time to name the flag, and that a refusal of `ofFlags?`
   is always `--ride`'s. The `Except String` option would either break the `?` naming rule
   (`?` returns `Option`) or rename `flags?` in six files, for the same effect.
9. "Unchanged ... By row" in `502-watch.md` (lean). Fixed: "Unchanged: the other 86." and "Row
   totals: …" are two bullets, and a line "The statements by module:" now stands between the delta
   list and the per-module list. Item 4's fix, removing the blank line, would have joined the two
   lists into one.
