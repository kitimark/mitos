import Mutants.Edit

namespace Mutants

inductive Expect where
  | breaks (theorems : List String)
  | survives (gap : String)
  deriving Repr, DecidableEq

def Expect.theorems : Expect → List String
  | .breaks ts => ts
  | .survives _ => []

inductive Stage where
  | lint
  | holes
  | values
  | refutation
  deriving Repr, DecidableEq

def Stage.ofString? : String → Option Stage
  | "lint" => some .lint
  | "holes" => some .holes
  | "values" => some .values
  | "refutation" => some .refutation
  | _ => none

def Stage.name : Stage → String
  | .lint => "lint"
  | .holes => "holes"
  | .values => "values"
  | .refutation => "refutation"

structure Mutant where
  why     : String
  expect  : Expect
  rejects : Option Stage := none
  edits   : List Edit
  deriving Repr, DecidableEq

def plainName (cs : List Char) : Bool :=
  !cs.isEmpty && cs.all fun c => c.isAlphanum || c == '_'

def leanFileName (f : String) : Bool :=
  ".lean".toList.isSuffixOf f.toList && plainName (f.toList.take (f.length - 5))

def plainPath : List String → Bool
  | [] => false
  | [f] => leanFileName f
  | c :: cs => plainName c.toList && plainPath cs

def inArea (area path : String) : Bool :=
  match path.splitOn "/" with
  | "Mitos" :: a :: rest => a == area && plainPath rest
  | _ => false

def allowedFile : Expect → String → Bool
  | .breaks _, p => inArea "Impl" p
  | .survives _, p => inArea "Impl" p || inArea "Proofs" p

def Mutant.implEdits (m : Mutant) : List Edit :=
  m.edits.filter fun e => inArea "Impl" e.file

def Stage.fits : Stage → Expect → Bool
  | .lint, _ => true
  | .holes, _ => true
  | .values, .survives _ => true
  | .refutation, .breaks _ => true
  | _, _ => false

def Mutant.valid (m : Mutant) : Bool :=
  !m.why.isEmpty &&
  m.edits.any (fun e => inArea "Impl" e.file) &&
  m.edits.all (fun e => !e.find.isEmpty && e.find != e.replace && allowedFile m.expect e.file) &&
  (match m.expect with
  | .breaks ts => !ts.isEmpty && ts.Nodup && ts.all (fun t => plainName t.toList)
  | .survives g => !g.isEmpty) &&
  m.rejects.all (·.fits m.expect)

def Mutant.problem (m : Mutant) : String :=
  if m.why.isEmpty then "no why= line"
  else if !m.edits.any (fun e => inArea "Impl" e.file) then "no edit under Mitos/Impl/"
  else match m.edits.find? (fun e => e.find.isEmpty) with
  | some e => s!"{e.file}: an empty find="
  | none => match m.edits.find? (fun e => e.find == e.replace) with
  | some e => s!"{e.file}: replace= is the same as find="
  | none => match m.edits.find? (fun e => !allowedFile m.expect e.file) with
  | some e => s!"{e.file}: this case may not edit it (breaks= edits Mitos/Impl/ only; survives= also Mitos/Proofs/)"
  | none => match m.expect with
  | .breaks ts =>
    if ts.isEmpty then "breaks= names no theorem"
    else if !ts.Nodup then "breaks= names a theorem twice"
    else if !ts.all (fun t => plainName t.toList) then
      "breaks= names something that is not a plain theorem name"
    else "rejects=values needs survives= (only a survives= case repairs proofs)"
  | .survives g =>
    if g.isEmpty then "survives= is empty"
    else "rejects=refutation needs breaks= (only a breaks= case has a refutation run)"

structure Raw where
  why      : List String := []
  breaks   : List String := []
  survives : List String := []
  rejects  : List String := []
  file     : Option String := none
  find     : Option String := none
  edits    : Array Edit := #[]

def splitKV (line : String) : Option (String × String) :=
  match line.splitOn "=" with
  | k :: v :: rest => some (k, "=".intercalate (v :: rest))
  | _ => none

def step (r : Raw) (n : Nat) (line : String) : Except String Raw :=
  let at_ (msg : String) : Except String Raw := .error s!"line {n}: {msg}"
  match splitKV line with
  | none => at_ "not key=value"
  | some ("why", v) => .ok { r with why := r.why ++ [v] }
  | some ("breaks", v) => .ok { r with breaks := r.breaks ++ [v] }
  | some ("survives", v) => .ok { r with survives := r.survives ++ [v] }
  | some ("rejects", v) => .ok { r with rejects := r.rejects ++ [v] }
  | some ("file", v) =>
    if r.find.isSome then at_ "file= between find= and replace=" else .ok { r with file := some v }
  | some ("find", v) =>
    match r.file, r.find with
    | none, _ => at_ "find= before any file="
    | some _, some _ => at_ "two find= lines without replace="
    | some _, none => .ok { r with find := some v }
  | some ("replace", v) =>
    match r.file, r.find with
    | some f, some x => .ok { r with find := none, edits := r.edits.push ⟨f, x, v⟩ }
    | _, _ => at_ "replace= without find="
  | some (k, _) => at_ s!"unknown key {k}"

def words (s : String) : List String :=
  (s.splitOn " ").filter (!·.isEmpty)

def checked (m : Mutant) : Except String Mutant :=
  if m.valid then .ok m else .error m.problem

def rejectsOf : List String → Except String (Option Stage)
  | [] => .ok none
  | [v] => match Stage.ofString? v with
    | some s => .ok (some s)
    | none => .error s!"rejects= names {v}, not lint, holes, values or refutation"
  | _ => .error "more than one rejects= line"

def parts (r : Raw) : Except String (String × Expect) :=
  if r.find.isSome then .error "find= without replace=" else
  match r.why, r.breaks, r.survives with
  | [w], [b], [] => .ok (w, .breaks (words b))
  | [w], [], [s] => .ok (w, .survives s)
  | [_], _, _ => .error "needs exactly one breaks= or survives= line"
  | _, _, _ => .error "needs exactly one why= line"

def finish (r : Raw) : Except String Mutant :=
  match parts r, rejectsOf r.rejects with
  | .ok (why, expect), .ok rejects => checked { why, expect, rejects, edits := r.edits.toList }
  | .error e, _ => .error e
  | _, .error e => .error e

def parseLines (r : Raw) : Nat → List String → Except String Raw
  | _, [] => .ok r
  | n, l :: ls =>
    if l.isEmpty then parseLines r (n + 1) ls
    else match step r n l with
      | .ok r' => parseLines r' (n + 1) ls
      | .error e => .error e

def parse (src : String) : Except String Mutant :=
  match parseLines {} 1 (src.splitOn "\n") with
  | .ok r => finish r
  | .error e => .error e

theorem checked_valid {m m' : Mutant} (h : checked m = .ok m') : m'.valid = true := by
  unfold checked at h
  split at h
  · rename_i hv
    simp only [Except.ok.injEq] at h
    exact h ▸ hv
  · simp at h

theorem finish_valid {r : Raw} {m : Mutant} (h : finish r = .ok m) : m.valid = true := by
  unfold finish at h
  split at h
  · exact checked_valid h
  · simp at h
  · simp at h

theorem parse_valid {src : String} {m : Mutant} (h : parse src = .ok m) : m.valid = true := by
  unfold parse at h
  split at h
  · exact finish_valid h
  · simp at h

theorem valid_breaks_impl {m : Mutant} {ts : List String} (hv : m.valid = true)
    (he : m.expect = .breaks ts) : ∀ e ∈ m.edits, inArea "Impl" e.file = true := by
  intro e hmem
  simp only [Mutant.valid, Bool.and_eq_true, List.all_eq_true] at hv
  have := (hv.1.1.2 e hmem).2
  rw [he] at this
  exact this

theorem valid_area {m : Mutant} (hv : m.valid = true) :
    ∀ e ∈ m.edits, inArea "Impl" e.file = true ∨ inArea "Proofs" e.file = true := by
  intro e hmem
  simp only [Mutant.valid, Bool.and_eq_true, List.all_eq_true] at hv
  have := (hv.1.1.2 e hmem).2
  cases hexp : m.expect with
  | breaks ts => rw [hexp] at this; exact .inl this
  | survives g => rw [hexp] at this; simpa [allowedFile] using this

theorem inArea_head {area path : String} (h : inArea area path = true) :
    ∃ rest, path.splitOn "/" = "Mitos" :: area :: rest := by
  unfold inArea at h
  split at h
  · rename_i a rest hs
    simp only [Bool.and_eq_true, beq_iff_eq] at h
    exact ⟨rest, by rw [hs, h.1]⟩
  · simp at h

#guard (parse "why=w\nbreaks=resolve_sound\nfile=Mitos/Impl/Resolve.lean\nfind=a = b\nreplace=c\n").toOption ==
  some { why := "w", expect := .breaks ["resolve_sound"],
         edits := [⟨"Mitos/Impl/Resolve.lean", "a = b", "c"⟩] }
#guard (parse "why=w\nsurvives=g\nfile=Mitos/Impl/A.lean\nfind=x\nreplace=y\nfile=Mitos/Proofs/Resolve/B.lean\nfind=p\nreplace=q").toOption ==
  some { why := "w", expect := .survives "g",
         edits := [⟨"Mitos/Impl/A.lean", "x", "y"⟩, ⟨"Mitos/Proofs/Resolve/B.lean", "p", "q"⟩] }
#guard (parse "why=w\nbreaks=t\nfile=Mitos/Core/Spec/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nfile=Mitos/Impl/../Core.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nfile=Mitos/Proofs/Resolver.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nfile=../Challenge/Resolver.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nsurvives=g\nfile=Mitos/Proofs/Resolver.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nrejects=refutation\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption ==
  some { why := "w", expect := .breaks ["t"], rejects := some .refutation,
         edits := [⟨"Mitos/Impl/Resolve.lean", "a", "b"⟩] }
#guard (parse "why=w\nsurvives=g\nrejects=holes\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption.map (·.rejects) ==
  some (some .holes)
#guard (parse "why=w\nbreaks=t\nrejects=lint\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption.map (·.rejects) ==
  some (some .lint)
#guard (parse "why=w\nbreaks=t\nrejects=values\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nsurvives=g\nrejects=refutation\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nrejects=gate\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nrejects=holes\nrejects=holes\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard ((parse "why=w\nsurvives=g\nfile=Mitos/Impl/A.lean\nfind=x\nreplace=y\nfile=Mitos/Proofs/B.lean\nfind=p\nreplace=q").toOption.map
    (·.implEdits)) == some [⟨"Mitos/Impl/A.lean", "x", "y"⟩]
#guard (parse "why=w\nbreaks=t t\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=a").toOption == none
#guard (parse "why=w\nbreaks=t\nfile=Mitos/Impl/Resolve.lean\nfind=a").toOption == none
#guard (parse "why=w\nbreaks=t\nexpect=x\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none
#guard (parse "why=w\nbreaks=t\nsurvives=g\nfile=Mitos/Impl/Resolve.lean\nfind=a\nreplace=b").toOption == none

end Mutants
