import Lean.Data.Json
import MitosGate.Watch
import MitosGate.Watch.Gh
import MitosGate.Watch.Store

/-! Usage:

  mitos-gate watch wait --state <dir> --repo <owner/name> --owner <login> --as <app>/<name>
      [--seen <n>] [--topics <kind>[,<kind>]...] [--on <n>[,<n>]...]
      [--ride none|<kind>[,<kind>]...] [--max <min>] [--since <UTC>] [--started <epoch>]
      [--tool-note <sha>] [--gh <path>] [--now <epoch>]
  mitos-gate watch own --state <dir> --as <app>/<name>
      (label|unlabel|assign|unassign <pr> <value> | merge|close <pr> |
       comment|review-comment|review <id>)
  mitos-gate watch status --state <dir> [--as <app>/<name>]
  mitos-gate watch unanswered --owner <login> [--issue-comments <file>]
      [--review-comments <file>] [--reviews <file>]
  mitos-gate watch read <route> --owner <login> <file>          (tests only)
  mitos-gate watch replay --owner <login> <dir>                  (tests only)

Exit codes of `wait`:
  0  a batch was delivered, or nothing changed until the deadline (one stdout line)
  1  cannot run (one stdout line `watch: cannot run: <why>; next: <what>`)
  2  usage. For `wait` only, one stdout line first, `watch: usage: <why>; next: <what>`; the usage
     text goes to stderr (`waitUsage`)
  3  superseded by a newer wait of the same consumer (stderr only)
  4  blind: no fresh successful read; one stdout line
`own` exits 0 even when the record fails, with a warning on stderr. `unanswered` exits 1 on any
refusal. -/

namespace MitosGate.WatchCli

open Lean (Json)
open Watch

structure WaitArgs where
  state : Option String := none
  repo : Option String := none
  owner : Option String := none
  as : Option String := none
  seen : Option Nat := none
  topics : Option String := none
  on : Option String := none
  ride : Option String := none
  max : Option Nat := none
  since : Option String := none
  started : Option Nat := none
  toolNote : Option String := none
  gh : Option String := none
  now : Option Nat := none
  testExit : Option String := none

structure OwnArgs where
  state : Option String := none
  as : Option String := none
  write : List String := []

structure StatusArgs where
  state : Option String := none
  as : Option String := none

structure UnansweredArgs where
  owner : Option String := none
  issueComments : Option String := none
  reviewComments : Option String := none
  reviews : Option String := none

def parseWait : List String → WaitArgs → Option WaitArgs := panic! "not implemented"
def parseOwn : List String → OwnArgs → Option OwnArgs := panic! "not implemented"
def parseStatus : List String → StatusArgs → Option StatusArgs := panic! "not implemented"
def parseUnanswered : List String → UnansweredArgs → Option UnansweredArgs :=
  panic! "not implemented"

/-- `app/name`: each part of `[a-z0-9._-]`, 1 to 64 characters, neither `.` nor `..`. -/
def consumer? (as : String) : Option Consumer := panic! "not implemented"

/-- The subscription flags of a wait, typed, in the order `Subscription.flags` prints them. A list
splits at commas with no empty part; a kind reads through `Kind.ofName?`; `--ride none` is the
empty list; `--on`'s numbers are positive decimals with no sign or leading zero, sorted, repeats
dropped. Any other text is `none`, a usage error (exit 2). `Subscription.ofFlags?` then refuses a
kind that cannot ride, so `--ride words` is exit 2 too. -/
def flags? (topics on ride : Option String) : Option (List Flag) := panic! "not implemented"

def waitUsage (why usage : String) : IO UInt32 := do
  IO.println s!"watch: usage: {why}; next: run the same command once in the foreground under timeout 60 and read stderr, fix it, then re-arm"
  IO.eprintln usage
  return 2

def wallNow : IO Epoch := do
  panic! "not implemented"

/-- One poll under the lease. Inside `Store.withLease` it reads `observed.json` again through
`load`, and returns that state unchanged when a poll is no longer due. Otherwise: `Plan.clock`
first (`main`, whose `Date` header is `serverNow`), then `Plan.fixed` from `Feed.sinceAt serverNow`, then `Plan.perHead` of
`Plan.heads` with `Plan.due`, the readers, `Shared.step` from the state it just read, then
`Store.write`. A fixed route that fails, or a reader that refuses, fails the poll with the route's
name and fixed words as its reason (`issueCommentsSince: reader refused`); a per-head failure fails
only that head (`HeadRead`). The whole poll stays within `pollBudget`. -/
def pollOnce (gh : String) (repo : Repo) (owner : String) (rules : Rules) (paths : Paths)
    (now : Epoch) (load : IO {s : Shared // s.Inv}) : IO Shared :=
  panic! "not implemented"

/-- The wait loop. First, before any claim or file: a missing `--state`, `--repo`, `--owner` or
`--as`, a bad `--as` (`consumer?`), a `--since` that `ofIso?` refuses, and subscription flags that
`flags?` or `Subscription.ofFlags?` refuse each end through `waitUsage`, exit 2. At the start, under `Store.withConsumer`: claim,
re-read `state.json`, take the offer `--seen` names, save. Every iteration: still the claim holder (else exit 3); read
`observed.json`; records; the acked mark (a consumer without state takes it from this step's shared
state, `Store`, and stands under this wait's subscription); `report`, `waking` under the
subscription of this wait's flags (`flags?`, `Subscription.ofFlags?`); `Moment.of`; act on
`nextMove`. Deliver, quiet and blind each take `Store.withConsumer`, check `stillMine` (else
exit 3), re-read `state.json`, and save the state `Deliver.finish` makes from that re-read and from
the `Shared` this iteration reported from (never a newer read of `observed.json`); then they unlock,
print the batch (or the quiet or blind line when the report is empty), and exit. At a quiet or blind
end the stale-tool note goes to stderr. The whole body runs under `try ... catch`: an IO error that
escapes (a full disk, a permission) prints one stdout line `watch: cannot run: the state folder
failed: <fixed words>; next: read GitHub over REST yourself, then re-arm after 10 min (a Monitor
running sleep 600 and then the same wait)` and exits 1. The `running`
handle is unlocked as the last act. -/
def wait (usage : String) (a : WaitArgs) : IO UInt32 := panic! "not implemented"

/-- Reads `observed.json` for the generation and the poll count, then writes one record. With no
`observed.json` yet, it warns that the record is dead (`Store.recordWrite`). -/
def own (a : OwnArgs) : IO UInt32 := panic! "not implemented"

/-- With `--as`: one line per fact: acked offer, pending offer and its repeats, whether a wait is
running, the caller's last subscription (`ConsumerState.last`), the shared state's generation, last
try, last success and failure streak. The subscription line is
`subscription: hears <kinds> on <items>[, riding <kinds>][ (catch-all)]`. The `riding` part lists
`rides.items` filtered by `topic.hears.has`, the riding kinds the caller hears, and is left out when
that list is empty (a caller with `--topics failed,alarms` and the default ride has none).
Without `--as`: one line per caller of this clone (`Store.callers`),
`caller <app>/<name>: hears <kinds> on <items>[, riding <kinds>][ (catch-all)]; waiting|not waiting`
(`state unreadable` in place of the subscription when its state does not read); then one
`overlap: <app>/<name> and <app>/<name> both hear <kinds>` line for each pair whose `Topic.overlap`
is not empty; then `watch: callers in other containers are not listed`. `status` writes
nothing. -/
def status (a : StatusArgs) : IO UInt32 := panic! "not implemented"

/-- Prints `{"<thread>":[ids]}` on one line, threads and ids as numbers, or refuses with exit 1,
also when any item is refused (`Reading.refused`). -/
def unanswered (a : UnansweredArgs) : IO UInt32 := panic! "not implemented"

/-- Tests only (`MITOS_WATCH_TEST=1`, else exit 2): one route's reader on a captured answer. -/
def read (args : List String) : IO UInt32 := panic! "not implemented"

/-- Tests only (`MITOS_WATCH_TEST=1`, else exit 2): `Shared.step` over a folder of polls. -/
def replay (args : List String) : IO UInt32 := panic! "not implemented"

def cli (args : List String) (usage : String) : IO UInt32 :=
  match args with
  | "wait" :: rest =>
    match parseWait rest {} with
    | some a => wait usage a
    | none => waitUsage "a flag is unknown, repeated or has no value" usage
  | "own" :: rest => run (parseOwn rest {}) own
  | "status" :: rest => run (parseStatus rest {}) status
  | "unanswered" :: rest => run (parseUnanswered rest {}) unanswered
  | "read" :: rest => read rest
  | "replay" :: rest => replay rest
  | _ => do IO.eprintln usage; return 2
where
  run {α : Type} (parsed : Option α) (k : α → IO UInt32) : IO UInt32 :=
    match parsed with
    | some a => k a
    | none => do IO.eprintln usage; return 2

end MitosGate.WatchCli
