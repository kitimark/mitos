import MitosGate.Base.Text

namespace MitosGate.Yaml

def exprTok : List Char := "${{".toList

def allowedChar (c : Char) : Bool := c == '\n' || (' ' ≤ c && c ≤ '~')

inductive Seg where
  | key (k : String)
  | idx (i : Nat)
  deriving DecidableEq, Repr

inductive Node where
  | text (s : String)
  | seq (items : List Node)
  | map (entries : List (String × Node))
  deriving Repr

inductive Scalar where
  | text (s : String)
  | emptyMap
  | emptySeq
  deriving DecidableEq, Repr

structure Leaf where
  path : List Seg
  value : Scalar
  deriving DecidableEq, Repr

def Leaf.exprCount : Leaf → Nat
  | ⟨_, .text s⟩ => Base.Text.count exprTok s.toList
  | _ => 0

private def indexed (xs : List α) (i : Nat := 0) : List (Seg × α) :=
  match xs with
  | [] => []
  | x :: xs => (.idx i, x) :: indexed xs (i + 1)

def Node.children : Node → List (Seg × Node)
  | .text _ => []
  | .seq xs => indexed xs
  | .map es => es.map fun (k, n) => (.key k, n)

def Node.get? (n : Node) : List Seg → Option Node
  | [] => some n
  | s :: p => (n.children.lookup s).bind fun child => child.get? p

def Node.asScalar? : Node → Option Scalar
  | .text s => some (.text s)
  | .map [] => some .emptyMap
  | .seq [] => some .emptySeq
  | _ => none

def Node.scalarAt? (n : Node) (p : List Seg) : Option Scalar :=
  (n.get? p).bind Node.asScalar?

private def prepend (s : Seg) (l : Leaf) : Leaf := ⟨s :: l.path, l.value⟩

private def branchLeaves (xs : List (Seg × List Leaf)) : List Leaf :=
  xs.flatMap fun (s, ls) => ls.map (prepend s)

mutual
  def Node.leaves : Node → List Leaf
    | .text s => [⟨[], .text s⟩]
    | .seq [] => [⟨[], .emptySeq⟩]
    | .seq (n :: ns) => branchLeaves (indexed (n.leaves :: seqLeaves ns))
    | .map [] => [⟨[], .emptyMap⟩]
    | .map ((k, n) :: es) => branchLeaves ((.key k, n.leaves) :: mapLeaves es)
  private def seqLeaves : List Node → List (List Leaf)
    | [] => []
    | n :: ns => n.leaves :: seqLeaves ns
  private def mapLeaves : List (String × Node) → List (Seg × List Leaf)
    | [] => []
    | (k, n) :: es => (.key k, n.leaves) :: mapLeaves es
end

inductive Problem where
  | duplicateKey (k : String)
  | exprKey
  | mergeKey
  | emptyKey
  | char (c : Char)
  deriving DecidableEq, Repr

private def asciiFold (k : String) : List Char := k.toList.map fun c =>
  if 'A' ≤ c && c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

private def keyProblem? (keys : List String) : Option (List Seg × Problem) :=
  match keys with
  | [] => none
  | k :: ks =>
    if ks.any (fun other => asciiFold k == asciiFold other) then some ([.key k], .duplicateKey k)
    else if Base.Text.hasSub exprTok k.toList then some ([.key k], .exprKey)
    else if k == "<<" then some ([.key k], .mergeKey)
    else if k == "" then some ([.key k], .emptyKey)
    else match k.toList.find? (fun c => !allowedChar c) with
      | some c => some ([.key k], .char c)
      | none => keyProblem? ks

private def branchProblem? : List (Seg × Option (List Seg × Problem)) → Option (List Seg × Problem)
  | [] => none
  | (s, some (p, problem)) :: _ => some (s :: p, problem)
  | (_, none) :: xs => branchProblem? xs

mutual
  def Node.firstProblem? : Node → Option (List Seg × Problem)
    | .text s => (s.toList.find? fun c => !allowedChar c).map fun c => ([], .char c)
    | .seq ns => branchProblem? (indexed (seqProblems ns))
    | .map es => (keyProblem? (es.map Prod.fst)).orElse fun _ => branchProblem? (mapProblems es)
  private def seqProblems : List Node → List (Option (List Seg × Problem))
    | [] => []
    | n :: ns => n.firstProblem? :: seqProblems ns
  private def mapProblems : List (String × Node) → List (Seg × Option (List Seg × Problem))
    | [] => []
    | (k, n) :: es => (.key k, n.firstProblem?) :: mapProblems es
end

private theorem indexed_map (f : α → β) (xs : List α) (i : Nat) :
    indexed (xs.map f) i = (indexed xs i).map (fun (s, x) => (s, f x)) := by
  induction xs generalizing i with
  | nil => rfl
  | cons x xs ih => simp [indexed, ih]

private theorem indexed_snd (xs : List α) (i : Nat) :
    ((indexed xs i).map Prod.snd) = xs := by
  induction xs generalizing i with
  | nil => rfl
  | cons x xs ih => simp [indexed, ih]

private theorem indexed_lower (xs : List α) (i : Nat) (s : Seg) (x : α)
    (h : (s, x) ∈ indexed xs i) : ∃ j, s = .idx j ∧ i ≤ j := by
  induction xs generalizing i with
  | nil => simp [indexed] at h
  | cons y ys ih =>
    simp only [indexed, List.mem_cons] at h
    rcases h with h | h
    · cases h; exact ⟨i, rfl, Nat.le_refl _⟩
    · obtain ⟨j, hj, hi⟩ := ih _ h
      exact ⟨j, hj, by omega⟩

private theorem indexed_nodup (xs : List α) (i : Nat) :
    ((indexed xs i).map Prod.fst).Nodup := by
  induction xs generalizing i with
  | nil => simp [indexed]
  | cons x xs ih =>
    simp only [indexed, List.map_cons, List.nodup_cons]
    refine ⟨?_, ih _⟩
    intro h
    obtain ⟨⟨s, y⟩, hm, hs⟩ := List.mem_map.mp h
    obtain ⟨j, hj, hi⟩ := indexed_lower xs (i + 1) s y hm
    subst s
    have : j = i := Seg.idx.inj hs
    omega

private theorem seqLeaves_eq (ns : List Node) : seqLeaves ns = ns.map Node.leaves := by
  induction ns with
  | nil => rfl
  | cons n ns ih => simp [seqLeaves, ih]

private theorem mapLeaves_eq (es : List (String × Node)) :
    mapLeaves es = es.map (fun (k, n) => (.key k, n.leaves)) := by
  induction es with
  | nil => rfl
  | cons e es ih => cases e; simp [mapLeaves, ih]

private theorem seqProblems_eq (ns : List Node) : seqProblems ns = ns.map Node.firstProblem? := by
  induction ns with
  | nil => rfl
  | cons n ns ih => simp [seqProblems, ih]

private theorem mapProblems_eq (es : List (String × Node)) :
    mapProblems es = es.map (fun (k, n) => (.key k, n.firstProblem?)) := by
  induction es with
  | nil => rfl
  | cons e es ih => cases e; simp [mapProblems, ih]

private theorem branchProblem_none (xs : List (Seg × Option (List Seg × Problem))) :
    branchProblem? xs = none ↔ ∀ s p, (s, p) ∈ xs → p = none := by
  induction xs with
  | nil => simp [branchProblem?]
  | cons e xs ih =>
    rcases e with ⟨s, p⟩
    cases p with
    | none => simp only [branchProblem?, ih, List.mem_cons, Prod.mk.injEq]; grind
    | some p =>
      rcases p with ⟨path, problem⟩
      constructor
      · intro h; contradiction
      · intro h
        have := h s (some (path, problem)) (by simp)
        contradiction

private theorem keyProblem_none (ks : List String) (h : keyProblem? ks = none) :
    ks.Nodup ∧ ∀ k ∈ ks, Base.Text.hasSub exprTok k.toList = false := by
  induction ks with
  | nil => simp
  | cons k ks ih =>
    unfold keyProblem? at h
    split at h <;> try contradiction
    rename_i hd
    split at h <;> try contradiction
    rename_i he
    split at h <;> try contradiction
    split at h <;> try contradiction
    split at h <;> try contradiction
    obtain ⟨hn, hk⟩ := ih h
    refine ⟨List.nodup_cons.mpr ⟨?_, hn⟩, ?_⟩
    · intro hm
      have : ks.any (fun other => asciiFold k == asciiFold other) = true :=
        List.any_eq_true.mpr ⟨k, hm, by simp⟩
      contradiction
    · intro other hm
      rcases List.mem_cons.mp hm with rfl | hm
      · simpa using he
      · exact hk _ hm

private theorem orElse_none (a b : Option α) :
    (a.orElse fun _ => b) = none ↔ a = none ∧ b = none := by
  cases a <;> simp [Option.orElse]

private theorem children_ok (n : Node) (h : n.firstProblem? = none)
    (s : Seg) (child : Node) (hm : (s, child) ∈ n.children) : child.firstProblem? = none := by
  cases n with
  | text t => simp [Node.children] at hm
  | seq ns =>
    simp only [Node.firstProblem?, seqProblems_eq, indexed_map] at h
    exact (branchProblem_none _).mp h s child.firstProblem?
      (List.mem_map.mpr ⟨(s, child), hm, rfl⟩)
  | map es =>
    simp only [Node.firstProblem?, orElse_none, mapProblems_eq] at h
    apply (branchProblem_none _).mp h.2 s child.firstProblem?
    simp only [Node.children, List.mem_map] at hm
    obtain ⟨⟨k, c⟩, hm, he⟩ := hm
    cases he
    exact List.mem_map.mpr ⟨(k, c), hm, rfl⟩

private theorem children_nodup (n : Node) (h : n.firstProblem? = none) :
    (n.children.map Prod.fst).Nodup := by
  cases n with
  | text t => simp [Node.children]
  | seq ns => exact indexed_nodup _ _
  | map es =>
    have hk := (keyProblem_none _ ((orElse_none _ _).mp h).1).1
    simpa [Node.children, List.map_map, List.nodup_iff_pairwise_ne, List.pairwise_map] using hk

private theorem children_key_no_expr (n : Node) (h : n.firstProblem? = none)
    (k : String) (child : Node) (hm : (.key k, child) ∈ n.children) :
    Base.Text.hasSub exprTok k.toList = false := by
  cases n with
  | text t => simp [Node.children] at hm
  | seq ns =>
    obtain ⟨j, hj, _⟩ := indexed_lower ns 0 (.key k) child hm
    contradiction
  | map es =>
    have hk := (keyProblem_none _ ((orElse_none _ _).mp h).1).2
    simp only [Node.children, List.mem_map] at hm
    obtain ⟨⟨other, c⟩, hm, he⟩ := hm
    cases he
    exact hk _ (List.mem_map.mpr ⟨(other, c), hm, rfl⟩)

private theorem leaves_eq (n : Node) : n.leaves =
    match n.asScalar? with
    | some s => [⟨[], s⟩]
    | none => branchLeaves (n.children.map fun (s, child) => (s, child.leaves)) := by
  cases n with
  | text t => rfl
  | seq ns =>
    cases ns with
    | nil => rfl
    | cons n ns =>
      simpa only [Node.leaves, Node.asScalar?, Node.children, seqLeaves_eq, List.map_cons] using
        congrArg branchLeaves (indexed_map Node.leaves (n :: ns) 0)
  | map es => cases es with
    | nil => rfl
    | cons e es => cases e; simp [Node.leaves, Node.asScalar?, Node.children, mapLeaves_eq, Function.comp_def]

private theorem scalar_children (n : Node) (s : Scalar) (h : n.asScalar? = some s) :
    n.children = [] := by
  cases n with
  | text t => rfl
  | seq ns => cases ns <;> simp_all [Node.asScalar?, Node.children, indexed]
  | map es => cases es <;> simp_all [Node.asScalar?, Node.children]

private theorem tree_induction (P : Node → Prop)
    (step : ∀ n, (∀ s child, (s, child) ∈ n.children → P child) → P n) (n : Node) : P n := by
  apply Node.rec (motive_1 := P)
    (motive_2 := fun ns => ∀ n ∈ ns, P n)
    (motive_3 := fun es => ∀ e ∈ es, P e.2)
    (motive_4 := fun e => P e.2) ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ n
  · intro s; exact step _ (by simp [Node.children])
  · intro ns ih
    apply step
    intro s child hm
    apply ih child
    have hc : child ∈ (indexed ns).map Prod.snd := List.mem_map.mpr ⟨(s, child), hm, rfl⟩
    simpa [indexed_snd] using hc
  · intro es ih
    apply step
    intro s child hm
    simp only [Node.children, List.mem_map] at hm
    obtain ⟨⟨k, c⟩, hm, he⟩ := hm
    cases he
    exact ih _ hm
  · simp
  · intro head tail ih it; simpa using And.intro ih it
  · simp
  · intro head tail ih it; simpa using And.intro ih it
  · intro k child ih; exact ih

private theorem lookup_mem (xs : List (Seg × Node)) (hn : (xs.map Prod.fst).Nodup)
    (s : Seg) (n : Node) : xs.lookup s = some n ↔ (s, n) ∈ xs := by
  induction xs with
  | nil => simp
  | cons entry xs ih =>
    rcases entry with ⟨key, child⟩
    simp only [List.map_cons, List.nodup_cons] at hn
    by_cases he : s = key
    · subst key
      simp only [List.lookup_cons, beq_self_eq_true]
      constructor
      · intro h; cases h; simp
      · intro h
        rcases List.mem_cons.mp h with h | h
        · cases h; rfl
        · exact False.elim (hn.1 (List.mem_map.mpr ⟨(s, n), h, rfl⟩))
    · simp [List.lookup_cons, beq_eq_false_iff_ne.mpr he, ih hn.2, he]

private theorem mem_branch_nil (cs : List (Seg × Node)) (v : Scalar) :
    (⟨[], v⟩ : Leaf) ∉ branchLeaves (cs.map fun (s, c) => (s, c.leaves)) := by
  simp [branchLeaves, List.mem_flatMap, prepend]

private theorem mem_branch_cons (cs : List (Seg × Node)) (s : Seg) (p : List Seg) (v : Scalar) :
    (⟨s :: p, v⟩ : Leaf) ∈ branchLeaves (cs.map fun (s, c) => (s, c.leaves)) ↔
      ∃ c, (s, c) ∈ cs ∧ (⟨p, v⟩ : Leaf) ∈ c.leaves := by
  simp only [branchLeaves, List.mem_flatMap, List.mem_map]
  constructor
  · rintro ⟨⟨tag, ls⟩, ⟨⟨key, c⟩, hc, he⟩, ⟨l, hl, he'⟩⟩
    cases he
    cases l
    cases he'
    exact ⟨c, hc, hl⟩
  · rintro ⟨c, hc, hl⟩
    exact ⟨(s, c.leaves), ⟨(s, c), hc, rfl⟩, ⟨⟨p, v⟩, hl, rfl⟩⟩

private theorem node_mem_leaves (n : Node) (hn : n.firstProblem? = none) (l : Leaf) :
    l ∈ n.leaves ↔ n.scalarAt? l.path = some l.value := by
  induction n using tree_induction generalizing l with
  | step n ih =>
    rcases l with ⟨path, value⟩
    rw [leaves_eq]
    cases hs : n.asScalar? with
    | some scalar =>
      cases path <;> simp [hs, Node.scalarAt?, Node.get?, scalar_children n scalar hs, eq_comm]
    | none =>
      cases path with
      | nil => simp [hs, mem_branch_nil, Node.scalarAt?, Node.get?]
      | cons tag path =>
        simp only [mem_branch_cons, Node.scalarAt?, Node.get?]
        cases hc : n.children.lookup tag with
        | none =>
          simp only [Option.bind_none, reduceCtorEq, iff_false, not_exists, not_and]
          intro child hm
          have := (lookup_mem _ (children_nodup n hn) tag child).mpr hm
          simp [hc] at this
        | some child =>
          have hm := (lookup_mem _ (children_nodup n hn) tag child).mp hc
          have hi := ih tag child hm (children_ok n hn tag child hm) ⟨path, value⟩
          simp only [Option.bind_some]
          constructor
          · rintro ⟨other, ho, hl⟩
            have he := (lookup_mem _ (children_nodup n hn) tag other).mpr ho
            rw [hc] at he
            cases he
            exact hi.mp hl
          · intro hl; exact ⟨child, hm, hi.mpr hl⟩

private theorem branch_nodup (cs : List (Seg × Node))
    (hn : (cs.map Prod.fst).Nodup)
    (hc : ∀ s c, (s, c) ∈ cs → (c.leaves.map Leaf.path).Nodup) :
    ((branchLeaves (cs.map fun (s, c) => (s, c.leaves))).map Leaf.path).Nodup := by
  induction cs with
  | nil => simp [branchLeaves]
  | cons entry cs ih =>
    rcases entry with ⟨s, c⟩
    simp only [List.map_cons, List.nodup_cons] at hn
    simp only [List.map_cons, branchLeaves, List.flatMap_cons, List.map_append, List.nodup_append]
    refine ⟨?_, ih hn.2 (fun t child hm => hc t child (by simp [hm])), ?_⟩
    · simpa [List.map_map, prepend, Function.comp_def, List.nodup_iff_pairwise_ne,
        List.pairwise_map] using hc s c (by simp)
    · intro a ha b hb he
      obtain ⟨l, hl, ha⟩ := List.mem_map.mp ha
      obtain ⟨leaf, hleaf, hb⟩ := List.mem_map.mp hb
      obtain ⟨l', hl', hl⟩ := List.mem_map.mp hl
      have hpath : s :: l'.path = leaf.path :=
        (congrArg Leaf.path hl).trans (ha.trans (he.trans hb.symm))
      cases hp : leaf.path with
      | nil => simp [hp] at hpath
      | cons t path =>
        have hm : (⟨t :: path, leaf.value⟩ : Leaf) ∈
            branchLeaves (cs.map fun (s, c) => (s, c.leaves)) := by
          cases leaf with
          | mk lp lv =>
            change lp = t :: path at hp
            subst lp
            exact hleaf
        obtain ⟨child, hm, _⟩ := (mem_branch_cons cs t path leaf.value).mp hm
        have ht : s = t := by simpa [hp] using congrArg List.head? hpath
        subst t
        exact hn.1 (List.mem_map.mpr ⟨(s, child), hm, rfl⟩)

private theorem node_paths_nodup (n : Node) (hn : n.firstProblem? = none) :
    (n.leaves.map Leaf.path).Nodup := by
  induction n using tree_induction with
  | step n ih =>
    rw [leaves_eq]
    cases hs : n.asScalar? with
    | some scalar => simp
    | none =>
      exact branch_nodup n.children (children_nodup n hn)
        (fun s child hm => ih s child hm (children_ok n hn s child hm))

private theorem get_append (n : Node) (p q : List Seg) :
    n.get? (p ++ q) = (n.get? p).bind fun child => child.get? q := by
  induction p generalizing n with
  | nil => rfl
  | cons s p ih => simp [Node.get?, ih, Option.bind_assoc]

private theorem get_ok (n : Node) (hn : n.firstProblem? = none) (p : List Seg)
    (child : Node) (h : n.get? p = some child) : child.firstProblem? = none := by
  induction p generalizing n with
  | nil =>
    have he : n = child := by simpa [Node.get?] using h
    subst child
    exact hn
  | cons s p ih =>
    simp only [Node.get?, Option.bind_eq_some_iff] at h
    obtain ⟨next, hm, ht⟩ := h
    exact ih next (children_ok n hn s next ((lookup_mem _ (children_nodup n hn) s next).mp hm)) ht

structure Doc where
  root : Node
  ok : root.firstProblem? = none

def Doc.ofNode (n : Node) : Except (List Seg × Problem) Doc :=
  match h : n.firstProblem? with
  | none => .ok ⟨n, h⟩
  | some problem => .error problem

def Doc.leaves (d : Doc) : List Leaf := d.root.leaves

def Doc.scalarAt? (d : Doc) (p : List Seg) : Option Scalar := d.root.scalarAt? p


theorem Doc.mem_leaves_iff (d : Doc) (l : Leaf) :
    l ∈ d.leaves ↔ d.scalarAt? l.path = some l.value :=
  node_mem_leaves d.root d.ok l

theorem Doc.leaves_paths_nodup (d : Doc) : (d.leaves.map (·.path)).Nodup :=
  node_paths_nodup d.root d.ok

theorem Doc.key_no_expr (d : Doc) (h : (d.root.get? (p ++ [.key k])).isSome) :
    Base.Text.hasSub exprTok k.toList = false := by
  rw [get_append] at h
  cases hp : d.root.get? p with
  | none => simp [hp] at h
  | some n =>
    have hn := get_ok d.root d.ok p n hp
    simp only [hp, Option.bind_some, Node.get?] at h
    cases hc : n.children.lookup (.key k) with
    | none => simp [hc] at h
    | some child =>
      exact children_key_no_expr n hn k child ((lookup_mem _ (children_nodup n hn) _ _).mp hc)


example : (Node.map [("a", .text "1"), ("A", .text "2")]).firstProblem? =
    some ([.key "a"], .duplicateKey "a") := by decide +kernel
example : (Node.map [("${{x", .text "")]).firstProblem? = some ([.key "${{x"], .exprKey) := by decide +kernel
example : (Node.map [("<<", .map [])]).firstProblem? = some ([.key "<<"], .mergeKey) := by decide +kernel
example : (Node.map [("", .text "")]).firstProblem? = some ([.key ""], .emptyKey) := by decide +kernel
example : (Node.text "x\ty").firstProblem? = some ([], .char '\t') := by decide +kernel

private def workflowFixture : Node := .map [
  ("on", .map [("push", .map [])]),
  ("jobs", .map [("a", .map [("steps", .seq [.map [("run", .text "x")]])])])]

example : workflowFixture.leaves = [
    ⟨[.key "on", .key "push"], .emptyMap⟩,
    ⟨[.key "jobs", .key "a", .key "steps", .idx 0, .key "run"], .text "x"⟩] := by decide +kernel
example : (Node.map [("permissions", .map [])]).leaves =
    [⟨[.key "permissions"], .emptyMap⟩] := by decide +kernel
example : (Node.seq []).leaves = [⟨[], .emptySeq⟩] := by decide +kernel
example : workflowFixture.scalarAt? [.key "on", .key "push"] = some .emptyMap := by decide +kernel
example : (⟨[], .text "${{a}}${{b}}"⟩ : Leaf).exprCount = 2 := by decide +kernel
example : (⟨[], .emptyMap⟩ : Leaf).exprCount = 0 := by decide +kernel

end MitosGate.Yaml
