# tasks/P1-019b-bare-land.md

phase: 1
goal: A bare `/land`, alone in a comment the owner typed, approves the head the pull request had when the owner commented, on a pull request that does not need `spec-approved`; a pull request that needs `spec-approved` still lands only on `/land <commit>`; every other guard of the land workflow stays.
statement: none locked (`gate/` is not in `statements.lock`); `Speech.ApprovalIsTypedAndPinned` (it replaces `Speech.ApprovalIsTypedAndNamed`), `Speech.PushLikeKinds`, the restated `Snapshot.KeptMergeIsTheOwnersTypedApproval` and the new `Snapshot.SpecMergeNamesItsCommit` are under Design, statements
touches: gate/MitosGate/Speech/Commit.lean (`pushLike`, `PushLikeKinds` and `pushLikeKinds` only), gate/MitosGate/Speech/Comment.lean, gate/MitosGate/Speech/Words.lean, gate/MitosGate/Speech.lean, gate/MitosGate/SpeechCli.lean (the `--no-spec` flag only), gate/Main.lean (the usage text of `speech` only), gate/MitosGate/Snapshot/Obs.lean, gate/MitosGate/Snapshot/Fixtures.lean, gate/MitosGate/Snapshot.lean (the axiom-check list only), gate/MitosGate/Land.lean (one doc comment in its fixture section), gate/MitosGate/LandAnswer.lean (one doc comment), gate/speech-test.sh, gate/snapshot-test.sh, this file (build notes), tasks/P1-020-land-merge-workflow.md (Usage, three table lines and one note, listed under Design, Task text), tasks/P1-019-typed-approval-reader.md and tasks/P1-013-claude-connector.md (one note each), ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, models, .github/, .claude/, .cursor/, CLAUDE.md, docs/process.md, plan/, gate/snapshot-fetch.sh, the rest of gate/MitosGate/Speech/Commit.lean (`headAt`'s body, `stamps`, `latest`, `matching`, `resolve` and the existing proofs), gate/MitosGate/Speech/Syntax.lean, gate/MitosGate/Carry.lean, gate/MitosGate/Shadow/, gate/MitosGate/SnapshotCli.lean, gate/MitosGate/LandCli.lean, gate/MitosGate/Snapshot/Fields.lean, the logic, statements and names of gate/MitosGate/Land.lean and gate/MitosGate/LandAnswer.lean, gate/land-test.sh, tasks/P1-021-land-merge-rules.md, and the goal line and the Real runs section of tasks/P1-020-land-merge-workflow.md (the plan PR already changed them)
checks: lake build (each module's axiom check: no `sorry`, no new axiom), lake exe mitos-lint-test, gate/speech-test.sh, gate/snapshot-test.sh, gate/land-test.sh and every other gate/*-test.sh, shellcheck, runlog, the drift check under Design; cheats and the `land-*.test.sh` files (in ci)
budget: 10 iterations · 4h wall · 1M tokens (#508 gave 8 · 3h · 0.8M before the spec rule of 28 Nov)
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-019b (A2b) in `plan/land.md`. Its issue is #508, which holds the first design and
  the owner's calls. The tracker is #179. The row amends P1-019's reader (#296, closed) and is
  part of #297, because it must merge before P1-020's real runs R1 to R16.
- The owner's calls:
  - **19 Nov.** A bare `/land` approves the PR head that was current when the owner commented
    (#508, Goal).
  - **28 Nov.** "accept the picks"
    (https://github.com/kitimark/mitos/issues/508#issuecomment-7241070778). It accepts the three
    picks of the catch-up of 19 Nov
    (https://github.com/kitimark/mitos/issues/508#issuecomment-7004617788): the plan row
    `P1-019b`; catch-ups keep the full `/land <head>` line, with a note that a bare `/land` also
    works; and a pull request that needs `spec-approved` keeps the named form.
- **This file is the design the builder follows.** #508's text was written before the third pick
  and was checked against `main` at 1daa433. This file adds that pick, folds in #508's review
  notes, and was checked again against `main` at 2e330cd. Since then `main` moved to f43fa1e
  (#601), which changes `gate/Main.lean` above the usage line of `speech` and
  `gate/lock-reach-test.sh`, so every line named here is the same there. Where this file and #508
  differ, this file wins.
- Who builds: a Claude agent on Fable, in one PR from the latest `main`, as the record on #508
  says (https://github.com/kitimark/mitos/issues/508#issuecomment-7241097603). That replaces
  #508's "an outside agent such as Codex" and its "no `fable` model". The PR touches `gate/`, so
  it is trust-critical and the owner merges it. Its body says `Closes #508`, `Part of #297` and
  `Part of #179`.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. The sketch below type-checks on a scratch copy of `main` at 2e330cd, the spec rule
included, and every fixture is named with its value. What was built there and what was not is
under "What was type-checked".

revisit_when: re-check after #599 merges. It changes `LandAnswer.lean`, `Snapshot.lean`'s list,
`Snapshot/Fixtures.lean`, `gate/snapshot-test.sh` and P1-020's task file, so the lines named here
move, and its `held` answer gets new words (Report texts). Re-check the line numbers also after
#612 (`Land.lean`, `Snapshot.lean`, `snapshot-test.sh`), #618 (`gate/Main.lean`) and #593
(`tasks/P1-013-claude-connector.md`) merge. None of them changes the reader.

modules: no new file. Each file keeps its one topic, and the numbers are the sketch's added lines.
- `gate/MitosGate/Speech/Commit.lean`: commits and heads. `pushLike` names `pr_merge`, and
  `PushLikeKinds` pins the four kinds. About 9 lines.
- `gate/MitosGate/Speech/Comment.lean`: the reading of one comment. `Ctx.requiresSpec`, the
  approval condition at line 143, `ownerRead_land` and the new lemma `target_pinned`. About 11
  lines.
- `gate/MitosGate/Speech/Words.lean`: the words of a conversation. `ApprovalIsTypedAndPinned` and
  its proof. About 12 lines.
- `gate/MitosGate/Speech.lean`: the reader's fixtures and its axiom-check list. About 58 lines.
- `gate/MitosGate/SpeechCli.lean` and `gate/Main.lean`: the `speech` subcommand's `--no-spec`
  flag and its usage text. About 10 lines.
- `gate/MitosGate/Snapshot/Obs.lean`: the observation. `ctx` sets `requiresSpec`,
  `KeptMergeIsTheOwnersTypedApproval` is restated, and `SpecMergeNamesItsCommit` is new. About 26
  lines.
- `gate/MitosGate/Snapshot/Fixtures.lean`: end-to-end fixtures. About 58 lines.
- `gate/MitosGate/Snapshot.lean`: the axiom-check list gains one name.
- `gate/MitosGate/Land.lean` and `gate/MitosGate/LandAnswer.lean`: one doc comment each, and no
  logic.
- `gate/speech-test.sh` and `gate/snapshot-test.sh`: the JSON cases of the two subcommands.

### Problem

Today the owner approves a land merge on a kept path by commenting `/land <full head sha>` alone.
A bare `/land` there gets only a bot reply with the line to copy. The owner asked that a bare
`/land` approve the head that was current when they commented, and later ruled that a pull request
that needs `spec-approved` keeps the named form.

The reader already resolves a bare `/land` to the head of its comment's time, on kept paths too:
`target` sends an empty argument to `headAt pushes c.created`
(`gate/MitosGate/Speech/Comment.lean:69-72`). The only thing that stops it from approving is the
`decide (arg ≠ [])` conjunct at `Comment.lean:143`. So the change is small. That conjunct becomes
"named, or the pull request does not need `spec-approved`". `headAt` counts a merge into the
branch as a push. Two statements that said "named" are restated, and one statement is added for
spec pull requests. Every fixture and test that pinned the old rule is updated. `decide` reads
nothing new. No answer kind and no answer text is added.

### Usage (caller's view)

The owner comments, alone in a comment on the pull request:

```
/land
```

It approves the head the pull request had just before the second the comment was created. That
is the latest push before the comment, however old, including one the owner's open page does not
show yet. Within minutes `github-actions` answers, and the merge follows `gate` on `main`'s tip:

```
<!-- land-report -->
Landed <head> on your /land. main is <sha>.
```

`/land <head>` alone works as before and approves that commit. It is the strict choice when an
agent may still be pushing, and it is the only form that approves a pull request that needs
`spec-approved`. A bare `/land` on such a pull request, and a `/land` with other text on any kept
path, get the line to type, as today:

````
<!-- land-report -->
This PR touches a path you keep. To approve and merge it, comment only this line:

```
/land <head>
```
````

The tool shows the same thing. `speech` is told whether the pull request changes a spec path, and
`snapshot` works that out from the files it read:

```
$ mitos-gate speech --owner owner --pr 7 --pushes pushes.tsv --no-spec comments.json
112 ownerLand@224 <head> approves
$ mitos-gate speech --owner owner --pr 7 --pushes pushes.tsv comments.json
112 ownerLand@224 <head> land
$ mitos-gate snapshot <reads> | jq -c '.prs[] | select(.pr == 9) | .words'
[{"about":"<head>","approves":true,"kind":"ownerLand","said":18002}]
```

A real case, read over REST on 28 Nov. On #599 the owner typed a bare `/land` at 15:09:49Z. The
newest event on the branch before that second is a `force_push` at 14:29:41Z whose `after` is
742b628. Today the word is `unnamed`, and the answer names 742b628. After this row the same word
approves 742b628, the commit that answer asks the owner to type.

### Semantics

A comment is an approving bare `/land` when all of these hold.

- The owner typed it. That is the owner's login, no `performed_via_github_app`, no agent footer,
  and `created_at` equal to `updated_at`.
- It has no `mitos-protocol` fence and nothing that `doubt` flags (a `/hold` line, a backtick,
  `<`, a fence marker, an unquoted `[` or a quote continuation).
- Every non-blank line is that one `/land`, with no argument. `onlyWords`
  (`Comment.lean:126-127`) checks every line, so `"    note\n/land"` does not approve. Up to 3
  leading spaces, one leading byte-order mark and trailing spaces or tabs are allowed.
- The pull request does not need `spec-approved`. That means its files were read and none is a
  spec path: `(r.files.map (·.any specPath)).getD true = false`, the expression that `rest` and
  `handoff` already use (`gate/MitosGate/Snapshot/Fields.lean:142-149`,
  `gate/MitosGate/LandAnswer.lean:85`). This is the owner's call of 28 Nov.

It approves `headAt activity created_at`, the reader's existing rule
(`gate/MitosGate/Speech/Commit.lean:19-31`), with one change in step 3.

1. If any activity stamp does not parse, there is no head.
2. If any listed event falls in the comment's own second, there is no head (`SameSecondUnknown`).
3. Otherwise take the events strictly before that second, at the latest such second. All of them
   must be `push`, `force_push`, `branch_creation` or `pr_merge`, and all must agree on a 40-hex
   `after`. That `after` is the approved commit. A `pr_merge` is a pull request merged into this
   PR's branch, as #455 was into #336's branch. Its `after` is the branch's new tip, so it counts
   like a push. It is new in this row.
4. In every other case there is no head.

No head reads as `.hold .noHead`, so the owner word is `held`, as today.

Everything after the reader is unchanged and still binds.

- The comment must be the owner's newest decisive word, with no later owner comment or review
  post (`spokeSince`, `spokeInReview`).
- `carries` must reach the approved commit from the live head. Only `force_push` events by
  `mitos-pr-updater[bot]` may lie between them, each continuing from the commit the one before it
  left, and the content ids must be equal. So any other push or merge into the branch after the
  comment, whether the owner's, an agent's under the owner's login or anyone else's, makes the
  approval `stale` until the owner types a new word.
- `covered`, `reviewed`, `gate == success`, `rest` (which needs the `spec-approved` label where
  the diff needs it), `updatable`, `enforced`, not stuck and a current base all hold at the merged
  head.
- `apply` re-reads the PR and requires the planned head and an equal digest. It checks that the
  approval comment is the owner's, with no app, unedited (`.github/scripts/land-apply.sh:60-63`).
  It does not look for the footer, which the reader already refused. Then it makes one `PUT` with
  `sha=`.

The other forms.

- `/land <7 to 40 lower-case hex>` works as today, on every pull request. A unique prefix of 7 or
  more resolves among the activity commits, and 40 characters stand for themselves.
- A `/land`, bare or named, with any other text in the comment still does not approve. On a kept
  path its word is still `unnamed`.
- A bare `/land` on a pull request that needs `spec-approved` reads as it does today:
  `approves: false`, and on a kept path the word `unnamed`. Like any newer owner word, it
  supersedes an earlier `/land <commit>`, so the owner types the named line again.
- Off kept paths a bare `/land` already enters (`gate/MitosGate/Land.lean:210`). Its word now
  prints `approves: true`. One decision changes there too. A bare `/land` whose latest earlier
  event is a `pr_merge` held before and now pins that merge's tip.

### Synthesis decision

#508 records how its design was made. One reader mapped `main`. Two designers wrote competing
designs, one for the smallest change and one that tried to merge a head the owner never saw. A
judge merged them. An adversarial review then found one blocking error, that a merge into the
branch held every later bare `/land`, and the revision fixed it with `pr_merge`. The spec rule of
28 Nov was designed once, by the author of the plan PR, with no second runner. Its alternatives
are 19 to 26 under Rejected alternatives.

### Lean

Paths and line numbers refer to `main` at 2e330cd. Every line that #508 names under
`gate/MitosGate/` is the same there. The lines it names in `gate/snapshot-test.sh` moved, and
Scripts gives the new ones.

**`gate/MitosGate/Speech/Commit.lean`**

- `pushLike` (line 8) also names `pr_merge`. Only `headAt` and `HeadAtSound` use it. A new
  statement after it pins the kinds.

```lean
def pushLike (k : String) : Bool :=
  k == "push" || k == "force_push" || k == "branch_creation" || k == "pr_merge"

def PushLikeKinds : Prop :=
  ∀ k, pushLike k = true ↔ k = "push" ∨ k = "force_push" ∨ k = "branch_creation" ∨ k = "pr_merge"

theorem pushLikeKinds : PushLikeKinds := by
  intro k
  simp [pushLike, or_assoc]
```

- `HeadAtSound` (51-56) keeps its text and now covers `pr_merge` through `pushLike`. Its proof and
  the `sameSecondUnknown` proof never unfold `pushLike`, and both built unchanged.
- `stamps`, `latest`, `headAt`'s body, `matching` and `resolve` do not change. `Carry.walk` does
  not change, so a `pr_merge` after the comment still makes the approval `stale`.

**`gate/MitosGate/Speech/Comment.lean`**

- `Ctx` (17-21) gains a required field with no default, between `known` and `apps`. Every place
  that builds a `Ctx` must then say it. There are three: `Speech.lean:21`, `SpeechCli.lean:119`
  and `Snapshot/Obs.lean:18`.

```lean
structure Ctx where
  owner : String
  pr : Pr
  known : List Sha
  requiresSpec : Bool
  apps : List (String × String) := Speech.apps
```

- Line 143 becomes

```lean
      | some s => .land s ((decide (arg ≠ []) || !x.requiresSpec) && onlyWords b)
```

- `ownerRead_land` (500-503) ends with
  `a = ((decide (arg ≠ []) || !x.requiresSpec) && onlyWords b)`. Its proof is unchanged.
- A new lemma after `target_named` (518).

```lean
theorem target_pinned {x : Ctx} {pushes : List Carry.Push} {t : Stamp} {arg : List Char}
    {s : Sha} (h : target x pushes t arg = some s) :
    (arg = [] ∧ headAt pushes t = some s) ∨ (arg ≠ [] ∧ resolve x.known arg = some s) := by
  by_cases ha : arg = []
  · subst ha
    exact .inl ⟨rfl, by simpa [target] using h⟩
  · exact .inr ⟨ha, target_named ha h⟩
```

**`gate/MitosGate/Speech/Words.lean`** (80-85, proof 395-403). `ApprovalIsTypedAndNamed` is
renamed `ApprovalIsTypedAndPinned`, because "named" would now be false.

```lean
def ApprovalIsTypedAndPinned : Prop :=
  ∀ (x : Ctx) cs pushes b m, Word.ownerLand m ∈ (words x cs pushes b).1 → m.approves = true →
    ∃ c ∈ cs, c.login = x.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      footer c.body.toList = false ∧ m.said = 2 * c.id ∧ onlyWords c.body.toList = true ∧
      ∃ arg, ownerLines c.body.toList = .ok [.land arg] ∧
        ((arg = [] ∧ x.requiresSpec = false ∧ headAt pushes c.created = some m.about) ∨
          (arg ≠ [] ∧ resolve x.known arg = some m.about))

theorem approvalIsTypedAndPinned : ApprovalIsTypedAndPinned := by
  intro x cs pushes b m hm ha
  obtain ⟨c, hc, ho, hs, hu, hr, hsaid⟩ := ownerLand_read hm
  obtain ⟨arg, hl, ht, hap⟩ := ownerRead_land hr
  rw [ha] at hap
  have hap' := hap.symm
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hap'
  refine ⟨c, hc, ho, hs, hu, ownerLines_footer hl, hsaid, hap'.2, arg, hl, ?_⟩
  rcases target_pinned ht with ⟨he, hh⟩ | hn
  · rcases hap'.1 with hne | hb
    · exact absurd he hne
    · exact .inl ⟨he, hb, hh⟩
  · exact .inr hn
```

**`gate/MitosGate/Speech.lean`.** The axiom-check list (373) names `approvalIsTypedAndPinned` in
place of `approvalIsTypedAndNamed`, and adds `pushLikeKinds`. The fixture context (21) says
`requiresSpec := false`, and `specCtx` is its twin. The fixtures are under `fixtures:` below.

```lean
def ctx : Ctx :=
  { owner := "owner", pr := 7, known := [hC, hB, h0, hA, hB, hA, hC], requiresSpec := false }
def specCtx : Ctx := { ctx with requiresSpec := true }
```

**`gate/MitosGate/SpeechCli.lean` and `gate/Main.lean`.** `speech` reads no files list, so it is
told. Without the flag it reads every pull request as one that needs `spec-approved`, and a bare
`/land` prints `land`. That is the fail-closed side. `--no-spec` says the pull request changes no
spec path. `Args` gains `noSpec : Bool := false`, `parse` gains one case, and the context at line
119 gets `requiresSpec := !noSpec`. The usage line (`gate/Main.lean:83`) and the error text name
the flag. No workflow or script calls `speech` except `gate/speech-test.sh`
(`tasks/P1-019-typed-approval-reader.md:220-221`).

```lean
  | "--no-spec" :: rest, a =>
    if a.noSpec then none else parse rest { a with noSpec := true }
```

**`gate/MitosGate/Snapshot/Obs.lean`**

- `ctx` (18-19) tells the reader. Unread files count as spec, as they do in `rest`.

```lean
def ctx (g : Global) (p : Pull) (r : Reads) : Speech.Ctx :=
  { owner := g.owner, pr := p.number, known := known ((activity p r).getD []),
    requiresSpec := (r.files.map (·.any specPath)).getD true }
```

- `KeptMergeIsTheOwnersTypedApproval` (126) keeps its name. Its approval clause (131-132) becomes

```lean
      (∃ arg s, Speech.ownerLines c.body.toList = .ok [.land arg] ∧
        ((arg = [] ∧ (r.files.map (·.any specPath)).getD true = false ∧
            Speech.headAt ((activity p r).getD []) c.created = some s) ∨
          (arg ≠ [] ∧ Speech.resolve (ctx g p r).known arg = some s)) ∧
        (obs g p r x).carries s = true) ∧
```

  Its proof (161) drops `harg` at lines 172 and 196 and calls `approvalIsTypedAndPinned` at 173.
- A new statement after it, with its proof before `failedReadHolds` (213). Its conclusion is
  P1-019's first one, word for word, under the spec hypothesis.

```lean
def SpecMergeNamesItsCommit : Prop :=
  ∀ g p r x q h e, Land.next q = some (e, obs g p r x) → Land.plan q = .merge p.number h →
    (obs g p r x).kept = true → (r.files.map (·.any specPath)).getD true = true →
    ∃ c ∈ r.comments.getD [], c.login = g.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      Speech.footer c.body.toList = false ∧ Speech.onlyWords c.body.toList = true ∧
      ∃ arg s, arg ≠ [] ∧ Speech.ownerLines c.body.toList = .ok [.land arg] ∧
        Speech.resolve (ctx g p r).known arg = some s ∧ (obs g p r x).carries s = true

theorem specMergeNamesItsCommit : SpecMergeNamesItsCommit := by
  intro g p r x q h e hn hp hk hs
  obtain ⟨c, hc, ho, hsl, hu, hf, hon, ⟨arg, s, hl, hpin, hcar⟩, -⟩ :=
    keptMergeIsTheOwnersTypedApproval g p r x q h e hn hp hk
  rcases hpin with ⟨-, hno, -⟩ | ⟨harg, hres⟩
  · rw [hs] at hno; cases hno
  · exact ⟨c, hc, ho, hsl, hu, hf, hon, arg, s, harg, hl, hres, hcar⟩
```

**`gate/MitosGate/Snapshot.lean`.** The axiom-check list (24) gains `specMergeNamesItsCommit`
after `keptMergeIsTheOwnersTypedApproval`.

**`gate/MitosGate/Land.lean` and `gate/MitosGate/LandAnswer.lean`.** No logic, statement or name
changes. One doc comment in `Land.lean`'s fixture section, on `Fixture.bare` (1660), and one on
`LandAnswer.Fixture.bareOnKept` (197), say what "bare" means in these fixtures since this row. It
is a `/land` the reader does not count as approval: one whose comment holds other text, or a bare
one on a pull request that needs `spec-approved`. The comment in `Land.lean` says that it covers
the whole section, with `laterOwnerCommentRetiresABareLandOffKeptPathsToo` (1728) and
`bareLandAfterAnApprovalStandsForNothing` (1731). The names stay, because P1-018, P1-019 and
P1-020 task text and run logs cite them.

**Not touched.** `Speech/Commit.lean` beyond `pushLike` and `PushLikeKinds`, `Speech/Syntax.lean`,
`SnapshotCli`, `LandCli`, `Snapshot/Fields.lean`, `Carry.lean`, `ContentId` and `Shadow/`.
`SnapshotCli.activityOf` (123-126) already keeps every activity kind, so a `pr_merge` reaches the
reader. The shadow scorer assumes an approving word at `o.head` and never calls the reader.

types: one field, `Speech.Ctx.requiresSpec : Bool`, required. No new type, constructor, answer
kind or wire field. `Read.land s approves` and `Mark.approves` keep their shape, and the snapshot
JSON does not change.

statements:
- `Speech.ApprovalIsTypedAndPinned` replaces `ApprovalIsTypedAndNamed`. An approving owner word
  comes from a typed, unedited, footer-less comment of only word lines, and either
  `arg = [] ∧ x.requiresSpec = false ∧ headAt pushes c.created = some m.about` or
  `arg ≠ [] ∧ resolve x.known arg = some m.about`.
- `Speech.PushLikeKinds` is new. `pushLike` holds for exactly `push`, `force_push`,
  `branch_creation` and `pr_merge`.
- `Snapshot.KeptMergeIsTheOwnersTypedApproval` gains the same bare branch, with the files read and
  no spec path among them, together with `carries s`.
- `Snapshot.SpecMergeNamesItsCommit` is new. A merge that the plan makes of a kept pull request
  that needs `spec-approved` comes from a typed, unedited comment of only word lines that names
  its commit. It is the owner's call of 28 Nov as a theorem.
- `HeadAtSound` keeps its text, and its `pushLike` now includes `pr_merge`. Unchanged and still in
  the axiom checks are `SameSecondUnknown`, `OwnerLandIsTyped`, `ResolveUnique`,
  `ResolveFullSelf`, `FailedReadHolds`, `RestNeedsAnswersAndTheLabel` and `PlannedMergeIsGated`.
- None of them is in `statements.lock`, so the row needs no `spec-approved`.

reuse:
- `Speech.headAt` and `Speech.target`: the head of a bare `/land` is already computed.
- `Snapshot.specPath` and the expression `(r.files.map (·.any specPath)).getD true`: the same
  test that `rest` uses for the label and `handoff` uses for `requiresSpec`. No second list of
  spec paths is written.
- `Land.Obs.entries` and `Obs.word`: on a kept path `approves: false` already means no entry and
  the word `unnamed`.
- `target_named`, `ownerLand_read`, `ownerRead_land` and `ownerLines_footer` in the proofs.

fixtures: all by `decide +kernel`. Line numbers are `main`'s at 2e330cd.

**`Speech.lean` fixtures that flip**

- `indentedUpToThreeSpaces` (115) and `bomThenLandLands` (183) give `.land hC true`.
- `landNamesTheHeadOfItsTime` (231) gives `.land hB true`.
- `bareLandDoesNotApprove` (318) becomes `bareLandAloneApproves`, `.land hC true`.
- `typedBareLandOnAKeptPathIsNotMerged` (332) becomes `typedBareLandOnAKeptPathIsMerged`,
  `.merge 7 hC`.

These keep `false`, because the comment holds other text: `quotedFooterThenLand` (110),
`crlfLand` (113), `blankLineEndsTheQuote` (156), `listLinesBesideALandLand` (189),
`arrowAndComparisonOpenNoQuote` (191) and `unknownSlashWordIsIgnored` (212).

**New `Speech.lean` fixtures, from #508.** "Kept" means `planOf`, whose paths are `CLAUDE.md`.

- `bareLandWithOtherTextDoesNotApprove`. `"approved\n/land"` gives `.land hC false`.
- `bareLandWithOtherTextOnAKeptPathIsNotMerged` gives `.idle`.
- `bareLandWithTrailingBlanksApproves`. `"/land  \n\n"` gives `.land hC true`.
- `bareLandBeforeAPushIsNotMerged`. `typed 105 5 "/land"` gives `.idle`.
- `bareLandBeforeAPushIsStale`. Its word is `.stale`.
- `bareLandBeforeAnUpdaterReplayIsMerged`. Pushes `[⟨true, hB, hC⟩]` and equal ids for hB and hC
  give `.merge 7 hC`.
- `bareLandInAPushSecondIsNotMerged`. `typed 104 4 "/land"` gives `.idle`.
- `bareLandAfterANamedApprovalApprovesItsOwnHead`. `/land a1b2c3d1` at 8 and then `/land` at 12
  give `.merge 7 hC`.
- `landAfterASubPrMergeApprovesItsTip`. With the one event
  `⟨"2026-11-13T12:00:02Z", "pr_merge", "owner", hA, hB⟩` as the pushes,
  `read ctx [..] (typed 105 5 "/land") = .land hB true`.
- `landInASubPrMergesSecondHolds`. The same event at 12:00:05 gives `.hold .noHead`.
- `landAfterAnUnknownEventHolds`. A `merge_queue_merge` event at 12:00:02 gives `.hold .noHead`.

**New `Speech.lean` fixtures, for the spec rule.** Their helpers:

```lean
def keptObs (cs : List Comment) : Obs :=
  { obs (words ctx cs pushes true).1 with paths := some ["CLAUDE.md"] }
def specObs (cs : List Comment) : Obs :=
  { obs (words specCtx cs pushes true).1 with
    paths := some ["statements.lock"],
    verdicts := [⟨1, hC, ⟨"claude", "verifier"⟩, "opus", .pass⟩] }
def specPlanOf (cs : List Comment) : Land.Plan := Land.plan (queueOf [specObs cs])
```

`statements.lock` is a critical path, so `specObs` carries an `opus` pass. Without it nothing
would merge and the two "is merged" and "is not merged" fixtures would not tell the rule apart.

- `bareLandOnASpecPullRequestDoesNotApprove`.
  `read specCtx pushes (typed 112 12 "/land") = .land hC false`.
- `namedLandOnASpecPullRequestApproves`.
  `read specCtx pushes (typed 112 12 "/land c0ffee0") = .land hC true`.
- `bareLandOnASpecPullRequestIsNotMerged`. `specPlanOf [typed 112 12 "/land"] = .idle`.
- `bareLandOnASpecPullRequestIsUnnamed`. `(specObs [typed 112 12 "/land"]).word = .unnamed`.
- `namedLandOnASpecPullRequestIsMerged`.
  `specPlanOf [typed 112 12 "/land c0ffee0"] = .merge 7 hC`.
- `bareLandAfterANamedApprovalOnASpecPullRequestIsNotMerged`.
  `specPlanOf [typed 108 8 "/land c0ffee0", typed 112 12 "/land"] = .idle`.

`keptObs` serves `bareLandBeforeAPushIsStale` and `bareLandBeforeAnUpdaterReplayIsMerged`.

**`Snapshot/Fixtures.lean`**, end to end from the reads through `obs`, `plan` and the word. Their
helpers:

```lean
def bareAt (t : Stamp) : Comment := ⟨900, owner, none, t, t, "/land"⟩
def noted : Comment :=
  ⟨960, owner, some "claude", 20261114080200, 20261114080200, "Noted." ++ footer⟩
def mergedInAt (t : Stamp) : Reads :=
  { withComments [bareAt t] with
    activity := some [⟨"2026-11-14T07:00:36Z", "pr_merge", owner, hA, hB⟩, pushes.getLast!] }
def pushedPull : Pull := { pull with head := hC }
def pushedAfter : Reads :=
  { reads with
    comments := some [bareAt 20261114080000],
    activity := some (⟨"2026-11-14T08:00:30Z", "push", owner, hB, hC⟩ :: pushes),
    reviews := some [{ rabbit with commit := hC }],
    checks := some [{ gateRun with sha := hC }] }
def pushedGit : Git := ⟨[(hC, "id-1"), (hB, "id-1"), (hA, "id-1")], .current⟩
def pushedObs : Obs := obs (withSource (source (head := hC))) pushedPull pushedAfter pushedGit
def labelled : Pull := { pull with labels := ["spec-approved"] }
def onSpec (cs : List Comment) : Reads :=
  { withComments cs with files := some ["examples/acme/models.lock"] }
```

From #508:

- `aBareLandOnATrustPathIsNotMerged` (379) becomes `aBareLandOnATrustPathIsMerged`,
  `planOf (r := withComments [{ land with body := "/land" }]) = .merge 7 hB`.
- `aBareLandWithOtherTextOnATrustPathIsNotMerged`. The body `"approved\n/land"` and the agent's
  answer `noted` give the plan `.idle` and `rest = true`, so only the reading stops it.
- `aBareLandBeforeTheUpdatersReplayIsMerged`. `bareAt 20261114070000`, before the updater's
  07:00:36 force push, gives `.merge 7 hB`.
- `aBareLandBeforeTheUpdatersReplayPinsTheOlderHead`. Its words are
  `[.ownerLand ⟨1800, hA, true⟩]`.
- `aBareLandInTheReplaysSecondHolds`. `bareAt 20261114070036` gives `.stop .held`.
- `aBareLandBeforeAnOwnerPushIsStale`. `pushedObs` has an owner push from hB to hC at 08:00:30,
  after the 08:00:00 comment, with hC's content id equal to hB's, so only the walk can stop it.
  `pushedObs.word = .stale`, its plan is `.idle`, and `pushedObs.eligibleBeforeRebase = true`.
- `aBareLandAfterASubPrMergeIsMerged`. `mergedInAt 20261114080000` replaces the updater's force
  push with a `pr_merge` from hA to hB at 07:00:36, and gives `.merge 7 hB`.
- `aBareLandBeforeASubPrMergeIsStale`. `mergedInAt 20261114070000` gives the word `.stale` and the
  plan `.idle`.
- `aBareLandInASubPrMergesSecondHolds`. `mergedInAt 20261114070036` gives `.stop .held`.

For the spec rule, on `examples/acme/models.lock` with the `spec-approved` label, so `rest` holds
and only the reading stops the bare form:

- `aBareLandOnASpecPathWithTheLabelIsNotMerged`.
  `planOf (p := labelled) (r := onSpec [bareAt 20261114080000]) = .idle`.
- `aBareLandOnASpecPathDoesNotApprove`. Its words are `[.ownerLand ⟨1800, hB, false⟩]`.
- `aBareLandOnASpecPathIsUnnamed`. Its word is `.unnamed`.
- `aNamedLandOnASpecPathWithTheLabelIsMerged`.
  `planOf (p := labelled) (r := onSpec [land]) = .merge 7 hB`.
- `aBareLandAfterANamedApprovalOnASpecPathIsNotMerged`.
  `onSpec [land, { bareAt 20261114080200 with id := 950 }]` gives `.idle`.
- `theReaderIsToldWhetherThePullRequestNeedsTheLabel`. `(ctx g pull reads).requiresSpec = false`,
  `(ctx g labelled (onSpec [land])).requiresSpec = true`, and with `files := none` it is `true`.

**Mutants**

| Mutant | Killed by |
|---|---|
| M1 the condition is `decide (arg ≠ [])` again | `bareLandAloneApproves`, `typedBareLandOnAKeptPathIsMerged`, `landNamesTheHeadOfItsTime`, `landAfterASubPrMergeApprovesItsTip`, `aBareLandOnATrustPathIsMerged`, `aBareLandBeforeTheUpdatersReplayIsMerged` and the three changed `speech-test.sh` lines |
| M2 `.land s true`, dropping `onlyWords` | `bareLandWithOtherTextDoesNotApprove`, `namedLandWithOtherTextDoesNotApprove`, `aBareLandWithOtherTextOnATrustPathIsNotMerged` and the other-text `speech-test.sh` case |
| M3 `target` sends `[]` to the newest listed `after`, ignoring the time | `landNamesTheHeadOfItsTime`, `aBareLandBeforeTheUpdatersReplayPinsTheOlderHead`, `bareLandBeforeAPushIsStale` |
| M4 `headAt` counts the comment's own second | `landInAPushSecondHolds`, `bareLandInAPushSecondIsNotMerged`, `landInASubPrMergesSecondHolds`, `aBareLandInTheReplaysSecondHolds`, `aBareLandInASubPrMergesSecondHolds`, and the `sameSecondUnknown` proof breaks |
| M5 `headAt` drops the `pushLike` test | `landAfterAnUnknownEventHolds` |
| M6 `walk` ignores the updater's actor or kind | `aBareLandBeforeAnOwnerPushIsStale`, `aBareLandBeforeASubPrMergeIsStale` and the existing `Land` stale fixtures |
| M7 `carries` ignores content ids | `aVerdictOnOtherContentDoesNotCarry`, `aHeadWithoutAContentIdMergesNothing` |
| M8 `editHold` dropped | `editedLandHolds`, `editedApprovalIsNotMerged` |
| M9 `SpeechCli` prints `land` for `approves` | `speech-test.sh` |
| M10 `pushLike` drops `pr_merge` | `landAfterASubPrMergeApprovesItsTip`, `aBareLandAfterASubPrMergeIsMerged`, and the `pushLikeKinds` proof breaks |
| M11 the reader drops the spec test (`.land s (onlyWords b)`, #508's first text) | `bareLandOnASpecPullRequestDoesNotApprove`, `bareLandOnASpecPullRequestIsNotMerged`, `bareLandOnASpecPullRequestIsUnnamed`, `aBareLandOnASpecPathWithTheLabelIsNotMerged`, `aBareLandOnASpecPathDoesNotApprove`, the spec cases of both scripts, and the `approvalIsTypedAndPinned` proof breaks |
| M12 `Snapshot.ctx` says `requiresSpec := false` | `aBareLandOnASpecPathWithTheLabelIsNotMerged`, `theReaderIsToldWhetherThePullRequestNeedsTheLabel`, the `snapshot-test.sh` spec case, and the `keptMergeIsTheOwnersTypedApproval` proof breaks |
| M13 `Snapshot.ctx` reads unread files as no spec (`getD false`) | the third part of `theReaderIsToldWhetherThePullRequestNeedsTheLabel`, and the `keptMergeIsTheOwnersTypedApproval` proof breaks |
| M14 the spec test also stops the named form (`!x.requiresSpec && onlyWords b`) | `namedLandOnASpecPullRequestApproves`, `namedLandOnASpecPullRequestIsMerged`, `aNamedLandOnASpecPathWithTheLabelIsMerged`, every existing typed-approval fixture and the named `speech-test.sh` spec case |
| M15 `SpeechCli` ignores `--no-spec`, or reads its absence as no spec | the three changed `speech-test.sh` lines, or its two spec cases |

**Drift check.** Before hand-over, and again at the head the owner merges, the verifier runs the
head's tool and `main`'s tool on one saved reads folder. That folder is the latest `land` run's
`land-reads-<run>-<attempt>` artifact (kept 7 days) or a fresh `gate/snapshot-fetch.sh` run. The
verifier diffs `.prs[].words[].approves` and the plan. The catch-up names every pull request that
flips (Trust argument, item 11).

### Scripts

**`gate/speech-test.sh`** (44 cases on `main`)

- `reads` (line 41) passes `--no-spec`, because its pull request 7 changes no spec path.
- Lines 69, 71 and 79 expect `approves` in place of `land`, with the labels "a bare /land alone
  approves the head of its second" and "a bare /land between two pushes approves the head then".
  Line 87, the CRLF case with `please land`, keeps `land`.
- New case "a bare /land with other text does not approve". `"approved\n/land"` gives
  `112 ownerLand@224 $hC land`.
- New case "a bare /land with trailing blanks approves". `"/land  \n\n"` gives
  `112 ownerLand@224 $hC approves`.
- New case, with no `--no-spec`: "a bare /land does not approve a pull request that needs
  spec-approved". `"/land"` gives `112 ownerLand@224 $hC land`.
- New case, with no `--no-spec`: "a named /land approves a pull request that needs
  spec-approved". `"/land $hC"` gives `112 ownerLand@224 $hC approves`.
- New case "--no-spec twice is a usage error", exit 2 and `^speech needs`.
- The case at line 132, "without --pushes a bare /land has no head", does not change. So the
  script has 49 cases.

**`gate/snapshot-test.sh`** (expected output derived from the code, not yet run)

- Lines 740-748 become "a bare /land on a kept path approves the head of its second, and land
  plans its merge". The expected output is the typed case's at line 734, and `words9` prints
  `"approves":true`.
- New case "a /land with other text on a kept path is unnamed". `said9` with the body
  `"approved\n/land"` plus an app-posted footer answer at 08:01:00, so `rest` holds. The expected
  output is today's line 743, and `words9` prints `"approves":false`.
- New case "a bare /land in its push's second holds". `activity-9.json` gets the timestamp
  08:00:00. The expected `step` is `stop held` and the `word` is `held`.
- New cases beside "a spec path with the label gives rest true" (916-930), where pull request 9
  changes `statements.lock`, has the label and has its base bare `/land`. "a bare /land on a spec
  path does not approve": `words9` prints `"approves":false`, and with `$me9` the `word` is
  `unnamed`. "a named /land on a spec path approves": the comment is `$typed9`, written after
  `files-9.json`, because `said9` resets that file to `gate/Main.lean` (700). `words9` prints
  `"approves":true`.
- The base fixtures (`per_pr`, 90-95) put a bare `/land` on every pull request, on `a.txt` and
  `b.txt`, off kept paths. Their words now print `approves: true`. No test compares that field
  there, and their decisions do not change. The other cases that put pull request 7 or 9 on kept
  files use a typed approval or read only `rest`: line 339 (`source_case` with `gate/Main.lean`
  on pull request 7, whose checks do not read `approves`), line 700 and line 918.

**`gate/land-test.sh`** does not change. Its cases feed `approves: false` directly and stay valid
as "a `/land` that does not approve".

### Workflow

Nothing in `.github/` changes, and `gate/snapshot-fetch.sh` does not change (its activity read is
at 146-147, and it already reads the files). `land-decide.test.sh`, `land-apply.test.sh` and
`land-report.test.sh` feed prebuilt snapshots or answers and never run the reader on a bare body.
`apply` never reads the approval's body, so a handoff from a bare `/land` passes through it the
same way as one from `/land <sha>`. The body stays bound through the digest.

### Report texts

No answer is added, and no string in `LandAnswer.lean` changes.

- `unnamed` now fires on a kept path for a `/land` with other text, and for a bare `/land` on a
  pull request that needs `spec-approved`. It still names the current head, and its line is the
  one such a pull request needs.
- `stale` after a bare `/land` reads `<new> is new content since <the head the comment pinned>.
  After its verdict, comment /land <new>.` So the owner sees which commit their word pinned.
- `queued`, `Landed`, `held` and `spoke` name the head as today. A bare `/land` after a pull
  request merged into the branch approves that merge's tip, like a push.
- A bare `/land` in the same second as a push or a merge into the branch, or with an event of
  another kind as the latest before it, gets the `held` line. That line does not name this cause,
  and its advice to type `/land <head>` works. #599, open, rewords `held` to "Held by your /hold
  or an edited comment. Comment /land <head> to go on." when every read succeeded. That text also
  names a wrong cause for this case, and the same advice works.

### Task text

The plan PR that adds this file already changed these, so the builder leaves them alone.

- `plan/land.md`: row P1-019b, and "`/land` or `/land <commit>`" in rows P1-019 and P1-021 and in
  the paragraph under the table.
- `tasks/P1-020-land-merge-workflow.md`: the goal line, and the Real runs section (its preamble
  and rows R1, R2, R9, R10, R11 and R16; see Changed real runs).
- `tasks/P1-021-land-merge-rules.md`: the goal line, Usage, one `owner_decisions` entry, one note
  under the amendment's section 7, and one Done-when line. Catch-ups keep `/land <full head sha>`
  and add that a bare `/land` also works right after the owner looks at the pull request.

The builder changes these, in the same PR as the code, because they describe behaviour that is
true only once the code merges. Line numbers are `main`'s at 2e330cd, before the plan PR. The plan
PR adds 9 lines to P1-020's Real runs section, so once it merges every line of that file after
1512 is 9 further down (1570 is then 1579).

**`tasks/P1-020-land-merge-workflow.md`**

- Usage (514-538) becomes the text below. Its first code block shows both forms, and its two
  answer blocks stay.

  > The owner comments `/land` alone in a comment on the pull request. It approves the head the
  > pull request had just before the second the comment was created. That is the latest push
  > before the comment, however old, including one the owner's open page does not show yet.
  > `/land <head>` alone approves that commit instead. Type `/land <head>` when an agent may still
  > be pushing, and on a pull request that needs `spec-approved`, where a bare `/land` does not
  > approve. Within minutes `github-actions` answers, and the merge follows `gate` on `main`'s
  > tip. On a kept path, a `/land` with other text in the comment, or a bare `/land` on a pull
  > request that needs `spec-approved`, gets the line to type.

- Section 2's first row (1570) becomes "The approval is the last thing the owner typed on the PR,
  only `/land` (the head just before its second, and not on a PR that needs `spec-approved`) or
  `/land <commit>`, unedited". Its decider cell becomes "Lean 15, 16, `ApprovalIsTypedAndPinned`,
  `SpecMergeNamesItsCommit`, `HeadAtSound`, `PushLikeKinds`".
- The report table row "bare `/land` or other text, on a kept path" (1608) becomes "a `/land` with
  other text, or a bare `/land` on a PR that needs `spec-approved`, on a kept path".
- Section 5 (1624): "A bare `/land` gets the answer." becomes "A bare `/land` merges the head it
  pins, and a `/land` with other text gets the answer."
- One note under Usage. Lines 127, 158, 228, 468, 1133, 1220 and 1772 use "bare" for
  `approves: false`. Since this row that means a `/land` with other text, or a bare one on a pull
  request that needs `spec-approved`.

**`tasks/P1-019-typed-approval-reader.md`.** One note under the table at line 245, and one at its
statements (lines 5, 89, 153 and 264). The bare-word row is superseded by this row,
`ApprovalIsTypedAndNamed` is renamed `ApprovalIsTypedAndPinned`, `headAt` now counts `pr_merge`,
and `Ctx` has `requiresSpec`.

**`tasks/P1-013-claude-connector.md`** (57, 983). Its planned fixture runs the reader on a bare
`/land` on `.claude/scripts/land.sh`. After this row that word approves again, so the fixture
returns to `.present hC` under its first name, `ownerLandOnAKeptPathIsPresentedToTheOrchestrator`.
`.stop .noEntry` now needs a `/land` with other text. Neither name is in `gate/` today, and #192
is open, so the note goes in that file's `revisit_when` (49). #593, open, edits the same file, so
the builder writes the note against whichever of the two merged first.

### Trust argument

1. **What a bare word approves.** By `ApprovalIsTypedAndPinned`, `HeadAtSound` and
   `PushLikeKinds` it is exactly the `after` of the latest push, force push, branch creation or
   merge into the branch strictly before the comment's second. Nothing in that second counts, and
   every event at that latest earlier second must agree.
2. **Later pushes stop it.** A merge needs `carries about` (`PlannedMergeIsGated`,
   `KeptMergeIsTheOwnersTypedApproval`). Any push or merge into the branch after the comment,
   other than an updater replay with equal content, makes the approval `stale` for good.
3. **Readiness binds the merged head.** That head needs its own standing independent verdict (an
   `opus` pass on critical paths), a bot review of its content, a green `gate`, an answered
   conversation, protection, and to be next and not stuck. All of these are evaluated at `o.head`.
4. **A spec pull request keeps two owner actions.** The amendment says "Spec PRs keep two owner
   actions: the label, then the line. A label alone lands nothing, and the line alone lands no
   spec diff" (section 2, quoted in `tasks/P1-020-land-merge-workflow.md`). A label names no
   content. With a bare `/land`, a label put on an early head and a bare word typed later would
   land a spec diff whose commit the owner never named. So the reader does not let a bare `/land`
   approve when the files hold a spec path, and `SpecMergeNamesItsCommit` proves that every merge
   the plan makes of such a kept pull request comes from a comment that names its commit. `rest`
   still needs the label (`RestNeedsAnswersAndTheLabel`).
5. **Equality at merge time.** `apply` re-reads the PR and requires the planned head and an equal
   digest, and GitHub pins `sha=`. A stale read in `decide` cannot merge a head that is no longer
   current.
6. **Reads fail closed.**
   - Unread, out-of-order or lagging activity, whose newest `after` is not the PR head, holds the
     PR (`pushesOk`, `FailedReadHolds`). The next trigger decides again.
   - Unread files count as spec, so a bare `/land` does not approve. Such a pull request is also
     held, because its read is not complete.
   - A push or a merge into the branch in the comment's own second holds.
   - No listed event before the comment holds. A list cut at its old end cannot mislead, because
     a cut drops only the oldest events.
   - A `pr_merge` as the latest event before the comment counts as a push. GitHub writes it when
     it merges a pull request into this PR's branch, and its `after` is the branch's new tip. On
     #336's branch the `pr_merge` at 2026-11-17T13:43:08Z has `after` 29809c6c, which is #455's
     merge commit and the `before` of the next push at 16:25:21Z. Merging into the branch needs
     the same write access as pushing to it.
   - Any other kind as the latest event before the comment holds, such as `merge_queue_merge` or
     a kind GitHub adds later.
   - A push missing from the list breaks either the tip check (hold) or the walk from the live
     head (stale). The one exception returns the branch to the pinned commit, whose content is
     then what was pinned.
7. **No new forgery path.** Typed still means the owner's login, no app and no footer. Anyone who
   can type that can already type `/land <sha>`. An agent that posts a footer-less `/land` with
   the owner's token reads as typed today too. A `pr_merge` gives no one a way to move the branch
   that a push does not already give.
8. **The trust rules hold.** `decide` reads nothing new: the files list that the spec test uses is
   already read for `rest`. `apply` still only re-reads and checks equality.
9. **GitHub's part, not proved.** The activity route lists every push and merge into the branch
   with its server time and real actor, and comment `created_at` and activity `timestamp` agree
   to the second. `carry` already assumes the first (`gate/MitosGate/Carry.lean:30-31`). On #336's
   branch each of the 15 force pushes has an activity time 1 to 2 s before its timeline
   `head_ref_force_pushed` event. So the PR page can show a push up to about 2 s after its
   activity time, which widens the residual below by about 2 s. Those were 15 small force pushes.
   GitHub gives no bound, and a large push or a sync delay could widen the gap. Under the
   one-clock assumption a push after the comment is never read as before it.
10. **The residual, said plainly.** P1-019 rejected a bare word on kept paths because "a fix
    pushed while the owner types would land unseen"
    (`tasks/P1-019-typed-approval-reader.md:245`). The owner has accepted that case. A head pushed
    or merged in before the comment's second that the owner did not look at is approved, however
    old the page the owner read. Item 3 still binds that head. With `/land <sha>` the typed commit
    pins the content, so an agent-written verdict cell lands nothing the owner did not name. With
    a bare `/land` the comment's time pins it, and the independent checks at that head do the
    rest. Today's answer to a bare `/land` names the head at `decide` time, and copying it
    approves that later head, so the copy flow never pinned an earlier head than the bare form
    does. `/land <head>` stays the strict choice for a PR the owner has not just looked at, and
    Usage says so. Spec diffs are outside this residual (item 4).
11. **Activation.** `land.yml` merges today (`LAND_MERGE: 'on'`). After this row merges, a bare
    `/land` alone that the owner typed earlier becomes an approval if it is still the newest
    decisive word on an open kept pull request with no spec path, and still carries. Off kept
    paths, a bare `/land` right after a merge into the branch flips from held to approving. The
    drift check finds both, the catch-up names each pull request that flips, and the owner types
    `/hold` on it or lets it stand. Read over REST on 28 Nov at 15:32 UTC, the open pull requests
    are #593, #599, #605, #612, #613, #616, #618 and #620. #599 has a typed bare `/land` at
    15:09:49Z with no later owner word, so it flips to an approval of 742b628 if it is still open
    and unchanged then. #593 has a bare `/land` at 15:08:21Z and then `/land b7b3780…` at
    15:11:34Z, so its newest word is already a named approval. The other six have no owner
    `/land`.

### Changed real runs

R1 to R16 run only after this row merges. The plan PR wrote these into P1-020's task file.

- **Preamble.** T1 changes no spec path. Each stop case types its `/land` while `gate` still runs
  at that head, a bare `/land` in R9 and `/land <head>` in R4 to R8.
- **R1** is a bare `/land`. The record shows `approves: true`, and `about` is the newest activity
  `after` before the comment's `created_at`.
- **R2** is `merge it` and `/land` on two lines, which an agent then answers so that `rest` holds
  for R1. It gets the unnamed answer once, and no merge.
- **R9** is a bare `/land`, then a push. It is `stale`, and the answer names the head the comment
  pinned.
- **R10** is a bare `/land` right after another merge. When the updater's rebase comes after the
  comment, the approval carries across it with an equal content id. A bare `/land` in the same
  second as the updater's force push reads `held`, with a text that names another cause. A hold
  there is expected, and the owner types again.
- **R11** is unchanged. It is now also the one real merge by the named form.
- **R16** also derives `about` by hand, for each bare word (R1, R9, R10), from the `land-reads`
  artifact's activity times and the comment's `created_at`. It records the gap between each T1
  push's activity time and its timeline event.

R3 to R8 and R12 to R15 are unchanged, and R14 still covers R2 to R9. After R1 and R11 both forms
have merged for real. The named form's `stale` path stays pinned by fixtures and shares `carries`
with the bare form, so no bare twin of R9 is added. That saves one push, one CI run, one CodeRabbit
review and one verdict on T1. No run merges a pull request into T1's branch: the `pr_merge` case
is pinned by fixtures and by the real event on #336's branch. No run types a bare `/land` on a
pull request that needs `spec-approved`: it would need a throwaway spec change with the owner's
label, and the fixtures and the JSON cases of both scripts pin it.

### Costs

- **`decide` reads.** No new route. The activity route is already read per open PR
  (`gate/snapshot-fetch.sh:146-147`), and so are the files. `cost.reads` is unchanged, and R16
  checks it.
- **`decide` runtime.** Unchanged. `headAt` already runs for every bare `/land`, and every `about`
  is already in `abouts`, so its content id is already computed
  (`gate/MitosGate/Snapshot/Obs.lean:76-86`). `pushLike` gains one string comparison, and the spec
  test is one more pass over the files list per pull request.
- **`apply` and `report`.** Unchanged, with no new call.
- **Lean build.** One sandbox run each on a loaded machine, no spread, so not a deciding number.
  #508 measured `Speech.lean` at 122 s on `main`, and 159 s and 147 s with its fixtures. With the
  spec fixtures too it took 166 s. `Snapshot/Fixtures.lean` took about 375 to 412 s over #508's
  three runs.
- **Real runs.** No new run. R2 needs one agent answer.
- **Verification.** An `opus` verifier at `xhigh` at every head, plus the drift check, which is
  one snapshot per tool on one reads folder, run twice.

### What was type-checked

On a scratch copy of `main` at 2e330cd, with Lean 4.35.0 and the build cache of `main`'s tool:

- The whole sketch above, the spec rule included, was applied: `Speech/Commit.lean`,
  `Speech/Comment.lean`, `Speech/Words.lean`, `Speech.lean`, `SpeechCli.lean`,
  `Snapshot/Obs.lean`, `Snapshot/Fixtures.lean` and `Snapshot.lean`'s list.
- `lake build MitosGate.Speech MitosGate.Snapshot.Obs` passed (19 jobs, exit 0). That covers
  `Commit`, `Comment`, `Words`, every `Speech.lean` fixture listed above with the reader's axiom
  check, and `Obs.lean` with the restated statement, `SpecMergeNamesItsCommit` and both proofs.
- Not built by the plan PR's author: the `Snapshot/Fixtures.lean` fixtures, `Snapshot.lean`'s
  axiom check, `SpeechCli` with `--no-spec`, and both scripts. Their values are derived from the
  code. #508's prototypes built its own `Snapshot` fixtures at 1daa433, without the spec rule.
- The mutants were not run. Each "killed by" entry is read from the code.

### Rejected alternatives

1. **A 10-minute quiet window.** A bare `/land` would approve only when no push other than an
   updater rebase reached the branch in the 10 minutes before the comment, and it would approve
   the head of 10 minutes before.
   - It narrows the meaning the owner accepted and brings back the reply they asked to drop
     whenever a push is under 10 minutes old.
   - It refuses a bare "approve now, merge when green" on a head pushed less than 10 minutes
     before.
   - It adds epoch arithmetic, a constant and four statements to trust-critical code.
   - It still approves an 11-minute-old push the owner did not see, so it shrinks the residual and
     does not close it. Item 3 of the trust argument already binds every approved head.
   - It stays one constant away if the real runs or practice show a need.
2. **A timeline read (`head_ref_force_pushed`).** It lists only force pushes, and only the commit
   after, so a plain push is invisible. It adds a read to `decide`. (P1-020 lines 494-499 reject a
   timeline read too, but of review events for #319, not of pushes.)
3. **Commit author or committer dates.** The pusher's client sets them, so they can be forged, and
   they do not mark a push.
4. **Check-run or check-suite times.** They follow CI scheduling, and an app can set them.
5. **Earlier land records** (`record.json` or the reads artifact). They give the head at a read's
   time, not the comment's. They add an artifact read and they expire.
6. **`o.head` at `decide` time.** It would approve pushes made after the comment and break "any
   later push stops it".
7. **Keeping today's reply with the line to copy.** The owner asked to drop it.
8. **Requiring the verdict to predate the comment.** A verdict's order is a counter in the
   provenance record, not a trusted time, and the rule would block "approve now, merge when
   green".
9. **A one-second skew band in `headAt`.** It changes `HeadAtSound` and `SameSecondUnknown` for a
   case of 1 to 2 s that readiness still binds. Revisit if the real runs show a gap beyond that
   measured page lag (R16 records it).
10. **A cutover time**, after which alone a bare word approves. The merge time is unknown at build
    time, and the drift check covers the only exposure.
11. **Keeping a merge into the branch as a hold.** Pull requests do merge into PR branches here.
    #455, opened through the owner's account, merged into #336's branch at 2026-11-17T13:43:09Z.
    With the hold, a bare `/land` typed after such a merge and before any other push would read
    `held`, with a text that blames another cause, and it would never merge until the owner typed
    `/land <head>`, the reply the owner asked to drop. A merge moves the head the same way a push
    does, and `walk` still makes a later merge `stale`. It costs one line in `Commit.lean`, one
    statement and six fixtures.
12. **Naming the no-head cause in the `held` text.** The reason would have to travel through
    `Word.ownerHold` and `OwnerWord`. The case is rare, and the text already says what to type.
13. **Having `unnamed` suggest a bare `/land`.** The named line pins the head the answer shows,
    and on a spec pull request the bare form would not approve.
14. **A new `Line` or `Read` constructor.** `.land []` already models a bare `/land`.
15. **Renaming the `bare*` fixtures in `Land.lean` and `LandAnswer.lean`.** Task text and run logs
    cite those names, so a doc comment defines them instead.
16. **Naming the head in the `Stopped` answers.** It adds a field to two answer kinds and makes
    `report` post again on every open PR with a `Stopped` answer after deploy. Nothing merges on
    those answers, and the page shows the head.
17. **`apply` re-reading activity.** `apply` checks equality only, and the head pin and GitHub's
    409 already stop a moved head.
18. **Counting `merge_queue_merge` too.** No PR branch here has a merge queue, and stacks merge
    through `merge-async` with `direct_merge`. The kind and any kind GitHub adds later stay a
    hold.
19. **The spec rule in `Land.lean`.** `Land` would have to know whether a word was bare. `Mark`
    does not carry that, so the wire format of `words` and `LandCli` would change, and the logic
    of `Land` is outside this row. In the reader the rule is one disjunct, and downstream
    `approves: false` already has the right meaning.
20. **Reading a bare `/land` on a spec pull request as a hold.** Its word would be `held`, whose
    text blames a `/hold`, an edit or a failed read. `unnamed` already carries the line to type,
    and it is what such a comment gets today, so nothing changes for the owner on spec pull
    requests.
21. **A default value for `Ctx.requiresSpec`.** With `false`, a new caller that forgets the field
    approves bare words on spec pull requests. With `true`, the choice is hidden. A required field
    makes each of the three callers say it.
22. **One shared definition for "needs `spec-approved`"**, used by `rest`, `handoff` and `ctx`. It
    would change `Snapshot/Fields.lean` and `LandAnswer.lean` for a rename. The three uses are one
    expression over `specPath`, and #347 and #355 own the path lists.
23. **Deciding it in `apply`.** `apply` checks equality only and never reads the approval's body.
    `decide` would also plan a merge and `report` would announce a landing that `apply` then
    refuses.
24. **Keying the rule on the `spec-approved` label.** A label can sit on any pull request, and it
    does not make a diff spec. `rest` keys on the paths, and so does this.
25. **Making the bare file name `core/Mitos/Core` critical here.** It is the one path that
    `specPath` accepts and `keptPath` does not. Fixing it changes `Land`'s path lists, and
    `pr-state.sh` and `ci-trust.sh` must agree. #347 owns it (see `deferrals`).
26. **`--requires-spec` as the `speech` flag, off by default.** A person who reads a spec pull
    request's comments by hand and forgets the flag would see `approves` where `snapshot` says
    `approves: false`. The default should be the side that approves less.

### Review notes

#508 ends with 12 minor findings of its last review, kept for the build. This file folds each in.

1. Alternative 9 no longer says "sub-second", and trust item 9 says that the 1 to 2 s lag comes
   from 15 small force pushes with no bound from GitHub.
2. Usage says that a bare `/land` approves the latest push before the comment, however old.
3. Semantics says "every non-blank line is that one `/land`".
4. The spec question went to the owner, who ruled on 28 Nov. It is the fourth condition under
   Semantics, trust item 4 and `SpecMergeNamesItsCommit`.
5. The drift check runs before hand-over and again at the head the owner merges.
6. R10 lists the same-second hold as expected.
7. The `carry` assumption is cited at `Carry.lean:30-31`, and the typed case's expected output at
   `snapshot-test.sh:734`.
8. Scripts lists line 339 with lines 700 and 918.
9. Alternative 2 says what P1-020 lines 494-499 reject, and the P1-019 note covers lines 89 and
   264 too.
10. The doc comment in `Land.lean` covers its whole fixture section, lines 1728 and 1731 included.
11. Semantics says that `apply` checks "the owner's, with no app, unedited", and not the footer.
12. A finding about #508's own layout. Nothing to carry.

cut_line: one PR by the builder, `Closes #508`, `Part of #297` and `Part of #179`. It ships the
reader change, the spec rule, the statements, the fixtures, the JSON cases of both scripts and the
task text listed under Task text. It ships no workflow change, no new answer and no rule text. The
plan row, the R-rows and P1-021's catch-up wording shipped in the plan PR. The agent rules
themselves change in P1-021.

deferrals:
- To #347 and #355: a pull request whose only spec path is a file named exactly `core/Mitos/Core`
  is spec for `specPath` and not kept for `keptPath`. Off kept paths any owner `/land` enters, so
  the spec rule does not bind there, and `SpecMergeNamesItsCommit` keeps the `kept` hypothesis.
  Git lists files and `core/Mitos/Core` is a directory, so the case is hard to reach. #347 makes
  that name critical and kept, and then the hypothesis can go.
- To P1-021 (#298): the catch-up rule itself, in `CLAUDE.md` and the skills. Its task file already
  carries the wording.
- From P1-019 (#296): its table row "A bare `/land`, or the line with other text" (line 245),
  whose bare half this row supersedes.
- From P1-013 (#192): the value of its planned fixture for a bare `/land` on a kept path.

owner_decisions:
- **Settled by the owner, 19 Nov:** a bare `/land` approves the PR head that was current when the
  owner commented, and the residual of trust item 10 is accepted (#508).
- **Settled by the owner, 28 Nov** ("accept the picks",
  https://github.com/kitimark/mitos/issues/508#issuecomment-7241070778): the plan row `P1-019b`
  with "`/land` or `/land <commit>`" in rows P1-019 and P1-021; catch-ups keep the full
  `/land <head>` line with a note that a bare `/land` also works; a pull request that needs
  `spec-approved` keeps the named form.
- **Defaults made at plan time, not the owner's rulings:**
  - "Needs `spec-approved`" is read from the files, with the same test as `rest`, and not from the
    label.
  - A bare `/land` on such a pull request reads `approves: false` and gets the `unnamed` answer.
    It is not a hold.
  - The rule lives in the reader, through the required field `Ctx.requiresSpec`.
  - `speech` gets `--no-spec`, and reads a pull request as spec without it.
  - A merge into the branch counts as a push (`pr_merge`), as #508's revision proposed.
  - The builder is a Claude agent on Fable, as the record on #508 says.

## Build notes
The builder writes here what differed from this design, with the reason.

## Done when
- [ ] all `checks` pass locally, and `lake build` runs every module's axiom check
- [ ] no `sorry`, no new axioms
- [ ] every fixture and JSON case under `fixtures:` and Scripts exists with the value given, or
      Build notes says why not
- [ ] the drift check ran at the hand-over head, and the catch-up names every pull request whose
      word or plan flips and says that the check runs again at the head the owner merges
- [ ] it merged before P1-020's real runs R1 to R16
- [ ] run-log record written (ops/runs/)
