import MitosGate.Speech.Comment

/-!
REST keeps only the last `updated_at` and never the first text, so an edited comment cannot be
read as what was first posted.
-/

namespace MitosGate.Speech

open Land (Word Mark newestOwner)

def lastBy (cs : List Comment) (c : Comment) : Nat :=
  cs.foldr (fun d k => if d.created ≤ c.updated then max d.id k else k) c.id

def editPos (cs : List Comment) (c : Comment) : Nat := 2 * lastBy cs c + 1

def Read.pos (r : Read) (cs : List Comment) (c : Comment) : Nat :=
  match r with
  | .editHold => editPos cs c
  | _ => 2 * c.id

def top (x : Ctx) (cs : List Comment) : Nat := cs.foldr (fun d k => max d.id k) x.pr

def place (w : Word) : List Word → List Word
  | [] => [w]
  | v :: vs =>
    if w.said < v.said then w :: v :: vs
    else if v.said < w.said then v :: place w vs
    else .ownerHold w.said :: vs

def arrange (ws : List Word) : List Word := ws.foldr place []

def said (x : Ctx) (cs : List Comment) (pushes : List Carry.Push) (complete : Bool) : List Word :=
  let ws := cs.filterMap fun c => (read x pushes c).word ((read x pushes c).pos cs c)
  if complete then ws else .ownerHold (2 * top x cs + 1) :: ws

def words (x : Ctx) (cs : List Comment) (pushes : List Carry.Push) (complete : Bool) :
    List Word × List (Nat × Why) :=
  (arrange (said x cs pushes complete),
    cs.filterMap fun c =>
      match read x pushes c with
      | .ignored why => some (c.id, why)
      | _ => none)

def EditHoldsWhateverItSays : Prop :=
  ∀ (x : Ctx) cs pushes b (c : Comment), c ∈ cs → c.login = x.owner → c.updated ≠ c.created →
    read x pushes c = .editHold ∧ Word.ownerHold (editPos cs c) ∈ (words x cs pushes b).1

def EditHoldBeatsEarlierComments : Prop :=
  ∀ (x : Ctx) cs pushes b (c d : Comment), c ∈ cs → c.login = x.owner →
    c.updated ≠ c.created → d ∈ cs → d.created ≤ c.updated →
    2 * d.id < editPos cs c ∧
      ∀ m, newestOwner (words x cs pushes b).1 = some (.ownerLand m) → editPos cs c < m.said

def SecondEditOnlyMovesLater : Prop :=
  ∀ (x : Ctx) pushes cs (c : Comment) t, c.login = x.owner → c.created < c.updated →
    c.updated ≤ t →
    read x pushes { c with updated := t } = .editHold ∧
      editPos cs c ≤ editPos cs { c with updated := t }

def IncompleteReadHolds : Prop :=
  ∀ x cs pushes, ∃ n, newestOwner (words x cs pushes false).1 = some (.ownerHold n)

def PositionsAscendingDistinct : Prop :=
  ∀ x cs pushes b, ((words x cs pushes b).1.map Word.said).Pairwise (· < ·)

def WordTraces : Prop :=
  ∀ x cs pushes b, ∀ u ∈ (words x cs pushes b).1,
    ((∃ c ∈ cs, (read x pushes c).word ((read x pushes c).pos cs c) = some u) ∨
      u = .ownerHold u.said) ∧
    ((∃ d ∈ cs, u.said = 2 * d.id ∨ u.said = 2 * d.id + 1) ∨
      (b = false ∧ u.said = 2 * top x cs + 1))

def OwnerLandIsTyped : Prop :=
  ∀ (x : Ctx) cs pushes b m, Word.ownerLand m ∈ (words x cs pushes b).1 →
    ∃ c ∈ cs, c.login = x.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      footer c.body.toList = false ∧ m.said = 2 * c.id ∧
      ∃ arg, ownerLines c.body.toList = .ok [.land arg] ∧ target x pushes c.created arg = some m.about

theorem place_mem {w u : Word} {vs : List Word} (h : u ∈ place w vs) :
    u = w ∨ u ∈ vs ∨ u = .ownerHold w.said := by
  induction vs with
  | nil => simp [place] at h; exact .inl h
  | cons v vs ih =>
    simp only [place] at h
    split at h
    · rcases List.mem_cons.1 h with h | h
      · exact .inl h
      · exact .inr (.inl h)
    · split at h
      · rcases List.mem_cons.1 h with h | h
        · exact .inr (.inl (h ▸ List.mem_cons_self))
        · rcases ih h with h | h | h
          · exact .inl h
          · exact .inr (.inl (List.mem_cons_of_mem _ h))
          · exact .inr (.inr h)
      · rcases List.mem_cons.1 h with h | h
        · exact .inr (.inr h)
        · exact .inr (.inl (List.mem_cons_of_mem _ h))

theorem place_keeps (w : Word) (vs : List Word) :
    (∃ u ∈ place w vs, u.said = w.said ∧ (u = w ∨ u = .ownerHold w.said)) ∧
      ∀ v ∈ vs, ∃ u ∈ place w vs, u.said = v.said ∧ (u = v ∨ u = .ownerHold v.said) := by
  induction vs with
  | nil => exact ⟨⟨w, by simp [place]⟩, by simp⟩
  | cons v vs ih =>
    simp only [place]
    split
    · exact ⟨⟨w, List.mem_cons_self, rfl, .inl rfl⟩,
        fun y hy => ⟨y, List.mem_cons_of_mem _ hy, rfl, .inl rfl⟩⟩
    · split
      · obtain ⟨⟨u, hu, hs, he⟩, hr⟩ := ih
        refine ⟨⟨u, List.mem_cons_of_mem _ hu, hs, he⟩, fun y hy => ?_⟩
        rcases List.mem_cons.1 hy with rfl | hy
        · exact ⟨y, List.mem_cons_self, rfl, .inl rfl⟩
        · obtain ⟨u, hu, hs, he⟩ := hr y hy
          exact ⟨u, List.mem_cons_of_mem _ hu, hs, he⟩
      · next h1 h2 =>
        have he : v.said = w.said := by omega
        refine ⟨⟨_, List.mem_cons_self, rfl, .inr rfl⟩, fun y hy => ?_⟩
        rcases List.mem_cons.1 hy with rfl | hy
        · exact ⟨_, List.mem_cons_self, show w.said = y.said from he.symm, .inr (by rw [he])⟩
        · exact ⟨y, List.mem_cons_of_mem _ hy, rfl, .inl rfl⟩

theorem place_sorted (w : Word) {vs : List Word} (h : vs.Pairwise (·.said < ·.said)) :
    (place w vs).Pairwise (·.said < ·.said) := by
  induction vs with
  | nil => simp [place]
  | cons v vs ih =>
    rw [List.pairwise_cons] at h
    simp only [place]
    split
    · next hl =>
      refine List.Pairwise.cons (fun y hy => ?_) (List.Pairwise.cons h.1 h.2)
      rcases List.mem_cons.1 hy with rfl | hy
      · exact hl
      · exact Nat.lt_trans hl (h.1 y hy)
    · split
      · next hl =>
        refine List.Pairwise.cons (fun y hy => ?_) (ih h.2)
        rcases place_mem hy with rfl | hy | rfl
        · exact hl
        · exact h.1 y hy
        · exact hl
      · next h1 h2 =>
        have he : v.said = w.said := by omega
        refine List.Pairwise.cons (fun y hy => ?_) h.2
        show w.said < y.said
        rw [← he]
        exact h.1 y hy

theorem arrange_sorted (ws : List Word) : (arrange ws).Pairwise (·.said < ·.said) := by
  induction ws with
  | nil => exact List.Pairwise.nil
  | cons w ws ih => exact place_sorted w ih

theorem arrange_mem {ws : List Word} {u : Word} (h : u ∈ arrange ws) :
    u ∈ ws ∨ ∃ w ∈ ws, u = .ownerHold w.said := by
  induction ws with
  | nil => cases h
  | cons w ws ih =>
    rcases place_mem h with rfl | h | rfl
    · exact .inl List.mem_cons_self
    · rcases ih h with h | ⟨v, hv, rfl⟩
      · exact .inl (List.mem_cons_of_mem _ h)
      · exact .inr ⟨v, List.mem_cons_of_mem _ hv, rfl⟩
    · exact .inr ⟨w, List.mem_cons_self, rfl⟩

theorem arrange_keeps {ws : List Word} {w : Word} (h : w ∈ ws) :
    ∃ u ∈ arrange ws, u.said = w.said ∧ (u = w ∨ u = .ownerHold w.said) := by
  induction ws with
  | nil => cases h
  | cons v ws ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact (place_keeps w _).1
    · obtain ⟨u, hu, hs, he⟩ := ih h
      obtain ⟨u', hu', hs', he'⟩ := (place_keeps v _).2 u hu
      refine ⟨u', hu', hs'.trans hs, ?_⟩
      rcases he' with rfl | rfl
      · exact he
      · exact .inr (by rw [hs])

theorem arrange_hold {ws : List Word} {n : Nat} (h : .ownerHold n ∈ ws) :
    .ownerHold n ∈ arrange ws := by
  obtain ⟨u, hu, -, he⟩ := arrange_keeps h
  rcases he with rfl | rfl <;> exact hu

theorem arrange_nodup (ws : List Word) : ((arrange ws).map Word.said).Nodup := by
  have := arrange_sorted ws
  rw [List.Nodup, List.pairwise_map]
  exact this.imp fun h => Nat.ne_of_lt h

theorem positionsAscendingDistinct : PositionsAscendingDistinct := by
  intro x cs pushes b
  rw [List.pairwise_map]
  exact arrange_sorted _

theorem lastBy_ge (cs : List Comment) (c : Comment) :
    c.id ≤ lastBy cs c ∧ ∀ d ∈ cs, d.created ≤ c.updated → d.id ≤ lastBy cs c := by
  induction cs with
  | nil => simp [lastBy]
  | cons e cs ih =>
    simp only [lastBy, List.foldr_cons] at ih ⊢
    obtain ⟨h1, h2⟩ := ih
    split
    · refine ⟨Nat.le_trans h1 (Nat.le_max_right _ _), fun d hd hc => ?_⟩
      rcases List.mem_cons.1 hd with rfl | hd
      · exact Nat.le_max_left _ _
      · exact Nat.le_trans (h2 d hd hc) (Nat.le_max_right _ _)
    · next hn =>
      refine ⟨h1, fun d hd hc => ?_⟩
      rcases List.mem_cons.1 hd with rfl | hd
      · exact absurd hc hn
      · exact h2 d hd hc

theorem lastBy_of (cs : List Comment) (c : Comment) :
    lastBy cs c = c.id ∨ ∃ d ∈ cs, lastBy cs c = d.id := by
  induction cs with
  | nil => exact .inl rfl
  | cons e cs ih =>
    simp only [lastBy, List.foldr_cons] at ih ⊢
    split
    · rcases Nat.le_total e.id (cs.foldr (fun d k => if d.created ≤ c.updated then max d.id k else k) c.id) with h | h
      · rw [Nat.max_eq_right h]
        rcases ih with h | ⟨d, hd, h⟩
        · exact .inl h
        · exact .inr ⟨d, List.mem_cons_of_mem _ hd, h⟩
      · rw [Nat.max_eq_left h]
        exact .inr ⟨e, List.mem_cons_self, rfl⟩
    · rcases ih with h | ⟨d, hd, h⟩
      · exact .inl h
      · exact .inr ⟨d, List.mem_cons_of_mem _ hd, h⟩

theorem lastBy_mono (cs : List Comment) (c : Comment) {t : Stamp} (ht : c.updated ≤ t) :
    lastBy cs c ≤ lastBy cs { c with updated := t } := by
  induction cs with
  | nil => exact Nat.le_refl _
  | cons e cs ih =>
    simp only [lastBy, List.foldr_cons] at ih ⊢
    split
    · next he =>
      have : e.created ≤ t := Nat.le_trans he ht
      simp only [this, ite_true]
      exact Nat.max_le.2 ⟨Nat.le_max_left _ _, Nat.le_trans ih (Nat.le_max_right _ _)⟩
    · split
      · exact Nat.le_trans ih (Nat.le_max_right _ _)
      · exact ih

theorem top_ge (x : Ctx) (cs : List Comment) : x.pr ≤ top x cs ∧ ∀ d ∈ cs, d.id ≤ top x cs := by
  induction cs with
  | nil => simp [top]
  | cons e cs ih =>
    simp only [top, List.foldr_cons] at ih ⊢
    refine ⟨Nat.le_trans ih.1 (Nat.le_max_right _ _), fun d hd => ?_⟩
    rcases List.mem_cons.1 hd with rfl | hd
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih.2 d hd) (Nat.le_max_right _ _)

theorem lastBy_le_top (x : Ctx) {cs : List Comment} {c : Comment} (hc : c ∈ cs) :
    lastBy cs c ≤ top x cs := by
  rcases lastBy_of cs c with h | ⟨d, hd, h⟩ <;> rw [h]
  · exact (top_ge x cs).2 c hc
  · exact (top_ge x cs).2 d hd

theorem pos_cases (r : Read) (cs : List Comment) (c : Comment) :
    r.pos cs c = 2 * c.id ∨ r.pos cs c = editPos cs c := by
  cases r <;> simp [Read.pos]

theorem pos_le_top (x : Ctx) (r : Read) {cs : List Comment} {c : Comment} (hc : c ∈ cs) :
    r.pos cs c ≤ 2 * top x cs + 1 := by
  rcases pos_cases r cs c with h | h <;> rw [h]
  · have := (top_ge x cs).2 c hc; omega
  · have := lastBy_le_top x hc; simp only [editPos]; omega

theorem pos_traces (r : Read) (cs : List Comment) (c : Comment) (hc : c ∈ cs) :
    ∃ d ∈ cs, r.pos cs c = 2 * d.id ∨ r.pos cs c = 2 * d.id + 1 := by
  rcases pos_cases r cs c with h | h
  · exact ⟨c, hc, .inl h⟩
  · rw [h]
    rcases lastBy_of cs c with h' | ⟨d, hd, h'⟩
    · exact ⟨c, hc, .inr (by simp [editPos, h'])⟩
    · exact ⟨d, hd, .inr (by simp [editPos, h'])⟩

theorem mem_said {x : Ctx} {cs : List Comment} {pushes : List Carry.Push} {b : Bool} {w : Word} :
    w ∈ said x cs pushes b ↔
      (b = false ∧ w = .ownerHold (2 * top x cs + 1)) ∨
        ∃ c ∈ cs, (read x pushes c).word ((read x pushes c).pos cs c) = some w := by
  cases b <;> simp [said, List.mem_filterMap]

theorem said_le_top {x : Ctx} {cs : List Comment} {pushes : List Carry.Push} {b : Bool}
    {w : Word} (h : w ∈ said x cs pushes b) : w.said ≤ 2 * top x cs + 1 := by
  rcases mem_said.1 h with ⟨-, rfl⟩ | ⟨c, hc, hw⟩
  · exact Nat.le_refl _
  · rw [word_said hw]; exact pos_le_top x _ hc

theorem editHoldsWhateverItSays : EditHoldsWhateverItSays := by
  intro x cs pushes b c hc ho hu
  have hr := read_edited (pushes := pushes) ho hu
  refine ⟨hr, arrange_hold (mem_said.2 (.inr ⟨c, hc, ?_⟩))⟩
  rw [hr]
  rfl

theorem newest_land_above {ws : List Word} {n : Nat} {m : Mark}
    (hn : (ws.map Word.said).Nodup) (hh : .ownerHold n ∈ ws)
    (hm : newestOwner ws = some (.ownerLand m)) : n < m.said := by
  obtain ⟨hmem, -, hmax⟩ := Land.newestOwner_max hm
  have hle : n ≤ m.said := hmax _ hh rfl
  rcases Nat.lt_or_eq_of_le hle with h | h
  · exact h
  · have := Land.eq_of_said_eq hn hh hmem h
    cases this

theorem editHoldBeatsEarlierComments : EditHoldBeatsEarlierComments := by
  intro x cs pushes b c d hc ho hu hd hdc
  refine ⟨?_, fun m hm => ?_⟩
  · have := (lastBy_ge cs c).2 d hd hdc
    simp only [editPos]
    omega
  · exact newest_land_above (arrange_nodup _) (editHoldsWhateverItSays x cs pushes b c hc ho hu).2 hm

theorem secondEditOnlyMovesLater : SecondEditOnlyMovesLater := by
  intro x pushes cs c t ho hcu ht
  refine ⟨read_edited ho (fun h => absurd (h ▸ ht) (Nat.not_le.2 hcu)), ?_⟩
  have := lastBy_mono cs c ht
  simp only [editPos]
  omega

theorem incompleteReadHolds : IncompleteReadHolds := by
  intro x cs pushes
  refine ⟨2 * top x cs + 1, ?_⟩
  show newestOwner (arrange (said x cs pushes false)) = _
  rw [Land.newestOwner_eq_some (arrange_nodup _)]
  refine ⟨arrange_hold (mem_said.2 (.inl ⟨rfl, rfl⟩)), rfl, fun u hu _ => ?_⟩
  rcases arrange_mem hu with h | ⟨w, hw, rfl⟩
  · exact said_le_top h
  · exact said_le_top (w := w) hw

theorem wordTraces : WordTraces := by
  intro x cs pushes b u hu
  have hpos : ∀ w ∈ said x cs pushes b, (∃ d ∈ cs, w.said = 2 * d.id ∨ w.said = 2 * d.id + 1) ∨
      (b = false ∧ w.said = 2 * top x cs + 1) := by
    intro w hw
    rcases mem_said.1 hw with ⟨hb, rfl⟩ | ⟨c, hc, hw⟩
    · exact .inr ⟨hb, rfl⟩
    · rw [word_said hw]; exact .inl (pos_traces _ cs c hc)
  rcases arrange_mem hu with h | ⟨w, hw, rfl⟩
  · refine ⟨?_, hpos u h⟩
    rcases mem_said.1 h with ⟨-, rfl⟩ | h
    · exact .inr rfl
    · exact .inl h
  · exact ⟨.inr rfl, hpos w hw⟩

theorem ownerLandIsTyped : OwnerLandIsTyped := by
  intro x cs pushes b m hm
  obtain ⟨⟨c, hc, hw⟩ | hh, -⟩ := wordTraces x cs pushes b _ hm
  · refine ⟨c, hc, ?_⟩
    have hb := word_byOwner hw
    by_cases ho : c.login = x.owner
    · by_cases hu : c.updated = c.created
      · cases hs : c.slug with
        | some s => rw [read_slug hs hu] at hb; simp [Land.Word.byOwner] at hb
        | none =>
          rw [read_typed ho hu hs] at hw
          refine ⟨ho, rfl, hu, ?_⟩
          cases hr : ownerRead x pushes c.created c.body.toList with
          | land s =>
            rw [hr] at hw
            simp only [Read.word, Read.pos, Option.some.injEq, Land.Word.ownerLand.injEq] at hw
            subst hw
            obtain ⟨arg, hl, ht⟩ := ownerRead_land hr
            exact ⟨ownerLines_footer hl, rfl, arg, hl, ht⟩
          | _ => rw [hr] at hw; simp [Read.word] at hw
      · rw [read_edited ho hu] at hw; simp [Read.word] at hw
    · simp [read, ho, Read.word] at hw
  · cases hh

end MitosGate.Speech
