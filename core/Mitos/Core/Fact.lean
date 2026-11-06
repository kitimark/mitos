/-!
# Facts

A fact is a claim an extractor makes about one source file: the file *provides* or *requires*
an identity, and the claim is anchored to a span of the file.

Phase 0 simplification: spans are **character** offsets into `String.toList`. Phase 1 moves to
checked UTF-8 byte positions (`String.Pos` / `String.Slice`); see `docs/process.md`.
-/

namespace Mitos

/-- Whether a fact says the file offers an identity or needs one. -/
inductive FactKind where
  | provides
  | requires
  deriving DecidableEq, Repr

/-- A global identity, e.g. `{ kind := "npm", key := "@jellyfin/sdk" }`. -/
structure Identity where
  kind : String
  key  : String
  deriving DecidableEq, Repr

/-- A span of a source file, as a character offset and a length. -/
structure Span where
  start : Nat
  len   : Nat
  deriving DecidableEq, Repr

/-- The characters of `src` covered by a span. -/
def Span.text (sp : Span) (src : List Char) : List Char :=
  (src.drop sp.start).take sp.len

/-- One claim about one source file. -/
structure Fact where
  kind  : FactKind
  ident : Identity
  span  : Span
  deriving DecidableEq, Repr

end Mitos
