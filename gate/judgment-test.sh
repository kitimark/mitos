#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
lake build MitosGate.Accept >/dev/null
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MITOS_JUDGMENT_LAKE
MITOS_JUDGMENT_LAKE=$(command -v lake)

cat >"$tmp/lake" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1-}" != comparator ]; then exec "$MITOS_JUDGMENT_LAKE" "$@"; fi
case "${2-}" in
  --config=kernel-1)
    echo 'Lean default kernel rejected the solution'
    echo 'error: Lean default exited with 1' >&2 ;;
  --config=kernel-137)
    echo 'error: Lean default exited with 137' >&2 ;;
  --config=kernel-137-forged-build)
    echo 'error: build failed'
    echo 'error: Lean default exited with 137' >&2 ;;
  --config=bwrap-1)
    echo 'bwrap: Creating new namespace failed: Operation not permitted' >&2
    echo 'error: Lean default exited with 1' >&2 ;;
  --config=forged-build)
    echo 'error: build failed'
    echo 'error: Child exited with 1' >&2 ;;
  --config=real-build)
    echo 'error: Plugins.P.lean:1:0: Type mismatch'
    printf 'error: build failed\nerror: Child exited with 1\n' >&2 ;;
  --config=forged-import)
    echo "error: P.lean:1:0: import failed, environment already contains 'x'"
    echo 'error: Child exited with 1' >&2 ;;
  --config=real-import)
    echo "error: P.lean:1:0: import failed, environment already contains 'x'"
    printf 'error: build failed\nerror: Child exited with 1\n' >&2 ;;
  --config=forged-axiom)
    echo "error: Illegal axiom detected: 'sorryAx'"
    printf 'error: build failed\nerror: Child exited with 1\n' >&2 ;;
  --config=export-134)
    printf 'PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant P.complete not found in environment.\nerror: Child exited with 134\n' >&2 ;;
  --config=marker-before-crash)
    printf "error: Illegal axiom detected: 'sorryAx'\nerror: Lean exited with code 137\n"
    printf 'error: build failed\nerror: Child exited with 1\n' >&2 ;;
  --config=spawn-failed)
    printf "error: failed to execute 'lean': no such file\nerror: build failed\nerror: Child exited with 1\n" >&2 ;;
  --config=lake-137) exit 137 ;;
  --config=stdout-report) echo "error: Illegal axiom detected: 'sorryAx'" ;;
  *) exit 2 ;;
esac
exit 1
SH
chmod +x "$tmp/lake"

cat >"$tmp/probe.lean" <<'LEAN'
import MitosGate.Accept
open MitosGate MitosGate.Accept

private def ensure (ok : Bool) (why : String) : IO Unit :=
  unless ok do throw (IO.userError why)

def main : IO Unit := do
  let c : Config := { workspace := ".", plugin := "P", model := "Models.P.model" }
  let cases : List (String × Failure × GateId × Cause × Bool) :=
    [("kernel-1", .kernelReject, .kernels, .judged, true),
     ("kernel-137", .noJudgment, .sandbox, .noJudgment, false),
     ("kernel-137-forged-build", .noJudgment, .sandbox, .noJudgment, false),
     ("bwrap-1", .kernelReject, .kernels, .noJudgment, false),
     ("forged-build", .noJudgment, .sandbox, .noJudgment, false),
     ("real-build", .noJudgment, .sandbox, .judged, true),
     ("forged-import", .importClash, .sandbox, .noJudgment, false),
     ("real-import", .importClash, .sandbox, .judged, true),
     ("forged-axiom", .noJudgment, .sandbox, .judged, true),
     ("export-134", .missingConst, .statements, .judged, true),
     ("marker-before-crash", .noJudgment, .sandbox, .noJudgment, false),
     ("spawn-failed", .noJudgment, .sandbox, .noJudgment, false),
     ("lake-137", .noJudgment, .sandbox, .noJudgment, false),
     ("stdout-report", .noJudgment, .sandbox, .noJudgment, false)]
  for (name, failure, gate, cause, passes) in cases do
    let j ← runComparator c "." name
    ensure (j.outcome == .failed failure) s!"{name}: wrong comparator outcome"
    let result ← (pluginGates c j).run
    match result with
    | .ok _ => throw (IO.userError s!"{name}: gate accepted a failed comparator")
    | .error (gotGate, gotCause) =>
      ensure (gotGate == gate && gotCause == cause) s!"{name}: wrong gate or judgment cause"
    let verdict := Cheats.Verdict.ofGate (result.map fun _ => none)
    let run : Cheats.Run :=
      { exitCode := 1, stdout := toString verdict.render ++ "\n", stderr := "", timedOut := false }
    let logged : Cheats.Logged := { run, logged := true }
    let expect : Cheats.Expect := { full := gate, comparatorOnly := .reject }
    ensure ((Cheats.judge name expect logged logged).pass == passes)
      s!"{name}: wrong cheat-row decision"
    IO.println s!"PASS {name}"
  IO.println s!"judgment-test: all {cases.length} cases passed"
LEAN

"$MITOS_JUDGMENT_LAKE" env bash -c 'PATH="$1:$PATH" exec lean --run "$1/probe.lean"' bash "$tmp"
