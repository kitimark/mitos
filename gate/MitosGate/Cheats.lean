import MitosGate.GateId
import MitosGate.Lint
import MitosGate.Util

/-!
# What the cheat runner decides (`mitos-gate cheats`)

`mitos-gate cheats` runs each case of `eval/cheats/` through the gate twice, the full gate and
`--skip-lint`, several runs at a time, and prints one row per case. Everything it decides is in
this module, which does no I/O. `CheatsRun.lean` lists the cases, copies the workspaces, starts
the gates, writes the logs and prints the rows, and decides nothing.

* **The verdict line.** The gate prints its verdict with `Verdict.render`, and the runner reads it
  with `Verdict.parse`. A line reads as `v` exactly when it is `v.render`
  (`Verdict.parse_eq_some_iff`). The runner reads a run's one `VERDICT:` line (`readVerdict`); none,
  or two, is no verdict (`readVerdict_eq_none`), and the gate's own output reads as its verdict
  (`readVerdict_printed`). A run whose exit code disagrees with its verdict, or that timed out, has
  none (`Run.verdict_eq_some`).
* **`expect` files.** `Expect.parse` reads `key=value` lines. Each key is known and given once,
  except `lock_append`, which may repeat; `full` and `comparator_only` are required
  (`Expect.parse_render`).
* **`judge`.** A case passes exactly when its full run is rejected at its `full=` gate, its
  comparator-only run matches `comparator_only=`, and its `guards=` claim holds (`judge_pass_iff`,
  `guardsWhy_eq_empty_iff`).
* **The table.** One row per case, in the given order (`table_cases`), and exit code 0 exactly when
  every row passed (`exitCode_eq_zero_iff`). Each judged case's two runs are jobs, each once
  (`mem_jobs`, `jobs_nodup`, `order_perm`).
* **The scheduler.** In every state the runner can reach, the jobs started so far are a prefix of
  the job list and each is running or done exactly once, at most `n` run at once, and a heavy job
  runs alone (`Reach.inv`). A job can always start while none runs (`start?_isSome`), every step
  shrinks a measure (`start?_measure`, `finish_measure`), and when the runner stops, every job is
  done, once (`Reach.complete`, `runner_done`).
-/

namespace MitosGate.Cheats

open Accept (GateId)

/-! ## Lines -/

/-- `cs` after the prefix `p`, if it starts with `p`. -/
def stripPrefix? : List Char → List Char → Option (List Char)
  | [], cs => some cs
  | _ :: _, [] => none
  | p :: ps, c :: cs => if p = c then stripPrefix? ps cs else none

theorem stripPrefix?_eq_some_iff {p cs r : List Char} :
    stripPrefix? p cs = some r ↔ cs = p ++ r := by
  induction p generalizing cs with
  | nil => simp [stripPrefix?, eq_comm]
  | cons a p ih =>
    cases cs with
    | nil => simp [stripPrefix?]
    | cons c cs =>
      simp only [stripPrefix?, List.cons_append, List.cons.injEq]
      split
      · rename_i h; subst h; simp [ih]
      · rename_i h; simp only [reduceCtorEq, false_iff, not_and]; intro h'; exact absurd h'.symm h

theorem stripPrefix?_append (p r : List Char) : stripPrefix? p (p ++ r) = some r :=
  stripPrefix?_eq_some_iff.mpr rfl

/-- The pieces of `cs` between `\n`s: `n` newlines give `n + 1` pieces. -/
def splitLines (cs : List Char) : List (List Char) := go cs []
where
  go : List Char → List Char → List (List Char)
    | [], acc => [acc.reverse]
    | c :: cs, acc => if c = '\n' then acc.reverse :: go cs [] else go cs (c :: acc)

/-- What `IO.println` writes for the lines `ls`, one after another. -/
def printed (ls : List String) : List Char := ls.flatMap fun l => l.toList ++ ['\n']

theorem splitLines_go_append {l rest acc : List Char} (h : '\n' ∉ l) :
    splitLines.go (l ++ '\n' :: rest) acc = (acc.reverse ++ l) :: splitLines.go rest [] := by
  induction l generalizing acc with
  | nil => simp [splitLines.go]
  | cons c l ih =>
    simp only [List.mem_cons, not_or] at h
    have hc : ¬ c = '\n' := fun e => h.1 e.symm
    simp [splitLines.go, hc, ih h.2]

/-- Lines the gate prints, followed by any text `rest`, split into the printed lines and `rest`'s
pieces. -/
theorem splitLines_printed_append {ls : List String} {rest : List Char}
    (h : ∀ l ∈ ls, '\n' ∉ l.toList) :
    splitLines (printed ls ++ rest) = ls.map String.toList ++ splitLines rest := by
  induction ls with
  | nil => simp [printed]
  | cons l ls ih =>
    have hl := h l (by simp)
    have := splitLines_go_append (rest := printed ls ++ rest) (acc := []) hl
    simp only [printed, List.flatMap_cons, List.append_assoc, List.cons_append, List.nil_append,
      List.map_cons] at *
    simp only [splitLines] at *
    rw [this, ih (fun l' hl' => h l' (by simp [hl']))]
    simp

/-! ## The verdict line -/

/-- What the gate decided, as its last line says. The texts are printed as given, so the gate
passes them through `oneLine` (`newline_not_mem_oneLine`). -/
inductive Verdict
  /-- Gates 0–6 passed. -/
  | accepted
  /-- Gate `g` rejected the plugin; `why` is `I/O error` when it was no judgment of the gate's own. -/
  | rejected (g : GateId) (why : String)
  /-- Gates 0–6 passed, but `--record` could not write the record. -/
  | unrecorded (why : String)
  deriving DecidableEq, Repr

/-- The verdict line the gate prints. -/
def Verdict.render : Verdict → String
  | .accepted => "VERDICT: ACCEPTED"
  | .rejected g why =>
    "VERDICT: REJECTED (gate " ++ toString g.num ++ ": " ++ g.name ++
      (if why.isEmpty then "" else ": " ++ why) ++ ")"
  | .unrecorded why => "VERDICT: REJECTED (record: " ++ why ++ ")"

/-- The gate's exit code with this verdict. -/
def Verdict.exitCode : Verdict → UInt32
  | .accepted => 0
  | _ => 1

example : (Verdict.rejected .adequacy "I/O error").render =
    "VERDICT: REJECTED (gate 6: model adequacy: I/O error)" := by decide
example : (Verdict.rejected .lint "").render = "VERDICT: REJECTED (gate 1: lint)" := by decide

def acceptedLine : List Char := "VERDICT: ACCEPTED".toList
def gateTag : List Char := "VERDICT: REJECTED (gate ".toList
def recordTag : List Char := "VERDICT: REJECTED (record: ".toList

/-- `N: name` of the gate numbered `N` that starts `cs`, and what follows it. -/
def gateOf? (cs : List Char) : Option (GateId × List Char) :=
  GateId.all.findSome? fun g => (stripPrefix? (toString g.num ++ ": " ++ g.name).toList cs).map (g, ·)

/-- What follows a gate's name on its verdict line: `)`, or `: why)` with `why` not empty. -/
def whyOf? (cs : List Char) : Option String :=
  if cs = [')'] then some ""
  else match stripPrefix? [':', ' '] cs with
    | some w => if w.getLast? = some ')' ∧ w.dropLast ≠ [] then some (String.ofList w.dropLast) else none
    | none => none

def Verdict.parseChars (cs : List Char) : Option Verdict :=
  if cs = acceptedLine then some .accepted
  else match stripPrefix? gateTag cs with
    | some rest =>
      match gateOf? rest with
      | some (g, tail) => (whyOf? tail).map (.rejected g)
      | none => none
    | none =>
      match stripPrefix? recordTag cs with
      | some rest => if rest.getLast? = some ')' then some (.unrecorded (String.ofList rest.dropLast)) else none
      | none => none

/-- The verdict a line states, if it is a verdict line the gate prints. -/
def Verdict.parse (l : String) : Option Verdict := Verdict.parseChars l.toList

theorem gateOf?_render (g : GateId) (tail : List Char) :
    gateOf? ((toString g.num ++ ": " ++ g.name).toList ++ tail) = some (g, tail) := by
  cases g <;> simp [gateOf?, GateId.all, GateId.num, GateId.name, stripPrefix?, List.findSome?,
    Nat.toDigits_of_lt_base, Nat.digitChar]

theorem gateOf?_eq_some {cs : List Char} {g : GateId} {tail : List Char}
    (h : gateOf? cs = some (g, tail)) : cs = (toString g.num ++ ": " ++ g.name).toList ++ tail := by
  obtain ⟨g', -, hg'⟩ := List.exists_of_findSome?_eq_some h
  obtain ⟨t, ht, he⟩ := Option.map_eq_some_iff.mp hg'
  cases he
  exact stripPrefix?_eq_some_iff.mp ht

theorem eq_dropLast_append {l : List Char} {a : Char} (h : l.getLast? = some a) :
    l = l.dropLast ++ [a] := by
  cases hr : l.reverse with
  | nil => simp at hr; subst hr; simp at h
  | cons b rest =>
    have hl : l = rest.reverse ++ [b] := by
      rw [← List.reverse_reverse l, hr]; simp
    subst hl
    simp only [List.getLast?_concat, Option.some.injEq] at h
    subst h
    simp

/-- The text after a gate's name on the line for `why`. -/
def whyText (why : String) : List Char :=
  (if why.isEmpty then [] else ':' :: ' ' :: why.toList) ++ [')']

theorem whyOf?_eq_some_iff {cs : List Char} {why : String} :
    whyOf? cs = some why ↔ cs = whyText why := by
  unfold whyOf? whyText
  by_cases h : cs = [')']
  · subst h
    by_cases hw : why = ""
    · subst hw; simp
    · have : why.isEmpty = false := by simpa [String.isEmpty_iff] using hw
      simp only [↓reduceIte, Option.some.injEq, this, Bool.false_eq_true]
      constructor
      · intro e; exact absurd e.symm hw
      · intro e; simp at e
  · simp only [h, ↓reduceIte]
    cases hs : stripPrefix? [':', ' '] cs with
    | none =>
      simp only [reduceCtorEq, false_iff]
      intro e
      split at e
      · simp at e; exact h e
      · rw [e] at hs; simp [stripPrefix?] at hs
    | some w =>
      have hcs := stripPrefix?_eq_some_iff.mp hs
      subst hcs
      simp only [Option.ite_none_right_eq_some, Option.some.injEq]
      constructor
      · rintro ⟨⟨hl, hne⟩, rfl⟩
        have hw : String.ofList w.dropLast ≠ "" := by
          intro e; apply hne; simpa using congrArg String.toList e
        have : (String.ofList w.dropLast).isEmpty = false := by simpa [String.isEmpty_iff] using hw
        simp only [this, Bool.false_eq_true, ↓reduceIte, String.toList_ofList, List.cons_append,
          List.cons.injEq, true_and]
        exact eq_dropLast_append hl
      · intro e
        split at e
        · simp at e
        · rename_i hwhy
          simp only [List.cons_append, List.cons.injEq, true_and] at e
          subst e
          refine ⟨⟨by simp, ?_⟩, by simp⟩
          have : why ≠ "" := by simpa [String.isEmpty_iff] using hwhy
          simpa [String.toList_eq_nil_iff] using this

theorem render_toList (v : Verdict) : v.render.toList = match v with
    | .accepted => acceptedLine
    | .rejected g why => gateTag ++ (toString g.num ++ ": " ++ g.name).toList ++ whyText why
    | .unrecorded why => recordTag ++ why.toList ++ [')'] := by
  cases v with
  | accepted => rfl
  | rejected g why =>
    simp only [Verdict.render, gateTag, whyText, String.toList_append, List.append_assoc]
    split <;> simp
  | unrecorded why => simp [Verdict.render, recordTag]

theorem gateTag_ne_accepted (x : List Char) : gateTag ++ x ≠ acceptedLine := by
  intro e
  have := congrArg List.length e
  simp [gateTag, acceptedLine] at this

theorem recordTag_ne_accepted (x : List Char) : recordTag ++ x ≠ acceptedLine := by
  intro e
  have := congrArg List.length e
  simp [recordTag, acceptedLine] at this

theorem stripPrefix?_gateTag_recordTag (x : List Char) : stripPrefix? gateTag (recordTag ++ x) = none := by
  simp [gateTag, recordTag, stripPrefix?]

/-- **The runner reads exactly what the gate prints.** A line reads as the verdict `v` exactly when
it is `v`'s line: the gate's lines read as their verdicts, and no other line reads as any verdict. -/
theorem Verdict.parse_eq_some_iff {l : String} {v : Verdict} : Verdict.parse l = some v ↔ l = v.render := by
  constructor
  · intro h
    apply String.ext_iff.mpr
    rw [render_toList]
    simp only [Verdict.parse, Verdict.parseChars] at h
    split at h
    · rename_i hacc; cases h; exact hacc
    · split at h
      · rename_i rest hrest
        split at h
        · rename_i g tail hg
          obtain ⟨why, hwhy, rfl⟩ := Option.map_eq_some_iff.mp h
          rw [stripPrefix?_eq_some_iff.mp hrest, gateOf?_eq_some hg, whyOf?_eq_some_iff.mp hwhy]
          simp
        · cases h
      · split at h
        · rename_i rest hrest
          split at h
          · rename_i hl
            cases h
            rw [stripPrefix?_eq_some_iff.mp hrest]
            simpa using eq_dropLast_append hl
          · cases h
        · cases h
  · rintro rfl
    simp only [Verdict.parse, Verdict.parseChars, render_toList]
    cases v with
    | accepted => simp
    | rejected g why =>
      simp only [List.append_assoc, gateTag_ne_accepted, ↓reduceIte, stripPrefix?_append,
        gateOf?_render]
      simp [whyOf?_eq_some_iff.mpr rfl]
    | unrecorded why =>
      simp only [List.append_assoc, recordTag_ne_accepted, ↓reduceIte, stripPrefix?_gateTag_recordTag,
        stripPrefix?_append]
      simp

theorem Verdict.parse_render (v : Verdict) : Verdict.parse v.render = some v :=
  Verdict.parse_eq_some_iff.mpr rfl

/-! ## Reading a run's verdict -/

/-- Lines that start with `VERDICT:`. -/
def isVerdictLine (l : List Char) : Bool := "VERDICT:".toList.isPrefixOf l

/-- The lines of the output that start with `VERDICT:`. -/
def verdictLines (out : String) : List (List Char) := (splitLines out.toList).filter isVerdictLine

/-- The verdict of a run's output: its one `VERDICT:` line, read with `Verdict.parse`. -/
def readVerdict (out : String) : Option Verdict :=
  match verdictLines out with
  | [l] => Verdict.parseChars l
  | _ => none

/-- No verdict line, or two or more, is no verdict. -/
theorem readVerdict_eq_none {out : String} (h : (verdictLines out).length ≠ 1) :
    readVerdict out = none := by
  unfold readVerdict
  split
  · rename_i l hl; simp [hl] at h
  · rfl

theorem isVerdictLine_render (v : Verdict) : isVerdictLine v.render.toList = true := by
  rw [render_toList]
  cases v <;> simp [isVerdictLine, acceptedLine, gateTag, recordTag, List.isPrefixOf]

/-- **The gate's output reads as its verdict.** The gate prints lines `pre` that are not verdict
lines, then its verdict line; anything may follow (such as the standard error), as long as none of
its lines is a verdict line. -/
theorem readVerdict_printed {pre : List String} {v : Verdict} {rest : List Char}
    (hpre : ∀ l ∈ pre, '\n' ∉ l.toList ∧ isVerdictLine l.toList = false)
    (hv : '\n' ∉ v.render.toList) (hrest : ∀ l ∈ splitLines rest, isVerdictLine l = false) :
    readVerdict (String.ofList (printed (pre ++ [v.render]) ++ rest)) = some v := by
  have hsplit := splitLines_printed_append (ls := pre ++ [v.render]) (rest := rest)
    (fun l hl => by
      rcases List.mem_append.mp hl with h | h
      · exact (hpre l h).1
      · simp at h; subst h; exact hv)
  have : verdictLines (String.ofList (printed (pre ++ [v.render]) ++ rest)) = [v.render.toList] := by
    simp only [verdictLines, String.toList_ofList, hsplit, List.map_append, List.map_cons,
      List.map_nil, List.filter_append, List.filter_cons, isVerdictLine_render, ↓reduceIte,
      List.filter_nil]
    rw [List.filter_eq_nil_iff.mpr, List.filter_eq_nil_iff.mpr]
    · simp
    · intro l hl; simp [hrest l hl]
    · intro l hl
      obtain ⟨s, hs, rfl⟩ := List.mem_map.mp hl
      simp [(hpre s hs).2]
  simp only [readVerdict, this]
  exact Verdict.parse_render v

/-- `oneLine` text has no newline, so a verdict made with it is one line. -/
theorem newline_not_mem_oneLine (s : String) : '\n' ∉ (oneLine s).toList := by
  intro h
  rcases oneLine_printable s '\n' h with h | h
  · exact absurd h (by decide)
  · exact absurd h (by decide)

/-- One finished run of the gate: its exit code, its standard output followed by its standard
error, and whether the runner stopped it at its timeout. -/
structure Run where
  exitCode : UInt32
  output : String
  timedOut : Bool
  deriving Inhabited, Repr

/-- A run that never happened: no output, so no verdict. -/
def noRun : Run := { exitCode := 255, output := "", timedOut := false }

/-- The run's verdict: the one its output states, if the run finished on its own and exited with
that verdict's exit code. -/
def Run.verdict (r : Run) : Option Verdict :=
  if r.timedOut then none
  else match readVerdict r.output with
    | some v => if v.exitCode = r.exitCode then some v else none
    | none => none

theorem Run.verdict_eq_some {r : Run} {v : Verdict} :
    r.verdict = some v ↔ r.timedOut = false ∧ readVerdict r.output = some v ∧ v.exitCode = r.exitCode := by
  unfold Run.verdict
  cases ht : r.timedOut
  · simp only [Bool.false_eq_true, ↓reduceIte, true_and]
    cases h : readVerdict r.output with
    | none => simp
    | some v' =>
      simp only [Option.some.injEq]
      by_cases he : v'.exitCode = r.exitCode
      · simp only [he, ↓reduceIte, Option.some.injEq]
        constructor
        · rintro rfl; exact ⟨rfl, he⟩
        · rintro ⟨rfl, -⟩; rfl
      · simp only [he, ↓reduceIte, reduceCtorEq, false_iff, not_and]
        rintro rfl; exact he
  · simp

example : noRun.verdict = none := by decide

/-- How the row shows a run. -/
def Run.shown (r : Run) : String :=
  match r.verdict with
  | some .accepted => "ACCEPTED"
  | some (.rejected g _) => s!"REJECTED@{g.num}"
  | some (.unrecorded _) => "REJECTED@record"
  | none => if r.timedOut then "TIMEOUT" else "NO-VERDICT"

/-! ## `expect` files -/

/-- What a case's comparator-only run must give. -/
inductive CompExpect
  | accept
  /-- Rejected at any gate. -/
  | reject
  | rejectAt (g : GateId)
  deriving DecidableEq, Repr

def CompExpect.render : CompExpect → String
  | .accept => "accept"
  | .reject => "reject"
  | .rejectAt g => s!"reject@{g.num}"

def CompExpect.all : List CompExpect := [.accept, .reject] ++ GateId.all.map .rejectAt

def CompExpect.parse (s : String) : Option CompExpect := CompExpect.all.find? (·.render == s)

theorem CompExpect.parse_render (c : CompExpect) : CompExpect.parse c.render = some c := by
  cases c with
  | accept => decide
  | reject => decide
  | rejectAt g => cases g <;> decide

/-- The gate numbered `s`, as `full=` gives it. -/
def gateOfNum? (s : String) : Option GateId := GateId.all.find? (toString ·.num == s)

theorem gateOfNum?_num (g : GateId) : gateOfNum? (toString g.num) = some g := by
  cases g <;> decide

/-- The keys of an `expect` file. -/
inductive Key
  | full | comparatorOnly | modelApproved | heavy | lockAppend | why | guards
  deriving DecidableEq, Repr

def Key.name : Key → String
  | .full => "full" | .comparatorOnly => "comparator_only" | .modelApproved => "model_approved"
  | .heavy => "heavy" | .lockAppend => "lock_append" | .why => "why" | .guards => "guards"

def Key.all : List Key := [.full, .comparatorOnly, .modelApproved, .heavy, .lockAppend, .why, .guards]

def Key.ofName? (s : String) : Option Key := Key.all.find? (·.name == s)

theorem Key.ofName?_name (k : Key) : Key.ofName? k.name = some k := by cases k <;> decide

theorem Key.eq_not_mem_name (k : Key) : '=' ∉ k.name.toList ∧ '\n' ∉ k.name.toList := by
  cases k <;> decide

/-- Keys that may be given at most once; each `lock_append` line adds a line to `models.lock`. -/
def Key.single (k : Key) : Bool := k != .lockAppend

/-- The lint rules a cheat case can guard (`Lint.Rule.guardable`), by id. -/
def guardIds : List String :=
  ((Lint.Rule.fixed ++ Lint.banned.map Lint.Rule.banned).filter Lint.Rule.guardable).map Lint.Rule.id

theorem newline_not_mem_guardIds : ∀ r ∈ guardIds, '\n' ∉ r.toList := by decide +kernel

/-- A cheat case's `expect` file. -/
structure Expect where
  /-- The gate that must reject the full run. -/
  full : GateId
  comparatorOnly : CompExpect
  /-- The case stands for models the owner approved: the runner re-pins `models.lock`. -/
  modelApproved : Bool := false
  /-- The case needs much memory: its runs run alone. -/
  heavy : Bool := false
  /-- Lines appended to the workspace's `models.lock`. -/
  lockAppend : List String := []
  why : Option String := none
  /-- The lint rule, by id, without which the full run would be accepted. -/
  guards : Option String := none
  deriving DecidableEq, Repr

/-- The pairs `(k, v)` for each value `v`. -/
def tagged (k : Key) (vs : List String) : List (Key × String) := vs.map (k, ·)

/-- The `key=value` pairs that `render` writes, in its order. -/
def Expect.fields (e : Expect) : List (Key × String) :=
  tagged .full [toString e.full.num] ++ tagged .comparatorOnly [e.comparatorOnly.render] ++
    tagged .modelApproved (if e.modelApproved then ["yes"] else []) ++
    tagged .heavy (if e.heavy then ["yes"] else []) ++ tagged .lockAppend e.lockAppend ++
    tagged .why e.why.toList ++ tagged .guards e.guards.toList

def fieldLine (f : Key × String) : String := f.1.name ++ "=" ++ f.2

def Expect.render (e : Expect) : String := String.join (e.fields.map fun f => fieldLine f ++ "\n")

/-- `cs` split at its first `=`. -/
def splitKV : List Char → Option (List Char × List Char)
  | [] => none
  | c :: cs => if c = '=' then some ([], cs) else (splitKV cs).map fun (k, v) => (c :: k, v)

theorem splitKV_append {k v : List Char} (h : '=' ∉ k) : splitKV (k ++ '=' :: v) = some (k, v) := by
  induction k with
  | nil => simp [splitKV]
  | cons c k ih =>
    simp only [List.mem_cons, not_or] at h
    have hc : ¬ c = '=' := fun e => h.1 e.symm
    simp [splitKV, hc, ih h.2]

/-- One line of an `expect` file. -/
def parseLine (l : List Char) : Except String (Key × String) :=
  match splitKV l with
  | none => .error s!"the line {String.ofList l} is not key=value"
  | some (k, v) =>
    match Key.ofName? (String.ofList k) with
    | some key => .ok (key, String.ofList v)
    | none => .error s!"unknown key {String.ofList k}"

theorem parseLine_fieldLine (f : Key × String) (h : '\n' ∉ f.2.toList) :
    parseLine (fieldLine f).toList = .ok f := by
  obtain ⟨k, v⟩ := f
  simp only [parseLine, fieldLine, String.toList_append, List.append_assoc]
  rw [show "=".toList ++ v.toList = '=' :: v.toList by simp,
    splitKV_append (Key.eq_not_mem_name k).1]
  simp [Key.ofName?_name]

/-- The pieces of a file's text, without the empty piece after a final `\n`. -/
def fileLines (txt : String) : List (List Char) :=
  let ls := splitLines txt.toList
  if ls.getLast? = some [] then ls.dropLast else ls

/-- The value of key `k`, the first if there are several. -/
def get (fs : List (Key × String)) (k : Key) : Option String := (fs.find? (·.1 == k)).map (·.2)

/-- `yes` for a flag that is given, otherwise absent. -/
def flag (fs : List (Key × String)) (k : Key) : Except String Bool :=
  match get fs k with
  | none => .ok false
  | some "yes" => .ok true
  | some v => .error s!"{k.name}={v}: the only value is yes"

/-- The `lock_append` values, in order. -/
def lockLines (fs : List (Key × String)) : List String :=
  fs.filterMap fun f => if f.1 = .lockAppend then some f.2 else none

/-- An `expect` file from its pairs: each key at most once (but `lock_append`), `full` a gate
number, `comparator_only` `accept`, `reject` or `reject@N`, a flag `yes`, `guards` a rule a case can
guard. -/
def ofFields (fs : List (Key × String)) : Except String Expect :=
  match Key.all.find? fun k => k.single && 1 < fs.countP (·.1 == k) with
  | some k => .error s!"{k.name}= is given more than once"
  | none =>
    match get fs .full, get fs .comparatorOnly with
    | none, _ => .error "full= is missing"
    | _, none => .error "comparator_only= is missing"
    | some f, some c =>
      match gateOfNum? f, CompExpect.parse c with
      | none, _ => .error s!"full={f} is not a gate number 0-6"
      | _, none => .error s!"comparator_only={c} is not accept, reject or reject@N"
      | some full, some comparatorOnly =>
        match flag fs .modelApproved, flag fs .heavy with
        | .error e, _ | _, .error e => .error e
        | .ok modelApproved, .ok heavy =>
          let guards := get fs .guards
          if guards.all guardIds.contains then
            .ok { full, comparatorOnly, modelApproved, heavy, guards, lockAppend := lockLines fs,
                  why := get fs .why }
          else .error s!"guards={guards.getD ""} names no lint rule a case can guard"

/-- Parse an `expect` file's text. -/
def Expect.parse (txt : String) : Except String Expect :=
  match (fileLines txt).mapM parseLine with
  | .ok fs => ofFields fs
  | .error e => .error e

/-- What `render` needs to write a file that `parse` reads back: values on one line, and a
`guards=` rule a case can guard. -/
structure Expect.Valid (e : Expect) : Prop where
  lockAppend : ∀ s ∈ e.lockAppend, '\n' ∉ s.toList
  why : ∀ s ∈ e.why, '\n' ∉ s.toList
  guards : ∀ r ∈ e.guards, r ∈ guardIds

theorem Key.beq_eq (a b : Key) : (a == b) = decide (a = b) := rfl

theorem find?_tagged (k k' : Key) (vs : List String) :
    (tagged k' vs).find? (·.1 == k) = if k' = k then vs.head?.map (k, ·) else none := by
  cases vs with
  | nil => simp [tagged]
  | cons v vs =>
    by_cases h : k' = k
    · subst h; simp [tagged, Key.beq_eq]
    · simp only [tagged, List.map_cons, List.find?_cons, Key.beq_eq, h, decide_false, ite_false]
      rw [List.find?_eq_none]
      simp [h]

theorem countP_tagged (k k' : Key) (vs : List String) :
    (tagged k' vs).countP (·.1 == k) = if k' = k then vs.length else 0 := by
  by_cases h : k' = k
  · subst h; simp [tagged, Key.beq_eq, List.countP_map, Function.comp_def]
  · simp [tagged, Key.beq_eq, List.countP_map, Function.comp_def, h]

theorem lockLines_tagged (k : Key) (vs : List String) :
    lockLines (tagged k vs) = if k = .lockAppend then vs else [] := by
  by_cases h : k = .lockAppend
  · subst h; simp [lockLines, tagged, List.filterMap_map, Function.comp_def]
  · simp [lockLines, tagged, List.filterMap_map, Function.comp_def, h]

theorem lockLines_append (a b : List (Key × String)) :
    lockLines (a ++ b) = lockLines a ++ lockLines b := by
  simp [lockLines, List.filterMap_append]

theorem Expect.get_fields (e : Expect) (k : Key) : get e.fields k = match k with
    | .full => some (toString e.full.num)
    | .comparatorOnly => some e.comparatorOnly.render
    | .modelApproved => if e.modelApproved then some "yes" else none
    | .heavy => if e.heavy then some "yes" else none
    | .lockAppend => e.lockAppend.head?
    | .why => e.why
    | .guards => e.guards := by
  cases k <;> simp only [get, Expect.fields, List.find?_append, find?_tagged, reduceCtorEq, ite_false,
      ite_true, Option.or_none, Option.none_or, Option.map_map, Function.comp_def] <;>
    first
    | rfl
    | (split <;> rfl)
    | (cases e.why <;> rfl)
    | (cases e.guards <;> rfl)
    | (cases e.lockAppend <;> rfl)

theorem Expect.countP_fields (e : Expect) (k : Key) (hk : k.single = true) :
    e.fields.countP (·.1 == k) ≤ 1 := by
  cases k <;> simp only [Key.single, bne_self_eq_false, Bool.false_eq_true] at hk <;>
    simp only [Expect.fields, List.countP_append, countP_tagged, reduceCtorEq, ite_false, ite_true] <;>
    simp only [List.length_cons, List.length_nil, Nat.zero_add, Nat.add_zero] <;>
    first
    | omega
    | (split <;> simp)
    | (cases e.why <;> simp)
    | (cases e.guards <;> simp)

/-- No `\n` in any value `fields` writes. -/
theorem Expect.newline_not_mem_fields (e : Expect) (hv : e.Valid) :
    ∀ f ∈ e.fields, '\n' ∉ f.2.toList := by
  have h1 : '\n' ∉ (toString e.full.num).toList := by cases e.full <;> decide
  have h2 : '\n' ∉ e.comparatorOnly.render.toList := by
    cases e.comparatorOnly with
    | accept => decide
    | reject => decide
    | rejectAt g => cases g <;> decide
  have h3 : ∀ b : Bool, ∀ s ∈ (if b then ["yes"] else []), '\n' ∉ s.toList := by
    intro b s hs; cases b <;> simp at hs; subst hs; decide
  intro f hf
  simp only [Expect.fields, tagged, List.mem_append, List.mem_map] at hf
  rcases hf with ((((((⟨s, hs, rfl⟩ | ⟨s, hs, rfl⟩) | ⟨s, hs, rfl⟩) | ⟨s, hs, rfl⟩) | ⟨s, hs, rfl⟩) |
    ⟨s, hs, rfl⟩) | ⟨s, hs, rfl⟩)
  · simp at hs; subst hs; exact h1
  · simp at hs; subst hs; exact h2
  · exact h3 _ s hs
  · exact h3 _ s hs
  · exact hv.lockAppend s hs
  · exact hv.why s (by simpa using hs)
  · exact newline_not_mem_guardIds s (hv.guards s (by simpa using hs))

theorem Expect.fileLines_render (e : Expect) (hv : e.Valid) :
    fileLines e.render = e.fields.map fun f => (fieldLine f).toList := by
  have hlines : ∀ l ∈ e.fields.map fieldLine, '\n' ∉ l.toList := by
    intro l hl
    obtain ⟨f, hf, rfl⟩ := List.mem_map.mp hl
    simp only [fieldLine, String.toList_append, List.mem_append, not_or]
    exact ⟨⟨(Key.eq_not_mem_name f.1).2, by decide⟩, e.newline_not_mem_fields hv f hf⟩
  have hp : e.render.toList = printed (e.fields.map fieldLine) := by
    simp [Expect.render, printed, List.flatMap_map]
  have hs := splitLines_printed_append (rest := []) hlines
  simp only [List.append_nil] at hs
  have : splitLines e.render.toList = (e.fields.map fun f => (fieldLine f).toList) ++ [[]] := by
    rw [hp, hs]
    simp [splitLines, splitLines.go, List.map_map, Function.comp_def]
  unfold fileLines
  simp only [this, List.getLast?_concat, ite_true, List.dropLast_concat]

theorem ofFields_fields (e : Expect) (hv : e.Valid) : ofFields e.fields = .ok e := by
  have hdup : Key.all.find? (fun k => k.single && 1 < e.fields.countP (·.1 == k)) = none := by
    rw [List.find?_eq_none]
    intro k _
    cases hk : k.single
    · simp
    · have := e.countP_fields k hk
      simp only [Bool.true_and, decide_eq_true_eq, Nat.not_lt]
      exact this
  have hflag : ∀ (b : Bool) (k : Key), (match (if b then some "yes" else none) with
      | none => Except.ok false | some "yes" => .ok true
      | some v => .error s!"{k.name}={v}: the only value is yes" : Except String Bool) = .ok b := by
    intro b k; cases b <;> rfl
  have hlock : lockLines e.fields = e.lockAppend := by
    simp only [Expect.fields, lockLines_append, lockLines_tagged, reduceCtorEq, ite_false, ite_true,
      List.nil_append, List.append_nil]
  have hguards : (e.guards.all guardIds.contains) = true := by
    cases h : e.guards with
    | none => rfl
    | some r => simpa using hv.guards r (by simp [h])
  unfold ofFields
  rw [hdup]
  simp only [e.get_fields, gateOfNum?_num, CompExpect.parse_render, flag]
  rw [hflag, hflag]
  simp only [hguards, ite_true, hlock]

theorem mapM_map_ok {β γ : Type} {f : γ → Except String β} {h : β → γ} :
    ∀ {xs : List β}, (∀ x ∈ xs, f (h x) = .ok x) → (xs.map h).mapM f = .ok xs
  | [], _ => rfl
  | x :: xs, hx => by
    simp only [List.map_cons, List.mapM_cons, hx x (by simp)]
    rw [mapM_map_ok (fun y hy => hx y (by simp [hy]))]
    rfl

/-- **The parser reads back what `render` writes.** -/
theorem Expect.parse_render (e : Expect) (hv : e.Valid) : Expect.parse e.render = .ok e := by
  unfold Expect.parse
  rw [Expect.fileLines_render e hv,
    mapM_map_ok (fun f hf => parseLine_fieldLine f (e.newline_not_mem_fields hv f hf))]
  exact ofFields_fields e hv

example : (Expect.parse "full=1\ncomparator_only=reject@4\nwhy=Uses `admit`.\n").toOption =
    some { full := .lint, comparatorOnly := .rejectAt .axioms, why := some "Uses `admit`." } := by
  decide +kernel
/-- A key given twice, a missing `comparator_only=`, a flag other than `yes`, an unknown key, a
blank line, a gate number that is not one, and a rule no case can guard are each an error. -/
example : (Expect.parse "full=1\nfull=1\ncomparator_only=accept\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\nheavy=no\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\nfull_exp=2\n").toBool = false := by
  decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\n\n").toBool = false := by decide +kernel
example : (Expect.parse "full=01\ncomparator_only=accept\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\nguards=parse\n").toBool = false := by
  decide +kernel
/-- `lock_append=` may repeat; its lines keep their order. -/
example : ((Expect.parse "full=0\ncomparator_only=reject@0\nlock_append=a\nlock_append=b\n").toOption.map
    (·.lockAppend)) = some ["a", "b"] := by decide +kernel

/-! ## Judging one case -/

/-- How a run's lines start when gate 1 failed. -/
def failTag : List Char := (GateId.lint.label ++ ": FAIL").toList

/-- The number of violations on gate 1's `FAIL — N violation(s)` line. -/
def violationCount (l : List Char) : Option Nat := do
  let r ← stripPrefix? (failTag ++ " — ".toList) l
  let d ← (stripPrefix? " violation(s)".toList.reverse r.reverse).map List.reverse
  if d ≠ [] ∧ d.all Char.isDigit then some (d.foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0)
  else none

/-- `[R]` of a line that ends with ` [R]`, where `R` has no space or bracket, otherwise
`no rule`. -/
def ruleOf (l : List Char) : String :=
  match l.reverse with
  | ']' :: rest =>
    let x := rest.takeWhile fun c => c ≠ '[' ∧ c ≠ ']' ∧ c ≠ ' '
    match rest.drop x.length with
    | '[' :: ' ' :: _ => "[" ++ String.ofList x.reverse ++ "]"
    | _ => "no rule"
  | _ => "no rule"

/-- What a full run's log says about gate 1, read line by line as `run.sh`'s `check_guards` read
it: after a line that starts with `GATE 1 lint: FAIL`, the lines that start with two spaces are
violations, counted in `listed`; `count` is the number on the `FAIL` line, and `others` lists, once
each, the rule of every violation that does not end with ` [R]`. -/
structure Scan where
  on : Bool := false
  count : Option Nat := none
  listed : Nat := 0
  others : List String := []
  deriving DecidableEq, Repr

def scanLine (want : List Char) (s : Scan) (l : List Char) : Scan :=
  if failTag.isPrefixOf l then { s with on := true, count := (violationCount l).or s.count }
  else if s.on && "  ".toList.isPrefixOf l then
    if want.isSuffixOf l then { s with listed := s.listed + 1 }
    else
      let r := ruleOf l
      { s with listed := s.listed + 1, others := if s.others.contains r then s.others else s.others ++ [r] }
  else { s with on := false }

def scan (rule : String) (out : String) : Scan :=
  (splitLines out.toList).foldl (scanLine (" [" ++ rule ++ "]").toList) {}

def notAccept : String := "it is not comparator_only=accept"

/-- Why gate 1's report does not show that rule `R` alone rejected the full run, or `""`. -/
def lintWhy (s : Scan) : String :=
  match s.count with
  | none | some 0 => "the full run reports no gate-1 violation"
  | some n =>
    if s.listed ≠ n then "gate 1 counts " ++ toString n ++ " violations and lists " ++ toString s.listed
    else if s.others ≠ [] then "the full run also has violations " ++ ", ".intercalate s.others
    else ""

/-- Why the claim `guards=R` fails, or `""` when it holds. `--skip-lint` skips gate 1 only, and lint
is a pure function of the bytes, so "without R the full run is ACCEPTED" holds when the
comparator-only run is accepted (`comparator_only=accept`, checked by `judge`) and every violation
of the full run has rule R. -/
def guardsWhy (rule : String) (comp : CompExpect) (out : String) : String :=
  if out = "" then "no full-run log"
  else
    let why := lintWhy (scan rule out)
    if comp = .accept then why
    else if why = "" then notAccept
    else why ++ "; " ++ notAccept

/-- A string whose length is positive is not empty; `simp` computes the length of a message. -/
theorem ne_empty_of_length {s : String} (h : 0 < s.length) : s ≠ "" := by
  rintro rfl; simp at h

theorem lintWhy_eq_empty_iff {s : Scan} :
    lintWhy s = "" ↔ ∃ n, 0 < n ∧ s.count = some n ∧ s.listed = n ∧ s.others = [] := by
  have e1 : "the full run reports no gate-1 violation" ≠ "" := by decide
  unfold lintWhy
  cases hc : s.count with
  | none => simp [e1]
  | some n =>
    cases n with
    | zero =>
      simp only [e1, false_iff, not_exists, not_and]
      intro x hx h
      cases h
      exact absurd hx (Nat.lt_irrefl 0)
    | succ m =>
      by_cases hl : s.listed = m + 1
      · by_cases ho : s.others = []
        · simp [hl, ho]
        · have hne : "the full run also has violations " ++ ", ".intercalate s.others ≠ "" := by
            apply ne_empty_of_length
            have : 0 < "the full run also has violations ".length := by decide
            simp only [String.length_append]; omega
          simp [hl, ho, hne]
      · have hne : "gate 1 counts " ++ toString (m + 1) ++ " violations and lists " ++
            toString s.listed ≠ "" := by
          apply ne_empty_of_length
          have : 0 < "gate 1 counts ".length := by decide
          simp only [String.length_append]; omega
        simp only [ne_eq, hl, not_false_eq_true, ite_true, hne, false_iff, not_exists, not_and]
        intro x _ h; cases h; exact fun h' => absurd h' hl

/-- **When `guards=R` holds.** The full run printed something, the case is `comparator_only=accept`,
and gate 1's report counts at least one violation, lists as many, and each has rule R. -/
theorem guardsWhy_eq_empty_iff {rule : String} {comp : CompExpect} {out : String} :
    guardsWhy rule comp out = "" ↔ out ≠ "" ∧ comp = .accept ∧
      ∃ n, 0 < n ∧ (scan rule out).count = some n ∧ (scan rule out).listed = n ∧
        (scan rule out).others = [] := by
  unfold guardsWhy
  by_cases ho : out = ""
  · simp [ho]
  · simp only [ho, ite_false, ne_eq, not_false_eq_true, true_and]
    by_cases hc : comp = .accept
    · simp [hc, lintWhy_eq_empty_iff]
    · simp only [hc, ite_false, false_and, iff_false]
      have : 0 < notAccept.length := by decide
      split
      · exact ne_empty_of_length this
      · apply ne_empty_of_length; simp only [String.length_append]; omega

/-- `eval_command.full.log` from a local run, which `guards=hash` reads. -/
def evalCommandLog : String := "GATE 0 provenance: PASS
GATE 1 lint: FAIL — 1 violation(s)
  /tmp/tmp.tZhcUv3lgT/Plugins/ToyRequire.lean:8:1: command `#eval` is not allowed [hash]
VERDICT: REJECTED (gate 1: lint)
"

example : readVerdict evalCommandLog = some (.rejected .lint "") := by decide +kernel
example : guardsWhy "hash" .accept evalCommandLog = "" := by decide +kernel
example : guardsWhy "banned:sorry" .accept evalCommandLog =
    "the full run also has violations [hash]" := by decide +kernel
example : guardsWhy "hash" (.rejectAt .axioms) evalCommandLog =
    "it is not comparator_only=accept" := by decide +kernel
/-- Gate 1 counts two violations but lists one. -/
example : guardsWhy "hash" .accept "GATE 1 lint: FAIL — 2 violation(s)
  Plugins/ToyRequire.lean:8:1: command `#eval` is not allowed [hash]
VERDICT: REJECTED (gate 1: lint)
" = "gate 1 counts 2 violations and lists 1" := by decide +kernel
example : guardsWhy "hash" .accept "VERDICT: REJECTED (gate 3: statements)\n" =
    "the full run reports no gate-1 violation" := by decide +kernel

/-- The guards cell of a row: `guards=R`, and why the claim fails if it does. -/
def guardText (rule why : String) : String :=
  "guards=" ++ rule ++ (if why = "" then "" else ": " ++ why)

/-- Whether the full run was rejected at gate `g`. -/
def fullOk (g : GateId) : Option Verdict → Bool
  | some (.rejected g' _) => g' == g
  | _ => false

/-- Whether a comparator-only verdict is what `comparator_only=` says. -/
def CompExpect.ok : CompExpect → Option Verdict → Bool
  | .accept, some .accepted => true
  | .reject, some (.rejected _ _) => true
  | .rejectAt g, some (.rejected g' _) => g' == g
  | _, _ => false

/-- Whether the case's `guards=` claim, if it has one, holds. -/
def guardsOk (e : Expect) (full : Run) : Bool :=
  match e.guards with
  | none => true
  | some r => guardsWhy r e.comparatorOnly full.output == ""

/-- `s` padded with spaces to `n` characters, as `printf '%-ns'` pads. -/
def pad (n : Nat) (s : String) : String := s ++ String.ofList (List.replicate (n - s.length) ' ')

/-- One row of the table: a case, the rest of its row, and whether it passed. -/
structure Row where
  case : String
  text : String
  pass : Bool
  deriving Repr

def Row.render (r : Row) : String :=
  pad 20 r.case ++ " " ++ r.text ++ (if r.pass then "" else "  <-- FAIL")

def header : String :=
  pad 20 "CASE" ++ " " ++ pad 14 "FULL" ++ " " ++ pad 14 "EXPECT" ++ " " ++ pad 22 "COMPARATOR-ONLY" ++
    " " ++ pad 10 "EXPECT" ++ " " ++ "GUARDS"

/-- The row of a case with expectations `e`, from its full and its comparator-only run. -/
def judge (case : String) (e : Expect) (full comp : Run) : Row :=
  let guard := match e.guards with
    | none => ""
    | some r => guardText r (guardsWhy r e.comparatorOnly full.output)
  { case
    text := pad 14 full.shown ++ " " ++ pad 14 ("@" ++ toString e.full.num) ++ " " ++
      pad 22 comp.shown ++ " " ++ pad 10 e.comparatorOnly.render ++ " " ++ guard
    pass := fullOk e.full full.verdict && e.comparatorOnly.ok comp.verdict && guardsOk e full }

/-- What `comparator_only=` asks of the comparator-only run's verdict. -/
def CompExpect.Holds : CompExpect → Option Verdict → Prop
  | .accept, v => v = some .accepted
  | .reject, v => ∃ g why, v = some (.rejected g why)
  | .rejectAt g, v => ∃ why, v = some (.rejected g why)

/-- **When a case passes.** Its full run is rejected at the gate `full=` names, its comparator-only
run gives what `comparator_only=` says, and, if it has `guards=R`, the claim holds
(`guardsWhy_eq_empty_iff`). -/
theorem judge_pass_iff {case : String} {e : Expect} {full comp : Run} :
    (judge case e full comp).pass = true ↔
      (∃ why, full.verdict = some (.rejected e.full why)) ∧ e.comparatorOnly.Holds comp.verdict ∧
        ∀ r, e.guards = some r → guardsWhy r e.comparatorOnly full.output = "" := by
  simp only [judge, Bool.and_eq_true, and_assoc]
  apply and_congr
  · generalize full.verdict = v
    rcases v with _ | _ | ⟨g, w⟩ | w <;> simp [fullOk]
  · apply and_congr
    · generalize comp.verdict = v
      rcases v with _ | _ | ⟨g, w⟩ | w <;> cases e.comparatorOnly <;>
        simp [CompExpect.ok, CompExpect.Holds]
    · unfold guardsOk
      split <;> simp_all

/-! ## The table -/

/-- A case as the runner found it: its directory's name, and its `expect` file parsed, or why
there is none. -/
structure Case where
  name : String
  expect : Except String Expect

/-- The two runs of a case. -/
inductive Mode
  | full | comparatorOnly
  deriving DecidableEq, Repr

/-- The run's name in its log's name, `<case>.full.log` or `<case>.comparator.log`. -/
def Mode.logName : Mode → String
  | .full => "full"
  | .comparatorOnly => "comparator"

/-- The case's row, from its runs (`none` for a run that did not happen). A case without a
parsed `expect` fails. -/
def Case.row (c : Case) (full comp : Option Run) : Row :=
  match c.expect with
  | .error msg => { case := c.name, text := msg, pass := false }
  | .ok e => judge c.name e (full.getD noRun) (comp.getD noRun)

def tableFrom (res : Nat → Mode → Option Run) : Nat → List Case → List Row
  | _, [] => []
  | i, c :: cs => c.row (res i .full) (res i .comparatorOnly) :: tableFrom res (i + 1) cs

/-- One row per case, in order; `res i m` is the run of mode `m` of the `i`-th case. -/
def table (res : Nat → Mode → Option Run) (cases : List Case) : List Row := tableFrom res 0 cases

theorem tableFrom_cases (res : Nat → Mode → Option Run) :
    ∀ (i : Nat) (cases : List Case), (tableFrom res i cases).map Row.case = cases.map Case.name
  | _, [] => rfl
  | i, c :: cs => by
    simp only [tableFrom, List.map_cons, tableFrom_cases res (i + 1) cs, List.cons.injEq, and_true]
    unfold Case.row; split <;> rfl

/-- **Every case appears exactly once, in order.** -/
theorem table_cases (res : Nat → Mode → Option Run) (cases : List Case) :
    (table res cases).map Row.case = cases.map Case.name := tableFrom_cases res 0 cases

def summary (rows : List Row) : String :=
  if rows.all (·.pass) then s!"cheat corpus: all {rows.length} cases behave as expected"
  else "cheat corpus: FAILURES (logs in .lake/cheats/)"

/-- The table the runner prints: a header, the rows, a blank line and a summary. -/
def report (rows : List Row) : List String := header :: rows.map Row.render ++ ["", summary rows]

def exitCode (rows : List Row) : UInt32 := if rows.all (·.pass) then 0 else 1

/-- **Exit code 0 exactly when every row passed.** -/
theorem exitCode_eq_zero_iff {rows : List Row} : exitCode rows = 0 ↔ ∀ r ∈ rows, r.pass = true := by
  unfold exitCode
  split
  · rename_i h; simpa using h
  · rename_i h; simp only [List.all_eq_true] at h; simp [h]

/-! ## Jobs -/

/-- One run to do: mode `mode` of the `case`-th case. `heavy` jobs run alone; `long` ones are
expected to reach the comparator, so they start first. -/
structure Job where
  case : Nat
  mode : Mode
  heavy : Bool
  long : Bool
  deriving DecidableEq, Repr

/-- Whether the run is expected to reach the comparator: a full run that gate 0 or 1 rejects does
not, nor a comparator-only run that gate 0 rejects. -/
def Expect.long (e : Expect) : Mode → Bool
  | .full => 2 ≤ e.full.num
  | .comparatorOnly => e.comparatorOnly != .rejectAt .provenance

def caseJobs (i : Nat) (c : Case) : List Job :=
  match c.expect with
  | .ok e =>
    [⟨i, .full, e.heavy, e.long .full⟩, ⟨i, .comparatorOnly, e.heavy, e.long .comparatorOnly⟩]
  | .error _ => []

def jobsFrom : Nat → List Case → List Job
  | _, [] => []
  | i, c :: cs => caseJobs i c ++ jobsFrom (i + 1) cs

/-- Both runs of every case whose `expect` parsed. -/
def jobs (cases : List Case) : List Job := jobsFrom 0 cases

theorem mem_caseJobs {i : Nat} {c : Case} {j : Job} :
    j ∈ caseJobs i c ↔
      j.case = i ∧ ∃ e, c.expect = .ok e ∧ j.heavy = e.heavy ∧ j.long = e.long j.mode := by
  unfold caseJobs
  split
  · rename_i e he
    obtain ⟨jc, jm, jh, jl⟩ := j
    cases jm <;> simp [he, eq_comm]
  · simp_all

theorem mem_jobsFrom {j : Job} : ∀ {i : Nat} {cases : List Case},
    j ∈ jobsFrom i cases ↔ i ≤ j.case ∧ ∃ c e, cases[j.case - i]? = some c ∧ c.expect = .ok e ∧
      j.heavy = e.heavy ∧ j.long = e.long j.mode
  | _, [] => by simp [jobsFrom]
  | i, c :: cs => by
    rw [jobsFrom, List.mem_append, mem_caseJobs, mem_jobsFrom]
    constructor
    · rintro (⟨hi, e, he, hh, hl⟩ | ⟨hi, c', e, hc', he, hh, hl⟩)
      · exact ⟨by omega, c, e, by simp [hi], he, hh, hl⟩
      · refine ⟨by omega, c', e, ?_, he, hh, hl⟩
        rw [show j.case - i = (j.case - (i + 1)) + 1 by omega]
        simpa using hc'
    · rintro ⟨hi, c', e, hc', he, hh, hl⟩
      by_cases h : j.case = i
      · left
        rw [h, Nat.sub_self] at hc'
        simp at hc'; subst hc'
        exact ⟨h, e, he, hh, hl⟩
      · right
        refine ⟨by omega, c', e, ?_, he, hh, hl⟩
        rw [show j.case - i = (j.case - (i + 1)) + 1 by omega] at hc'
        simpa using hc'

/-- **The jobs are the runs of the judged cases.** -/
theorem mem_jobs {cases : List Case} {j : Job} :
    j ∈ jobs cases ↔ ∃ c e, cases[j.case]? = some c ∧ c.expect = .ok e ∧
      j.heavy = e.heavy ∧ j.long = e.long j.mode := by
  simp [jobs, mem_jobsFrom]

theorem jobsFrom_case_ge :
    ∀ {i : Nat} {cases : List Case} {j : Job}, j ∈ jobsFrom i cases → i ≤ j.case
  | _, _, _, h => (mem_jobsFrom.mp h).1

theorem jobsFrom_nodup : ∀ (i : Nat) (cases : List Case), (jobsFrom i cases).Nodup
  | _, [] => List.nodup_nil
  | i, c :: cs => by
    rw [jobsFrom, List.nodup_append]
    refine ⟨?_, jobsFrom_nodup (i + 1) cs, ?_⟩
    · unfold caseJobs; split <;> simp
    · intro a ha b hb hab
      have := jobsFrom_case_ge hb
      rw [← hab, (mem_caseJobs.mp ha).1] at this
      omega

/-- **No run is a job twice.** -/
theorem jobs_nodup (cases : List Case) : (jobs cases).Nodup := jobsFrom_nodup 0 cases

/-- Heavy jobs first, then the long ones, then the rest, each group in case order. -/
def Job.rank (j : Job) : Nat := if j.heavy then 0 else if j.long then 1 else 2

/-- The order jobs start in. -/
def order (js : List Job) : List Job := js.mergeSort fun a b => a.rank ≤ b.rank

/-- **Ordering keeps every job, once.** -/
theorem order_perm (js : List Job) : (order js).Perm js := List.mergeSort_perm _ _

/-! ## The scheduler

The runner starts jobs from the front of `pending` while `mayStart` allows, and otherwise waits
for a running job to finish. `Reach` is every state that can reach, whatever order the runs
finish in. -/

structure Sched (α : Type) where
  pending : List α
  running : List α
  done : List α

def Sched.init {α : Type} (jobs : List α) : Sched α := ⟨jobs, [], []⟩

/-- Whether `j` may start while `running` runs: a heavy job only when nothing runs, any other job
when fewer than `n` run and none of them is heavy. -/
def mayStart {α : Type} (n : Nat) (heavy : α → Bool) (running : List α) (j : α) : Bool :=
  if heavy j then running.isEmpty else running.length < n && !running.any heavy

/-- Start the first pending job, if it may start. -/
def Sched.start? {α : Type} (n : Nat) (heavy : α → Bool) (s : Sched α) : Option (α × Sched α) :=
  match s.pending with
  | j :: rest => if mayStart n heavy s.running j then some (j, ⟨rest, s.running ++ [j], s.done⟩) else none
  | [] => none

/-- `j`, a running job, finished. -/
def Sched.finish {α : Type} [BEq α] (s : Sched α) (j : α) : Sched α :=
  ⟨s.pending, s.running.erase j, s.done ++ [j]⟩

/-- The states the runner can be in, from `Sched.init jobs`, whatever order runs finish in. -/
inductive Reach {α : Type} [BEq α] (n : Nat) (heavy : α → Bool) (jobs : List α) : Sched α → Prop
  | init : Reach n heavy jobs (.init jobs)
  | start {s s' : Sched α} {j : α} : Reach n heavy jobs s → s.start? n heavy = some (j, s') →
      Reach n heavy jobs s'
  | finish {s : Sched α} {j : α} : Reach n heavy jobs s → j ∈ s.running →
      Reach n heavy jobs (s.finish j)

/-- What holds in every state the runner can reach. -/
structure Inv {α : Type} (n : Nat) (heavy : α → Bool) (jobs : List α) (s : Sched α) : Prop where
  /-- The jobs started so far are the first `k` jobs, and each is running or done, once. -/
  fifo : ∃ k, s.pending = jobs.drop k ∧ (s.done ++ s.running).Perm (jobs.take k)
  /-- At most `n` jobs run at once. -/
  atMost : s.running.length ≤ n
  /-- A heavy job runs alone. -/
  alone : ∀ j ∈ s.running, heavy j = true → s.running = [j]

theorem Sched.start?_eq_some {α : Type} {n : Nat} {heavy : α → Bool} {s s' : Sched α} {j : α}
    (h : s.start? n heavy = some (j, s')) :
    ∃ rest, s.pending = j :: rest ∧ mayStart n heavy s.running j = true ∧
      s' = ⟨rest, s.running ++ [j], s.done⟩ := by
  unfold Sched.start? at h
  split at h
  · rename_i j' rest hp
    split at h
    · cases h; exact ⟨rest, hp, by assumption, rfl⟩
    · cases h
  · cases h

/-- **The invariant holds in every reachable state.** -/
theorem Reach.inv {α : Type} [BEq α] [LawfulBEq α] {n : Nat} {heavy : α → Bool} {jobs : List α}
    {s : Sched α} (hn : 1 ≤ n) (h : Reach n heavy jobs s) : Inv n heavy jobs s := by
  induction h with
  | init => exact ⟨⟨0, by simp [Sched.init], by simp [Sched.init]⟩, by simp [Sched.init],
      by simp [Sched.init]⟩
  | @start s s' j _ hs ih =>
    obtain ⟨rest, hp, hm, rfl⟩ := Sched.start?_eq_some hs
    obtain ⟨⟨k, hk, hperm⟩, hat, hal⟩ := ih
    rw [hk] at hp
    have hj : jobs[k]? = some j := by rw [← List.head?_drop, hp]; rfl
    refine ⟨⟨k + 1, ?_, ?_⟩, ?_, ?_⟩
    · show rest = jobs.drop (k + 1)
      rw [show k + 1 = k + 1 from rfl, ← List.drop_drop, hp]; rfl
    · show (s.done ++ (s.running ++ [j])).Perm (jobs.take (k + 1))
      rw [List.take_add_one, hj, ← List.append_assoc]
      exact hperm.append_right [j]
    · show (s.running ++ [j]).length ≤ n
      simp only [List.length_append, List.length_cons, List.length_nil]
      unfold mayStart at hm
      split at hm
      · simp only [List.isEmpty_iff] at hm; simp [hm]; omega
      · simp only [Bool.and_eq_true, decide_eq_true_eq] at hm; omega
    · show ∀ x ∈ s.running ++ [j], heavy x = true → s.running ++ [j] = [x]
      intro x hx hhx
      simp only [List.mem_append, List.mem_singleton] at hx
      unfold mayStart at hm
      split at hm
      · simp only [List.isEmpty_iff] at hm
        rw [hm] at hx ⊢
        simp at hx; subst hx; rfl
      · rename_i hjh
        simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true', List.any_eq_false] at hm
        rcases hx with hx | rfl
        · exact absurd hhx (by simpa using hm.2 x hx)
        · exact absurd hhx hjh
  | @finish s j _ hj ih =>
    obtain ⟨⟨k, hk, hperm⟩, hat, hal⟩ := ih
    refine ⟨⟨k, hk, ?_⟩, ?_, ?_⟩
    · show (s.done ++ [j] ++ s.running.erase j).Perm (jobs.take k)
      rw [List.append_assoc, List.singleton_append]
      exact ((List.perm_cons_erase hj).symm.append_left s.done).trans hperm
    · show (s.running.erase j).length ≤ n
      exact Nat.le_trans List.length_erase_le hat
    · show ∀ x ∈ s.running.erase j, heavy x = true → s.running.erase j = [x]
      intro x hx hhx
      have hrx := hal x (List.mem_of_mem_erase hx) hhx
      rw [hrx] at hj hx
      simp only [List.mem_singleton] at hj
      subst hj
      simp at hx

/-- **Progress.** While nothing runs, the first pending job can start. -/
theorem start?_isSome {α : Type} {n : Nat} {heavy : α → Bool} {s : Sched α} (hn : 1 ≤ n)
    (hr : s.running = []) (hp : s.pending ≠ []) : (s.start? n heavy).isSome := by
  unfold Sched.start?
  cases h : s.pending with
  | nil => exact absurd h hp
  | cons j rest =>
    simp only [mayStart, hr, List.isEmpty_nil, List.length_nil, List.any_nil, Bool.not_false,
      Bool.and_true]
    split <;> simp <;> omega

/-- The runner's measure: two for each pending job, one for each running job. -/
def Sched.measure {α : Type} (s : Sched α) : Nat := 2 * s.pending.length + s.running.length

theorem start?_measure {α : Type} {n : Nat} {heavy : α → Bool} {s s' : Sched α} {j : α}
    (h : s.start? n heavy = some (j, s')) : s'.measure < s.measure := by
  obtain ⟨rest, hp, -, rfl⟩ := Sched.start?_eq_some h
  simp [Sched.measure, hp]; omega

theorem finish_measure {α : Type} [BEq α] [LawfulBEq α] {s : Sched α} {j : α} (hj : j ∈ s.running) :
    (s.finish j).measure < s.measure := by
  simp only [Sched.measure, Sched.finish, List.length_erase_of_mem hj]
  have := List.length_pos_of_mem hj
  omega

/-- **Every job runs, once.** When the runner stops, because nothing runs and nothing can start,
nothing is pending and every job is done exactly once. -/
theorem Reach.complete {α : Type} [BEq α] [LawfulBEq α] {n : Nat} {heavy : α → Bool}
    {jobs : List α} {s : Sched α} (hn : 1 ≤ n) (h : Reach n heavy jobs s) (hr : s.running = [])
    (hs : s.start? n heavy = none) : s.pending = [] ∧ s.done.Perm jobs := by
  have hp : s.pending = [] := by
    cases hpe : s.pending with
    | nil => rfl
    | cons j rest =>
      have := start?_isSome (heavy := heavy) hn hr (by simp [hpe])
      simp [hs] at this
  obtain ⟨⟨k, hk, hperm⟩, -, -⟩ := h.inv hn
  refine ⟨hp, ?_⟩
  rw [hr, List.append_nil] at hperm
  rw [hp] at hk
  have : jobs.take k = jobs := List.take_of_length_le (List.drop_eq_nil_iff.mp hk.symm)
  rw [this] at hperm
  exact hperm

/-- **The runner runs both runs of every judged case, each once.** When `mitos-gate cheats` stops
scheduling `order (jobs cases)`, the runs done are the jobs, each once. -/
theorem runner_done {n : Nat} {cases : List Case} {s : Sched Job} (hn : 1 ≤ n)
    (h : Reach n Job.heavy (order (jobs cases)) s) (hr : s.running = [])
    (hs : s.start? n Job.heavy = none) : s.done.Perm (jobs cases) ∧ s.done.Nodup := by
  have hp := (h.complete hn hr hs).2.trans (order_perm _)
  exact ⟨hp, hp.nodup_iff.mpr (jobs_nodup cases)⟩

end MitosGate.Cheats
