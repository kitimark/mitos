import Mitos.Core
import Models.GoMod

open Mitos Models.GoMod

namespace GoMod

private structure Scan where
  mode : Mode
  reversedFacts : List Fact

private def scanLine (scan : Scan) (line : Nat × List Char) : Scan :=
  match scan.mode.step line with
  | (next, reading) =>
    { mode := next, reversedFacts := (reading.entry?.map fact).toList ++ scan.reversedFacts }

def extractor : Extractor where
  run s :=
    ((lines s.toList).foldl scanLine { mode := .top, reversedFacts := [] }).reversedFacts.reverse

private theorem foldl_scanLine (ls : List (Nat × List Char)) (scan : Scan) :
    (ls.foldl scanLine scan).reversedFacts =
      (((readingsFrom scan.mode ls).filterMap fun r => r.2.entry?).map fact).reverse ++
        scan.reversedFacts := by
  induction ls generalizing scan with
  | nil => rfl
  | cons line rest ih =>
    rw [List.foldl_cons, ih]
    unfold scanLine
    rw [readingsFrom]
    rcases scan.mode.step line with ⟨next, reading⟩
    cases h : reading.entry? with
    | none =>
      simp only [h, Option.map_none, Option.toList_none, List.nil_append,
        List.filterMap_cons_none]
    | some entry =>
      simp only [h, Option.map_some, Option.toList_some, List.cons_append, List.nil_append,
        Option.some.injEq, List.filterMap_cons_some, List.map_cons, List.reverse_cons,
        List.append_assoc]

theorem run_eq (s : String) : extractor.run s = facts s := by
  simp only [extractor, foldl_scanLine, List.append_nil, List.reverse_reverse, facts, entries,
    readings]

theorem sound : SoundWrt model extractor := by
  intro s f hf
  rw [run_eq] at hf
  exact hf

theorem anchored : Anchored extractor := by
  intro s f hf
  rw [run_eq] at hf
  exact facts_anchored hf

theorem complete : CompleteWrt model extractor := by
  intro s f hf
  exact ⟨f, by rw [run_eq]; exact hf, rfl, rfl⟩

end GoMod
