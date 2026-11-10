import Mitos.Core.Fact

namespace Mitos

structure Extractor where
  run : String → List Fact

structure Model where
  Holds : String → Fact → Prop

def Anchored (x : Extractor) : Prop :=
  ∀ s, ∀ f ∈ x.run s, f.span.text s.toList = some f.ident.key.toList

def SoundWrt (M : Model) (x : Extractor) : Prop :=
  ∀ s, ∀ f ∈ x.run s, M.Holds s f

def CompleteWrt (M : Model) (x : Extractor) : Prop :=
  ∀ s f, M.Holds s f → ∃ g ∈ x.run s, g.kind = f.kind ∧ g.ident = f.ident

end Mitos
