import Mutants.Manifest

/-!
# Outcomes and the run's verdict

First the **lint** (`Mutants.Lint`) reads every Lean text the case wrote or changed: the
`replace=` texts, each file its edits change, and its `Refute.lean`. If it finds code that runs or
declares syntax while Lean elaborates, an import outside the approved core and the implementation,
or a name declared, entered or opened outside the namespaces the text may use, the case is refused
and nothing is built. Otherwise it gets up to three sandboxed
`lake comparator` runs, each in a fresh copy of the core:

1. **holes**: the mutated core with only the edits under `Mitos/Impl/`, without `Mitos/Proofs/`
   and without any file of the case. The solution module imports every `Mitos/Impl/` module, and
   the configuration is the approved one's definition holes alone. Accepted means: the mutant's
   implementation builds from the approved core alone, and declares every approved hole publicly,
   with its approved type and standard axioms. A case whose implementation hides a hole
   (`private`) stops here.
2. **approved**: the approved Challenge and configuration (`core/Challenge/Resolver.lean`,
   `core/comparator.json`) with the real solution module, on the mutated core. This is what the PR
   gate does with the bug.
3. After an acceptance, **values**: the approved Challenge with the holes as values
   (`Mutants.approvedByValue`), so the comparator compares the solution's holes with the mutant's
   by value. Accepted means the gate's acceptance is about the mutant's own holes.
   After a rejection, for a `breaks=` case, **refutation**: the refutation Challenge with the holes
   as values (`Mutants.refutation`) against the case's `Refute.lean`. Accepted means each named
   theorem is proved false, with standard axioms only, for the mutant's own holes.

Before any case, a **control** run judges the unmutated core as in run 2; it must be accepted, so a
rejection in run 2 comes from the mutant and not from the workspace.

The run passes exactly when the control is accepted, there is at least one case, every case is
judged exactly once, and every case meets its expectation (`passes_iff`). Then every `breaks=` case
passed the lint and was refuted for its own holes (`passes_refuted`), every `survives=` case passed
the lint and was accepted by the gate about its own holes (`passes_survived`), every cheat case was
rejected at its stage and counted neither as refuted nor as surviving (`passes_rejects`), and the
lint refused only cheat cases that expect it (`passes_refused`).
-/

namespace Mutants

/-- What one comparator run decided. -/
inductive Run where
  /-- Exit code 0 and `Your solution is okay!`. -/
  | accepted
  /-- Exit code 1: a statement mismatch, an illegal axiom, a kernel rejection or a failed build. -/
  | rejected
  /-- Anything else, such as exit code 2 (could not start): no judgment. -/
  | failed
  deriving Repr, DecidableEq

def okMarker : String := "Your solution is okay!"

def Run.ofExit (code : UInt32) (output : String) : Run :=
  if code == 0 && (splitFirst okMarker.toList output.toList).isSome then .accepted
  else if code == 1 then .rejected
  else .failed

/-- Only a run that exited with 0 and printed the marker is accepted. -/
theorem Run.ofExit_accepted {code : UInt32} {output : String} (h : Run.ofExit code output = .accepted) :
    code = 0 ∧ ∃ pre post, output.toList = pre ++ okMarker.toList ++ post := by
  unfold Run.ofExit at h
  split at h
  · rename_i hc
    simp only [Bool.and_eq_true, beq_iff_eq] at hc
    obtain ⟨⟨pre, post⟩, hs⟩ := Option.isSome_iff_exists.mp hc.2
    exact ⟨hc.1, pre, post, (splitFirst_some hs).1⟩
  · split at h <;> simp at h

/-- The lint's findings and the comparator runs of one case; a run that did not happen is `none`. -/
structure Runs where
  /-- What the lint found in the case's Lean text, one line each (`Mutants.Lint`). The comparator
  runs only when it found nothing. -/
  lint       : List String := []
  holes      : Option Run := none
  approved   : Option Run := none
  values     : Option Run := none
  refutation : Option Run := none
  deriving Repr, DecidableEq

/-- What happened to one mutant. -/
inductive Outcome where
  /-- The holes are the mutant's, the gate rejects it, and the refutation of every named theorem
  is accepted for those holes. -/
  | refuted
  /-- The holes are the mutant's and the gate rejects it, but no refutation is accepted. -/
  | rejected
  /-- The holes are the mutant's, and the gate accepts it with proofs about those holes. -/
  | survived
  /-- The mutant's implementation alone does not build the approved holes, or the gate accepts
  proofs that are not about them. -/
  | unbound
  /-- A comparator run gave no judgment. -/
  | failed
  /-- The case could not be set up: its manifest, its files, its edits or its Challenge. -/
  | invalid
  /-- The lint found code that runs or declares syntax while Lean elaborates, an import outside
  the approved core and the implementation, or a name outside the namespaces the text may use, in
  the case's Lean text; nothing was built. -/
  | refused
  deriving Repr, DecidableEq

/-- The outcome of a case's runs. -/
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

/-- Whether an outcome is the one a case's claim expects. -/
def Outcome.meets : Outcome → Expect → Bool
  | .refuted, .breaks _ => true
  | .survived, .survives _ => true
  | _, _ => false

/-- Whether a cheat case was rejected at stage `s`, after every earlier stage let it through: at
the lint, with no comparator run; at a run, after a lint that found nothing. -/
def Stage.rejected : Stage → Runs → Bool
  | .lint, x => !x.lint.isEmpty && x.holes.isNone && x.approved.isNone && x.values.isNone &&
    x.refutation.isNone
  | .holes, x => x.lint.isEmpty && x.holes == some .rejected
  | .values, x => x.lint.isEmpty && x.holes == some .accepted && x.approved == some .accepted &&
    x.values == some .rejected
  | .refutation, x => x.lint.isEmpty &&
    x.holes == some .accepted && x.approved == some .rejected && x.refutation == some .rejected

/-- A case rejected at any stage is neither refuted nor surviving. -/
theorem Stage.rejected_outcome {s : Stage} {x : Runs} (h : s.rejected x = true) :
    outcome x ≠ .refuted ∧ outcome x ≠ .survived := by
  obtain ⟨l, hl, a, v, r⟩ := x
  cases s <;> simp only [Stage.rejected, Bool.and_eq_true, beq_iff_eq] at h <;>
    simp only [ne_eq, outcome_refuted_iff, outcome_survived_iff] <;> cases l <;> simp_all

/-- How a case was judged. -/
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

/-- A case met its expectation: a cheat case was rejected at its stage, any other case's outcome is
the one its claim expects. -/
def Result.ok (r : Result) : Bool :=
  match r.judged with
  | .invalid _ => false
  | .ran _ (some s) x => s.rejected x
  | .ran e none x => (Mutants.outcome x).meets e

/-- The verdict of a run over `cases`. -/
def passes (control : Run) (cases : List String) (rs : List Result) : Bool :=
  control == .accepted && !cases.isEmpty &&
  cases.all (fun c => rs.countP (·.name == c) == 1) &&
  rs.all (fun r => cases.contains r.name && r.ok)

/-- **The run passes exactly when** the control run is accepted, there is a case, every case is
judged exactly once, nothing else is judged, and every case meets its expectation. -/
theorem passes_iff {control : Run} {cases : List String} {rs : List Result} :
    passes control cases rs = true ↔
      control = .accepted ∧ cases ≠ [] ∧ (∀ c ∈ cases, rs.countP (·.name == c) = 1) ∧
        ∀ r ∈ rs, r.name ∈ cases ∧ r.ok = true := by
  simp only [passes, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true', List.isEmpty_eq_false_iff,
    List.all_eq_true, List.contains_iff_mem, and_assoc]

/-- In a passing run, a case that claims to break theorems, and is no cheat case, **passed the
lint**, has **the mutant's own holes** (the hole run accepted), **was rejected by the gate, and the
refutation of each theorem it names was accepted for those holes**. -/
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

/-- In a passing run, a known gap that is no cheat case **passed the lint**, has **the mutant's
own holes, the gate accepted it, and the gate's proofs are about those holes** (the values run
accepted). -/
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

/-- In a passing run, **a cheat case was rejected at the stage it names, and is counted neither as
refuted nor as surviving.** -/
theorem passes_rejects {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) :
    ∀ r ∈ rs, ∀ e s x, r.judged = .ran e (some s) x →
      s.rejected x = true ∧ outcome x ≠ .refuted ∧ outcome x ≠ .survived := by
  intro r hr e s x hj
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  simp only [Result.ok, hj] at hok
  exact ⟨hok, Stage.rejected_outcome hok⟩

/-- In a passing run, **the lint refused only cheat cases that expect it**, and nothing was built
for them. -/
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

/-- In a passing run, every case was judged, so no case was skipped or failed to set up. -/
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

/-- The cases whose mutant was refuted and names theorem `t`: the mutants that break it. A cheat
case is never one. -/
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
