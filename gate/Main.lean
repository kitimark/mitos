import MitosGate.Lint
import MitosGate.Imports
import MitosGate.Lock
import MitosGate.Accept
import MitosGate.RunLog

open MitosGate

def trustedCoreImports : List String := ["Init", "Std", "Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def lockedSpecImports : List String := ["Init", "Std", "Mitos.Core"]

def usage : String := "usage:
  mitos-gate lint <file.lean>...                 gate 1 on plugin sources
  mitos-gate imports                             import rule for core/ (Init, Std, Mitos.*; spec never imports impl)
  mitos-gate lock [--check]                      write or check statements.lock
  mitos-gate accept --workspace <dir> --plugin <Name> --model <Module.const>
                    [--plugin-file <f>] [--paranoid] [--record] [--keep] [--skip-lint]
  mitos-gate runlog [--base <dir>] --head <dir>   run-log records parse, one per (task, role, attempt);
                                                 with --base, every base line is kept (append-only)"

partial def parseAccept (args : List String) (c : Accept.Config) : Except String Accept.Config :=
  match args with
  | [] => .ok c
  | "--workspace" :: v :: rest => parseAccept rest { c with workspace := v }
  | "--plugin" :: v :: rest => parseAccept rest { c with plugin := v }
  | "--model" :: v :: rest => parseAccept rest { c with model := v }
  | "--plugin-file" :: v :: rest => parseAccept rest { c with pluginFile := some v }
  | "--mitos-root" :: v :: rest => parseAccept rest { c with mitosRoot := v }
  | "--paranoid" :: rest => parseAccept rest { c with paranoid := true }
  | "--record" :: rest => parseAccept rest { c with record := true }
  | "--keep" :: rest => parseAccept rest { c with keep := true }
  | "--skip-lint" :: rest => parseAccept rest { c with skipLint := true }
  | a :: _ => .error s!"unknown argument {a}"

def main (args : List String) : IO UInt32 := do
  match args with
  | "lint" :: files@(_ :: _) =>
    let env ← Lint.syntaxEnv
    let mut bad := 0
    for f in files do
      let vs ← Lint.check env Accept.pluginImports (← IO.FS.readFile f)
      for v in vs do IO.println (oneLine (v.render f))
      bad := bad + vs.size
    IO.println s!"{bad} violation(s)"
    return if bad == 0 then 0 else 1
  | ["imports"] =>
    let vs ← Imports.check "core" trustedCoreImports
    let vs := vs ++ (← Imports.check ("core" / "Mitos" / "Core") lockedSpecImports)
    for v in vs do IO.println (oneLine v)
    IO.println s!"{vs.size} import violation(s) in core/"
    return if vs.isEmpty then 0 else 1
  | "lock" :: rest =>
    let es ← Lock.entries `Mitos.Core [`Mitos.Core]
    let txt := Lock.render es
    if rest == ["--check"] then
      let old ← IO.FS.readFile "statements.lock"
      if old == txt then
        IO.println s!"statements.lock up to date ({es.size} declarations)"
        return 0
      let oldSet := (old.splitOn "\n").filter (fun l => !l.startsWith "#" && !l.isEmpty)
      let newSet := (txt.splitOn "\n").filter (fun l => !l.startsWith "#" && !l.isEmpty)
      for l in oldSet do unless newSet.contains l do IO.println s!"- {l}"
      for l in newSet do unless oldSet.contains l do IO.println s!"+ {l}"
      IO.println "statements.lock is out of date: the meaning of the trusted core changed."
      return 1
    IO.FS.writeFile "statements.lock" txt
    IO.println s!"wrote statements.lock ({es.size} declarations)"
    return 0
  | "accept" :: rest =>
    match parseAccept rest { workspace := "", plugin := "", model := "" } with
    | .error e => IO.eprintln e; IO.eprintln usage; return 2
    | .ok c =>
      if c.workspace.toString.isEmpty || c.plugin.isEmpty || c.model.isEmpty then
        IO.eprintln usage; return 2
      Accept.runAccept c
  | "runlog" :: rest => RunLog.cli rest usage
  | _ => IO.eprintln usage; return 2
