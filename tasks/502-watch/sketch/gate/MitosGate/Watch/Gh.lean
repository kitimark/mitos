import Lean.Data.Json
import MitosGate.Watch.Route
import MitosGate.Watch.Voice

/-! UNCHECKED SKETCH (#502). The one `gh` process a route runs.

`gh` runs with stdin closed, in its own process group (`setsid`), with both pipes drained by
dedicated tasks, and is killed at its timeout: the pattern of `CheatsRun.runChild`, which this file
copies rather than imports, because that one runs its command inside a namespace. On Lean v4.35
`Child.kill` sends SIGKILL to the whole group of a child spawned with `setsid`; `mitos-lint-test`
already pins that.

Both pipes are drained as bytes (`readBinToEnd`): `Handle.readToEnd` throws on bytes that are not
UTF-8, and stderr is never decoded at all. stderr never leaves this file. A failure is named by the
route and fixed words (`main: gh exited 1`, `issueCommentsSince: timed out after 20 s`,
`checks #512: not UTF-8`, `main: no Date header`), never by what `gh` printed, so a token or a URL
that `gh` writes to stderr cannot reach a line, a state file or a log. `gate/watch-test.sh` pins it
with a fake `gh` that prints a token on stderr and fails. Tested, not proved. PR 4 adds this file
with `Answer` and `frame` only, imported by `WatchCli` for `watch read`, so it is in the build from
PR 4 on; PR 8 adds the process. -/

namespace MitosGate.Watch

open Lean (Json)

def callTimeoutMs : Nat := 20000

/-- How `runRoute` starts `gh`: nothing else in the watcher spawns a process. -/
def ghSpawn (gh : String) (args : List String) : IO.Process.SpawnArgs :=
  { cmd := gh, args := args.toArray, stdin := .null, stdout := .piped, stderr := .piped,
    setsid := true,
    env := #[("GH_PROMPT_DISABLED", some "1"), ("GH_NO_UPDATE_NOTIFIER", some "1"),
      ("NO_COLOR", some "1")] }

/-- A route's answer. `date` is GitHub's `Date` header, read only for a route with `headers`. -/
structure Answer where
  date : Option Epoch
  json : Json

/-- The header framing of a `--include` answer, pure, so that `watch read main <file>` tests it on a
captured answer from PR 4 on, before `runRoute` exists (PR 8). `gh api --include` writes the status
line ending in LF, then each header as `Name: value` ending in CRLF, then a CRLF line before the
body. So each line before the body is split on LF with one trailing CR stripped, the first line
that is then empty ends the headers, header names match without regard to case, and the `Date`
value, after its leading spaces, goes through `ofHttpDate?` as a `List Char`. A missing or
unreadable `Date` refuses with fixed words (`no Date header`). Returns GitHub's time and the body.
`gate/watch-fixtures/routes/` keeps one captured `--include` answer with its CR bytes. -/
def frame (text : String) : Except String (Epoch × String) := panic! "not implemented"

/-- Runs `gh` with `r.argv repo` for at most `min callTimeoutMs budgetMs`: drain both pipes as
bytes in dedicated tasks, poll `tryWait` against `IO.monoMsNow`, kill the group at the bound, reap
only after both pipes close. Then stdout through `String.fromUTF8?`; for a route with `headers`,
through `frame`; then the body through `Json.parse`. The stderr bytes are dropped. This bound is
what keeps a poll in flight within `pollBudget` of the wait's deadline; it is tested (PR 8's
fifo-blocking fake `gh`), not proved. -/
def runRoute {owner : String} (gh : String) (repo : Repo) (r : Route owner) (budgetMs : Nat) :
    IO (Except Excerpt Answer) :=
  panic! "not implemented"

end MitosGate.Watch
