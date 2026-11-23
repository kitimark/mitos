import Lean.Data.Json
import MitosGate.Accept
import MitosGate.Watch.Deliver

/-! UNCHECKED SKETCH (#502). The files: their codecs, the poll lease, the claim, the records, and
quarantine.

One folder per clone, beside main's tool, so every worktree of the clone shares it. The shim makes
it private (`umask 077`) and checks its mode and owner. `observed.json` names the repository and the
owner login it was made for; a mismatch reads as a bad file.

  <git-common-dir>/mitos-watch/
    observed.json                       the `Shared` state, replaced whole by rename
    poll.lock                           the lease: `IO.FS.Handle.tryLock`, never replaced
    consumers/<app>/<name>/state.json   the `ConsumerState`
    consumers/<app>/<name>/lock         an exclusive lock, held only to claim, to ack, and to save
                                        an offer, so every write of `state.json` follows a re-read
    consumers/<app>/<name>/claim        a random token; a newer wait of the same consumer replaces it
    consumers/<app>/<name>/running      every wait holds a shared lock on it while it runs
    consumers/<app>/<name>/writes/<r>   one `WriteRecord` per file, made with `.writeNew`, carrying
                                        the consumer's next `seq`; `readRecords` sorts by it
    classes/<app>/posts/<place>-<id>    one recorded post id per file, shared by the class
    *.bad.<r>                           a file that did not read, set aside

Every handle Lean opens is `O_CLOEXEC`, so `gh` inherits no lock. Writes go through
`Accept.writeByRename` (a new temporary, flush, rename), imported, not moved. There is no fsync in
Lean's API: after a crash a state file is the old one or the new one, never half of one, but a
record made just before the crash can be lost, and the only cost is one echo line.

Reading is bytes, then `String.fromUTF8?`, then `Json.parse`, then `fromJson?`, then the on-load
checks: `IO.FS.readFile` throws on bytes that are not UTF-8. The on-load checks are:
* `Shared.checked?` (the invariant every no-spin statement assumes: polls bounded, keys held once,
  each view map `WF`);
* `View.WF` of a consumer's acked and offered marks;
* `Names.of n.items = n` for every stored `Names`, so a stored list is sorted and has no repeats;
* `Excerpt.ofStored?` for every stored excerpt.
A file that fails any step is renamed to `*.bad.<r>` and read as absent: a bad `observed.json`
makes a new generation, so every consumer gets a reset line; a bad `state.json` makes that consumer
fresh, which tells it the current state. Nothing that did not read is ever trusted, and nothing is
lost silently.

A consumer without a usable state takes its mark from the shared state of each step:
`Mark.fresh s.gen (since.getD s.feed.floor)` for a new consumer (`--since` applies only here), and
`Mark.fresh "" 0` for one whose `state.json` was set aside, which no generation fits, so `report`
tells it the reset line. A new consumer saves its state with its first offer, and only once the
shared state has a cursor: a wait that ends before any poll succeeded saves nothing, its trailer's
number takes nothing, and the next wait starts new again. A `state.json` whose acked or offered
poll is above `observed.json`'s poll count (a restored copy, or a crash that kept one rename and
lost the other) is not set aside: its mark does not fit, so it resets with a line (`Mark.fits`).

Housekeeping, each one line in PR 8's cases:
* class post records older than `keep` are removed; a wait reads the records once at its start and
  again only when the records folder changes, not every 2 s step;
* `*.tmp.<r>` files older than an hour, left by a killed writer, are removed under the lease;
* an end takes the consumer's lock, checks `stillMine`, re-reads `state.json`, and saves the state
  that `Deliver.finish` makes from that re-read and from the shared state its last step reported
  from, never a newer `observed.json`; then it unlocks and prints. So a superseded wait that saves
  late cannot reuse an offer number, and no offer marks a state its batch did not report. The
  start of a wait (claim, ack) takes the same lock;
* the first `observed.json` and its generation are made under the lease, so two first waits cannot
  make two generations.

Every file carries `"version"`. A file with a newer version than this tool knows is not set aside:
the wait exits 1 with `watch: cannot run: the state is newer than this tool; next: run
.claude/scripts/watch.sh build`, so an old binary that a wait still runs never destroys a newer
file. A file with an older version is read by that version's codec and written back in the new
one, once. A new `state.json` is `Deliver.ConsumerState.fresh` with a random six-digit base drawn
here (`randomBase`).

The codecs are tested, not proved (`Json` is `partial`); `gate/watch-test.sh` round-trips every
fixture state and feeds damaged files and a newer version. Layout copies `Accept`'s file
helpers. -/

namespace MitosGate.Watch

open Lean (Json ToJson FromJson)

structure Paths where
  root : System.FilePath
  consumer : Consumer

def Paths.observed (p : Paths) : System.FilePath := p.root / "observed.json"
def Paths.lease (p : Paths) : System.FilePath := p.root / "poll.lock"
def Paths.home (p : Paths) : System.FilePath := p.root / "consumers" / p.consumer.app / p.consumer.name
def Paths.state (p : Paths) : System.FilePath := p.home / "state.json"
def Paths.claim (p : Paths) : System.FilePath := p.home / "claim"
def Paths.running (p : Paths) : System.FilePath := p.home / "running"
def Paths.writes (p : Paths) : System.FilePath := p.home / "writes"
def Paths.posts (p : Paths) : System.FilePath := p.root / "classes" / p.consumer.app / "posts"

/-- 16 random bytes as 32 lowercase hex digits: a generation, a claim token, a file suffix. -/
def randomHex : IO String := panic! "not implemented"

def version : Nat := 1

/-- What a read found. `newer`: a file of a later version, left in place. -/
inductive Read (α : Type)
  | ok (x : α)
  | absent
  | newer (v : Nat)

/-- Reads, decodes and runs `check`, or quarantines and answers `absent`. -/
def readOr {α β : Type} [FromJson α] (path : System.FilePath) (check : α → Option β) :
    IO (Read β) :=
  panic! "not implemented"

def write {α : Type} [ToJson α] (path : System.FilePath) (x : α) : IO Unit := do
  Accept.writeByRename (path.toString ++ ".tmp." ++ (← randomHex)) path (ToJson.toJson x).compress

/-- Runs `k` under the poll lease if no one else holds it; `none` when someone does. The lease is
held only for one poll (at most `pollBudget`), and a process that dies drops it. `k` must read
`observed.json` again and decide again whether a poll is due: the state the caller read before the
lease may be a poll old (`WatchCli.pollOnce`). -/
def withLease {α : Type} (p : Paths) (k : IO α) : IO (Option α) := do
  let h ← IO.FS.Handle.mk p.lease .append
  if ← h.tryLock (exclusive := true) then
    try return some (← k) finally h.unlock
  else return none

/-- A number from 100000 to 999999, from `IO.getRandomBytes`: the offer base of a new state. -/
def randomBase : IO Nat := panic! "not implemented"

/-- Runs `k` holding the consumer's exclusive lock (`lock`, blocking, bounded by `pollBudget`). The
claim, the ack and the offer save each run inside it, after a re-read of `state.json`. -/
def withConsumer {α : Type} (p : Paths) (k : IO α) : IO α := panic! "not implemented"

/-- Writes a new claim token and returns it. A wait that finds another token is superseded. -/
def claim (p : Paths) : IO String := panic! "not implemented"

/-- Read again inside `withConsumer` before an offer is saved, not only at the top of the loop. -/
def stillMine (p : Paths) (token : String) : IO Bool := panic! "not implemented"

/-- The handle stays open, holding a shared lock, for the whole wait. `WatchCli.wait` unlocks it
explicitly as its last act, so nothing frees the handle early. -/
def holdRunning (p : Paths) : IO IO.FS.Handle := do
  let h ← IO.FS.Handle.mk p.running .append
  h.lock (exclusive := false)
  return h

/-- `status`: a wait is running when an exclusive `tryLock` fails. -/
def waitRunning (p : Paths) : IO Bool := panic! "not implemented"

/-- A record needs the generation and poll count of `observed.json`. Before the clone's first wait
there is none, so `own` warns on stderr that the record is dead and the echo will wake once
(`HANDOVER.md`: run one wait before your first write). -/
def recordWrite (p : Paths) (r : WriteRecord) : IO Unit := panic! "not implemented"

def recordPost (p : Paths) (r : PostRecord) : IO Unit := panic! "not implemented"

/-- The consumer's records, writes sorted by `seq`; write files of another generation or spent for
`ackedPoll` are removed after they are read. -/
def readRecords (p : Paths) (gen : String) (ackedPoll : Nat) : IO Records :=
  panic! "not implemented"

end MitosGate.Watch
