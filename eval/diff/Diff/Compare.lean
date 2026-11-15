namespace Diff

inductive Directive where
  | module
  | require
  deriving DecidableEq, Repr

structure Keys where
  modules : List String
  requires : List String
  deriving DecidableEq, Repr

inductive Side where
  | plugin
  | go
  deriving DecidableEq, Repr

inductive Mismatch where
  | onlyIn (side : Side) (directive : Directive) (path : String)
  | order (directive : Directive)
  deriving DecidableEq, Repr

def unmatched (xs ys : List String) : List String := ys.foldl List.erase xs

def shared (xs ys : List String) : List String :=
  (unmatched xs.reverse (unmatched xs ys)).reverse

def compareList (directive : Directive) (plugin go : List String) : List Mismatch :=
  if plugin = go then []
  else
    let onlyGo := unmatched go plugin
    let onlyPlugin := unmatched plugin go
    if onlyGo.isEmpty && onlyPlugin.isEmpty then [.order directive]
    else onlyGo.map (.onlyIn .go directive) ++ onlyPlugin.map (.onlyIn .plugin directive) ++
      if shared plugin go = shared go plugin then [] else [.order directive]

def compare (plugin go : Keys) : List Mismatch :=
  compareList .module plugin.modules go.modules ++
    compareList .require plugin.requires go.requires

theorem compareList_eq_nil {directive : Directive} {plugin go : List String} :
    compareList directive plugin go = [] ↔ plugin = go := by
  unfold compareList
  by_cases h : plugin = go
  · simp [h]
  · simp only [h, ite_false, iff_false]
    split
    · exact List.cons_ne_nil _ _
    · rename_i hne
      intro hnil
      simp only [List.append_eq_nil_iff, List.map_eq_nil_iff] at hnil
      simp [hnil.1.1, hnil.1.2] at hne

theorem compare_eq_nil {plugin go : Keys} : compare plugin go = [] ↔ plugin = go := by
  rw [compare, List.append_eq_nil_iff, compareList_eq_nil, compareList_eq_nil]
  cases plugin
  cases go
  simp

#guard compare ⟨["m"], ["a", "b"]⟩ ⟨["m"], ["a", "b"]⟩ == []

#guard compare ⟨["m"], ["a", "b"]⟩ ⟨["m"], ["b", "a"]⟩ == [.order .require]

#guard compare ⟨["m"], ["a"]⟩ ⟨["m"], ["a", "a"]⟩ == [.onlyIn .go .require "a"]

#guard compare ⟨[], ["a"]⟩ ⟨[","], ["a"]⟩ == [.onlyIn .go .module ","]

#guard compare ⟨["m"], ["a", "x"]⟩ ⟨["m"], ["a", "y"]⟩ ==
  [.onlyIn .go .require "y", .onlyIn .plugin .require "x"]

#guard compare ⟨["m"], ["a", "b"]⟩ ⟨["m"], ["b", "a", "c"]⟩ ==
  [.onlyIn .go .require "c", .order .require]

#guard compare ⟨["m"], ["a", "b", "x"]⟩ ⟨["m"], ["b", "a", "c"]⟩ ==
  [.onlyIn .go .require "c", .onlyIn .plugin .require "x", .order .require]

#guard compare ⟨["m"], ["a", "b", "a"]⟩ ⟨["m"], ["a", "b"]⟩ ==
  [.onlyIn .plugin .require "a"]

end Diff
