import Mitos.Core.Graph
import Mitos.Core.Lines

namespace Score.Chain

open Mitos

def reads (path : String) : Bool := path == "CHAIN" || path == "CHAIN.ai"

private def origin (repo path : String) : Assumption :=
  if path == "CHAIN.ai" then .ai s!"{repo}/{path}"
  else .humanDeclaredOutsideSource s!"{repo}/{path}"

private def needsChars : List Char := "needs ".toList

private def bindsChars : List Char := "binds ".toList

private def servesChars : List Char := "serves ".toList

private def env (key : List Char) : Identity := { kind := "env", key := String.ofList key }

private def svc (key : List Char) : Identity := { kind := "svc", key := String.ofList key }

private def ofLine (o : Nat) (l : List Char) : Option Fact :=
  if needsChars.isPrefixOf l then
    let key := l.drop needsChars.length
    some { kind := .requires, ident := env key,
           span := { start := o + utf8Len needsChars, len := utf8Len key } }
  else if bindsChars.isPrefixOf l then
    let (key, rest) := (l.drop bindsChars.length).span (· != ' ')
    let target := rest.drop 1
    if key.isEmpty || target.all Char.isWhitespace then none
    else
      some { kind := .binds (svc target), ident := env key,
             span := { start := o + utf8Len bindsChars, len := utf8Len key } }
  else if servesChars.isPrefixOf l then
    let key := l.drop servesChars.length
    some { kind := .provides, ident := svc key,
           span := { start := o + utf8Len servesChars, len := utf8Len key } }
  else none

def facts (repo path text : String) : List (Fact × Assumption) :=
  ((lines text.toList).filterMap fun (o, l) => ofLine o l).map (·, origin repo path)

theorem reads_cases :
    ["CHAIN", "CHAIN.ai", "sub/CHAIN", "CHAIN.bak", "PROVIDES"].map reads =
      [true, true, false, false, false] := by decide

theorem facts_line_forms :
    facts "deploy" "CHAIN" "needs A\nbinds A db\nserves db\n# needs B\n" =
      [({ kind := .requires, ident := ⟨"env", "A"⟩, span := ⟨6, 1⟩ },
          .humanDeclaredOutsideSource "deploy/CHAIN"),
        ({ kind := .binds ⟨"svc", "db"⟩, ident := ⟨"env", "A"⟩, span := ⟨14, 1⟩ },
          .humanDeclaredOutsideSource "deploy/CHAIN"),
        ({ kind := .provides, ident := ⟨"svc", "db"⟩, span := ⟨26, 2⟩ },
          .humanDeclaredOutsideSource "deploy/CHAIN")] := by decide

theorem facts_ai :
    facts "deploy" "CHAIN.ai" "binds A db\n" =
      [({ kind := .binds ⟨"svc", "db"⟩, ident := ⟨"env", "A"⟩, span := ⟨6, 1⟩ },
          .ai "deploy/CHAIN.ai")] := by decide

theorem skips_incomplete_bindings :
    facts "deploy" "CHAIN" "binds A\nbinds A \nbinds A  \nbinds  db\n" = [] := by
  decide

theorem requires_env {repo path text : String} {p : Fact × Assumption}
    (h : p ∈ facts repo path text) (hk : p.1.kind = .requires) :
    p.1.ident.kind = "env" ∧ p.1.scope = .runtime := by
  obtain ⟨f, hf, rfl⟩ := List.mem_map.1 h
  obtain ⟨⟨o, l⟩, -, hl⟩ := List.mem_filterMap.1 hf
  simp only [ofLine] at hl
  split at hl
  · cases hl; exact ⟨rfl, rfl⟩
  · split at hl
    · split at hl
      · cases hl
      · cases hl; cases hk
    · split at hl
      · cases hl; cases hk
      · cases hl

end Score.Chain
