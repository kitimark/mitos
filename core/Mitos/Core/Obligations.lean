import Mitos.Core.Fact

/-!
# Extractors and their obligations

Mitos owns these statements. A plugin supplies an `Extractor` and proofs of the obligations;
it never states them. The gate generates a Challenge module that names exactly these
predicates, and `lake comparator` checks the plugin proved the same statements.

`statements.lock` pins the types and Prop-valued definitions in this file, so changing what an
obligation *means* needs an approved spec change.
-/

namespace Mitos

/-- An extractor turns one source file into facts. It must be a total, safe Lean function. -/
structure Extractor where
  run : String → List Fact

/-- A human-reviewed model of a convention: which facts are true of a file. -/
structure Model where
  Holds : String → Fact → Prop

/-- **Anchoring.** Every emitted fact cites a span whose text is exactly its identity key. -/
def Anchored (x : Extractor) : Prop :=
  ∀ s, ∀ f ∈ x.run s, f.span.text s.toList = f.ident.key.toList

/-- **Soundness.** Every emitted fact holds according to the model. -/
def SoundWrt (M : Model) (x : Extractor) : Prop :=
  ∀ s, ∀ f ∈ x.run s, M.Holds s f

/-- **Completeness.** Every fact the model says holds is emitted (same kind and identity).
This is what stops an extractor from passing by emitting nothing. -/
def CompleteWrt (M : Model) (x : Extractor) : Prop :=
  ∀ s f, M.Holds s f → ∃ g ∈ x.run s, g.kind = f.kind ∧ g.ident = f.ident

end Mitos
