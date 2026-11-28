import Lean.Data.Json
import MitosGate.Accept
import MitosGate.Watch.Deliver

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

def withLease {α : Type} (p : Paths) (k : IO α) : IO (Option α) := do
  let h ← IO.FS.Handle.mk p.lease .append
  if ← h.tryLock (exclusive := true) then
    try return some (← k) finally h.unlock
  else return none

/-- A number from 100000 to 999999, from `IO.getRandomBytes`: the offer base of a new state. -/
def randomBase : IO Nat := panic! "not implemented"

/-- Runs `k` holding the consumer's exclusive lock (`lock`, blocking, bounded by `pollBudget`). -/
def withConsumer {α : Type} (p : Paths) (k : IO α) : IO α := panic! "not implemented"

/-- Writes a new claim token and returns it. A wait that finds another token is superseded. -/
def claim (p : Paths) : IO String := panic! "not implemented"

def stillMine (p : Paths) (token : String) : IO Bool := panic! "not implemented"

def holdRunning (p : Paths) : IO IO.FS.Handle := do
  let h ← IO.FS.Handle.mk p.running .append
  h.lock (exclusive := false)
  return h

/-- `status`: a wait is running when an exclusive `tryLock` fails. -/
def waitRunning (p : Paths) : IO Bool := panic! "not implemented"

/-- `status` with no `--as`: every `consumers/<app>/<name>/` of this clone, with its state when
`state.json` reads (`none` when it does not). Read-only: it takes no lock but `waitRunning`'s and
sets no file aside. -/
def callers (root : System.FilePath) : IO (List (Consumer × Option ConsumerState)) :=
  panic! "not implemented"

/-- A record needs the generation and poll count of `observed.json`. Before the clone's first wait
there is none, so `own` warns on stderr that the record is dead and the echo will wake once. -/
def recordWrite (p : Paths) (r : WriteRecord) : IO Unit := panic! "not implemented"

def recordPost (p : Paths) (r : PostRecord) : IO Unit := panic! "not implemented"

/-- The consumer's records, writes sorted by `seq`; write files of another generation or spent for
`ackedPoll` are removed after they are read. -/
def readRecords (p : Paths) (gen : String) (ackedPoll : Nat) : IO Records :=
  panic! "not implemented"

end MitosGate.Watch
