import Lean.Data.Json
import MitosGate.Watch.Route
import MitosGate.Watch.Voice

namespace MitosGate.Watch

open Lean (Json)

def callTimeoutMs : Nat := 20000

def ghSpawn (gh : String) (args : List String) : IO.Process.SpawnArgs :=
  { cmd := gh, args := args.toArray, stdin := .null, stdout := .piped, stderr := .piped,
    setsid := true,
    env := #[("GH_PROMPT_DISABLED", some "1"), ("GH_NO_UPDATE_NOTIFIER", some "1"),
      ("NO_COLOR", some "1")] }

structure Answer where
  date : Option Epoch
  json : Json

/-- The header framing of a `--include` answer. `gh api --include` writes the status
line ending in LF, then each header as `Name: value` ending in CRLF, then a CRLF line before the
body. So each line before the body is split on LF with one trailing CR stripped, the first line
that is then empty ends the headers, header names match without regard to case, and the `Date`
value, after its leading spaces, goes through `ofHttpDate?` as a `List Char`. A missing or
unreadable `Date` refuses with fixed words (`no Date header`). Returns GitHub's time and the
body. -/
def frame (text : String) : Except String (Epoch × String) := panic! "not implemented"

/-- Runs `gh` with `r.argv repo` for at most `min callTimeoutMs budgetMs`: drain both pipes as
bytes in dedicated tasks, poll `tryWait` against `IO.monoMsNow`, kill the group at the bound, reap
only after both pipes close. Then stdout through `String.fromUTF8?`; for a route with `headers`,
through `frame`; then the body through `Json.parse`. The stderr bytes are dropped. -/
def runRoute {owner : String} (gh : String) (repo : Repo) (r : Route owner) (budgetMs : Nat) :
    IO (Except Excerpt Answer) :=
  panic! "not implemented"

end MitosGate.Watch
