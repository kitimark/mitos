import MitosGate.Land
import MitosGate.Speech.Syntax

namespace MitosGate.Speech

open Land (Sha)

def pushLike (k : String) : Bool := k == "push" || k == "force_push" || k == "branch_creation"

def stamps : List Carry.Push → Option (List (Stamp × Carry.Push))
  | [] => some []
  | p :: ps =>
    match stamp? p.time.toList, stamps ps with
    | some t, some r => some ((t, p) :: r)
    | _, _ => none

def latest (l : List (Stamp × Carry.Push)) : Nat := l.foldr (fun e m => max e.1 m) 0

def headAt (pushes : List Carry.Push) (t : Stamp) : Option Sha :=
  match stamps pushes with
  | none => none
  | some ts =>
    if ts.any (·.1 == t) then none
    else
      match (ts.filter (·.1 < t)).filter (·.1 == latest (ts.filter (·.1 < t))) with
      | [] => none
      | (_, p) :: rest =>
        if pushLike p.kind && rest.all (fun e => pushLike e.2.kind && e.2.after == p.after) then
          some p.after
        else none

def matching (known : List Sha) (p : List Char) : List Sha :=
  known.filter fun s => p.isPrefixOf s.toList

def resolve (known : List Sha) (p : List Char) : Option Sha :=
  if p.length = 40 then some (String.ofList p)
  else
    match matching known p with
    | [] => none
    | s :: rest => if rest.all (· == s) then some s else none

def ResolveUnique : Prop :=
  ∀ known p s, p.length < 40 → resolve known p = some s →
    s ∈ known ∧ p.isPrefixOf s.toList = true ∧
      ∀ s' ∈ known, p.isPrefixOf s'.toList = true → s' = s

def ResolveFullSelf : Prop :=
  ∀ known (p : List Char), p.length = 40 → resolve known p = some (String.ofList p)

def HeadAtSound : Prop :=
  ∀ pushes t s, headAt pushes t = some s →
    ∃ p ∈ pushes, p.after = s ∧ pushLike p.kind = true ∧
      ∃ tp, stamp? p.time.toList = some tp ∧ tp < t ∧
        ∀ q ∈ pushes, ∃ tq, stamp? q.time.toList = some tq ∧ tq ≠ t ∧ (tq < t → tq ≤ tp) ∧
          (tq = tp → pushLike q.kind = true ∧ q.after = s)

def SameSecondUnknown : Prop :=
  ∀ pushes t (p : Carry.Push), p ∈ pushes → stamp? p.time.toList = some t →
    headAt pushes t = none

theorem resolveFullSelf : ResolveFullSelf := by
  intro known p hp
  simp [resolve, hp]

theorem resolveUnique : ResolveUnique := by
  intro known p s hp h
  simp only [resolve, Nat.ne_of_lt hp, ite_false] at h
  split at h
  · cases h
  · next s' rest hm =>
    split at h
    · next ha =>
      cases h
      have hmem : s ∈ matching known p := by rw [hm]; exact List.mem_cons_self
      simp only [matching, List.mem_filter] at hmem
      refine ⟨hmem.1, hmem.2, fun t ht htp => ?_⟩
      have : t ∈ matching known p := List.mem_filter.2 ⟨ht, htp⟩
      rw [hm] at this
      rcases List.mem_cons.1 this with rfl | this
      · rfl
      · simpa using List.all_eq_true.1 ha t this
    · cases h

theorem stamps_mem {pushes : List Carry.Push} {ts : List (Stamp × Carry.Push)}
    (h : stamps pushes = some ts) :
    (∀ q ∈ pushes, ∃ tq, stamp? q.time.toList = some tq ∧ (tq, q) ∈ ts) ∧
      ∀ e ∈ ts, e.2 ∈ pushes ∧ stamp? e.2.time.toList = some e.1 := by
  induction pushes generalizing ts with
  | nil => simp [stamps] at h; subst h; simp
  | cons p ps ih =>
    simp only [stamps] at h
    split at h
    · next t r ht hr =>
      cases h
      obtain ⟨h1, h2⟩ := ih hr
      refine ⟨fun q hq => ?_, fun e he => ?_⟩
      · rcases List.mem_cons.1 hq with rfl | hq
        · exact ⟨t, ht, List.mem_cons_self⟩
        · obtain ⟨tq, h, hm⟩ := h1 q hq
          exact ⟨tq, h, List.mem_cons_of_mem _ hm⟩
      · rcases List.mem_cons.1 he with rfl | he
        · exact ⟨List.mem_cons_self, ht⟩
        · obtain ⟨hm, h⟩ := h2 e he
          exact ⟨List.mem_cons_of_mem _ hm, h⟩
    · cases h

theorem latest_ge {l : List (Stamp × Carry.Push)} {e : Stamp × Carry.Push} (h : e ∈ l) :
    e.1 ≤ latest l := by
  induction l with
  | nil => cases h
  | cons f l ih =>
    simp only [latest, List.foldr_cons] at ih ⊢
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

theorem sameSecondUnknown : SameSecondUnknown := by
  intro pushes t p hp ht
  unfold headAt
  split
  · rfl
  · next ts hts =>
    obtain ⟨tq, htq, hm⟩ := (stamps_mem hts).1 p hp
    rw [ht] at htq
    cases htq
    have : ts.any (·.1 == t) = true := List.any_eq_true.2 ⟨_, hm, by simp⟩
    simp [this]

theorem headAtSound : HeadAtSound := by
  intro pushes t s h
  unfold headAt at h
  split at h
  · cases h
  · next ts hts =>
    obtain ⟨hall, hback⟩ := stamps_mem hts
    split at h
    · cases h
    · next hany =>
      split at h
      · cases h
      · next tp p rest hl =>
        split at h
        · next hk =>
          cases h
          simp only [Bool.and_eq_true, List.all_eq_true] at hk
          have hpm : (tp, p) ∈ (ts.filter (·.1 < t)).filter
              (·.1 == latest (ts.filter (·.1 < t))) := by rw [hl]; exact List.mem_cons_self
          simp only [List.mem_filter, decide_eq_true_eq, beq_iff_eq] at hpm
          obtain ⟨⟨hpts, hpt⟩, hplat⟩ := hpm
          obtain ⟨hpin, hpst⟩ := hback _ hpts
          refine ⟨p, hpin, rfl, hk.1, tp, hpst, hpt, fun q hq => ?_⟩
          obtain ⟨tq, hqs, hqm⟩ := hall q hq
          have hne : tq ≠ t := by
            intro he
            subst he
            exact hany (List.any_eq_true.2 ⟨_, hqm, by simp⟩)
          refine ⟨tq, hqs, hne, fun hlt => ?_, fun heq => ?_⟩
          · rw [hplat]
            exact latest_ge (List.mem_filter.2 ⟨hqm, by simpa using hlt⟩)
          · subst heq
            have hqf : (tq, q) ∈ (ts.filter (·.1 < t)).filter
                (·.1 == latest (ts.filter (·.1 < t))) := by
              simp only [List.mem_filter, decide_eq_true_eq, beq_iff_eq]
              exact ⟨⟨hqm, hpt⟩, hplat⟩
            rw [hl] at hqf
            rcases List.mem_cons.1 hqf with he | he
            · cases he; exact ⟨hk.1, rfl⟩
            · have := hk.2 _ he
              simpa using this
        · cases h

end MitosGate.Speech
