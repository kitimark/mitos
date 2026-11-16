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

/-- What `lake comparator` printed, each stream on its own. `lake build` writes its log, which holds
every message Lean prints about the plugin's source, to stdout (`mkBuildConfig (out := .stdout)` in
Lake's `CLI/Main.lean`), and the comparator writes its reports to stderr. -/
structure Streams where
  stdout : String
  stderr : String

def Streams.toList (out : Streams) : List Char := out.stdout.toList ++ out.stderr.toList

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

/-!
`lake comparator` (Lake's `CLI/Check.lean` at v4.35.0, which `lean-toolchain` pins) ends a judgment
that does not pass in one handler: it prints `error: ` and the reason to stderr and returns 1. It
prints that line after every sandboxed child it started has exited, and `bwrap` gives each child
its own PID namespace, whose processes die with it, so nothing the plugin started can write after
the line. -/

private inductive Quote
  | colon
  | space

/-- A report of the comparator's after its `error: `, as Lake's `Check/Compare.lean`,
`Check/Axioms.lean` and `CLI/Check.lean` print it. -/
private inductive Report
  | names (text : String) (quote : Quote)
  | exits (kernel : String)

private def Report.lead : Report → List Char
  | .names text .colon => text.toList ++ ": '".toList
  | .names text .space => text.toList ++ " '".toList
  | .exits kernel => kernel.toList ++ " exited with ".toList

private def Report.rest : Report → List Char → Bool
  | .names _ _, rest => 2 ≤ rest.length && rest.getLast? == some '\''
  | .exits _, rest => !rest.isEmpty && rest.all Char.isDigit

private def Report.matches (line : List Char) (r : Report) : Bool :=
  r.lead.isPrefixOf line && r.rest (line.drop r.lead.length)

private structure ReportRule where
  failure : Failure
  reports : List Report

/-- The kernels Lake's comparator runs: with `--paranoid` its bundled ones, then always Lean's
own. -/
def Outcome.kernels : List String :=
  ["Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron", "Lean default"]

private def rules : List ReportRule :=
  [ { failure := .illegalAxiom
      reports := [.names "Illegal axiom detected" .colon] },
    { failure := .missingConst
      reports :=
        [.names "Const not found in solution" .colon,
          .names "Const not found in solution" .space] },
    { failure := .statement
      reports :=
        [.names "Const not found in challenge" .colon, .names "Const not found in challenge" .space,
          .names "Const does not match between challenge and target" .space,
          .names "Challenge and solution constant kind don't match" .colon,
          .names "Challenge and solution theorem statement do not match" .colon] },
    { failure := .definitionHole
      reports :=
        [.names "Challenge constant is not a definition" .colon,
          .names "Solution constant is not a definition" .colon] },
    { failure := .kernelReject
      reports := Outcome.kernels.map .exits } ]

private theorem rules_cover :
    (rules.map (·.failure)).Nodup ∧
      ∀ f, f ∈ rules.map (·.failure) ↔ f ≠ .importClash ∧ f ≠ .noJudgment := by
  refine ⟨by decide, fun f => ?_⟩
  cases f <;> decide

private theorem leads_apart :
    ∀ r₁ ∈ rules, ∀ r₂ ∈ rules, ∀ a ∈ r₁.reports, ∀ b ∈ r₂.reports,
      a.lead <+: b.lead → r₁.failure = r₂.failure := by
  decide +kernel

private theorem Report.lead_prefix {line : List Char} {r : Report} (h : r.matches line = true) :
    r.lead <+: line := by
  simp only [Report.matches, Bool.and_eq_true] at h
  exact List.isPrefixOf_iff_prefix.1 h.1

private theorem rules_apart {line : List Char} {r₁ r₂ : ReportRule} (h₁ : r₁ ∈ rules)
    (h₂ : r₂ ∈ rules) (m₁ : r₁.reports.any (·.matches line) = true)
    (m₂ : r₂.reports.any (·.matches line) = true) :
    r₁.failure = r₂.failure := by
  obtain ⟨a, ha, hma⟩ := List.any_eq_true.1 m₁
  obtain ⟨b, hb, hmb⟩ := List.any_eq_true.1 m₂
  rcases List.prefix_or_prefix_of_prefix (Report.lead_prefix hma) (Report.lead_prefix hmb) with
    hab | hba
  · exact leads_apart r₁ h₁ r₂ h₂ a ha b hb hab
  · exact (leads_apart r₂ h₂ r₁ h₁ b hb a ha hba).symm

/-- The failure the comparator reports in `line`, or `none` when `line` is not one of its
reports. -/
def Outcome.report (line : List Char) : Option Failure :=
  match "error: ".toList.isPrefixOf? line with
  | some rest => (rules.find? fun r => r.reports.any (·.matches rest)).map (·.failure)
  | none => none

/-- The last line of `out`, without its newline. -/
def Outcome.lastLine (out : List Char) : List Char :=
  ((dropNewline out.reverse).takeWhile (· != '\n')).reverse
where
  dropNewline : List Char → List Char
    | '\n' :: r => r
    | r => r

theorem Outcome.lastLine_append {pre l : List Char} (hl : '\n' ∉ l) :
    lastLine (pre ++ '\n' :: (l ++ ['\n'])) = l := by
  have hp : ∀ a ∈ l.reverse, (a != '\n') = true := by
    intro a ha
    have : a ≠ '\n' := fun h => hl (h ▸ List.mem_reverse.1 ha)
    simpa using this
  simp [lastLine, lastLine.dropNewline, List.takeWhile_append_of_pos hp]

theorem Outcome.lastLine_of_line {pre l : List Char} (hpre : pre = [] ∨ pre.getLast? = some '\n')
    (hl : '\n' ∉ l) : lastLine (pre ++ l ++ ['\n']) = l := by
  rcases hpre with rfl | h
  · have hp : ∀ a ∈ l.reverse, (a != '\n') = true := by
      intro a ha
      have : a ≠ '\n' := fun h => hl (h ▸ List.mem_reverse.1 ha)
      simpa using this
    have ht : l.reverse.takeWhile (· != '\n') = l.reverse := by
      simpa using List.takeWhile_append_of_pos (l₂ := []) hp
    simp [lastLine, lastLine.dropNewline, ht]
  · obtain ⟨p, rfl⟩ := List.getLast?_eq_some_iff.1 h
    simpa using lastLine_append (pre := p) hl

private def linesFromLast (s : List Char) : List (List Char) :=
  go (Outcome.lastLine.dropNewline s.reverse) [] []
where
  go : List Char → List Char → List (List Char) → List (List Char)
    | [], line, acc => (line :: acc).reverse
    | c :: rest, line, acc =>
      if c == '\n' then go rest [] (line :: acc) else go rest (c :: line) acc

private def frame (line : List Char) : Bool :=
  occursIn " [0x".toList line && line.getLast? == some ']'

/-- The exporter's panic for a constant the comparator asked it to export and the module does not
declare. -/
private def exportPanic (line : List Char) : Bool :=
  "PANIC at LeanExport.dumpConstant ".toList.isPrefixOf line &&
    " not found in environment.".toList.isSuffixOf line

/-- The comparator prints the exporter's stderr once the exporter has exited, just before its last
line. Here that stderr ends with the panic, then the backtrace Lean prints after it. -/
private def panicBefore (err : List Char) : Bool :=
  match (linesFromLast err).tail.dropWhile frame with
  | line :: rest =>
    exportPanic line || (line == "backtrace:".toList && (rest.head?.map exportPanic).getD false)
  | [] => false

private def importClash (line : List Char) : Bool :=
  "error: ".toList.isPrefixOf line && occursIn ", environment already contains '".toList line

/-- The comparator's last line when a sandboxed child exits with `code`. -/
def Outcome.childExited (code : String) : List Char :=
  "error: Child exited with ".toList ++ code.toList

private def classify (out : Streams) : Failure :=
  let last := Outcome.lastLine out.stderr.toList
  match Outcome.report last with
  | some f => f
  | none =>
    if last == Outcome.childExited "134" && panicBefore out.stderr.toList then .missingConst
    else if last == Outcome.childExited "1" && (linesFromLast out.stdout.toList).any importClash
    then .importClash
    else .noJudgment

def Outcome.parse (code : UInt32) (out : Streams) : Outcome :=
  if code == 0 && occursIn "Your solution is okay!".toList out.toList then .ok
  else if code == 1 then .failed (classify out)
  else .failed .noJudgment

theorem Outcome.parse_eq_ok_iff {code : UInt32} {out : Streams} :
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
    simp only [Bool.false_eq_true, ite_false]
    constructor
    · intro h
      split at h <;> cases h
    · intro hin
      have ht := hcond.mpr hin
      rw [hflag] at ht
      cases ht
  | true =>
    simp
    exact hcond.mp hflag

theorem Outcome.parse_ok {code : UInt32} {out : Streams} (h : Outcome.parse code out = .ok) :
    code = 0 :=
  (Outcome.parse_eq_ok_iff.mp h).1

private theorem Outcome.parse_one (out : Streams) :
    Outcome.parse 1 out = .failed (classify out) := by
  simp [Outcome.parse]

theorem Outcome.parse_of_report {out : Streams} {pre l : List Char} {f : Failure}
    (herr : out.stderr.toList = pre ++ l ++ ['\n']) (hpre : pre = [] ∨ pre.getLast? = some '\n')
    (hl : '\n' ∉ l) (hr : report l = some f) :
    Outcome.parse 1 out = .failed f := by
  have hlast : lastLine out.stderr.toList = l := by
    rw [herr]
    exact lastLine_of_line hpre hl
  simp [Outcome.parse_one, classify, hlast, hr]

theorem Outcome.parse_failed_build {out : Streams} (t : List Char)
    (herr : out.stderr.toList = t ++ "\nerror: Child exited with 1\n".toList) :
    Outcome.parse 1 out = .failed .noJudgment ∨ Outcome.parse 1 out = .failed .importClash := by
  have hlast : lastLine out.stderr.toList = childExited "1" := by
    have hsplit : "\nerror: Child exited with 1\n".toList =
        '\n' :: ("error: Child exited with 1".toList ++ ['\n']) := by decide
    rw [herr, hsplit, lastLine_append (by decide)]
    decide
  have hr : report (childExited "1") = none := by decide
  have h134 : (childExited "1" == childExited "134") = false := by decide
  by_cases hc : (linesFromLast out.stdout.toList).any importClash = true
  · exact Or.inr (by simp [Outcome.parse_one, classify, hlast, hr, h134, hc])
  · exact Or.inl (by simp [Outcome.parse_one, classify, hlast, hr, h134, hc])

private theorem classify_stdout (s₁ s₂ e : String) :
    classify ⟨s₁, e⟩ = classify ⟨s₂, e⟩ ∨
      (classify ⟨s₁, e⟩ = .noJudgment ∨ classify ⟨s₁, e⟩ = .importClash) ∧
        (classify ⟨s₂, e⟩ = .noJudgment ∨ classify ⟨s₂, e⟩ = .importClash) := by
  simp only [classify]
  cases Outcome.report (Outcome.lastLine e.toList) with
  | some f => simp
  | none =>
    by_cases ha : (Outcome.lastLine e.toList == Outcome.childExited "134" &&
        panicBefore e.toList) = true
    · simp only [ha, ↓reduceIte]
      simp
    · simp only [ha, Bool.false_eq_true, ↓reduceIte]
      refine Or.inr ⟨?_, ?_⟩ <;> split <;> simp

theorem Outcome.parse_stdout {code : UInt32} {s₁ s₂ e : String} {f₁ f₂ : Failure}
    (h₁ : Outcome.parse code ⟨s₁, e⟩ = .failed f₁) (h₂ : Outcome.parse code ⟨s₂, e⟩ = .failed f₂) :
    f₁ = f₂ ∨ (f₁ = .noJudgment ∨ f₁ = .importClash) ∧ (f₂ = .noJudgment ∨ f₂ = .importClash) := by
  by_cases h1 : code = 1
  · subst h1
    rw [Outcome.parse_one] at h₁ h₂
    cases h₁
    cases h₂
    exact classify_stdout s₁ s₂ e
  · have hn : ∀ {s f}, Outcome.parse code ⟨s, e⟩ = .failed f → f = .noJudgment := by
      intro s f h
      unfold Outcome.parse at h
      split at h
      · cases h
      · simp only [beq_iff_eq, h1, ↓reduceIte] at h
        exact (Outcome.failed.inj h).symm
    exact Or.inl ((hn h₁).trans (hn h₂).symm)

theorem Outcome.parse_judged {code : UInt32} {out : Streams} {f : Failure}
    (h : Outcome.parse code out = .failed f) (hf : f ≠ .noJudgment) :
    code = 1 ∧ (report (lastLine out.stderr.toList) = some f ∨
      report (lastLine out.stderr.toList) = none ∧
        (lastLine out.stderr.toList = childExited "134" ∧ f = .missingConst ∨
          lastLine out.stderr.toList = childExited "1" ∧ f = .importClash)) := by
  unfold Outcome.parse at h
  by_cases h0 : (code == 0 && occursIn "Your solution is okay!".toList out.toList) = true
  · simp only [h0, ↓reduceIte] at h
    cases h
  simp only [h0, Bool.false_eq_true, ↓reduceIte] at h
  by_cases h1 : (code == 1) = true
  · simp only [h1, ↓reduceIte] at h
    refine ⟨beq_iff_eq.1 h1, ?_⟩
    have h' : classify out = f := Outcome.failed.inj h
    unfold classify at h'
    dsimp only at h'
    split at h'
    · rename_i g hg
      exact Or.inl (hg.trans (congrArg some h'))
    · rename_i hg
      refine Or.inr ⟨hg, ?_⟩
      by_cases ha : (lastLine out.stderr.toList == childExited "134" &&
          panicBefore out.stderr.toList) = true
      · simp only [ha, ↓reduceIte] at h'
        exact Or.inl ⟨beq_iff_eq.1 (Bool.and_eq_true _ _ ▸ ha).1, h'.symm⟩
      simp only [ha, Bool.false_eq_true, ↓reduceIte] at h'
      by_cases hb : (lastLine out.stderr.toList == childExited "1" &&
          (linesFromLast out.stdout.toList).any importClash) = true
      · simp only [hb, ↓reduceIte] at h'
        exact Or.inr ⟨beq_iff_eq.1 (Bool.and_eq_true _ _ ▸ hb).1, h'.symm⟩
      simp only [hb, Bool.false_eq_true, ↓reduceIte] at h'
      exact absurd h'.symm hf
  · simp only [h1, Bool.false_eq_true, ↓reduceIte] at h
    exact absurd (Outcome.failed.inj h).symm hf

/-! Each outcome, from the last lines of a run as the gate prints them, stdout first and then
stderr, each line after `  | `. An example whose comment names a log takes its text from that log
in CI's `cheat-logs` artifact for main at c79e03f, unless the comment says otherwise. The other
examples are not from a cheat log. The exit codes are the ones Lake's `CLI/Check.lean` returns: 0
for an accepted run, 1 for any error once the run has started. -/

-- The `cd core && lake comparator --paranoid` step of the same CI run: the gate prints no
-- comparator output for an accepted run.
example : Outcome.parse 0 ⟨"Running con-ron kernel on solution
con-ron: accepted 1885 declarations (--verified)
con-ron kernel accepts the solution
Running Lean default kernel on solution
Lean default kernel accepts the solution
Your solution is okay!
", ""⟩ = .ok := by decide +kernel

-- `admit.comparator.log`.
example : Outcome.parse 1 ⟨"warning: Plugins/ToyRequire.lean:38:8: declaration uses `sorry`
Build completed successfully (11 jobs).
", "error: Illegal axiom detected: 'sorryAx'
"⟩ = .failed .illegalAxiom := by decide +kernel

-- `missing_obligation.full.log`.
example : Outcome.parse 1 ⟨"Build completed successfully (11 jobs).
", "PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant ToyRequire.complete not found in environment.
error: Child exited with 134
"⟩ = .failed .missingConst := by decide +kernel

-- The comparator's own output in that case's judging directory, from a local run, with all but
-- one frame of the backtrace cut.
example : Outcome.parse 1 ⟨"", "PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant ToyRequire.complete not found in environment.
backtrace:
/lib/x86_64-linux-gnu/libc.so.6(+0x129ecc) [0x7f9eabb29ecc]
error: Child exited with 134
"⟩ = .failed .missingConst := by decide +kernel

-- `weakened_statement.full.log`.
example : Outcome.parse 1 ⟨"Building Plugins.ToyRequire
Build completed successfully (11 jobs).
", "error: Challenge and solution theorem statement do not match: 'ToyRequire.complete'
"⟩ = .failed .statement := by decide +kernel

-- `env_hack.comparator.log`.
example : Outcome.parse 1 ⟨"Running Lean default kernel on solution
Lean default kernel rejected the solution
", "error: Lean default exited with 1
"⟩ = .failed .kernelReject := by decide +kernel

example : Outcome.parse 1 ⟨"error: Models/ToyRequire/Adequacy.lean:1:0: import Models.ToyRequire.Examples failed, environment already contains 'Models.ToyRequire.model.examples' from Models.ToyRequire
", "error: build failed
error: Child exited with 1
"⟩ = .failed .importClash := by decide +kernel

example (t : List Char) (out : Streams)
    (h : out.stderr.toList = t ++ "\nerror: Lean default exited with 1\n".toList) :
    Outcome.parse 1 out = .failed .kernelReject :=
  Outcome.parse_of_report (pre := t ++ ['\n']) (l := "error: Lean default exited with 1".toList)
    (by rw [h]; simp only [List.append_assoc]; exact congrArg (t ++ ·) (by decide))
    (Or.inr (by simp)) (by decide) (by decide +kernel)

-- `escaped_sorry.comparator.log`.
example : Outcome.parse 1 ⟨"error: Plugins/ToyRequire.lean:39:8: Unknown identifier `«sorry»`
Some required targets logged failures:
- Plugins.ToyRequire
", "error: build failed
error: Child exited with 1
"⟩ = .failed .noJudgment := by decide +kernel

/-! Each text is from the case's `full.log` in a local run, with the lines that do not bear on the
outcome cut. -/

-- `print_kernel_reject`.
example : Outcome.parse 1 ⟨"Lean default kernel rejected the solution
error: Lean default exited with 1
error: Plugins/ToyRequire.lean:42:50: Unknown identifier `kernel_reject`
", "error: build failed
error: Child exited with 1
"⟩ = .failed .noJudgment := by decide +kernel

-- `print_illegal_axiom`.
example : Outcome.parse 1 ⟨"error: Illegal axiom detected: 'sorryAx'
Build completed successfully (13 jobs).
", "error: Challenge and solution theorem statement do not match: 'ToyRequire.complete'
"⟩ = .failed .statement := by decide +kernel

-- `print_missing_const`.
example : Outcome.parse 1 ⟨"info: Plugins/ToyRequire.lean:38:0: PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant ToyRequire.complete not found in environment.
error: Child exited with 134
", "error: build failed
error: Child exited with 1
"⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 ⟨"error: Lean default exited with 1
", ""⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 ⟨"", "Lean default kernel rejected the solution: error: Lean default exited with 1
"⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 ⟨"", "error: Lean default exited with 1 and more
"⟩ = .failed .noJudgment := by decide +kernel

/-! Exit code 0 always comes with `Your solution is okay!`, and 2 means that the run could not
start. -/

example : Outcome.parse 0 ⟨"Build completed successfully (11 jobs).
", ""⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 0 ⟨"", "error: Illegal axiom detected: 'sorryAx'
"⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 2 ⟨"", "error: Illegal axiom detected: 'sorryAx'
"⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 ⟨"Your solution is okay!
", ""⟩ = .failed .noJudgment := by decide +kernel

example : Outcome.parse 0 ⟨"Your solution is okay!
", "error: Illegal axiom detected: 'sorryAx'
"⟩ = .ok := by decide +kernel

end MitosGate.Accept
