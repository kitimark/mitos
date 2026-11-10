namespace MitosGate.Accept

inductive Failure
  | illegalAxiom
  | missingConst
  | statement
  | definitionHole
  | kernelReject
  | importClash
  | noJudgment
  deriving DecidableEq

inductive Outcome
  /-- Exit code 0 and `Your solution is okay!`: everything built, the statements and definition holes
  match the Challenge's, only permitted axioms are used, and every kernel accepts. -/
  | ok
  | failed (why : Failure)
  deriving DecidableEq

/-- `decide` cannot evaluate `String.splitOn`, so the search stays on `List Char`. -/
private def occursIn (pat : List Char) : List Char → Bool
  | [] => pat.isEmpty
  | s@(_ :: rest) => pat.isPrefixOf s || occursIn pat rest

private theorem occursIn_eq_isInfixOf (pat s : List Char) :
    occursIn pat s = pat.isInfixOf_internal s := by
  induction s with
  | nil => cases pat <;> rfl
  | cons _ rest ih => simp [occursIn, List.isInfixOf_internal, ih]

private theorem occursIn_iff {pat s : List Char} : occursIn pat s = true ↔ pat <:+: s := by
  rw [occursIn_eq_isInfixOf, List.isInfixOf_internal_iff_isInfix]

private inductive Marker
  | text (s : String)
  | allOf (parts : List String)

private def Marker.holds (out : List Char) : Marker → Bool
  | .text s => occursIn s.toList out
  | .allOf parts => parts.all fun s => occursIn s.toList out

private structure MarkerRule where
  failure : Failure
  markers : List Marker

private def rules : List MarkerRule :=
  [ { failure := .illegalAxiom
      markers := [.text "Illegal axiom"] },
    { failure := .missingConst
      markers := [.text "not found in environment", .text "Const not found in solution"] },
    { failure := .statement
      markers :=
        [.text "Const not found in challenge",
          .text "Const does not match between challenge and target",
          .text "Challenge and solution constant kind don't match",
          .text "Challenge and solution theorem statement do not match"] },
    { failure := .definitionHole
      markers :=
        [.text "Challenge constant is not a definition",
          .text "Solution constant is not a definition"] },
    { failure := .kernelReject
      markers := [.allOf ["kernel", "reject"]] },
    { failure := .importClash
      markers := [.text "environment already contains"] } ]

private theorem rules_cover :
    (rules.map (·.failure)).Nodup ∧
      ∀ f, f ∈ rules.map (·.failure) ↔ f ≠ .noJudgment := by
  refine ⟨by decide, fun f => ?_⟩
  cases f <;> decide

private def classify (out : String) : Failure :=
  match rules.find? fun r => r.markers.any (·.holds out.toList) with
  | some r => r.failure
  | none => .noJudgment

def Outcome.parse (code : UInt32) (out : String) : Outcome :=
  if code == 0 && occursIn "Your solution is okay!".toList out.toList then .ok
  else .failed (classify out)

theorem Outcome.parse_eq_ok_iff {code : UInt32} {out : String} :
    Outcome.parse code out = .ok ↔
      code = 0 ∧ "Your solution is okay!".toList <:+: out.toList := by
  unfold Outcome.parse
  have hcond :
      (code == 0 && occursIn "Your solution is okay!".toList out.toList) = true ↔
        code = 0 ∧ "Your solution is okay!".toList <:+: out.toList := by
    rw [Bool.and_eq_true, beq_iff_eq, occursIn_iff]
  generalize hflag :
    (code == 0 && occursIn "Your solution is okay!".toList out.toList) = flag
  cases flag with
  | false =>
    simp
    intro hc hin
    have ht := hcond.mpr ⟨hc, hin⟩
    rw [hflag] at ht
    cases ht
  | true =>
    simp
    exact hcond.mp hflag

theorem Outcome.parse_ok {code : UInt32} {out : String} (h : Outcome.parse code out = .ok) :
    code = 0 :=
  (Outcome.parse_eq_ok_iff.mp h).1

/-! Each outcome, from the last lines of a real run as the gate prints them, without its `  | `
prefix. Unless its comment says otherwise, the text is from the named log in CI's `cheat-logs`
artifact for main at c79e03f. The exit codes are the ones Lake's `CLI/Check.lean` returns: 0 for an
accepted run, 1 for any error once the run has started. -/

-- The `cd core && lake comparator --paranoid` step of the same CI run: the gate prints no
-- comparator output for an accepted run.
example : Outcome.parse 0 "Running con-ron kernel on solution
con-ron: accepted 1885 declarations (--verified)
con-ron kernel accepts the solution
Running Lean default kernel on solution
Lean default kernel accepts the solution
Your solution is okay!
" = .ok := by decide +kernel

-- `admit.comparator.log`.
example : Outcome.parse 1 "warning: Plugins/ToyRequire.lean:38:8: declaration uses `sorry`
Build completed successfully (11 jobs).
error: Illegal axiom detected: 'sorryAx'
" = .failed .illegalAxiom := by decide +kernel

-- `missing_obligation.full.log`.
example : Outcome.parse 1 "Build completed successfully (11 jobs).
PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant ToyRequire.complete not found in environment.
error: Child exited with 134
" = .failed .missingConst := by decide +kernel

-- `weakened_statement.full.log`.
example : Outcome.parse 1 "Building Plugins.ToyRequire
Build completed successfully (11 jobs).
error: Challenge and solution theorem statement do not match: 'ToyRequire.complete'
" = .failed .statement := by decide +kernel

-- `env_hack.comparator.log`.
example : Outcome.parse 1 "Running Lean default kernel on solution
Lean default kernel rejected the solution
error: Lean default exited with 1
" = .failed .kernelReject := by decide +kernel

example : Outcome.parse 1 "error: Models/ToyRequire/Adequacy.lean:1:0: import Models.ToyRequire.Examples failed, environment already contains 'Models.ToyRequire.model.examples' from Models.ToyRequire
Some required targets logged failures:
- Models.ToyRequire.Adequacy
error: build failed
error: Child exited with 1
" = .failed .importClash := by decide +kernel

-- `escaped_sorry.comparator.log`.
example : Outcome.parse 1 "error: Plugins/ToyRequire.lean:39:8: Unknown identifier `«sorry»`
Some required targets logged failures:
- Plugins.ToyRequire
error: build failed
error: Child exited with 1
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 0 "Build completed successfully (11 jobs).
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 "Your solution is okay!
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 0 "error: Illegal axiom detected: 'sorryAx'
" = .failed .illegalAxiom := by decide +kernel

example : Outcome.parse 0 "error: Illegal axiom detected: 'sorryAx'
Your solution is okay!
" = .ok := by decide +kernel

example : Outcome.parse 1 "Illegal axiom
not found in environment
" = .failed .illegalAxiom := by decide +kernel

example : Outcome.parse 1 "not found in environment
Challenge and solution theorem statement do not match
" = .failed .missingConst := by decide +kernel

example : Outcome.parse 1 "Challenge and solution theorem statement do not match
kernel rejected the solution
" = .failed .statement := by decide +kernel

example : Outcome.parse 1 "kernel rejected the solution
environment already contains
" = .failed .kernelReject := by decide +kernel

end MitosGate.Accept
