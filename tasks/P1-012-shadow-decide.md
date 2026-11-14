# tasks/P1-012-shadow-decide.md

phase: 1
goal: A keyless `decide` job on `main` leaves one record per run, and a report on #191 compares its decisions with what merged and states its run time.
statement: none locked (tooling task); the scorer's own statements are under Design, statements
touches: PR 1 (the recorder): .github/workflows/land.yml, .github/scripts/land-decide.sh, .github/scripts/land-decide.test.sh, .github/workflows/ci.yml · PR 2 (the scorer): gate/MitosGate/Shadow.lean, gate/MitosGate/ShadowCli.lean, gate/MitosGate/LandCli.lean (one public `read`), gate/Main.lean, gate/shadow-fetch.sh, gate/shadow-fixtures/, gate/shadow-test.sh · both: this file, ops/runs/
must_not_touch: statements.lock, models.lock, gate/MitosGate/Land.lean, gate/MitosGate/Speech*, gate/MitosGate/Snapshot*, gate/snapshot-fetch.sh, eval/cheats/, models, .github/workflows/update-prs.yml, .github/scripts/rebase-prs.sh
checks: build, the axiom check (standard axioms only), actionlint, shellcheck, land-decide.test.sh, every gate/*-test.sh, cheats (in ci)
budget: PR 1 10 iterations · 3h wall · 1M tokens; PR 2 20 iterations · 6h wall · 2M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P1-012 in `plan/phase-1.md` (Land track), issue #191: step 3 of the land / auto-rebase
  migration, tracker #179. Proof it works: its plan compared with what merged, and its run time.
- The migration's design: #178, comment 6821317899 and its amendment 6832011164. The planner
  pushes only the pull request that lands next, so rebase churn stops costing CI runs, paid bot
  reviews and agent tokens.
- Built before this row: step 1 (P1-010, #189, merged as #198: `gate/MitosGate/Land*.lean` and
  `mitos-gate land` over fixed JSON); step 2a (#233, #244: `gate/MitosGate/Speech*.lean` and
  `mitos-gate speech`). Step 2b, the snapshot producer (#246, `Closes #190`), is open and not
  merged, so every part of this design that names it is a contract. The 2a/2b split and its four
  defaults are in #190's comment 6860988056.
- The old updater is `.github/workflows/update-prs.yml`; the root's monitor is
  `.claude/scripts/watch-github.sh`. This row changes neither.
- Design written at plan time (#220): an arena of two runners and a judge; base B ("the record is
  the product"), grafts from A. No second cross-judge ran. The judge type-checked the Lean sketch
  against B's build of #246 (six proofs on the three standard axioms, 12 kernel fixtures pass),
  linted the workflow with actionlint, and ran the recorder through shellcheck and four stub runs
  (decided, refused, skipped, bad event text). Not verified: a run of the recorder against the
  real `mitos-gate snapshot`, and anything in a real workflow run.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build for the recorder (`land.yml`, `land-decide.sh`) and for `Shadow.lean`. Contract only
for `ShadowCli`, `shadow-fetch.sh` and every part that names 2b.

revisit_when: re-check after the P1-011 step 2b PR (#246, Closes #190) merges.

### Usage (caller's view)

The shadow runs by itself. Job `decide` in `land.yml` starts on a move of `main`, a finished
pull-request `ci` run of this repository, a comment from the owner's login on a pull request
(created or edited), or a dispatch on `main`. Its log shows:

```
{"next":null,"plan":{"kind":"idle"}}
snapshot: #237 holds: unread protection
```

It uploads `land-record-<run>-<attempt>` (one JSON line, kept 90 days) and
`land-reads-<run>-<attempt>` (2b's raw reads, kept 7 days).

An agent scores a window:

```
gate/shadow-fetch.sh kitimark/mitos <from-date> <dir>
mitos-gate shadow <dir>
```

```
shadow: 23 merges, 312 records, 2 refused, 4 skipped, 0 drifted
#237 at 5c258d6: agrees. one word away, then present; record 71 s old; 6 updater pushes
#236 at d3e0dff: disagrees. stop notEligible, lacks reviewed; record 12 s old
#231: blind. unseen
merges: agrees 19, waits 1, disagrees 2, other tree 0, blind 1; a word was assumed for 19; no author 3
pushes: the updater started 158 ci runs; the plans name 27 distinct pushes
decide (s): setup 38 (20, p90 61, 170), fetch 15, snapshot 1, decide 0; n=312
runs: mainMoved 32, gateDone 260 (cancelled 118), comment 20; 9 superseded while pending
```

The `pushes` line counts the distinct `push` plans (`pr`, `expect`, `replay`) over the decided
records. It is an estimate of the pushes the planner would make, not a bound: a hold or a new
`main` between a push and its merge costs another push, and `PushIsNotRepeated` only stops the
same push from being planned twice.

The PR owner posts that output on #191. The owner does nothing during the shadow.

### The record (the one data structure)

Only `land-decide.sh` writes it, and only `ShadowCli.run?` parses it.

```
{"v":1,"trigger":{"kind":"mainMoved"|"gateDone","head","conclusion"|"comment","pr","id"|"dispatch"},
 "read":"<UTC, end of the reads>","main":"<sha read>","tool":"<sha built>",
 "cost":{"setup","fetch","snapshot","decide","reads"},"unread":["<2b's failed-read lines, verbatim>"],
 "outcome":{"kind":"decided","snapshot":{"prs":[…]},"decision":{…},"trees":[{"commit","tree"}],"notes":[…]}
          |{"kind":"refused","stage":"fetch|snapshot|land","said":[…]}
          |{"kind":"skipped","remaining":N}}
```

- A refused run exits 1, so it is red. A skipped run (under the REST floor of 300) exits 0.
- `trees` gives the tree of each clean replay, because the replay commit exists only in
  `decide`'s clone.
- A change to the snapshot schema bumps `v`.
- The scorer's folder is written only by `shadow-fetch.sh`: `records/`, `runs.json` (id, event,
  conclusion, times), `merges.json` and `baseline.json`.

types:

```lean
namespace MitosGate.Shadow
inductive Trigger | mainMoved | gateDone (head : Sha) (conclusion : String)
  | comment (pr : Pr) (id : Nat) | dispatch
structure Cost where setup : Nat; fetch : Nat; snapshot : Nat; decide : Nat; reads : Nat
structure TreeOf where commit : Sha; tree : Sha
structure Record where run : Nat; trigger : Trigger; read : Stamp; main : Sha; tool : Sha
  cost : Cost; prs : List Obs; trees : List TreeOf
structure Merge where pr : Pr; time : Stamp; before : Sha; head : Sha; tree : Sha
inductive Clause | updatable | enforced | covered | reviewed | rest
def lacks (o : Obs) : List Clause
def observer : Teammate := ⟨"shadow", "observer"⟩
def withWord (said : Nat) (o : Obs) : Obs
inductive Reading | asRead (step : Step) | oneWordAway (after : Step)
def reading (os : List Obs) (o : Obs) : Reading
inductive Head | same | replayedAsPlanned | replayedOtherwise | other
structure Sat where run : Nat; age : Nat; reading : Reading; lacks : List Clause
  head : Head; authorKnown : Bool; updaterPushes : Nat
inductive Seat | unseen | unlisted (run : Nat) | sat (s : Sat)
def last (m : Merge) : List Record → Option Record
def seat (m : Merge) (rs : List Record) : Seat
inductive Finding | agrees | waits | disagrees (why : Stop) | otherTree | blind
def finding : Seat → Finding
structure Tally where agrees : Nat; waits : Nat; disagrees : Nat; otherTree : Nat; blind : Nat
  assumed : Nat; noAuthor : Nat; updaterPushes : Nat
def tally (ms : List Merge) (rs : List Record) : Tally
structure Spread where n : Nat; min : Nat; median : Nat; p90 : Nat; max : Nat
end MitosGate.Shadow

-- contract only
def LandCli.read : String → Except String Snapshot          -- parse and check; `run` then uses it
inductive ShadowCli.Stage | fetch | snapshot | land
inductive ShadowCli.Run | decided (r : Shadow.Record)
  | refused (t : Shadow.Trigger) (s : Stage) | skipped (t : Shadow.Trigger) (remaining : Nat)
def ShadowCli.run? (j : Json) : Except String Run            -- not implemented; refuses v ≠ 1
def ShadowCli.cli (args : List String) (usage : String) : IO UInt32   -- not implemented
```

`run?` counts a record as drifted when `LandCli.run` on its snapshot does not give the decision it
printed. Drifted records are listed and not scored.

statements: proved in the sketch, standard axioms only.

| Statement | Says |
|---|---|
| `ReadyIsOneWordFromLanding` | After `stop noEntry`, the owner's newest `/land` about the head is landable. |
| `TheWordIsOnlyAssumedWhenReady` | `oneWordAway` exactly when the as-read step is `stop noEntry`. |
| `LacksNothingIffEligible` | `lacks o = []` iff `eligibleBeforeRebase`. A new clause in `Land` breaks the build. |
| `PairedRecordPrecedesTheMerge` | The paired record read the merge's `before`, no later than the merge, and is the newest such. |
| `AgreesMeansTheMergedContent` | `agrees` only for `present` at the merged head, or `awaitPush` with the merged tree. |
| `TallyCountsEveryMergeOnce` | The five counts sum to the merges. |

Stated and type-checked, not proved: `SeatIgnoresRecordOrder`.

reuse:
- `gate/MitosGate/Land.lean`: `step` (238), `queueOf` (189), `Obs.eligibleBeforeRebase` (130) and
  the statements `PushOnlyNext` (298), `NoEntryNoPush` (303), `PushIsNotRepeated` (314: right
  after its push, the entry stays landable with `base = current`, so that push is not planned
  again; it bounds no pushes per merge), `UnenforcedLandsNothing` (324), `HoldWins` (329),
  `StuckDoesNotBlock` (340), `NextIgnoresListingOrder` (346).
- 2a: `IncompleteReadHolds` and `PositionsAscendingDistinct` (`gate/MitosGate/Speech/Words.lean`,
  61 and 64).
- Printing: `ciLine` (`gate/MitosGate/Util.lean`, 282).
- CI: ci's cache key (`.github/workflows/ci.yml`, 144 to 151), restore only;
  `.github/scripts/install-elan.sh` and `.github/scripts/install-toolchains.sh`.
- Contract only: 2b's `FailedReadHolds`, `EnforcedNeedsProtection` and `OnlyTheOwnerQueues`.

fixtures:
- Kernel (12, all pass in the sketch): `readyBehindIsOneWordFromThePush`,
  `readyOnMainGreenIsOneWordFromPresent`, `aHoldIsReadAsItIs`, `aTypedWordIsReadAsItIs`,
  `newContentIsNotAssumed`, `anotherWordAheadMakesTheAssumedWordWait`,
  `theReplayThatMergedAgrees`, `anotherTreeIsNotAgreement`, `aRecordOfAnotherMainIsUnseen`,
  `aRecordAfterTheMergeIsUnseen`, `theNewestRecordBeforeTheMergeIsUsed`, `aHeldMergeDisagrees`.
- `.github/scripts/land-decide.test.sh` (the real `land`; stubs for the fetch, `snapshot` and
  `gh`):
  - `decided-on-the-land-fixture`: the record's decision equals `mitos-gate land` on
    `gate/land-fixtures/queue.json`.
  - `refused-snapshot-is-red`
  - `unread-main-is-red`
  - `failed-reads-pass-through`: the lines land in `unread` verbatim, and the run exits 0.
  - `rate-floor-skips`
  - `bad-event-text-is-refused`
  - `a-push-plan-records-its-tree`
  - `holds-no-key`: every permission is `read`; no secret, environment or app token; no write
    verb in either script.
  - `filter-pins`: `refs/heads/main`, `repository_owner` and `head_repository.full_name` are
    named; the concurrency group is on the job; no event text sits in a `run:` line.
- `gate/shadow-fixtures/` and `gate/shadow-test.sh`: `record-idle.json` (a real record),
  `record-refused.json`, `record-skipped.json`, `record-v2.json` (refused), and `window/` with its
  expected report. A drifted record is listed and not scored.
- Live: one dispatch run on `main` whose `unread` lists what the workflow token cannot read; a
  comment from another login starts no job; a day-one report over real records.

cut_line: two PRs, each `Part of #191`. The report comment that meets the bar (O2) closes #191.
- PR 1, the recorder (`.github/` only, after 2b merges). It opens the window. It also adds one ci
  step after `lake build` that runs every `gate/*-test.sh` by glob, as its own commit. If a test
  is red on the CI image for a reason outside this row, that commit moves to its own PR under
  #164.
- PR 2, the scorer (`gate/` only, in parallel with PR 1).
- Reports on #191: day one (token reach and run time), then at the bar.

deferrals:
- Into this row:
  - CI wiring of the gate shell tests (from #233 and #246). Today ci runs only
    `gate/lock-header-test.sh` of them.
  - "How often a mixed-model PR gets no author" (#190 default 4) is `Tally.noAuthor`.
  - The design's guess of 200 run-minutes for `decide` is the cost line.
- To P1-014 (#193):
  - the hand-off `{main, pr, expect, tree}` as a job output; it is derivable from `main`,
    `decision.plan` and `trees`;
  - per-PR steps for `report`;
  - retry of a failed read;
  - a `conclusion` filter on `workflow_run`, decided from this row's counts.
- To P1-013 (#192): `wake` replayed over the recorded triggers, and a red `decide` reaching the
  root (the monitor's `ci:` lines cover only `ci.yml`, `.claude/scripts/watch-github.sh` line 88).
- To #245: the protection read, and its other three reader gaps.
- To #200: the Bool split of `Obs`.
- Unchanged: #171 lands before P1-014. #190 default 2's "step 3's report" means the design's
  `report` job; step 3 posts nothing on pull requests.

owner_decisions: O1 to O5. Each has a default that the builder follows until the owner says
otherwise on #191.
- **O1. How does a keyless `decide` read `strict`?** This blocks the comparison now and step 5
  later (`UnenforcedLandsNothing`).
  - Default: the owner adds a ruleset on `main` (the `gate` check, `strict`, no bypass) beside
    the classic rule, and #245's protection item teaches 2b to read `rules/branches/main`. That
    item starts now, as its own PR. The cost window opens with PR 1. The comparison window opens
    at the first record whose `unread` has no protection line.
  - Unknown: whether a read token can see a ruleset's bypass list. Probe this before building.
  - Alternatives: a small separate job that holds a read-only administration key and passes
    `protection.json` to `decide`; or measuring run time only.
- **O2. The bar that clears step 5.** Default:
  - at least 20 merges over at least 3 days of the comparison window;
  - `blind` at most 10%;
  - every `disagrees` and `otherTree` explained as a filed reader gap, a merge ahead of the
    rules, or a hold by design;
  - no `push` plan for a pull request without the owner's typed `/land`;
  - whole-run time with a median of at most 2 min and a p90 of at most 5 min;
  - `skipped` under 5%.
- **O3. A new `land.yml`** where the accepted design named `update-prs.yml`. Default: yes. Step 5
  deletes the old file, and rollback stays a plain revert.
- **O4. The row gains `gate/`.** The plan says "(owner-gated: `.github/`)", and the scorer adds a
  second owner-merged PR under `gate/`. Default: yes, with the plan text unchanged.
- **O5. Typing `/land` during the shadow.** Default: not needed. A typed one is counted as real,
  and it is still a standing entry when step 5 switches.

### Contract only (2b), read at #246 3a7922f

| Needed from 2b | Used for |
|---|---|
| `gate/snapshot-fetch.sh <owner/name> <dashboard> <empty dir>`: GETs only, exit 0, one stderr line per failed read, 6 + 6N reads | `unread`, `cost.reads` |
| `mitos-gate snapshot <dir>`: prints `{"prs":[…]}`, exit 1 on a fatal read, fetches missing commits from `origin` itself | `snapshot`, `notes`, `refused` |
| `<dir>/main.json` `.commit.sha` | `main` |
| The replay commit of `base: clean` is in the clone afterwards | `trees` |
| `LandCli`'s schema with the `event.pr` check, and no public parser yet | `LandCli.read` |
| Which reads the workflow token can make (protection: no; stacks: unknown) | whether any seat is not `held` |

## Rationale

### Problem

Step 3 must show that 2b's reader plus `mitos-gate land` reach the decision the owner reached, and
what one decision costs. Three facts make a printing job useless as proof:
- With no typed `/land`, `plan` is always `idle` (`NoEntryNoPush`).
- The old updater rebases about 20 s after `main` moves, before `decide` reads.
- The workflow token cannot read protection.

The main risk is in neither candidate: the workflow token cannot read protection, so every pull
request reads `held` until that is fixed, and the same read blocks step 5 (O1).

### Facts this design rests on (checked against `main` at 50e0587 and #246 at 3a7922f)

- `step` depends on `me` only through `Obs.mayMerge` (`Land.lean` 133, used in `step` at 249 and
  257), which is true for no one while `Speech.delegates = []` (`Speech/Comment.lean` 23). So the
  scorer decides as `observer`, which is no likely future delegate.
- Metadata cannot ride in the snapshot: every object refuses a key it does not define
  (`LandCli.lean` 54 to 60), and the snapshot takes only `prs`, `me`, `pr` and `event`.
- The cache key above equals ci's, and ci sets `permissions: {}` at the top (`ci.yml` 9); the
  recorder does the same and grants `read` per job.
- The owner-comment grammar lives in `Speech.word?` (`Speech/Comment.lean` 44 to 55), so the
  workflow filters only by login and copies no grammar into YAML.
- Unread protection holds every pull request: `rules/branches/main` returns `[]`, and
  `branches/main` shows `everyone` and `gate` but not `strict`. #246's `complete` needs
  protection, and its `FailedReadHolds` then gives `stop held`.
- The hand-off must name a tree, because a push is of the replay only if it has the tree of
  `replay` (`Land.lean` 208).
- `LandCli.read` is needed: `snapshot` is private (`LandCli.lean` 180) and only `run` is public
  (261). #246 edits the same file.

### Synthesis decision

Base: B. Its record and pure scorer make the comparison a function with statements, which is the
repository's "Lean first" rule, and it was the only candidate whose proof half existed and
checked. A's comparison was a prose TODO in shell, with the pairing and the assumed word in `jq`.

Both candidates converged on these, so they ship as consensus: a new `land.yml`, not a job in
`update-prs.yml`; a job-level concurrency group `land-decide`; restore-only use of ci's cache;
only `main`'s tool, with pull-request heads as git objects only; the assumed word only at
`stop noEntry`; no `wake`, no retry and no paging in the shadow.

Grafts from A:
1. The recorder lives under `.github/scripts/` and lands first as its own PR, so the window opens
   while the scorer is reviewed.
2. The static pins `holds-no-key` and `filter-pins`. Step 5 must edit them to add `apply`, so a
   key never arrives by accident.
3. The REST floor, as a third outcome, `skipped`.
4. The recorder parses no line that 2b printed; `unread` and `notes` are verbatim.
5. The gate shell tests run by glob, not by a hand-kept list.
6. A numeric pass bar with p90.
7. The dashboard number is one `env` value.

The judge's own additions: `noAuthor` (owed by #190 default 4), and the conclusion kept in the
trigger with no filter, so step 5 can choose a filter from counts.

Rejected from B: the `handoff` job output (step 5's interface with no consumer here); a single
PR; scripts under `gate/` for the recorder.

Rejected from A: N+1 `land` calls and a per-PR summary table (the scorer derives each step);
`me = claude/orchestrator`, a likely future delegate; three workflow steps for timing (the record
carries its own cost, so the scorer stays pure); the land and hold words copied into the `if:`;
workflow-level permissions.

### Tradeoffs accepted

- We accept two new Lean modules in `gate/`, in exchange for a comparison that is proved, not
  hand-counted.
- We accept an assumed word, counted on its own line, in exchange for a sample at every merge
  without the owner typing anything.
- We accept a run for every owner-login comment on a pull request, agents' posts included, in
  exchange for no grammar in YAML. This is also step 5's real load.
- We accept self-timed phases in the record, in exchange for a scorer that needs no per-run REST
  call.
- We accept few `replayedAsPlanned` samples, because the old updater usually rebases first.
- We accept public artifacts; they hold only public data.

### Alternatives considered

- A `decide` job inside `update-prs.yml`. It lost because the shared concurrency group and the
  new triggers would change when the old updater runs.
- A printing job compared by hand. It has the smallest surface but proves nothing: each reader
  redoes the pairing, and every line says `idle`.
- Simulating the word at the read boundary. It exercises `Speech` too, but it feeds the decision
  an invented read and needs git objects at scoring time.
- A fabricated protection read in the shadow. It gives comparison data at once, but it puts an
  invented read in the script that step 5 extends.

### Open questions and risks (for the builder to measure)

- Does a job whose `if:` is false stay out of its job-level concurrency group? The "superseded"
  count answers this on day one.
- Can the workflow token read the stacks route? The first run's `unread` shows.
- Is 1,000 REST calls an hour enough at 6 + 6N per run? The floor protects ci, and the report
  prints the peak.
- Does an anonymous `git fetch origin <sha>` work with `persist-credentials: false`? If not,
  persist the read token.
- `otherTree` also catches a stale sample after a content push; the report must explain each one.

### Next implementation step

After #246 merges, re-check the contract table against `main`, then build PR 1 from the linted
workflow and recorder sketch.

## Done when
- [ ] PR 1 merged: a dispatch run of `decide` on `main` leaves a record whose `unread` lists what
      the workflow token cannot read, and a comment from another login starts no job
- [ ] PR 2 merged: `mitos-gate shadow` scores `gate/shadow-fixtures/window/` to its expected report
- [ ] the day-one report on #191 (token reach and run time), then the report at the bar (O2)
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
