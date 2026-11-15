import Mitos.Core
import Plugins.GoMod

namespace Score.GoMod

open Mitos

private def fileName : List Char := "go.mod".toList

def reads (path : String) : Bool :=
  path.toList == fileName || ('/' :: fileName).isSuffixOf path.toList

def facts (text : String) : List (Fact × Assumption) :=
  (_root_.GoMod.extractor.run text).map (·, .extractor "GoMod")

theorem reads_root : reads "go.mod" = true := by decide

theorem reads_nested : reads "tools/cmd/go.mod" = true := by decide

theorem not_reads_longer_name : reads "notgo.mod" = false := by decide

theorem not_reads_backup : reads "go.mod.orig" = false := by decide

theorem not_reads_directory : reads "go.mod/README" = false := by decide

theorem reads_testdata : reads "testdata/go.mod" = true := by decide

theorem reads_dot_directory : reads ".hidden/go.mod" = true := by decide

theorem reads_underscore_directory : reads "_scratch/go.mod" = true := by decide

theorem reads_under_testdata : reads "pkg/testdata/extra/go.mod" = true := by decide

theorem facts_eq (text : String) :
    facts text = (Models.GoMod.facts text).map (·, .extractor "GoMod") := by
  rw [facts, _root_.GoMod.run_eq]

theorem facts_kind {text : String} {p : Fact × Assumption} (h : p ∈ facts text) :
    p.1.ident.kind = "go-module" ∧ p.1.scope = .runtime := by
  rw [facts_eq] at h
  obtain ⟨f, hf, rfl⟩ := List.mem_map.1 h
  obtain ⟨e, -, rfl⟩ := List.mem_map.1 hf
  exact ⟨rfl, rfl⟩

end Score.GoMod
