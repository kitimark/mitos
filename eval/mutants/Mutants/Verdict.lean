import Mutants.Manifest

namespace Mutants

inductive Run where
  | accepted
  | rejected
  | failed
  deriving Repr, DecidableEq

def okMarker : String := "Your solution is okay!"

def Run.ofExit (code : UInt32) (output : String) : Run :=
  if code == 0 && (splitFirst okMarker.toList output.toList).isSome then .accepted
  else if code == 1 then .rejected
  else .failed

theorem Run.ofExit_accepted {code : UInt32} {output : String} (h : Run.ofExit code output = .accepted) :
    code = 0 ∧ ∃ pre post, output.toList = pre ++ okMarker.toList ++ post := by
  unfold Run.ofExit at h
  split at h
  · rename_i hc
    simp only [Bool.and_eq_true, beq_iff_eq] at hc
    obtain ⟨⟨pre, post⟩, hs⟩ := Option.isSome_iff_exists.mp hc.2
    exact ⟨hc.1, pre, post, (splitFirst_some hs).1⟩
  · split at h <;> simp at h

structure Runs where
  lint       : List String := []
  holes      : Option Run := none
  approved   : Option Run := none
  values     : Option Run := none
  refutation : Option Run := none
  deriving Repr, DecidableEq

inductive Outcome where
  | refuted
  | rejected
  | survived
  | unbound
  | failed
  | invalid
  | refused
  deriving Repr, DecidableEq

def outcome (x : Runs) : Outcome :=
  if !x.lint.isEmpty then .refused else
  match x.holes, x.approved, x.values, x.refutation with
  | none, _, _, _ => .failed
  | some .failed, _, _, _ => .failed
  | some .rejected, _, _, _ => .unbound
  | some .accepted, none, _, _ => .failed
  | some .accepted, some .failed, _, _ => .failed
  | some .accepted, some .accepted, some .accepted, _ => .survived
  | some .accepted, some .accepted, some .failed, _ => .failed
  | some .accepted, some .accepted, _, _ => .unbound
  | some .accepted, some .rejected, _, some .accepted => .refuted
  | some .accepted, some .rejected, _, some .failed => .failed
  | some .accepted, some .rejected, _, _ => .rejected

theorem outcome_refuted_iff {x : Runs} :
    outcome x = .refuted ↔ x.lint = [] ∧
      x.holes = some .accepted ∧ x.approved = some .rejected ∧ x.refutation = some .accepted := by
  obtain ⟨l, h, a, v, r⟩ := x
  cases l <;> rcases h with _ | (_ | _ | _) <;> rcases a with _ | (_ | _ | _) <;>
    rcases v with _ | (_ | _ | _) <;> rcases r with _ | (_ | _ | _) <;> simp [outcome]

theorem outcome_survived_iff {x : Runs} :
    outcome x = .survived ↔ x.lint = [] ∧
      x.holes = some .accepted ∧ x.approved = some .accepted ∧ x.values = some .accepted := by
  obtain ⟨l, h, a, v, r⟩ := x
  cases l <;> rcases h with _ | (_ | _ | _) <;> rcases a with _ | (_ | _ | _) <;>
    rcases v with _ | (_ | _ | _) <;> rcases r with _ | (_ | _ | _) <;> simp [outcome]

def Outcome.meets : Outcome → Expect → Bool
  | .refuted, .breaks _ => true
  | .survived, .survives _ => true
  | _, _ => false

def Stage.rejected : Stage → Runs → Bool
  | .lint, x => !x.lint.isEmpty && x.holes.isNone && x.approved.isNone && x.values.isNone &&
    x.refutation.isNone
  | .holes, x => x.lint.isEmpty && x.holes == some .rejected
  | .values, x => x.lint.isEmpty && x.holes == some .accepted && x.approved == some .accepted &&
    x.values == some .rejected
  | .refutation, x => x.lint.isEmpty &&
    x.holes == some .accepted && x.approved == some .rejected && x.refutation == some .rejected

theorem Stage.rejected_outcome {s : Stage} {x : Runs} (h : s.rejected x = true) :
    outcome x ≠ .refuted ∧ outcome x ≠ .survived := by
  obtain ⟨l, hl, a, v, r⟩ := x
  cases s <;> simp only [Stage.rejected, Bool.and_eq_true, beq_iff_eq] at h <;>
    simp only [ne_eq, outcome_refuted_iff, outcome_survived_iff] <;> cases l <;> simp_all

inductive Judged where
  | invalid (why : String)
  | ran (expect : Expect) (rejects : Option Stage) (runs : Runs)
  deriving Repr, DecidableEq

structure Result where
  name   : String
  judged : Judged
  deriving Repr, DecidableEq

def Result.outcome (r : Result) : Outcome :=
  match r.judged with
  | .invalid _ => .invalid
  | .ran _ _ x => Mutants.outcome x

def Result.ok (r : Result) : Bool :=
  match r.judged with
  | .invalid _ => false
  | .ran _ (some s) x => s.rejected x
  | .ran e none x => (Mutants.outcome x).meets e

def passes (control : Run) (cases : List String) (rs : List Result) : Bool :=
  control == .accepted && !cases.isEmpty &&
  cases.all (fun c => rs.countP (·.name == c) == 1) &&
  rs.all (fun r => cases.contains r.name && r.ok)

theorem passes_iff {control : Run} {cases : List String} {rs : List Result} :
    passes control cases rs = true ↔
      control = .accepted ∧ cases ≠ [] ∧ (∀ c ∈ cases, rs.countP (·.name == c) = 1) ∧
        ∀ r ∈ rs, r.name ∈ cases ∧ r.ok = true := by
  simp only [passes, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true', List.isEmpty_eq_false_iff,
    List.all_eq_true, List.contains_iff_mem, and_assoc]

theorem passes_refuted {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) :
    ∀ r ∈ rs, ∀ ts x, r.judged = .ran (.breaks ts) none x → x.lint = [] ∧
      x.holes = some .accepted ∧ x.approved = some .rejected ∧ x.refutation = some .accepted := by
  intro r hr ts x hj
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  simp only [Result.ok, hj] at hok
  have : outcome x = .refuted := by
    revert hok; cases outcome x <;> simp [Outcome.meets]
  exact outcome_refuted_iff.mp this

theorem passes_survived {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) :
    ∀ r ∈ rs, ∀ g x, r.judged = .ran (.survives g) none x → x.lint = [] ∧
      x.holes = some .accepted ∧ x.approved = some .accepted ∧ x.values = some .accepted := by
  intro r hr g x hj
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  simp only [Result.ok, hj] at hok
  have : outcome x = .survived := by
    revert hok; cases outcome x <;> simp [Outcome.meets]
  exact outcome_survived_iff.mp this

theorem passes_rejects {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) :
    ∀ r ∈ rs, ∀ e s x, r.judged = .ran e (some s) x →
      s.rejected x = true ∧ outcome x ≠ .refuted ∧ outcome x ≠ .survived := by
  intro r hr e s x hj
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  simp only [Result.ok, hj] at hok
  exact ⟨hok, Stage.rejected_outcome hok⟩

theorem passes_refused {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) :
    ∀ r ∈ rs, ∀ e s x, r.judged = .ran e s x → x.lint ≠ [] →
      s = some .lint ∧ x.holes = none ∧ x.approved = none ∧ x.values = none ∧ x.refutation = none := by
  intro r hr e s x hj hl
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  obtain ⟨l, hs, a, v, rf⟩ := x
  cases l with
  | nil => exact absurd rfl hl
  | cons _ _ =>
    cases s with
    | none => simp [Result.ok, hj, outcome, Outcome.meets] at hok
    | some st => cases st <;> simp_all [Result.ok, Stage.rejected]

theorem passes_judged {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) : ∀ r ∈ rs, ∃ e s x, r.judged = .ran e s x := by
  intro r hr
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  unfold Result.ok at hok
  split at hok
  · simp at hok
  · rename_i e s x hj
    exact ⟨e, some s, x, hj⟩
  · rename_i e x hj
    exact ⟨e, none, x, hj⟩

def breakers (rs : List Result) (t : String) : List String :=
  rs.filterMap fun r =>
    match r.judged with
    | .ran (.breaks ts) none x => if outcome x == .refuted && ts.contains t then some r.name else none
    | _ => none

theorem mem_breakers {rs : List Result} {t n : String} :
    n ∈ breakers rs t ↔ ∃ r ∈ rs, r.name = n ∧ ∃ ts x, r.judged = .ran (.breaks ts) none x ∧
      t ∈ ts ∧ x.lint = [] ∧ x.holes = some .accepted ∧ x.approved = some .rejected ∧
        x.refutation = some .accepted := by
  simp only [breakers, List.mem_filterMap]
  constructor
  · rintro ⟨r, hr, hm⟩
    split at hm
    · rename_i ts x hj
      split at hm
      · rename_i hc
        simp only [Option.some.injEq] at hm
        simp only [Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem] at hc
        exact ⟨r, hr, hm, ts, x, hj, hc.2, outcome_refuted_iff.mp hc.1⟩
      · simp at hm
    · simp at hm
  · rintro ⟨r, hr, rfl, ts, x, hj, ht, hx⟩
    refine ⟨r, hr, ?_⟩
    simp only [hj]
    have : outcome x = .refuted := outcome_refuted_iff.mpr hx
    simp [this, ht]

end Mutants
