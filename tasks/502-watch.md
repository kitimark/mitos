# tasks/502-watch.md (Design block)

This is the task file that PR 0 adds as `tasks/502-watch.md`, shaped by `tasks/TEMPLATE.md`. PR 0
also commits the rest of this package under `tasks/502-watch/` (`DESIGN.md`, `PR-SEQUENCE.md`,
`HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`), so a builder in a fresh clone has it. Each later
PR's own task file (also from PR 0) names its slice of `modules` and `statements` by PR number
from `PR-SEQUENCE.md` and the path of the package. It does not restate them.

phase: tracker #502. PR 0 adds one row and one issue per PR in `PR-SEQUENCE.md` (except PR 1, PR 3a and PR 3b, which start now) to the current `plan/phase-N.md`: rows P2-013 to P2-029 in `plan/phase-2.md` (section "Watch track (#502, milestone 6)"), issues #562 to #578 in milestone 6
goal: Every consumer of the clone (the root, a PR owner, Codex) waits on GitHub through one Lean tool. Each sees every change meant for it once, and nobody's words or writes hide another's.
statement: none locked (tooling task). Named statements live in `gate/MitosGate/Watch/` and are audited in `gate/MitosGate/Watch.lean`.
touches: gate/MitosGate/Watch/*.lean, gate/MitosGate/Watch.lean, gate/MitosGate/WatchCli.lean, gate/Main.lean (one import, one usage block, one arm), gate/watch-test.sh, gate/watch-fixtures/, gate/watch-fetch.sh, .claude/scripts/watch.sh, .claude/scripts/watch.test.sh, .claude/scripts/watch-diff.test.sh, .claude/scripts/watch-diff.intended, .claude/scripts/watch-github.sh and its test (PR 1 only, then deleted in PR 15), .claude/scripts/watch-own.sh (deleted in PR 15), .claude/hooks/pr-state.sh and its test, .claude/scripts/gh-api-rest.test.sh, .claude/scripts/sourced-bash.test.sh (PR 9 and PR 15), .claude/scripts/main-tool.test.sh, the Watchers text in .claude/skills/kitimark-mode/SKILL.md and .agents/skills/kitimark-mode/SKILL.md, the four waiting playbooks in both poteto-mode/playbooks copies and .claude/README.md (PR 13), .agents/scripts/agents-roster.tsv (stamps), docs/process.md (check matrix, the gh-only row and the waiting rows), plan/phase-N.md, tasks/502-watch.md, tasks/502-watch/ and the row task files (PR 0 only), the bootstrap files of question 3a (PR 11), and for PR 3c only (question 8b yes) gate/MitosGate/Snapshot/Types.lean, gate/MitosGate/Snapshot/Fields.lean, gate/MitosGate/Snapshot/Obs.lean, gate/MitosGate/Snapshot/Fixtures.lean, the review-comment reader in gate/MitosGate/SnapshotCli.lean and gate/snapshot-test.sh; ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, gate/MitosGate/{Speech,Shadow,Accept,CheatsRun,DecideList,Util,Base,Snapshot*}.lean and every other existing gate module (imported, never moved or edited; PR 3c's Snapshot set above is the one exception), .github/ (except PR 11, whose route the owner chooses)
checks: build, imports, lock, lint-test, gate-tests (gate/watch-test.sh), cheats (locally for every row that touches gate/, as the check matrix asks, and in CI), plan-tasks (PR 0), the script tests each PR names
budget: per PR, in the budget table under Design. Estimates from the unelaborated sketch, about 29M builder tokens for the Lean rows; the Architect re-budgets each row when it upgrades it to build depth. Script and rules PRs 20 iterations · 2h wall · 1M tokens each; PR 12 is its own A/B budget (owner question 2c)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written into this file and goes to the owner; the implementation is not bent to fit)

## Context
- Issue #502 (the daemon question and its five calls), #501 (a typed owner comment that quotes the
  footer is dropped), #336 (Codex and the root cannot hear each other), #224 and #239 (echo lines),
  #84 (no-run history), #38 (stays open).
- Design package, in `tasks/502-watch/` after PR 0: `DESIGN.md` (rationale and owner questions),
  `PR-SEQUENCE.md`, `sketch/` (unchecked Lean at repository paths, plus the tested PR 1 and PR 3a
  diffs), `HANDOVER.md` (brief for an outside agent), `REVIEW-LOG.md` (review rounds 1 and 2;
  round 3 is at the end of `DESIGN.md`).

## Design
depth: contract only for the Lean rows (PRs 2, 3c, 4, 5, 6, 7a, 7b, 7c, 8): their inputs, outputs and statements are fixed here, but the `sketch/` was never elaborated (the design ran with no Lean toolchain) and 34 bodies are stubs, `report`, `View.of`, `ciHealth`, `Shared.nextAges` and the readers among them. Build for PR 1 and PR 3a, whose diffs ran against `main` at `7dfd6cb`. PR 0's issues for the Lean rows say "contract only". Before a Lean row's PR owner starts, the Architect type-checks that row's slice of the sketch with the repository's toolchain, writes the stubs its statements are stated over, checks those statements against the written bodies, and upgrades the row's task file to build depth (`kitimark-mode`, Plan-time designs). For PR 2 this is its first step.
revisit_when: each Lean row: re-check after the row it depends on merges (the upgrade to build depth above). Re-check `Observe` and `Time.ofHttpDate?` after PR 4's live read confirms `pull_request.merged_at` on the issues route, the absent app key on both review routes, and the `Date` header framing that `gh api --include` returns for `branches/main`. Re-check `nextMove`'s constants after PR 12's A/B. Re-check `Voice` after the owner answers questions 8a and 8b, or refuses default 8c on PR 0.

### modules

| File | The one topic it owns | Budget (code and proofs) | Layout copies |
|---|---|---|---|
| `gate/MitosGate/Watch/KeyMap.lean` | a keyed map as an association list, and the delta between two | 200 | `DecideList.lean` |
| `gate/MitosGate/Watch/Time.lean` | epoch seconds, the one ISO form (`isoChars`, `ofIso?`) and GitHub's `Date` value (`ofHttpDate?`), all over `List Char` | 220 | `Shadow/Types.lean` |
| `gate/MitosGate/Watch/Route.lean` | the closed set of REST reads, their argv, the per-poll bound, the poll plan (`clock`, `fixed`, `perHead`) | 200 | `Carry.lean` |
| `gate/MitosGate/Watch/Voice.lean` | who spoke in a post; `pr-state`'s unanswered rule (land's classes plus #501) | 420 | `Speech/Comment.lean` |
| `gate/MitosGate/Watch/Observe.lean` | one JSON reader per route, refused items (`Refused`, `Reading`); `Names`; `Fixed` with GitHub's time; `Plan.heads` | 460 | `SnapshotCli` readers |
| `gate/MitosGate/Watch/View.lean` | the level view, checks, `ci` health, the second look (`Plan.due`) | 560 | `Snapshot/Fields.lean` |
| `gate/MitosGate/Watch/Feed.lean` | posts, closes and refused items keyed by GitHub time, poll-numbered, pruned; the cursor and the floor | 360 | `Carry.lean` |
| `gate/MitosGate/Watch/Shared.lean` | the clone's one observation, its decidable invariant, one poll's step, head ages | 360 | `Snapshot/Obs.lean` |
| `gate/MitosGate/Watch/Wake.lean` | identity, quiet posts, echoes of one's writes, which changes wake, scope, tiers | 360 | `Land` wake plus `Carry.lean` |
| `gate/MitosGate/Watch/Deliver.lean` | the report, offer and ack (PR 7b); the cut, `Moment.of`, `nextMove`, `finish` (PR 7c) | 900 | `LandAnswer`, `CheatsSlot` |
| `gate/MitosGate/Watch/Render.lean` | the text of every line and the next command | 220 | `Util.oneLine` |
| `gate/MitosGate/Watch/Gh.lean` | the one `gh` process: bounded, stdin closed, both pipes as bytes (PR 8); the pure `Date` header framing `frame` (PR 4) | 140 | `CheatsRun.runChild` (copied) |
| `gate/MitosGate/Watch/Store.lean` | the state files: version, codecs and on-load checks, lease, the consumer lock, claim, records, quarantine, housekeeping | 380 | `Accept.writeByRename` |
| `gate/MitosGate/WatchCli.lean` | `watch wait / own / status / unanswered`, and the test-only `read` (PR 4) and `replay` (PR 6) | 460 | `SpeechCli.lean` |
| `gate/MitosGate/Watch.lean` | imports of the pure modules and their axiom audit | 60 | `Snapshot.lean` |
| `.claude/scripts/watch.sh` | find clone, repo, owner and main's tool; exec the tool | 100 | `watch-own.sh` |

That is about 5,350 lines of Lean, code and proofs. The unchecked sketch is 2,736 lines with 34
stub bodies and no proofs, and gate modules with proofs of this kind (`Snapshot/Obs.lean`,
`Yaml/View.lean`) run several hundred lines of proof each, so the budgets are for writing the
bodies and the proofs, not for new topics. Planned splits, each along a topic already in this map,
so a build that crosses a budget splits as planned instead of reporting a deviation:
- `Deliver.lean` into `Deliver/Report.lean` (the report, offer and ack, what is told) and
  `Deliver/Move.lean` (the cut, `Moment`, `nextMove`), when it passes 600 lines.
- `Observe.lean` into `Observe/Posts.lean` (the post and close readers, `Refused`, `Reading`) and
  `Observe/Pulls.lean` (pulls, runs, checks, `Names`, `Plan.heads`), when it passes 300.
- `View.lean` into `View.lean` and `View/Health.lean` (`ciHealth`, the alarms and their
  statements), when it passes 400.
Any other growth is reported as a deviation. The Architect re-budgets each file when it upgrades
its row to build depth. PR 7b and PR 7c each write part of `Deliver.lean`, as PR 2 and PR 4 each
write part of `Time.lean` and `Observe.lean`. `watch-github.sh` (395), `watch-own.sh` (25), their tests and pr-state's
two jq classifiers go in PR 15 and PR 3.

### budget

`docs/process.md` makes a row's budget a hard stop: when it runs out, the PR owner writes a stuck
report and stops. These numbers are estimates from a sketch that was never elaborated, scaled from
`docs/process.md`'s sample record (31 iterations, 74 minutes, 1.18M tokens: about 40k tokens and
2 to 3 minutes per iteration) at about 20 iterations a row, 4 per statement and 20 more per
EXPENSIVE proof. The Architect re-budgets each row at its build-depth upgrade.

| PR | Statements (EXPENSIVE) | Bodies to write | Budget |
|---|---|---|---|
| 2 | 8 | three post readers, `unanswered` | 50 iterations · 3h wall · 2M tokens |
| 3c | 2 restated, every Snapshot proof re-checked | the place on `Post` | 60 · 3h · 2.5M |
| 4 | 7 (1) | the other readers, `frame`, `watch read` | 70 · 4h · 3M |
| 5 | 19 | `View.of`, `ciHealth`, `Checks.of` | 100 · 5h · 4M |
| 6 | 24 | `nextAges`, `watch replay` | 110 · 6h · 4.5M |
| 7a | 13 | none | 70 · 4h · 3M |
| 7b | 17 (2) | `report` | 130 · 7h · 5M |
| 7c | 24 | `Item.line` | 120 · 6h · 4.5M |
| 8 | none; the fault cases | `Gh`, `Store`, `WatchCli` | 80 · 4h · 3M |

The Lean rows without PR 3c come to about 29M builder tokens, before the Architect's upgrades and
the verifiers.

### types

```
Repo := {owner name : String, ok : SafeSegment owner ∧ SafeSegment name}   -- SafeSegment is an abbrev, so decidable
Sha40 := {text : String, ok : Speech.isSha text.toList}
OwnedHead owner := {pr, login, sha : Sha40, mine : login = owner}         -- only OwnedHead.of? makes one
Route owner := runs | openPulls | closedSince t | main | issueCommentsSince t | reviewCommentsSince t
             | checks h | reviews h | runsAt h                            -- h : OwnedHead owner
Gh.Answer := {date : Option Epoch, json : Json}   -- date only from `main`, read with --include
Place := issueComment | reviewComment | review
Via := absent | none | app slug        -- absent: the route has no app key (both review routes)
Speaker := typed | app slug | untold   -- typed only for an issue comment whose key is null
Said := {place, id, thread, login, via, created, updated, state, body}  -- raw, for pr-state
Excerpt := {text, ok : ∀ c ∈ text, printable c}                        -- Excerpt.of b := oneLine (squeeze 120 b)
Post := {place, id, thread, speaker, created, updated, state, excerpt : Excerpt}
ItemKind := post place | close
Refused := {kind, id, thread : Option Pr, why : Excerpt}   -- an item a post or close reader could not read
Reading α := {items : List α, refused : List Refused}       -- what a post or close reader gives
KeyMap α β := List (α × β);  Delta := {key, before after : Option β}
Names := sorted, no repeats (DecideList.sortStrings)
Fixed := {serverNow, runs, pulls, closed, main, posts, refused}   -- serverNow from GitHub's Date header
PullFacts := {author : own | outside, labels assignees : Names}
Run := pending | done conclusion;  Checks := {gate prove scorecard coderabbit : Option Run}
HeadFacts := {sha, checks};  HeadRoute := checks | reviews | look
Health := noRun pr sha | queued run | stale run | rabbitSkipped pr sha | unread pr sha route
HeadAge := {firstSeen, look : notAsked | noRunFound | runFound, misses : KeyMap HeadRoute Nat}
View := {pulls : KeyMap Pr PullFacts, heads : KeyMap Pr HeadFacts, health : KeyMap Health Epoch}
Change := pull (Delta Pr PullFacts) | head (Delta Pr HeadFacts) | health (Delta Health Epoch)
EntryKey := post place id updated | close pr closedAt | refused kind id
Fact := post Post | closed ClosedPull | refused Refused seen
Feed := {entries : List {fact, poll}, cursor : Option Epoch (GitHub time), prunedPoll}
        overlap = 3600, keep = 86400, slack = 60;  floor = cursor - keep
Shared := {repo, owner, gen, polls, view, feed, main, ages, lastTry, lastOk, failStreak, lastError}
                                                -- each state file also carries "version" (Store.version = 1)
Consumer := {app, name, scope : repo | pulls ns}
PostRecord := {place, id}  (per class);  WriteRecord := {gen, afterPoll, seq, write}  (per consumer;
        seq orders the writes of one poll interval)
Mark := {gen, view, feed : since t | after poll, toldDown};  Mark.fits s := gen = s.gen ∧ poll ≤ s.polls
Pending := nothing | offered number mark repeats;  ConsumerState := {acked, pending, offers}
        ConsumerState.fresh acked base   -- base: a random six-digit number Store draws
Item := change | post | closed | gone pr author | refused | note (reset | gap | down | up | redelivering)
Told := {item, tier : words | owned | outside, wakes};  Batch := {shown, more}
Moment := {now, started, deadline, lastTry, lastOk, failStreak, waking, words, told, firstWake, leaseBusy}
Move := deliver | poll | sleep ms | quiet | blind
Store.Read α := ok α | absent | newer      -- newer: a later state version, exit 1, not set aside
```

The stale-tool line is not an `Item`: `Render.batchLines` appends it from `--tool-note`, so it
never enters the report, the cut or the offer; at a quiet or blind end it goes to stderr.

Signatures that carry the design:

```
ofHttpDate?     : List Char → Option Epoch                    -- Gh strips each header line's CR first
issueComments, reviewComments, reviews : (owner : String) → Json → Except String (Reading Said)
closedPulls     : (owner : String) → Json → Except String (Reading ClosedPull)
Shared.step     : Rules → (owner : String) → Shared → Poll owner → Shared
Shared.checked? : Shared → Option {s : Shared // s.Inv}        -- every load goes through it
Shared.nextAges : (now : Epoch) → KeyMap (Pr × String) HeadAge → Fixed → List (HeadRead owner) → KeyMap ..
ciHealth        : Rules → (now : Epoch) → Fixed → KeyMap (Pr × String) HeadAge → List Health
                  -- noRun on the local clock, queued on fixed.serverNow, stale on none
Feed.sinceAt    : (serverNow : Epoch) → Feed → Epoch
Feed.add        : (poll : Nat) → (serverNow : Epoch) → List Fact → Feed → Feed   -- a lost window sets prunedPoll
Mark.fresh      : (gen : String) → (since : Epoch) → Mark      -- since = --since, or Feed.floor
report          : OutsidePolicy → Consumer → Records → (acked : Mark) → Pending → Shared → List Told
waking          : OutsidePolicy → Consumer → Records → Mark → Pending → Shared → Bool
ConsumerState.ack   : ConsumerState → (seen : Option Nat) → ConsumerState   -- takes only the exact number
ConsumerState.offer : ConsumerState → Shared → ConsumerState
finish          : OutsidePolicy → Consumer → Records → (cap : Nat) → ConsumerState → Shared
                  → Batch × ConsumerState   -- the batch and the offer from one shared state
cut             : (cap : Nat) → List Told → Batch               -- words and notes, then heads, owned, outside
Moment.of       : (now started deadline : Epoch) → Shared → (report : List Told) → (waking : Bool)
                  → (firstWake : Option Epoch) → (leaseBusy : Bool) → Moment
nextMove        : Moment → Move                                 -- at the deadline a non-empty report delivers
unanswered      : (owner : String) → (apps : List String) → List Said → List (Pr × List Nat)
                  -- apps = Voice.answerApps, the slugs of Speech.apps
```

### statements

Each one is written `def Name : Prop` with `theorem name : Name` beside it, as in `gate/`. They are
marked **EXPENSIVE** (a long proof; its proof plan and fallback are named) or *moderate* (a page of
tactic work). The rest are short. There are 112; `Watch.lean`'s audit finds every one and fails the
build when one has no theorem. Every statement is written outside any `variable` section, so its
type is exactly `Prop` and the audit sees it.

- `Watch/KeyMap.lean`: DiffNamesEveryChange, DiffNamesOnlyChanges, DiffSelf, DiffOnePerKey
  (needs `WF` of both maps), DiffSeesOnlyLookups, SetKeepsWF. None needs a key order.
- `Watch/Time.lean`: **IsoReadsBack** (for `e < 4102444800`, EXPENSIVE: Hinnant's inverse. It is
  the one statement whose fallback is weaker: a run-time round-trip check in `WatchCli` before any
  `since=`, plus the fixtures. Taking the fallback deletes the `def`, since the audit fails on a
  statement with no theorem, so it is a deviation the PR body records, not a free choice).
- `Watch/Route.lean`: OnlyRestReads (`gh api` and read-only flags only; that `--include` goes only
  on `main` follows from `Route.headers`'s definition, not from this statement), *SegmentsAreSafe*,
  PollCallsBounded (at most 6 + 3 per owned head, counted as processes; PR 12 counts requests).
- `Watch/Voice.lean`: TypedOnlyFromAnIssueCommentWithNoApp, ReviewRoutesAreNeverTyped,
  TypedIsAlwaysWords, AnAppPostIsNeverWords, SpeaksAsLandUnlessTyped, AnswersAsLandUnlessTyped,
  *TypedWordsAreListedUntilAnswered*, ExcerptIsOneLine (stated with `printable`).
- `Watch/Observe.lean`: *NamesOfIgnoresOrderAndRepeats* (needs `String.lt` to be a strict total
  order), HeadsComeFromOpenPulls, OutsidePullsAreNeverRead (stated over `Plan.perHead` of
  `Plan.heads`: every per-head route names an open pull of the owner's login at that head). The
  readers are tested, not proved, because `Json.parse` is `partial` and `TreeMap.Raw` lemmas need a
  WF hypothesis.
- `Watch/View.lean`: OfIsWF, HeadsAreOpenOwnedPulls, PullsAreTheOpenPullsRead (the positive half:
  the pulls read, less those the same poll closed), *PrevReachesOnlyUnreadHeadsAndStarts*,
  UnreadHeadKeepsItsFacts (for a `HeadRead.alone` failure), ReadHeadShowsItsChecks,
  *AReReadMovesOnlyHealth* (the same facts read later move only the alarms), and the five alarms,
  each stated both ways on `(View.of …).health`: NoRunNeedsTheSecondLook,
  RabbitAlarmNeedsTheOwnerAssigned, StaleNeedsAnUnfinishedRunOffEveryHead,
  QueuedIsMeasuredOnGitHubsClock, AFailingHeadReadIsTold (`unread` per route: checks, reviews,
  second look); and ASuspectedHeadGetsTheSecondLook.
- `Watch/Feed.lean`: *AddKeepsEachKeyOnce*, ARereadFactKeepsItsPoll, AddKeepsTheWindow,
  CursorNeverGoesBack (within `slack`), CursorNeverPassesGitHubNow, ANewFeedAsksForADay,
  AfterIsOnlyNewer, *ANewFactIsAfterEveryOlderMark*, *TheSameFactsTwiceAddNothing* (`add` dedupes
  against the entries it keeps; round 3's counterexample is a fixture), AddKeepsPollsBelow,
  AnUnpolledDayIsAGap.
- `Watch/Shared.lean`: StartHasInv, FailedPollKeepsTheView, FailuresCount, PollsCountSuccesses,
  StepKeepsTheGeneration, *StepKeepsInv*, TheFeedIgnoresTheLocalClock, OnlyTheOwnersPostsAreKept
  (empty `COMMENTED` reviews are not posts), MissesCountFailedReads, NoRunFoundNeedsASuccessfulLook,
  AFailedLookMovesNothing (when the runs page shows no run at that sha), ARunOnThePageIsFound (so a
  late run that scrolls off the page raises no `noRun`), AReReadAddsNoPostOrClose (the same facts
  at the same or a later `Date` add no post or close; only a refused item pruned a day after it
  was told comes back).
- `Watch/Wake.lean`: TypedWordsAreNeverQuiet, QuietNeedsTheClassOrARecord, AnotherClassIsHeard,
  UntoldIsHeardUnlessRecorded, QuietIgnoresTheText, FinishedCheckWakes, OnlyPendingIsQuiet,
  *EchoAddsOnlyWhatWasWritten*, *EchoDropsOnlyWhatWasWritten*, NoLiveWriteNoEcho,
  ARecordIsSpentTwoPollsLater, ARecordOfAnotherGenerationIsDead, OnlyAMergeExplainsAMerge.
- `Watch/Deliver.lean` (PR 7b proves the first two groups but CopiedTrailerNeverSpins; PR 7c the
  rest):
  - offer and ack: AckOnlyTakesTheOffer, AckNeedsTheNumber (every other number is ignored),
    AnUntakenOfferIsReplayed, **NoNewsStaysQuiet** (EXPENSIVE: it unfolds `report`. A state with no
    news for a mark (`Shared.noNewsSince`: it fits, the view has the same lookups, no later feed
    entry, no gap, the same down flag) gives an empty report. Proof plan, not a weaker statement:
    the change, feed and note parts separately, then `List.append_eq_nil`), and three short ones
    from it: AnAckedOfferHasNothingNew (under `Shared.Inv`), IgnoredTrailerReplaysOnce and
    CopiedTrailerNeverSpins (both over any number of polls with no news, not only before the first;
    the second names `nextMove`, so PR 7c proves it). Both hold only for a caller that runs the
    text after `next: ` exactly, which PR 13 writes into the rules. OfferMarksTheReportedState
    (PR 7c): `finish` makes the batch and the offer from one consumer state and one shared state.
  - what is told: TypedWordsAreTold, ANonQuietPostIsTold, **EveryNotableChangeIsTold**
    (EXPENSIVE: it follows a change through scope, echo and the close merge, and covers `change`,
    `closed` and `gone`, each with its own wake: a close wakes as its author, `gone` as the pull's.
    Proof plan: split by `Change` constructor, then by whether the feed holds a new close),
    ANewCloseIsToldUnlessItsWriterRecordedIt, OneItemPerClose, ARefusedItemIsTold,
    AScopedConsumerHearsOnlyItsPulls, GapIsNeverSilent, ResetIsNeverSilent (another generation, or
    a mark ahead of the state), AFreshConsumerHearsFinishedChecks (and they wake),
    AFailingGitHubIsTold. All of them take `acked.fits s` where they used to take the same
    generation.
  - the cut: WordsAreNeverCut, NotesAreNeverCut, OutsideIsCutFirst (its witness is not a head line:
    `cut` ranks every head line first, whatever its tier), ChecksAreCutLast, TheCutCountsEveryLine.
  - `nextMove`: OnlyPossibleOwnerWordsSkipTheWindow (a waking post no app names, or a post a reader
    could not read; an app's post waits the window), OwnerWordsAreNotHeld, WakeIsDelivered,
    NeverEarlyEmpty (now also: the report is empty), QuietEndAcksNothingUnshown, EndsWithinOneBudget
    (the decision at a moment one budget past the deadline is to end; a poll in flight is bounded
    by `Gh`'s timeout, tested in PR 8, not proved), QuietOnlyAfterAFreshRead and
    BlindOnlyWithoutAFreshRead (fresh: a success within `interval + pollBudget + freshSlack` of
    `min now deadline`, and a failure streak below `downAfter`), AHealthyWaitNeverEndsBlind,
    TheFirstPollIsAlwaysTried, ABusyLeaseNeverPolls, NoPollPastTheBudget,
    CoalescingNeverPassesOneWindow.
- `Watch/Render.lean`: *EveryLineIsOneLine* (batch, quiet and blind lines, with `printable`),
  OwnerWordsNameTheirId, OnlyTypedWordsAreCalledTheOwners, TheLastLineIsTheNextCommand (all three
  ends).
- Tested, not proved: the readers in `Observe` (refusal at both levels, through `watch read` from
  PR 4), `Time.ofHttpDate?` beyond its fixtures, the header framing `Gh.frame`, the `gh` timeout
  that bounds a poll in flight, the codecs, on-load checks, quarantine and housekeeping in `Store`,
  the lease re-read and unique poll numbers (PR 8's `lease-race`), the consumer lock around every
  `state.json` write, and `WatchCli`.

Lean lens fixes this list carries:
- No ordering claim needs `List.mergeSort`. Maps compare by lookup (`Equiv`) and are WF by `Nodup`.
- Anything a `decide +kernel` fixture evaluates avoids `String.splitOn`, `String.toNat?`,
  `String.all` and `toString` (taken to run through loops the kernel does not reduce, unverified
  until PR 2's elaboration) and works on `List Char` with `Base.Text` and `Nat.toDigits`, as
  `Speech.stamp?` does. `String` appends are fine: `Snapshot/Fixtures.lean` proves fixtures over
  `"Why." ++ footer` by `decide +kernel` on v4.35.0. `native_decide` is not a way out: the audit refuses `Lean.ofReduceBool`.
- Codecs make no proof claim, because `Json` is `partial`. What a proof needs of loaded state is
  checked on load (`Shared.checked?`, `View.WF` of each mark, canonical `Names`,
  `Excerpt.ofStored?`); a file that fails is quarantined.
- Files and both `gh` pipes are read as bytes, then `fromUTF8?`.
- `Shadow.days` and `Speech.stamp?` are reused, not moved.
- Decide fixtures use `DecideList.sortStrings` or a local insertion sort.
- `WatchCli` imports `MitosGate.Watch`, so the audit is in the build; `gate/watch-test.sh` checks
  that `Watch.olean` exists after `lake build mitos-gate`.

### reuse

- `Speech.stamp?` and `Shadow.Stamp.seconds`, for time.
- `Base.Text` (`split`, `parseNat`), for every text a fixture evaluates.
- `Speech.footer`, `Speech.apps` and the classes of `Snapshot.speaks` and `Snapshot.answers`, for
  Voice.
- `Util.oneLine`, `printable` and `oneLine_printable`, for excerpts and lines.
- `Util.ciLine`, for refusals.
- `DecideList.sortStrings`, for `Names`.
- `Speech.isSha`, for `Sha40`.
- `Land (Pr)`.
- `Accept.writeByRename`, imported.
- The `CheatsRun.runChild` pattern, copied into `Gh` because that function runs its command in a
  namespace.
- The `SnapshotCli` reader pattern, and the `SpeechCli.parse` shape for each subcommand's flags.
- The `Snapshot.lean` axiom audit pattern, with the lists found rather than written by hand.
- `.claude/scripts/lib/main-tool.sh` (`main_tool ready`, `main_tool_bin`, `main_tool_dir`) and
  `lib/origin-repo.sh`.

### fixtures

Decide fixtures, in the `Fixture` namespace of their module, are audited:
- `Time`: `isoNow`, `isoEpoch`, `isoLeapDay` (on `isoChars`), `readNow`, `readRefusesMillis`,
  `httpDateNow`, `httpDateRefusesAnotherZone` (on `List Char`).
- `Voice`: `quotedFooterIsStillTyped`, `quotedFooterIsWordsForPrState`,
  `codexWithTheFooterAnswers`, `codexWithoutTheFooterIsNeither`, `claudeWithoutTheFooterAnswers`,
  `reviewReplyIsUntold`, `reviewReplyWithFooterAnswersForPrState`,
  `anEmptyCommentedReviewDoesNotCount`, `quotedWordsStayUnanswered` (with a newer Codex post in the
  same thread that is neither words nor an answer).
- `Observe`: `namesKeepACommaInsideAName` (#239).
- `View` (written in PR 5 against the written `View.of`):
  - `scorecardPrefersARunThatDidNotSkip`
  - `newestRunDecidesTheCheck`
  - `rabbitSkippedOnlyWhileAssigned`
  - `aPullClosedBetweenTwoReadsLeavesTheView`
  - `aReviewsReadFailingFivePollsIsUnread`
  - `aFastLocalClockQueuesNothing`
  - `aReReadAnHourLaterChangesNoPullOrHead`
- `Feed`:
  - `anEditIsANewEntry`
  - `sixtyClosesInAGapAreAllKept`, the case the bash watcher's 50-cap loses
  - `aLateListedPostLandsAfterAnOlderMark`
  - `theFirstPollAsksADayBackOnGitHubsClock`
  - `aDayWithNoPollIsAGap`: 30 hours with no poll; the post in between is dropped and an older
    mark hears a gap
  - `aRefusedItemPrunedAndRelistedIsAddedOnce`: round 3's counterexample (in the sketch)
- `Shared`: `anEmptyCommentedReviewIsNotAPost`, `aFailedLookLeavesTheSecondLook`.
- `Wake`:
  - `echo224` and `echo239`: the recorded label and assignee writes of those issues are quiet for
    the writer and loud for the other consumer
  - `codexWakesTheRoot`, `claudeReplyIsQuietForTheRoot` and `rootCatchUpWakesCodex` (#501, #336)
  - `recordedReviewReplyIsQuiet` and `unrecordedReviewReplyWakes`
  - `aWriteThenTenQuietMinutesStillExplainsItsEcho`: no poll means no spend
  - `aFinishedCheckOnANewHeadWakes`, the merge-ready case that `pushed` absorption lost
  - `unassignThenAssignInOnePollIsQuiet`: the re-ping's two records of one poll, applied in `seq`
    order, explain the change
- `Deliver`:
  - `aMissingSeenReplaysOnce`
  - `copiedTrailerBlocks`, and `copiedTrailerBlocksAcrossARereadPoll`
  - `aStaleSeenIsIgnored`: a number that is not the pending offer acks nothing
  - `aGapSaysSo`
  - `aMarkAheadOfTheStateResets`
  - `aFreshPrOwnerHearsItsGreenGate`
  - `ownMergeReadInOnePollIsQuiet`: the root's recorded merge, with the pull and its close read in
    the same poll, tells the root nothing
  - `ownerWordsSkipTheWindow`, `untoldWordsSkipTheWindow` (a review-route post no app names and no
    one recorded), `anAgentAppPostWaitsForTheWindow`
  - `anOutsidePullRidesToTheDeadline`, `nothingToldEndsQuiet` and
    `aHealthyWaitAtTheDeadlineEndsQuiet` (round 3's moment; all three in the sketch)

File fixtures in `gate/watch-fixtures/`, run by `gate/watch-test.sh` (through the test-only
`watch read` and `watch replay` until `wait` exists):
- `routes/`: one live-captured answer per route, taken by `gate/watch-fetch.sh` (read only) in
  PR 4, read through `watch read`, plus edited copies:
  - an issue comment page with one owner item without the app key among good ones: the good ones
    are read, the bad one is a `Refused` item, and the poll applies
  - the same item from another login: dropped, not refused
  - a review comment with an app key, which is read as absent
  - a page that is not UTF-8, and a `total_count` that does not match its pages (the whole answer
    is refused and the poll fails, naming the route)
  - a `main` answer captured with `--include`, CR bytes kept, and one without a `Date` header
- `posts-336/`: the public posts of #336 (typed, Claude-app and Codex-app, with and without the
  footer), plus edited copies that add one post of each class `Voice.lean` lists, replayed through
  `watch unanswered`, with `expected.json` and `classes.tsv`. It must match the jq classifiers
  except on the ids listed in `classes.tsv`, each with its class from `Voice.lean`.
- `history-84/` (PR 6, where `nextAges` and `Shared.step` exist, through `watch replay`): the runs
  and heads of #84 as poll sequences. A `noRun` line needs the second look, every head that met
  the condition has one, and a head with no run, then a late run, then that run scrolled off the
  runs page raises no `noRun`.
- `state/`: one `observed.json` and one `state.json` per Store case:
  - a good file that round-trips
  - a truncated file
  - a non-UTF-8 file
  - a stored excerpt holding a newline, which must be quarantined
  - a file of another repository, which reads as bad
  - a state that fails `Shared.checked?` (a repeated feed key), which must be quarantined
  - a file of a newer version, which exits 1 and is left in place
  - a `state.json` whose acked poll is above `observed.json`'s poll count: a reset line
- `faults/`: deterministic fault injection with no timing races:
  - a fixed clock (`--now`)
  - a fake `gh` that blocks on a fifo until the test writes to it (lease busy, a supersede while
    polling, `lease-race`)
  - named exit points (`--test-exit after-offer|in-lease|after-claim`, refused unless
    `MITOS_WATCH_TEST=1`)
  - a fake `gh` that prints a token on stderr and exits 1: no stdout line, state file or log
    may contain the token
  - a state folder that turns read-only mid-wait: one stdout `cannot run` line, exit 1

### cut_line

The program ships PRs 0 to 10 (3c only on question 8b yes), PR 11 and PR 13 from
`PR-SEQUENCE.md`. PR 13 switches the rules only after PR 11 (main's tool runs where the root runs)
and PR 12 (canary and A/B) are in, so until then the bash watcher, with PR 1's fix, stays the
root's watcher and `watch.sh` serves PR owners wherever main's tool is built. PR 15 deletes the
bash watcher only after its gates hold and the owner signs it off. PR 14 (lifting the
background-shell ban) ships only if PR 12's numbers and the owner say so.

### deferrals

- Conditional requests (ETag, `If-None-Match`) to cut REST cost. Deferred to a follow-up after
  PR 12 measures the REST use of the shared poll. It moves from no row to a new follow-up issue.
- Refusals that still fail the poll: a whole answer of the wrong shape, an item with no `id`, and
  any open-pull or run item the reader cannot read. Each lasts until the answer changes or the tool
  is fixed, and every consumer hears it (`DESIGN.md`, Tradeoffs). Post and close items no longer
  fail the poll: they are `Refused` items, built in PR 4 and told in PR 7b.
- Facts that GitHub lists more than one hour after their time are lost (the `overlap`). PR 12
  counts how late facts are listed; a larger overlap is a follow-up only if that number calls for
  it.
- The bash watcher's first-poll scan of every open thread is not carried over. A new consumer
  hears the feed's last day (or from `--since`, with a gap line when that is older); owner words
  older than the feed come from pr-state's unanswered column, which the root reads at session
  start (PR 13), and `watch-diff.intended` lists the difference (PR 10).
- One owner default shared by `watch.sh`, `watch-github.sh` and `pr-state.sh` (today
  `MITOS_OWNER` and `WATCH_OWNER`). A follow-up issue, not part of PR 9.
- The Actions event log (#502 call 4). Not built, as #502 already decided.
- A recording hook that records every agent post id at write time, so review-route replies are
  quiet without a manual `watch.sh own`. It follows default 5b.
- An hourly digest of outside-account events. Default 6 takes ride-along instead; a digest is a
  follow-up only if the owner asks for one.
- A resident watcher agent. It is rejected for now (`DESIGN.md`, Alternatives) and returns only
  if owner question 1 is answered no.
- #38 stays open, and nothing here closes it. #501 is closed by PR 1 and PR 3a, and made
  structural by PR 3 and PR 13.
- Round 3's minor findings that are more than one line, each in the row that takes it:
  - PR 7c: an owned close or `gone` ranks with the notes in `cut`, never cut, with a statement that
    says so. Until then more than 30 head lines in one batch can cut an owned merge, and the `more`
    line says to read REST (`DESIGN.md`, Tradeoffs).
  - PR 4 and PR 6: the reviews reader's refused items join the feed as `Refused`
    (`HeadRead.reviews` holds a `Reading`), so one unreadable review no longer fails that head's
    reviews read; a PR 4 reader case pins it.
  - PR 4, PR 6 and PR 7b: a pull that left the open list with no close read gets one `pulls/N`
    read (a new route) before `gone` is told, and an unreadable outside open-pull item is skipped
    and told instead of failing the poll.
  - PR 8: `own comment|review-comment|review` reads the id back over REST and records it only when
    it is a post of the owner's login made after the caller's last wait started, printing its
    excerpt on stderr; otherwise it warns and records nothing.

### owner_decisions

`DESIGN.md` (Questions for you) splits these in two.

Part A, the owner's: 1 (no resident process: the deviation from the owner's ask), 2b (where the
root runs, a fact only the owner has), 2c (PR 12's spend and who starts its arm sessions), 3a (how
main's tool reaches the root: network and trust), 5a (the owner's own Claude-app posts quiet for
Claude consumers), 8a (pr-state's unanswered rule), 8b (land's merge admission, optional PR 3c),
9 (deleting the bash watcher's test suite, at PR 15).

Part B, the root's defaults, each with its reason. PR 0 carries them; merging PR 0 accepts them,
and a no on PR 0 changes one before the merge.
- 2a: Monitor with a wait that exits on the first event; the background-shell ban stays unless
  PR 12's numbers and the owner (PR 14) say otherwise. Reason: it saves about 66M of the about
  100M tokens with no new risk.
- 3b: pr-state's unanswered column uses main's tool once PR 11 lands. Reason: one classifier, in
  `gate/`.
- 3c: an outside agent gets the tool the way 3a decides, through `watch.sh build --fetch`; one that
  cannot keeps a bounded `gh` loop. Reason: one route to keep working.
- 4: all of it in `gate/`, in the one `mitos-gate` binary. Reason: the offer and ack logic bears on
  trust, and one binary keeps one build and one bootstrap.
- 5b: agents record review-thread reply ids with `watch.sh own`. Reason: GitHub names no app there,
  so an unrecorded reply wakes every waiting agent.
- 6: outside-account events ride along and never wake alone (`OutsidePolicy.rideAlong`). Reason: a
  fork's activity should not cost the root a wake; it is shown at the latest at the wait's deadline.
- 8c: no app besides `claude` and `cursor` answers the owner's words without its footer. Reason: it
  keeps land's rule.
- 7: #502's calls 1 to 3 and 5, restated against this design, follow from the answers above
  (call 4 is settled).
- Rows live in `plan/phase-2.md` under their own milestone (6), as the land and gate-architecture
  tracks each have their own milestone; the owner asked for a milestone.

## Done when
- [ ] all `checks` pass locally, per PR
- [ ] no `sorry`, no new axioms: `Watch.lean`'s audit ran, it checked every constant under
  `MitosGate.Watch` for axioms (`sorryAx` included) and found a theorem for every statement, and
  `gate/watch-test.sh` found no `sorry` in the build log of `Gh`, `Store` or `WatchCli`
- [ ] run-log record written (`ops/runs/`) per PR attempt
