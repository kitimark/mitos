import Mitos.Core

namespace Models.ToyRequire

def prefixChars : List Char := "require ".toList

def fact (lineByteOffset : Nat) (name : List Char) : Mitos.Fact :=
  { kind := .requires
    ident := { kind := "toy", key := String.ofList name }
    span := { start := lineByteOffset + Mitos.utf8Len prefixChars, len := Mitos.utf8Len name } }

def model : Mitos.Model where
  Holds s f := ∃ o name, (o, prefixChars ++ name) ∈ Mitos.lines s.toList ∧ f = fact o name

def requirements (s : String) : List (Nat × List Char) :=
  (Mitos.lines s.toList).filterMap fun p =>
    if prefixChars.isPrefixOf p.2 then some (p.1, p.2.drop prefixChars.length) else none

theorem mem_requirements {s : String} {r : Nat × List Char} :
    r ∈ requirements s ↔ (r.1, prefixChars ++ r.2) ∈ Mitos.lines s.toList := by
  unfold requirements
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨p, hp, h⟩
    split at h
    · rename_i hpre
      cases h
      have := (List.prefix_iff_eq_append).1 ((List.isPrefixOf_iff_prefix).1 hpre)
      simpa [this] using hp
    · contradiction
  · intro h
    exact ⟨_, h, by simp [List.isPrefixOf_iff_prefix]⟩

/-- A golden file is exact and anchored when its facts are those of its requirement lines. The
lines are compared as offsets and characters, so `decide` never compares `String`s: comparing
facts built from a non-ASCII file overflowed nanoda's stack under `--paranoid`. -/
theorem golden_of_requirements {g : Mitos.GoldenFile} (rs : List (Nat × List Char))
    (hr : requirements g.file = rs) (hf : g.facts = rs.map fun r => fact r.1 r.2) :
    (∀ f, model.Holds g.file f ↔ f ∈ g.facts) ∧
    (∀ f ∈ g.facts, f.span.text g.file.toList = some f.ident.key.toList) := by
  rw [hf, ← hr]
  refine ⟨fun f => ⟨?_, ?_⟩, ?_⟩
  · rintro ⟨o, name, h, rfl⟩
    exact List.mem_map.2 ⟨(o, name), mem_requirements.2 h, rfl⟩
  · intro h
    obtain ⟨r, hr, rfl⟩ := List.mem_map.1 h
    exact ⟨r.1, r.2, mem_requirements.1 hr, rfl⟩
  · intro f h
    obtain ⟨r, hr, rfl⟩ := List.mem_map.1 h
    obtain ⟨pre, post, hs, ho, -⟩ := Mitos.Span.text_eq_some.1 (Mitos.mem_lines (mem_requirements.1 hr))
    exact Mitos.Span.text_eq_some.2
      ⟨pre ++ prefixChars, post, by simp [fact, hs], by simp [fact, ho], by simp [fact]⟩

end Models.ToyRequire
