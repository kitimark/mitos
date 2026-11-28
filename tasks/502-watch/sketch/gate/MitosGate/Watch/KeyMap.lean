namespace MitosGate.Watch

abbrev KeyMap (α β : Type) := List (α × β)

structure Delta (α β : Type) where
  key : α
  before : Option β
  after : Option β
  deriving DecidableEq, Repr

namespace KeyMap

variable {α β : Type} [DecidableEq α] [DecidableEq β]

def get? (m : KeyMap α β) (k : α) : Option β :=
  (m.find? fun p => p.1 == k).map Prod.snd

def keys (m : KeyMap α β) : List α := m.map Prod.fst

def WF (m : KeyMap α β) : Prop := m.keys.Nodup

def Equiv (m n : KeyMap α β) : Prop := ∀ k, m.get? k = n.get? k

def set (m : KeyMap α β) (k : α) (v : β) : KeyMap α β :=
  (k, v) :: m.filter fun p => p.1 != k

def erase (m : KeyMap α β) (k : α) : KeyMap α β :=
  m.filter fun p => p.1 != k

def diff (m n : KeyMap α β) : List (Delta α β) :=
  let ks := m.keys ++ n.keys.filter fun k => !m.keys.contains k
  ks.filterMap fun k =>
    if m.get? k = n.get? k then none else some ⟨k, m.get? k, n.get? k⟩

end KeyMap

def DiffNamesEveryChange : Prop :=
  ∀ {α β : Type} [DecidableEq α] [DecidableEq β] (m n : KeyMap α β) (k : α),
    m.get? k ≠ n.get? k →
    ∃ d ∈ KeyMap.diff m n, d.key = k ∧ d.before = m.get? k ∧ d.after = n.get? k

def DiffNamesOnlyChanges : Prop :=
  ∀ {α β : Type} [DecidableEq α] [DecidableEq β] (m n : KeyMap α β) (d : Delta α β),
    d ∈ KeyMap.diff m n →
    d.before = m.get? d.key ∧ d.after = n.get? d.key ∧ d.before ≠ d.after

def DiffSelf : Prop :=
  ∀ {α β : Type} [DecidableEq α] [DecidableEq β] (m : KeyMap α β), KeyMap.diff m m = []

def DiffOnePerKey : Prop :=
  ∀ {α β : Type} [DecidableEq α] [DecidableEq β] (m n : KeyMap α β),
    m.WF → n.WF → ((KeyMap.diff m n).map (·.key)).Nodup

def DiffSeesOnlyLookups : Prop :=
  ∀ {α β : Type} [DecidableEq α] [DecidableEq β] (m m' n n' : KeyMap α β) (k : α),
    m.Equiv m' → n.Equiv n' →
    ((∃ d ∈ KeyMap.diff m n, d.key = k) ↔ (∃ d ∈ KeyMap.diff m' n', d.key = k))

def SetKeepsWF : Prop :=
  ∀ {α β : Type} [DecidableEq α] [DecidableEq β] (m : KeyMap α β) (k : α) (v : β),
    m.WF → (m.set k v).WF

end MitosGate.Watch
