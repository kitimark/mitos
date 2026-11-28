# tasks/P2-013-watch-voice.md

phase: 2 (Watch track, #502; milestone 6)
goal: `mitos-gate watch unanswered` lists the owner's unanswered words per thread, read from the three post routes, by land's rule plus the #501 fix (a typed issue comment is words even with a footer, and never answers), and the 8 `Watch/Voice.lean` statements are proved.
statement: none locked (tooling task). Named and audited in `gate/MitosGate/Watch.lean`: the 8 statements of `Watch/Voice.lean`.
touches: gate/MitosGate/Watch/{Time,Voice,Observe}.lean (Time: `Epoch`, `ofStamp`, `ofIso?` only; Observe: the three post readers with `Refused` and `Reading`, and `readJsonFile` only), gate/MitosGate/WatchCli.lean (`unanswered` only, importing `MitosGate.Watch`), gate/MitosGate/Watch.lean (imports of Time, Voice, Observe; the audit), gate/Main.lean (one import, one usage block, the `watch` arm), gate/watch-test.sh (mode 100755), gate/watch-fixtures/posts-336/, docs/process.md (one check-matrix row), tasks/P2-013-watch-voice.md, ops/runs/
must_not_touch: statements.lock, models.lock, core/, eval/cheats/, .github/, every existing gate/ module outside `touches` (imported, never moved or edited), and every path outside `touches` (`tasks/502-watch.md`, must_not_touch)
checks: `lake build`, `lake exe mitos-gate imports`, `lake exe mitos-gate lock --check`, `lake exe mitos-lint-test`, `lake exe mitos-gate cheats` (locally since the row touches `gate/`; it needs `bwrap`), `bash gate/watch-test.sh`, `shellcheck -x gate/watch-test.sh`, `python3 -I .github/scripts/gate-tests.test.py`, `bash .claude/scripts/plan-tasks.test.sh`, `lake exe mitos-gate runlog --head ops/runs`; the results of the upgrade are under Design (checks)
budget: 30 iterations · 2h wall · 1.2M tokens (re-budgeted at the upgrade, see Design, budget; `tasks/502-watch.md` had 50 · 3h · 2M)
escalation: hint → automation → stronger model → pair → split → revisit statement (a statement that looks false gets its counterexample written here and goes to the owner)

## Context
- Plan row P2-013 in `plan/phase-2.md` (Watch track), issue [#562](https://github.com/kitimark/mitos/issues/562). It is PR 2 of `tasks/502-watch/PR-SEQUENCE.md` (Rows). Tracker [#502](https://github.com/kitimark/mitos/issues/502), milestone [Watch: one Lean waiter for GitHub (#502)](https://github.com/kitimark/mitos/milestone/6).
- Waits for: nothing. PR 0 (#580) and PR 0b (#583) are merged. The owner asked on 28 November to start the build with this row.
- Role: PR owner, hard (`opus`, `xhigh`). The row touches `gate/`, so it is trust-critical: it also needs an `opus` verifier at `xhigh` or above, and the owner merges it. `docs/process.md` is owner-kept too.
- The design: `tasks/502-watch.md` (the Design block) and `tasks/502-watch/` (`DESIGN.md` with the owner's questions, `PR-SEQUENCE.md`, `HANDOVER.md`, `REVIEW-LOG.md` and `sketch/`). This file is the row's slice at build depth. Where it differs from those files, this file is right for this row, and Design (deviations) lists each difference.
- The row was built in two steps. The Architect's upgrade wrote the five Lean files and the `watch` arm, with every statement proved. Two reviewers then read that slice, and the build added three fixtures for what they found, `gate/watch-test.sh`, `gate/watch-fixtures/posts-336/` and the `docs/process.md` row. Design (review) says what became of each finding. The `/no-comments` pass then ran over the diff before the first push, and the PR owner took what it accepts (Design, reshape).

## Design
PR 2's slice of `tasks/502-watch.md`; its row in `tasks/502-watch/PR-SEQUENCE.md` sets the files, the gate and the check.
depth: build. The slice type-checks with the repository's toolchain (Lean v4.35.0): `lake build` passes with the five files below and the `watch` arm. Every body is written, the readers and the command included. The 8 statements and the 16 fixtures are proved with no `sorry`, and the audit ran in the build. The unedited sketch of `Watch/Time.lean` (all of it, with its 7 fixtures), of `Watch/Voice.lean` (with its 9 fixtures) and of the audit in `Watch.lean` also elaborates as written. So no change below is an elaboration fix. Each one is a reshape ruling or an addition.
revisit_when: none. PR 0 and PR 0b are merged, which accepts default 8c, and questions 10 to 13 are answered with the recommendations.

### modules

| File | The one topic it owns | Lines as built | Budget for this row | Layout copies |
|---|---|---|---|---|
| `gate/MitosGate/Watch/Time.lean` | epoch seconds on GitHub's clock, and reading the one ISO form (`ofIso?`) | 34 | 50 | `Shadow/Types.lean` |
| `gate/MitosGate/Watch/Voice.lean` | who spoke in a post; `pr-state`'s unanswered rule (land's classes plus #501) | 301 | 320 | `Speech/Comment.lean` |
| `gate/MitosGate/Watch/Observe.lean` | one JSON reader per post route, and the items a reader refuses (`Refused`, `Reading`) | 125 | 160 | the `SnapshotCli` readers, with `SpeechCli`'s reasons |
| `gate/MitosGate/WatchCli.lean` | `watch unanswered`: its flags, its one line of JSON and its exit codes | 102 | 130 | `SpeechCli.lean` |
| `gate/MitosGate/Watch.lean` | imports of the pure modules and their audit (`MitosGate.WatchAudit`) | 41 | 60 | `Snapshot.lean` |
| `gate/Main.lean` | one import, five usage lines, the `watch` arm | +8 | +8 | its other arms |
| `gate/watch-test.sh` | the suite: the `posts-336` cases, the refusals, the usage errors and the audit | 258 | 260 | `gate/speech-test.sh` |
| `gate/watch-fixtures/posts-336/` | the captured posts of #336, the added posts, the expected answers | 7 files, 225 KB | about 225 KB | `gate/shadow-fixtures/` |
| `docs/process.md` | one check-matrix row | 1 row | 1 row | the `main-tool.test.sh` row |

`tasks/502-watch.md` budgets the whole of each Lean file (`Time` 220, `Voice` 420, `Observe` 460, `WatchCli` 500, `Watch` 60). Those stay for the later rows. A file that passes its budget for this row is a deviation the PR body reports.

### types

As they type-check (`gate/MitosGate/Watch/`):

```
structure Epoch where seconds : Nat        -- GitHub's clock; DecidableEq, Repr, LT, LE, both decidable
ofStamp : Speech.Stamp → Epoch             -- ⟨Shadow.Stamp.seconds ⟨t⟩⟩
ofIso?  : String → Option Epoch            -- (Speech.stamp? s.toList).map ofStamp

inductive Place   | issueComment | reviewComment | review
inductive Via     | noKey | null | app (slug : String)     -- noKey: the route has no app key
inductive Speaker | typed | app (slug : String) | untold
structure Said where
  place : Place; id : Nat; thread : Pr; login : String; via : Via
  created : Epoch; updated : Epoch; state : Option String; body : String
Said.speaker : Said → Speaker   -- issueComment with null: typed; any place with app s: app s; else untold
Said.slug    : Said → Option String
structure Excerpt where
  text : String
  ok : ∀ c ∈ text.toList, printable c = true ∨ c = '\\'
squeezeGo : List Char → Bool → List Char
squeeze   : Nat → String → String
Excerpt.of        : String → Excerpt          -- ⟨oneLine (squeeze 120 b), oneLine_printable _⟩
Excerpt.ofStored? : String → Option Excerpt
structure Post where
  place : Place; id : Nat; thread : Pr; speaker : Speaker
  created : Epoch; updated : Epoch; state : Option String; excerpt : Excerpt
Post.of : Said → Post;  Post.edited : Post → Bool
answerApps : List String                      -- Speech.apps.map (·.1)
footer : Said → Bool                          -- Speech.footer p.body.toList
counts : Said → Bool                          -- a review counts when APPROVED, CHANGES_REQUESTED or its body is not empty
words  : Said → Bool                          -- typed: true; else no slug and no footer
answer : (apps : List String) → Said → Bool   -- typed: false; else a slug in apps, or the footer
unansweredIn : (owner : String) → (apps : List String) → List Said → (thread : Pr) → List Nat
unanswered   : (owner : String) → (apps : List String) → List Said → List (Pr × List Nat)

inductive ItemKind | post (place : Place) | close
structure Refused where kind : ItemKind; id : Nat; thread : Option Pr; why : Excerpt
structure Reading (α : Type) where items : List α; refused : List Refused
Field.get, Field.str, Field.nat, Field.text, Field.time, Field.thread : String → Json → Except String _
Field.login : Json → Except String (Option String)   -- none: a null user
located : Json → Except String (List (String × Json))   -- each item with its place, "[page][item]"
collect : Place → (owner : String) → (Json → Except String Pr)
          → (Nat → Pr → Json → Except String (Option Said)) → Json → Except String (Reading Said)
issueComments, reviewComments, reviews : (owner : String) → Json → Except String (Reading Said)
readJsonFile : System.FilePath → IO (Except String Json)

WatchCli.parseUnanswered : List String → UnansweredArgs → Option UnansweredArgs
WatchCli.unansweredJson  : List (Pr × List Nat) → String     -- threads and ids ascending
WatchCli.unanswered      : (owner : String) → UnansweredArgs → IO UInt32
WatchCli.cli             : List String → (usage : String) → IO UInt32
WatchAudit.predicates    : List Name                         -- [] in this row
WatchAudit.auditedStatements : CoreM (Array Name)            -- the audit; Watch.lean runs it with #eval
```

What the readers do, as written and run:
- Every answer is a `gh api --paginate --slurp` answer: a list of one or more pages, each a list of items. Any other shape refuses the whole answer.
- An item of another login is dropped before any other field is read. A null `user` is another login.
- An item whose `user` does not read (no `user` key, or a `user` that is neither null nor an object with a `login`) refuses the whole answer, because such an item cannot be told from the owner's. So does an owner item whose `id` does not read, because a `Refused` item needs an id (`tasks/502-watch.md`, deferrals).
- Any other field of an owner item that does not read makes that item `Refused`, with a reason that starts with its place, such as `[0][3].performed_via_github_app: missing`. The rest of the answer applies.
- An issue comment needs the `performed_via_github_app` key: null reads `Via.null`, an object with a `slug` reads `Via.app`. Both review routes read `Via.noKey` and never look at the key.
- The thread is the number that ends `issue_url` (issue comments) or `pull_request_url` (both review routes).
- Times read through `ofIso?`: `created_at` and `updated_at`, or `submitted_at` twice for a review. A `PENDING` review is skipped. A null `body` reads as empty, as the jq reads it.

What `watch unanswered` does:
- `mitos-gate watch unanswered --owner <login> [--issue-comments <file>] [--review-comments <file>] [--reviews <file>]`. A flag given twice, an unknown flag, a flag with no value, a missing or empty `--owner`: exit 2, with the usage text on stderr.
- It prints one line, `{"<thread>":[ids]}`, threads and ids ascending, `{}` when there is none, and exits 0.
- A route whose flag is left out has no posts, as the sketch has it, so the answer covers only the routes given and a call with no route flag prints `{}`. The caller chooses the routes: P2-014's by-thread call gives two and its full-thread call all three (`tasks/502-watch/sketch/.claude/hooks/pr-state-unanswered.sh`). The suite pins this with a case where leaving out `--reviews` loses an answer.
- A file that cannot be opened prints `watch unanswered: stopped on an I/O error: …` on stderr and exits 1.
- A file that is not UTF-8 or not JSON, a refused answer, and each refused item print one line on stderr through `ciLine` (`watch unanswered: --issue-comments: issue comment 1 is refused: [0][0].performed_via_github_app: missing`). Then it exits 1 with nothing on stdout.
- `watch wait`, `own` and `status` print `watch <verb> is not built yet` on stderr and exit 2.

### statements

Word for word as they type-check, each `def Name : Prop` with `theorem name : Name` beside it in `Watch/Voice.lean`. All 8 are proved.

```
def TypedOnlyFromAnIssueCommentWithNoApp : Prop :=
  ∀ p : Said, p.speaker = .typed ↔ (p.place = .issueComment ∧ p.via = .null)

def ReviewRoutesAreNeverTyped : Prop :=
  ∀ p : Said, p.place ≠ .issueComment → p.speaker ≠ .typed

def TypedIsAlwaysWords : Prop :=
  ∀ (apps : List String) (p : Said), p.speaker = .typed → words p = true ∧ answer apps p = false

def AnAppPostIsNeverWords : Prop :=
  ∀ (apps : List String) (p : Said) s, p.speaker = .app s →
    words p = false ∧ (s ∉ apps → answer apps p = footer p)

def SpeaksAsLandUnlessTyped : Prop :=
  ∀ (g : Snapshot.Global) (p : Said) (l : Snapshot.Post), p.speaker ≠ .typed →
    l.login = g.owner → l.slug = p.slug → l.body = p.body → words p = Snapshot.speaks g l

def AnswersAsLandUnlessTyped : Prop :=
  ∀ (g : Snapshot.Global) (p : Said) (l : Snapshot.Post), p.speaker ≠ .typed →
    l.login = g.owner → l.slug = p.slug → l.body = p.body →
    answer answerApps p = Snapshot.answers g l

def TypedWordsAreListedUntilAnswered : Prop :=
  ∀ (owner : String) (apps : List String) (posts : List Said) (p : Said), p ∈ posts →
    p.login = owner → p.speaker = .typed →
    (∀ q ∈ posts, q.login = owner → q.thread = p.thread → counts q = true → answer apps q = true →
      q.created < p.created) →
    p.id ∈ unansweredIn owner apps posts p.thread

def ExcerptIsOneLine : Prop :=
  ∀ b : String, ∀ c ∈ (Excerpt.of b).text.toList, printable c = true ∨ c = '\\'
```

Each one checked against the written bodies:
- TypedOnlyFromAnIssueCommentWithNoApp: proved by cases on the place and the key. Its only change from the sketch is the constructor's name, `.null` for `.none`.
- ReviewRoutesAreNeverTyped: proved from the first.
- TypedIsAlwaysWords: proved by the first arm of `words` and of `answer`. This is the #501 rule.
- AnAppPostIsNeverWords: proved with `slug_of_app` (a speaker `app s` has the slug `s`).
- SpeaksAsLandUnlessTyped and AnswersAsLandUnlessTyped: proved against `Snapshot.speaks` and `Snapshot.answers` as they are on `main`, the second with `lookup_isSome_eq_contains`. Their premises hold for a real pair, so neither is vacuous.
- TypedWordsAreListedUntilAnswered: proved. The post itself never blocks its premise, because typed words do not answer. `quotedWordsStayUnanswered` is an instance. It gives one direction for typed words only: no statement says that an answered word is hidden, that the owner's words on a review route are listed, or anything about `unanswered`, the function the command prints. Three fixtures and the suite pin those (fixtures, and review, findings 1 and 2).
- ExcerptIsOneLine: proved, by `(Excerpt.of b).ok`. It is true, and its premise is not empty. But it holds for any function into `Excerpt`, because the type carries the proof: the work is where `Excerpt.of` builds the field from `oneLine_printable`. The statement keeps the text of `tasks/502-watch.md`. Whether a later row should state it over the text function instead is an open question for the owner, not a change made here.

No statement is suspect, and none changed meaning.

### reuse

`tasks/502-watch.md` (reuse), as used: `Speech.footer`, `Speech.apps`, `Snapshot.speaks` and `Snapshot.answers` (the two land statements), `Util.oneLine`, `printable` and `oneLine_printable`, `Util.ciLine`, `Speech.stamp?`, `Shadow.Stamp.seconds`, `Base.Text.split` and `parseNat` (the thread number), `Land.Pr`, the `SnapshotCli` reader pattern with `SpeechCli`'s path-prefixed reasons, `SpeechCli.parse`'s shape, and the `Snapshot.lean` audit pattern. `DecideList` is not used: Voice has no sort (reshape).

### fixtures

Decide fixtures, all proved by `decide +kernel` and audited:
- `Watch/Time.lean`, `Fixture`: `readNow`, `readRefusesMillis`. Two `#guard_msgs` examples beside them pin that an `Epoch` has no subtraction and that a `Nat` is not an `Epoch`.
- `Watch/Voice.lean`, `Fixture`: `quotedFooterIsStillTyped`, `quotedFooterIsWordsForPrState` (class 1), `codexWithTheFooterAnswers`, `codexWithoutTheFooterIsNeither` (class 3), `claudeWithoutTheFooterAnswers` (class 2), `reviewReplyIsUntold`, `reviewReplyWithFooterAnswersForPrState`, `aQuotedFooterLineIsNoFooter` and `anotherToolsFooterAnswers` (class 4, both added at the upgrade), `anEmptyCommentedReviewDoesNotCount`, `quotedWordsStayUnanswered`.
- Added at the build, for review findings 1 and 2: `aLaterAnswerHidesWords` (an answer after typed words hides them; a `unansweredIn` that ignores answers fails it), `ownerReviewWordsAreListed` (the owner's words on a review route are listed; a `unansweredIn` that keeps only typed words fails it) and `unansweredIsPerThread` (`unanswered` on two threads gives `[(501, [11]), (512, [17])]`).

File fixture `gate/watch-fixtures/posts-336/`. The answers in the table below were worked out by hand from each added post's class, that is, who posted it, through which app and how its body ends, and `expected.json` and `classes.tsv` were written from that. The tool and the jq then gave the same answers.

Where the input comes from. Three REST reads of pull request #336 (merged on 19 November), each cut down to the keys a reader reads:

```
gh api --paginate --slurp "repos/kitimark/mitos/issues/336/comments?per_page=100"
gh api --paginate --slurp "repos/kitimark/mitos/pulls/336/comments?per_page=100"
gh api --paginate --slurp "repos/kitimark/mitos/pulls/336/reviews?per_page=100"
```

```
# issue-comments.json
jq -c '[.[] | [.[] | {id, user: (.user | if . == null then null else {login} end)} + (if .user.login == "kitimark" then (if has("performed_via_github_app") then {performed_via_github_app: (.performed_via_github_app | if . == null then null else {slug} end)} else {} end) + {created_at, updated_at, issue_url, body} else {} end)]]'
# review-comments.json
jq -c '[.[] | [.[] | {id, user: (.user | if . == null then null else {login} end)} + (if .user.login == "kitimark" then {created_at, updated_at, pull_request_url, body} else {} end)]]'
# reviews.json
jq -c '[.[] | [.[] | {id, user: (.user | if . == null then null else {login} end)} + (if .user.login == "kitimark" then {state, submitted_at, pull_request_url, body} else {} end)]]'
```

An item of another login keeps only `id` and `user.login`, so the capture also shows that such an item is dropped before its other fields are read. Read on 28 November, the capture holds:
- 104 issue comments in two pages. 78 are the owner's: 4 typed (no app, no footer), 24 through `claude` and 50 through `chatgpt-codex-connector`, every one of those 74 with the footer. All 104 carry the app key.
- 67 review comments, 36 the owner's, all with the footer.
- 62 reviews, 36 the owner's, all `COMMENTED` with an empty body.
- No review comment and no review carries the app key, which is what `Via.noKey` assumes.
- The three files come to 167 KB, 46 KB and 8 KB. No body holds a session link.

The files:
- `issue-comments.json`, `review-comments.json`, `reviews.json`: the capture above.
- `added.json`, written by hand: per case and route, the posts that one edited copy adds as one more page. Their ids are 9900000001 to 9900000006, above every captured id, and their times are on 20 November, after every captured post. The test builds each copy with `jq -c --arg c <case> --arg r <route> --slurpfile add added.json '. + [($add[0][$c][$r] // [])]' <route>.json`. The `live` case reads the three captured files as they are.
- `expected.json`, written by hand from the class table, never from the tool's output: per case, the exact object `watch unanswered` must print.
- `classes.tsv`, written by hand: one row per id on which the tool and the jq differ. It is tab-separated with no header, and its columns are the case, the id, the class, what the jq does and what the tool does, the last two `listed` or `not-listed`.
- `jq-7dfd6cb.jq`: the full-thread classifier of `.claude/hooks/pr-state.sh` as on `main` at `7dfd6cb` (the file is the same at `3bdc56a`, and these lines are the same at `7c3afc8`): its lines 288 to 299, with the hook's indent of 8 spaces and the shell quote after `unique` taken off. It is the jq that the Voice note's four classes are measured against, and the copy still runs after P2-014 takes the jq out of the hook.

One edited copy cannot show every class. A typed comment with a footer is an answer for the jq, so it hides every earlier post there. A `claude` post without a footer is an answer here, so it hides every earlier post here. So there is one copy per class, and class 4 has two, one for each direction:

| Case | Added posts (id) | `watch unanswered` | jq | `classes.tsv` |
|---|---|---|---|---|
| `live` | none | `{}` | `[]` | no row |
| `class-1` | a typed issue comment that ends with Claude's footer (9900000001) | `{"336":[9900000001]}` | `[]` | 9900000001, class 1, jq not-listed, lean listed |
| `class-2` | a `claude` issue comment with no footer (9900000002) | `{}` | `[9900000002]` | 9900000002, class 2, jq listed, lean not-listed |
| `class-3` | a typed issue comment (9900000003), then a `chatgpt-codex-connector` issue comment with no footer (9900000004) | `{"336":[9900000003]}` | `[9900000003,9900000004]` | 9900000004, class 3, jq listed, lean not-listed |
| `class-4-quoted` | a review comment whose last line is a quoted Claude footer (9900000005) | `{"336":[9900000005]}` | `[]` | 9900000005, class 4, jq not-listed, lean listed |
| `class-4-other-tool` | a review comment that ends `_Generated by Grok Bot (builder)_` (9900000006) | `{}` | `[9900000006]` | 9900000006, class 4, jq listed, lean not-listed |

In `class-3` the typed comment is listed by both, which shows that the Codex post after it answers nothing.

What `gate/watch-test.sh` checks, in 43 checks (it builds with `lake build mitos-gate`, as `gate/speech-test.sh` does):
- `classes.tsv` has a row for each of the four classes, and each row's case is one the suite runs.
- For each of the six cases, the tool's line equals the case's entry in `expected.json`, byte for byte, with nothing on stderr.
- For each case, the ids the tool lists and the ids `jq-7dfd6cb.jq` lists differ on exactly the rows of that case in `classes.tsv`, each in the direction its row says.
- Refusals, each exit 1 with nothing on stdout and one line on stderr: the owner's issue comment without the app key, among good items (stderr names its id and `[0][1].performed_via_github_app: missing`); an item with no `user` key; the owner's item with no `id`; a time that is not the one ISO form; an answer read without `--slurp`; an object; a file that is not UTF-8; a file that is not JSON; a file that is not there.
- Not refusals, each exit 0: the same item without the key from another login (dropped, and the owner's item beside it is read); a null `user`; a review comment with an app key (read as no key, so it is words); a `PENDING` review (skipped); a `COMMENTED` review with a null body (does not count); an `APPROVED` review with an empty body (counts).
- A review with a footer answers the typed words before its `submitted_at` and not the ones after it. The same call without `--reviews` lists both, since a route with no flag has no posts.
- The output is one line, with threads and ids ascending: two threads, 999 and 1000, with ids given out of order.
- Usage, each exit 2: no `--owner`, an empty `--owner`, a flag twice, an unknown flag, a flag with no value, `watch wait`.
- The audit, see reshape 2: `Watch.olean` exists after the build; a scratch file that imports `MitosGate.Watch` and prints `MitosGate.WatchAudit.auditedStatements` gives exactly the 8 names; and four scratch files that each add one bad declaration under `MitosGate.Watch` fail with the audit's message (a statement with no theorem, a statement in a `variable` section, a private theorem with `sorry`, an `axiom`).

The `docs/process.md` row, in "What runs where", after the `usage-sum.sh` row:

```
| `mitos-gate watch unanswered` lists the owner's unanswered words per thread as land classifies posts, with a typed issue comment as words even with a footer; it refuses an owner item it cannot read; and the Watch audit finds a theorem for every statement | `bash gate/watch-test.sh` | when touching `gate/MitosGate/Watch*` or `gate/watch-*` | ✓ | | yes |
```

The `gate-tests` job runs every `gate/*-test.sh`, so the row needs no change under `.github/`.

### checks

Run at the upgrade, in this order, on a 4-CPU container with the build of `main` at `3bdc56a` copied in:

| Command | Result |
|---|---|
| `lake build` (before any change) | exit 0 in 1.8 s, 697 jobs, nothing rebuilt |
| `lake build` (with the slice) | exit 0, 707 jobs; 39.5 s the first time, of which `Main` 23 s and the link 10 s |
| `lake exe mitos-gate imports` | `0 import violation(s) in core/ and gate/` |
| `lake exe mitos-gate lock --check` | `statements.lock up to date (248 declarations)` |
| `lake exe mitos-lint-test` | `all 269 cases behave as expected`, 49 s |
| `python3 -I .github/scripts/gate-tests.test.py` | `Ran 11 tests`, `OK` (before `gate/watch-test.sh` exists) |
| `lake exe mitos-gate cheats admit` | cannot pass here: `bwrap` is not installed. `GATE 2 sandbox build: FAIL — no judgment`, `error: \`lake comparator\` needs \`bwrap\` to sandbox the code it checks, and it was not found.` The whole corpus runs in CI |
| `.lake/build/bin/mitos-gate watch unanswered --owner kitimark` on the live reads of #336 | `{}`, exit 0; `jq-7dfd6cb.jq` gives `[]` |
| the six `posts-336` cases and 22 reader cases, in a scratch folder | as the tables above say |
| the audit on seven scratch files | the 8 names; each of six bad declarations refused (no theorem, a `variable` section, `sorry`, a private `sorry`, `native_decide`, an `axiom`) |

Run at the build on `main` at `7c3afc8`, and run again by the PR owner after the `/no-comments` pass and the rename (reshape), on the same container, one `lake` command at a time, at the tree first pushed for the PR, on `main` at `2e330cd`. Both runs gave the same results. The run-log counts are those of the second run, since `main` gained two records in between:

| Command | Result |
|---|---|
| `lake build` | exit 0, `Build completed successfully (707 jobs)` |
| `lake exe mitos-gate imports` | `0 import violation(s) in core/ and gate/` |
| `lake exe mitos-gate lock --check` | `statements.lock up to date (248 declarations)` |
| `lake exe mitos-lint-test` | `all 269 cases behave as expected` |
| `bash gate/watch-test.sh` | `43 passed, 0 failed`, in 12 s on a built tree |
| `shellcheck -x gate/watch-test.sh` | no finding, exit 0 |
| `python3 -I .github/scripts/gate-tests.test.py` | `Ran 11 tests`, `OK`, with the suite in place |
| `bash .claude/scripts/plan-tasks.test.sh` | exit 0 |
| `lake exe mitos-gate runlog --head ops/runs`, and with `--base <the merge base's ops/runs>` as CI runs it | `run log OK: 344 file(s), 403 record(s), one per (task, role, attempt)`, exit 0, both ways; the second compares 342 files with the merge base |
| `lake exe mitos-gate cheats` | cannot pass here, exit 1: `bwrap` is not installed. Of its 112 runs of 56 cases, 48 are rejected before the sandbox and the other 64 give `NO-JUDGMENT@2` with ``error: `lake comparator` needs `bwrap` to sandbox the code it checks, and it was not found.`` So 47 cases fail. The corpus runs in CI |
| `cd core && lake check`, and `cd core && lake comparator --paranoid` | cannot run here, exit 2 each: ``error: `lake check` needs `bwrap` to sandbox the code it checks, and it was not found.`` and the same line for `lake comparator`. The row changes no file under `core/` |
| the suite against 17 wrong versions, one at a time: 4 of the fixture folder, 5 of the readers, 4 of the command, 4 of the audit | each one fails at least one check of the suite; the tree was restored and is green |
| `bash gate/<name>-test.sh` for `speech`, `shadow`, `snapshot`, `land`, `carry`, `content-id` and `imports`, the suites nearest the `watch` arm | all pass: 44, 145, 270, 79, 21, 79 and 64 checks |
| the audit over a scratch copy of `Voice.lean` whose proof of TypedIsAlwaysWords is `sorry` | `MitosGate.Watch.typedWordsAreListedUntilAnswered depends on the axiom sorryAx`, exit 1; with the `sorry` taken out again, exit 0 |

Facts about `decide +kernel` on v4.35.0 that `tasks/502-watch.md` left unverified until this elaboration, each tried once on a small example:
- These do not reduce: `String.splitOn`, `String.toNat?`, `String.all`, `List.mergeSort`.
- These do: `toString` of a `Nat`, an `s!` string with a `Nat` in it, `String.intercalate`, `String.join`, `String.ofList`, `String.toList`, `++`, `<` and `==` on strings, `Nat.toDigits`.

### budget

The upgrade proved the 8 statements and 13 fixtures and wrote the readers and the command. It set the rest of the row at 30 iterations · 2h wall · 1.2M tokens, a hard stop as `docs/process.md` says. The build spent part of that on 3 more fixtures, the suite, the fixture folder and the `docs/process.md` row, and its run-log record gives the numbers. The PR, CI and the bot's threads spend the rest.

### cut_line

Row 2 of `tasks/502-watch/PR-SEQUENCE.md`. `ofHttpDate?`, `isoChars`, `iso`, IsoReadsBack and the other readers wait for P2-016. Declared here and first used later: `Post`, `Post.of`, `Post.edited` and `Excerpt.ofStored?` (the sketch's whole `Voice.lean` is this row's), and `ItemKind.close` (the type is as designed; P2-016's `closedPulls` makes the first one).

### deferrals

- The local clock's own type goes to P2-017 (#566), the first row that reads a local clock (`ciHealth`'s `now`, `HeadAge.firstSeen`). See reshape 5. This file cannot edit that row's task file, so the root adds the line to its issue.
- P2-016 (#565) states IsoReadsBack over `e.seconds < 4102444800`, since `Epoch` is a structure.
- Each later Lean row names its predicates in `MitosGate.WatchAudit.predicates` (P2-016: `SafeSegment`). See reshape 1.
- The audit tests a definition's type as it is written (review, finding 3). To P2-016 (#565), which edits the audit's list anyway: reduce the type before the test (`Meta.forallTelescopeReducing`, then `Meta.whnfD` on the body), read `inductive` and `opaque` constants too, and add an aliased `Prop` to the suite's bad declarations. A reviewer ran that change in a scratch file: it found the same 8 statements and refused the three declarations the audit misses today. This file cannot post to that issue, so the root adds the line.
- A named type for the result of one item in `collect` goes to P2-016 (#565), and the name of `Epoch` goes to P2-017 (#566) with the local clock's type. Both are open flags of the `/no-comments` pass (reshape).
- None of `tasks/502-watch.md`'s deferrals moves to or from this row.

### owner_decisions

Questions 1 and 8a (answered yes on 27 November), default 4 (all of it in `gate/`, in `mitos-gate`) and default 8c (no app besides `claude` and `cursor` answers without its footer), accepted with PR 0b's merge. Questions 10 to 13 are answered with the recommendations and change nothing in this row.

### reshape

The five inputs of the `/no-comments` pass over the sketch at 588dc1a (`tasks/502-watch/REVIEW-LOG.md`, Amendment 1), each settled inside `touches`.

1. The audit's statement finder.
   - Ruling: no attribute. The audit takes every definition into `Prop` under `MitosGate.Watch` as one of two things. With no arguments it is a statement and needs a theorem of its type. With arguments it must be named in `MitosGate.WatchAudit.predicates`, or the build fails. A statement written in a `variable` section takes arguments, so it can no longer pass unseen. An attribute needs a module of its own, which is outside `touches`, and a statement nobody tagged would have no check.
   - The code now: `WatchAudit.auditedStatements` in `Watch.lean` does this. `predicates` is empty, and nothing in this slice needs it. It also reads private names (the sketch's finder skipped them, so a private theorem with `sorry` passed), and it fails when it finds no statement. Run against the sketch's audit, the `variable`-section case and the private `sorry` case both passed; against this one, both fail.
   - Its limit: "into `Prop`" is tested on the type as it is written, `Prop` or a function type that ends in `Prop`, and only on a `def`. A definition whose type reaches `Prop` through an abbreviation and an `inductive … : Prop` are not seen, so neither needs a theorem or a place in the list (review, finding 3; deferrals). The axiom check has no such limit: it reads every constant under `MitosGate.Watch`.
   - Deferred: nothing. Later rows add their predicates to the list (deferrals).
2. The audit's build root.
   - Ruling: the audit is a function, `MitosGate.WatchAudit.auditedStatements`, that `Watch.lean` runs with `#eval` and that any file importing `MitosGate.Watch` can run again. `gate/watch-test.sh` runs it itself from a scratch file with `lake env lean <file>`. So the `gate-tests` job runs the audit whatever `WatchCli` imports, with no target in `lakefile.toml`. `lake build +MitosGate.Watch` also builds the module alone, with no lakefile change.
   - The code now: `WatchCli.lean` imports `MitosGate.Watch`, so `lake build` runs the audit too. The audit prints nothing when it passes, because `lake` replays a module's messages on every later run. The scratch run takes under 2 s and prints the 8 names.
   - Deferred: nothing.
3. The names `Via.none` and `Via.absent`.
   - Ruling: `Via.null` (the key is there and null) and `Via.noKey` (the route has no such key).
   - The code now: `inductive Via | noKey | null | app (slug : String)`. TypedOnlyFromAnIssueCommentWithNoApp reads `p.via = .null`. Both review readers give `.noKey`.
   - Deferred: nothing. The sketches of later rows that write `.absent` or `Via.none` take the new names when their rows are upgraded.
4. The second hand-written sort (`insertId`, `sortIds`).
   - Ruling: there is no second sort. `unansweredIn` gives the ids in the order the posts were read, without repeats. Sorting is for the printed line only, so `WatchCli.unansweredJson` orders threads and ids with the library's `Array.qsort`, which no `decide` fixture has to evaluate. `DecideList` is not touched.
   - The code now: `insertId` and `sortIds` are gone. TypedWordsAreListedUntilAnswered is about membership, so its text and meaning are the same, and its proof needs no sort lemma.
   - Deferred: nothing.
5. One `Epoch` type for two clocks.
   - Ruling: `Epoch` is GitHub's clock, and it is a structure, not `Nat`. In this row every `Epoch` comes out of a GitHub answer through `ofIso?`. The local clock gets a structure of its own in the first row that reads one.
   - The code now: `structure Epoch where seconds : Nat`, with order and decidable equality, laid out as `Shadow.Stamp` is. Two `#guard_msgs` examples pin that two epochs do not subtract and that a `Nat` is not an `Epoch`. Fixtures write `⟨10⟩`.
   - Deferred: the local clock's type, to P2-017 (#566). P2-016 keeps `Fixed.serverNow` an `Epoch`.

The `/no-comments` pass over this row's own diff ran before the first push. It deleted 6 comments and trimmed 1, and no code token changed. Two comments stay. One is the note on `reviews` in `Observe.lean`: GitHub gives a pending review no time, and `SnapshotCli.reviewsOf` on `main` carries the same note. The other is the usage text in `WatchCli.lean`, which is the command's contract. The pass raised three flags:
- fixed: `MitosGate.WatchAudit.statements` (`Watch.lean`). The name said that it lists the statements, but it runs the whole audit. It is now `auditedStatements`. No statement changed.
- reshape (no-comments): `collect` (`Watch/Observe.lean`): two rules are only in its body. The first is which failure refuses one item and which refuses the whole answer. The second is that its `said` argument gives `none` for an item that is not a post yet, which only a pending review is. Give the result of one item a named type, such as a post or a draft. Not fixed here: the fix is a new type, which is a shape and not a rename. P2-016 (#565) writes the other readers in this file, so its upgrade sets the type with every caller in view.
- reshape (no-comments): `Epoch` (`Watch/Time.lean`): the name does not say that the type holds only GitHub's clock (ruling 5). Rename it, for example `GitHubTime`. Not fixed here: the row P2-013 in `plan/phase-2.md`, row 2 of `tasks/502-watch/PR-SEQUENCE.md` and the types of later rows in `tasks/502-watch.md` name `Epoch`, and this row may edit none of them. The name is best chosen together with the local clock's type, which ruling 5 sends to P2-017 (#566).

This file cannot edit those rows' task files, so the root adds each open line to its issue, and the PR's follow-up issue lists both.

### review

Two reviewers read the upgrade's slice before the build. Each of their ten findings is minor: none shows a wrong result, a red check or a weakened statement. What the build did with each:
1. TypedWordsAreListedUntilAnswered gives one direction, and two wrong versions of `unansweredIn` pass it: two fixtures added, `aLaterAnswerHidesWords` and `ownerReviewWordsAreListed`, one for each wrong version. The finding's two-way theorems are not added: a new statement is the owner's.
2. No statement or fixture names `unanswered`: one fixture added, `unansweredIsPerThread`. The finding's corollary `typedWordsReachUnanswered` is not added, since it is more than a one-line fix; it is listed for the PR's follow-up issue.
3. The audit tests the written type only: real, and not fixed here, since it is not a one-line fix. Reshape 1 now states the limit, and the fix goes to P2-016 (deferrals).
4. ExcerptIsOneLine holds for every function into `Excerpt`: no change. Restating it is the owner's question (statements).
5. The route flags are optional: kept, because the sketch's by-thread call gives two routes. It is now written under "What `watch unanswered` does" and pinned by a case of the suite.
6. The whole-answer refusal was not among the deviations: added there, and an item with no `user` is in the suite.
7. The `docs/process.md` row was planned in prose: this file now holds the literal row, and `docs/process.md` has it.
8. Lines of this file that the merge would make false: rewritten to the state as built.
9. The layout of `classes.tsv`, where the expected answers come from, and a file that is not there: all three are written above and in the suite.
10. Issue #562 still says "contract only": the root edits the issue. Nothing in the diff changes.

### deviations

From `tasks/502-watch.md` and the files under `tasks/502-watch/`, which this row must not edit. Each line there that is now wrong for this row:
- `Via := absent | none | app slug` (types), "Review comments and reviews read `via := .absent`" (`HANDOVER.md`) and the sketch's `.none` and `.absent`: now `noKey` and `null`. Reason: reshape 3.
- `abbrev Epoch := Nat` in the sketch, and every fixture literal of an epoch: now a structure and `⟨n⟩`. Reason: reshape 5.
- The sketch's `insertId` and `sortIds`, the gloss "(a filter, `eraseDups` and the sort keep membership)" and the lens fix "Decide fixtures use `DecideList.sortStrings` or a local insertion sort": Voice has no sort, and `unansweredIn`'s ids are in reading order. Reason: reshape 4.
- "Every statement is written outside any `variable` section, so its type is exactly `Prop` and the audit sees it" (statements) and "There is no audit list to keep" (`HANDOVER.md`): the audit now enforces the first, and it keeps one list, the predicates, empty here. Reason: reshape 1.
- "`gate/watch-test.sh` checks that `Watch.olean` exists after `lake build mitos-gate`" (lens fixes): it does, and it also runs the audit itself and four bad declarations. Reason: reshape 2. The audit is a `def` in the namespace `MitosGate.WatchAudit`, not a bare `#eval` block.
- The Voice note says each of the four classes has a Voice fixture, but the list of nine had none for class 4. Added: `aQuotedFooterLineIsNoFooter` and `anotherToolsFooterAnswers`.
- `posts-336/` is described as edited copies with one `expected.json` and one `classes.tsv`. It is one capture, six cases, and both files are keyed by case, because one copy cannot show every class (fixtures). It also holds a frozen copy of the jq.
- "taken to run through loops the kernel does not reduce, unverified until PR 2's elaboration" (lens fixes) names `toString` among four helpers: `toString` of a `Nat` does reduce; the other three do not (checks).
- Not in the sketch, whose readers were stubs: `Field.*`, `located` and `collect` in `Observe.lean`, and `placeName`, `kindName` and `unansweredJson` in `WatchCli.lean`. `WatchCli.unanswered` takes the owner as its own argument.
- "An owner item that lacks it, or that it cannot read, becomes a `Refused` entry in the reader's `Reading`, and the rest of the answer applies" (`HANDOVER.md`, Readers): an item whose `user` does not read, and an owner item whose `id` does not read, refuse the whole answer instead. Reason: a `Refused` item needs an id, and an item with no readable `user` cannot be told from the owner's (`tasks/502-watch.md`, deferrals).
- The Voice fixtures are 14, where the sketch has 9: the two of class 4 above, and `aLaterAnswerHidesWords`, `ownerReviewWordsAreListed` and `unansweredIsPerThread`, added at the build. Reason: review, findings 1 and 2.
- The suite checks more than `HANDOVER.md` (Tests) lists: the frozen jq beside every case, an item with no `user`, a file that is not there, a flag with no value, a review that answers by its `submitted_at`, and a route whose flag is left out. Reason: review, findings 5, 6 and 9.
- `Time.lean` imports only `MitosGate.Shadow.Types` in this row. `MitosGate.Base.Text` comes back with P2-016's parsers.

## Done when
- [x] row 2's Check column in `tasks/502-watch/PR-SEQUENCE.md` holds, and all `checks` pass locally, except `cheats`, which cannot run where `bwrap` is missing (Design, checks, has the error text)
- [ ] `cheats` passes in CI, and the PR body carries the local error text
- [x] no `sorry`, no new axioms: `Watch.lean`'s audit ran and found a theorem for every statement, and `gate/watch-test.sh` shows the 8 names and the four refused declarations
- [x] run-log record written (ops/runs/)
