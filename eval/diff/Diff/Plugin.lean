import Mitos.Core
import Models.GoMod
import Models.GoMod.Examples
import Plugins.GoMod
import Diff.Compare

namespace Diff

open Mitos

def Keys.ofFacts (facts : List Fact) : Keys where
  modules := (facts.filter (·.kind == .provides)).map (·.ident.key)
  requires := (facts.filter (·.kind == .requires)).map (·.ident.key)

def Keys.ofPlugin (text : String) : Keys := Keys.ofFacts (GoMod.extractor.run text)

theorem Keys.ofPlugin_eq_model (text : String) :
    Keys.ofPlugin text = Keys.ofFacts (Models.GoMod.facts text) := by
  rw [Keys.ofPlugin, GoMod.run_eq]

structure UnreadLine where
  number : Nat
  text : String

theorem readingsFrom_offsets (mode : Models.GoMod.Mode) (ls : List (Nat × List Char)) :
    (Models.GoMod.readingsFrom mode ls).map Prod.fst = ls.map Prod.fst := by
  induction ls generalizing mode with
  | nil => rfl
  | cons line rest ih =>
    rw [Models.GoMod.readingsFrom]
    rcases mode.step line with ⟨next, reading⟩
    simp only [List.map_cons, ih]

theorem readings_offsets (text : String) :
    (Models.GoMod.readings text).map Prod.fst = (lines text.toList).map Prod.fst :=
  readingsFrom_offsets _ _

def unreadLines (text : String) : List UnreadLine :=
  ((lines text.toList).zip (Models.GoMod.readings text)).zipIdx.filterMap
    fun ((line, _, reading), index) =>
      match reading with
      | .unread => some { number := index + 1, text := String.ofList line.2 }
      | _ => none

theorem ofPlugin_wholeFile :
    Keys.ofPlugin Models.GoMod.wholeFile.file =
      { modules := ["example.com/app"], requires := ["example.com/lib", "example.com/util"] } := by
  rw [Keys.ofPlugin_eq_model]
  decide +kernel

theorem unreadLines_wholeFile :
    (unreadLines Models.GoMod.wholeFile.file).map (fun l => (l.number, l.text)) =
      [(3, "go 1.22"), (11, "replace example.com/lib => ../lib")] := by
  decide +kernel

def laxBlockOpener : String :=
  "module example.com/app\nrequire a (\n\tb v1.0.0\n)\nrequire c/d v1.0.0\n"

#guard Keys.ofPlugin laxBlockOpener == ⟨["example.com/app"], ["a", "c/d"]⟩

#guard Keys.ofPlugin "require example.com/lib v1.2.0\n" == ⟨[], ["example.com/lib"]⟩

end Diff
