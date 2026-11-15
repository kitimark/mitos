# tasks/P1-019-typed-approval-reader.md

phase: 1
goal: The reader sets `approves` only for a typed, unedited owner comment that holds only `/land <commit>`, reads every other typed owner comment as `ownerSpoke`, adds one `ownerSpoke` when the owner posts on a review route at or after the approval, and `KeptMergeIsTheOwnersTypedApproval` proves that a `merge` plan on a kept path traces to that one comment.
statement: none locked (`gate/` is not in `statements.lock`); `Speech.ApprovalIsTypedAndNamed`, `Speech.TypedCommentIsAWord` and `Snapshot.KeptMergeIsTheOwnersTypedApproval` are under Design, statements
touches: gate/MitosGate/Speech/Comment.lean, gate/MitosGate/Speech/Words.lean, gate/MitosGate/Speech.lean, gate/MitosGate/SpeechCli.lean, gate/MitosGate/Snapshot/Obs.lean, gate/MitosGate/Snapshot/Fixtures.lean, gate/MitosGate/SnapshotCli.lean (`wordJson` only), gate/speech-test.sh, gate/snapshot-test.sh, gate/land-test.sh, this file, ops/runs/
must_not_touch: statements.lock, models.lock, eval/cheats/, models, .github/, .claude/, gate/MitosGate/Land.lean, gate/MitosGate/LandCli.lean, gate/MitosGate/Shadow.lean, gate/MitosGate/Shadow/, gate/MitosGate/ShadowCli.lean, gate/MitosGate/ShadowCli/, gate/MitosGate/Speech/Syntax.lean, gate/MitosGate/Speech/Commit.lean, gate/snapshot-fetch.sh, gate/shadow-fetch.sh
checks: build (`lake build`, which proves every fixture and runs each module's axiom check), the axiom check (standard axioms only), every gate/*-test.sh, shellcheck, cheats (in ci)
budget: 20 iterations · 6h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-019 in `plan/phase-1.md` (Land track), row A2 of the auto-merge amendment (#178,
  comment 6890739593, accepted by the owner on 15 Nov in #179, comment 6890996353); issue none
  yet; tracker #179.
- Needs P1-018 (A1), which adds `Mark.approves`, `Word.ownerSpoke`, the `merge` plan and statements
  15 to 18, and has the reader pass `approves := false`. P1-020 (A3) follows this row.
- Who merges: the owner, by hand (`gate/`). It is trust-critical, so it also gets an `opus`
  verifier at `xhigh`.
- The judge built this row's Lean on Lean 4.35.0: the three `Speech` files with every fixture, and
  `Snapshot` up to `Obs.lean` with `KeptMergeIsTheOwnersTypedApproval` proved. It did not build
  `Snapshot/Fixtures.lean` with the new base comment (its build was killed for memory, on `main`'s
  tree too), `SpeechCli`, `SnapshotCli` or any `gate/*-test.sh` (the amendment's "Not run").
- #245's fourth item (a typed `@coderabbitai` command counts as unanswered) is unchanged by this
  row. Under N2 such a command also retires the approval, the cost the amendment names.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: contract only, so this row's issue says "contract only". Most of its sketch is built: at
plan time the judge's `Speech/Comment.lean`, `Speech/Words.lean`, `Speech.lean` (125 fixtures, in
115 s) and `Snapshot/Obs.lean` built on top of P1-018's plan-time split on `main` at a222e99, and
`SpeechCli` built with the two arms under `modules`.
`main`'s `Snapshot/Fixtures.lean` also built on it (417 s) with three edits: the base comment
`"/land " ++ hB`, `aLandAfterAByteOrderMarkNeedsNoAnswer`'s body `"\uFEFF/land " ++ hB`, and
`⟨1800, hB, true⟩` in `theOwnersLandIsTheEntry`. So every fixture that expects `.present hB` on
`main` passes again, after P1-018 turned eight of them to `.stop .noEntry`.
Not built: `SnapshotCli`'s `approves`, the 11 Snapshot cases and the JSON cases.

revisit_when: re-check after P1-018 merges.

modules: one topic per file; no file is added.
- `gate/MitosGate/Speech/Comment.lean`: what one comment says. `Read.land` gains `approves`; `Read`
  gains `spoke`; `onlyWords`, `holdOrSpoke` and `typed` are added. `ownerRead` (125) reads `spoke`
  where it read `ignored .noWord` or `ignored .protocolFence`, and `ignored .footer` stays. Lemmas:
  `ownerRead_land` (it also gives the flag), `target_named`, `ownerRead_byOwner`, `byOwner_word`.
  About 565 lines (514 today).
- `gate/MitosGate/Speech/Words.lean`: the words of a conversation. `ApprovalIsTypedAndNamed`,
  `TypedCommentIsAWord`, and `ownerLand_read`, which `OwnerLandIsTyped`'s proof now uses. About
  430 lines (377).
- `gate/MitosGate/Speech.lean`: the fixtures. 10 reads gain the flag, 10 change from `ignored` to
  `spoke`, 19 are new, and the axiom check's list gains the two statements. About 380 lines (330).
- `gate/MitosGate/SpeechCli.lean`: the `speech` line. `.land s a` prints `approves` where it
  printed `land` when `a` is true, and `.spoke` prints `<id> ownerSpoke@<n>`. Built at plan time
  with exactly these two arms; the words are the root's default.
- `gate/MitosGate/Snapshot/Obs.lean`: the snapshot of one pull request. `reviewPosts`,
  `spokeInReview`, `withReviewSpeech` and the `words` of `obs` (20); `KeptMergeIsTheOwnersTypedApproval`
  with `newestOwner_append_spoke`, `newestOwner_withReviewSpeech` and `mem_withReviewSpeech`;
  `failedReadHolds` reads through `newestOwner_withReviewSpeech`. About 270 lines (167).
- `gate/MitosGate/Snapshot/Fixtures.lean`: the base comment `land` names its commit
  (`"/land " ++ hB`), and so does `aLandAfterAByteOrderMarkNeedsNoAnswer`'s body; P1-018's eight
  `.stop .noEntry` go back to `.present hB`; `theOwnersLandIsTheEntry` reads `⟨1800, hB, true⟩`;
  the 11 cases of section 5.
- `gate/MitosGate/SnapshotCli.lean`: `wordJson` (243) prints `("approves", .bool m.approves)` on
  `ownerLand`. P1-018 already prints `ownerSpoke`.
- `gate/speech-test.sh`, `gate/snapshot-test.sh`, `gate/land-test.sh`: the JSON cases.

### Usage (caller's view)

After this row, on a kept pull request, the owner's comment that holds only `/land <commit>`
approves; `decide`'s record then plans `{"kind":"merge","pr":7,"head":"…"}` once everything is
green, still printed only, because no job acts on it until P1-020. A bare `/land`, or the line with
other text, on a kept path is no entry; off the kept paths it lands as before. Anything else the
owner types after the approval, in the conversation or on a review, retires it until they type the
line again.

```
$ mitos-gate speech --owner owner --pr 7 --pushes pushes.tsv comments.json
108 ownerLand@216 <sha> approves
112 ownerSpoke@224
```

`mitos-gate snapshot` prints `{"kind":"ownerLand","said":216,"about":"…","approves":true}` and
`{"kind":"ownerSpoke","said":224}`; `land` reads an absent `approves` as false (P1-018).

types: the amendment's section 3, Speech and Snapshot parts, under The amendment's text for this
row. In the built files `Read` is:

```lean
inductive Read
  | land (about : Sha) (approves : Bool)
  | hold (why : Why)
  | editHold
  | spoke
  | agent (who : Teammate) (about : Sha)
  | ignored (why : Why)
  deriving DecidableEq
```

statements: `Speech.ApprovalIsTypedAndNamed`, `Speech.TypedCommentIsAWord` and
`Snapshot.KeptMergeIsTheOwnersTypedApproval`, in the amendment's text below, each proved in the
judge's files on the three standard axioms. The 19 `Speech` statements and the 10 `Snapshot`
statements keep their text (`AppNeverOwner`, `FooterIsNeverOwner` and the rest).

reuse:
- `gate/MitosGate/Speech/Comment.lean`: `word?` (44), `unbom` (59), `ownerLines` (63), `target`
  (68), `holdLine` (79), `doubt` (118), `ownerRead` (125), `read` (207), `Read.word` (218).
- `gate/MitosGate/Speech/Words.lean`: `top` (22), `words` (37), `OwnerLandIsTyped` (74),
  `arrange_keeps` (169), `lastBy_ge` (198), `top_ge` (249), `pos_cases` (265), `wordTraces` (338).
- `gate/MitosGate/Speech/Syntax.lean` `footer` (85) and `blank` (23); `Speech/Commit.lean`
  `resolve` (36).
- `gate/MitosGate/Snapshot/Fields.lean`: `speaks` (71), `unanswered` (78), `counts` (82), `posts`
  (85), `rest` (95). `reviewPosts` reads the same two routes as `posts`, so the fetch reads nothing
  new.
- From P1-018: `Land.plannedMergeIsGated`, `Land.onlyLandOrHoldChangesTheWord`,
  `Land.newestOwner_max`.

fixtures:
- `Speech` and `Snapshot`: section 5's lists below. The `Speech` ones are built (106 become 125).
  The 11 `Snapshot` cases are to write; the judge evaluated each through `obs` and `plan`.
- The JSON cases: section 5's first "To write" bullet below. Each runs the real `mitos-gate`
  commands, as the `gate/*-test.sh` scripts do.
- `speech-test.sh`: every typed comment that read `ignored no-word` or `ignored record-without-app`
  now reads `ownerSpoke`, `ignored footer` stays, and a named `/land` alone prints `approves`.

cut_line: one PR, `Part of #179`. It ships the reader of section 3, its two statements and the
Snapshot statement, the fixtures and the JSON cases. It leaves every job that acts on a `merge`
plan to P1-020 and the rules to P1-021.

deferrals:
- From P1-018: `approves` in `SnapshotCli.wordJson`, and the eight Snapshot fixtures back to
  `.present hB`.
- To P1-020: the shadow evidence. Records made from this row's merge on are the first in which a
  typed approval reads as one, so P1-020's window starts here.
- To P1-021: the rule and the hook for a deleted comment (N6).
- Unchanged and still open on #245: an owner's typed `@coderabbitai` command counts as unanswered.

owner_decisions:
- **Settled by the owner's acceptance (15 Nov):** N1 (the approval is a comment that holds only
  `/land <commit>`, and it covers exact content), N2 (anything else the owner types after it
  retires it), N3 (the workflow also merges the owner's `/land` off kept paths, where a bare one
  still counts) and N6 (a deleted comment stays unseen), each with its default.
- **Root's default, made at plan time:** the `speech` line words, `approves` and `ownerSpoke`. They
  show only in `mitos-gate speech`, which no workflow or script reads but `speech-test.sh`.

### The amendment's text for this row

Section 6, row A2:

| Row | Change | Needs | Merged by |
|---|---|---|---|
| A2, new | The reader of section 3 with its two statements and fixtures, the Snapshot statement, the JSON cases | A1 | the owner, by hand (`gate/`) |

Section 1, what the reader reads:

**The approval is one comment that the owner types in the PR conversation and that holds only the line `/land <commit>`.**

| Candidate | Call | Reason |
|---|---|---|
| `/land <commit>`, alone in a typed comment | **chosen** | It is already parsed and proved typed, it names content, and it is ordered against `/hold` and edits. |
| A review approval | no | Agents open PRs through the owner's account, so the owner is the author, and GitHub lets no author approve their own PR. Review objects also have no app field, so an agent's review would look typed. |
| The owner's own words ("approved, merge it after pipeline is passed") | no | Free text names no commit. Four of the last seven approvals set an order or a condition (#159, #232, #234, #246). The root answers such a comment with the line to type. |
| A bare `/land`, or the line with other text | no approval on a kept path | A bare word names the head of that second, so a fix pushed while the owner types would land unseen. Other text can hold a condition. The workflow answers with the line. Off kept paths both land as before. |
| A label, or GitHub's auto-merge | no | A label names no content, and its event shows no app. Auto-merge is off and checks no verdict. |

- **Pin.** The commit is 7 to 40 hex digits, resolved as today. The approval stands while `carry` reaches the live head from it. So the updater's replay keeps it, and any other push ends it.
- **Edited.** An edited comment under the owner's login reads as `/hold`, whatever it says (unchanged).
- **Deleted.** A deleted comment cannot be seen over REST (call N6).
- **`/hold`** wins as before. New: anything else the owner types after the approval, in the conversation or on a review, retires it until they type the line again. It never lifts a `/hold`.
- **An app's post never counts.** A comment with an app or a footer is never an owner word. Step 2 proved that (`AppNeverOwner`, `FooterIsNeverOwner`), and the same statements now cover the approval and the retiring comment.

Section 3 (Speech and Snapshot parts):

Changed parts only. All of it is built (see What was checked).

```lean
-- Speech. `Read` gains `spoke`, and `land` gains the flag: `.land s (decide (arg ≠ []) && onlyWords b)`.
-- A typed comment with no word, or with a protocol fence, reads `spoke`. It was ignored.
def onlyWords (b : List Char) : Bool := (lines (unbom b)).all fun l => blank l || (word? l).isSome
def typed (x : Ctx) (c : Comment) : Bool :=
  c.login == x.owner && c.slug.isNone && !footer (unbom c.body.toList)
def ApprovalIsTypedAndNamed : Prop :=
  ∀ (x : Ctx) cs pushes b m, Word.ownerLand m ∈ (words x cs pushes b).1 → m.approves = true →
    ∃ c ∈ cs, c.login = x.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      footer c.body.toList = false ∧ m.said = 2 * c.id ∧ onlyWords c.body.toList = true ∧
      ∃ arg, arg ≠ [] ∧ ownerLines c.body.toList = .ok [.land arg] ∧
        resolve x.known arg = some m.about
def TypedCommentIsAWord : Prop :=
  ∀ (x : Ctx) cs pushes b (c : Comment), c ∈ cs → typed x c = true →
    ∃ w ∈ (words x cs pushes b).1, w.byOwner = true ∧ 2 * c.id ≤ w.said

-- Snapshot. `obs` adds one `ownerSpoke` after every word when the owner spoke on a review route (a
-- review or review comment with no footer, as `unanswered` reads them) in the approval's second or later.
/-- A merge of a kept path traces to one comment the owner typed: only the line `/land <commit>`,
unedited, naming a commit `carry` reaches, with nothing typed by the owner after it. -/
def KeptMergeIsTheOwnersTypedApproval : Prop :=
  ∀ g p r x q h e, Land.next q = some (e, obs g p r x) → Land.plan q = .merge p.number h →
    (obs g p r x).kept = true →
    ∃ c ∈ r.comments.getD [], c.login = g.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      Speech.footer c.body.toList = false ∧ Speech.onlyWords c.body.toList = true ∧
      (∃ arg s, arg ≠ [] ∧ Speech.ownerLines c.body.toList = .ok [.land arg] ∧
        Speech.resolve (ctx g p r).known arg = some s ∧ (obs g p r x).carries s = true) ∧
      (∀ d ∈ r.comments.getD [], Speech.typed (ctx g p r) d = true → d.id ≤ c.id) ∧
      ∀ s ∈ reviewPosts r, speaks g s = true → s.created < c.created
```

- **No statement text changes** in `Land` (1 to 14), `Speech` or `Snapshot`. The texts were compared mechanically. The definitions under them that change are `Mark`, `Word`, `newestOwner`, `Obs.entries`, `Plan` and `plan`, and in the reader `Read`, `ownerRead`, `Read.word` and the `words` of `Snapshot.obs`. `newestOwner` gives the same answer on every word list that exists today.
- **Expected values that change.** In `Land`, `afterPushNothingIsPushedAgain` goes from `.idle` to `.merge 153 "ar"`, and its "no second push" half stays as a fixture on the head whose `gate` still runs. In `Speech`, 10 reads gain the flag and 10 change from ignored to `spoke`. In `Snapshot`, the fixtures' base comment is a bare `/land` on `gate/Main.lean`, so it gains the commit.

Section 5, the `Speech` and `Snapshot` cases and the JSON cases:

`eval/cheats` is the corpus of proof cheats against the core gate, so no land case goes there. Land cases are `Fixture` theorems (`decide +kernel`, checked by the build) and the JSON cases of the `gate/*-test.sh` scripts.

**`Speech`, built (19 new), from comment text to the plan.**

- **Reject:** `appPostedApprovalIsNotMerged`, `cursorAppPostedApprovalIsNotMerged`, `footerApprovalIsNotMerged`, `editedApprovalIsNotMerged`, `typedBareLandOnAKeptPathIsNotMerged`, `approvalWithOtherTextIsNotMerged`, `approvalOfAnOlderCommitIsNotMerged`, `holdAfterTheApprovalIsNotMerged`, `laterTypedCommentRetiresTheApproval`, `laterTypedCommentDoesNotLiftAHold`.
- **Accept:** `typedApprovalOnAKeptPathIsMerged`, `approvalTypedAgainIsMerged`, `laterAgentPostDoesNotRetireTheApproval`.

**`Snapshot`, evaluated here through `obs` and `plan` (11 cases, to write as fixtures).** A typed approval on a trust path merges. An owner's review comment after the approval stops it even after an agent answered it, and so does one in the approval's own second. One before the approval leaves it, and a new approval typed after it merges. A bare `/land`, an app-posted approval, a later typed comment that an agent answered, and a spec path without the label each merge nothing. With the label the spec path merges. An agent's later post retires nothing.

**To write.**

- **JSON cases.** The snapshot's JSON carries `approves` and `ownerSpoke`, and an absent `approves` reads false. One case runs a later typed comment through `snapshot` and then `land` and expects `idle`, because a printer that dropped `ownerSpoke` would fail open. A spec path without the label gives `rest = false`. `/land <commit>` in a review gives no word.

## Done when
- [ ] the three statements proved; the 19 `Speech` and 10 `Snapshot` statements keep their text
- [ ] `lake build` passes: 125 `Speech` fixtures, the Snapshot fixtures with the 11 new cases
- [ ] the JSON cases pass in `speech-test.sh`, `snapshot-test.sh` and `land-test.sh`
- [ ] the PR body lists each expected value that changed
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
