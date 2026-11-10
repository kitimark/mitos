import Lean.Data.Json
import MitosGate.Util

namespace MitosGate.RunLog

def appendOnly (base head : List String) : Bool :=
  base.all fun l => base.count l ≤ head.count l

def firstMissing? (base head : List String) : Option Nat :=
  base.findIdx? fun l => head.count l < base.count l

def Subperm {α : Type} (l₁ l₂ : List α) : Prop :=
  ∃ l : List α, l.Perm l₁ ∧ l.Sublist l₂

theorem subperm_iff_count {α : Type} [BEq α] [LawfulBEq α] {l₁ l₂ : List α} :
    Subperm l₁ l₂ ↔ ∀ a, l₁.count a ≤ l₂.count a := by
  constructor
  · rintro ⟨l, hp, hs⟩ a
    rw [← hp.count_eq a]
    exact hs.count_le a
  · intro h
    induction l₁ generalizing l₂ with
    | nil => exact ⟨[], .nil, List.nil_sublist _⟩
    | cons x t ih =>
      have hx : x ∈ l₂ := by
        have := h x
        rw [List.count_cons_self] at this
        exact List.count_pos_iff.mp (by omega)
      have ht : ∀ a, t.count a ≤ (l₂.erase x).count a := by
        intro a
        by_cases hax : a = x
        · subst hax
          have := h a
          rw [List.count_cons_self] at this
          rw [List.count_erase_self]
          omega
        · have := h a
          rw [List.count_cons_of_ne (Ne.symm hax)] at this
          rwa [List.count_erase_of_ne hax]
      obtain ⟨s, hs, hsub⟩ := ih ht
      obtain ⟨s', hs', hsub'⟩ :=
        List.exists_perm_sublist (hsub.cons_cons x) (List.perm_cons_erase hx).symm
      exact ⟨s', hs'.trans (hs.cons x), hsub'⟩

theorem appendOnly_iff_count {base head : List String} :
    appendOnly base head = true ↔ ∀ l, base.count l ≤ head.count l := by
  unfold appendOnly
  rw [List.all_eq_true]
  constructor
  · intro h l
    by_cases hl : l ∈ base
    · exact of_decide_eq_true (h l hl)
    · rw [List.count_eq_zero_of_not_mem hl]
      exact Nat.zero_le _
  · intro h l _
    exact decide_eq_true (h l)

theorem appendOnly_iff_subperm {base head : List String} :
    appendOnly base head = true ↔ Subperm base head :=
  appendOnly_iff_count.trans subperm_iff_count.symm

theorem appendOnly_iff_perm_append {base head : List String} :
    appendOnly base head = true ↔ ∃ a, head.Perm (base ++ a) := by
  constructor
  · intro h
    obtain ⟨s, hs, hsub⟩ := appendOnly_iff_subperm.mp h
    obtain ⟨a, ha⟩ := hsub.exists_perm_append
    exact ⟨a, ha.trans (hs.append_right a)⟩
  · rintro ⟨a, ha⟩
    apply appendOnly_iff_count.mpr
    intro l
    rw [ha.count_eq l, List.count_append]
    exact Nat.le_add_right _ _

theorem appendOnly_eq_false_of_count_lt {base head : List String} {l : String}
    (h : head.count l < base.count l) : appendOnly base head = false := by
  cases hb : appendOnly base head with
  | false => rfl
  | true =>
    have := appendOnly_iff_count.mp hb l
    omega

theorem appendOnly_edit (p s : List String) {l l' : String} (hne : l ≠ l') :
    appendOnly (p ++ l :: s) (p ++ l' :: s) = false := by
  apply appendOnly_eq_false_of_count_lt (l := l)
  rw [List.count_append, List.count_append, List.count_cons_self,
    List.count_cons_of_ne (Ne.symm hne)]
  omega

theorem appendOnly_delete (p s : List String) (l : String) :
    appendOnly (p ++ l :: s) (p ++ s) = false := by
  apply appendOnly_eq_false_of_count_lt (l := l)
  rw [List.count_append, List.count_append, List.count_cons_self]
  omega

/-- **Union keeps the base.** The model of git's union merge, an assumption about git that is not
proved here: when one side is the base plus lines `a` and the other the base plus lines `b`, union
keeps each base line once and every added line of each side, so its result `r` is some order of
`base ++ a ++ b`. The replays in `gate/runlog-test.sh` check such merges on real git. -/
theorem union_appendOnly {base a b r : List String} (hunion : r.Perm (base ++ a ++ b)) :
    appendOnly base r = true :=
  appendOnly_iff_perm_append.mpr ⟨a ++ b, by rw [← List.append_assoc]; exact hunion⟩

theorem firstMissing?_eq_none_iff {base head : List String} :
    firstMissing? base head = none ↔ appendOnly base head = true := by
  rw [firstMissing?, List.findIdx?_eq_none_iff, appendOnly, List.all_eq_true]
  constructor
  · intro h l hl
    have := h l hl
    simp only [decide_eq_false_iff_not, Nat.not_lt] at this
    exact decide_eq_true this
  · intro h l hl
    have := of_decide_eq_true (h l hl)
    exact decide_eq_false (Nat.not_lt.mpr this)

theorem firstMissing?_spec {base head : List String} {i : Nat}
    (h : firstMissing? base head = some i) :
    ∃ l, base[i]? = some l ∧ head.count l < base.count l := by
  have := List.of_findIdx?_eq_some h
  revert this
  cases hi : base[i]? with
  | none => intro h; exact absurd h (by simp)
  | some l => intro h; exact ⟨l, rfl, of_decide_eq_true h⟩

def missingIndex (base head : List String) (h : appendOnly base head = false) : Nat :=
  match hfm : firstMissing? base head with
  | some i => i
  | none => False.elim <| nomatch (h.symm.trans (firstMissing?_eq_none_iff.mp hfm))


structure Record where
  task : String
  role : String
  attempt : Nat
  deriving DecidableEq, Repr, Inhabited

abbrev Key := String × String × Nat

def Record.key (r : Record) : Key := (r.task, r.role, r.attempt)

def dupAt? {α : Type} [BEq α] : List α → Option (Nat × Nat)
  | [] => none
  | x :: xs =>
    if xs.contains x then some (0, xs.idxOf x + 1)
    else (dupAt? xs).map fun p => (p.1 + 1, p.2 + 1)

theorem dupAt?_eq_none_iff {α : Type} [BEq α] [LawfulBEq α] {xs : List α} :
    dupAt? xs = none ↔ xs.Nodup := by
  induction xs with
  | nil => simp [dupAt?]
  | cons x xs ih =>
    rw [dupAt?, List.nodup_cons]
    by_cases hc : xs.contains x = true
    · have : x ∈ xs := List.contains_iff_mem.mp hc
      simp [this]
    · have : x ∉ xs := fun hm => hc (List.contains_iff_mem.mpr hm)
      simp [this, ih]

theorem dupAt?_spec {α : Type} [BEq α] [LawfulBEq α] {xs : List α} {i j : Nat}
    (h : dupAt? xs = some (i, j)) : i < j ∧ ∃ x, xs[i]? = some x ∧ xs[j]? = some x := by
  induction xs generalizing i j with
  | nil => simp [dupAt?] at h
  | cons x xs ih =>
    rw [dupAt?] at h
    by_cases hc : xs.contains x = true
    · simp only [hc, ↓reduceIte] at h
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
      have hm : x ∈ xs := List.contains_iff_mem.mp hc
      have hlt := List.idxOf_lt_length_of_mem hm
      refine ⟨Nat.succ_pos _, x, rfl, ?_⟩
      rw [List.getElem?_cons_succ, List.getElem?_eq_getElem hlt, List.getElem_idxOf hlt]
    · simp only [hc, Bool.false_eq_true, ↓reduceIte] at h
      obtain ⟨⟨i', j'⟩, hp, hq⟩ := Option.map_eq_some_iff.mp h
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj hq
      obtain ⟨hlt, y, hy₁, hy₂⟩ := ih hp
      exact ⟨Nat.succ_lt_succ hlt, y, hy₁, hy₂⟩

def noDupKeys (rs : List Record) : Bool :=
  (dupAt? (rs.map Record.key)).isNone

theorem noDupKeys_iff {rs : List Record} :
    noDupKeys rs = true ↔ (rs.map Record.key).Nodup := by
  rw [noDupKeys, Option.isNone_iff_eq_none, dupAt?_eq_none_iff]

theorem noDupKeys_perm {rs rs' : List Record} (h : rs.Perm rs') :
    noDupKeys rs = noDupKeys rs' := by
  apply Bool.eq_iff_iff.mpr
  rw [noDupKeys_iff, noDupKeys_iff]
  exact (h.map Record.key).nodup_iff

theorem union_noDupKeys_iff (f : String → Record) {base a b r : List String}
    (hunion : r.Perm (base ++ a ++ b)) :
    noDupKeys (r.map f) = true ↔ ((base ++ a ++ b).map fun l => (f l).key).Nodup := by
  rw [noDupKeys_perm (hunion.map f), noDupKeys_iff, List.map_map]
  rfl

theorem eq_of_nodup_map {α β : Type} {g : α → β} {x y : α} :
    ∀ {l : List α}, (l.map g).Nodup → x ∈ l → y ∈ l → g x = g y → x = y
  | [], _, hx, _, _ => absurd hx List.not_mem_nil
  | c :: l, h, hx, hy, hg => by
    rw [List.map_cons, List.nodup_cons] at h
    obtain ⟨hc, hl⟩ := h
    rcases List.mem_cons.mp hx with hxc | hxl <;> rcases List.mem_cons.mp hy with hyc | hyl
    · exact hxc.trans hyc.symm
    · subst hxc; exact (hc (hg ▸ List.mem_map_of_mem hyl)).elim
    · subst hyc; exact (hc (hg ▸ List.mem_map_of_mem hxl)).elim
    · exact eq_of_nodup_map hl hxl hyl hg

theorem noDupKeys_eq_false_of_mem (f : String → Record) {r : List String} {l₁ l₂ : String}
    (h₁ : l₁ ∈ r) (h₂ : l₂ ∈ r) (hne : l₁ ≠ l₂) (hkey : (f l₁).key = (f l₂).key) :
    noDupKeys (r.map f) = false := by
  cases hd : noDupKeys (r.map f) with
  | false => rfl
  | true =>
    rw [noDupKeys_iff, List.map_map] at hd
    exact absurd (eq_of_nodup_map hd h₁ h₂ hkey) hne

theorem edit_then_union (f : String → Record) (p : List String) {l l' : String}
    (hne : l ≠ l') (hkey : (f l).key = (f l').key) {r : List String} (hl : l ∈ r) (hl' : l' ∈ r) :
    appendOnly (p ++ [l]) (p ++ [l']) = false ∧ noDupKeys (r.map f) = false :=
  ⟨appendOnly_edit p [] hne, noDupKeys_eq_false_of_mem f hl hl' hne hkey⟩

example : appendOnly ["a", "b"] ["a", "b", "c"] = true := by decide
example : appendOnly ["a", "b"] ["c", "b", "x", "a"] = true := by decide
example : appendOnly ["a", "b"] ["a", "b'"] = false := by decide
example : appendOnly ["a", "b"] ["a"] = false := by decide
example : appendOnly ["a", "a"] ["a", "b"] = false := by decide
example : appendOnly [] ["a"] = true := by decide
example : firstMissing? ["a", "b", "c"] ["a", "c", "d"] = some 1 := by decide
example : firstMissing? ["a", "b"] ["b", "a"] = none := by decide
example : dupAt? [1, 2, 3, 2, 1] = some (0, 4) := by decide
example : dupAt? [1, 2, 3, 2] = some (1, 3) := by decide
example : dupAt? [1, 2, 3] = none := by decide
example : noDupKeys [⟨"T", "builder", 1⟩, ⟨"T", "builder", 2⟩, ⟨"T", "verifier", 1⟩] = true := by
  decide
example : noDupKeys [⟨"T", "builder", 1⟩, ⟨"U", "builder", 1⟩, ⟨"T", "builder", 1⟩] = false := by
  decide

example :
    appendOnly ["A", "B"] ["A", "B'"] = false ∧
    appendOnly ["A", "B", "C"] ["A", "B", "C", "B'"] = true ∧
    noDupKeys [⟨"A", "builder", 1⟩, ⟨"B", "builder", 1⟩, ⟨"C", "builder", 1⟩,
      ⟨"B", "builder", 1⟩] = false := by
  decide

def splitLines (s : String) : List String :=
  if s.isEmpty then []
  else
    let ls := s.splitOn "\n"
    if s.endsWith "\n" then ls.dropLast else ls

/-- Text that stays unprinted until `Message.oneLine` or `Message.ciLine` consumes it. -/
structure Message where
  private text : String
  deriving Repr, Inhabited, DecidableEq

namespace Message

def ofString (s : String) : Message := ⟨s⟩

instance : Append Message where
  append a b := ⟨a.text ++ b.text⟩

def oneLine (m : Message) : String := MitosGate.oneLine m.text

def ciLine (m : Message) : String := MitosGate.ciLine m.text

end Message

/-- `s` quoted for a message: `"` and `\` are escaped with `\`, and only the first `max` characters
are kept. -/
def quote (s : String) (max : Nat := 60) : Message :=
  let cs := s.toList
  let esc (acc : String) (c : Char) : String :=
    if c == '"' then acc ++ "\\\""
    else if c == '\\' then acc ++ "\\\\"
    else acc.push c
  Message.ofString ("\"" ++ (cs.take max).foldl esc "" ++ (if cs.length > max then "\"..." else "\""))

private def m (s : String) : Message := Message.ofString s

/-- GitHub's escaping for the message of a workflow command. Written character by character, not
with `String.replace`, so that the kernel can evaluate `Problem.render` in the examples below. -/
def escapeData (s : String) : String :=
  String.ofList <| s.toList.flatMap fun
    | '%' => ['%', '2', '5']
    | '\r' => ['%', '0', 'D']
    | '\n' => ['%', '0', 'A']
    | c => [c]

/-- GitHub's escaping for a property value of a workflow command. -/
def escapeProperty (s : String) : String :=
  String.ofList <| (escapeData s).toList.flatMap fun
    | ':' => ['%', '3', 'A']
    | ',' => ['%', '2', 'C']
    | c => [c]

structure Problem where
  file : String
  line : Nat
  msg : Message

def Problem.render (p : Problem) : String :=
  s!"::error file={escapeProperty (oneLine p.file)},line={p.line}::{escapeData p.msg.oneLine}"

example : (Problem.mk "ops/runs/d\u200b1.ndjson" 4
      (m "a second record for task " ++ quote "B\u200d\u00ad\u2800" ++ m ", role " ++ quote "builder")).render =
    "::error file=ops/runs/d\\u{200B}1.ndjson,line=4::a second record for task " ++
      "\"B\\u{200D}\\u{00AD}\\u{2800}\", role \"builder\"" := by
  decide

example : (Problem.mk "ops/runs/a,b::c.ndjson" 2
      (m "task " ++ quote "x\n::warning::injected\x1b[2J\u202e%0A,y")).render =
    "::error file=ops/runs/a%2Cb%3A%3Ac.ndjson,line=2::task " ++
      "\"x\\u{000A}::warning::injected\\u{001B}[2J\\u{202E}%250A,y\"" := by
  decide

example : (Problem.mk "f" 1 (quote "a\"b\\c")).render =
    "::error file=f,line=1::\"a\\u{005C}\"b\\u{005C}\\u{005C}c\"" := by
  decide

def safeChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '_' || c == '-'

def safeTask (s : String) : Bool :=
  match s.toList with
  | [] => false
  | c :: cs => c.isAlphanum && cs.all safeChar

def safeRole (s : String) : Bool := !s.toList.isEmpty && s.toList.all safeChar

def fileName (k : Key) : String := k.1 ++ "-" ++ k.2.1 ++ "-" ++ toString k.2.2 ++ ".json"

theorem fileName_safe {k : Key} (ht : safeTask k.1 = true) (hr : safeRole k.2.1 = true) :
    (∀ c ∈ (fileName k).toList, safeChar c = true) ∧
      ∃ c cs, (fileName k).toList = c :: cs ∧ c.isAlphanum = true := by
  obtain ⟨t, r, n⟩ := k
  simp only at ht hr
  unfold safeTask at ht
  split at ht
  · exact absurd ht (by decide)
  · rename_i c cs hcs
    simp only [Bool.and_eq_true, List.all_eq_true] at ht
    unfold safeRole at hr
    simp only [Bool.and_eq_true, List.all_eq_true] at hr
    have hdig : ∀ x ∈ (toString n).toList, safeChar x = true := by
      intro x hx
      simp only [toString, Nat.repr, String.toList_ofList] at hx
      have := Nat.isDigit_of_mem_toDigits (by decide) (by decide) hx
      simp [safeChar, Char.isAlphanum, this]
    refine ⟨?_, c, cs ++ ('-' :: r.toList ++ '-' :: (toString n).toList ++ ".json".toList), ?_, ht.1⟩
    · intro x hx
      simp only [fileName, String.toList_append, hcs, List.mem_append, List.mem_cons] at hx
      rcases hx with ((((hx | hx) | hx) | hx) | hx) | hx
      · rcases hx with rfl | hx
        · simp [safeChar, ht.1]
        · exact ht.2 x hx
      · revert hx; decide +revert
      · exact hr.2 x hx
      · revert hx; decide +revert
      · exact hdig x hx
      · revert hx; decide +revert
    · simp [fileName, String.toList_append, hcs]

def singleLine? (s : String) : Option String :=
  let cs := if s.toList.getLast? = some '\n' then s.toList.dropLast else s.toList
  if cs = [] ∨ '\n' ∈ cs then none else some (String.ofList cs)

theorem singleLine?_spec {s l : String} (h : singleLine? s = some l) :
    l.toList ≠ [] ∧ '\n' ∉ l.toList ∧
      (s.toList = l.toList ∨ s.toList = l.toList ++ ['\n']) := by
  have key : ∀ cs : List Char,
      (if cs = [] ∨ '\n' ∈ cs then none else some (String.ofList cs)) = some l →
        l.toList = cs ∧ cs ≠ [] ∧ '\n' ∉ cs := by
    intro cs hcs
    split at hcs
    · cases hcs
    · rename_i hc
      cases hcs
      exact ⟨String.toList_ofList, fun h => hc (Or.inl h), fun h => hc (Or.inr h)⟩
  unfold singleLine? at h
  by_cases hl : s.toList.getLast? = some '\n'
  · simp only [hl, ↓reduceIte] at h
    obtain ⟨h1, h2, h3⟩ := key _ h
    obtain ⟨ys, hys⟩ := List.getLast?_eq_some_iff.mp hl
    refine ⟨h1 ▸ h2, h1 ▸ h3, Or.inr ?_⟩
    rw [h1, hys, List.dropLast_concat]
  · simp only [hl, ↓reduceIte] at h
    obtain ⟨h1, h2, h3⟩ := key _ h
    exact ⟨h1 ▸ h2, h1 ▸ h3, Or.inl h1.symm⟩

def recordFile (parse : String → Except Message Record) (name text : String) :
    Except Message Record :=
  match singleLine? text with
  | none => .error (m ("a record file holds one record on one line; this one is empty or has " ++
      "more lines (ops/runs/README.md)"))
  | some l =>
    match parse l with
    | .error e => .error e
    | .ok r =>
      if safeTask r.task = false then
        .error (m "task " ++ quote r.task ++ m " must start with a letter or a digit and hold only letters, \
          digits, '.', '_' and '-', because it names the file")
      else if safeRole r.role = false then
        .error (m "role " ++ quote r.role ++ m " must not be empty and must hold only letters, digits, \
          '.', '_' and '-', because it names the file")
      else if name = fileName r.key then .ok r
      else
        .error (m "the file must be named " ++ quote (fileName r.key) 120 ++ m ", from its record's task, \
          role and attempt, so that two records for one attempt on one day are one path \
          (ops/runs/README.md)")

theorem recordFile_ok {parse : String → Except Message Record} {name text : String} {r : Record}
    (h : recordFile parse name text = .ok r) :
    (∃ l, singleLine? text = some l ∧ parse l = .ok r) ∧ safeTask r.task = true ∧
      safeRole r.role = true ∧ name = fileName r.key := by
  unfold recordFile at h
  split at h
  · cases h
  · rename_i l hl
    split at h
    · cases h
    · rename_i r' hr
      split at h
      · cases h
      · rename_i ht
        split at h
        · cases h
        · rename_i hro
          split at h
          · rename_i hn
            cases h
            refine ⟨⟨l, hl, hr⟩, ?_, ?_, hn⟩
            · simpa using ht
            · simpa using hro
          · cases h

theorem day_keys_nodup {fs : List (String × Record)} (hnames : (fs.map (·.1)).Nodup)
    (hname : ∀ p ∈ fs, p.1 = fileName p.2.key) : (fs.map (·.2.key)).Nodup := by
  have : fs.map (·.1) = (fs.map (·.2.key)).map fileName := by
    rw [List.map_map]
    exact List.map_congr_left hname
  rw [this] at hnames
  exact List.Pairwise.of_map fileName (fun _ _ h e => h (congrArg fileName e)) hnames

def isDate (s : String) : Bool :=
  match s.toList with
  | [y₁, y₂, y₃, y₄, '-', m₁, m₂, '-', d₁, d₂] =>
    [y₁, y₂, y₃, y₄, m₁, m₂, d₁, d₂].all Char.isDigit
  | _ => false

/-- What the check reads under `ops/runs/`: each day file directly in it, with its name and lines,
and each record file in its folders, with the folder's name, the file's name and its text. -/
structure Tree where
  days : List (String × List String) := []
  files : List (String × String × String) := []

def linesOf (t : Tree) (n : String) : List String :=
  ((t.days.find? (·.1 == n)).map (·.2)).getD []

def records (parse : String → Except Message Record) (t : Tree) : List Record :=
  t.days.flatMap (fun d => d.2.filterMap fun l => (parse l).toOption) ++
    t.files.filterMap fun f => (recordFile parse f.2.1 f.2.2).toOption

def lineRecords (parse : String → Except Message Record) (f : String) :
    Nat → List String → List (String × Nat × Record)
  | _, [] => []
  | i, l :: ls =>
    match parse l with
    | .ok r => (f, i, r) :: lineRecords parse f (i + 1) ls
    | .error _ => lineRecords parse f (i + 1) ls

def lineErrors (parse : String → Except Message Record) (f : String) :
    Nat → List String → List Problem
  | _, [] => []
  | i, l :: ls =>
    match parse l with
    | .ok _ => lineErrors parse f (i + 1) ls
    | .error e => ⟨f, i, e⟩ :: lineErrors parse f (i + 1) ls

def located (parse : String → Except Message Record) (dir : System.FilePath) (t : Tree) :
    List (String × Nat × Record) :=
  t.days.flatMap (fun d => lineRecords parse (dir / d.1).toString 1 d.2) ++
    t.files.filterMap fun f =>
      match recordFile parse f.2.1 f.2.2 with
      | .ok r => some ((dir / f.1 / f.2.1).toString, 1, r)
      | .error _ => none

theorem lineRecords_map (parse : String → Except Message Record) (f : String) (i : Nat)
    (ls : List String) :
    (lineRecords parse f i ls).map (·.2.2) = ls.filterMap fun l => (parse l).toOption := by
  induction ls generalizing i with
  | nil => rfl
  | cons l ls ih =>
    simp only [lineRecords, List.filterMap_cons]
    cases parse l <;> simp [Except.toOption, ih]

theorem located_map (parse : String → Except Message Record) (dir : System.FilePath) (t : Tree) :
    (located parse dir t).map (·.2.2) = records parse t := by
  simp only [located, records, List.map_append, List.map_flatMap, lineRecords_map,
    List.map_filterMap]
  congr 1
  congr 1
  funext f
  cases recordFile parse f.2.1 f.2.2 <;> rfl

theorem lineErrors_eq_nil {parse : String → Except Message Record} {f : String} {i : Nat}
    {ls : List String} (h : lineErrors parse f i ls = []) : ∀ l ∈ ls, ∃ r, parse l = .ok r := by
  induction ls generalizing i with
  | nil => simp
  | cons l ls ih =>
    unfold lineErrors at h
    intro x hx
    split at h
    · rename_i r hr
      rcases List.mem_cons.mp hx with rfl | hx
      · exact ⟨r, hr⟩
      · exact ih h x hx
    · cases h

def fileProblem (parse : String → Except Message Record) (dir : System.FilePath)
    (f : String × String × String) : Option Problem :=
  let p := (dir / f.1 / f.2.1).toString
  if isDate f.1 = false then
    some ⟨p, 1, m ("a record file must be in a folder named by its date, YYYY-MM-DD " ++
      "(ops/runs/README.md)")⟩
  else
    match recordFile parse f.2.1 f.2.2 with
    | .ok _ => none
    | .error e => some ⟨p, 1, e⟩

def parseProblems (parse : String → Except Message Record) (dir : System.FilePath) (t : Tree) :
    List Problem :=
  t.days.flatMap (fun d => lineErrors parse (dir / d.1).toString 1 d.2) ++
    t.files.filterMap (fileProblem parse dir)

def keyText (r : Record) : Message :=
  m "task " ++ quote r.task ++ m ", role " ++ quote r.role ++ m s!", attempt {r.attempt}"

def dupProblems (parse : String → Except Message Record) (dir : System.FilePath) (t : Tree) :
    List Problem :=
  let recs := located parse dir t
  let keys := recs.map fun x => x.2.2.key
  match hdup : dupAt? keys with
  | none => []
  | some (i, j) =>
    have hi' : i < recs.length := by
      rcases dupAt?_spec hdup with ⟨_, _, hi, _⟩
      simpa [keys, List.length_map] using (List.getElem?_eq_some_iff.mp hi).1
    have hj' : j < recs.length := by
      rcases dupAt?_spec hdup with ⟨_, _, _, hj⟩
      simpa [keys, List.length_map] using (List.getElem?_eq_some_iff.mp hj).1
    match recs[i], recs[j] with
    | (fi, li, r), (fj, lj, _) =>
      [⟨fj, lj, m "a second record for " ++ keyText r ++
        m s!"; the first is at {fi}:{li}. An attempt has one record: a correction goes in the next attempt's record. Union keeps both versions of an edited day-file line (ops/runs/README.md)"⟩]

def keptProblems (dir : System.FilePath) (b h : Tree) : List Problem :=
  b.days.filterMap (fun d =>
    let lines := d.2
    let hl := linesOf h d.1
    if honly : appendOnly lines hl = true then none
    else
      let i := missingIndex lines hl (by simpa using honly)
      let what := if h.days.any (·.1 == d.1) then "is missing from this file" else
        "is missing: the file was deleted"
      some ⟨(dir / d.1).toString, i + 1, m s!"line {i + 1} of the merge-base version {what}. " ++
        m "Run-log lines are append-only: a line already on the base branch may not be edited " ++
        m "or deleted (ops/runs/README.md)"⟩) ++
  h.days.filterMap (fun d =>
    if b.days.any (·.1 == d.1) then none
    else some ⟨(dir / d.1).toString, 1, m ("a new day file. Each attempt's record goes in its own " ++
      "file, ops/runs/<date>/<task>-<role>-<attempt>.json (ops/runs/README.md)")⟩) ++
  b.files.filterMap (fun f =>
    if h.files.contains f then none
    else
      let what := if h.files.any (fun g => g.1 == f.1 && g.2.1 == f.2.1) then "was changed" else
        "was deleted"
      some ⟨(dir / f.1 / f.2.1).toString, 1, m s!"this record file is on the base branch and " ++
        m s!"{what}. A record file never changes once it is on main: a correction goes in the " ++
        m "note of the next attempt's record (ops/runs/README.md)"⟩)

def problems (parse : String → Except Message Record) (dir : System.FilePath) (base : Option Tree)
    (head : Tree) : List Problem :=
  parseProblems parse dir head ++ dupProblems parse dir head ++
    match base with
    | some b => keptProblems dir b head
    | none => []

theorem parseProblems_eq_nil {parse : String → Except Message Record} {dir : System.FilePath}
    {t : Tree} (h : parseProblems parse dir t = []) :
    (∀ d ∈ t.days, ∀ l ∈ d.2, ∃ r, parse l = .ok r) ∧
      (∀ f ∈ t.files, isDate f.1 = true ∧ ∃ r, recordFile parse f.2.1 f.2.2 = .ok r) := by
  rw [parseProblems, List.append_eq_nil_iff, List.flatMap_eq_nil_iff,
    List.filterMap_eq_nil_iff] at h
  refine ⟨fun d hd => lineErrors_eq_nil (h.1 d hd), fun f hf => ?_⟩
  have hp := h.2 f hf
  unfold fileProblem at hp
  split at hp
  · cases hp
  · rename_i hd
    refine ⟨by simpa using hd, ?_⟩
    split at hp
    · rename_i r hr
      exact ⟨r, hr⟩
    · cases hp

theorem dupProblems_eq_nil {parse : String → Except Message Record} {dir : System.FilePath}
    {t : Tree} (h : dupProblems parse dir t = []) : noDupKeys (records parse t) = true := by
  dsimp only [dupProblems] at h
  split at h
  · rename_i hn
    rw [noDupKeys, ← located_map parse dir, List.map_map, Option.isNone_iff_eq_none]
    exact hn
  · cases h

theorem keptProblems_eq_nil {dir : System.FilePath} {b h : Tree} (hk : keptProblems dir b h = []) :
    (∀ d ∈ b.days, appendOnly d.2 (linesOf h d.1) = true) ∧
      (∀ d ∈ h.days, ∃ d' ∈ b.days, d'.1 = d.1) ∧ (∀ f ∈ b.files, f ∈ h.files) := by
  simp only [keptProblems, List.append_eq_nil_iff, List.filterMap_eq_nil_iff] at hk
  obtain ⟨⟨h1, h2⟩, h3⟩ := hk
  refine ⟨fun d hd => ?_, fun d hd => ?_, fun f hf => ?_⟩
  · have := h1 d hd
    split at this
    · assumption
    · cases this
  · have := h2 d hd
    split at this
    · rename_i ha
      obtain ⟨d', hd', he⟩ := List.any_eq_true.mp ha
      exact ⟨d', hd', beq_iff_eq.mp he⟩
    · cases this
  · have := h3 f hf
    split at this
    · exact List.contains_iff_mem.mp (by assumption)
    · cases this

theorem records_kept (parse : String → Except Message Record) {b h : Tree}
    (hdays : ∀ d ∈ b.days, appendOnly d.2 (linesOf h d.1) = true)
    (hfiles : ∀ f ∈ b.files, f ∈ h.files) :
    ∀ r ∈ records parse b, r ∈ records parse h := by
  intro r hr
  simp only [records, List.mem_append, List.mem_flatMap, List.mem_filterMap] at hr ⊢
  rcases hr with ⟨d, hd, l, hl, hp⟩ | ⟨f, hf, hp⟩
  · left
    have hlh : l ∈ linesOf h d.1 := by
      have := appendOnly_iff_count.mp (hdays d hd) l
      exact List.count_pos_iff.mp (Nat.lt_of_lt_of_le (List.count_pos_iff.mpr hl) this)
    unfold linesOf at hlh
    cases hfind : h.days.find? (fun x => x.1 == d.1) with
    | none => simp [hfind] at hlh
    | some d' =>
      simp only [hfind, Option.map_some, Option.getD_some] at hlh
      exact ⟨d', List.mem_of_find?_eq_some hfind, l, hlh, hp⟩
  · exact Or.inr ⟨f, hfiles f hf, hp⟩

theorem problems_eq_nil (parse : String → Except Message Record) (dir : System.FilePath)
    {base : Option Tree} {h : Tree} (hp : problems parse dir base h = []) :
    noDupKeys (records parse h) = true ∧
      (∀ d ∈ h.days, ∀ l ∈ d.2, ∃ r, parse l = .ok r) ∧
      (∀ f ∈ h.files, isDate f.1 = true ∧ ∃ r, recordFile parse f.2.1 f.2.2 = .ok r) ∧
      (∀ b, base = some b → (∀ r ∈ records parse b, r ∈ records parse h) ∧
        ∀ d ∈ h.days, ∃ d' ∈ b.days, d'.1 = d.1) := by
  unfold problems at hp
  rw [List.append_eq_nil_iff, List.append_eq_nil_iff] at hp
  obtain ⟨⟨hpar, hdup⟩, hkept⟩ := hp
  obtain ⟨hl, hf⟩ := parseProblems_eq_nil hpar
  refine ⟨dupProblems_eq_nil hdup, hl, hf, fun b hb => ?_⟩
  subst hb
  obtain ⟨k1, k2, k3⟩ := keptProblems_eq_nil hkept
  exact ⟨records_kept parse k1 k3, k2⟩

example : fileName ("ci-escape-68", "builder", 12) = "ci-escape-68-builder-12.json" := by decide
example : safeTask "P1-006" = true ∧ safeTask ".x" = false ∧ safeTask "-x" = false ∧
    safeTask "a/b" = false ∧ safeTask "" = false ∧ safeRole "red-team" = true ∧
    safeRole "" = false ∧ safeRole "a b" = false := by decide
example : isDate "2026-11-09" = true ∧ isDate "2026-1-09" = false ∧ isDate "notes" = false := by
  decide
example : singleLine? "{}\n" = some "{}" ∧ singleLine? "{}" = some "{}" ∧
    singleLine? "{}\n{}\n" = none ∧ singleLine? "" = none ∧ singleLine? "\n" = none ∧
    singleLine? "{}\n\n" = none := by decide

def outcomes : List String := ["in-review", "merged", "stuck", "counterexample", "abandoned"]

open Lean in
private def isNat (j : Json) : Bool := (j.getNat?).toBool

open Lean in
private def isStr : Json → Bool
  | .str _ => true
  | _ => false

open Lean in
private def isObj : Json → Bool
  | .obj _ => true
  | _ => false

open Lean in
private def isStrArray : Json → Bool
  | .arr a => a.all isStr
  | _ => false

open Lean in
private def isNatObject : Json → Bool
  | .obj kvs => kvs.all fun _ v => isNat v
  | _ => false

def parseRecord (line : String) : Except Message Record := do
  let j ← match Lean.Json.parse line with
    | .ok j => pure j
    | .error e => throw (m "the line is not valid JSON (" ++ quote e ++ m ")")
  unless isObj j do throw (m "the line is not a JSON object")
  let get (k : String) : Except Message Lean.Json :=
    match j.getObjVal? k with
    | .ok v => pure v
    | .error _ => throw (m "field " ++ quote k ++ m " is missing")
  let want (k ty : String) (ok : Lean.Json → Bool) : Except Message Unit := do
    unless ok (← get k) do throw (m "field " ++ quote k ++ m s!" must be {ty}")
  let str (k : String) : Except Message String := do
    match ← get k with
    | .str s => pure s
    | _ => throw (m "field " ++ quote k ++ m " must be a string")
  let task ← str "task"
  let role ← str "role"
  let _ ← str "model"
  let attempt ← match (← get "attempt").getNat? with
    | .ok n => pure n
    | .error _ => throw (m "field " ++ quote "attempt" ++ m " must be a natural number")
  want "iterations" "a natural number" isNat
  want "wall_min" "a natural number" isNat
  want "tokens" "a natural number or null" fun v => isNat v || v.isNull
  want "errors_by_kind" "an object of natural numbers" isNatObject
  want "lint_hits" "an array of strings" isStrArray
  want "escalations" "an array of strings" isStrArray
  let outcome ← str "outcome"
  unless outcomes.contains outcome do
    throw (m "field " ++ quote "outcome" ++ m " is " ++ quote outcome ++
      m s!", not one of {", ".intercalate outcomes}")
  if let .ok v := j.getObjVal? "note" then
    unless isStr v do throw (m "field " ++ quote "note" ++ m " must be a string")
  return { task, role, attempt }

def readText (path : System.FilePath) : IO (Except String String) := do
  let md ← path.symlinkMetadata
  if md.type != .file then
    return .error "not a regular file; run-log files must be plain files, not symlinks or directories"
  match String.fromUTF8? (← IO.FS.readBinFile path) with
  | none => return .error "not valid UTF-8"
  | some s => return .ok s

def readLines (path : System.FilePath) : IO (Except String (List String)) :=
  return (← readText path).map splitLines

def sortedEntries (dir : System.FilePath) : IO (Array IO.FS.DirEntry) :=
  return (← dir.readDir).qsort (·.fileName < ·.fileName)

def readTree (dir shown : System.FilePath) (isBase : Bool) :
    IO (Tree × Array Problem × Array String) := do
  let pre := if isBase then "the merge-base copy: " else ""
  let mut days : Array (String × List String) := #[]
  let mut files : Array (String × String × String) := #[]
  let mut ps : Array Problem := #[]
  let mut bad : Array String := #[]
  for e in ← sortedEntries dir do
    let n := e.fileName
    let p := dir / n
    let f := (shown / n).toString
    let ty := (← p.symlinkMetadata).type
    if n.endsWith ".ndjson" then
      match ← readLines p with
      | .ok ls => days := days.push (n, ls)
      | .error err => ps := ps.push ⟨f, 1, m (pre ++ err)⟩; bad := bad.push f
    else if ty == .dir then
      for e' in ← sortedEntries p do
        let q := (shown / n / e'.fileName).toString
        if e'.fileName.endsWith ".json" then
          match ← readText (p / e'.fileName) with
          | .ok s => files := files.push (n, e'.fileName, s)
          | .error err => ps := ps.push ⟨q, 1, m (pre ++ err)⟩; bad := bad.push q
        else unless isBase do
          ps := ps.push ⟨q, 1, m ("does not belong in a run-log folder, which holds only record " ++
            "files <task>-<role>-<attempt>.json (ops/runs/README.md)")⟩
    else unless isBase || (n == "README.md" && ty == .file) do
      ps := ps.push ⟨f, 1, m ("does not belong in the run log, which holds README.md, the day files " ++
        "<date>.ndjson and the folders <date>/ of record files (ops/runs/README.md)")⟩
  return ({ days := days.toList, files := files.toList }, ps, bad)

def check (base : Option System.FilePath) (head : System.FilePath) : IO UInt32 := do
  for d in base.toList ++ [head] do
    let isDir ← try pure ((← d.symlinkMetadata).type == .dir) catch _ => pure false
    unless isDir do
      let msg := m "run-log directory " ++ quote d.toString ++
        m " is missing, or is not a plain directory"
      IO.println s!"::error::{escapeData msg.oneLine}"
      return 1
  let (h, hps, hbad) ← readTree head head false
  let mut ps := hps
  let mut b? : Option Tree := none
  if let some bd := base then
    let (b, bps, _) ← readTree bd head true
    ps := ps ++ bps
    b? := some b
  ps := ps ++ ((problems parseRecord head b? h).filter fun p => !hbad.contains p.file).toArray
  if ps.isEmpty then
    let vs := match b? with
      | some b => s!", every merge-base line and record file kept " ++
          s!"({b.days.length + b.files.length} file(s) compared)"
      | none => ""
    IO.println (s!"run log OK: {h.days.length + h.files.length} file(s), " ++
      s!"{(records parseRecord h).length} record(s), one per (task, role, attempt){vs}")
    return 0
  for p in ps do IO.println p.render
  IO.println s!"{ps.size} run-log problem(s); see ops/runs/README.md"
  return 1

def parseArgs : List String → Option String → Option String →
    Except Message (Option String × Option String)
  | [], b, h => .ok (b, h)
  | "--base" :: v :: rest, _, h => parseArgs rest (some v) h
  | "--head" :: v :: rest, b, _ => parseArgs rest b (some v)
  | a :: _, _, _ => .error (m "unknown or incomplete argument " ++ quote a)

/-- `check`, but an I/O error it throws is printed as one `::error::` line through `oneLine`, with
exit 1. The Lean runtime would print an uncaught one raw, and the error names the path it failed
on, which can hold a newline. A file name that is not UTF-8 throws one: Lean reads it back with
U+FFFD, and no file has that name. -/
def cli (args : List String) (usage : String) : IO UInt32 := do
  match parseArgs args none none with
  | .ok (b, some h) =>
    try check (b.map System.FilePath.mk) h
    catch e =>
      let msg := s!"the run-log check stopped on an I/O error: {e}"
      IO.println s!"::error::{escapeData (oneLine msg)}"
      return 1
  | .ok (_, none) => IO.eprintln "runlog needs --head <dir>"; IO.eprintln usage; return 2
  | .error e => IO.eprintln e.ciLine; IO.eprintln usage; return 2

end MitosGate.RunLog
