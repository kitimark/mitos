/-! Small IO helpers shared by the gate commands. -/

namespace MitosGate

/-- Run a command; return (exit code, stdout ++ stderr). -/
def run (cmd : String) (args : Array String) (cwd : Option System.FilePath := none)
    (stdin : Option String := none) : IO (UInt32 × String) := do
  let out ← IO.Process.output { cmd, args, cwd } stdin
  return (out.exitCode, out.stdout ++ out.stderr)

/-- All `.lean` files under `dir`, sorted. -/
def leanFiles (dir : System.FilePath) : IO (Array System.FilePath) := do
  if !(← dir.isDir) then return #[]
  let fs ← dir.walkDir
  let fs := fs.filter (·.extension == some "lean")
  return fs.qsort (·.toString < ·.toString)

def copyFile (src dst : System.FilePath) : IO Unit := do
  if let some p := dst.parent then IO.FS.createDirAll p
  IO.FS.writeBinFile dst (← IO.FS.readBinFile src)

/-- Copy every `.lean` file under `src` to the same relative path under `dst`. -/
def copyLeanTree (src dst : System.FilePath) : IO Unit := do
  for f in ← leanFiles src do
    let rel := (f.toString.drop (src.toString.length + 1)).toString
    copyFile f (dst / rel)

/-- `sha256sum` of a string. -/
def sha256 (s : String) : IO String := do
  let (code, out) ← run "sha256sum" #["-"] none (some s)
  if code != 0 then throw <| IO.userError s!"sha256sum failed: {out}"
  return (out.splitOn " ").head!

def trim (s : String) : String := (s.trimAscii).toString

end MitosGate
