import Lean

namespace MitosGate.Lock.Canon

open Lean

inductive Ref where
  | named (n : Name)
  | byMeaning (digest : String)

inductive CLevel where
  | zero
  | succ (l : CLevel)
  | max (a b : CLevel)
  | imax (a b : CLevel)
  | param (index : Nat)

inductive CExpr where
  | bvar (i : Nat)
  | sort (u : CLevel)
  | const (r : Ref) (us : List CLevel)
  | app (f a : CExpr)
  | lam (bi : BinderInfo) (ty body : CExpr)
  | pi (bi : BinderInfo) (ty body : CExpr)
  | letE (ty val body : CExpr)
  | natLit (n : Nat)
  | strLit (s : String)
  | proj (struct : Ref) (field : Nat) (e : CExpr)

def canonLevel (levels : List Name) : Level → Except String CLevel
  | .zero => .ok .zero
  | .succ u => return .succ (← canonLevel levels u)
  | .max a b => return .max (← canonLevel levels a) (← canonLevel levels b)
  | .imax a b => return .imax (← canonLevel levels a) (← canonLevel levels b)
  | .param n =>
    match levels.idxOf? n with
    | some i => .ok (.param i)
    | none => .error s!"unknown universe parameter {n}"
  | .mvar _ => .error "universe metavariable"

def canon (levels : List Name) (ref : Name → Except String Ref) : Expr → Except String CExpr
  | .bvar i => .ok (.bvar i)
  | .fvar _ => .error "free variable"
  | .mvar _ => .error "metavariable"
  | .sort u => return .sort (← canonLevel levels u)
  | .const n us => return .const (← ref n) (← us.mapM (canonLevel levels))
  | .app f a => return .app (← canon levels ref f) (← canon levels ref a)
  | .lam _ ty body bi => return .lam bi (← canon levels ref ty) (← canon levels ref body)
  | .forallE _ ty body bi => return .pi bi (← canon levels ref ty) (← canon levels ref body)
  | .letE _ ty val body _ =>
    return .letE (← canon levels ref ty) (← canon levels ref val) (← canon levels ref body)
  | .lit (.natVal n) => .ok (.natLit n)
  | .lit (.strVal s) => .ok (.strLit s)
  | .mdata _ e => canon levels ref e
  | .proj n i e => return .proj (← ref n) i (← canon levels ref e)

theorem canon_mdata (levels : List Name) (ref : Name → Except String Ref) (d : MData) (e : Expr) :
    canon levels ref (.mdata d e) = canon levels ref e := rfl

namespace Encode

def Splits {α : Type} (enc : α → List Char) : Prop :=
  ∀ a b r1 r2, enc a ++ r1 = enc b ++ r2 → a = b ∧ r1 = r2

def encNat (n : Nat) : List Char := (toString n).toList ++ [';']

theorem semi_not_in_toString (n : Nat) : ';' ∉ (toString n).toList := by
  intro h
  have hd := Nat.isDigit_of_mem_toDigits (b := 10) (by decide) (by decide)
    (by simpa [Nat.toString_eq_repr, Nat.toList_repr] using h)
  simp [Char.isDigit] at hd

theorem toString_nat_injective {a b : Nat} (h : toString a = toString b) : a = b := by
  have hdigits : Nat.toDigits 10 a = Nat.toDigits 10 b := by
    simpa [Nat.toString_eq_repr, Nat.toList_repr] using congrArg String.toList h
  have := congrArg (Nat.ofDigitChars 10 · 0) hdigits
  simpa [Nat.ofDigitChars_ten_toDigits] using this

theorem append_term_splits {a b r1 r2 : List Char}
    (ha : ';' ∉ a) (hb : ';' ∉ b)
    (h : a ++ ';' :: r1 = b ++ ';' :: r2) : a = b ∧ r1 = r2 := by
  rcases List.append_eq_append_iff.mp h with ⟨e, hbEq, hr⟩ | ⟨e, haEq, hr⟩
  · cases e with
    | nil =>
      constructor
      · have hba : b = a := by simpa using hbEq
        exact hba.symm
      · simpa using hr
    | cons c es =>
      have hc : c = ';' := by
        have : (c :: es) ++ ';' :: r2 = ';' :: r1 := hr.symm
        simp at this
        exact this.1
      have : ';' ∈ b := by
        rw [hbEq]
        simp [hc]
      exact absurd this hb
  · cases e with
    | nil =>
      constructor
      · simpa using haEq
      · have : r2 = r1 := by simpa using hr
        exact this.symm
    | cons c es =>
      have hc : c = ';' := by
        have : (c :: es) ++ ';' :: r1 = ';' :: r2 := hr.symm
        simp at this
        exact this.1
      have : ';' ∈ a := by
        rw [haEq]
        simp [hc]
      exact absurd this ha

theorem splits_nat : Splits encNat := by
  intro a b r1 r2 h
  have h' : (toString a).toList ++ ';' :: r1 = (toString b).toList ++ ';' :: r2 := by
    simpa [encNat] using h
  have ⟨hd, hr⟩ := append_term_splits (semi_not_in_toString a) (semi_not_in_toString b) h'
  exact ⟨toString_nat_injective (String.toList_injective hd), hr⟩

def encStr (s : String) : List Char := encNat s.length ++ s.toList

theorem splits_str : Splits encStr := by
  intro a b r1 r2 h
  have ⟨hlen, hrest⟩ := splits_nat a.length b.length (a.toList ++ r1) (b.toList ++ r2)
    (by simpa [encStr] using h)
  have hlenEq : a.toList.length = b.toList.length := by
    simpa [String.length_toList] using hlen
  have ⟨hchars, hr⟩ := (List.append_eq_append_iff_of_size_eq_left hlenEq).1 hrest
  exact ⟨String.toList_injective hchars, hr⟩

def encName : Name → List Char
  | .anonymous => ['A']
  | .str p s => 'S' :: encName p ++ encStr s
  | .num p n => 'N' :: encName p ++ encNat n

theorem splits_name : Splits encName := by
  intro a b r1 r2 h
  induction a generalizing b r1 r2 with
  | anonymous =>
    cases b with
    | anonymous => exact ⟨rfl, by simpa [encName] using h⟩
    | str _ _ | num _ _ => simp [encName] at h
  | str p s ih =>
    cases b with
    | str q t =>
      have h' : encName p ++ (encStr s ++ r1) = encName q ++ (encStr t ++ r2) := by
        simpa [encName] using h
      have ⟨rfl, h2⟩ := ih q (encStr s ++ r1) (encStr t ++ r2) h'
      have ⟨rfl, hr⟩ := splits_str s t r1 r2 h2
      exact ⟨rfl, hr⟩
    | anonymous | num _ _ => simp [encName] at h
  | num p n ih =>
    cases b with
    | num q m =>
      have h' : encName p ++ (encNat n ++ r1) = encName q ++ (encNat m ++ r2) := by
        simpa [encName] using h
      have ⟨rfl, h2⟩ := ih q (encNat n ++ r1) (encNat m ++ r2) h'
      have ⟨rfl, hr⟩ := splits_nat n m r1 r2 h2
      exact ⟨rfl, hr⟩
    | anonymous | str _ _ => simp [encName] at h

def encLevel : CLevel → List Char
  | .zero => ['Z']
  | .succ l => 'S' :: encLevel l
  | .max a b => 'M' :: encLevel a ++ encLevel b
  | .imax a b => 'I' :: encLevel a ++ encLevel b
  | .param i => 'P' :: encNat i

theorem splits_level : Splits encLevel := by
  intro a b r1 r2 h
  induction a generalizing b r1 r2 with
  | zero =>
    cases b with
    | zero => exact ⟨rfl, by simpa [encLevel] using h⟩
    | succ _ | max _ _ | imax _ _ | param _ => simp [encLevel] at h
  | succ l ih =>
    cases b with
    | succ m =>
      have h' : encLevel l ++ r1 = encLevel m ++ r2 := by simpa [encLevel] using h
      have ⟨rfl, hr⟩ := ih m r1 r2 h'
      exact ⟨rfl, hr⟩
    | zero | max _ _ | imax _ _ | param _ => simp [encLevel] at h
  | max a1 a2 ih1 ih2 =>
    cases b with
    | max b1 b2 =>
      have h' : encLevel a1 ++ (encLevel a2 ++ r1) = encLevel b1 ++ (encLevel b2 ++ r2) := by
        simpa [encLevel] using h
      have ⟨rfl, h2⟩ := ih1 b1 (encLevel a2 ++ r1) (encLevel b2 ++ r2) h'
      have ⟨rfl, hr⟩ := ih2 b2 r1 r2 h2
      exact ⟨rfl, hr⟩
    | zero | succ _ | imax _ _ | param _ => simp [encLevel] at h
  | imax a1 a2 ih1 ih2 =>
    cases b with
    | imax b1 b2 =>
      have h' : encLevel a1 ++ (encLevel a2 ++ r1) = encLevel b1 ++ (encLevel b2 ++ r2) := by
        simpa [encLevel] using h
      have ⟨rfl, h2⟩ := ih1 b1 (encLevel a2 ++ r1) (encLevel b2 ++ r2) h'
      have ⟨rfl, hr⟩ := ih2 b2 r1 r2 h2
      exact ⟨rfl, hr⟩
    | zero | succ _ | max _ _ | param _ => simp [encLevel] at h
  | param i =>
    cases b with
    | param j =>
      have h' : encNat i ++ r1 = encNat j ++ r2 := by simpa [encLevel] using h
      have ⟨rfl, hr⟩ := splits_nat i j r1 r2 h'
      exact ⟨rfl, hr⟩
    | zero | succ _ | max _ _ | imax _ _ => simp [encLevel] at h

def encBi : BinderInfo → List Char
  | .default => ['D']
  | .implicit => ['I']
  | .strictImplicit => ['S']
  | .instImplicit => ['T']

theorem splits_bi : Splits encBi := by
  intro a b r1 r2 h
  cases a <;> cases b <;> first
    | exact ⟨rfl, by simpa [encBi] using h⟩
    | simp [encBi] at h

def encRef : Ref → List Char
  | .named n => 'N' :: encName n
  | .byMeaning d => 'D' :: encStr d

theorem splits_ref : Splits encRef := by
  intro a b r1 r2 h
  cases a with
  | named n =>
    cases b with
    | named m =>
      have h' : encName n ++ r1 = encName m ++ r2 := by simpa [encRef] using h
      have ⟨rfl, hr⟩ := splits_name n m r1 r2 h'
      exact ⟨rfl, hr⟩
    | byMeaning _ => simp [encRef] at h
  | byMeaning d =>
    cases b with
    | named _ => simp [encRef] at h
    | byMeaning e =>
      have h' : encStr d ++ r1 = encStr e ++ r2 := by simpa [encRef] using h
      have ⟨rfl, hr⟩ := splits_str d e r1 r2 h'
      exact ⟨rfl, hr⟩

def encElems {α : Type} (enc : α → List Char) : List α → List Char
  | [] => []
  | x :: xs => enc x ++ encElems enc xs

def encList {α : Type} (enc : α → List Char) (xs : List α) : List Char :=
  encNat xs.length ++ encElems enc xs

theorem splits_elems {α : Type} {enc : α → List Char} (henc : Splits enc) :
    ∀ xs ys r1 r2, xs.length = ys.length →
      encElems enc xs ++ r1 = encElems enc ys ++ r2 → xs = ys ∧ r1 = r2 := by
  intro xs
  induction xs with
  | nil =>
    intro ys r1 r2 hlen h
    cases ys with
    | nil => exact ⟨rfl, by simpa [encElems] using h⟩
    | cons _ _ => simp at hlen
  | cons x xs ih =>
    intro ys r1 r2 hlen h
    cases ys with
    | nil => simp at hlen
    | cons y ys =>
      have hlen' : xs.length = ys.length := by simpa using hlen
      have h' : enc x ++ (encElems enc xs ++ r1) = enc y ++ (encElems enc ys ++ r2) := by
        simpa [encElems] using h
      have ⟨rfl, h2⟩ := henc x y (encElems enc xs ++ r1) (encElems enc ys ++ r2) h'
      have ⟨rfl, hr⟩ := ih ys r1 r2 hlen' h2
      exact ⟨rfl, hr⟩

theorem splits_list {α : Type} {enc : α → List Char} (henc : Splits enc) : Splits (encList enc) := by
  intro xs ys r1 r2 h
  have ⟨hlen, hrest⟩ := splits_nat xs.length ys.length
    (encElems enc xs ++ r1) (encElems enc ys ++ r2) (by simpa [encList] using h)
  exact splits_elems henc xs ys r1 r2 hlen hrest

def encExpr : CExpr → List Char
  | .bvar i => 'V' :: encNat i
  | .sort u => 'U' :: encLevel u
  | .const r us => 'C' :: encRef r ++ encList encLevel us
  | .app f a => 'A' :: encExpr f ++ encExpr a
  | .lam bi ty body => 'L' :: encBi bi ++ encExpr ty ++ encExpr body
  | .pi bi ty body => 'P' :: encBi bi ++ encExpr ty ++ encExpr body
  | .letE ty val body => 'E' :: encExpr ty ++ encExpr val ++ encExpr body
  | .natLit n => 'N' :: encNat n
  | .strLit s => 'S' :: encStr s
  | .proj st i e => 'J' :: encRef st ++ encNat i ++ encExpr e

theorem splits_expr : Splits encExpr := by
  intro a b r1 r2 h
  induction a generalizing b r1 r2 with
  | bvar i =>
    cases b with
    | bvar j =>
      have h' : encNat i ++ r1 = encNat j ++ r2 := by simpa [encExpr] using h
      have ⟨rfl, hr⟩ := splits_nat i j r1 r2 h'
      exact ⟨rfl, hr⟩
    | sort _ | const _ _ | app _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | sort u =>
    cases b with
    | sort v =>
      have h' : encLevel u ++ r1 = encLevel v ++ r2 := by simpa [encExpr] using h
      have ⟨rfl, hr⟩ := splits_level u v r1 r2 h'
      exact ⟨rfl, hr⟩
    | bvar _ | const _ _ | app _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | const r us =>
    cases b with
    | const s vs =>
      have h' : encRef r ++ (encList encLevel us ++ r1) =
          encRef s ++ (encList encLevel vs ++ r2) := by simpa [encExpr] using h
      have ⟨rfl, h2⟩ := splits_ref r s (encList encLevel us ++ r1) (encList encLevel vs ++ r2) h'
      have ⟨rfl, hr⟩ := splits_list splits_level us vs r1 r2 h2
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | app _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | app f a ihf iha =>
    cases b with
    | app g c =>
      have h' : encExpr f ++ (encExpr a ++ r1) = encExpr g ++ (encExpr c ++ r2) := by
        simpa [encExpr] using h
      have ⟨rfl, h2⟩ := ihf g (encExpr a ++ r1) (encExpr c ++ r2) h'
      have ⟨rfl, hr⟩ := iha c r1 r2 h2
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | lam bi ty body ihTy ihBody =>
    cases b with
    | lam bj ty2 body2 =>
      have h' : encBi bi ++ (encExpr ty ++ (encExpr body ++ r1)) =
          encBi bj ++ (encExpr ty2 ++ (encExpr body2 ++ r2)) := by simpa [encExpr] using h
      have ⟨rfl, h2⟩ := splits_bi bi bj (encExpr ty ++ (encExpr body ++ r1))
        (encExpr ty2 ++ (encExpr body2 ++ r2)) h'
      have ⟨rfl, h3⟩ := ihTy ty2 (encExpr body ++ r1) (encExpr body2 ++ r2) h2
      have ⟨rfl, hr⟩ := ihBody body2 r1 r2 h3
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | app _ _ | pi _ _ _ | letE _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | pi bi ty body ihTy ihBody =>
    cases b with
    | pi bj ty2 body2 =>
      have h' : encBi bi ++ (encExpr ty ++ (encExpr body ++ r1)) =
          encBi bj ++ (encExpr ty2 ++ (encExpr body2 ++ r2)) := by simpa [encExpr] using h
      have ⟨rfl, h2⟩ := splits_bi bi bj (encExpr ty ++ (encExpr body ++ r1))
        (encExpr ty2 ++ (encExpr body2 ++ r2)) h'
      have ⟨rfl, h3⟩ := ihTy ty2 (encExpr body ++ r1) (encExpr body2 ++ r2) h2
      have ⟨rfl, hr⟩ := ihBody body2 r1 r2 h3
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | app _ _ | lam _ _ _ | letE _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | letE ty val body ihTy ihVal ihBody =>
    cases b with
    | letE ty2 val2 body2 =>
      have h' : encExpr ty ++ (encExpr val ++ (encExpr body ++ r1)) =
          encExpr ty2 ++ (encExpr val2 ++ (encExpr body2 ++ r2)) := by simpa [encExpr] using h
      have ⟨rfl, h2⟩ := ihTy ty2 (encExpr val ++ (encExpr body ++ r1))
        (encExpr val2 ++ (encExpr body2 ++ r2)) h'
      have ⟨rfl, h3⟩ := ihVal val2 (encExpr body ++ r1) (encExpr body2 ++ r2) h2
      have ⟨rfl, hr⟩ := ihBody body2 r1 r2 h3
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | app _ _ | lam _ _ _ | pi _ _ _ | natLit _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | natLit n =>
    cases b with
    | natLit m =>
      have h' : encNat n ++ r1 = encNat m ++ r2 := by simpa [encExpr] using h
      have ⟨rfl, hr⟩ := splits_nat n m r1 r2 h'
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | app _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | strLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | strLit s =>
    cases b with
    | strLit t =>
      have h' : encStr s ++ r1 = encStr t ++ r2 := by simpa [encExpr] using h
      have ⟨rfl, hr⟩ := splits_str s t r1 r2 h'
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | app _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | natLit _ | proj _ _ _ =>
      simp [encExpr] at h
  | proj st i e ih =>
    cases b with
    | proj st2 j e2 =>
      have h' : encRef st ++ (encNat i ++ (encExpr e ++ r1)) =
          encRef st2 ++ (encNat j ++ (encExpr e2 ++ r2)) := by simpa [encExpr] using h
      have ⟨rfl, h2⟩ := splits_ref st st2 (encNat i ++ (encExpr e ++ r1))
        (encNat j ++ (encExpr e2 ++ r2)) h'
      have ⟨rfl, h3⟩ := splits_nat i j (encExpr e ++ r1) (encExpr e2 ++ r2) h2
      have ⟨rfl, hr⟩ := ih e2 r1 r2 h3
      exact ⟨rfl, hr⟩
    | bvar _ | sort _ | const _ _ | app _ _ | lam _ _ _ | pi _ _ _ | letE _ _ _ | natLit _ | strLit _ =>
      simp [encExpr] at h

end Encode

def CExpr.encode (e : CExpr) : String := String.ofList (Encode.encExpr e)

theorem CExpr.encode_injective : Function.Injective CExpr.encode := by
  intro a b h
  have hlist : Encode.encExpr a = Encode.encExpr b := by
    simpa [CExpr.encode, String.toList_ofList] using congrArg String.toList h
  exact (Encode.splits_expr a b [] [] (by simpa using hlist)).1

example :
    canon [] (fun n => .ok (.named n))
      (.lam `x (.const `Nat []) (.bvar 0) .default) =
    canon [] (fun n => .ok (.named n))
      (.lam `y (.const `Nat []) (.bvar 0) .default) := rfl

example :
    canon [`u] (fun n => .ok (.named n)) (.sort (.param `u)) =
    canon [`v] (fun n => .ok (.named n)) (.sort (.param `v)) := rfl

example :
    canon [] (fun n => .ok (.named n)) (.mdata {} (.bvar 0)) =
    canon [] (fun n => .ok (.named n)) (.bvar 0) :=
  canon_mdata _ _ _ _

theorem canon_fvar (levels : List Name) (ref : Name → Except String Ref) (id : FVarId) :
    canon levels ref (.fvar id) = .error "free variable" := rfl

theorem canon_mvar (levels : List Name) (ref : Name → Except String Ref) (id : MVarId) :
    canon levels ref (.mvar id) = .error "metavariable" := rfl

theorem canon_levelMVar (levels : List Name) (ref : Name → Except String Ref) (id : LMVarId) :
    canon levels ref (.sort (.mvar id)) = .error "universe metavariable" := rfl

theorem canonLevel_unknown {n : Name} {levels : List Name} (h : levels.idxOf? n = none) :
    canonLevel levels (.param n) = .error s!"unknown universe parameter {n}" := by
  simp [canonLevel, h]

end MitosGate.Lock.Canon
