import MitosGate.GateId
import MitosGate.Lint
import MitosGate.Util

namespace MitosGate.Cheats

open Accept (GateId Cause)

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

def splitLines (cs : List Char) : List (List Char) := go cs []
where
  go : List Char → List Char → List (List Char)
    | [], acc => [acc.reverse]
    | c :: cs, acc => if c = '\n' then acc.reverse :: go cs [] else go cs (c :: acc)

def printed (ls : List String) : List Char := ls.flatMap fun l => l.toList ++ ['\n']

theorem splitLines_go_append {l rest acc : List Char} (h : '\n' ∉ l) :
    splitLines.go (l ++ '\n' :: rest) acc = (acc.reverse ++ l) :: splitLines.go rest [] := by
  induction l generalizing acc with
  | nil => simp [splitLines.go]
  | cons c l ih =>
    simp only [List.mem_cons, not_or] at h
    have hc : ¬ c = '\n' := fun e => h.1 e.symm
    simp [splitLines.go, hc, ih h.2]

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

inductive Verdict
  | accepted
  | rejected (g : GateId) (cause : Cause)
  | unrecorded (why : String)
  deriving DecidableEq, Repr

structure VerdictLine where
  private mk ::
  text : String

def VerdictLine.bytes (l : VerdictLine) : List Char := l.text.toList

instance : ToString VerdictLine where
  toString l := l.text

def Verdict.exitCode : Verdict → UInt32
  | .accepted => 0
  | _ => 1

def acceptedLine : List Char := "VERDICT: ACCEPTED".toList
def gateTag : List Char := "VERDICT: REJECTED (gate ".toList
def recordTag : List Char := "VERDICT: REJECTED (record: ".toList

def causeBytes : Cause → List Char
  | .judged => [')']
  | .ioError => ": I/O error)".toList

theorem ciLine_empty : ciLine "" = "" := by decide

theorem ciLine_ioError : ciLine "I/O error" = "I/O error" := by decide

def Verdict.render : Verdict → VerdictLine
  | .accepted => .mk "VERDICT: ACCEPTED"
  | .rejected g c =>
    .mk <| "VERDICT: REJECTED (gate " ++ toString g.num ++ ": " ++ g.name ++
      (match c with
        | .judged => ""
        | .ioError => ": " ++ ciLine "I/O error") ++ ")"
  | .unrecorded why => .mk <| "VERDICT: REJECTED (record: " ++ why ++ ")"

theorem Verdict.render_bytes (v : Verdict) : v.render.bytes = match v with
    | .accepted => acceptedLine
    | .rejected g c => gateTag ++ (toString g.num ++ ": " ++ g.name).toList ++ causeBytes c
    | .unrecorded why => recordTag ++ why.toList ++ [')'] := by
  cases v with
  | accepted => simp [Verdict.render, VerdictLine.bytes, acceptedLine]
  | rejected g c =>
    cases c with
    | judged =>
      simp [Verdict.render, VerdictLine.bytes, gateTag, causeBytes, String.toList_append,
        List.append_assoc]
    | ioError =>
      simp [Verdict.render, VerdictLine.bytes, gateTag, causeBytes, ciLine_ioError,
        String.toList_append, List.append_assoc]
  | unrecorded why =>
    simp [Verdict.render, VerdictLine.bytes, recordTag, String.toList_append]

example : (Verdict.rejected .adequacy .ioError).render.bytes =
    "VERDICT: REJECTED (gate 6: model adequacy: I/O error)".toList := by
  rw [Verdict.render_bytes]; decide

example : (Verdict.rejected .lint .judged).render.bytes =
    "VERDICT: REJECTED (gate 1: lint)".toList := by
  rw [Verdict.render_bytes]; decide

example : toString (Verdict.rejected .lint .judged).render =
    "VERDICT: REJECTED (gate 1: lint)" := by decide

def gateOf? (cs : List Char) : Option (GateId × List Char) :=
  GateId.all.findSome? fun g => (stripPrefix? (toString g.num ++ ": " ++ g.name).toList cs).map (g, ·)

theorem causeBytes_ne : causeBytes .judged ≠ causeBytes .ioError := by decide

def causeOf? (cs : List Char) : Option Cause :=
  if cs = causeBytes .judged then some .judged
  else if cs = causeBytes .ioError then some .ioError
  else none

def Verdict.parseChars (cs : List Char) : Option Verdict :=
  if cs = acceptedLine then some .accepted
  else match stripPrefix? gateTag cs with
    | some rest =>
      match gateOf? rest with
      | some (g, tail) => (causeOf? tail).map (.rejected g)
      | none => none
    | none =>
      match stripPrefix? recordTag cs with
      | some rest => if rest.getLast? = some ')' then some (.unrecorded (String.ofList rest.dropLast)) else none
      | none => none

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

theorem causeOf?_eq_some_iff {cs : List Char} {c : Cause} :
    causeOf? cs = some c ↔ cs = causeBytes c := by
  cases c with
  | judged =>
    by_cases h : cs = causeBytes .judged <;> simp [causeOf?, h]
  | ioError =>
    by_cases h : cs = causeBytes .judged <;> by_cases h2 : cs = causeBytes .ioError <;>
      simp [causeOf?, h, h2, causeBytes_ne, causeBytes_ne.symm]

theorem VerdictLine.toString_bytes (l : VerdictLine) : (toString l).toList = l.bytes := by
  rfl

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

theorem Verdict.parse_eq_some_iff {l : String} {v : Verdict} :
    Verdict.parse l = some v ↔ l.toList = v.render.bytes := by
  constructor
  · intro h
    rw [render_bytes]
    simp only [Verdict.parse, Verdict.parseChars] at h
    split at h
    · rename_i hacc; cases h; exact hacc
    · split at h
      · rename_i rest hrest
        split at h
        · rename_i g tail hg
          obtain ⟨c, hc, rfl⟩ := Option.map_eq_some_iff.mp h
          rw [stripPrefix?_eq_some_iff.mp hrest, gateOf?_eq_some hg, causeOf?_eq_some_iff.mp hc]
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
  · intro h
    simp only [Verdict.parse, Verdict.parseChars, h, render_bytes]
    cases v with
    | accepted => simp
    | rejected g c =>
      simp only [List.append_assoc, gateTag_ne_accepted, ↓reduceIte, stripPrefix?_append,
        gateOf?_render]
      simp [causeOf?_eq_some_iff.mpr rfl]
    | unrecorded why =>
      simp only [List.append_assoc, recordTag_ne_accepted, ↓reduceIte, stripPrefix?_gateTag_recordTag,
        stripPrefix?_append]
      simp

theorem Verdict.parse_render (v : Verdict) : Verdict.parse (toString v.render) = some v :=
  Verdict.parse_eq_some_iff.mpr (VerdictLine.toString_bytes v.render)

def isVerdictLine (l : List Char) : Bool := "VERDICT:".toList.isPrefixOf l

def verdictLines (out : String) : List (List Char) := (splitLines out.toList).filter isVerdictLine

def readVerdict (out : String) : Option Verdict :=
  match verdictLines out with
  | [l] => Verdict.parseChars l
  | _ => none

theorem readVerdict_eq_none {out : String} (h : (verdictLines out).length ≠ 1) :
    readVerdict out = none := by
  unfold readVerdict
  split
  · rename_i l hl; simp [hl] at h
  · rfl

theorem isVerdictLine_render (v : Verdict) : isVerdictLine v.render.bytes = true := by
  rw [Verdict.render_bytes]
  cases v with
  | accepted => simp [isVerdictLine, acceptedLine, List.isPrefixOf]
  | rejected g c =>
    cases c <;> simp [isVerdictLine, gateTag, causeBytes, List.isPrefixOf]
  | unrecorded _ => simp [isVerdictLine, recordTag, List.isPrefixOf]

theorem readVerdict_printed {pre : List String} {v : Verdict} {rest : List Char}
    (hpre : ∀ l ∈ pre, '\n' ∉ l.toList ∧ isVerdictLine l.toList = false)
    (hv : '\n' ∉ v.render.bytes) (hrest : ∀ l ∈ splitLines rest, isVerdictLine l = false) :
    readVerdict (String.ofList (printed (pre ++ [toString v.render]) ++ rest)) = some v := by
  have hline : (toString v.render).toList = v.render.bytes := VerdictLine.toString_bytes v.render
  have hsplit := splitLines_printed_append (ls := pre ++ [toString v.render]) (rest := rest)
    (fun l hl => by
      rcases List.mem_append.mp hl with h | h
      · exact (hpre l h).1
      · simp at h; subst h; rw [hline]; exact hv)
  have : verdictLines (String.ofList (printed (pre ++ [toString v.render]) ++ rest)) =
      [v.render.bytes] := by
    simp only [verdictLines, String.toList_ofList, hsplit, List.map_append, List.map_cons,
      List.map_nil, List.filter_append, List.filter_cons, hline, isVerdictLine_render, ↓reduceIte,
      List.filter_nil]
    rw [List.filter_eq_nil_iff.mpr, List.filter_eq_nil_iff.mpr]
    · simp
    · intro l hl; simp [hrest l hl]
    · intro l hl
      obtain ⟨s, hs, rfl⟩ := List.mem_map.mp hl
      simp [(hpre s hs).2]
  simp only [readVerdict, this]
  exact Verdict.parse_render v

def Verdict.ofGate : Except (GateId × Cause) (Option String) → Verdict
  | .ok none => .accepted
  | .ok (some e) => .unrecorded (ciLine e)
  | .error (g, cause) => .rejected g cause

theorem hasLegacy_append_singleton {c : Char} (hc : c ≠ '[') (l : List Char) :
    hasLegacy (l ++ [c]) = hasLegacy l := by
  induction l with
  | nil => simp [hasLegacy]
  | cons a l ih =>
    have : ((l ++ [c]).take 2 == ['#', '[']) = (l.take 2 == ['#', '[']) := by
      rcases l with _ | ⟨x, _ | ⟨y, r⟩⟩ <;> simp [hc]
    rw [List.cons_append, hasLegacy, hasLegacy, ih, this]

theorem Verdict.ofGate_render_bytes (o : Except (GateId × Cause) (Option String)) :
    (Verdict.ofGate o).render.bytes = acceptedLine ∨
      ∃ pre s, (Verdict.ofGate o).render.bytes = pre ++ (ciLine s).toList ++ [')'] ∧
        pre.head? = some 'V' ∧ (∀ x ∈ pre, x ≠ '#' ∧ printable x = true) := by
  rcases o with ⟨g, c⟩ | _ | e
  · right
    rw [Verdict.ofGate, render_bytes]
    cases c with
    | judged =>
      refine ⟨gateTag ++ (toString g.num ++ ": " ++ g.name).toList, "", ?_, ?_, ?_⟩
      · simp [causeBytes, ciLine_empty]
      · cases g <;> decide
      · cases g <;> decide
    | ioError =>
      refine ⟨gateTag ++ (toString g.num ++ ": " ++ g.name).toList ++ [':', ' '], "I/O error",
        ?_, ?_, ?_⟩
      · simp [causeBytes, ciLine_ioError, String.toList_append]
      · cases g <;> decide
      · cases g <;> decide
  · left
    rw [Verdict.ofGate, render_bytes]
  · right
    refine ⟨recordTag, e, ?_, by decide, by decide⟩
    rw [Verdict.ofGate, render_bytes]

theorem Verdict.ofGate_not_startsCommand (o : Except (GateId × Cause) (Option String)) :
    ¬ startsCommand (toString (Verdict.ofGate o).render) := by
  unfold startsCommand
  rw [VerdictLine.toString_bytes]
  rcases Verdict.ofGate_render_bytes o with h | ⟨pre, s, h, hV, hpre⟩
  · rw [h]; decide +kernel
  · rw [h]
    rintro (hp | hl)
    · obtain ⟨rest, rfl⟩ : ∃ rest, pre = 'V' :: rest := by
        cases pre with
        | nil => simp at hV
        | cons a rest => simp at hV; exact ⟨rest, by rw [hV]⟩
      simp only [List.cons_append, List.dropWhile_cons, show runnerBlank 'V' = false by decide,
        Bool.false_eq_true, ↓reduceIte] at hp
      simp at hp
    · rw [← hasLegacy_iff, List.append_assoc, hasLegacy_append (fun x hx => (hpre x hx).1),
        hasLegacy_append_singleton (by decide), ciLine, String.toList_ofList, ciChars_legacy] at hl
      exact Bool.false_ne_true hl

theorem Verdict.ofGate_printable (o : Except (GateId × Cause) (Option String)) :
    ∀ x ∈ (Verdict.ofGate o).render.bytes, printable x = true ∨ x = '\\' := by
  rcases Verdict.ofGate_render_bytes o with h | ⟨pre, s, h, -, hpre⟩
  · rw [h]; decide
  · rw [h]
    intro x hx
    simp only [List.mem_append, List.mem_singleton] at hx
    rcases hx with (hx | hx) | rfl
    · exact .inl (hpre x hx).2
    · exact ciLine_printable s x hx
    · exact .inl (by decide)

theorem Verdict.ofGate_no_break (o : Except (GateId × Cause) (Option String)) :
    ∀ c ∈ ['\n', '\x0b', '\x0c', '\r', '\u0085', ' ', ' '],
      c ∉ (Verdict.ofGate o).render.bytes := by
  have key : ∀ c ∈ ['\n', '\x0b', '\x0c', '\r', '\u0085', ' ', ' '],
      ¬(printable c = true ∨ c = '\\') := by decide
  intro c hc hmem
  exact key c hc (Verdict.ofGate_printable o c hmem)

example : (Verdict.ofGate (.error (.adequacy, .ioError))).render.bytes =
    "VERDICT: REJECTED (gate 6: model adequacy: I/O error)".toList := by
  rw [Verdict.ofGate, Verdict.render_bytes]; decide

example : (Verdict.ofGate (.error (.lint, .judged))).render.bytes =
    "VERDICT: REJECTED (gate 1: lint)".toList := by
  rw [Verdict.ofGate, Verdict.render_bytes]; decide

/-- A hostile record error: the legacy form and a newline before a command are escaped. The record
line stays `VERDICT: REJECTED (record: <escaped error>)`. -/
example : (Verdict.ofGate (.ok (some "##[warning]x\n::error::y"))).render.bytes =
    "VERDICT: REJECTED (record: ##\\u{005B}warning]x\\u{000A}::error::y)".toList := by
  rw [Verdict.ofGate, Verdict.render_bytes]; decide

example :
    let v := Verdict.ofGate (.ok (some "a\nb"))
    let line := String.ofList v.render.bytes
    ciLine line ≠ line ∧
      Verdict.parse (ciLine line) = some (.unrecorded (ciLine (ciLine "a\nb"))) ∧
      Verdict.parse (ciLine line) ≠ some v := by
  decide

structure Run where
  exitCode : UInt32
  output : String
  timedOut : Bool
  deriving Inhabited, Repr

def noRun : Run := { exitCode := 255, output := "", timedOut := false }

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

def Run.shown (r : Run) : String :=
  match r.verdict with
  | some .accepted => "ACCEPTED"
  | some (.rejected g _) => s!"REJECTED@{g.num}"
  | some (.unrecorded _) => "REJECTED@record"
  | none => if r.timedOut then "TIMEOUT" else "NO-VERDICT"

inductive CompExpect
  | accept
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

def gateOfNum? (s : String) : Option GateId := GateId.all.find? (toString ·.num == s)

theorem gateOfNum?_num (g : GateId) : gateOfNum? (toString g.num) = some g := by
  cases g <;> decide

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

def Key.single (k : Key) : Bool := k != .lockAppend

def guardIds : List String :=
  ((Lint.Rule.fixed ++ Lint.banned.map Lint.Rule.banned).filter Lint.Rule.guardable).map Lint.Rule.id

theorem newline_not_mem_guardIds : ∀ r ∈ guardIds, '\n' ∉ r.toList := by decide +kernel

structure Expect where
  full : GateId
  comparatorOnly : CompExpect
  modelApproved : Bool := false
  heavy : Bool := false
  lockAppend : List String := []
  why : Option String := none
  guards : Option String := none
  deriving DecidableEq, Repr

def tagged (k : Key) (vs : List String) : List (Key × String) := vs.map (k, ·)

def Expect.fields (e : Expect) : List (Key × String) :=
  tagged .full [toString e.full.num] ++ tagged .comparatorOnly [e.comparatorOnly.render] ++
    tagged .modelApproved (if e.modelApproved then ["yes"] else []) ++
    tagged .heavy (if e.heavy then ["yes"] else []) ++ tagged .lockAppend e.lockAppend ++
    tagged .why e.why.toList ++ tagged .guards e.guards.toList

def fieldLine (f : Key × String) : String := f.1.name ++ "=" ++ f.2

def Expect.render (e : Expect) : String := String.join (e.fields.map fun f => fieldLine f ++ "\n")

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

def fileLines (txt : String) : List (List Char) :=
  let ls := splitLines txt.toList
  if ls.getLast? = some [] then ls.dropLast else ls

def get (fs : List (Key × String)) (k : Key) : Option String := (fs.find? (·.1 == k)).map (·.2)

def flag (fs : List (Key × String)) (k : Key) : Except String Bool :=
  match get fs k with
  | none => .ok false
  | some "yes" => .ok true
  | some v => .error s!"{k.name}={v}: the only value is yes"

def lockLines (fs : List (Key × String)) : List String :=
  fs.filterMap fun f => if f.1 = .lockAppend then some f.2 else none

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

def Expect.parse (txt : String) : Except String Expect :=
  match (fileLines txt).mapM parseLine with
  | .ok fs => ofFields fs
  | .error e => .error e

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

theorem Expect.parse_render (e : Expect) (hv : e.Valid) : Expect.parse e.render = .ok e := by
  unfold Expect.parse
  rw [Expect.fileLines_render e hv,
    mapM_map_ok (fun f hf => parseLine_fieldLine f (e.newline_not_mem_fields hv f hf))]
  exact ofFields_fields e hv

example : (Expect.parse "full=1\ncomparator_only=reject@4\nwhy=Uses `admit`.\n").toOption =
    some { full := .lint, comparatorOnly := .rejectAt .axioms, why := some "Uses `admit`." } := by
  decide +kernel
example : (Expect.parse "full=1\nfull=1\ncomparator_only=accept\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\nheavy=no\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\nfull_exp=2\n").toBool = false := by
  decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\n\n").toBool = false := by decide +kernel
example : (Expect.parse "full=01\ncomparator_only=accept\n").toBool = false := by decide +kernel
example : (Expect.parse "full=1\ncomparator_only=accept\nguards=parse\n").toBool = false := by
  decide +kernel
example : ((Expect.parse "full=0\ncomparator_only=reject@0\nlock_append=a\nlock_append=b\n").toOption.map
    (·.lockAppend)) = some ["a", "b"] := by decide +kernel

def failTag : List Char := (GateId.lint.label ++ ": FAIL").toList

def violationCount (l : List Char) : Option Nat := do
  let r ← stripPrefix? (failTag ++ " — ".toList) l
  let d ← (stripPrefix? " violation(s)".toList.reverse r.reverse).map List.reverse
  if d ≠ [] ∧ d.all Char.isDigit then some (d.foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0)
  else none

def ruleOf (l : List Char) : String :=
  match l.reverse with
  | ']' :: rest =>
    let x := rest.takeWhile fun c => c ≠ '[' ∧ c ≠ ']' ∧ c ≠ ' '
    match rest.drop x.length with
    | '[' :: ' ' :: _ => "[" ++ String.ofList x.reverse ++ "]"
    | _ => "no rule"
  | _ => "no rule"

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

def evalCommandLog : String := "GATE 0 provenance: PASS
GATE 1 lint: FAIL — 1 violation(s)
  /tmp/tmp.tZhcUv3lgT/Plugins/ToyRequire.lean:8:1: command `#eval` is not allowed [hash]
VERDICT: REJECTED (gate 1: lint)
"

example : readVerdict evalCommandLog = some (.rejected .lint .judged) := by decide +kernel
example : guardsWhy "hash" .accept evalCommandLog = "" := by decide +kernel
example : guardsWhy "banned:sorry" .accept evalCommandLog =
    "the full run also has violations [hash]" := by decide +kernel
example : guardsWhy "hash" (.rejectAt .axioms) evalCommandLog =
    "it is not comparator_only=accept" := by decide +kernel
example : guardsWhy "hash" .accept "GATE 1 lint: FAIL — 2 violation(s)
  Plugins/ToyRequire.lean:8:1: command `#eval` is not allowed [hash]
VERDICT: REJECTED (gate 1: lint)
" = "gate 1 counts 2 violations and lists 1" := by decide +kernel
example : guardsWhy "hash" .accept "VERDICT: REJECTED (gate 3: statements)\n" =
    "the full run reports no gate-1 violation" := by decide +kernel

def guardText (rule why : String) : String :=
  "guards=" ++ rule ++ (if why = "" then "" else ": " ++ why)

def fullOk (g : GateId) : Option Verdict → Bool
  | some (.rejected g' .judged) => g' == g
  | _ => false

def CompExpect.ok : CompExpect → Option Verdict → Bool
  | .accept, some .accepted => true
  | .reject, some (.rejected _ .judged) => true
  | .rejectAt g, some (.rejected g' .judged) => g' == g
  | _, _ => false

example : fullOk .adequacy (some (.rejected .adequacy .ioError)) = false := by decide
example : fullOk .adequacy (some (.rejected .adequacy .judged)) = true := by decide
example : CompExpect.ok .reject (some (.rejected .lint .ioError)) = false := by decide
example : CompExpect.ok (.rejectAt .adequacy) (some (.rejected .adequacy .ioError)) = false := by decide
example : CompExpect.ok (.rejectAt .adequacy) (some (.rejected .adequacy .judged)) = true := by decide

def guardsOk (e : Expect) (full : Run) : Bool :=
  match e.guards with
  | none => true
  | some r => guardsWhy r e.comparatorOnly full.output == ""

def pad (n : Nat) (s : String) : String := s ++ String.ofList (List.replicate (n - s.length) ' ')

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

def judge (case : String) (e : Expect) (full comp : Run) : Row :=
  let guard := match e.guards with
    | none => ""
    | some r => guardText r (guardsWhy r e.comparatorOnly full.output)
  { case
    text := pad 14 full.shown ++ " " ++ pad 14 ("@" ++ toString e.full.num) ++ " " ++
      pad 22 comp.shown ++ " " ++ pad 10 e.comparatorOnly.render ++ " " ++ guard
    pass := fullOk e.full full.verdict && e.comparatorOnly.ok comp.verdict && guardsOk e full }

def CompExpect.Holds : CompExpect → Option Verdict → Prop
  | .accept, v => v = some .accepted
  | .reject, v => ∃ g, v = some (.rejected g .judged)
  | .rejectAt g, v => v = some (.rejected g .judged)

theorem judge_pass_iff {case : String} {e : Expect} {full comp : Run} :
    (judge case e full comp).pass = true ↔
      full.verdict = some (.rejected e.full .judged) ∧ e.comparatorOnly.Holds comp.verdict ∧
        ∀ r, e.guards = some r → guardsWhy r e.comparatorOnly full.output = "" := by
  simp only [judge, Bool.and_eq_true, and_assoc]
  apply and_congr
  · generalize full.verdict = v
    rcases v with _ | _ | ⟨g, c⟩ | _
    · simp [fullOk]
    · simp [fullOk]
    · cases c <;> simp [fullOk, beq_iff_eq]
    · simp [fullOk]
  · apply and_congr
    · generalize comp.verdict = v
      rcases v with _ | _ | ⟨g, c⟩ | _
      · cases e.comparatorOnly <;> simp [CompExpect.ok, CompExpect.Holds]
      · cases e.comparatorOnly <;> simp [CompExpect.ok, CompExpect.Holds]
      · cases c <;> cases e.comparatorOnly <;> simp [CompExpect.ok, CompExpect.Holds, beq_iff_eq]
      · cases e.comparatorOnly <;> simp [CompExpect.ok, CompExpect.Holds]
    · unfold guardsOk
      split <;> simp_all

def ioAtAdequacy : Run :=
  { exitCode := 1
    output := "VERDICT: REJECTED (gate 6: model adequacy: I/O error)\n"
    timedOut := false }

def judgedAtAdequacy : Run :=
  { exitCode := 1
    output := "VERDICT: REJECTED (gate 6: model adequacy)\n"
    timedOut := false }

example : (judge "wrong cause" { full := .adequacy, comparatorOnly := .reject }
    ioAtAdequacy judgedAtAdequacy).pass = false := by decide

example : (judge "judged" { full := .adequacy, comparatorOnly := .reject }
    judgedAtAdequacy judgedAtAdequacy).pass = true := by decide

structure Case where
  name : String
  expect : Except String Expect

inductive Mode
  | full | comparatorOnly
  deriving DecidableEq, Repr

def Mode.logName : Mode → String
  | .full => "full"
  | .comparatorOnly => "comparator"

def Case.row (c : Case) (full comp : Option Run) : Row :=
  match c.expect with
  | .error msg => { case := c.name, text := msg, pass := false }
  | .ok e => judge c.name e (full.getD noRun) (comp.getD noRun)

def tableFrom (res : Nat → Mode → Option Run) : Nat → List Case → List Row
  | _, [] => []
  | i, c :: cs => c.row (res i .full) (res i .comparatorOnly) :: tableFrom res (i + 1) cs

def table (res : Nat → Mode → Option Run) (cases : List Case) : List Row := tableFrom res 0 cases

theorem tableFrom_cases (res : Nat → Mode → Option Run) :
    ∀ (i : Nat) (cases : List Case), (tableFrom res i cases).map Row.case = cases.map Case.name
  | _, [] => rfl
  | i, c :: cs => by
    simp only [tableFrom, List.map_cons, tableFrom_cases res (i + 1) cs, List.cons.injEq, and_true]
    unfold Case.row; split <;> rfl

theorem table_cases (res : Nat → Mode → Option Run) (cases : List Case) :
    (table res cases).map Row.case = cases.map Case.name := tableFrom_cases res 0 cases

def summary (rows : List Row) : String :=
  if rows.all (·.pass) then s!"cheat corpus: all {rows.length} cases behave as expected"
  else "cheat corpus: FAILURES (logs in .lake/cheats/)"

def report (rows : List Row) : List String := header :: rows.map Row.render ++ ["", summary rows]

def exitCode (rows : List Row) : UInt32 := if rows.all (·.pass) then 0 else 1

theorem exitCode_eq_zero_iff {rows : List Row} : exitCode rows = 0 ↔ ∀ r ∈ rows, r.pass = true := by
  unfold exitCode
  split
  · rename_i h; simpa using h
  · rename_i h; simp only [List.all_eq_true] at h; simp [h]

structure Job where
  case : Nat
  mode : Mode
  heavy : Bool
  long : Bool
  deriving DecidableEq, Repr

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

theorem jobs_nodup (cases : List Case) : (jobs cases).Nodup := jobsFrom_nodup 0 cases

def Job.rank (j : Job) : Nat := if j.heavy then 0 else if j.long then 1 else 2

def order (js : List Job) : List Job := js.mergeSort fun a b => a.rank ≤ b.rank

theorem order_perm (js : List Job) : (order js).Perm js := List.mergeSort_perm _ _

structure Sched (α : Type) where
  pending : List α
  running : List α
  done : List α

def Sched.init {α : Type} (jobs : List α) : Sched α := ⟨jobs, [], []⟩

def mayStart {α : Type} (n : Nat) (heavy : α → Bool) (running : List α) (j : α) : Bool :=
  if heavy j then running.isEmpty else running.length < n && !running.any heavy

def Sched.start? {α : Type} (n : Nat) (heavy : α → Bool) (s : Sched α) : Option (α × Sched α) :=
  match s.pending with
  | j :: rest => if mayStart n heavy s.running j then some (j, ⟨rest, s.running ++ [j], s.done⟩) else none
  | [] => none

def Sched.finish {α : Type} [BEq α] (s : Sched α) (j : α) : Sched α :=
  ⟨s.pending, s.running.erase j, s.done ++ [j]⟩

inductive Reach {α : Type} [BEq α] (n : Nat) (heavy : α → Bool) (jobs : List α) : Sched α → Prop
  | init : Reach n heavy jobs (.init jobs)
  | start {s s' : Sched α} {j : α} : Reach n heavy jobs s → s.start? n heavy = some (j, s') →
      Reach n heavy jobs s'
  | finish {s : Sched α} {j : α} : Reach n heavy jobs s → j ∈ s.running →
      Reach n heavy jobs (s.finish j)

structure Inv {α : Type} (n : Nat) (heavy : α → Bool) (jobs : List α) (s : Sched α) : Prop where
  fifo : ∃ k, s.pending = jobs.drop k ∧ (s.done ++ s.running).Perm (jobs.take k)
  atMost : s.running.length ≤ n
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

theorem start?_isSome {α : Type} {n : Nat} {heavy : α → Bool} {s : Sched α} (hn : 1 ≤ n)
    (hr : s.running = []) (hp : s.pending ≠ []) : (s.start? n heavy).isSome := by
  unfold Sched.start?
  cases h : s.pending with
  | nil => exact absurd h hp
  | cons j rest =>
    simp only [mayStart, hr, List.isEmpty_nil, List.length_nil, List.any_nil, Bool.not_false,
      Bool.and_true]
    split <;> simp <;> omega

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

theorem runner_done {n : Nat} {cases : List Case} {s : Sched Job} (hn : 1 ≤ n)
    (h : Reach n Job.heavy (order (jobs cases)) s) (hr : s.running = [])
    (hs : s.start? n Job.heavy = none) : s.done.Perm (jobs cases) ∧ s.done.Nodup := by
  have hp := (h.complete hn hr hs).2.trans (order_perm _)
  exact ⟨hp, hp.nodup_iff.mpr (jobs_nodup cases)⟩

end MitosGate.Cheats
