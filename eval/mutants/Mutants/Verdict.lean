import Mutants.Manifest

/-!
# Outcomes and the run's verdict

Each mutant gets up to two sandboxed `lake comparator` runs:

1. **approved**: the approved Challenge and configuration (`core/Challenge/Resolver.lean`,
   `core/comparator.json`) with the real solution module, on the mutated core. For a bug the
   theorems see, this is rejected.
2. **refutation** (`breaks=` cases, after a rejection): the refutation Challenge
   (`Mutants.Challenge`) against a solution module the runner writes (`refutationSolution`). It
   imports every `Mitos.Impl` module of the mutated core and the case's `Refute.lean`. Accepted
   means each named theorem is proved false, with standard axioms only, for the mutated core's
   definitions. The comparator compares definition holes by type only, so the binding comes from
   the imports: a `Refute.lean` that declared its own `Mitos.Impl.impact`, say, would clash with
   the imported one and not build.

Before any mutant, a **control** run judges the unmutated core the same way as run 1; it must be
accepted, so a rejection in run 1 comes from the mutant and not from the workspace.

The run passes exactly when the control is accepted, there is at least one case, every case is
judged exactly once, and every case meets its expectation (`passes_iff`). With no known gap among
the cases, that means every mutant was rejected by the approved Challenge and a refutation of each
theorem it names was accepted (`passes_refuted`).
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

/-- The comparator runs of one case; a run that did not happen is `none`. -/
structure Runs where
  approved   : Run
  refutation : Option Run := none
  deriving Repr, DecidableEq

/-- What happened to one mutant. -/
inductive Outcome where
  /-- Rejected by the approved Challenge, and the refutation of every named theorem accepted. -/
  | refuted
  /-- Rejected by the approved Challenge, but no refutation accepted. -/
  | rejected
  /-- Accepted by the approved Challenge: the proofs still prove every theorem for the mutant. -/
  | survived
  /-- A comparator run gave no judgment. -/
  | failed
  /-- The case could not be set up: its manifest, its files, its edits or its refutation Challenge. -/
  | invalid
  deriving Repr, DecidableEq

/-- The outcome of a case's runs. -/
def outcome (x : Runs) : Outcome :=
  match x.approved, x.refutation with
  | .accepted, _ => .survived
  | .failed, _ => .failed
  | .rejected, some .accepted => .refuted
  | .rejected, some .failed => .failed
  | .rejected, _ => .rejected

theorem outcome_refuted_iff {x : Runs} :
    outcome x = .refuted ↔ x.approved = .rejected ∧ x.refutation = some .accepted := by
  obtain ⟨a, r⟩ := x
  cases a <;> rcases r with _ | (_ | _ | _) <;> simp [outcome]

theorem outcome_survived_iff {x : Runs} : outcome x = .survived ↔ x.approved = .accepted := by
  obtain ⟨a, r⟩ := x
  cases a <;> rcases r with _ | (_ | _ | _) <;> simp [outcome]

/-- Whether an outcome is the one the case expects. -/
def Outcome.meets : Outcome → Expect → Bool
  | .refuted, .breaks _ => true
  | .survived, .survives _ => true
  | _, _ => false

/-- How a case was judged. -/
inductive Judged where
  | invalid (why : String)
  | ran (expect : Expect) (runs : Runs)
  deriving Repr, DecidableEq

structure Result where
  name   : String
  judged : Judged
  deriving Repr, DecidableEq

def Result.outcome (r : Result) : Outcome :=
  match r.judged with
  | .invalid _ => .invalid
  | .ran _ x => Mutants.outcome x

def Result.ok (r : Result) : Bool :=
  match r.judged with
  | .invalid _ => false
  | .ran e x => (Mutants.outcome x).meets e

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

/-- In a passing run, a case that expects to break theorems was **rejected by the approved
Challenge, and the refutation of each theorem it names was accepted**. -/
theorem passes_refuted {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) :
    ∀ r ∈ rs, ∀ ts x, r.judged = .ran (.breaks ts) x →
      x.approved = .rejected ∧ x.refutation = some .accepted := by
  intro r hr ts x hj
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  simp only [Result.ok, hj] at hok
  have : outcome x = .refuted := by
    revert hok; cases outcome x <;> simp [Outcome.meets]
  exact outcome_refuted_iff.mp this

/-- In a passing run, every case was judged, so no case was skipped or failed to set up. -/
theorem passes_judged {control : Run} {cases : List String} {rs : List Result}
    (h : passes control cases rs = true) : ∀ r ∈ rs, ∃ e x, r.judged = .ran e x := by
  intro r hr
  have hok := ((passes_iff.mp h).2.2.2 r hr).2
  unfold Result.ok at hok
  split at hok
  · simp at hok
  · rename_i e x hj
    exact ⟨e, x, hj⟩

/-- The cases whose mutant was refuted and names theorem `t`: the mutants that break it. -/
def breakers (rs : List Result) (t : String) : List String :=
  rs.filterMap fun r =>
    match r.judged with
    | .ran (.breaks ts) x => if outcome x == .refuted && ts.contains t then some r.name else none
    | _ => none

theorem mem_breakers {rs : List Result} {t n : String} :
    n ∈ breakers rs t ↔ ∃ r ∈ rs, r.name = n ∧ ∃ ts x, r.judged = .ran (.breaks ts) x ∧ t ∈ ts ∧
      x.approved = .rejected ∧ x.refutation = some .accepted := by
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
