import Lean.Data.Json
import Mutants

open Mutants Lean

def usage : String := "usage: mitos-mutants [--paranoid] [--keep] [<case>...]
       mitos-mutants --prepare <dir> <case>...
  Run from the repository root. Lints each case's Lean text, then judges every case in
  eval/mutants/cases/, or the named ones, with the sandboxed lake comparator. --paranoid also runs
  the external kernels. --keep keeps the workspaces. Logs go to .lake/mutants/. Exit 0: every case
  as expected; 1: not; 2: could not run.
  --prepare writes each named case's workspaces to <dir>/<case>/ (refutation or values run) and
  <dir>/<case>.holes/ (hole run), and judges nothing; it writes none for a case the lint refuses.
  REFUSED BY LINT: the case's Lean text holds code that runs or declares syntax while Lean
  elaborates it, imports a module outside the approved core and the implementation, or declares,
  enters or opens a name outside the namespaces it may use.
  UNBOUND: the mutant's implementation alone does not build the approved definition holes, or the
  gate accepts proofs that are not about them.
  Before anything else, it builds the approved Challenge and compares what Lean declares in it
  and how Lean's parser reads it with what its line reader read, and it builds every Challenge it
  will generate for the cases and compares what Lean declares in each with what it must state; any
  difference stops it (exit 2)."

structure Config where
  paranoid : Bool := false
  keep     : Bool := false
  prepare  : Option System.FilePath := none
  cases    : List String := []

def parseArgs : List String → Config → Except String Config
  | [], c => .ok c
  | "--paranoid" :: rest, c => parseArgs rest { c with paranoid := true }
  | "--keep" :: rest, c => parseArgs rest { c with keep := true }
  | "--prepare" :: d :: rest, c => parseArgs rest { c with prepare := some d }
  | a :: rest, c =>
    if a.startsWith "-" then .error s!"unknown option {a}" else parseArgs rest { c with cases := c.cases ++ [a] }

def clean (s : String) : String :=
  String.join <| s.toList.map fun c =>
    let n := c.toNat
    if n < 0x20 || (0x7F ≤ n && n ≤ 0x9F) || (0x200B ≤ n && n ≤ 0x200F) || (0x2028 ≤ n && n ≤ 0x202E) ||
        (0x2066 ≤ n && n ≤ 0x2069) || n == 0xFEFF || c == '\\' then
      s!"\\u\{{String.ofList (Nat.toDigits 16 n)}}"
    else c.toString

def inPackage (dirName : String) (names : List String) (path : String) : Bool :=
  names.any fun n =>
    let dir := ((dirName : System.FilePath) / n).toString
    path == dir || (dir ++ System.FilePath.pathSeparator.toString).isPrefixOf path

def sourcesOnly (dirName : String) (names : List String) (files : List (String × String)) :
    List (String × String) :=
  files.filter fun (path, _) => !inPackage dirName names path

theorem inPackage_iff (dirName : String) (names : List String) (path : String) :
    inPackage dirName names path = true ↔
      ∃ n, n ∈ names ∧
        (path = ((dirName : System.FilePath) / n).toString ∨
          (((dirName : System.FilePath) / n).toString ++
              System.FilePath.pathSeparator.toString).isPrefixOf path = true) := by
  simp only [inPackage, List.any_eq_true, Bool.or_eq_true_iff, beq_iff_eq]

theorem sourcesOnly_excludes {dirName : String} {names : List String}
    {files : List (String × String)} {path body : String}
    (h : inPackage dirName names path = true) :
    (path, body) ∉ sourcesOnly dirName names files := by
  simp [sourcesOnly, List.mem_filter, h]

theorem sourcesOnly_keeps {dirName : String} {names : List String}
    {files : List (String × String)} {path body : String}
    (hmem : (path, body) ∈ files) (h : inPackage dirName names path = false) :
    (path, body) ∈ sourcesOnly dirName names files := by
  simp [sourcesOnly, List.mem_filter, hmem, h]

def coreFiles (core : System.FilePath) (skip : List String := []) : IO (List (String × String)) := do
  let paths ← core.walkDir fun p => do
    if p.fileName == some ".lake" then return false
    let rel := if p.toString.length ≤ core.toString.length then ""
      else (p.toString.drop (core.toString.length + 1)).toString
    return !(skip.any fun dir => rel == dir || (dir ++ System.FilePath.pathSeparator.toString).isPrefixOf rel)
  let mut out := #[]
  for p in paths do
    if ← p.isDir then continue
    let rel := (p.toString.drop (core.toString.length + 1)).toString
    out := out.push (rel, ← IO.FS.readFile p)
  return (out.qsort (·.1 < ·.1)).toList

def readPackageSpec (manifest : Json) : Except String (Option (String × List String)) := do
  let arr ← match manifest.getObjVal? "packages" with
    | .ok (.arr a) => pure a
    | .ok _ => throw "packages is not an array"
    | .error _ => pure (#[] : Array Json)
  if arr.isEmpty then return none
  let dirName ← match manifest.getObjVal? "packagesDir" with
    | .ok (.str s) => pure s
    | .ok _ => throw "packagesDir is not a string"
    | .error _ => pure ".lake/packages"
  let p : System.FilePath := dirName
  let comps := p.components.filter fun c => c != "." && !c.isEmpty
  if p.isAbsolute || comps.isEmpty || comps.any (· == "..") then
    throw "packagesDir must be a relative path inside the workspace"
  let mut names : Array String := #[]
  for p in arr do
    match p.getObjValAs? String "name" with
    | .ok n => names := names.push n
    | .error _ => throw "a package has no string name"
  return some (dirName, names.toList)

private def specOf (s : String) : Except String (Option (String × List String)) := do
  readPackageSpec (← Json.parse s)

private def specNone (s : String) : Bool :=
  match specOf s with | .ok none => true | _ => false

private def specSome (s dir : String) (names : List String) : Bool :=
  match specOf s with | .ok (some p) => p.1 == dir && p.2 == names | _ => false

private def specBad (s : String) : Bool :=
  match specOf s with | .error _ => true | .ok _ => false

#guard specNone "{}"
#guard specNone "{\"packages\":[]}"
#guard specNone "{\"packagesDir\":\".lake/packages\",\"packages\":[]}"
#guard specSome "{\"packages\":[{\"name\":\"batteries\"}]}" ".lake/packages" ["batteries"]
#guard specSome "{\"packagesDir\":\"deps\",\"packages\":[{\"name\":\"a\"}]}" "deps" ["a"]
#guard specBad "{\"packagesDir\":\"/opt/pkgs\",\"packages\":[{\"name\":\"a\"},{\"name\":\"b\"}]}"
#guard specBad "{\"packagesDir\":\"..\",\"packages\":[{\"name\":\"a\"}]}"
#guard specBad "{\"packagesDir\":\"../x\",\"packages\":[{\"name\":\"a\"}]}"
#guard specBad "{\"packagesDir\":\"\",\"packages\":[{\"name\":\"a\"}]}"
#guard specBad "{\"packagesDir\":\".\",\"packages\":[{\"name\":\"a\"}]}"
#guard specBad "{\"packages\":[{}]}"
#guard specBad "{\"packages\":1}"

def pathTop (p : System.FilePath) : Option String :=
  (p.components.filter fun c => c != "." && !c.isEmpty).head?

def overlapsSources (rel : System.FilePath) (files : List (String × String)) : Bool :=
  match pathTop rel with
  | none => true
  | some top => files.any fun (path, _) => pathTop path == some top

#guard overlapsSources ".lake/packages" [("Mitos/Core.lean", "")] == false
#guard overlapsSources "deps" [("Challenge/Resolver.lean", "")] == false
#guard overlapsSources "Mitos" [] == false
#guard overlapsSources "Mitos" [("Mitos/Core.lean", "")]
#guard overlapsSources "Mitos/Proofs" [("Mitos/Core.lean", "")]
#guard overlapsSources "lakefile.toml" [("lakefile.toml", "")]
#guard inPackage "deps" ["batteries"] "deps/batteries/Foo.lean"
#guard inPackage "deps" ["batteries"] "deps/Extra.lean" == false
#guard inPackage "deps" ["batteries"] "deps/batteries-extra/Foo.lean" == false
#guard overlapsSources "deps" (sourcesOnly "deps" ["batteries"] [("deps/batteries/Foo.lean", "")]) == false
#guard overlapsSources "deps" (sourcesOnly "deps" ["batteries"]
  [("deps/batteries/Foo.lean", ""), ("deps/Extra.lean", "")])

def packagesMissing : String :=
  "core's packages are not resolved: run cd core && lake build first"

structure ResolvedPackages where
  dir   : System.FilePath
  rel   : System.FilePath
  names : List String

inductive PackageLink where
  | symlink
  | hardlink
  | copy
  deriving DecidableEq

def PackageLink.name : PackageLink → String
  | .symlink => "symlink"
  | .hardlink => "hardlink"
  | .copy => "copy"

structure PackageReuse where
  packages : ResolvedPackages
  link     : PackageLink

def resolvedPackages (core : System.FilePath) : ExceptT String IO (Option ResolvedPackages) := do
  let text ← IO.FS.readFile (core / "lake-manifest.json")
  let json ← match Json.parse text with
    | .ok j => pure j
    | .error e => throw s!"core/lake-manifest.json: {e}"
  let spec ← match readPackageSpec json with
    | .ok s => pure s
    | .error e => throw s!"core/lake-manifest.json: {e}"
  let some (dirName, names) := spec | return none
  let rel : System.FilePath := dirName
  let dir := core / rel
  for n in names do
    unless ← (dir / n).isDir do throw packagesMissing
  return some { dir, rel, names }

def clearPackagesLink (dest : System.FilePath) : IO Unit := do
  try
    do
      let info ← dest.symlinkMetadata
      if info.type == .symlink then IO.FS.removeFile dest else IO.FS.removeDirAll dest
  catch
    | .noFileOrDirectory .. => pure ()
    | e => throw e

def placePackages (workspace : System.FilePath) (reuse : PackageReuse)
    (files : List (String × String) := []) : IO Bool := do
  if overlapsSources reuse.packages.rel files then return false
  let dest := workspace / reuse.packages.rel
  IO.FS.createDirAll (workspace / ".lake")
  if let some parent := dest.parent then IO.FS.createDirAll parent
  clearPackagesLink dest
  let src ← IO.FS.realPath reuse.packages.dir
  let out ← match reuse.link with
    | .symlink => IO.Process.output { cmd := "ln", args := #["-s", src.toString, dest.toString] }
    | .hardlink => IO.Process.output { cmd := "cp", args := #["-al", src.toString, dest.toString] }
    | .copy => IO.Process.output { cmd := "cp", args := #["-a", src.toString, dest.toString] }
  return out.exitCode == 0

def sandboxSees (dir rel : System.FilePath) (names : List String) : IO Bool := do
  let out ← IO.Process.output {
    cmd := "bwrap"
    args := #[
      "--ro-bind", "/", "/",
      "--tmpfs", "/home", "--tmpfs", "/root", "--tmpfs", "/run/user", "--tmpfs", "/tmp",
      "--tmpfs", "/run", "--tmpfs", "/var",
      "--dir", "/tmp/home", "--dev", "/dev", "--proc", "/proc", "--clearenv",
      "--ro-bind", dir.toString, dir.toString,
      "--bind", (dir / ".lake").toString, (dir / ".lake").toString,
      "--setenv", "PATH", "/usr/bin:/bin",
      "--unshare-all", "--die-with-parent",
      "--chdir", dir.toString,
      "--", "/bin/sh", "-c",
      "rel=$1; shift; for n; do test -d \"$rel/$n\" || exit 1; done", "sh", rel.toString
    ] ++ names.toArray
  }
  return out.exitCode == 0

def fileSha (p : System.FilePath) : IO (Option String) := do
  let out ← IO.Process.output { cmd := "sha256sum", args := #[p.toString] }
  if out.exitCode != 0 then return none
  match (out.stdout.splitOn " ").head? with
  | some s => return if s.isEmpty then none else some s
  | none => return none

def gitIndexMoves (pkg : System.FilePath) : IO (Option Bool) := do
  let idx := pkg / ".git" / "index"
  unless ← idx.pathExists do return some false
  let tmp ← IO.FS.createTempDir
  try
    let bak := tmp / "index"
    let some h1 ← fileSha idx | return none
    let copied ← IO.Process.output { cmd := "cp", args := #["-a", idx.toString, bak.toString] }
    if copied.exitCode != 0 then return none
    let status ← IO.Process.output {
      cmd := "env"
      args := #[s!"GIT_INDEX_FILE={bak}", "git", "-C", pkg.toString, "status", "--porcelain"]
    }
    if status.exitCode != 0 then return none
    let some h2 ← fileSha bak | return none
    return some (h1 != h2)
  finally
    IO.FS.removeDirAll tmp

def symlinkWrites (pkgs : ResolvedPackages) : IO Bool := do
  for n in pkgs.names do
    match ← gitIndexMoves (pkgs.dir / n) with
    | some false => pure ()
    | some true | none => return true
  return false

def chooseLink (pkgs : ResolvedPackages) : ExceptT String IO PackageLink := do
  for m in [PackageLink.symlink, .hardlink, .copy] do
    let dir ← IO.FS.createTempDir
    try
      let placed ← placePackages dir { packages := pkgs, link := m }
      if placed && (← sandboxSees dir pkgs.rel pkgs.names) then
        let writes ← if m == .symlink then symlinkWrites pkgs else pure false
        if !writes then return m
    finally
      IO.FS.removeDirAll dir
  throw "could not reuse core's packages"

def prepareReuse (core : System.FilePath) : ExceptT String IO (Option PackageReuse) := do
  let some pkgs ← resolvedPackages core | return none
  return some { packages := pkgs, link := ← chooseLink pkgs }

def searchPath (dir : System.FilePath) (reuse : Option PackageReuse) : List System.FilePath :=
  let built := dir / ".lake" / "build" / "lib" / "lean"
  match reuse with
  | none => [built]
  | some r =>
    built :: r.packages.names.map fun (n : String) =>
      dir / r.packages.rel / (n : System.FilePath) / ".lake" / "build" / "lib" / "lean"

def judge (cfg : Config) (toolchain : String) (files : List (String × String))
    (config : Option String) (log : System.FilePath) (reuse : Option PackageReuse) : IO Run := do
  let dir ← IO.FS.createTempDir
  try
    IO.FS.writeFile (dir / "lean-toolchain") toolchain
    for (rel, txt) in files do
      if let some p := (dir / rel).parent then IO.FS.createDirAll p
      IO.FS.writeFile (dir / rel) txt
    if let some r := reuse then
      unless ← placePackages dir r files do
        IO.FS.writeFile log "could not reuse core's packages"
        return .failed
    let args := #["comparator"] ++ (config.map (#[s!"--config={·}"])).getD #[] ++
      (if cfg.paranoid then #["--paranoid"] else #[])
    (← IO.getStdout).flush
    let out ← IO.Process.output { cmd := "lake", args, cwd := dir }
    let text := out.stdout ++ out.stderr
    IO.FS.writeFile log s!"$ lake {" ".intercalate args.toList}\nexit {out.exitCode}\n{text}"
    return Run.ofExit out.exitCode text
  catch e =>
    IO.FS.writeFile log s!"could not run lake comparator: {e}"
    return .failed
  finally
    if cfg.keep then IO.println s!"  (workspace kept: {dir})" else IO.FS.removeDirAll dir

structure Approved where
  toolchain  : String
  files      : List (String × String)
  config     : Json
  chalModule : String
  challenge  : List Line
  theorems   : List String
  defs       : List String
  impls      : List String
  checked    : List String := []

def strs (xs : List String) : Json := Json.arr (xs.toArray.map Json.str)

def holesConfig (a : Approved) : String :=
  ((a.config.setObjVal! "solution_module" (.str "Mitos.Proofs.Holes")).setObjVal!
    "theorem_names" (strs [])).pretty

def valuesConfig (a : Approved) : String :=
  ((a.config.setObjVal! "challenge_module" (.str "Challenge.Mutant")).setObjVal!
    "definition_names" (strs [])).pretty

def refutationConfig (a : Approved) (ts : List String) : String :=
  let names := Output.refutationNames a.defs ts
  ((((a.config.setObjVal! "challenge_module" (.str "Challenge.Mutant")).setObjVal!
    "solution_module" (.str "Mitos.Proofs.Refute")).setObjVal! "theorem_names" (strs names)).setObjVal!
    "definition_names" (strs [])).pretty

def generated : List String :=
  ["Challenge/Mutant.lean", "Mitos/Proofs/Holes.lean", "Mitos/Proofs/Refute.lean",
    "Mitos/Proofs/RefuteCase.lean", "holes.json", "values.json", "mutant.json"]

structure Prepared where
  mutant     : Mutant
  lint       : List String
  holes      : List (String × String)
  approved   : List (String × String)
  values     : List (String × String)
  refutation : Option (List (String × String))

def lintCase (env : Environment) (m : Mutant) (files : List (String × String))
    (refute : Option String) (defs : List String) : ExceptT String IO (List String) := do
  let mut found := #[]
  for e in m.edits do
    for w in Lint.replaceProblems e.replace do
      found := found.push s!"mutant: replace= in {e.file}: {w}"
  for (p, k) in Lint.targets m do
    let some txt := files.lookup p | throw s!"{p}: no such file in core/"
    found := found ++ (← Lint.check env k s!"core/{p} (edited)" txt)
  if let some src := refute then
    found := found ++ (← Lint.check env (.refute (defs.map (·.splitOn "."))) "Refute.lean" src)
  return found.toList

def prepare (env : Environment) (a : Approved) (casesDir : System.FilePath) (name : String) :
    ExceptT String IO Prepared := do
  let dir := casesDir / name
  unless ← dir.isDir do throw "no such case directory"
  unless ← (dir / "mutant").pathExists do throw "no mutant file"
  let m ← match parse (← IO.FS.readFile (dir / "mutant")) with
    | .ok m => pure m
    | .error e => throw s!"mutant: {e}"
  let wants := match m.expect with
    | .breaks _ => ["Refute.lean", "mutant"]
    | .survives _ => ["mutant"]
  let have_ := ((← dir.readDir).map (·.fileName)).qsort (· < ·) |>.toList
  if have_ != wants then throw s!"holds {have_}, expected {wants}"
  if let some g := generated.find? fun g => a.files.any (·.1 == g) then
    throw s!"core/{g} exists; the runner writes that path"
  let files ← match applyEdits a.files m.edits with
    | .ok fs => pure fs
    | .error e => throw e
  let refuteSrc ← match m.expect with
    | .breaks _ => some <$> IO.FS.readFile (dir / "Refute.lean")
    | .survives _ => pure none
  let lint ← lintCase env m files refuteSrc a.defs
  let core ← match holeCore a.files m with
    | .ok fs => pure fs
    | .error e => throw e
  let holes := core ++ [("Mitos/Proofs/Holes.lean", holesSolution (core.map (·.1))),
    ("holes.json", holesConfig a)]
  let checked (g : Except String Output.Gen) : ExceptT String IO String := do
    let g ← match g with
      | .ok g => pure g
      | .error e => throw e
    unless a.checked.contains g.text do throw s!"{g.what} was not checked as Lean builds it"
    return g.text
  let byValue ← checked (Output.valuesGen a.impls a.challenge)
  let values := [("Challenge/Mutant.lean", byValue), ("values.json", valuesConfig a)]
  match m.expect with
  | .survives _ => return { mutant := m, lint, holes, approved := files, values, refutation := none }
  | .breaks ts =>
    let chal ← checked (Output.refutationGen a.impls a.defs a.challenge ts)
    let extra := [("Challenge/Mutant.lean", chal),
      ("Mitos/Proofs/RefuteCase.lean", refuteSrc.getD ""),
      ("Mitos/Proofs/Refute.lean", refutationSolution a.defs),
      ("mutant.json", refutationConfig a ts)]
    return { mutant := m, lint, holes, approved := files, values, refutation := some extra }

def caseLogs (logDir : System.FilePath) (name : String) : List System.FilePath :=
  ["refutation", "values", "approved", "holes"].map fun s => logDir / s!"{name}.{s}.log"

def runCase (cfg : Config) (env : Environment) (a : Approved) (casesDir logDir : System.FilePath)
    (name : String) (reuse : Option PackageReuse) : IO Judged := do
  for log in caseLogs logDir name do
    if ← log.pathExists then IO.FS.removeFile log
  let p ← match ← (prepare env a casesDir name).run with
    | .ok p => pure p
    | .error e => return .invalid e
  let ran := Judged.ran p.mutant.expect p.mutant.rejects
  unless p.lint.isEmpty do return ran { lint := p.lint }
  let holes ← judge cfg a.toolchain p.holes (some "holes.json") (logDir / s!"{name}.holes.log") reuse
  if holes != .accepted then return ran { holes }
  let approved ← judge cfg a.toolchain p.approved none (logDir / s!"{name}.approved.log") reuse
  match approved with
  | .accepted =>
    let values ← judge cfg a.toolchain (p.approved ++ p.values) (some "values.json")
      (logDir / s!"{name}.values.log") reuse
    return ran { holes, approved, values }
  | .rejected =>
    let some extra := p.refutation | return ran { holes, approved }
    let refutation ← judge cfg a.toolchain (p.approved ++ extra) (some "mutant.json")
      (logDir / s!"{name}.refutation.log") reuse
    return ran { holes, approved, refutation }
  | .failed => return ran { holes, approved }

def writeFiles (toolchain : String) (dir : System.FilePath) (files : List (String × String))
    (reuse : Option PackageReuse) : IO Unit := do
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "lean-toolchain") toolchain
  for (rel, txt) in files do
    if let some d := (dir / rel).parent then IO.FS.createDirAll d
    IO.FS.writeFile (dir / rel) txt
  if let some r := reuse then
    unless ← placePackages dir r files do
      throw <| IO.userError "could not reuse core's packages"

def generatedFor (a : Approved) (casesDir : System.FilePath) (cases : List String) :
    IO (List Output.Gen) := do
  let add (gs : Array Output.Gen) : Except String Output.Gen → Array Output.Gen
    | .ok g => if gs.any (·.text == g.text) then gs else gs.push g
    | .error _ => gs
  let mut gens := add #[] (Output.valuesGen a.impls a.challenge)
  for name in cases do
    let src ← try some <$> IO.FS.readFile (casesDir / name / "mutant") catch _ => pure none
    if let some (.ok m) := src.map parse then
      if let .breaks ts := m.expect then
        gens := add gens (Output.refutationGen a.impls a.defs a.challenge ts)
  return gens.toList

structure Checked where
  decls    : Nat
  commands : Nat
  gens     : Nat

class Detach (α : Type) where
  detach : α → α

def detachFromRegions (s : String) : String := String.ofList s.toList

instance : Detach String := ⟨detachFromRegions⟩
instance : Detach Unit := ⟨fun _ => ()⟩
instance : Detach Nat := ⟨fun n => n.repr.toNat!⟩
instance {α β : Type} [Detach α] [Detach β] : Detach (α × β) :=
  ⟨fun (a, b) => (Detach.detach a, Detach.detach b)⟩

unsafe def withImportUnsafe {α : Type} [Detach α] (m : String)
    (act : Environment → ExceptT String IO α) : ExceptT String IO α := ExceptT.mk do
  let env ← importModules #[{ module := m.toName }] {}
  try
    match ← (act env).run with
    | .ok a => return .ok (Detach.detach a)
    | .error e => return .error (Detach.detach e)
  catch e => return .error (Detach.detach (toString e))
  finally env.freeRegions

@[implemented_by withImportUnsafe]
opaque withImport {α : Type} [Detach α] (m : String) (act : Environment → ExceptT String IO α) :
  ExceptT String IO α

def leanCheck (a : Approved) (gens : List Output.Gen) (log : System.FilePath)
    (reuse : Option PackageReuse) : ExceptT String IO Checked := do
  let genPath (k : Nat) : String := s!"Challenge/MutantsOutput{k}.lean"
  let numbered := (List.range gens.length).zip gens
  let outProbes ← Output.outProbes.mapM fun p => do
    match Output.refutationGen a.impls Output.probeDefs p.lines p.breaks with
    | .ok g => pure (p, g, s!"{moduleOf p.path |>.replace "." "/"}Gen.lean")
    | .error e => throw s!"{p.path}: {e}"
  let first := CrossCheck.probes.map fun p => (p.path, p.source)
  let second := numbered.map (fun (k, g) => (genPath k, g.text)) ++
    outProbes.flatMap fun (p, g, gp) => [(p.path, p.source), (gp, g.text)]
  for (p, _) in first ++ second do
    if a.files.any (·.1 == p) then throw s!"core/{p} exists; the runner writes that path"
  let chalPath := "/".intercalate (a.chalModule.splitOn ".") ++ ".lean"
  let some chalSrc := a.files.lookup chalPath | throw s!"core/{chalPath} not found"
  let dir ← IO.FS.createTempDir
  try
    IO.FS.writeFile log ""
    let build (what : String) (files : List (String × String)) (mods : List String) :
        ExceptT String IO Unit := do
      writeFiles a.toolchain dir files reuse
      (← IO.getStdout).flush
      let out ← IO.Process.output { cmd := "lake", args := #["build"] ++ mods.toArray, cwd := dir }
      let text := out.stdout ++ out.stderr
      IO.FS.writeFile log
        ((← IO.FS.readFile log) ++ s!"$ lake build {" ".intercalate mods}\nexit {out.exitCode}\n{text}\n")
      unless out.exitCode == 0 do
        let err := ((text.splitOn "\n").find? (·.startsWith "error:")).getD ""
        throw s!"lake build of {what} failed: {err} ({log})"
    build "the Challenge module and the cross-check's probes" (a.files ++ first)
      (a.chalModule :: first.map (moduleOf ·.1))
    initSearchPath (← findSysroot) (searchPath dir reuse)
    let load {α : Type} [Detach α] (m : String)
        (act : Environment → List String → List CrossCheck.Decl → ExceptT String IO α) :
        ExceptT String IO α :=
      withImport m fun env => do
        let some (imps, ds) := CrossCheck.built env m.toName
          | throw s!"{m}: not in the environment that imports it"
        act env imps ds
    let check (aenv : Environment) (am m : String) (g : Output.Gen)
        (judge : List Output.OutProblem → ExceptT String IO Unit) : ExceptT String IO Unit := do
      let want ← ExceptT.adapt (s!"{g.what}: {·}") (ExceptT.mk (Output.wantTypes aenv am.toName g.wants))
      withImport m fun env => do
        let some (imps, found) := Output.builtTheorems env m.toName
          | throw s!"{m}: not in the environment that imports it"
        judge (Output.outProblems Output.sameType want g.imports imps found)
    let (decls, commands) ← load a.chalModule fun approvedEnv imps ds => do
      let ps := CrossCheck.problems a.challenge a.defs imps ds
      unless ps.isEmpty do
        throw ("the refutation reader read the Challenge otherwise than Lean built it: " ++
          "; ".intercalate (ps.map (·.text)).eraseDups)
      for p in CrossCheck.probes do
        load (moduleOf p.path) fun _ pi pd => do
          unless p.caught pi pd do
            let found := (CrossCheck.problems p.lines p.defs pi pd).map (·.text)
            throw (s!"the cross-check missed a known misread in {p.path}: " ++
              s!"expected {p.expect}, found {found}")
      let penv ← Output.parseEnv (CrossCheck.importNames a.challenge)
      let parsed (src : String) : ExceptT String IO (List String × List String × List Output.Cmd) :=
        ExceptT.adapt (s!"Lean's parser stops: {·}") (ExceptT.mk (Output.readParse penv src))
      let (hdr, pimps, cmds) ← parsed chalSrc
      let pps := Output.parseProblems a.challenge hdr pimps cmds
      unless pps.isEmpty do
        throw ("the refutation reader read the Challenge otherwise than Lean's parser: " ++
          "; ".intercalate (pps.map (·.text)))
      for p in Output.parseProbes do
        let (h, i, c) ← parsed p.source
        let found := (Output.parseProblems p.lines h i c).map (·.key)
        unless p.expect.all found.contains do
          throw s!"the parse check missed a known misread in probe {p.name}: expected {p.expect}, found {found}"
      build "the generated Challenges and the output check's probes" second (second.map (moduleOf ·.1))
      for (k, g) in numbered do
        check approvedEnv a.chalModule (moduleOf (genPath k)) g fun ps =>
          unless ps.isEmpty do
            throw (s!"{g.what}, as Lean built it, does not state what it must: " ++
              "; ".intercalate (ps.map (·.text)))
      return (ds.length, cmds.length)
    for (p, g, gp) in outProbes do
      withImport (moduleOf p.path) fun aenv => check aenv (moduleOf p.path) (moduleOf gp) g fun ps => do
        let found := ps.map (·.key)
        unless p.expect.all found.contains do
          throw s!"the output check missed a known misread in {p.path}: expected {p.expect}, found {found}"
    return { decls, commands, gens := gens.length }
  finally
    IO.FS.removeDirAll dir

def writeWorkspaces (env : Environment) (a : Approved) (casesDir out : System.FilePath)
    (cases : List String) (reuse : Option PackageReuse) : IO UInt32 := do
  let mut code := 0
  for name in cases do
    match ← (prepare env a casesDir name).run with
    | .error e => IO.eprintln s!"{clean name}: {clean e}"; code := 1
    | .ok p =>
      unless p.lint.isEmpty do
        for l in p.lint do IO.eprintln s!"{clean name}: lint: {clean l}"
        code := 1
        continue
      writeFiles a.toolchain (out / name) (p.approved ++ p.refutation.getD p.values) reuse
      writeFiles a.toolchain (out / s!"{name}.holes") p.holes reuse
      IO.println s!"{clean name}: {out / name}"
  return code

def expectText : Judged → String
  | .ran _ (some s) _ => s!"rejected at {s.name} (cheat case)"
  | .ran (.breaks ts) none _ => "breaks " ++ ", ".intercalate ts
  | .ran (.survives _) none _ => "survives (known gap)"
  | .invalid _ => "-"

def outcomeText : Outcome → String
  | .refuted => "REFUTED"
  | .rejected => "REJECTED, NOT REFUTED"
  | .survived => "SURVIVED"
  | .unbound => "UNBOUND"
  | .failed => "NO JUDGMENT"
  | .invalid => "INVALID"
  | .refused => "REFUSED BY LINT"

def pad (s : String) (n : Nat) : String := s ++ String.ofList (List.replicate (n - s.length) ' ')

def mentions (pat l : String) : Bool := (splitFirst pat.toList l.toList).isSome

def isLogError (l : String) : Bool := l.startsWith "error:"

def isPanic (l : String) : Bool := mentions "PANIC" l

def isFileError (l : String) : Bool := isLogError l && mentions ".lean:" l

def logEvidence (lines : List String) : Option String :=
  lines.find? isPanic <|> lines.find? isFileError <|> lines.find? isLogError

def isCheatCase (r : Result) : Bool := r.judged matches .ran _ (some _) _

def unexpectedRejection (r : Result) : Bool :=
  !r.ok && (r.outcome == .rejected || r.outcome == .failed || r.outcome == .unbound)

def rejectionEvidence (logDir : System.FilePath) (r : Result) : IO (List String) := do
  let mut out : List String := []
  if let .ran _ _ x := r.judged then
    if let l :: more := x.lint then
      let rest := if more.isEmpty then "" else s!" (and {more.length} more)"
      out := out ++ [s!"{clean (l.take 150).toString}{rest}"]
  if isCheatCase r || unexpectedRejection r then
    for log in caseLogs logDir r.name do
      if ← log.pathExists then
        if let some l := logEvidence ((← IO.FS.readFile log).splitOn "\n") then
          out := out ++ [clean (l.take 150).toString]
        break
  return out

def readApproved (root : System.FilePath) (skip : List String := []) : ExceptT String IO Approved := do
  let core := root / "core"
  let toolchain ← IO.FS.readFile (root / "lean-toolchain")
  let files ← coreFiles core skip
  let config ← match Json.parse (← IO.FS.readFile (core / "comparator.json")) with
    | .ok j => pure j
    | .error e => throw s!"core/comparator.json: {e}"
  let chalModule ← match config.getObjValAs? String "challenge_module" with
    | .ok m => pure m
    | .error e => throw s!"core/comparator.json: {e}"
  let chalPath := "/".intercalate (chalModule.splitOn ".") ++ ".lean"
  let some chalSrc := files.lookup chalPath | throw s!"core/{chalPath} not found"
  let challenge ← match readChallenge chalSrc with
    | .ok ls => pure ls
    | .error e => throw s!"core/{chalPath}: {e}"
  let theorems := challenge.filterMap fun | .thm n _ _ => some n | _ => none
  let defs ← match config.getObjValAs? (Array String) "definition_names" with
    | .ok ds => pure ds.toList
    | .error _ => pure []
  if let some e := unqualified challenge defs then throw s!"core/{chalPath}: {e}"
  return { toolchain, files, config, chalModule, challenge, theorems, defs,
           impls := implModules (files.map (·.1)) }

def main (args : List String) : IO UInt32 := do
  let cfg ← match parseArgs args {} with
    | .ok c => pure c
    | .error e => IO.eprintln e; IO.eprintln usage; return 2
  if cfg.prepare.isSome && cfg.cases.isEmpty then IO.eprintln usage; return 2
  let root : System.FilePath := "."
  let prepared ← try (prepareReuse (root / "core")).run catch e => pure (.error (toString e))
  let reuse ← match prepared with
    | .ok r => pure r
    | .error e => IO.eprintln e; return 2
  if let some r := reuse then IO.eprintln s!"packages: {r.link.name}"
  let casesDir := root / "eval" / "mutants" / "cases"
  let logDir := root / ".lake" / "mutants"
  IO.FS.createDirAll logDir
  let skip := match reuse with
    | some r => r.packages.names.map fun (n : String) =>
      ((r.packages.rel / (n : System.FilePath)).toString)
    | none => []
  let a ← match ← (readApproved root skip).run with
    | .ok a => pure a
    | .error e => IO.eprintln s!"mitos-mutants: {clean e}"; return 2
  if let some r := reuse then
    let sources := sourcesOnly r.packages.rel.toString r.packages.names a.files
    if overlapsSources r.packages.rel sources then
      IO.eprintln "packagesDir overlaps the workspace sources"
      return 2
  let cases ← if cfg.cases.isEmpty then do
      unless ← casesDir.isDir do IO.eprintln "mitos-mutants: no eval/mutants/cases/"; return 2
      pure (((← casesDir.readDir).map (·.fileName)).qsort (· < ·)).toList
    else pure cfg.cases
  if cases.isEmpty then IO.eprintln "mitos-mutants: no cases in eval/mutants/cases/"; return 2
  let gens ← generatedFor a casesDir cases
  let t0 ← IO.monoMsNow
  let checked ← try (leanCheck a gens (logDir / "challenge.log") reuse).run
    catch e => pure (.error (toString e))
  let a ← match checked with
  | .ok c =>
    let secs := ((← IO.monoMsNow) - t0 + 50) / 100
    IO.println (s!"challenge (reader against Lean's build): AGREE on {c.decls} declarations, " ++
      s!"{CrossCheck.probes.length} probes caught")
    IO.println (s!"challenge (reader against Lean's parse): AGREE on {c.commands} commands, " ++
      s!"{Output.parseProbes.length} probes caught")
    IO.println (s!"generated Challenges (as Lean built them): {c.gens} state what they must, " ++
      s!"{Output.outProbes.length} probes caught ({secs / 10}.{secs % 10}s)")
    pure { a with checked := gens.map (·.text) }
  | .error e =>
    IO.eprintln s!"mitos-mutants: core/{"/".intercalate (a.chalModule.splitOn ".")}.lean: {clean e}"
    return 2
  let env ← try Lint.syntaxEnv catch e =>
    IO.eprintln s!"mitos-mutants: cannot load Lean's syntax for the lint: {clean (toString e)}"; return 2
  if let some out := cfg.prepare then
    return ← writeWorkspaces env a casesDir out cases reuse
  let start ← IO.monoMsNow
  let control ← judge cfg a.toolchain a.files none (logDir / "control.log") reuse
  let controlText := match control with
    | .accepted => "ACCEPTED" | .rejected => "REJECTED  <-- FAIL" | .failed => "NO JUDGMENT  <-- FAIL"
  IO.println s!"control (unmutated core, approved Challenge and proofs): {controlText}"
  let w := (cases.map (·.length)).foldl max 4 + 2
  IO.println s!"\n{pad "CASE" w}{pad "RESULT" 23}{pad "TIME" 8}EXPECT"
  let mut results := #[]
  for name in cases do
    let t0 ← IO.monoMsNow
    let j ← runCase cfg env a casesDir logDir name reuse
    let r : Result := { name, judged := j }
    let secs := ((← IO.monoMsNow) - t0 + 50) / 100
    let mark := if r.ok then "" else "  <-- FAIL"
    let why := match j with | .invalid w => s!" ({clean w})" | _ => ""
    IO.println s!"{pad (clean name) w}{pad (outcomeText r.outcome) 23}{pad s!"{secs / 10}.{secs % 10}s" 8}{expectText j}{why}{mark}"
    for l in ← rejectionEvidence logDir r do
      IO.println s!"{pad "" w}{l}"
    results := results.push r
  let rs := results.toList
  IO.println "\nCHALLENGE THEOREM               BROKEN BY (refuted)"
  for t in a.theorems do
    let bs := breakers rs t
    IO.println s!"{pad t 32}{if bs.isEmpty then "none" else s!"{bs.length}: " ++ ", ".intercalate bs}"
  let survivors (known : Bool) := rs.filterMap fun r =>
    match r.judged with
    | .ran e c x =>
      let gap := (e matches .survives _) && c.isNone
      if outcome x == .survived && gap == known then some (r.name, e) else none
    | .invalid _ => none
  let gaps := survivors true
  unless gaps.isEmpty do
    IO.println "\nKNOWN GAPS (the approved Challenge still accepts the mutant)"
    for (n, e) in gaps do
      if let .survives g := e then IO.println s!"{clean n}: {clean g}"
  let unexpected := survivors false
  unless unexpected.isEmpty do
    IO.println "\nUNEXPECTED SURVIVORS (the approved Challenge still accepts the mutant: a theorem is too weak, or the mutant changes nothing the theorems state)"
    for (n, _) in unexpected do IO.println (clean n)
  let total := ((← IO.monoMsNow) - start) / 1000
  let refuted := (rs.filter (·.outcome == .refuted)).length
  let cheats := (rs.filter fun r => r.ok && r.judged matches .ran _ (some _) _).length
  if passes control cases rs then
    IO.println s!"\nmutants: all {rs.length} cases as expected, {refuted} refuted, {gaps.length} known gap(s), {cheats} cheat case(s) rejected ({total}s)"
    return 0
  else
    IO.println s!"\nmutants: FAILURES (logs in .lake/mutants/) ({total}s)"
    return 1
