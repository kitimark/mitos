import Lean.Data.Json
import Diff.Compare
import Diff.Pins

namespace Diff

open Lean (Json)

def Keys.ofGoJson (text : String) : Except String Keys := do
  let json ← Json.parse text
  let module ← json.getObjVal? "Module"
  let modulePath ← module.getObjValAs? String "Path"
  let requires ← match json.getObjValD "Require" with
    | .null => pure #[]
    | value => value.getArr?
  let requirePaths ← requires.mapM (·.getObjValAs? String "Path")
  return { modules := if modulePath.isEmpty then [] else [modulePath],
           requires := requirePaths.toList }

#guard (Keys.ofGoJson "{\"Module\": {\"Path\": \"\"}, \"Require\": null}").toOption == some ⟨[], []⟩

#guard (Keys.ofGoJson "{\"Module\": {\"Path\": \"m\"}, \"Require\": [{\"Path\": \"a\"}, {\"Path\": \"b\", \"Indirect\": true}]}").toOption == some ⟨["m"], ["a", "b"]⟩

#guard (Keys.ofGoJson "{\"Require\": []}").toOption.isNone

#guard (Keys.ofGoJson "{\"Module\": {\"Path\": \"m\"}, \"Require\": 3}").toOption.isNone

def goEnv : Array (String × Option String) :=
  #[("GOTOOLCHAIN", some "local"), ("GOWORK", some "off"), ("GOFLAGS", some ""),
    ("GOENV", some "off")]

def runGo (args : Array String) : IO IO.Process.Output :=
  IO.Process.output { cmd := "go", args, env := goEnv, cwd := some "/" }

def refresh (cases : System.FilePath) (goVersion : String) (pins : List Pin) : IO Bool := do
  let version ← runGo #["env", "GOVERSION"]
  unless version.exitCode == 0 && version.stdout.trimAscii.toString == goVersion do
    IO.eprintln s!"--refresh needs {goVersion}; `go env GOVERSION` printed {repr version.stdout.trimAscii.toString}"
    return false
  let mut ok := true
  for p in pins do
    let modFile ← IO.FS.realPath (cases / p.case / "module.mod")
    let out ← runGo #["mod", "edit", "-json", modFile.toString]
    if out.exitCode == 0 then IO.FS.writeFile (cases / p.case / "module.json") out.stdout
    else
      IO.eprintln s!"{p.case}: {goVersion} rejects {p.module}@{p.version}: {out.stderr.trimAscii.toString}"
      ok := false
  return ok

end Diff
