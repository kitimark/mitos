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

/-! ## The comparator's last line

`lake comparator` (Lake's `CLI/Check.lean` at v4.35.0, which `lean-toolchain` pins) ends a judgment
that does not pass in one handler: it prints `error: ` and the reason to stderr and returns 1. It
prints that line after every sandboxed child it started has exited, and `bwrap` gives each child
its own PID namespace, whose processes die with it, so nothing the plugin started can write after
the line. The gate's `run` returns stdout and then stderr, so the line is the last of the output.

Everything before it can hold text the plugin chose. The build log holds every message Lean prints
about the plugin's source: gate 1 allows `#print`, which prints any string, and an error echoes the
identifier it names. The exporter and the kernels report on the plugin's declarations too. So a
failure is read from the last line alone, and only when the whole line is one of the comparator's
reports. -/

/-- A report of the comparator's after its `error: `, as Lake's `Check/Compare.lean`,
`Check/Axioms.lean` and `CLI/Check.lean` print it. -/
private inductive Report
  /-- `lead`, which ends with the opening quote, then a constant's name and `'`. -/
  | names (lead : String)
  /-- A kernel's name, ` exited with ` and the kernel's exit code. -/
  | exits (kernel : String)

/-- A kernel decodes a string literal in time quadratic in its length, so the pieces stay apart. -/
private def Report.lead : Report → List Char
  | .names lead => lead.toList
  | .exits kernel => kernel.toList ++ " exited with ".toList

private def Report.rest : Report → List Char → Bool
  | .names _, rest => 2 ≤ rest.length && rest.getLast? == some '\''
  | .exits _, rest => !rest.isEmpty && rest.all Char.isDigit

private def Report.matches (line : List Char) (r : Report) : Bool :=
  r.lead.isPrefixOf line && r.rest (line.drop r.lead.length)

private structure ReportRule where
  failure : Failure
  reports : List Report

/-- The kernels `--paranoid` adds, then Lean's own, which always runs. The gate's configurations
name no other kernel. -/
private def kernels : List String :=
  ["Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron", "Lean default"]

private def rules : List ReportRule :=
  [ { failure := .illegalAxiom
      reports := [.names "Illegal axiom detected: '"] },
    { failure := .missingConst
      reports :=
        [.names "Const not found in solution: '", .names "Const not found in solution '"] },
    { failure := .statement
      reports :=
        [.names "Const not found in challenge: '", .names "Const not found in challenge '",
          .names "Const does not match between challenge and target '",
          .names "Challenge and solution constant kind don't match: '",
          .names "Challenge and solution theorem statement do not match: '"] },
    { failure := .definitionHole
      reports :=
        [.names "Challenge constant is not a definition: '",
          .names "Solution constant is not a definition: '"] },
    { failure := .kernelReject
      reports := kernels.map .exits } ]

private theorem rules_cover :
    (rules.map (·.failure)).Nodup ∧
      ∀ f, f ∈ rules.map (·.failure) ↔ f ≠ .importClash ∧ f ≠ .noJudgment := by
  refine ⟨by decide, fun f => ?_⟩
  cases f <;> decide

/-- No report's lead is a prefix of another rule's, so a line matches at most one rule and the
order of `rules` decides nothing. -/
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

/-- The lines of the text whose reverse is `r`, from the last, each without its newline. -/
private def revLines (r : List Char) : List (List Char) :=
  go r [] []
where
  go : List Char → List Char → List (List Char) → List (List Char)
    | [], line, acc => (line :: acc).reverse
    | c :: rest, line, acc =>
      if c == '\n' then go rest [] (line :: acc) else go rest (c :: line) acc

/-- The lines of `out` before its last line, from the last. -/
private def linesBefore (out : List Char) : List (List Char) :=
  revLines (((Outcome.lastLine.dropNewline out.reverse).dropWhile (· != '\n')).drop 1)

/-- A frame of a panic's backtrace: `<binary>(<symbol>+<offset>) [<address>]`. -/
private def frame (line : List Char) : Bool :=
  occursIn " [0x".toList line && line.getLast? == some ']'

/-- The exporter's panic for a constant the comparator asked it to export and the module does not
declare. -/
private def exportPanic (line : List Char) : Bool :=
  "PANIC at LeanExport.dumpConstant ".toList.isPrefixOf line &&
    " not found in environment.".toList.isSuffixOf line

/-- The comparator prints the exporter's stderr once the exporter has exited, just before its last
line. Here that stderr ends with the panic, then the backtrace Lean prints after it. -/
private def panicBefore (out : List Char) : Bool :=
  match (linesBefore out).dropWhile frame with
  | line :: rest =>
    exportPanic line || (line == "backtrace:".toList && (rest.head?.map exportPanic).getD false)
  | [] => false

/-- Lean's error when two modules that a module imports declare one name. -/
private def importClash (line : List Char) : Bool :=
  "error: ".toList.isPrefixOf line && occursIn ", environment already contains '".toList line

/-- The comparator's last line when a sandboxed child exits with `code`. -/
def Outcome.childExited (code : String) : List Char :=
  "error: Child exited with ".toList ++ code.toList

/-- The last line decides, when it is one of the comparator's reports. When it says only that a
child failed, that child's output may name the failure:
- exit code 134, the exporter's abort, after its panic for a constant the module does not declare;
- exit code 1, a failed `lake build`, whose log holds Lean's error for a name declared twice. In the
  plugin's run that log holds the plugin's text too, but this only chooses between `importClash`
  and `noJudgment`, which `pluginFailure` reports at one gate. Gate 6's runs build no plugin
  source. -/
private def classify (out : List Char) : Failure :=
  let last := Outcome.lastLine out
  match Outcome.report last with
  | some f => f
  | none =>
    if last == Outcome.childExited "134" && panicBefore out then .missingConst
    else if last == Outcome.childExited "1" && (revLines out.reverse).any importClash then
      .importClash
    else .noJudgment

def Outcome.parse (code : UInt32) (out : String) : Outcome :=
  if code == 0 && occursIn "Your solution is okay!".toList out.toList then .ok
  else if code == 1 then .failed (classify out.toList)
  else .failed .noJudgment

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

theorem Outcome.parse_ok {code : UInt32} {out : String} (h : Outcome.parse code out = .ok) :
    code = 0 :=
  (Outcome.parse_eq_ok_iff.mp h).1

/-- A report in the comparator's last line decides the failure, whatever the output holds before
it. -/
theorem Outcome.parse_of_report {out : String} {pre l : List Char} {f : Failure}
    (hout : out.toList = pre ++ '\n' :: (l ++ ['\n'])) (hl : '\n' ∉ l) (hr : report l = some f) :
    Outcome.parse 1 out = .failed f := by
  simp [Outcome.parse, classify, hout, lastLine_append hl, hr]

/-- A failed build, which the comparator reports as `error: Child exited with 1`, is read as no
judgment or as an import clash, which the plugin's run reports at the same gate, whatever text the
plugin printed before that line. -/
theorem Outcome.parse_failed_build {out : String} (t : List Char)
    (hout : out.toList = t ++ "\nerror: Child exited with 1\n".toList) :
    Outcome.parse 1 out = .failed .noJudgment ∨ Outcome.parse 1 out = .failed .importClash := by
  have hlast : lastLine out.toList = childExited "1" := by
    have hsplit : "\nerror: Child exited with 1\n".toList =
        '\n' :: ("error: Child exited with 1".toList ++ ['\n']) := by decide
    rw [hout, hsplit, lastLine_append (by decide)]
    decide
  have hr : report (childExited "1") = none := by decide
  have h134 : (childExited "1" == childExited "134") = false := by decide
  by_cases hc : (revLines out.toList.reverse).any importClash = true
  · exact Or.inr (by simp [Outcome.parse, classify, hlast, hr, h134, hc])
  · exact Or.inl (by simp [Outcome.parse, classify, hlast, hr, h134, hc])

/-- Every failure but `noJudgment` needs exit code 1, the code of the comparator's handler. It is
the report in the last line, or, when that line says only that a child failed, a missing constant
after exit code 134 or an import clash after exit code 1. -/
theorem Outcome.parse_judged {code : UInt32} {out : String} {f : Failure}
    (h : Outcome.parse code out = .failed f) (hf : f ≠ .noJudgment) :
    code = 1 ∧ (report (lastLine out.toList) = some f ∨
      report (lastLine out.toList) = none ∧
        (lastLine out.toList = childExited "134" ∧ f = .missingConst ∨
          lastLine out.toList = childExited "1" ∧ f = .importClash)) := by
  unfold Outcome.parse at h
  by_cases h0 : (code == 0 && occursIn "Your solution is okay!".toList out.toList) = true
  · simp only [h0, ↓reduceIte] at h
    cases h
  simp only [h0, Bool.false_eq_true, ↓reduceIte] at h
  by_cases h1 : (code == 1) = true
  · simp only [h1, ↓reduceIte] at h
    refine ⟨beq_iff_eq.1 h1, ?_⟩
    have h' : classify out.toList = f := Outcome.failed.inj h
    unfold classify at h'
    dsimp only at h'
    split at h'
    · rename_i g hg
      exact Or.inl (hg.trans (congrArg some h'))
    · rename_i hg
      refine Or.inr ⟨hg, ?_⟩
      by_cases ha : (lastLine out.toList == childExited "134" && panicBefore out.toList) = true
      · simp only [ha, ↓reduceIte] at h'
        exact Or.inl ⟨beq_iff_eq.1 (Bool.and_eq_true _ _ ▸ ha).1, h'.symm⟩
      simp only [ha, Bool.false_eq_true, ↓reduceIte] at h'
      by_cases hb : (lastLine out.toList == childExited "1" &&
          (revLines out.toList.reverse).any importClash) = true
      · simp only [hb, ↓reduceIte] at h'
        exact Or.inr ⟨beq_iff_eq.1 (Bool.and_eq_true _ _ ▸ hb).1, h'.symm⟩
      simp only [hb, Bool.false_eq_true, ↓reduceIte] at h'
      exact absurd h'.symm hf
  · simp only [h1, Bool.false_eq_true, ↓reduceIte] at h
    exact absurd (Outcome.failed.inj h).symm hf

/-! Each outcome, from the last lines of a run as the gate prints them, without its `  | ` prefix.
An example whose comment names a log takes its text from that log in CI's `cheat-logs` artifact
for main at c79e03f, unless the comment says otherwise. The other examples are not from a cheat
log. The exit codes are the ones Lake's `CLI/Check.lean` returns: 0 for an accepted run, 1 for any
error once the run has started. -/

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

-- The comparator's own output in that case's judging directory, from a local run, with all but
-- one frame of the backtrace cut. The gate's log leaves the backtrace out (`comparatorTail`).
example : Outcome.parse 1 "PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant ToyRequire.complete not found in environment.
backtrace:
/lib/x86_64-linux-gnu/libc.so.6(+0x129ecc) [0x7f9eabb29ecc]
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

-- Lean's error when an adequacy module imports two modules that declare `model.examples`, without
-- the build's list of failed targets.
example : Outcome.parse 1 "error: Models/ToyRequire/Adequacy.lean:1:0: import Models.ToyRequire.Examples failed, environment already contains 'Models.ToyRequire.model.examples' from Models.ToyRequire
error: build failed
error: Child exited with 1
" = .failed .importClash := by decide +kernel

-- A kernel's rejection, whatever the output holds before the comparator's last line.
example (t : List Char) (out : String)
    (h : out.toList = t ++ "\nerror: Lean default exited with 1\n".toList) :
    Outcome.parse 1 out = .failed .kernelReject :=
  Outcome.parse_of_report (l := "error: Lean default exited with 1".toList)
    (by rw [h]; exact congrArg (t ++ ·) (by decide)) (by decide) (by decide +kernel)

-- `escaped_sorry.comparator.log`.
example : Outcome.parse 1 "error: Plugins/ToyRequire.lean:39:8: Unknown identifier `«sorry»`
Some required targets logged failures:
- Plugins.ToyRequire
error: build failed
error: Child exited with 1
" = .failed .noJudgment := by decide +kernel

/-! Text the plugin prints comes before the comparator's last line. Each text is from the case's
`full.log` in a local run, with the lines that do not bear on the outcome cut. A kernel decodes a
long string literal slowly, so the texts stay short. -/

-- `print_kernel_reject`: `#print` writes the comparator's kernel-rejection lines, and Lean's
-- error echoes `kernel_reject`; the build failed.
example : Outcome.parse 1 "Lean default kernel rejected the solution
error: Lean default exited with 1
error: Plugins/ToyRequire.lean:42:50: Unknown identifier `kernel_reject`
error: build failed
error: Child exited with 1
" = .failed .noJudgment := by decide +kernel

-- `print_illegal_axiom`: `#print` writes the comparator's report of an illegal axiom; the
-- statement does not match.
example : Outcome.parse 1 "error: Illegal axiom detected: 'sorryAx'
Build completed successfully (13 jobs).
error: Challenge and solution theorem statement do not match: 'ToyRequire.complete'
" = .failed .statement := by decide +kernel

-- `print_missing_const`: `#print` writes the exporter's panic and the comparator's exit line for
-- it; the build failed.
example : Outcome.parse 1 "info: Plugins/ToyRequire.lean:38:0: PANIC at LeanExport.dumpConstant LeanExport.Basic:254:48: Constant ToyRequire.complete not found in environment.
error: Child exited with 134
error: build failed
error: Child exited with 1
" = .failed .noJudgment := by decide +kernel


-- A report counts only as a whole line.
example : Outcome.parse 1 "Lean default kernel rejected the solution: error: Lean default exited with 1
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 "error: Lean default exited with 1 and more
" = .failed .noJudgment := by decide +kernel

/-! A failure is read only at exit code 1. Exit code 0 always comes with `Your solution is okay!`,
and 2 means that the run could not start. -/

example : Outcome.parse 0 "Build completed successfully (11 jobs).
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 0 "error: Illegal axiom detected: 'sorryAx'
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 2 "error: Illegal axiom detected: 'sorryAx'
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 1 "Your solution is okay!
" = .failed .noJudgment := by decide +kernel

example : Outcome.parse 0 "error: Illegal axiom detected: 'sorryAx'
Your solution is okay!
" = .ok := by decide +kernel

end MitosGate.Accept
