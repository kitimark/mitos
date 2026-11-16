import MitosGate.Util
import MitosGate.Yaml.LineCases

namespace MitosGate.WorkflowCli

open Yaml

def refusalLine : Refusal → Nat
  | .char n _ | .anchorOrAlias n | .tag n | .complexKey n | .mergeKey n | .marker n
  | .escape n | .multiline n | .blockIndicator n | .indent n => n

def reason : Refusal → String
  | .char _ c => s!"character U+{String.ofList (hexDigits c.toNat)} outside LF and printable ASCII"
  | .anchorOrAlias _ => "anchor or alias"
  | .tag _ => "tag"
  | .complexKey _ => "complex key"
  | .mergeKey _ => "merge key"
  | .marker _ => "document marker or directive"
  | .escape _ => "backslash escape in a double-quoted scalar"
  | .multiline _ => "scalar runs onto the next line"
  | .blockIndicator _ => "block indentation indicator"
  | .indent _ => "block line indented between its owner and its content"

def cli (args : List String) (usage : String) : IO UInt32 := do
  let ["parse", file] := args | do
    IO.eprintln usage
    return 2
  let text ← try IO.FS.readFile file catch e =>
    IO.eprintln (ciLine s!"workflow: cannot read {file}: {e}")
    return 2
  match lex text.toList with
  | .ok _ => return 0
  | .error refusal =>
    IO.eprintln (ciLine s!"{file}:{refusalLine refusal}: refused: {reason refusal}")
    return 1

end MitosGate.WorkflowCli
