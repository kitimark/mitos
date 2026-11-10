import MitosGate.Lint
import Mutants.Manifest

namespace Mutants.Lint
open Lean

inductive Kind where
  | impl
  | proofs
  | refute (holes : List (List String))
  deriving Repr, DecidableEq

def Kind.imports : Kind → List String
  | .impl | .refute _ => ["Mitos.Core", "Mitos.Impl"]
  | .proofs => ["Mitos.Core", "Mitos.Impl", "Mitos.Proofs"]

def Kind.ofPath (path : String) : Kind :=
  if inArea "Impl" path then .impl else .proofs

abbrev Pos := Nat × Nat

inductive Scoped where
  | ns (name : Option (List String))
  | sec (name : Option (List String))
  | close (name : Option (List String))
  | decl (name : Option (List String))
  deriving Repr, DecidableEq

structure Source where
  unparsed   : Option (Pos × String) := none
  modifiers  : List (Pos × String) := []
  imports    : List (Pos × String × Option (List String)) := []
  commands   : List (Pos × String × String) := []
  attributes : List (Pos × String) := []
  tokens     : List (Pos × String) := []
  scopes     : List (Pos × String × Scoped) := []
  opens      : List (Pos × String × Option (List String)) := []
  deriving Repr, DecidableEq

def allowedCommands : List String :=
  [``Parser.Command.moduleDoc, ``Parser.Command.namespace, ``Parser.Command.section,
    ``Parser.Command.end, ``Parser.Command.open, ``Parser.Command.definition,
    ``Parser.Command.theorem, ``Parser.Command.abbrev, ``Parser.Command.example].map toString

def bans : List String :=
  MitosGate.Lint.banned ++
    ["by_elab", "run_tac", "set_option", "attribute", "deriving", "with_decl_name"]

def bannedComponent (c : String) : Bool :=
  bans.contains c || bans.any fun b => c == b ++ "%"

def tokenOk (t : String) : Bool :=
  !t.startsWith "#" && (MitosGate.Lint.components t).all fun c => !bannedComponent c

theorem tokenOk_iff {t : String} :
    tokenOk t = true ↔ t.startsWith "#" = false ∧
      ∀ c ∈ MitosGate.Lint.components t, c ∉ bans ∧ ∀ b ∈ bans, c ≠ b ++ "%" := by
  simp [tokenOk, bannedComponent]

inductive Found where
  | entered (ns : List String)
  | declared (name : List String)
  | unreadable
  | unbalanced
  deriving Repr, DecidableEq

def fullName (cur : List String) : List String → List String
  | "_root_" :: rest => rest
  | n => cur ++ n

def nsScopes (cur n : List String) : List (List String) :=
  ((List.range n.length).map fun i => cur ++ n.take (i + 1)).reverse

def walk : List (List String) → List (Pos × String × Scoped) → List (Pos × String × Found)
  | _, [] => []
  | st, (p, t, c) :: cs =>
    let cur := st.headD []
    match c with
    | .ns (some n) => (p, t, .entered (cur ++ n)) :: walk (nsScopes cur n ++ st) cs
    | .sec (some n) => walk (List.replicate (max 1 n.length) cur ++ st) cs
    | .close (some n) =>
      if max 1 n.length ≤ st.length then walk (st.drop (max 1 n.length)) cs
      else (p, t, .unbalanced) :: walk [] cs
    | .decl (some n) => (p, t, .declared (fullName cur n)) :: walk st cs
    | .ns none | .sec none | .close none | .decl none => (p, t, .unreadable) :: walk st cs

def strictlyUnder (pre name : List String) : Bool :=
  pre.isPrefixOf name && pre.length < name.length

def nsOk (ns : List String) : Bool :=
  ns.head? == some "Mitos" && !ns.contains "_root_"

def Kind.declOk (k : Kind) (name : List String) : Bool :=
  !name.contains "_root_" &&
    match k with
    | .impl => strictlyUnder ["Mitos", "Impl"] name
    | .refute holes => strictlyUnder ["Mitos", "Refute"] name || holes.contains name
    | .proofs => strictlyUnder ["Mitos"] name

def Kind.foundOk (k : Kind) : Found → Bool
  | .entered ns => nsOk ns
  | .declared n => k.declOk n
  | .unreadable | .unbalanced => false

def openOk : Option (List String) → Bool
  | some ns => nsOk ns
  | none => false

def foundProblem (k : Kind) (t : String) : Found → String
  | .entered ns => s!"`{t}` enters `{".".intercalate ns}`; a case may enter only namespaces under `Mitos`, which hold no scoped syntax"
  | .declared n =>
    let where_ := match k with
      | .impl => "under `Mitos.Impl`"
      | .refute _ => "under `Mitos.Refute` (or an approved definition hole)"
      | .proofs => "under `Mitos`"
    s!"`{t}` declares `{".".intercalate n}`; this file may declare names only {where_}, with no `_root_` inside"
  | .unreadable => s!"`{t}`: a name with a component that is not a plain identifier is not allowed"
  | .unbalanced => s!"`{t}` closes more scopes than are open"

def importOk (k : Kind) : Option (List String) → Bool
  | some mod => MitosGate.Lint.moduleAllowed k.imports mod
  | none => false

def shortKind (k : String) : String :=
  ((k.splitOn ".").getLast?).getD k

def tokenProblem (t : String) : String :=
  if t.startsWith "#" then s!"`{t}`: no `#` command is allowed"
  else
    let c := ((MitosGate.Lint.components t).find? bannedComponent).getD t
    s!"`{c}` is not allowed in a case's Lean text"

def problems (k : Kind) (s : Source) : List (Pos × String) :=
  match s.unparsed with
  | some (p, why) => [(p, s!"Lean's parser cannot read it to the end with Init's syntax alone: {why}")]
  | none =>
    s.modifiers.map (fun (p, t) => (p, s!"`{t}` is not allowed; only a plain `import`")) ++
    s.imports.filterMap (fun (p, t, mod) =>
      if importOk k mod then none
      else some (p, s!"import `{t}` is not allowed; imports must lie under {", ".intercalate k.imports}")) ++
    s.commands.filterMap (fun (p, head, kind) =>
      if allowedCommands.contains kind then none
      else some (p, s!"command `{head}` ({shortKind kind}) is not allowed; only imports, namespace, section, open, end and def, theorem, abbrev and example declarations")) ++
    s.attributes.map (fun (p, t) => (p, s!"attribute `{t}` is not allowed")) ++
    s.tokens.filterMap (fun (p, t) => if tokenOk t then none else some (p, tokenProblem t)) ++
    (walk [] s.scopes).filterMap (fun (p, t, f) =>
      if k.foundOk f then none else some (p, foundProblem k t f)) ++
    s.opens.filterMap (fun (p, t, ns) =>
      if openOk ns then none
      else some (p, s!"`open {t}` is not allowed; a case may open only namespaces under `Mitos`, which hold no scoped syntax"))

theorem problems_eq_nil_iff {k : Kind} {s : Source} :
    problems k s = [] ↔
      s.unparsed = none ∧ s.modifiers = [] ∧
      (∀ i ∈ s.imports, ∃ mod, i.2.2 = some mod ∧ MitosGate.Lint.moduleAllowed k.imports mod = true) ∧
      (∀ c ∈ s.commands, c.2.2 ∈ allowedCommands) ∧ s.attributes = [] ∧
      (∀ t ∈ s.tokens, tokenOk t.2 = true) ∧
      (∀ f ∈ walk [] s.scopes, k.foundOk f.2.2 = true) ∧
      ∀ o ∈ s.opens, openOk o.2.2 = true := by
  obtain ⟨u, ms, is, cs, as, ts, sc, os⟩ := s
  cases u with
  | some x => simp [problems]
  | none =>
    simp only [problems, List.append_eq_nil_iff, List.map_eq_nil_iff, List.filterMap_eq_nil_iff,
      ite_eq_left_iff, reduceCtorEq, imp_false, Bool.not_eq_true, true_and]
    constructor
    · rintro ⟨⟨⟨⟨⟨⟨hm, hi⟩, hc⟩, ha⟩, ht⟩, hw⟩, ho⟩
      refine ⟨hm, fun i hi' => ?_, fun c hc' => ?_, ha, fun t ht' => ?_, fun f hf => ?_,
        fun o ho' => ?_⟩
      · obtain ⟨p, t, mod⟩ := i
        have := hi _ hi'
        cases mod with
        | none => simp [importOk] at this
        | some m => exact ⟨m, rfl, by simpa [importOk] using this⟩
      · have := hc _ hc'
        simpa using this
      · have := ht _ ht'
        simpa using this
      · have := hw _ hf
        simpa using this
      · have := ho _ ho'
        simpa using this
    · rintro ⟨hm, hi, hc, ha, ht, hw, ho⟩
      refine ⟨⟨⟨⟨⟨⟨hm, fun i hi' => ?_⟩, fun c hc' => ?_⟩, ha⟩, fun t ht' => ?_⟩,
        fun f hf => ?_⟩, fun o ho' => ?_⟩
      · obtain ⟨m, hm', ha'⟩ := hi i hi'
        obtain ⟨p, t, mod⟩ := i
        simp only at hm'
        subst hm'
        simp [importOk, ha']
      · simpa using hc c hc'
      · simpa using ht t ht'
      · simpa using hw f hf
      · simpa using ho o ho'

def wordChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '\'' || c == '!' || c == '?'

def flush (cur : List Char) : List String :=
  if cur.isEmpty then [] else [String.ofList cur.reverse]

def wordsGo : List Char → List Char → List String
  | [], cur => flush cur
  | c :: cs, cur => if wordChar c then wordsGo cs (c :: cur) else flush cur ++ wordsGo cs []

def words (s : String) : List String := wordsGo s.toList []

theorem wordsGo_word {rest cur : List Char} :
    ∀ {ws : List Char}, ws.all wordChar = true → wordsGo (ws ++ rest) cur = wordsGo rest (ws.reverse ++ cur)
  | [], _ => by simp
  | w :: ws, h => by
    simp only [List.all_cons, Bool.and_eq_true] at h
    simp only [List.cons_append, wordsGo, h.1, ite_true, List.reverse_cons, List.append_assoc]
    exact wordsGo_word h.2

theorem wordsGo_after {rest : List Char} :
    ∀ {pre cur : List Char}, pre ≠ [] → wordChar (pre.getLast?.getD 'a') = false →
      ∃ ws, wordsGo (pre ++ rest) cur = ws ++ wordsGo rest []
  | [], _, h, _ => absurd rfl h
  | [c], cur, _, hc => by
    simp only [List.getLast?_singleton, Option.getD_some] at hc
    exact ⟨flush cur, by simp [wordsGo, hc]⟩
  | c :: d :: ds, cur, _, hl => by
    have hl' : wordChar ((d :: ds).getLast?.getD 'a') = false := by
      simpa [List.getLast?_cons_cons] using hl
    by_cases hc : wordChar c = true
    · obtain ⟨ws, h⟩ := wordsGo_after (rest := rest) (pre := d :: ds) (cur := c :: cur) (by simp) hl'
      exact ⟨ws, by rw [List.cons_append, wordsGo, ite_eq_left hc]; exact h⟩
    · obtain ⟨ws, h⟩ := wordsGo_after (rest := rest) (pre := d :: ds) (cur := []) (by simp) hl'
      refine ⟨flush cur ++ ws, ?_⟩
      rw [List.cons_append, wordsGo, ite_eq_right hc, h, List.append_assoc]

theorem mem_words {pre w post : List Char} (hw : w ≠ []) (hall : w.all wordChar = true)
    (hpre : wordChar (pre.getLast?.getD ' ') = false) (hpost : wordChar (post.head?.getD ' ') = false) :
    String.ofList w ∈ wordsGo (pre ++ w ++ post) [] := by
  have hsp : wordChar ' ' = false := by decide
  have hstart : ∃ ws, wordsGo (pre ++ (w ++ post)) [] = ws ++ wordsGo (w ++ post) [] := by
    cases pre with
    | nil => exact ⟨[], rfl⟩
    | cons c cs =>
      exact wordsGo_after (by simp) (by simpa [List.getLast?_cons] using hpre)
  obtain ⟨ws, hs⟩ := hstart
  rw [List.append_assoc, hs, wordsGo_word hall, List.append_nil]
  have hflush : flush w.reverse = [String.ofList w] := by
    simp [flush, hw]
  apply List.mem_append_right
  cases post with
  | nil => rw [wordsGo, hflush]; exact List.mem_singleton_self _
  | cons c cs =>
    simp only [List.head?_cons, Option.getD_some] at hpost
    rw [wordsGo, ite_eq_right (by simp [hpost]), hflush]
    exact List.mem_append_left _ (List.mem_singleton_self _)

def replaceProblems (r : String) : List String :=
  (if r.toList.contains '#' then ["`#`: no `#` command is allowed"] else []) ++
  (if (splitFirst "@[".toList r.toList).isSome then ["`@[`: no attribute is allowed"] else []) ++
  ((words r).filter (bans.contains ·)).map fun w => s!"`{w}` is not allowed in a case's Lean text"

theorem bans_words : ∀ b ∈ bans, b.toList ≠ [] ∧ b.toList.all wordChar = true := by
  decide

theorem replaceProblems_banned {r : String} (h : replaceProblems r = []) :
    '#' ∉ r.toList ∧ (∀ pre post, r.toList ≠ pre ++ "@[".toList ++ post) ∧
      ∀ b ∈ bans, ∀ pre post, r.toList = pre ++ b.toList ++ post →
        wordChar (pre.getLast?.getD ' ') = true ∨ wordChar (post.head?.getD ' ') = true := by
  simp only [replaceProblems, List.append_eq_nil_iff, ite_eq_right_iff, reduceCtorEq, imp_false,
    List.map_eq_nil_iff, List.filter_eq_nil_iff, Bool.not_eq_true] at h
  obtain ⟨⟨hhash, hat⟩, hw⟩ := h
  refine ⟨by simpa using hhash, fun pre post he => ?_, fun b hb pre post he => ?_⟩
  · have := splitFirst_isSome (pat := "@[".toList) (pre := pre) (post := post) he
    rw [hat] at this
    simp at this
  · apply Classical.byContradiction
    intro hc
    simp only [not_or, Bool.not_eq_true] at hc
    obtain ⟨hne, hall⟩ := bans_words b hb
    have hmem : String.ofList b.toList ∈ words r := by
      unfold words
      rw [he]
      exact mem_words hne hall hc.1 hc.2
    simp only [String.ofList_toList] at hmem
    have := hw b hmem
    simp [hb] at this

def targets (m : Mutant) : List (String × Kind) :=
  (m.edits.map (·.file)).eraseDups.map fun p => (p, Kind.ofPath p)

theorem mem_targets {m : Mutant} {e : Edit} (he : e ∈ m.edits) :
    (e.file, Kind.ofPath e.file) ∈ targets m := by
  simp only [targets, List.mem_map]
  exact ⟨e.file, List.mem_eraseDups.mpr (List.mem_map_of_mem he), rfl⟩

def syntaxEnv : IO Environment := do
  unsafe enableInitializersExecution
  initSearchPath (← findSysroot)
  importModules #[{ module := `Init }] {} (loadExts := true)

private def posOf (fm : FileMap) (stx : Syntax) : Pos :=
  let p := fm.toPosition (stx.getPos?.getD 0)
  (p.line, p.column + 1)

private def headOf (fm : FileMap) (stx : Syntax) : String :=
  ((MitosGate.Lint.tokensOf fm stx #[])[0]?.map (·.text)).getD (toString stx.getKind)

partial def attributesOf (fm : FileMap) (stx : Syntax) (acc : Array (Pos × String)) :
    Array (Pos × String) :=
  match stx with
  | .node _ k args =>
    let acc := if k == ``Parser.Term.attrInstance then acc.push (posOf fm stx, headOf fm stx) else acc
    args.foldl (fun a s => attributesOf fm s a) acc
  | _ => acc

private def partsOf (stx : Syntax) : Option (List String) :=
  match stx with
  | .ident _ _ n _ => MitosGate.Lint.plainComponents n
  | _ => none

private def optName (opt : Syntax) : Option (List String) :=
  if MitosGate.Lint.isEmptyNode opt then some []
  else if opt[0].isIdent && (opt.getNumArgs == 1 || MitosGate.Lint.isEmptyNode opt[1]) then partsOf opt[0]
  else if opt.isIdent then partsOf opt
  else none

private def scopedOf (fm : FileMap) (cmd : Syntax) : Option (String × Scoped) :=
  let k := cmd.getKind
  let text (kw : String) (stx : Syntax) : String :=
    " ".intercalate (kw :: (MitosGate.Lint.tokensOf fm stx #[]).toList.map (·.text))
  if k == ``Parser.Command.namespace then some (text "namespace" cmd[1], .ns (partsOf cmd[1]))
  else if k == ``Parser.Command.section then some (text "section" cmd[2], .sec (optName cmd[2]))
  else if k == ``Parser.Command.end then some (text "end" cmd[1], .close (optName cmd[1]))
  else if k == ``Parser.Command.declaration then
    let d := cmd[1]
    if d.getKind == ``Parser.Command.definition || d.getKind == ``Parser.Command.theorem ||
        d.getKind == ``Parser.Command.abbrev then
      some (text (headOf fm d) d[1][0], .decl (partsOf d[1][0]))
    else none
  else none

private partial def identsOf (stx : Syntax) (acc : Array Syntax) : Array Syntax :=
  match stx with
  | .ident .. => acc.push stx
  | .node _ _ args => args.foldl (fun a s => identsOf s a) acc
  | _ => acc

partial def opensOf (fm : FileMap) (stx : Syntax) (acc : Array (Pos × String × Option (List String))) :
    Array (Pos × String × Option (List String)) :=
  match stx with
  | .node _ k args =>
    let found : Array Syntax :=
      if k == ``Parser.Command.openSimple || k == ``Parser.Command.openScoped then identsOf stx #[]
      else if k == ``Parser.Command.openOnly || k == ``Parser.Command.openHiding ||
          k == ``Parser.Command.openRenaming then #[stx[0]]
      else #[]
    let acc := found.foldl (fun a i => a.push (posOf fm i, headOf fm i, partsOf i)) acc
    args.foldl (fun a s => opensOf fm s a) acc
  | _ => acc

def read (env : Environment) (src : String) : IO Source := do
  match ← MitosGate.Lint.parse env src with
  | .error v => return { unparsed := some ((v.line, v.col), v.msg) }
  | .ok (fm, header, cmds) =>
    let mut modifiers := #[]
    let mut imports := #[]
    if !MitosGate.Lint.isEmptyNode header[0] then modifiers := modifiers.push (posOf fm header[0], "module")
    if !MitosGate.Lint.isEmptyNode header[1] then modifiers := modifiers.push (posOf fm header[1], "prelude")
    for imp in header[2].getArgs do
      unless MitosGate.Lint.isEmptyNode imp[0] && MitosGate.Lint.isEmptyNode imp[1] &&
          MitosGate.Lint.isEmptyNode imp[3] do
        modifiers := modifiers.push (posOf fm imp, s!"{headOf fm imp} import")
      let (text, mod) := match imp[4] with
        | .ident _ _ n _ => (n.toString, MitosGate.Lint.plainComponents n)
        | stx => (toString stx, none)
      imports := imports.push (posOf fm imp, text, mod)
    let commands := cmds.map fun cmd =>
      let kind := if cmd.getKind == ``Parser.Command.declaration then cmd[1].getKind else cmd.getKind
      (posOf fm cmd, headOf fm cmd, toString kind)
    let attributes := cmds.foldl (fun a c => attributesOf fm c a) #[]
    let tokens := (cmds.foldl (fun a c => MitosGate.Lint.tokensOf fm c a)
      (MitosGate.Lint.tokensOf fm header #[])).map fun t => ((t.line, t.col), t.text)
    let scopes := cmds.filterMap fun cmd => (scopedOf fm cmd).map fun (t, c) => (posOf fm cmd, t, c)
    let opens := cmds.foldl (fun a c => opensOf fm c a) #[]
    return { modifiers := modifiers.toList, imports := imports.toList, commands := commands.toList,
             attributes := attributes.toList, tokens := tokens.toList, scopes := scopes.toList,
             opens := opens.toList }

def check (env : Environment) (k : Kind) (file src : String) : IO (List String) := do
  return (problems k (← read env src)).map fun ((l, c), msg) => s!"{file}:{l}:{c}: {msg}"

#guard (walk [] [((1, 1), "namespace", .ns (some ["Mitos", "Impl"])), ((2, 1), "def", .decl (some ["f"])),
    ((3, 1), "section", .sec (some [])), ((4, 1), "def", .decl (some ["Refute", "g"])),
    ((5, 1), "end", .close (some [])), ((6, 1), "end", .close (some ["Impl"])),
    ((7, 1), "def", .decl (some ["h"])), ((8, 1), "end", .close (some ["Mitos"])),
    ((9, 1), "def", .decl (some ["Mitos", "Refute", "Mitos", "Spec", "X"])),
    ((10, 1), "def", .decl (some ["_root_", "Mitos", "Impl", "k"])),
    ((11, 1), "end", .close (some []))]).map (·.2.2) =
  [.entered ["Mitos", "Impl"], .declared ["Mitos", "Impl", "f"], .declared ["Mitos", "Impl", "Refute", "g"],
    .declared ["Mitos", "h"], .declared ["Mitos", "Refute", "Mitos", "Spec", "X"],
    .declared ["Mitos", "Impl", "k"], .unbalanced]
#guard (walk [] [((1, 1), "namespace", .ns (some ["Mitos"])), ((2, 1), "namespace", .ns (some ["Impl"])),
    ((3, 1), "def", .decl (some ["_root_", "Mitos", "Refute", "x"])), ((4, 1), "end", .close (some ["Mitos", "Impl"])),
    ((5, 1), "namespace", .ns none)]).map (·.2.2) =
  [.entered ["Mitos"], .entered ["Mitos", "Impl"], .declared ["Mitos", "Refute", "x"], .unreadable]
#guard Kind.impl.declOk ["Mitos", "Impl", "resolve"] && !Kind.impl.declOk ["Mitos", "Impl"] &&
  !Kind.impl.declOk ["Mitos", "Refute", "Mitos", "Spec", "X"] && !Kind.impl.declOk ["Mitos", "Mitos", "Impl", "resolve"] &&
  !Kind.impl.declOk ["Mitos", "Impl", "_root_", "x"]
#guard (Kind.refute [["Mitos", "Impl", "resolve"]]).declOk ["Mitos", "Impl", "resolve"] &&
  (Kind.refute [["Mitos", "Impl", "resolve"]]).declOk ["Mitos", "Refute", "Impl", "resolve"] &&
  !(Kind.refute [["Mitos", "Impl", "resolve"]]).declOk ["Mitos", "Impl", "helper"]
#guard Kind.proofs.declOk ["Mitos", "Impl", "resolve"] && !Kind.proofs.declOk ["Int", "x"]
#guard nsOk ["Mitos", "Impl"] && !nsOk ["Int"] && !nsOk ["Mitos", "_root_"] && !nsOk []
#guard tokenOk "Mitos.Impl.resolve" && tokenOk "decl_name%" && !tokenOk "with_decl_name%" &&
  !tokenOk "with_decl_name" && !tokenOk "macro_rules" && !tokenOk "Mitos.deriving"
#guard replaceProblems "def a := with_decl_name% N (let rec x := 0; 0)" ==
  ["`with_decl_name` is not allowed in a case's Lean text"]

end Mutants.Lint
