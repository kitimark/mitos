# tasks/P1-012-shadow-decide.md

phase: 1
goal: A keyless `decide` job on `main` leaves one record per run, and a report on #191 compares its decisions with what merged and states its run time.
statement: none locked (tooling task); the scorer's own statements are under Design, statements
touches: PR 1 (the recorder): .github/workflows/land.yml, .github/scripts/land-decide.sh, .github/scripts/land-decide.test.sh, .github/workflows/ci.yml · PR 2 (the scorer): gate/MitosGate/Shadow.lean, gate/MitosGate/Shadow/, gate/MitosGate/ShadowCli.lean, gate/MitosGate/ShadowCli/, gate/MitosGate/LandCli.lean (one public `read`), gate/Main.lean, gate/shadow-fetch.sh, gate/shadow-fixtures/, gate/shadow-test.sh · both: this file, ops/runs/
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
  (decided, refused, skipped, bad event text). Round 2 of #248 pasted the judge's five sketch
  files below and re-checked them against `main` at 4ba56dc: `Shadow.lean`, its proofs and its
  fixtures type-check as pasted, on the same axioms, and actionlint 1.7.12 and shellcheck 0.11.0
  report nothing on the two recorder files. The paste is verbatim except two changes from review:
  `land-decide.sh` reads `main` again after the fetch (`mainAfter`), which orders a record's reads
  against a merge without a clock; and a record pairs with a merge only when its `read` is in an
  earlier second than the merge (`precedes` and `PairedRecordPrecedesTheMerge`), which a 13th
  fixture pins. Not verified: a run of the recorder against the real `mitos-gate snapshot`, and
  anything in a real workflow run.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build for the recorder (`land.yml`, `land-decide.sh`) and for `Shadow.lean`, whose sketches
are below in full. Contract only for `ShadowCli`, `shadow-fetch.sh` and every part that names 2b,
which includes the recorder's two calls into 2b, `gate/snapshot-fetch.sh` and
`mitos-gate snapshot`: `land-decide.test.sh` stubs both, and PR 1's dry run is the one run of the
recorder against the real ones.

revisit_when: none. #246 merged, and PR 1 re-checked the contract table and the facts against
`main` at 31cc93a (Build notes, PR 1).

modules: one topic per file (`.claude/skills/principle-split-by-topic/SKILL.md`). Line counts are
rough budgets.
- PR 1, the recorder (as built):
  - `.github/workflows/land.yml`: when `decide` runs and what it may read; 76 lines; copies the
    `gate` job of `ci.yml` (`permissions: {}` at the top and `read` per job, ci's cache restored,
    `install-elan.sh` and `install-toolchains.sh`).
  - `.github/scripts/land-decide.sh`: one `decide` run as one record; 110 lines; copies
    `gate/snapshot-fetch.sh` (usage header, `die`, exit 2 on usage, `timeout -k 5 120` on each
    `gh api` read).
  - `.github/scripts/land-decide.test.sh`: the recorder's outcomes against stubs, and the static
    pins of `land.yml`; 380 lines; copies `gate/land-test.sh` (`ok` and `bad` counters, one
    summary line).
  - `.github/workflows/ci.yml`: two steps in the `gate` job after `Build core and gate`; copies the
    `cancel-superseded.test.sh` step.
- PR 2, the scorer (as built). Each statement, its proof and its fixtures sit in the file of the
  definition they are about. Build notes, PR 2 says why this split is finer than one `Reading`
  and one `Score` file.
  - `gate/MitosGate/Shadow.lean`: the root, imports and the axiom check only; 20 lines; copies
    `gate/MitosGate/Snapshot.lean`.
  - `gate/MitosGate/Shadow/Types.lean`: what the scorer reads, a record and a merge, and the
    seconds of a stamp; 80 lines; copies `gate/MitosGate/Snapshot/Types.lean`.
  - `gate/MitosGate/Shadow/Lacks.lean`: the eligibility clauses a pull request lacks; 25 lines.
  - `gate/MitosGate/Shadow/Reading.lean`: the assumed word; 140 lines.
  - `gate/MitosGate/Shadow/Seat.lean`: the pairing of a merge with a record; 180 lines.
  - `gate/MitosGate/Shadow/Finding.lean`: the finding at one merge; 70 lines.
  - `gate/MitosGate/Shadow/Tally.lean`: the count of findings over a window; 60 lines.
  - `gate/MitosGate/Shadow/Spread.lean`: how a cost spreads, over runs and over an hour; 60 lines.
  - `gate/MitosGate/ShadowCli/Read.lean`: the folder's JSON, `Run` and `run?`; 150 lines.
  - `gate/MitosGate/ShadowCli/Report.lean`: the report's lines; 130 lines.
  - `gate/MitosGate/ShadowCli.lean`: the command; 75 lines; copies
    `gate/MitosGate/SnapshotCli.lean`.
  - `gate/MitosGate/LandCli.lean`: one public `read`; `run` decides what it returns.
  - `gate/Main.lean`: one usage entry and one dispatch line.
  - `gate/shadow-fetch.sh`: the folder; 120 lines; copies `gate/snapshot-fetch.sh`.
  - `gate/shadow-test.sh` and `gate/shadow-fixtures/`: the command and the fetch, end to end
    over fixed folders and a stub `gh`; 290 lines; copies `gate/snapshot-test.sh`.

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

Only `land-decide.sh` writes it, as one line in `<dir>/record.json`, and only `ShadowCli.run?`
parses it. A decided or refused record has these fields; `TRIGGER` and `OUTCOME` are below.

```
{"v": 1,
 "trigger": TRIGGER,
 "read": "<UTC, YYYY-MM-DDTHH:MM:SSZ, when the reads ended, by the runner's clock>",
 "main": "<40-hex sha from reads/main.json, or \"\" when that read failed>",
 "mainAfter": "<40-hex sha of main read again after all the reads, or \"\" when that read failed>",
 "mainAfterSaid": ["<a stderr line of that read, verbatim>", ..., "<land-decide.sh's own line>"],
 "tool": "<40-hex sha of the clone's HEAD, the tool that was built>",
 "cost": {"setup": <s>, "fetch": <s>, "snapshot": <s>, "decide": <s>,
          "reads": <number of reads that saved a file>},
 "unread": ["<one stderr line of snapshot-fetch.sh per failed read, verbatim>", ...],
 "outcome": OUTCOME}
```

`TRIGGER`, one shape per `Trigger` constructor, from the event that started the job:

| `Trigger` | Event | JSON |
|---|---|---|
| `mainMoved` | `push` to `main` | `{"kind":"mainMoved"}` |
| `gateDone head conclusion` | `workflow_run` of `ci`, completed, for a pull request of this repository | `{"kind":"gateDone","head":"<40-hex sha>","conclusion":"<1 to 32 of a-z and _, such as success or cancelled>"}` |
| `comment pr id` | `issue_comment`, created or edited, by the owner's login on a pull request | `{"kind":"comment","pr":<pull request number>,"id":<comment id>}` |
| `dispatch` | `workflow_dispatch` on `main` | `{"kind":"dispatch"}` |

`OUTCOME`, one shape per `ShadowCli.Run` constructor:

| `Run` | Exit | JSON |
|---|---|---|
| `decided` | 0 | `{"kind":"decided","snapshot":{"prs":[...]},"decision":{"next":...,"plan":...},"trees":[{"commit":"<replay sha>","tree":"<its tree>"}],"notes":["<a stderr line of mitos-gate snapshot, verbatim>"]}` |
| `refused` | 1 | `{"kind":"refused","stage":"fetch"\|"snapshot"\|"land","said":["<a stderr line of that stage, verbatim>"]}` |
| `skipped` | 0 | `{"kind":"skipped","remaining":<REST calls left>}` |

- A run skips when fewer than 300 REST calls are left. Its record has no `main`, `mainAfter`,
  `mainAfterSaid`, `cost` or `unread`, and its `read` is from before any read:

  ```
  {"v":1,"trigger":TRIGGER,"read":"<UTC>","tool":"<sha>","outcome":{"kind":"skipped","remaining":<n>}}
  ```
- A refused run exits 1, so it is red. A record whose `main` is `""` is refused too, at the stage
  the run reached.
- `mainAfter` orders the reads against merges without a clock. `run?` gives a record whose
  `mainAfter` is not its `main` the `main` `""`, so it pairs with no merge: `main` moved while it
  read. The run itself is decided and green.
- `mainAfterSaid` keeps why `mainAfter` is `""`: the stderr lines of `gh api`, then one line of
  `land-decide.sh`, `land-decide: the second read of main exited <code>` (124 when the timeout
  stopped it, 137 when it had to kill it) or `land-decide: the second read of main gave no commit`. It is `[]` when `mainAfter`
  is a commit. `run?` accepts the field and scores nothing from it.
- `trees` gives the tree of each clean replay, because the replay commit exists only in
  `decide`'s clone.
- The line holds no run number. `Record.run` is the `<run>` of the artifact's name, which
  `shadow-fetch.sh` keeps, so `run?` takes it as an argument.
- A change to the snapshot schema bumps `v`.
- The scorer's folder is written only by `shadow-fetch.sh`: `records/`, `runs.json` (id, event,
  conclusion, times), `merges.json` and `baseline.json`.

### The recorder (PR 1 starts from these two files)

Both files below are the judge's sketch, verbatim except that `land-decide.sh` reads `main` again
after the fetch and writes it as `mainAfter` (from review). actionlint 1.7.12 (which also runs
shellcheck on each `run:` line) and shellcheck 0.11.0 report nothing on them. PR 1 adds them with
`land-decide.test.sh` and the ci steps under `cut_line`. The built files are the source once PR 1
merges; Build notes, PR 1 lists how they differ from these sketches.

`.github/workflows/land.yml`:

```yaml
name: land

on:
  push:
    branches: [main]
  workflow_run:
    workflows: [ci]
    types: [completed]
  issue_comment:
    types: [created, edited]
  workflow_dispatch:

permissions: {}

jobs:
  decide:
    if: >-
      github.ref == 'refs/heads/main' && (
        github.event_name == 'push' || github.event_name == 'workflow_dispatch' ||
        (github.event_name == 'workflow_run' &&
          github.event.workflow_run.event == 'pull_request' &&
          github.event.workflow_run.head_repository.full_name == github.repository) ||
        (github.event_name == 'issue_comment' && github.event.issue.pull_request &&
          github.event.comment.user.login == github.repository_owner))
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    concurrency:
      group: land-decide
      cancel-in-progress: false
    permissions:
      contents: read
      pull-requests: read
      issues: read
      checks: read
    env:
      LAND_DASHBOARD: 43
    steps:
      - id: t0
        run: echo "at=$(date +%s)" >> "$GITHUB_OUTPUT"
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/cache/restore@v4
        with:
          path: |
            ~/.elan
            .lake
            core/.lake
          key: lean-${{ hashFiles('lean-toolchain', 'lake-manifest.json') }}-${{ github.sha }}
          restore-keys: lean-${{ hashFiles('lean-toolchain', 'lake-manifest.json') }}-
      - run: .github/scripts/install-elan.sh
      - run: .github/scripts/install-toolchains.sh
      - run: lake build mitos-gate
      - name: Decide (prints only)
        env:
          GH_TOKEN: ${{ github.token }}
          LAND_T0: ${{ steps.t0.outputs.at }}
          LAND_EVENT: ${{ github.event_name }}
          LAND_EVENT_HEAD: ${{ github.event.workflow_run.head_sha }}
          LAND_EVENT_CONCLUSION: ${{ github.event.workflow_run.conclusion }}
          LAND_EVENT_PR: ${{ github.event.issue.number }}
          LAND_EVENT_COMMENT: ${{ github.event.comment.id }}
        run: .github/scripts/land-decide.sh "$GITHUB_REPOSITORY" "$LAND_DASHBOARD" "$RUNNER_TEMP/land"
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: land-record-${{ github.run_id }}-${{ github.run_attempt }}
          path: ${{ runner.temp }}/land/record.json
          retention-days: 90
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: land-reads-${{ github.run_id }}-${{ github.run_attempt }}
          path: ${{ runner.temp }}/land/reads
          retention-days: 7
```

`.github/scripts/land-decide.sh`:

```bash
#!/usr/bin/env bash
# Usage: .github/scripts/land-decide.sh <owner/name> <dashboard-issue> <dir>
#
# One decide run, in a clone of the repository: the reads, the snapshot, the decision, then one
# line, <dir>/record.json. It holds no rule: every decision is `mitos-gate`'s, and it reads no
# line that another tool printed. Exit 0: decided, or skipped under the REST floor. Exit 1:
# refused, and the record says at which stage. Exit 2: usage.
set -u

die() { printf 'land-decide: %s\n' "$1" >&2; exit 2; }
[ $# = 3 ] || die "usage: land-decide.sh <owner/name> <dashboard-issue> <dir>"
repo=$1 dash=$2 out=$3
gate=${MITOS_GATE:-.lake/build/bin/mitos-gate}
fetch=${SNAPSHOT_FETCH:-gate/snapshot-fetch.sh}
floor=${LAND_REST_FLOOR:-300}
for tool in jq git date gh; do command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"; done
mkdir -p -- "$out" || die "cannot make the folder"
[ -z "$(ls -A -- "$out")" ] || die "the folder is not empty"

sha() { [[ $1 =~ ^[0-9a-f]{40}$ ]]; }
num() { [[ $1 =~ ^(0|[1-9][0-9]{0,18})$ ]]; }
trigger() {
  case ${LAND_EVENT:-workflow_dispatch} in
    push) jq -cn '{kind: "mainMoved"}' ;;
    workflow_run)
      sha "${LAND_EVENT_HEAD:-}" && [[ ${LAND_EVENT_CONCLUSION:-} =~ ^[a-z_]{1,32}$ ]] || return 1
      jq -cn --arg h "$LAND_EVENT_HEAD" --arg c "$LAND_EVENT_CONCLUSION" \
        '{kind: "gateDone", head: $h, conclusion: $c}' ;;
    issue_comment)
      num "${LAND_EVENT_PR:-}" && num "${LAND_EVENT_COMMENT:-}" || return 1
      jq -cn --argjson p "$LAND_EVENT_PR" --argjson c "$LAND_EVENT_COMMENT" \
        '{kind: "comment", pr: $p, id: $c}' ;;
    workflow_dispatch) jq -cn '{kind: "dispatch"}' ;;
    *) return 1 ;;
  esac
}
trig=$(trigger) || die "the trigger is not one this script records"
tool=$(git rev-parse --verify --quiet 'HEAD^{commit}') || die "not in a clone"
num "$floor" || die "LAND_REST_FLOOR is not a number"

now() { date -u +%s; }
lines() { if [ -f "$1" ]; then jq -Rsc 'split("\n") | map(select(. != ""))' "$1"; else echo '[]'; fi; }
t_job=${LAND_T0:-$(now)}; num "$t_job" || die "LAND_T0 is not a time"
t0=$(now)
stamp() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
head_of() {
  jq -cn --argjson trigger "$trig" --arg read "$(stamp "$1")" --arg tool "$tool" \
    --argjson setup "$((t0 - t_job))" '{v: 1, trigger: $trigger, read: $read, tool: $tool, setup: $setup}'
}

left=$(gh api rate_limit --jq .resources.core.remaining 2>/dev/null) || left=
if num "$left" && [ "$left" -lt "$floor" ]; then
  jq -c --argjson left "$left" 'del(.setup) + {outcome: {kind: "skipped", remaining: $left}}' \
    <<<"$(head_of "$t0")" >"$out/record.json"
  printf 'land-decide: skipped, %s REST calls left\n' "$left"
  exit 0
fi

"$fetch" "$repo" "$dash" "$out/reads" 2>"$out/fetch.err"; code=$?
after=$(gh api "repos/$repo/branches/main" --jq .commit.sha 2>/dev/null) && sha "$after" || after=
t1=$(now)
stage=fetch
if [ "$code" = 0 ]; then
  stage=snapshot
  "$gate" snapshot "$out/reads" >"$out/snapshot.json" 2>"$out/snapshot.err"; code=$?
fi
t2=$(now)
if [ "$code" = 0 ]; then
  stage=land
  "$gate" land "$out/snapshot.json" >"$out/decision.json" 2>"$out/land.err"; code=$?
fi
t3=$(now)

main=$(jq -er '.commit.sha' "$out/reads/main.json" 2>/dev/null) && sha "$main" || main=
reads=$(find "$out/reads" -name '*.json' 2>/dev/null | wc -l)
head=$(jq -c --arg main "$main" --arg after "$after" --argjson reads "$reads" \
  --argjson unread "$(lines "$out/fetch.err")" \
  --argjson fetch "$((t1 - t0))" --argjson snapshot "$((t2 - t1))" --argjson decide "$((t3 - t2))" \
  '{v, trigger, read, main: $main, mainAfter: $after, tool,
    cost: {setup, fetch: $fetch, snapshot: $snapshot, decide: $decide, reads: $reads},
    unread: $unread}' <<<"$(head_of "$t1")")

if [ "$code" != 0 ] || [ -z "$main" ]; then
  jq -c --arg stage "$stage" --argjson said "$(lines "$out/$stage.err")" \
    '. + {outcome: {kind: "refused", stage: $stage, said: $said}}' <<<"$head" >"$out/record.json"
  printf 'land-decide: refused at %s\n' "$stage" >&2
  exit 1
fi

trees='[]'
while read -r commit; do
  sha "$commit" || continue
  tree=$(git rev-parse --verify --quiet "$commit^{tree}") || continue
  trees=$(jq -c --arg c "$commit" --arg t "$tree" '. + [{commit: $c, tree: $t}]' <<<"$trees")
done < <(jq -r '.prs[] | select(.base.kind == "clean") | .base.replay' "$out/snapshot.json")

jq -c --argjson head "$head" --argjson trees "$trees" --slurpfile decision "$out/decision.json" \
  --argjson notes "$(lines "$out/snapshot.err")" \
  '$head + {outcome: {kind: "decided", snapshot: ., decision: $decision[0], trees: $trees,
    notes: $notes}}' "$out/snapshot.json" >"$out/record.json"
cat "$out/decision.json" "$out/snapshot.err"
```

### The scorer (PR 2)

types: `gate/MitosGate/Shadow.lean`, the judge's sketch, verbatim except that `precedes` and
`PairedRecordPrecedesTheMerge` compare `read < time`. It type-checks against `main` at 4ba56dc
with real bodies, and ends with the statements.

```lean
import MitosGate.LandCli
import MitosGate.Speech

namespace MitosGate.Shadow

open Land

abbrev Stamp := Speech.Stamp

inductive Trigger
  | mainMoved
  | gateDone (head : Sha) (conclusion : String)
  | comment (pr : Pr) (id : Nat)
  | dispatch
  deriving DecidableEq

structure Cost where
  setup : Nat
  fetch : Nat
  snapshot : Nat
  decide : Nat
  reads : Nat

structure TreeOf where
  commit : Sha
  tree : Sha

structure Record where
  run : Nat
  trigger : Trigger
  read : Stamp
  main : Sha
  tool : Sha
  cost : Cost
  prs : List Obs
  trees : List TreeOf

structure Merge where
  pr : Pr
  time : Stamp
  before : Sha
  head : Sha
  tree : Sha

def observer : Teammate := ⟨"shadow", "observer"⟩

inductive Clause
  | updatable | enforced | covered | reviewed | rest
  deriving DecidableEq

def lacks (o : Obs) : List Clause :=
  [(Clause.updatable, o.updatable), (.enforced, o.enforced), (.covered, o.covered),
   (.reviewed, o.reviewed), (.rest, o.rest)].filterMap fun (c, b) => if b then none else some c

def fresh (os : List Obs) : Nat := (os.flatMap fun o => o.words.map Word.said).foldr max 0 + 1

def withWord (said : Nat) (o : Obs) : Obs :=
  { o with words := o.words ++ [.ownerLand ⟨said, o.head⟩] }

inductive Reading
  | asRead (step : Step)
  | oneWordAway (after : Step)
  deriving DecidableEq

def Reading.step : Reading → Step
  | .asRead s | .oneWordAway s => s

def reading (os : List Obs) (o : Obs) : Reading :=
  match step observer (queueOf os) o with
  | .stop .noEntry =>
    let o' := withWord (fresh os) o
    .oneWordAway (step observer (queueOf (os.map fun x => if x.pr == o.pr then o' else x)) o')
  | s => .asRead s

inductive Head
  | same
  | replayedAsPlanned
  | replayedOtherwise
  | other
  deriving DecidableEq

def headOf (r : Record) (o : Obs) (m : Merge) : Head :=
  if o.head == m.head then .same
  else
    match o.base with
    | .clean x =>
      if r.trees.any fun t => t.commit == x && t.tree == m.tree then .replayedAsPlanned
      else .replayedOtherwise
    | _ => .other

structure Sat where
  run : Nat
  age : Nat
  reading : Reading
  lacks : List Clause
  head : Head
  authorKnown : Bool
  updaterPushes : Nat

inductive Seat
  | unseen
  | unlisted (run : Nat)
  | sat (s : Sat)

def precedes (m : Merge) (r : Record) : Bool := r.main == m.before && decide (r.read < m.time)

def last (m : Merge) : List Record → Option Record
  | [] => none
  | r :: rs =>
    match last m rs with
    | some x => if precedes m r && decide (x.read < r.read) then some r else some x
    | none => if precedes m r then some r else none

def seat (m : Merge) (rs : List Record) : Seat :=
  match last m rs with
  | none => .unseen
  | some r =>
    match r.prs.find? (·.pr == m.pr) with
    | none => .unlisted r.run
    | some o =>
      .sat { run := r.run, age := m.time - r.read, reading := reading r.prs o, lacks := lacks o,
             head := headOf r o m, authorKnown := o.author.isSome,
             updaterPushes := (o.pushes.filter (·.byUpdater)).length }

inductive Finding
  | agrees
  | waits
  | disagrees (why : Stop)
  | otherTree
  | blind
  deriving DecidableEq

def finding : Seat → Finding
  | .unseen | .unlisted _ => .blind
  | .sat s =>
    match s.head, s.reading.step with
    | .other, _ => .blind
    | .replayedOtherwise, _ => .otherTree
    | _, .stop why => .disagrees why
    | .same, .present _ => .agrees
    | .replayedAsPlanned, .awaitPush _ => .agrees
    | _, _ => .waits

structure Tally where
  agrees : Nat := 0
  waits : Nat := 0
  disagrees : Nat := 0
  otherTree : Nat := 0
  blind : Nat := 0
  assumed : Nat := 0
  noAuthor : Nat := 0
  updaterPushes : Nat := 0

def Tally.add (t : Tally) (s : Seat) : Tally :=
  let t := match finding s with
    | .agrees => { t with agrees := t.agrees + 1 }
    | .waits => { t with waits := t.waits + 1 }
    | .disagrees _ => { t with disagrees := t.disagrees + 1 }
    | .otherTree => { t with otherTree := t.otherTree + 1 }
    | .blind => { t with blind := t.blind + 1 }
  match s with
  | .sat x =>
    { t with updaterPushes := t.updaterPushes + x.updaterPushes,
             assumed := t.assumed + (match x.reading with | .oneWordAway _ => 1 | _ => 0),
             noAuthor := t.noAuthor + (if x.authorKnown then 0 else 1) }
  | _ => t

def tally (ms : List Merge) (rs : List Record) : Tally :=
  ms.foldl (fun t m => t.add (seat m rs)) ({} : Tally)

structure Spread where
  n : Nat
  min : Nat
  median : Nat
  p90 : Nat
  max : Nat

def spread (xs : List Nat) : Spread :=
  let s := xs.mergeSort (· ≤ ·)
  { n := s.length, min := s.head?.getD 0, median := s.getD (s.length / 2) 0,
    p90 := s.getD (s.length * 9 / 10) 0, max := s.getLast?.getD 0 }

/-! ## Statements -/

def ReadyIsOneWordFromLanding : Prop :=
  ∀ (me : Teammate) (q : Queue) (o : Obs) (said : Nat),
    step me q o = .stop .noEntry → (∀ w ∈ o.words, w.said < said) →
    landable (⟨o.pr, ⟨said, o.head⟩, .owner⟩, withWord said o) = true

def TheWordIsOnlyAssumedWhenReady : Prop :=
  ∀ (os : List Obs) (o : Obs),
    (∃ s, reading os o = .oneWordAway s) ↔ step observer (queueOf os) o = .stop .noEntry

def LacksNothingIffEligible : Prop :=
  ∀ o : Obs, lacks o = [] ↔ o.eligibleBeforeRebase = true

def PairedRecordPrecedesTheMerge : Prop :=
  ∀ (m : Merge) (rs : List Record) (r : Record), last m rs = some r →
    r ∈ rs ∧ r.main = m.before ∧ r.read < m.time ∧
      ∀ x ∈ rs, x.main = m.before → x.read < m.time → x.read ≤ r.read

def SeatIgnoresRecordOrder : Prop :=
  ∀ (m : Merge) (rs rs' : List Record), rs.Perm rs' → (rs.map (·.read)).Nodup →
    seat m rs = seat m rs'

def AgreesMeansTheMergedContent : Prop :=
  ∀ s : Sat, finding (.sat s) = .agrees →
    (s.head = .same ∧ ∃ h, s.reading.step = .present h) ∨
      (s.head = .replayedAsPlanned ∧ ∃ h, s.reading.step = .awaitPush h)

def TallyCountsEveryMergeOnce : Prop :=
  ∀ (ms : List Merge) (rs : List Record),
    let t := tally ms rs
    t.agrees + t.waits + t.disagrees + t.otherTree + t.blind = ms.length

end MitosGate.Shadow
```

Contract only, after `Shadow.lean`. The names and types are fixed; the bodies are the builder's.
This block type-checks against `main` at 4ba56dc after the one above.

```lean
namespace MitosGate
open Lean (Json)

-- parse and check; `run` then uses it
def LandCli.read : String → Except String LandCli.Snapshot := sorry

namespace ShadowCli
inductive Stage
  | fetch
  | snapshot
  | land
inductive Run
  | decided (r : Shadow.Record)
  | refused (t : Shadow.Trigger) (s : Stage)
  | skipped (t : Shadow.Trigger) (remaining : Nat)
-- refuses v ≠ 1; `run` is the `<run>` of the artifact's name; `main` is "" when `mainAfter` differs
def run? (run : Nat) (j : Json) : Except String Run := sorry
def cli (args : List String) (usage : String) : IO UInt32 := sorry
end ShadowCli
end MitosGate
```

`run?` counts a record as drifted when `LandCli.run` on its snapshot does not give the decision it
printed. Drifted records are listed and not scored.

statements: proved in the sketch, standard axioms only. Their Lean is the `Statements` section at
the end of the `Shadow.lean` block above, and the proofs are below. Against `main` at 4ba56dc,
`agreesMeansTheMergedContent` uses `propext` alone and the other five `propext`,
`Classical.choice` and `Quot.sound`.

| Statement | Says |
|---|---|
| `ReadyIsOneWordFromLanding` | After `stop noEntry`, the owner's newest `/land` about the head is landable. |
| `TheWordIsOnlyAssumedWhenReady` | `oneWordAway` exactly when the as-read step is `stop noEntry`. |
| `LacksNothingIffEligible` | `lacks o = []` iff `eligibleBeforeRebase`. A new clause in `Land` breaks the build. |
| `PairedRecordPrecedesTheMerge` | The paired record read the merge's `before`, in an earlier second than the merge, and is the newest such. |
| `AgreesMeansTheMergedContent` | `agrees` only for `present` at the merged head, or `awaitPush` with the merged tree. |
| `TallyCountsEveryMergeOnce` | The five counts sum to the merges. |

Stated and type-checked, not proved: `SeatIgnoresRecordOrder`.

The ordering of a record's reads against a merge comes from `main`, not from a clock. `read` is
the runner's clock and `Merge.time` is GitHub's `merged_at`, so `read < time` alone cannot show
that the reads ended before the merge. But a record keeps its `main` only when `mainAfter`, read
after all its reads, is the same commit (`run?`), and a merge moves `main` off `before`. So
`main = before` shows that every read came before the merge, given two facts. `main` never
returns to an old commit: its protection refuses force pushes for everyone (`allow_force_pushes`
false, `enforce_admins` true, read on 2026-11-14 with the owner's token). And GitHub's branch read
shows a merge once it is done, which GitHub does not document (risks). `read < time` can then
only drop a record, never pair a later one.

<details>
<summary>The sketch's proofs, as their own file that imports <code>MitosGate.Shadow</code>. The
builder puts them after the statements in <code>Shadow.lean</code>, without that
<code>import</code> line; the closing <code>#eval</code> only prints their axioms.</summary>

```lean
import MitosGate.Shadow

namespace MitosGate.Shadow
open Land

theorem walk_self (v : String) (ps : List Carry.Push) : Carry.walk v v ps = true := by
  cases ps <;> simp [Carry.walk]

theorem newestOwner_append_land (m : Mark) :
    ∀ ws : List Word, (∀ w ∈ ws, w.said < m.said) →
      newestOwner (ws ++ [.ownerLand m]) = some (.ownerLand m)
  | [], _ => by simp [newestOwner, Word.byOwner]
  | w :: ws, h => by
    have ih := newestOwner_append_land m ws (fun x hx => h x (List.mem_cons_of_mem _ hx))
    have hw : w.said < m.said := h w (List.mem_cons_self ..)
    simp only [List.cons_append, newestOwner, ih]
    have : ¬ ((Word.ownerLand m).said < w.said) := by
      show ¬ (m.said < w.said)
      omega
    simp [this]

theorem lacksNothingIffEligible : LacksNothingIffEligible := by
  intro o
  simp only [lacks, Obs.eligibleBeforeRebase]
  cases o.updatable <;> cases o.enforced <;> cases o.covered <;> cases o.reviewed <;>
    cases o.rest <;> simp [List.filterMap]

theorem agreesMeansTheMergedContent : AgreesMeansTheMergedContent := by
  intro s h
  simp only [finding] at h
  split at h
  · cases h
  · cases h
  · cases h
  · rename_i h1 h2; exact .inl ⟨h1, _, h2⟩
  · rename_i h1 h2; exact .inr ⟨h1, _, h2⟩
  · cases h

theorem covered_head_id {o : Obs} (h : o.covered = true) : (o.id? o.head).isSome = true := by
  have hc : o.Covered := of_decide_eq_true h
  unfold Obs.Covered at hc
  split at hc
  · exact hc.elim
  · have key : ∀ v, o.stands v → (o.id? o.head).isSome = true := by
      intro v hv
      have := hv.1
      simp only [Obs.carries, Bool.and_eq_true] at this
      obtain ⟨⟨_, h1⟩, h2⟩ := this
      have : o.id? v.head = o.id? o.head := by simpa using h2
      rw [← this]; exact h1
    rcases hc.2 with ⟨v, _, hv, _⟩ | ⟨⟨v, _, hv, _⟩, _⟩ <;> exact key v hv

theorem readyIsOneWordFromLanding : ReadyIsOneWordFromLanding := by
  intro me q o said h hs
  have hel : o.eligibleBeforeRebase = true ∧ o.stuck? = none := by
    unfold step at h
    split at h
    · cases h
    · split at h
      · cases h
      · split at h
        · cases h
        · rename_i _ _ he
          split at h
          · cases h
          · rename_i hst
            refine ⟨by simpa using he, hst⟩
  obtain ⟨he, hst⟩ := hel
  have hcov : o.covered = true := by
    simp only [Obs.eligibleBeforeRebase, Bool.and_eq_true] at he
    exact he.1.1.2
  have hid := covered_head_id hcov
  have hn := newestOwner_append_land ⟨said, o.head⟩ o.words hs
  simp only [landable, Entry.valid, Bool.and_eq_true]
  refine ⟨⟨⟨?_, he⟩, ?_⟩, ?_⟩
  · simp only [Obs.entries, withWord, hn]
    simp
  · show (Carry.walk o.head o.head (o.pushes.map Push.toCarry) && (o.id? o.head).isSome &&
      o.id? o.head == o.id? o.head) = true
    simp [walk_self, hid]
  · show (o.stuck?).isNone = true
    simp [hst]

theorem theWordIsOnlyAssumedWhenReady : TheWordIsOnlyAssumedWhenReady := by
  intro os o
  unfold reading
  split
  · rename_i h; simp [h]
  · rename_i h
    constructor
    · rintro ⟨s, hs⟩; cases hs
    · intro h'; exact absurd h' (h)

def Tally.total (t : Tally) : Nat := t.agrees + t.waits + t.disagrees + t.otherTree + t.blind

theorem add_total (t : Tally) (s : Seat) : (t.add s).total = t.total + 1 := by
  unfold Tally.add Tally.total
  cases s <;> (dsimp only; split <;> simp <;> omega)

theorem foldl_total (rs : List Record) :
    ∀ (ms : List Merge) (t : Tally),
      (ms.foldl (fun t m => t.add (seat m rs)) t).total = t.total + ms.length
  | [], t => by simp
  | m :: ms, t => by
    simp only [List.foldl_cons, List.length_cons]
    rw [foldl_total rs ms, add_total]; omega

theorem tallyCountsEveryMergeOnce : TallyCountsEveryMergeOnce := by
  intro ms rs
  have := foldl_total rs ms {}
  simpa [tally, Tally.total] using this

theorem last_none {m : Merge} : ∀ {rs : List Record}, last m rs = none →
    ∀ y ∈ rs, precedes m y = false
  | [], _, y, hy => by cases hy
  | a :: rs, h, y, hy => by
    simp only [last] at h
    split at h
    · split at h <;> cases h
    · rename_i hx
      split at h
      · cases h
      · rename_i hc
        rcases List.mem_cons.mp hy with rfl | hy
        · simpa using hc
        · exact last_none hx y hy

theorem pairedRecordPrecedesTheMerge : PairedRecordPrecedesTheMerge := by
  intro m rs
  induction rs with
  | nil => intro r h; cases h
  | cons a rs ih =>
    intro r h
    simp only [last] at h
    split at h
    · rename_i x hx
      obtain ⟨hmem, hmain, hread, hmax⟩ := ih x hx
      split at h
      · rename_i hc
        cases h
        simp only [precedes, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hc
        refine ⟨List.mem_cons_self .., hc.1.1, hc.1.2, ?_⟩
        intro y hy h1 h2
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · exact Nat.le_trans (hmax y hy h1 h2) (Nat.le_of_lt hc.2)
      · rename_i hc
        cases h
        refine ⟨List.mem_cons_of_mem _ hmem, hmain, hread, ?_⟩
        intro y hy h1 h2
        rcases List.mem_cons.mp hy with rfl | hy
        · simp only [precedes, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, not_and,
            Nat.not_lt] at hc
          exact hc ⟨h1, h2⟩
        · exact hmax y hy h1 h2
    · rename_i hx
      split at h
      · rename_i hc
        cases h
        simp only [precedes, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at hc
        refine ⟨List.mem_cons_self .., hc.1, hc.2, ?_⟩
        intro y hy h1 h2
        rcases List.mem_cons.mp hy with rfl | hy
        · exact Nat.le_refl _
        · have := last_none hx y hy
          simp [precedes, h1, h2] at this
      · cases h

open Lean in
#eval show CoreM Unit from do
  for n in [``readyIsOneWordFromLanding, ``lacksNothingIffEligible, ``agreesMeansTheMergedContent,
      ``theWordIsOnlyAssumedWhenReady, ``tallyCountsEveryMergeOnce,
      ``pairedRecordPrecedesTheMerge] do
    IO.println s!"{n}: {(← collectAxioms n).toList}"
end MitosGate.Shadow
```

</details>

reuse:
- `gate/MitosGate/Land.lean`: `step` (238), `queueOf` (189), `Obs.eligibleBeforeRebase` (130) and
  the statements `PushOnlyNext` (298), `NoEntryNoPush` (303), `PushIsNotRepeated` (314),
  `UnenforcedLandsNothing` (324), `HoldWins` (329), `StuckDoesNotBlock` (340),
  `NextIgnoresListingOrder` (346).
  - `PushIsNotRepeated` takes a landable entry `(e, o)` with `o.base = .clean r` and no verdict
    whose head is `r`. Then the model's `pushed r o` is still landable with `base = .current`, so
    the model does not plan that push again. It is about the model's `pushed`, not what GitHub
    shows after a real push, and it bounds no pushes per merge.
- 2a: `IncompleteReadHolds` and `PositionsAscendingDistinct` (`gate/MitosGate/Speech/Words.lean`,
  61 and 64).
- Printing: `ciLine` (`gate/MitosGate/Util.lean`, 282).
- CI: ci's cache key (`.github/workflows/ci.yml`, 144 to 151), restore only;
  `.github/scripts/install-elan.sh` and `.github/scripts/install-toolchains.sh`.
- Contract only: 2b's `FailedReadHolds`, `EnforcedNeedsProtection` and `OnlyTheOwnerQueues`.

fixtures:
- Kernel (13, all pass against `main` at 4ba56dc: the sketch's 12 and
  `aRecordInTheMergesSecondIsUnseen`, which fails under `≤`). The block below is its own file
  that imports `MitosGate.Shadow`. The builder puts it in `Shadow.lean` without that `import`
  line, as `Land.lean` keeps its `Fixture` namespace:

```lean
import MitosGate.Shadow
namespace MitosGate.Shadow.Fixture
open Land Land.Fixture

def unsaid : Obs := { agentBehind with words := [] }
def unsaidOnMain : Obs := { agentOnMain with words := [] }

theorem readyBehindIsOneWordFromThePush :
    reading [unsaid] unsaid = .oneWordAway (.awaitPush "bbb") := by decide +kernel
theorem readyOnMainGreenIsOneWordFromPresent :
    reading [unsaidOnMain] unsaidOnMain = .oneWordAway (.present "bbb") := by decide +kernel
theorem aHoldIsReadAsItIs :
    reading [ownerKeptHeld] ownerKeptHeld = .asRead (.stop .held) := by decide +kernel
theorem aTypedWordIsReadAsItIs :
    reading [ownerKeptPushed] ownerKeptPushed = .asRead (.present "ar") := by decide +kernel
theorem newContentIsNotAssumed :
    reading [{ ownerKeptNewContent with words := [] }] { ownerKeptNewContent with words := [] } =
      .asRead (.stop .notEligible) := by decide +kernel
theorem anotherWordAheadMakesTheAssumedWordWait :
    reading [ownerKeptPushed, unsaid] unsaid = .oneWordAway (.wait 153) := by decide +kernel

def rec (run read : Nat) (main : Sha) (prs : List Obs) : Record :=
  { run, trigger := .mainMoved, read, main, tool := main, cost := ⟨20, 12, 1, 0, 36⟩, prs,
    trees := [⟨"br", "tb"⟩] }
def merged : Merge := { pr := 149, time := 100, before := "m1", head := "b2", tree := "tb" }

theorem theReplayThatMergedAgrees :
    finding (seat merged [rec 1 90 "m1" [unsaid]]) = .agrees := by decide +kernel
theorem anotherTreeIsNotAgreement :
    finding (seat { merged with tree := "tx" } [rec 1 90 "m1" [unsaid]]) = .otherTree := by
  decide +kernel
theorem aRecordOfAnotherMainIsUnseen :
    finding (seat merged [rec 1 90 "m0" [unsaid]]) = .blind := by decide +kernel
theorem aRecordAfterTheMergeIsUnseen :
    finding (seat merged [rec 1 101 "m1" [unsaid]]) = .blind := by decide +kernel
theorem aRecordInTheMergesSecondIsUnseen :
    finding (seat merged [rec 1 100 "m1" [unsaid]]) = .blind := by decide +kernel
theorem theNewestRecordBeforeTheMergeIsUsed :
    (match seat { merged with head := "bbb" } [rec 1 80 "m1" [unsaid], rec 2 90 "m1" [unsaidOnMain]] with
      | .sat s => s.run | _ => 0) = 2 := by decide +kernel
theorem aHeldMergeDisagrees :
    finding (seat { merged with pr := 153, head := "aaa" } [rec 1 90 "m1" [ownerKeptHeld]]) =
      .disagrees .held := by decide +kernel
end MitosGate.Shadow.Fixture
```

- `.github/scripts/land-decide.test.sh` (the real `land`; stubs for the fetch, `snapshot` and
  `gh`):
  - `decided-on-the-land-fixture`: the record's decision equals `mitos-gate land` on the `prs` of
    `gate/land-fixtures/queue.json`, the shape 2b's snapshot prints.
  - `refused-fetch-is-red` (PR 1): a fetch that exits 2 is refused at `fetch`, and the snapshot
    does not run.
  - `refused-snapshot-is-red`
  - `refused-land-is-red` (PR 1): the real `land` refuses a malformed snapshot, and its line is the
    record's `said`.
  - `unread-main-is-red`
  - `failed-reads-pass-through`: the lines land in `unread` verbatim, and the run exits 0.
  - `main-moved-while-reading`: `mainAfter` is the second read's commit, and the run exits 0.
  - `failed-second-read-of-main` (verifier on #248): `mainAfter` is `""`, `mainAfterSaid` keeps the
    error text, and the run exits 0.
  - `rate-floor-skips`
  - `bad-event-text-is-refused`
  - `each-event-has-its-trigger` (PR 1): each of the four events gives its `TRIGGER`.
  - `a-push-plan-records-its-tree`
  - `holds-no-key`: every permission is `read`; no secret, environment or app token; no write
    verb in either script. Pinned as built: the only actions are checkout, cache restore and
    upload-artifact; the `run:` lines are the five of the sketch; the only `gh` calls are the two
    reads; and the stub `gh` saw no other call in any case.
  - `filter-pins`: `refs/heads/main`, `repository_owner` and `head_repository.full_name` are
    named; the concurrency group is on the job; no event text sits in a `run:` line.
  - `every-read-has-a-timeout` (verifier on #248): each `gh api` call runs under
    `timeout -k 5 120`.
  - `an-unwritten-record-is-red` (CodeRabbit on #260): when `record.json` cannot be written, a
    skipped, decided or refused run exits 1 and prints no decision.
- `gate/shadow-fixtures/` and `gate/shadow-test.sh`: `record-idle.json` (a real record),
  `record-refused.json`, `record-skipped.json`, `record-v2.json` (refused), `record-main-moved.json`
  (pairs with no merge), and `window/` with its expected report. A drifted record is listed and not
  scored.
- Live: one dispatch run on `main` whose `unread` lists what the workflow token cannot read; a
  comment from another login starts no job; a day-one report over real records.

cut_line: two PRs, each `Part of #191`. The report comment that meets the bar (O2) closes #191.
- PR 1, the recorder (`.github/` only, after 2b merges). It opens the window. It adds two ci steps
  after `lake build` (`Build core and gate`), because both need the built `mitos-gate`:
  - `land-decide.sh records each outcome and holds no key`, which runs
    `.github/scripts/land-decide.test.sh`, as ci runs `.github/scripts/cancel-superseded.test.sh`
    today (`ci.yml` 141 and 142);
  - one step that runs every `gate/*-test.sh` by glob, as its own commit. If a test is red on the
    CI image for a reason outside this row, that commit moves to its own PR under #164.
- PR 2, the scorer (`gate/` only, in parallel with PR 1).
- Reports on #191: day one (token reach and run time), then at the bar.

deferrals:
- Into this row:
  - CI wiring of the gate shell tests (from #233 and #246). Today ci runs only
    `gate/lock-header-test.sh` of them.
  - "How often a mixed-model PR gets no author" (#190 default 4) is `Tally.noAuthor`.
  - The design's guess of 200 run-minutes for `decide` is the cost line.
  - The `mainAfter` read's error text (CodeRabbit on #248): the sketch drops it, so a failed read
    shows only as `""`. PR 1 keeps that text in the record field `mainAfterSaid`; no record
    exists before PR 1 merges, so `v` stays 1.
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

### Contract only (2b), read at #246 e4275f8 on `main` 4ba56dc

Re-checked against `main` at 31cc93a after #246 merged; Build notes, PR 1 lists the drift.

| Needed from 2b | Used for |
|---|---|
| `gate/snapshot-fetch.sh <owner/name> <dashboard> <empty dir>`: GETs only, through `gh api`. Exit 0, with one stderr line per failed read. Exit 2 on a usage error: wrong arguments, a missing `gh`, `jq` or `timeout`, or a folder that is not empty. 6 + 6N reads at most for N open pull requests. | `unread`, `cost.reads` |
| `mitos-gate snapshot <dir>`: prints `{"prs":[…]}`, exit 1 on a fatal read, fetches missing commits from `origin` itself | `snapshot`, `notes`, `refused` |
| `<dir>/main.json` `.commit.sha` | `main` |
| The replay commit of `base: clean` is in the clone afterwards | `trees` |
| `LandCli`'s schema with the `event.pr` check, and no public parser yet | `LandCli.read` |
| Which reads the workflow token can make (protection: no; stacks: unknown) | whether any seat is not `held` |

### Build notes, PR 1

The re-check against `main` at 31cc93a, after #246 merged:
- Every row of the table above holds. Drift: `snapshot-fetch.sh` also exits 2 when `<owner/name>`
  is not a repository name or `<dashboard-issue>` is not an issue number, and it reads each list
  with `--paginate --slurp`. The recorder passes `$GITHUB_REPOSITORY` and `LAND_DASHBOARD: 43`,
  which have those shapes. `mitos-gate snapshot` also exits 1 when it cannot fetch `main`'s commit.
- The facts under Rationale hold, except two line numbers in `LandCli.lean`: the private
  `snapshot` parser is at 182 (was 180) and the public `run` at 270 (was 261). The 2b statements
  that `reuse` names are in `gate/MitosGate/Snapshot/Obs.lean` (41, 45 and 57).
  `rules/branches/main` still returns `[]`, and `branches/main` still shows `everyone` and `gate`
  but not `strict`.
- The workflow token's reach is still unknown; the first dispatch run's `unread` shows it.

How PR 1 differs from the two sketches:
1. A new record field, `mainAfterSaid` (see The record). It closes the deferral from CodeRabbit on
   #248. PR 2's `run?` must accept it.
2. Both `gh api` calls run under `timeout -k 5 120` with standard input closed, as
   `snapshot-fetch.sh`'s reads do, and the tool check names `timeout`. The verifier on #248 asked
   for this on the `mainAfter` read. The rate read had the same gap, so it got the same fix.
3. `land-decide.test.sh` has six cases more than the design named (marked `PR 1` or `verifier on
   #248` under `fixtures`). It pins more than the design asked: the action list, the `run:` lines
   and the two `gh` calls. All 16 cases pass. Each of 21 mutants of `land-decide.sh` and
   `land.yml` fails at least one case. For example, a fork's run, a write permission, a secret, a
   write flag on a read, `-le` for the floor, or a dropped `mainAfterSaid`.
4. `decided-on-the-land-fixture` feeds the `prs` of `queue.json` without its `me` and `pr`, because
   2b's snapshot prints only `prs`.
5. The glob step also runs `gate/lock-header-test.sh`, which keeps its own named step, so that
   test runs twice (about 7 s).
6. The test has a file-level `shellcheck disable=SC2016`, as `.github/scripts/rebase-prs.test.sh`
   does: its single-quoted `$names` are jq variables.
7. Each write of `record.json` is checked, and a failed write exits 1 with
   `land-decide: the record was not written` (CodeRabbit on #260). In the sketch, a failed write or
   a failed `jq` in the decided branch still exited 0, through the last `cat`, with no record.

The dry run, since the workflow can run only after PR 1 merges:
- From a clone of `main` at 31cc93a with its push URL disabled, through a `gh` wrapper that logged
  each call and refused any call but `gh api` without a write flag. The session's credential is
  the owner's, not the workflow token, so protection and stacks read here. The dispatch run after
  the merge shows the workflow token's reach.
- 32 GETs, none refused: the rate read, 30 fetch reads for 4 open pull requests (6 + 6N), and
  `mainAfter`. Exit 0 in 18 s: `fetch` 13 s, `snapshot` 5 s, `decide` 0 s. `cost.reads` 30, the
  record 7,232 bytes on one line, the decision `{"next":null,"plan":{"kind":"idle"}}`, `unread`,
  `notes` and `trees` empty. No pull request was a clean replay: three conflict, one is current.
- #259 (open): 2b's reader ends the In flight section at a `## ` line that GitHub does not show as
  a heading, so a later table's rows are not read. The shadow only records, so this does not block
  PR 1. Records made before the fix can miss such rows; the scorer's report explains any finding
  it causes.

## Rationale

### Problem

Step 3 must show that 2b's reader plus `mitos-gate land` reach the decision the owner reached, and
what one decision costs. Three facts make a printing job useless as proof:
- With no typed `/land`, `plan` is always `idle` (`NoEntryNoPush`).
- The old updater rebases about 20 s after `main` moves, before `decide` reads.
- The workflow token cannot read protection.

The main risk is in neither candidate: the workflow token cannot read protection, so every pull
request reads `held` until that is fixed, and the same read blocks step 5 (O1).

### Facts this design rests on (checked against `main` at 4ba56dc and #246 at e4275f8)

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
- `LandCli.read` is needed: the parser `snapshot` (`LandCli.lean` 180) and the decoders it uses
  (52 to 165) are private. `Snapshot`, `Snapshot.check` and `Snapshot.decide` are public, but the
  public `run` (261) takes text and returns the decision's JSON, not the `Snapshot`. #246 edits
  the same file.

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
- Is 1,000 REST calls an hour enough? A run makes 7 + 6N reads at most: 6 + 6N in the fetch, and
  `mainAfter`. A read of a list is one REST call per page of 100, so a run makes at least as many
  REST calls as reads, and more when a list (files, activity, comments) runs past one page.
  `cost.reads` counts the fetch's reads that saved a file, not the REST calls. The floor is read
  once, at the start, and a failed read of it skips the check. Other jobs spend calls too. So the
  floor does not bound a run's cost or reserve calls for ci. The report prints the peak.
- Does GitHub's branch read show a merge as soon as the merge is done? The pairing rests on it
  (`mainAfter`), GitHub documents no freshness bound, and the shadow does not measure it.
- Does an anonymous `git fetch origin <sha>` work with `persist-credentials: false`? If not,
  persist the read token.
- `otherTree` also catches a stale sample after a content push; the report must explain each one.

### Next implementation step

After #246 merges, re-check the contract table and the facts against `main`, then build PR 1 from
the recorder's two files above, and PR 2 from the `Shadow.lean` block, its proofs and its
fixtures.

### Build notes, PR 2

Re-checked at `main` 31cc93a, after #246 merged. The 2b table holds row by row: the fetch makes
6 + 6N GETs through `gh api`, `snapshot` prints only `prs`, `main.json` names the commit, the
replay is a `commit-tree` object, and `LandCli` had no public parser. The facts under Rationale
hold, with line drift only: `LandCli`'s `obj` is at 56, its `snapshot` at 182 and `run` at 270.
One new fact: in a Claude Code session, `gh api --paginate` fails past the first page, because the
proxy refuses the `repositories/<id>` links that GitHub returns. The runner has no such proxy.

Deviations, each pinned by a fixture or a case of `gate/shadow-test.sh`:
- The split (`modules:` above) is finer than one `Reading` and one `Score` file. `Score` would hold
  the record, the pairing, the finding, the tally and the spread, five topics in about 280 lines,
  and `lacks` is not the assumed word. Each module imports only what it uses: `MitosGate.Land` and
  `MitosGate.Speech.Syntax`, not `LandCli` and all of `Speech`.
- `precedes` also needs `before ≠ ""`. A record that saw `main` move gets `main` `""`, and so would
  a merge whose `before` was not read, so the two would pair. `aRecordThatSawMainMoveIsUnseen`.
- `age` is `seconds m.time - seconds r.read`. A stamp is `YYYYMMDDHHMMSS` as one number, so the
  sketch's plain difference counts a minute as 100. `theAgeIsInSeconds` and seven stamp fixtures.
- `spread` sorts with an insertion sort, because `decide +kernel` cannot run `List.mergeSort`.
- New: `peak` and `PeakBoundsEveryWindow`, the most reads in one hour, which the risks ask for.
- `run?` ignores a key it does not read, so it reads PR 1's `mainAfterSaid`, empty or not, and `v`
  stays 1. `record-main-after-unread.json` carries a failed second read; every other record of the
  window carries `[]`. A record from PR 1's `land-decide.sh` at #260's head, run once against
  `kitimark/mitos`, reads as decided with no drift.
- A drifted record is an error of `run?` that starts with `drifted: `, because the contract's `Run`
  has no constructor for it. `refused` carries no cost, so the cost and reads lines count decided
  records only.
- The report differs from the Usage sample: each merge line names the merged head and the run of
  its record; every phase of `decide (s)`, and their total, has a spread; a `reads` line; the
  header counts unreadable records; the `merges` line adds the updater pushes; the `runs` line
  adds `dispatch` and the runs that the job filter skipped. The `pushes` line counts typed plans
  as designed, so it is 0 until the owner types `/land` (O5).
- `shadow-fetch.sh` follows pages by number and by cursor itself (the fact above), reads the runs
  one day at a time (a filtered list stops at 1000), and reads a record through the artifacts
  route and `unzip`. `SHADOW_WORKFLOW` names another workflow, so the script ran against real
  REST before `land.yml` exists.
- `gate/shadow-fixtures/record-idle.json` is a real record, from the recorder sketch above run
  once against `kitimark/mitos` from a session. Its token could read protection, so its `unread`
  is empty.
- ci does not run `shadow-test.sh` yet: PR 1 adds the step that runs every `gate/*-test.sh`. The
  test needs `zip` and `unzip`, which `ubuntu-24.04` has.

## Done when
- [ ] PR 1 merged: a dispatch run of `decide` on `main` leaves a record whose `unread` lists what
      the workflow token cannot read, and a comment from another login starts no job
- [ ] PR 2 merged: `mitos-gate shadow` scores `gate/shadow-fixtures/window/` to its expected report
- [ ] the day-one report on #191 (token reach and run time), then the report at the bar (O2)
- [ ] all `checks` pass locally
- [ ] no `sorry`, no new axioms
- [ ] run-log record written (ops/runs/)
