import Lean.DeclarationRange
import Mutants.Challenge

namespace Mutants.CrossCheck

open Lean

inductive Kind where
  | thm (stmt : Option (List String))
  | hole
  | other (what : String)
  deriving DecidableEq, Repr

structure Decl where
  name : String
  pos  : Option (Nat × Nat)
  kind : Kind
  deriving DecidableEq, Repr

def holeName (t : String) : String :=
  String.ofList ((t.toList.drop "def ".length).takeWhile (· != ' '))

def thmDecl (i : Nat) (n s : String) : Decl :=
  { name := "Mitos.Proofs." ++ n, pos := some (i, "theorem ".length),
    kind := .thm (some (s.splitOn " ")) }

def holeDecl (i : Nat) (t : String) : Decl :=
  { name := holeName t, pos := some (i, "def ".length), kind := .hole }

def expectedFrom : Nat → List Line → List Decl
  | _, [] => []
  | k, .thm n s _ :: ls => thmDecl k n s :: expectedFrom (k + 1) ls
  | k, .hole t :: ls => holeDecl k t :: expectedFrom (k + 1) ls
  | k, _ :: ls => expectedFrom (k + 1) ls

def expected (ls : List Line) : List Decl := expectedFrom 1 ls

def holeNames (ls : List Line) : List String :=
  ls.filterMap fun | .hole t => some (holeName t) | _ => none

def importNames (ls : List Line) : List String :=
  ls.filterMap fun | .imp t => some (String.ofList (t.toList.drop "import ".length)) | _ => none

inductive Problem where
  | unread (lean : Decl)
  | undeclared (read : Decl)
  | differs (read lean : Decl)
  | notConfigured (hole : String)
  | notAHole (name : String)
  | imports (read lean : List String)
  deriving DecidableEq, Repr

def problems (ls : List Line) (defs imps : List String) (ds : List Decl) : List Problem :=
  let ex := expected ls
  let hs := holeNames ls
  let rs := "Init" :: importNames ls
  (ds.filter (!ex.contains ·)).map (fun d => match ex.find? (·.name == d.name) with
      | some e => .differs e d
      | none => .unread d) ++
    (ex.filter (!ds.contains ·)).map (fun e => match ds.find? (·.name == e.name) with
      | some d => .differs e d
      | none => .undeclared e) ++
    (hs.filter (!defs.contains ·)).map .notConfigured ++
    (defs.filter (!hs.contains ·)).map .notAHole ++
    (if imps.all rs.contains && rs.all imps.contains then [] else [.imports (importNames ls) imps])

theorem problems_nil {ls : List Line} {defs imps : List String} {ds : List Decl}
    (h : problems ls defs imps ds = []) :
    (∀ d, d ∈ ds ↔ d ∈ expected ls) ∧ (∀ n, n ∈ holeNames ls ↔ n ∈ defs) ∧
      ∀ m, m ∈ imps ↔ m ∈ "Init" :: importNames ls := by
  unfold problems at h
  simp only [List.append_eq_nil_iff, List.map_eq_nil_iff, List.filter_eq_nil_iff] at h
  obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := h
  refine ⟨fun d => ⟨fun hd => ?_, fun hd => ?_⟩, fun n => ⟨fun hn => ?_, fun hn => ?_⟩,
    fun m => ⟨fun hm => ?_, fun hm => ?_⟩⟩
  · have := h1 d hd; simpa using this
  · have := h2 d hd; simpa using this
  · have := h3 n hn; simpa using this
  · have := h4 n hn; simpa using this
  · split at h5
    · rename_i hi
      simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hi
      exact hi.1 m hm
    · simp at h5
  · split at h5
    · rename_i hi
      simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hi
      exact hi.2 m hm
    · simp at h5

theorem mem_expectedFrom {d : Decl} : ∀ {k : Nat} {ls : List Line},
    d ∈ expectedFrom k ls ↔ ∃ i, (∃ n s t, ls[i]? = some (.thm n s t) ∧ d = thmDecl (k + i) n s) ∨
      ∃ t, ls[i]? = some (.hole t) ∧ d = holeDecl (k + i) t
  | _, [] => by simp [expectedFrom]
  | k, l :: ls => by
    have ih := @mem_expectedFrom d (k + 1) ls
    have shift : ∀ {i : Nat}, k + 1 + i = k + (i + 1) := by omega
    constructor
    · intro hd
      cases l with
      | thm n s t =>
        simp only [expectedFrom, List.mem_cons] at hd
        rcases hd with rfl | hd
        · exact ⟨0, .inl ⟨n, s, t, rfl, by simp⟩⟩
        · obtain ⟨i, hi⟩ := ih.mp hd
          exact ⟨i + 1, by simpa [shift] using hi⟩
      | hole t =>
        simp only [expectedFrom, List.mem_cons] at hd
        rcases hd with rfl | hd
        · exact ⟨0, .inr ⟨t, rfl, by simp⟩⟩
        · obtain ⟨i, hi⟩ := ih.mp hd
          exact ⟨i + 1, by simpa [shift] using hi⟩
      | imp t =>
        obtain ⟨i, hi⟩ := ih.mp hd
        exact ⟨i + 1, by simpa [shift] using hi⟩
      | keep t =>
        obtain ⟨i, hi⟩ := ih.mp hd
        exact ⟨i + 1, by simpa [shift] using hi⟩
    · rintro ⟨i, hi⟩
      cases i with
      | zero =>
        rcases hi with ⟨n, s, t, hl, rfl⟩ | ⟨t, hl, rfl⟩
        · simp only [List.getElem?_cons_zero, Option.some.injEq] at hl
          subst hl; simp [expectedFrom]
        · simp only [List.getElem?_cons_zero, Option.some.injEq] at hl
          subst hl; simp [expectedFrom]
      | succ i =>
        have hi' := ih.mpr ⟨i, by simpa [shift] using hi⟩
        cases l <;> simp [expectedFrom, hi']

theorem mem_expected {ls : List Line} {d : Decl} :
    d ∈ expected ls ↔ ∃ i, (∃ n s t, ls[i]? = some (.thm n s t) ∧ d = thmDecl (i + 1) n s) ∨
      ∃ t, ls[i]? = some (.hole t) ∧ d = holeDecl (i + 1) t := by
  unfold expected
  rw [mem_expectedFrom]
  simp only [Nat.add_comm 1]

theorem readLines_getElem? : ∀ {b : Bool} {xs : List String} {ls : List Line},
    readLines b xs = .ok ls → ∀ {i : Nat} {x : Line}, ls[i]? = some x →
      ∃ l b' b'', xs[i]? = some l ∧ readLine b' l = .ok (x, b'')
  | b, [], ls, h, i, x, hx => by
    cases b <;> simp [readLines] at h
    subst h; simp at hx
  | b, l :: xs, ls, h, i, x, hx => by
    unfold readLines at h
    cases hl : readLine b l with
    | error e => rw [hl] at h; simp [bind, Except.bind] at h
    | ok r =>
      obtain ⟨y, b'⟩ := r
      rw [hl] at h
      cases hr : readLines b' xs with
      | error e => simp [hr, bind, Except.bind] at h
      | ok rs =>
        simp only [hr, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
        subst h
        cases i with
        | zero =>
          simp only [List.getElem?_cons_zero, Option.some.injEq] at hx
          subst hx
          exact ⟨l, b, b', rfl, hl⟩
        | succ i =>
          simp only [List.getElem?_cons_succ] at hx ⊢
          exact readLines_getElem? hr hx

theorem holeName_of_holeForm {cs n ty : List Char} (h : holeForm cs = some (n, ty)) :
    holeName (String.ofList cs) = String.ofList n := by
  have hs := holeForm_spec h
  have hn : ∀ c ∈ n, (c != ' ') = true := by
    unfold holeForm at h
    dsimp only at h
    split at h
    · simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, -⟩ := h
      have := List.all_takeWhile (p := (· != ' '))
        (l := (cs.drop 4).take (cs.length - 4 - sorrySuffix.length))
      exact List.all_eq_true.mp this
    · simp at h
  unfold holeName
  rw [String.toList_ofList, hs.1, show "def ".length = 4 by decide]
  simp only [List.append_assoc]
  rw [show "def ".toList = ['d', 'e', 'f', ' '] from rfl, List.drop_append_of_le_length (by simp),
    List.drop_eq_nil_of_le (by simp), List.nil_append, List.takeWhile_append_of_pos hn]
  simp [show " : ".toList = [' ', ':', ' '] from rfl]

def constApp (e : Expr) : Option (List String) :=
  match e.getAppFn with
  | .const c _ =>
    (e.getAppArgs.toList.mapM fun (a : Expr) => match a with
      | .const n _ => some n.toString
      | _ => none).map (c.toString :: ·)
  | _ => none

/-- Whether `v` is exactly `sorry` of type `ty`: `sorryAx ty s`, or the labeled or unique sorry
`sorryAx (τ → ty) s tag` that `sorry` elaborates to in this toolchain
(`Lean.Meta.mkLabeledSorry`). -/
def sorryOf (ty v : Expr) : Bool :=
  match v.getAppFn, v.getAppArgs with
  | .const ``sorryAx _, #[a, _] => a == ty
  | .const ``sorryAx _, #[.forallE _ _ b _, _, _] => b == ty
  | _, _ => false

def kindOf : ConstantInfo → Kind
  | .thmInfo t => .thm (constApp t.type)
  | .defnInfo d =>
    if d.safety == .safe && sorryOf d.type d.value then .hole
    else .other "a definition that is not a safe one whose value is exactly `sorry`"
  | .axiomInfo _ => .other "an axiom"
  | .opaqueInfo _ => .other "an opaque constant"
  | .quotInfo _ => .other "a quotient constant"
  | .inductInfo _ => .other "an inductive type"
  | .ctorInfo _ => .other "a constructor"
  | .recInfo _ => .other "a recursor"

def declOf (env : Environment) (c : ConstantInfo) : Decl :=
  let r := declRangeExt.find? (level := .exported) env c.name <|>
    declRangeExt.find? (level := .server) env c.name
  { name := c.name.toString, kind := kindOf c,
    pos := r.map fun r => (r.selectionRange.pos.line, r.selectionRange.pos.column) }

def built (env : Environment) (m : Name) : Option (List String × List Decl) := do
  let i ← env.header.moduleNames.idxOf? m
  let md ← env.header.moduleData[i]?
  return (md.imports.toList.map (·.module.toString), md.constants.toList.map (declOf env))

def Kind.text : Kind → String
  | .thm (some ws) => s!"a theorem stating `{" ".intercalate ws}`"
  | .thm none => "a theorem whose statement is not a constant applied to constants"
  | .hole => "a definition hole (value exactly `sorry`)"
  | .other w => w

def Decl.text (d : Decl) : String :=
  let at_ := match d.pos with
    | some (l, c) => s!"line {l}, column {c}"
    | none => "no position"
  s!"{d.name}, {d.kind.text}, at {at_}"

def Problem.text : Problem → String
  | .unread d => s!"Lean declares {d.text}; the reader read no theorem or hole line for it"
  | .undeclared e => s!"the reader read {e.text}; Lean declares nothing of that name"
  | .differs e d => s!"the reader read {e.text}; Lean declares {d.text}"
  | .notConfigured n => s!"the reader read the hole {n}, which definition_names does not name"
  | .notAHole n => s!"definition_names names {n}, which the reader read no hole line for"
  | .imports r l => s!"the reader read the imports {r}, Lean's are {l}"

def Problem.key : Problem → String × String
  | .unread d => ("unread", d.name)
  | .undeclared e => ("undeclared", e.name)
  | .differs e _ => ("differs", e.name)
  | .notConfigured n => ("notConfigured", n)
  | .notAHole n => ("notAHole", n)
  | .imports _ _ => ("imports", "")

structure Probe where
  path   : String
  source : String
  lines  : List Line
  defs   : List String
  expect : List (String × String)
  deriving Inhabited

def decoySource : String :=
  "import Mitos.Core\n\n/--\n-- -/\ntheorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry\n-- -/\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\n"

def reverseSource : String :=
  "import Mitos.Core\n\n/--\n-- -/\ndef Mitos.Impl.extra : String := sorry\n-- -/\ndef Mitos.Impl.resolve : Mitos.Resolver := sorry\n"

def valueLine : String := "def Mitos.Impl.f : Nat → Nat | _ => 0 where g : Nat := sorry"

def probes : List Probe := [
  { path := "Challenge/CrossCheckDecoy.lean", source := decoySource,
    lines := [.imp "import Mitos.Core", .keep "", .keep "/--", .keep "-- -/",
      .thm "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve"
        "theorem Mitos.Proofs.decoy : Mitos.Spec.Sound Mitos.Impl.resolve := sorry",
      .keep "-- -/", .hole "def Mitos.Impl.resolve : Mitos.Resolver := sorry", .keep ""],
    defs := ["Mitos.Impl.resolve"], expect := [("undeclared", "Mitos.Proofs.decoy")] },
  { path := "Challenge/CrossCheckReverse.lean", source := reverseSource,
    lines := [.imp "import Mitos.Core", .keep "", .keep "/--", .keep "-- -/",
      .hole "def Mitos.Impl.extra : String := sorry", .keep "-- -/",
      .hole "def Mitos.Impl.resolve : Mitos.Resolver := sorry", .keep ""],
    defs := ["Mitos.Impl.extra", "Mitos.Impl.resolve"],
    expect := [("undeclared", "Mitos.Impl.extra")] },
  { path := "Challenge/CrossCheckValue.lean", source := s!"import Mitos.Core\n\n{valueLine}\n",
    lines := [.imp "import Mitos.Core", .keep "", .hole valueLine, .keep ""],
    defs := ["Mitos.Impl.f"],
    expect := [("differs", "Mitos.Impl.f"), ("unread", "Mitos.Impl.f.g")] }]

def Probe.caught (p : Probe) (imps : List String) (ds : List Decl) : Bool :=
  let found := (problems p.lines p.defs imps ds).map (·.key)
  p.expect.all found.contains

#guard probes.map (fun p => (readChallenge p.source).toOption == some p.lines) == [true, true, false]
#guard (readChallenge s!"import Mitos.Core\n\n{valueLine}\n").toOption == none

#guard expected (probes.head!.lines) ==
  [thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve",
    { name := "Mitos.Impl.resolve", pos := some (7, 4), kind := .hole }]
#guard (thmDecl 5 "decoy" "Mitos.Spec.Sound Mitos.Impl.resolve").kind ==
  .thm (some ["Mitos.Spec.Sound", "Mitos.Impl.resolve"])
#guard holeName valueLine == "Mitos.Impl.f"
#guard holeNames (probes.head!.lines) == ["Mitos.Impl.resolve"]
#guard importNames (probes.head!.lines) == ["Mitos.Core"]

#guard (problems (probes.head!.lines) ["Mitos.Impl.resolve"] ["Init", "Mitos.Core"]
    [{ name := "Mitos.Impl.resolve", pos := some (7, 4), kind := .hole }]).map (·.key) ==
  [("undeclared", "Mitos.Proofs.decoy")]
#guard problems [.imp "import Mitos.Core", .hole "def Mitos.Impl.f : String := sorry",
    .thm "t" "Mitos.Spec.P Mitos.Impl.f" "theorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry"]
    ["Mitos.Impl.f"] ["Init", "Init", "Mitos.Core"]
    [thmDecl 3 "t" "Mitos.Spec.P Mitos.Impl.f", holeDecl 2 "def Mitos.Impl.f : String := sorry"] == []
#guard (problems [.hole "def Mitos.Impl.f : String := sorry",
    .thm "t" "Mitos.Spec.P Mitos.Impl.f" "theorem Mitos.Proofs.t : Mitos.Spec.P Mitos.Impl.f := sorry"]
    ["Mitos.Impl.g"] ["Init", "Mitos.Core"]
    [{ name := "Mitos.Proofs.t", pos := some (3, 8), kind := .thm (some ["Mitos.Spec.P", "Mitos.Impl.f"]) },
      { name := "Mitos.Impl.f", pos := some (1, 4), kind := .other "x" },
      { name := "Mitos.Impl.f.match_1", pos := none, kind := .other "x" }]).map (·.key) ==
  [("differs", "Mitos.Proofs.t"), ("differs", "Mitos.Impl.f"), ("unread", "Mitos.Impl.f.match_1"),
    ("differs", "Mitos.Impl.f"), ("differs", "Mitos.Proofs.t"), ("notConfigured", "Mitos.Impl.f"),
    ("notAHole", "Mitos.Impl.g"), ("imports", "")]

end Mutants.CrossCheck
