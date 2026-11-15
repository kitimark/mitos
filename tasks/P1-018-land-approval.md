# tasks/P1-018-land-approval.md

phase: 1
goal: `plan` names a `merge` only for the pull request that is next on the owner's own entry, which on a kept path must approve (statements 15 to 18 proved, standard axioms only), and `mitos-gate land` reads and prints the new shapes, while nothing acts on a `merge` plan yet.
statement: none locked (`gate/` is not in `statements.lock`); the new `Land` statements are under Design, statements
touches: gate/MitosGate/Land.lean, gate/MitosGate/LandCli.lean, gate/MitosGate/Shadow/Reading.lean, gate/MitosGate/ShadowCli/Report.lean (one arm), gate/MitosGate/Speech/Comment.lean (`Read.word` only), gate/MitosGate/Speech.lean only under revisit_when (one fixture), gate/MitosGate/Snapshot/Obs.lean (`abouts` only), gate/MitosGate/SnapshotCli.lean (`wordJson` only), gate/MitosGate/Snapshot/Fixtures.lean, gate/land-fixtures/queue.json, gate/land-test.sh, gate/snapshot-test.sh, gate/shadow-fixtures/window/records/1003-1.json, this file, ops/runs/
must_not_touch: statements.lock, models.lock, eval/cheats/, models, .github/, .claude/, gate/MitosGate/Speech/Words.lean, gate/MitosGate/Speech/Syntax.lean, gate/MitosGate/Speech/Commit.lean, gate/MitosGate/SpeechCli.lean, gate/snapshot-fetch.sh, gate/shadow-fetch.sh, gate/speech-test.sh
checks: build (`lake build`, which proves every fixture and runs each module's axiom check), the axiom check (standard axioms only), every gate/*-test.sh, shellcheck, cheats (in ci)
budget: 15 iterations · 4h wall · 1.5M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-018 in `plan/phase-1.md` (Land track), row A1 of the auto-merge amendment; issue none
  yet; tracker #179.
- The amendment: #178, comment 6890739593. The owner accepted it on 15 Nov (#179, comment
  6890996353, recorded in 6891010165): call 2 of #179 flips to one owner action, `/land <commit>`,
  and calls N1 to N6 take their defaults. It amends the land design (#178, 6821317899) and its
  `covered` amendment (6832011164), and it follows the owner's word on #271 (6889810263).
- Rows A1 to A4 are P1-018 to P1-021. This row needs steps 1 and 2 (P1-010 merged as #198; step 2
  as #233, #244 and #246), which are merged. P1-019 (A2) follows it.
- Who merges: the owner, by hand (`gate/`). It is trust-critical, so it also gets an `opus`
  verifier at `xhigh`.
- How the design was made: two runners, on Opus and Fable, and a judge on Fable. The judge built
  the changed `Land.lean`, `LandCli.lean` and `Shadow/Reading.lean` on Lean 4.35.0, file by file,
  against a copy of `main` whose `gate/` is identical to `main` at a222e99 (compared file by file at
  plan time). This file carries the amendment's text for A1, and Build notes at plan time says what
  this row needs beyond it.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. The Land part of the amendment's section 3 is built: the judge's `Land.lean` (148
fixtures; statements 1 to 14 and 15 to 18 on the three standard axioms), `LandCli.lean` (the reader
of `approves` and `ownerSpoke`, the `merge` plan) and `Shadow/Reading.lean`. At plan time this
row's split was built alone on `main` at a222e99, with the reader passing `approves := false`:
every module from `Land` through `Speech`, `SpeechCli`, `Snapshot` (fixtures included),
`SnapshotCli`, `Shadow` and `ShadowCli` type-checks, and `land-test.sh`, `shadow-test.sh`,
`snapshot-test.sh` and `speech-test.sh` pass with the case changes under `fixtures` (Build notes at
plan time). The `Obs.word` sketch below, which says why an owner word does not stand, was added
and type-checked at plan time, with its statement proved and six fixtures. Contract only: how
`LandCli` prints it.

revisit_when: one case, for this row's PR owner. Steps 1 and 2 are merged; nothing this row needs
is open. If P1-013's PR 2 has merged first, its fixture
`ownerLandOnAKeptPathIsPresentedToTheOrchestrator` in `gate/MitosGate/Speech.lean` expects
`.present hC` for a bare `/land` on `.claude/scripts/land.sh`, a kept path. This row reads that
`/land` with `approves := false`, so it is no entry and the step is `.stop .noEntry`. This row then
changes that one fixture to expect `.stop .noEntry`, renamed
`bareOwnerLandOnAKeptPathIsNoEntryForTheOrchestrator`, and nothing else in that file. Either row may
merge first: the one that merges second writes `.stop .noEntry` (P1-013, revisit_when). Both values
were checked with `decide +kernel` (Build notes at plan time).

modules: one topic per file. Each edit stays in the file that owns its topic, and no file is added.
- `gate/MitosGate/Land.lean`: the decision over a snapshot. It gains `Mark.approves`,
  `Word.ownerSpoke` with its `Word.said` arm, `Word.decides`, `spokeSince`, `Obs.unnamed`,
  `OwnerWord` and `Obs.word`, the `merge` plan and its `plan` arm, statements 15 to 18 and
  `WordStandsIsTheEntry` with their proofs, and 43 fixtures (111 today, 148 in the judge's file,
  154 with `Obs.word`'s six). About 1,680 lines (1,388 today). It keeps its own layout: statements,
  proofs, `namespace Fixture`, then the axiom check, whose list gains the new statements.
- `gate/MitosGate/LandCli.lean`: the JSON of `land`. It reads `approves` (an absent key reads
  false) and `ownerSpoke`, prints the `merge` plan and the `word` field. About 330 lines (304).
- `gate/MitosGate/Shadow/Reading.lean`: the assumed word, which now approves. 16 lines change.
- `gate/MitosGate/ShadowCli/Report.lean`: in `pushes` (75), `.merge _ _ | .idle => none`, because a
  merge is no push.
- `gate/MitosGate/Speech/Comment.lean`: `Read.word` (218) passes `false` for both marks. Two lines.
  The reader that sets `approves` is P1-019's.
- `gate/MitosGate/Speech.lean`: only if P1-013's PR 2 has merged first (revisit_when). Its fixture
  `ownerLandOnAKeptPathIsPresentedToTheOrchestrator` becomes
  `bareOwnerLandOnAKeptPathIsNoEntryForTheOrchestrator`, `= .stop .noEntry`. Three lines.
- `gate/MitosGate/Snapshot/Obs.lean`: one `abouts` arm (30), `.ownerSpoke _ :: ws => abouts ws`.
- `gate/MitosGate/SnapshotCli.lean`: one `wordJson` arm (243),
  `.ownerSpoke s => kind "ownerSpoke" [("said", n s)]`. It prints no `approves` yet, since every
  word the reader gives in this row has `approves := false`, which an absent key reads as.
- `gate/MitosGate/Snapshot/Fixtures.lean`: one literal and eight expected steps (Build notes).
- `gate/land-fixtures/queue.json`, `gate/land-test.sh`, `gate/snapshot-test.sh`: the JSON cases
  (`fixtures`).
- `gate/shadow-fixtures/window/records/1003-1.json`: its printed decision (Build notes).

### Usage (caller's view)

Nothing changes for an agent or the owner when this row merges. No job acts on a `merge` plan
until P1-020, and the reader approves nothing until P1-019.

`mitos-gate land` reads two new word shapes and prints a new plan:

```
{"kind":"ownerLand","said":900,"about":"aaa","approves":true}
{"kind":"ownerSpoke","said":950}
{"next":153,"plan":{"head":"ar","kind":"merge","pr":153},"step":{"head":"ar","kind":"present"},"word":"stands"}
```

`word` (contract) is printed beside `step`, so only when the snapshot names `me` and `pr`. It is
one of `none` (no owner `/land` or `/hold` is the newest owner word), `held`, `unnamed` (a `/land`
that does not approve, on a kept path), `spoke` (the owner typed another comment after it), `stale`
(it names content that `carry` does not reach from the head) and `stands`. P1-020's `report` reads
it. `decide` runs `land` without `me` and `pr`, so its records keep their shape.

types: the amendment's section 3, Land part, under The amendment's text for this row, and this
sketch, added at plan time and type-checked against the judge's `Land.lean`:

```lean
inductive OwnerWord
  | none | held | unnamed | spoke | stale | stands
  deriving DecidableEq

def Obs.word (o : Obs) : OwnerWord :=
  match newestOwner o.words with
  | some (.ownerHold _) => .held
  | some (.ownerLand m) =>
    if o.kept && !m.approves then .unnamed
    else if spokeSince o.words m.said then .spoke
    else if !o.carries m.about then .stale
    else .stands
  | _ => .none
```

`Mark`, `Plan` and `Word.said` as they become. The quote names the changes to `Mark` and `Plan`
only in its comments, and `Word.said`, which needs an arm for `ownerSpoke`, not at all, so here they
are as code. `Mark` and `Plan` were added in round 2 of the plan PR and type-checked beside
`main`'s `Land`, together with the uses that the quote and Build notes give them:
`⟨said, o.head, true⟩`, `⟨n, s, false⟩`, `.merge o.pr o.head` and `m.approves`. `Word.said` was
added in round 3 and built with the rest of the sketch (Build notes). `Plan.push` keeps its doc
comment from `main`.

```lean
structure Mark where
  said : Nat
  about : Sha
  approves : Bool
  deriving DecidableEq

def Word.said : Word → Nat
  | .ownerLand m => m.said
  | .ownerHold s => s
  | .ownerSpoke s => s
  | .agentLand _ m => m.said

inductive Plan
  | push (pr : Pr) (expect replay : Sha)
  | idle
  | merge (pr : Pr) (head : Sha)
  deriving DecidableEq
```

statements: 15 `PlannedMergeIsGated`, 16 `OwnerEntryIsTheirLastWord`, 17 `KeptEntryIsTheOwners`
and 18 `OnlyLandOrHoldChangesTheWord`, in the amendment's text below, each proved in the judge's
file. Statements 1 to 14 keep their text. Added at plan time and proved (standard axioms only):

```lean
def WordStandsIsTheEntry : Prop :=
  ∀ o : Obs, o.word = .stands ↔ ∃ e ∈ o.entries, e.lander = .owner ∧ o.carries e.mark.about = true
```

The doc comments in the amendment's sketch are its prose. `main`'s statements carry none, and the
judge's built file keeps them out.

reuse:
- `gate/MitosGate/Land.lean` on `main`: `Mark` (40), `Word` (45), `Word.byOwner` (135),
  `newestOwner` (139), `Obs.entries` (161), `Plan` (207), `plan` (213), `step` (238),
  `MergeIsGated` (319), `HoldWins` (329), `AgentKeepsOwnerWord` (333), `OnlyMergersQueue` (336),
  `next_landable` (362).
- The judge's proofs: `entries_agent`, `entries_cases`, `spokeSince_false` and the four new
  statements' proofs; `newestOwner_none`, `newestOwner_max` and `newestOwner_eq_some` now read
  `decides`. `wordStandsIsTheEntry` rests on `entries_cases`.
- `gate/MitosGate/LandCli.lean`: `tagged` and `opt` (the `word` decoder, 137), `planJson` (233),
  `Decision` and `Snapshot.decide` (214 and 220).

fixtures:
- `Land`: section 5's list below, all built (111 become 148). The judge's file adds four that the
  list leaves out: `bareLandOnAKeptPathIsAskedForTheCommit`,
  `laterOwnerCommentLeavesAHeldPullRequestWithNoEntry`,
  `laterOwnerCommentRetiresABareLandOffKeptPathsToo` and
  `laterOwnerCommentLeavesAnAgentLandingAlone`. Added at plan time for `Obs.word`:
  `aBareLandOnAKeptPathIsUnnamed`, `anApprovalStands`, `aLaterCommentIsSpoke`,
  `anApprovalOfOlderContentIsStale`, `aHoldIsHeld` and `noOwnerWordIsNone`.
- `gate/land-test.sh` (run at plan time with the split):
  - `queue.json`'s owner word on PR 153 (a kept path) gains `"approves": true`. Without it, 14 of
    the 55 cases fail, because a bare `/land` on a kept path is no entry now.
  - "green on main, a kept path: the owner merges, the tool presents" expects
    `"plan":{"head":"ar","kind":"merge","pr":153}`, the JSON twin of
    `afterPushNothingIsPushedAgain`'s new value. Its name says the workflow merges.
  - New cases: an absent `approves` on a kept path is no entry and `word` reads `unnamed`; an
    `ownerSpoke` after the approval leaves no entry for 153 and `word` reads `spoke`; each `word`
    value once; `approves` that is not a boolean, and `approves` on any other word kind, are
    refused; an `ownerSpoke` out of comment order is refused, as other words are.
- `gate/snapshot-test.sh`: four cases whose `next` is PR 9, an owner word on a green head on
  `main` off the kept paths, now expect `"plan":{"head":"$q1","kind":"merge","pr":9}` where they
  expected `idle`: "the owner's /land on a head already on main goes first, and nothing is pushed"
  (renamed: its plan is that merge), "a conflict is stuck", "an edited /land holds" and "an app's
  /land is no entry". #278 merged first, and its case "protection: with the reader's file, the
  owner's /land goes first" is a fifth. Every case that prints `step` also prints `word`.
- `gate/MitosGate/Snapshot/Fixtures.lean`: the eight steps under Build notes.
- `gate/shadow-test.sh`: the window still scores to its expected report once record 1003-1 prints
  this build's decision (Build notes).

cut_line: one PR, `Part of #179` (A1 has no issue yet; the PR names its issue once the plan's
issues are opened). It ships section 3's Land part, `LandCli`, `Shadow`, the four one-arm edits
that keep the reader compiling with `approves := false`, and `Obs.word` with its `word` field. It
leaves the reader that sets `approves` and reads `ownerSpoke` (`onlyWords`, `typed`, the review
routes) and the JSON cases of section 5 to P1-019, and every job that acts on a `merge` plan to
P1-020.

deferrals:
- Into this row: "why an owner word does not stand" (section 6, A1) had no sketch; `Obs.word` is
  its plan-time design.
- To P1-019: `approves` in `SnapshotCli.wordJson`, the reader's `spoke`, and turning the eight
  Snapshot fixtures back to `.present hB` once the base comment names its commit.
- To P1-012 (#191): after this row merges, a scorer built from `main` marks every record made
  before it as drifted wherever this row changed the plan: an owner word on a green head on
  `main` (`idle` becomes `merge`), or a bare `/land` on a kept path (no entry now). The report on
  #191 scores records made before this merge with a build of the commit before it, as
  `gate/shadow-fixtures/window/records/1003-1.json` shows.
- To P1-020: everything that acts on a `merge` plan.

owner_decisions:
- **Settled by the owner's acceptance (15 Nov):** the three changed promises of `gate/` in section
  3 (6 `MergeIsGated` speaks for agents only, 10 `OnlyMergersQueue` gains 16 and 17,
  `Shadow.ReadyIsOneWordFromLanding` changes its text). The PR body lists them again.
- **Root's default, made at plan time:** the eight Snapshot fixtures read `.stop .noEntry` in this
  row and go back to `.present hB` in P1-019. The reason: with `approves := false` the reader's
  bare `/land` on `gate/Main.lean` is no entry, and that is the new rule, so the fixtures pin it
  while each `notEligible` neighbour still differs. The other choice is one PR for A1 and A2.
- **Root's default, made at plan time:** `word` is printed only beside `step`, so the records
  `decide` makes keep the shape the scorer compares.

### The amendment's text for this row

Section 6, row A1:

| Row | Change | Needs | Merged by |
|---|---|---|---|
| A1, new, can start now | `Land.lean` as in section 3, with proofs and fixtures. `LandCli`: `approves`, `ownerSpoke`, the `merge` plan, and why an owner word does not stand. `Shadow`: the assumed word approves. The reader compiles with `approves := false`. | steps 1 and 2 | the owner, by hand (`gate/`) |

Section 3 (Land part):

Changed parts only. All of it is built (see What was checked).

```lean
-- `Mark` gains `approves : Bool`: a typed comment that holds only `/land <commit>`. False elsewhere.
inductive Word
  | ownerLand (m : Mark)
  | ownerHold (said : Nat)
  | ownerSpoke (said : Nat)   -- any other comment the owner typed; `byOwner` is true for it
  | agentLand (who : Teammate) (m : Mark)
  deriving DecidableEq

/-- The owner's `/land` or `/hold`. `newestOwner` now reads `decides` where it read `byOwner`. -/
def Word.decides : Word → Bool
  | .ownerLand _ | .ownerHold _ => true
  | _ => false
def spokeSince (ws : List Word) (n : Nat) : Bool :=
  ws.any fun
    | .ownerSpoke s => decide (n < s)
    | _ => false

-- `Obs.entries`, the one changed arm:
  | some (.ownerLand m) =>
    if (!o.kept || m.approves) && !spokeSince o.words m.said then ⟨o.pr, m, .owner⟩ :: agents
    else agents
-- `Plan` gains `merge (pr : Pr) (head : Sha)`: rebase-merge pinned to `head`, with the workflow's key.
-- `plan`, the new arm, where `(e, o)` is the entry that is next:
    | .current => if e.lander.isOwner && o.gate == .success then .merge o.pr o.head else .idle

/-- 15. The workflow merges only the pull request that is next: its live head, on `main`, green
there, protection binding everyone, covered, reviewed, on the owner's own entry. That entry is
their newest `/land` or `/hold`, no other comment of theirs follows it, it names a commit `carry`
reaches, and on a kept path it approves. -/
def PlannedMergeIsGated : Prop :=
  ∀ q p h, plan q = .merge p h →
    ∃ e o, next q = some (e, o) ∧ o.pr = p ∧ h = o.head ∧ o.base = .current ∧ o.gate = .success ∧
      o.enforced = true ∧ o.updatable = true ∧ o.Covered ∧ o.reviewed = true ∧ o.rest = true ∧
      e.lander = .owner ∧ newestOwner o.words = some (.ownerLand e.mark) ∧
      (∀ s, Word.ownerSpoke s ∈ o.words → s ≤ e.mark.said) ∧
      o.carries e.mark.about = true ∧ (o.kept = true → e.mark.approves = true)

/-- 16. The same word clauses for every owner entry, so they hold for a replay too. -/
def OwnerEntryIsTheirLastWord : Prop :=
  ∀ (o : Obs) (e : Entry), e ∈ o.entries → e.lander = .owner →
    e.pr = o.pr ∧ newestOwner o.words = some (.ownerLand e.mark) ∧
      (∀ s, Word.ownerSpoke s ∈ o.words → s ≤ e.mark.said) ∧
      (o.kept = true → e.mark.approves = true)

/-- 17. On a kept path nothing stands but the owner's entry, whatever agents wrote. -/
def KeptEntryIsTheOwners : Prop :=
  ∀ (o : Obs) (e : Entry), e ∈ o.entries → o.kept = true → e.lander = .owner

/-- 18. Only a `/land` or a `/hold` changes the owner's newest word. So another comment never
lifts a `/hold` and never brings back an older `/land`. -/
def OnlyLandOrHoldChangesTheWord : Prop :=
  ∀ ws : List Word, newestOwner ws = newestOwner (ws.filter (·.decides))
```

- **The actor is the workflow, and it is `plan`'s only reader.** `plan` takes no caller, so nobody can claim to be the workflow.
- **`step` does not change.** On an approved kept path it still answers `present`, which now means "the workflow has the merge".
- **No statement text changes** in `Land` (1 to 14), `Speech` or `Snapshot`. The texts were compared mechanically. The definitions under them that change are `Mark`, `Word`, `newestOwner`, `Obs.entries`, `Plan` and `plan`, and in the reader `Read`, `ownerRead`, `Read.word` and the `words` of `Snapshot.obs`. `newestOwner` gives the same answer on every word list that exists today.
- **What `gate/` promises changes in three places.** The owner should accept each as a statement change:
  - **6 `MergeIsGated`** keeps its text and now speaks for agents only. "No merge of a kept path" becomes "no agent merge of a kept path (6), and a workflow merge only on the owner's approval (15 to 17)".
  - **10 `OnlyMergersQueue`** keeps its text. 17 adds that on a kept path only the owner's entry stands, and 16 that it approves. So a bare `/land` on a kept path is no longer replayed.
  - **`Shadow.ReadyIsOneWordFromLanding`** changes its text: the assumed word approves (`⟨said, o.head, true⟩`).
- **8 `HoldWins`, 9 and 14** keep their text and their reach. 18 pins the first two. A green `gate` on the owner's entry still wakes no agent, now because the workflow merges.
- **Expected values that change.** In `Land`, `afterPushNothingIsPushedAgain` goes from `.idle` to `.merge 153 "ar"`, and its "no second push" half stays as a fixture on the head whose `gate` still runs. In `Speech`, 10 reads gain the flag and 10 change from ignored to `spoke`. In `Snapshot`, the fixtures' base comment is a bare `/land` on `gate/Main.lean`, so it gains the commit.

Section 5, the `Land` cases:

`eval/cheats` is the corpus of proof cheats against the core gate, so no land case goes there. Land cases are `Fixture` theorems (`decide +kernel`, checked by the build) and the JSON cases of the `gate/*-test.sh` scripts.

**`Land`, built (111 fixtures become 148).**

- **Accept:** `afterPushTheApprovedLandingIsMergedNotPushedAgain`, `approvalOfTheNewContentMerges`, `approvalTypedAgainAfterSpeakingMerges`, `ownerCommentBeforeTheApprovalDoesNotRetireIt`, `bareLandOffEveryKeptPathIsMerged`, `verdictFromAnotherModelLetsTheRulePathMerge`, `oneMergeAtATimeTheLandingOnMainFirst`.
- **Reject, the word:** `bareLandOnAKeptPathIsNoEntry` (with `…IsNotPushed`, `…IsNotMerged`, `…DoesNotHoldTheLine`), `bareLandOnUnreadPathsIsNotMerged`, `bareLandAfterAnApprovalStandsForNothing`, `agentWordOnAKeptPathMergesNothing`, `agentEntryIsNeverThePlannedMerge`, `agentStepOnAnApprovedKeptPathIsStillPresent`, `approvalNamingAnUnknownCommitMergesNothing`.
- **Reject, stale or held:** `approvalOfAnOlderCommitDoesNotReachNewContent` (an owner content push after the approval), `holdAfterTheApprovalMergesNothing`, `laterOwnerCommentRetiresTheApproval`, `laterOwnerCommentDoesNotReviveAnOlderApproval`, `laterOwnerCommentDoesNotLiftAHold`, `laterOwnerCommentDoesNotLetAHeldBranchBePushed`, `holdThenOwnerCommentStaysHeldOnAKeptPath`.
- **Reject, the rest:** `missingSpecLabelOrUnansweredCommentMergesNothing`, `draftForkOrStackMergesNothing`, `botReviewMissingMergesNothing`, `redGateMergesNothing`, `cancelledGateMergesNothing`, `afterPushNothingIsPushedWhileTheGateRuns`, `unenforcedProtectionMergesNothing`, `verdictFromTheAuthorsModelOnlyMergesNothing`, `trustPathWithoutAnOpusPassMergesNothing`, `laterFailMergesNothing`.

### Build notes at plan time

Checked on `main` at a222e99, Lean 4.35.0, each module compiled alone with `lean -o` in dependency
order:
- With the judge's `Land.lean`, `LandCli.lean` and `Shadow/Reading.lean` and only these edits
  elsewhere, the reader compiles with `approves := false`:
  - `Speech/Comment.lean` `Read.word`: `⟨n, s, false⟩` for `ownerLand` and `agentLand`;
  - `Snapshot/Obs.lean` `abouts`: an `ownerSpoke` arm;
  - `SnapshotCli.lean` `wordJson`: an `ownerSpoke` arm;
  - `ShadowCli/Report.lean` `pushes`: a `merge` arm.
  `Speech.lean` (106 fixtures), `Speech/Words.lean`, `SpeechCli`, `Shadow/*` and `ShadowCli/*`
  build unchanged. The judge's `Obs.lean` has the `abouts` arm; the last two edits are new, because
  the judge built neither `SnapshotCli` nor `ShadowCli`. P1-013's PR 2 was not on that `main`; the
  next bullet checks its one fixture that this row changes (revisit_when).
- The fixture under revisit_when, in round 3 of the plan PR, on `main` at 48bb997 with P1-013 PR 2's
  `delegates` and its eight `Speech` fixtures, each module compiled alone with `lean -o`:
  - `main`'s `Land`: `stepAs orchestrator [typed 112 12 "/land"] [".claude/scripts/land.sh"]` is
    `.present hC` and not `.stop .noEntry`, so PR 2's fixture holds while this row is open.
  - `main`'s `Land` definitions with the sketch's changes (`Mark` and `Plan` as code above, the
    `ownerSpoke` arm of `Word.said`, `Word.decides`, `spokeSince`, the `Obs.entries` arm, the
    `plan` arm), `newestOwner_none`, `newestOwner_max`, `eq_of_said_eq` and `newestOwner_eq_some`
    reading `Word.decides`, and `Read.word` passing `false`: the same step is `.stop .noEntry` and
    not `.present hC`. So after this row the fixture expects `.stop .noEntry`, whichever row merged
    first.
  - Each value is a `decide +kernel` theorem on the three standard axioms. PR 2's other seven
    fixtures, and `Speech.lean`'s 106, build on both.
- `Snapshot/Fixtures.lean` fails on nine fixtures until it changes: `theOwnersLandIsTheEntry` needs
  `⟨1800, hB, false⟩`, and eight that expected `.present hB` now give `.stop .noEntry`, because the
  base comment is a bare `/land` on `gate/Main.lean`: `allReadAndCoveredIsPresented`,
  `aVerdictOnAnOlderHeadCarriesOverTheUpdatersPush`, `anAnsweredOwnerQuestionIsEligible`,
  `aLandAfterAByteOrderMarkNeedsNoAnswer`, `anOtherLoginsCommentNeedsNoAnswer`,
  `aSummaryBelowTheFooterIsPresented`, `aSpecPathWithTheLabelIsPresented` and
  `aPassedRabbitCheckAtTheHeadIsAReview`. With those values it builds (about 330 s here).
- `land-test.sh`, `shadow-test.sh`, `snapshot-test.sh` and `speech-test.sh` ran through the
  interpreter on these modules (no `lake build` of `mitos-gate`, which also needs the core):
  - `land-test.sh`: 41 of 55 pass as `main` has it; 54 with `"approves": true` on PR 153's word;
    55 with the merge plan in "green on main, a kept path".
  - `shadow-test.sh`: 48 of 49, the window case failing; 49 once record 1003-1 prints this build's
    decision.
  - `snapshot-test.sh`: 47 of 51; 51 with the four expected plans under `fixtures`.
  - `speech-test.sh`: 39 of 39, unchanged.
- `gate/shadow-fixtures/window/records/1003-1.json` printed `{"next":304,"plan":{"kind":"idle"}}`.
  This build decides `{"next":304,"plan":{"head":"a304a304a304a304a304a304a304a304a304a304","kind":"merge","pr":304}}`,
  so the scorer lists it as drifted, #303 and #305 turn `blind`, and four lines of counts change.
  With the record printing this build's decision, the window scores to its report as today, and
  record 1006-1 still pins the drift case.
- `Obs.word`, `WordStandsIsTheEntry` and its six fixtures type-check in a file that imports the
  judge's `Land`; `#print axioms` gives `propext`, `Classical.choice` and `Quot.sound`.
- Not run: a whole `lake build`, `lake exe mitos-gate` itself, `cd core && lake check`, the cheat
  corpus, and `LandCli`'s `word` field, which has no code yet.

## Done when
- [x] statements 15 to 18 and `WordStandsIsTheEntry` proved; the 14 old statements keep their text
- [x] `lake build` passes: 154 `Land` fixtures, and every other module's fixtures
- [x] every `gate/*-test.sh` passes, with the cases under `fixtures`
- [x] the PR body lists the three changed promises and each expected value that changed
- [x] all `checks` pass locally, except the cheat corpus, which runs in CI
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)

## After merge: the #303 and #200 follow-ups

One later PR changed `Land.lean` and `land-test.sh` for #303 (items 1 and 2) and for the `Land`
items of #200:
- `Obs.unnamed` is gone (#303 item 1). Nothing read it, and it repeated the `unnamed` arm of
  `Obs.word`, which `LandCli` prints as `word`. Its fixture `bareLandOnAKeptPathIsAskedForTheCommit`
  went with it. `aBareLandOffTheKeptPathsStands` now pins the `o.kept` test in `Obs.word`, as
  `WordStandsIsTheEntry` does.
- The rules of `Obs.Covered` are statements: `UnknownAuthorCoversNothing`,
  `StandingFailOrHoldCoversNothing`, `CoverIsAnotherJudgesWord` and
  `CriticalCoverIsAnOpusPassOrWordingOnly`.
- `QuietAfterRebase` (statement 14) no longer puts its gate clauses under `covered p = true`. On
  the owner's word alone, a gate result that is not red wakes nobody exactly when it is green,
  covered or not; in nobody's line it wakes nobody exactly when the pull request is covered. Only
  the bot-review clause keeps the hypothesis. The old text follows from the new one.
- The axiom check covers every theorem the file adds, private ones included, and names each
  failure. `land-test.sh` plants four `sorry`s (one in a private lemma) and an axiom in a copy and
  requires the check to name all five.
- New fixtures pin each entry of the kept and critical path lists, unread paths as critical,
  a stale bot review, a head without a content id and the holder wake of an uncovered gate in
  nobody's line. 164 `Land` fixtures (154 before).
