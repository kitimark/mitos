import Lean
import MitosGate.Util

/-!
# `statements.lock`

Declarations Lean generates (`match_*`, `_f`, `decEq`, `casesOn`, …) are not listed, but a
listed declaration can keep its meaning in them: a structurally recursive definition's value is
`List.brecOn … f._f`, and a `match`'s patterns live in its `match_1`. So each line also hashes, in
`aux=`, every unlisted core declaration its type or value reaches, transitively, hashed the same
way.

(`Expr.hash` is not used: its effective width is 32 bits.)
-/

open Lean

namespace MitosGate.Lock

def line1a : String := "# statements.lock: g"
def line1b : String := "enerated by `lake ex"
def line1c : String := "e mitos-gate lock`. "
def line1d : String := "Do not edit by hand."
def line2a : String := "# A change to this f"
def line2b : String := "ile needs the `spec-"
def line2c : String := "approved` label (see"
def line2d : String := " docs/process.md)."

def headerLine1 : String := line1a ++ line1b ++ line1c ++ line1d
def headerLine2 : String := line2a ++ line2b ++ line2c ++ line2d
def header : String := headerLine1 ++ "\n" ++ headerLine2 ++ "\n"

def splitOnChar (sep : Char) : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    let rest := splitOnChar sep cs
    if c == sep then [] :: rest
    else match rest with
      | [] => [[c]]
      | line :: lines => (c :: line) :: lines

def firstTwoLinesMatchHeader (txt : String) : Bool :=
  match splitOnChar '\n' header.toList with
  | [l1, l2, []] =>
    match splitOnChar '\n' txt.toList with
    | l1' :: l2' :: _ => !l1.isEmpty && !l2.isEmpty && l1 == l1' && l2 == l2'
    | _ => false
  | _ => false

def joinLines : List (List Char) → List Char
  | [] => []
  | [line] => line
  | line :: rest => line ++ '\n' :: joinLines rest

def headerWithLine (i : Nat) (line : List Char) : String :=
  match splitOnChar '\n' header.toList with
  | [l1, l2, []] =>
    match i with
    | 0 => String.ofList (joinLines [line, l2, []])
    | 1 => String.ofList (joinLines [l1, line, []])
    | _ => ""
  | _ => ""

private def sha256Short (s : String) : IO String := do
  return ((← sha256 s).take 32).toString

private def digest (e : Expr) : IO String := sha256Short (toString e)

def generatedSuffixes : List String :=
  ["rec", "sizeOf_spec", "noConfusionType", "ctorIdx", "ofNat_ctorIdx", "toCtorIdx", "ofNat",
   "ctorElim", "ctorElimType", "inj", "injEq", "repr", "decEq"]

def isGenerated (n : Name) : Bool :=
  match n with
  | .str _ s => generatedSuffixes.contains s || s.startsWith "match_" || s.startsWith "eq_" ||
                s.startsWith "proof_"
  | _ => false

def pinned : ConstantInfo → List Expr
  | .defnInfo d => [d.type, d.value]
  | ci => [ci.type]

partial def unlistedDeps (env : Environment) (unlisted : Name → Bool) (es : List Expr)
    (seen : NameSet := {}) : NameSet :=
  es.foldl (init := seen) fun seen e =>
    e.getUsedConstants.foldl (init := seen) fun seen n =>
      if seen.contains n || !unlisted n then seen
      else match env.find? n with
        | some ci => unlistedDeps env unlisted (pinned ci) (seen.insert n)
        | none => seen

def entries (root : Name) (prefixes : List Name) : IO (Array String) := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := root }] {} (trustLevel := 0)
  let inCore (n : Name) : Bool := match env.getModuleIdxFor? n with
    | some idx => prefixes.any (·.isPrefixOf env.header.moduleNames[idx.toNat]!)
    | none => false
  let listed (n : Name) : Bool := inCore n &&
    !(n.isInternal || isAuxRecursor env n || isNoConfusion env n || isGenerated n)
  let mut out : Array String := #[]
  for (n, ci) in env.constants.map₁.toList do
    unless listed n do continue
    let ty ← digest ci.type
    let line ← match ci with
      | .defnInfo d => pure s!"def {n} type={ty} value={← digest d.value}"
      | .thmInfo _ => pure s!"theorem {n} type={ty}"
      | .inductInfo _ => pure s!"inductive {n} type={ty}"
      | .ctorInfo _ => pure s!"ctor {n} type={ty}"
      | .opaqueInfo _ => pure s!"opaque {n} type={ty}"
      | .axiomInfo _ => pure s!"AXIOM {n} type={ty}"
      | _ => pure s!"other {n} type={ty}"
    let deps := (unlistedDeps env (fun m => inCore m && !listed m) (pinned ci)).toList.toArray
    if deps.isEmpty then out := out.push line; continue
    let aux ← (deps.qsort (·.toString < ·.toString)).mapM fun m => do
      let ds ← (pinned (env.find? m).get!).mapM digest
      return s!"{m} {" ".intercalate ds}"
    out := out.push s!"{line} aux={← sha256Short ("\n".intercalate aux.toList)}"
  return out.qsort (· < ·)

def render (es : Array String) : String :=
  header ++ String.intercalate "\n" es.toList ++ "\n"

end MitosGate.Lock
