import MitosGate.Land

/-!
# What a pull request's comments say

`words` reads a pull request's issue comments into `Land.Word`s. Inline review comments and
reviews never speak.

Every agent posts through the owner's account, so the login cannot tell the owner from an agent.
What can: an app post carries the app's slug (`performed_via_github_app`), and a post made through
the account's token without an app ends with the adapter footer. So only an unedited comment from
the owner's login, with no slug and no trailing footer, is the owner typing. A footer inside a
`>` quote is not trailing, and a word line inside a quote, a fence or an indented block is not a
word.

REST keeps only the last `updated_at` and never the first text, so an edited comment cannot be
read as what was first posted. Any edit of a comment from the owner's login, whatever its slug and
body, is a hold: an ignored edit could hide a `/hold`. The hold sits just above every comment
created by the edit's second, so a word typed before the edit, or in the same second, does not
lift it, a later `/land` does, and a second edit only moves it later.

An app may speak only as an agent, through one top-level `mitos-protocol` fence holding a `land`
record for this pull request whose provider is the app's. The record is read by a parser over a
flat subset of JSON that keeps duplicate keys, which `Lean.Json.parse` would drop.

Every scanner here is structural over `List Char`, so the fixtures run in the kernel.
-/

namespace MitosGate.Speech

open Land (Sha Pr Teammate Word Mark newestOwner)

/-- `YYYYMMDDHHMMSS` in UTC. -/
abbrev Stamp := Nat

structure Comment where
  id : Nat
  login : String
  slug : Option String
  created : Stamp
  updated : Stamp
  body : String

def apps : List (String × String) := [("claude", "claude"), ("cursor", "grok")]

structure Ctx where
  owner : String
  pr : Pr
  known : List Sha
  apps : List (String × String) := Speech.apps

/-- No agent lands on its own `land` record until the owner delegates it. -/
def delegates : List Teammate := []

inductive Why
  | notOwner | unknownApp | noRecord | malformed | notLand | wrongTask | wrongProvider
  | footer | protocolFence | noWord
  | hold | severalWords | badArgument | unknownCommit | ambiguousCommit | noHead
  deriving DecidableEq

inductive Read
  | land (about : Sha)
  | hold (why : Why)
  | editHold
  | agent (who : Teammate) (about : Sha)
  | ignored (why : Why)
  deriving DecidableEq

/-! ## Lines -/

def lines : List Char → List (List Char)
  | [] => [[]]
  | '\n' :: cs => [] :: lines cs
  | c :: cs =>
    match lines cs with
    | [] => [[c]]
    | l :: ls => (c :: l) :: ls

def dropCR : List Char → List Char
  | ['\r'] => []
  | c :: cs => c :: dropCR cs
  | [] => []

def split (b : List Char) : List (List Char) := (lines b).map dropCR

def isSp (c : Char) : Bool := c == ' ' || c == '\t'

def blank (l : List Char) : Bool := l.all isSp

def trim (l : List Char) : List Char := ((l.dropWhile isSp).reverse.dropWhile isSp).reverse

/-- Markdown reads a line indented by four spaces or a tab as code, which never speaks. -/
def lead (l : List Char) : Option (List Char) :=
  let r := match l with
    | ' ' :: ' ' :: ' ' :: r => r
    | ' ' :: ' ' :: r => r
    | ' ' :: r => r
    | r => r
  match r with
  | ' ' :: _ | '\t' :: _ => none
  | _ => some r

def span (c : Char) : List Char → Nat × List Char
  | d :: r => if d = c then ((span c r).1 + 1, (span c r).2) else (0, d :: r)
  | [] => (0, [])

def opener (l : List Char) : Option (Char × Nat × List Char) :=
  match lead l with
  | some (c :: r) =>
    if c = '`' ∨ c = '~' then
      if 3 ≤ (span c (c :: r)).1 then some (c, (span c (c :: r)).1, (span c (c :: r)).2)
      else none
    else none
  | _ => none

def closes (c : Char) (n : Nat) (l : List Char) : Bool :=
  match lead l with
  | some r => decide (n ≤ (span c r).1) && blank (span c r).2
  | none => false

def isProtocol (info : List Char) : Bool := trim info == "mitos-protocol".toList

structure Scan where
  top : List (List Char)
  protocol : List (Bool × List (List Char))

/-- A fence that never closes runs to the end of the body. -/
def scanGo : List (List Char) → Option (Char × Nat × Bool × List (List Char)) → Scan → Scan
  | [], none, s => s
  | [], some (_, _, p, body), s =>
    if p then { s with protocol := s.protocol ++ [(false, body)] } else s
  | l :: ls, none, s =>
    match opener l with
    | none => scanGo ls none { s with top := s.top ++ [l] }
    | some (c, n, info) => scanGo ls (some (c, n, isProtocol info, [])) s
  | l :: ls, some (c, n, p, body), s =>
    if closes c n l then
      scanGo ls none (if p then { s with protocol := s.protocol ++ [(true, body)] } else s)
    else scanGo ls (some (c, n, p, body ++ [l])) s

def scan (b : List Char) : Scan := scanGo (split b) none ⟨[], []⟩

def lastNonBlank : List (List Char) → Option (List Char)
  | [] => none
  | l :: ls =>
    match lastNonBlank ls with
    | some x => some x
    | none => if blank l then none else some l

def footer (b : List Char) : Bool :=
  match lastNonBlank (split b) with
  | some l =>
    match lead l with
    | some r => "_Generated by".toList.isPrefixOf r
    | none => false
  | none => false

/-! ## The owner's words -/

inductive Line
  | land (arg : List Char)
  | hold
  deriving DecidableEq

/-- A doubtful hold is the safe side, so `/hold` with any text after it holds, while `/land` counts
only as a token of its own. -/
def word? (l : List Char) : Option Line :=
  match lead l with
  | some ('/' :: r) =>
    if "hold".toList.isPrefixOf r then some .hold
    else
      match r with
      | 'l' :: 'a' :: 'n' :: 'd' :: rest =>
        match rest with
        | [] => some (.land [])
        | c :: _ => if isSp c then some (.land (trim rest)) else none
      | _ => none
  | _ => none

def ownerLines (b : List Char) : Except Why (List Line) :=
  if footer b then .error .footer
  else if (scan b).protocol.isEmpty then .ok ((scan b).top.filterMap word?)
  else .error .protocolFence

def hex (c : Char) : Bool := "0123456789abcdef".toList.contains c

def isSha (s : List Char) : Bool := s.length == 40 && s.all hex

def digit (c : Char) : Bool := "0123456789".toList.contains c

def num : List Char → Nat → Option Nat
  | [], acc => some acc
  | c :: cs, acc => if digit c then num cs (acc * 10 + (c.toNat - '0'.toNat)) else none

def stamp? : List Char → Option Stamp
  | [y1, y2, y3, y4, '-', m1, m2, '-', d1, d2, 'T', h1, h2, ':', n1, n2, ':', s1, s2, 'Z'] =>
    num [y1, y2, y3, y4, m1, m2, d1, d2, h1, h2, n1, n2, s1, s2] 0
  | _ => none

def pushLike (k : String) : Bool := k == "push" || k == "force_push" || k == "branch_creation"

def stamps : List Carry.Push → Option (List (Stamp × Carry.Push))
  | [] => some []
  | p :: ps =>
    match stamp? p.time.toList, stamps ps with
    | some t, some r => some ((t, p) :: r)
    | _, _ => none

def latest (l : List (Stamp × Carry.Push)) : Nat := l.foldr (fun e m => max e.1 m) 0

/-- The head when a comment of second `t` was posted: the commit the newest push before `t` left.
A push in second `t` itself may have come before or after the comment, so there is none. -/
def headAt (pushes : List Carry.Push) (t : Stamp) : Option Sha :=
  match stamps pushes with
  | none => none
  | some ts =>
    if ts.any (·.1 == t) then none
    else
      match (ts.filter (·.1 < t)).filter (·.1 == latest (ts.filter (·.1 < t))) with
      | [] => none
      | (_, p) :: rest =>
        if pushLike p.kind && rest.all (fun e => pushLike e.2.kind && e.2.after == p.after) then
          some p.after
        else none

def matching (known : List Sha) (p : List Char) : List Sha :=
  known.filter fun s => p.isPrefixOf s.toList

/-- A full sha stands for itself, seen or not: an unseen one has no content id, so it gives no
entry in `Land`. -/
def resolve (known : List Sha) (p : List Char) : Option Sha :=
  if p.length = 40 then some (String.ofList p)
  else
    match matching known p with
    | [] => none
    | s :: rest => if rest.all (· == s) then some s else none

def target (x : Ctx) (pushes : List Carry.Push) (t : Stamp) (arg : List Char) : Option Sha :=
  if arg = [] then headAt pushes t
  else if 7 ≤ arg.length ∧ arg.length ≤ 40 ∧ arg.all hex = true then resolve x.known arg
  else none

def unresolved (x : Ctx) (arg : List Char) : Why :=
  if arg = [] then .noHead
  else if 7 ≤ arg.length ∧ arg.length ≤ 40 ∧ arg.all hex = true then
    if matching x.known arg = [] then .unknownCommit else .ambiguousCommit
  else .badArgument

def ownerRead (x : Ctx) (pushes : List Carry.Push) (t : Stamp) (b : List Char) : Read :=
  match ownerLines b with
  | .error why => .ignored why
  | .ok [] => .ignored .noWord
  | .ok [.hold] => .hold .hold
  | .ok [.land arg] =>
    match target x pushes t arg with
    | some s => .land s
    | none => .hold (unresolved x arg)
  | .ok _ => .hold .severalWords

/-! ## An agent's record -/

inductive Val
  | str (s : List Char)
  | num (n : Nat)
  | obj (kvs : List (List Char × Val))

def isWs (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == '\r'

def skipWs : List Char → List Char
  | c :: r => if isWs c then skipWs r else c :: r
  | [] => []

/-- No `land` record needs an escape, so a string with one is malformed. -/
def strBody : List Char → Option (List Char × List Char)
  | '"' :: r => some ([], r)
  | c :: r =>
    if c == '\\' || c.toNat < 32 then none
    else (strBody r).map fun (s, r') => (c :: s, r')
  | [] => none

def digits : List Char → List Char × List Char
  | c :: r => if digit c then (c :: (digits r).1, (digits r).2) else ([], c :: r)
  | [] => ([], [])

def scalar : List Char → Option (Val × List Char)
  | '"' :: r => (strBody r).map fun (s, r') => (.str s, r')
  | c :: r =>
    if digit c then
      if c == '0' && (digits (c :: r)).1.length > 1 then none
      else (num (digits (c :: r)).1 0).map fun n => (.num n, (digits (c :: r)).2)
    else none
  | [] => none

def members (value : List Char → Option (Val × List Char)) :
    Nat → List Char → Option (List (List Char × Val) × List Char)
  | 0, _ => none
  | n + 1, cs =>
    match skipWs cs with
    | '"' :: r =>
      match strBody r with
      | none => none
      | some (k, r) =>
        match skipWs r with
        | ':' :: r =>
          match value (skipWs r) with
          | none => none
          | some (v, r) =>
            match skipWs r with
            | ',' :: r => (members value n r).map fun (kvs, r) => ((k, v) :: kvs, r)
            | '}' :: r => some ([(k, v)], r)
            | _ => none
        | _ => none
    | _ => none

def object (value : List Char → Option (Val × List Char)) (cs : List Char) :
    Option (List (List Char × Val) × List Char) :=
  match skipWs cs with
  | '{' :: r =>
    match skipWs r with
    | '}' :: r => some ([], r)
    | r => members value r.length r
  | _ => none

def value (cs : List Char) : Option (Val × List Char) :=
  match cs with
  | '{' :: _ => (object scalar cs).map fun (kvs, r) => (.obj kvs, r)
  | _ => scalar cs

def distinct : List (List Char) → Bool
  | [] => true
  | k :: ks => !ks.contains k && distinct ks

def get (kvs : List (List Char × Val)) (k : String) : Option Val := kvs.lookup k.toList

structure Record where
  task : Nat
  provider : String
  teammate : String
  head : Sha

def recordKeys : List (List Char) := ["v", "kind", "task", "as", "head", "cause"].map String.toList

def fields? (cs : List Char) : Option (List (List Char × Val)) :=
  match object value cs with
  | some (kvs, rest) => if (skipWs rest).isEmpty && distinct (kvs.map (·.1)) then some kvs else none
  | none => none

def teammate? : Option Val → Option (String × String)
  | some (.obj as) =>
    if as.length == 2 && distinct (as.map (·.1)) then
      match get as "provider", get as "teammate" with
      | some (.str p), some (.str t) =>
        if p.isEmpty || t.isEmpty then none else some (String.ofList p, String.ofList t)
      | _, _ => none
    else none
  | _ => none

def sha? : Option Val → Option Sha
  | some (.str s) => if isSha s then some (String.ofList s) else none
  | _ => none

def record? (cs : List Char) : Except Why Record :=
  match fields? cs with
  | none => .error .malformed
  | some kvs =>
    match get kvs "v", get kvs "kind" with
    | some (.num 1), some (.str k) =>
      if k != "land".toList then .error .notLand
      else if !kvs.all (fun kv => recordKeys.contains kv.1) then .error .malformed
      else
        match get kvs "task", teammate? (get kvs "as"), sha? (get kvs "head") with
        | some (.num task), some (p, t), some head => .ok ⟨task, p, t, head⟩
        | _, _, _ => .error .malformed
    | _, _ => .error .malformed

def joinLines : List (List Char) → List Char
  | [] => []
  | [l] => l
  | l :: ls => l ++ '\n' :: joinLines ls

def agentRead (x : Ctx) (provider : String) (b : List Char) : Read :=
  match (scan b).protocol with
  | [(true, body)] =>
    match record? (joinLines body) with
    | .error why => .ignored why
    | .ok r =>
      if r.task ≠ x.pr then .ignored .wrongTask
      else if r.provider ≠ provider then .ignored .wrongProvider
      else .agent ⟨provider, r.teammate⟩ r.head
  | [] => .ignored .noRecord
  | _ => .ignored .malformed

/-! ## One comment, then the list -/

def read (x : Ctx) (pushes : List Carry.Push) (c : Comment) : Read :=
  if c.login ≠ x.owner then .ignored .notOwner
  else if c.updated ≠ c.created then .editHold
  else
    match c.slug with
    | some s =>
      match x.apps.lookup s with
      | some p => agentRead x p c.body.toList
      | none => .ignored .unknownApp
    | none => ownerRead x pushes c.created c.body.toList

def lastBy (cs : List Comment) (c : Comment) : Nat :=
  cs.foldr (fun d k => if d.created ≤ c.updated then max d.id k else k) c.id

def editPos (cs : List Comment) (c : Comment) : Nat := 2 * lastBy cs c + 1

def Read.pos (r : Read) (cs : List Comment) (c : Comment) : Nat :=
  match r with
  | .editHold => editPos cs c
  | _ => 2 * c.id

def Read.word : Read → Nat → Option Word
  | .land s, n => some (.ownerLand ⟨n, s⟩)
  | .hold _, n => some (.ownerHold n)
  | .editHold, n => some (.ownerHold n)
  | .agent t s, n => some (.agentLand t ⟨n, s⟩)
  | .ignored _, _ => none

def Read.byOwner : Read → Bool
  | .land _ | .hold _ | .editHold => true
  | .agent _ _ | .ignored _ => false

/-- Starting from the pull request's number gives the holds of two empty incomplete reads different
positions, since `land` refuses a snapshot where two words share one. -/
def top (x : Ctx) (cs : List Comment) : Nat := cs.foldr (fun d k => max d.id k) x.pr

/-- Two words at one position become one hold. Only an edit hold shares a position with another
word when comment ids are distinct, and then both are holds. -/
def place (w : Word) : List Word → List Word
  | [] => [w]
  | v :: vs =>
    if w.said < v.said then w :: v :: vs
    else if v.said < w.said then v :: place w vs
    else .ownerHold w.said :: vs

def arrange (ws : List Word) : List Word := ws.foldr place []

def said (x : Ctx) (cs : List Comment) (pushes : List Carry.Push) (complete : Bool) : List Word :=
  let ws := cs.filterMap fun c => (read x pushes c).word ((read x pushes c).pos cs c)
  if complete then ws else .ownerHold (2 * top x cs + 1) :: ws

/-- The words, ascending by position, and why each other comment says nothing. A read that may
have missed comments (`complete = false`) adds a hold above every word. -/
def words (x : Ctx) (cs : List Comment) (pushes : List Carry.Push) (complete : Bool) :
    List Word × List (Nat × Why) :=
  (arrange (said x cs pushes complete),
    cs.filterMap fun c =>
      match read x pushes c with
      | .ignored why => some (c.id, why)
      | _ => none)

/-! ## Statements -/

def AppNeverOwner : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) n w, c.slug ≠ none → c.updated = c.created →
    (read x pushes c).word n = some w → w.byOwner = false

def FooterIsNeverOwner : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) n w, footer c.body.toList = true → c.updated = c.created →
    (read x pushes c).word n = some w → w.byOwner = false

def EditHoldsWhateverItSays : Prop :=
  ∀ (x : Ctx) cs pushes b (c : Comment), c ∈ cs → c.login = x.owner → c.updated ≠ c.created →
    read x pushes c = .editHold ∧ Word.ownerHold (editPos cs c) ∈ (words x cs pushes b).1

def EditHoldBeatsEarlierComments : Prop :=
  ∀ (x : Ctx) cs pushes b (c d : Comment), c ∈ cs → c.login = x.owner →
    c.updated ≠ c.created → d ∈ cs → d.created ≤ c.updated →
    2 * d.id < editPos cs c ∧
      ∀ m, newestOwner (words x cs pushes b).1 = some (.ownerLand m) → editPos cs c < m.said

def SecondEditOnlyMovesLater : Prop :=
  ∀ (x : Ctx) pushes cs (c : Comment) t, c.login = x.owner → c.created < c.updated →
    c.updated ≤ t →
    read x pushes { c with updated := t } = .editHold ∧
      editPos cs c ≤ editPos cs { c with updated := t }

def AgentNeedsSlugProviderTaskHead : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) who about, read x pushes c = .agent who about →
    c.login = x.owner ∧ c.updated = c.created ∧
    ∃ s, c.slug = some s ∧ x.apps.lookup s = some who.provider ∧
    ∃ body r, (scan c.body.toList).protocol = [(true, body)] ∧ record? (joinLines body) = .ok r ∧
      r.task = x.pr ∧ r.provider = who.provider ∧ r.teammate = who.name ∧ r.head = about ∧
      isSha about.toList = true

def FenceDuplicateKeyMalformed : Prop :=
  ∀ cs kvs rest, object value cs = some (kvs, rest) →
    (distinct (kvs.map (·.1)) = false ∨
      ∃ as, get kvs "as" = some (.obj as) ∧ distinct (as.map (·.1)) = false) →
    ∀ r, record? cs ≠ .ok r

def SeveralWordLinesHold : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) ls, c.login = x.owner → c.updated = c.created →
    c.slug = none → ownerLines c.body.toList = .ok ls → 2 ≤ ls.length →
    read x pushes c = .hold .severalWords

def UnresolvedLandHolds : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) arg, c.login = x.owner → c.updated = c.created →
    c.slug = none → ownerLines c.body.toList = .ok [.land arg] →
    target x pushes c.created arg = none → ∃ why, read x pushes c = .hold why

def ResolveUnique : Prop :=
  ∀ known p s, p.length < 40 → resolve known p = some s →
    s ∈ known ∧ p.isPrefixOf s.toList = true ∧
      ∀ s' ∈ known, p.isPrefixOf s'.toList = true → s' = s

def ResolveFullSelf : Prop :=
  ∀ known (p : List Char), p.length = 40 → resolve known p = some (String.ofList p)

def HeadAtSound : Prop :=
  ∀ pushes t s, headAt pushes t = some s →
    ∃ p ∈ pushes, p.after = s ∧ pushLike p.kind = true ∧
      ∃ tp, stamp? p.time.toList = some tp ∧ tp < t ∧
        ∀ q ∈ pushes, ∃ tq, stamp? q.time.toList = some tq ∧ tq ≠ t ∧ (tq < t → tq ≤ tp) ∧
          (tq = tp → pushLike q.kind = true ∧ q.after = s)

def SameSecondUnknown : Prop :=
  ∀ pushes t (p : Carry.Push), p ∈ pushes → stamp? p.time.toList = some t →
    headAt pushes t = none

def IncompleteReadHolds : Prop :=
  ∀ x cs pushes, ∃ n, newestOwner (words x cs pushes false).1 = some (.ownerHold n)

def PositionsAscendingDistinct : Prop :=
  ∀ x cs pushes b, ((words x cs pushes b).1.map Word.said).Pairwise (· < ·)

def WordTraces : Prop :=
  ∀ x cs pushes b, ∀ u ∈ (words x cs pushes b).1,
    ((∃ c ∈ cs, (read x pushes c).word ((read x pushes c).pos cs c) = some u) ∨
      u = .ownerHold u.said) ∧
    ((∃ d ∈ cs, u.said = 2 * d.id ∨ u.said = 2 * d.id + 1) ∨
      (b = false ∧ u.said = 2 * top x cs + 1))

def OwnerLandIsTyped : Prop :=
  ∀ (x : Ctx) cs pushes b m, Word.ownerLand m ∈ (words x cs pushes b).1 →
    ∃ c ∈ cs, c.login = x.owner ∧ c.slug = none ∧ c.updated = c.created ∧
      footer c.body.toList = false ∧ m.said = 2 * c.id ∧
      ∃ arg, ownerLines c.body.toList = .ok [.land arg] ∧ target x pushes c.created arg = some m.about

/-! ## Proofs -/

theorem word_said {r : Read} {n : Nat} {w : Word} (h : r.word n = some w) : w.said = n := by
  cases r <;> simp [Read.word] at h <;> subst h <;> rfl

theorem word_byOwner {r : Read} {n : Nat} {w : Word} (h : r.word n = some w) :
    w.byOwner = r.byOwner := by
  cases r <;> simp [Read.word] at h <;> subst h <;> rfl

theorem agentRead_byOwner (x : Ctx) (p : String) (b : List Char) :
    (agentRead x p b).byOwner = false := by
  unfold agentRead
  repeat' split
  all_goals rfl

theorem read_slug {x : Ctx} {pushes : List Carry.Push} {c : Comment} {s : String}
    (hs : c.slug = some s) (hu : c.updated = c.created) : (read x pushes c).byOwner = false := by
  unfold read
  by_cases ho : c.login = x.owner
  · simp only [ho, hu, ne_eq, not_true_eq_false, ite_false, hs]
    split
    · exact agentRead_byOwner _ _ _
    · rfl
  · simp [ho, Read.byOwner]

theorem appNeverOwner : AppNeverOwner := by
  intro x pushes c n w hs hu hw
  obtain ⟨s, hs⟩ := Option.ne_none_iff_exists'.1 hs
  rw [word_byOwner hw, read_slug hs hu]

theorem footerIsNeverOwner : FooterIsNeverOwner := by
  intro x pushes c n w hf hu hw
  rw [word_byOwner hw]
  cases hs : c.slug with
  | some s => exact read_slug hs hu
  | none =>
    unfold read
    by_cases ho : c.login = x.owner
    · simp only [ho, hu, ne_eq, not_true_eq_false, ite_false, hs, ownerRead, ownerLines, hf,
        ite_true]
      rfl
    · simp [ho, Read.byOwner]

theorem read_edited {x : Ctx} {pushes : List Carry.Push} {c : Comment} (ho : c.login = x.owner)
    (hu : c.updated ≠ c.created) : read x pushes c = .editHold := by
  simp [read, ho, hu]

/-! ### Placing words -/

theorem place_mem {w u : Word} {vs : List Word} (h : u ∈ place w vs) :
    u = w ∨ u ∈ vs ∨ u = .ownerHold w.said := by
  induction vs with
  | nil => simp [place] at h; exact .inl h
  | cons v vs ih =>
    simp only [place] at h
    split at h
    · rcases List.mem_cons.1 h with h | h
      · exact .inl h
      · exact .inr (.inl h)
    · split at h
      · rcases List.mem_cons.1 h with h | h
        · exact .inr (.inl (h ▸ List.mem_cons_self))
        · rcases ih h with h | h | h
          · exact .inl h
          · exact .inr (.inl (List.mem_cons_of_mem _ h))
          · exact .inr (.inr h)
      · rcases List.mem_cons.1 h with h | h
        · exact .inr (.inr h)
        · exact .inr (.inl (List.mem_cons_of_mem _ h))

theorem place_keeps (w : Word) (vs : List Word) :
    (∃ u ∈ place w vs, u.said = w.said ∧ (u = w ∨ u = .ownerHold w.said)) ∧
      ∀ v ∈ vs, ∃ u ∈ place w vs, u.said = v.said ∧ (u = v ∨ u = .ownerHold v.said) := by
  induction vs with
  | nil => exact ⟨⟨w, by simp [place]⟩, by simp⟩
  | cons v vs ih =>
    simp only [place]
    split
    · exact ⟨⟨w, List.mem_cons_self, rfl, .inl rfl⟩,
        fun y hy => ⟨y, List.mem_cons_of_mem _ hy, rfl, .inl rfl⟩⟩
    · split
      · obtain ⟨⟨u, hu, hs, he⟩, hr⟩ := ih
        refine ⟨⟨u, List.mem_cons_of_mem _ hu, hs, he⟩, fun y hy => ?_⟩
        rcases List.mem_cons.1 hy with rfl | hy
        · exact ⟨y, List.mem_cons_self, rfl, .inl rfl⟩
        · obtain ⟨u, hu, hs, he⟩ := hr y hy
          exact ⟨u, List.mem_cons_of_mem _ hu, hs, he⟩
      · next h1 h2 =>
        have he : v.said = w.said := by omega
        refine ⟨⟨_, List.mem_cons_self, rfl, .inr rfl⟩, fun y hy => ?_⟩
        rcases List.mem_cons.1 hy with rfl | hy
        · exact ⟨_, List.mem_cons_self, show w.said = y.said from he.symm, .inr (by rw [he])⟩
        · exact ⟨y, List.mem_cons_of_mem _ hy, rfl, .inl rfl⟩

theorem place_sorted (w : Word) {vs : List Word} (h : vs.Pairwise (·.said < ·.said)) :
    (place w vs).Pairwise (·.said < ·.said) := by
  induction vs with
  | nil => simp [place]
  | cons v vs ih =>
    rw [List.pairwise_cons] at h
    simp only [place]
    split
    · next hl =>
      refine List.Pairwise.cons (fun y hy => ?_) (List.Pairwise.cons h.1 h.2)
      rcases List.mem_cons.1 hy with rfl | hy
      · exact hl
      · exact Nat.lt_trans hl (h.1 y hy)
    · split
      · next hl =>
        refine List.Pairwise.cons (fun y hy => ?_) (ih h.2)
        rcases place_mem hy with rfl | hy | rfl
        · exact hl
        · exact h.1 y hy
        · exact hl
      · next h1 h2 =>
        have he : v.said = w.said := by omega
        refine List.Pairwise.cons (fun y hy => ?_) h.2
        show w.said < y.said
        rw [← he]
        exact h.1 y hy

theorem arrange_sorted (ws : List Word) : (arrange ws).Pairwise (·.said < ·.said) := by
  induction ws with
  | nil => exact List.Pairwise.nil
  | cons w ws ih => exact place_sorted w ih

theorem arrange_mem {ws : List Word} {u : Word} (h : u ∈ arrange ws) :
    u ∈ ws ∨ ∃ w ∈ ws, u = .ownerHold w.said := by
  induction ws with
  | nil => cases h
  | cons w ws ih =>
    rcases place_mem h with rfl | h | rfl
    · exact .inl List.mem_cons_self
    · rcases ih h with h | ⟨v, hv, rfl⟩
      · exact .inl (List.mem_cons_of_mem _ h)
      · exact .inr ⟨v, List.mem_cons_of_mem _ hv, rfl⟩
    · exact .inr ⟨w, List.mem_cons_self, rfl⟩

theorem arrange_keeps {ws : List Word} {w : Word} (h : w ∈ ws) :
    ∃ u ∈ arrange ws, u.said = w.said ∧ (u = w ∨ u = .ownerHold w.said) := by
  induction ws with
  | nil => cases h
  | cons v ws ih =>
    rcases List.mem_cons.1 h with rfl | h
    · exact (place_keeps w _).1
    · obtain ⟨u, hu, hs, he⟩ := ih h
      obtain ⟨u', hu', hs', he'⟩ := (place_keeps v _).2 u hu
      refine ⟨u', hu', hs'.trans hs, ?_⟩
      rcases he' with rfl | rfl
      · exact he
      · exact .inr (by rw [hs])

theorem arrange_hold {ws : List Word} {n : Nat} (h : .ownerHold n ∈ ws) :
    .ownerHold n ∈ arrange ws := by
  obtain ⟨u, hu, -, he⟩ := arrange_keeps h
  rcases he with rfl | rfl <;> exact hu

theorem arrange_nodup (ws : List Word) : ((arrange ws).map Word.said).Nodup := by
  have := arrange_sorted ws
  rw [List.Nodup, List.pairwise_map]
  exact this.imp fun h => Nat.ne_of_lt h

theorem positionsAscendingDistinct : PositionsAscendingDistinct := by
  intro x cs pushes b
  rw [List.pairwise_map]
  exact arrange_sorted _

/-! ### Positions -/

theorem lastBy_ge (cs : List Comment) (c : Comment) :
    c.id ≤ lastBy cs c ∧ ∀ d ∈ cs, d.created ≤ c.updated → d.id ≤ lastBy cs c := by
  induction cs with
  | nil => simp [lastBy]
  | cons e cs ih =>
    simp only [lastBy, List.foldr_cons] at ih ⊢
    obtain ⟨h1, h2⟩ := ih
    split
    · refine ⟨Nat.le_trans h1 (Nat.le_max_right _ _), fun d hd hc => ?_⟩
      rcases List.mem_cons.1 hd with rfl | hd
      · exact Nat.le_max_left _ _
      · exact Nat.le_trans (h2 d hd hc) (Nat.le_max_right _ _)
    · next hn =>
      refine ⟨h1, fun d hd hc => ?_⟩
      rcases List.mem_cons.1 hd with rfl | hd
      · exact absurd hc hn
      · exact h2 d hd hc

theorem lastBy_of (cs : List Comment) (c : Comment) :
    lastBy cs c = c.id ∨ ∃ d ∈ cs, lastBy cs c = d.id := by
  induction cs with
  | nil => exact .inl rfl
  | cons e cs ih =>
    simp only [lastBy, List.foldr_cons] at ih ⊢
    split
    · rcases Nat.le_total e.id (cs.foldr (fun d k => if d.created ≤ c.updated then max d.id k else k) c.id) with h | h
      · rw [Nat.max_eq_right h]
        rcases ih with h | ⟨d, hd, h⟩
        · exact .inl h
        · exact .inr ⟨d, List.mem_cons_of_mem _ hd, h⟩
      · rw [Nat.max_eq_left h]
        exact .inr ⟨e, List.mem_cons_self, rfl⟩
    · rcases ih with h | ⟨d, hd, h⟩
      · exact .inl h
      · exact .inr ⟨d, List.mem_cons_of_mem _ hd, h⟩

theorem lastBy_mono (cs : List Comment) (c : Comment) {t : Stamp} (ht : c.updated ≤ t) :
    lastBy cs c ≤ lastBy cs { c with updated := t } := by
  induction cs with
  | nil => exact Nat.le_refl _
  | cons e cs ih =>
    simp only [lastBy, List.foldr_cons] at ih ⊢
    split
    · next he =>
      have : e.created ≤ t := Nat.le_trans he ht
      simp only [this, ite_true]
      exact Nat.max_le.2 ⟨Nat.le_max_left _ _, Nat.le_trans ih (Nat.le_max_right _ _)⟩
    · split
      · exact Nat.le_trans ih (Nat.le_max_right _ _)
      · exact ih

theorem top_ge (x : Ctx) (cs : List Comment) : x.pr ≤ top x cs ∧ ∀ d ∈ cs, d.id ≤ top x cs := by
  induction cs with
  | nil => simp [top]
  | cons e cs ih =>
    simp only [top, List.foldr_cons] at ih ⊢
    refine ⟨Nat.le_trans ih.1 (Nat.le_max_right _ _), fun d hd => ?_⟩
    rcases List.mem_cons.1 hd with rfl | hd
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih.2 d hd) (Nat.le_max_right _ _)

theorem lastBy_le_top (x : Ctx) {cs : List Comment} {c : Comment} (hc : c ∈ cs) :
    lastBy cs c ≤ top x cs := by
  rcases lastBy_of cs c with h | ⟨d, hd, h⟩ <;> rw [h]
  · exact (top_ge x cs).2 c hc
  · exact (top_ge x cs).2 d hd

theorem pos_cases (r : Read) (cs : List Comment) (c : Comment) :
    r.pos cs c = 2 * c.id ∨ r.pos cs c = editPos cs c := by
  cases r <;> simp [Read.pos]

theorem pos_le_top (x : Ctx) (r : Read) {cs : List Comment} {c : Comment} (hc : c ∈ cs) :
    r.pos cs c ≤ 2 * top x cs + 1 := by
  rcases pos_cases r cs c with h | h <;> rw [h]
  · have := (top_ge x cs).2 c hc; omega
  · have := lastBy_le_top x hc; simp only [editPos]; omega

theorem pos_traces (r : Read) (cs : List Comment) (c : Comment) (hc : c ∈ cs) :
    ∃ d ∈ cs, r.pos cs c = 2 * d.id ∨ r.pos cs c = 2 * d.id + 1 := by
  rcases pos_cases r cs c with h | h
  · exact ⟨c, hc, .inl h⟩
  · rw [h]
    rcases lastBy_of cs c with h' | ⟨d, hd, h'⟩
    · exact ⟨c, hc, .inr (by simp [editPos, h'])⟩
    · exact ⟨d, hd, .inr (by simp [editPos, h'])⟩

theorem mem_said {x : Ctx} {cs : List Comment} {pushes : List Carry.Push} {b : Bool} {w : Word} :
    w ∈ said x cs pushes b ↔
      (b = false ∧ w = .ownerHold (2 * top x cs + 1)) ∨
        ∃ c ∈ cs, (read x pushes c).word ((read x pushes c).pos cs c) = some w := by
  cases b <;> simp [said, List.mem_filterMap]

theorem said_le_top {x : Ctx} {cs : List Comment} {pushes : List Carry.Push} {b : Bool}
    {w : Word} (h : w ∈ said x cs pushes b) : w.said ≤ 2 * top x cs + 1 := by
  rcases mem_said.1 h with ⟨-, rfl⟩ | ⟨c, hc, hw⟩
  · exact Nat.le_refl _
  · rw [word_said hw]; exact pos_le_top x _ hc

theorem editHoldsWhateverItSays : EditHoldsWhateverItSays := by
  intro x cs pushes b c hc ho hu
  have hr := read_edited (pushes := pushes) ho hu
  refine ⟨hr, arrange_hold (mem_said.2 (.inr ⟨c, hc, ?_⟩))⟩
  rw [hr]
  rfl

theorem newest_land_above {ws : List Word} {n : Nat} {m : Mark}
    (hn : (ws.map Word.said).Nodup) (hh : .ownerHold n ∈ ws)
    (hm : newestOwner ws = some (.ownerLand m)) : n < m.said := by
  obtain ⟨hmem, -, hmax⟩ := Land.newestOwner_max hm
  have hle : n ≤ m.said := hmax _ hh rfl
  rcases Nat.lt_or_eq_of_le hle with h | h
  · exact h
  · have := Land.eq_of_said_eq hn hh hmem h
    cases this

theorem editHoldBeatsEarlierComments : EditHoldBeatsEarlierComments := by
  intro x cs pushes b c d hc ho hu hd hdc
  refine ⟨?_, fun m hm => ?_⟩
  · have := (lastBy_ge cs c).2 d hd hdc
    simp only [editPos]
    omega
  · exact newest_land_above (arrange_nodup _) (editHoldsWhateverItSays x cs pushes b c hc ho hu).2 hm

theorem secondEditOnlyMovesLater : SecondEditOnlyMovesLater := by
  intro x pushes cs c t ho hcu ht
  refine ⟨read_edited ho (fun h => absurd (h ▸ ht) (Nat.not_le.2 hcu)), ?_⟩
  have := lastBy_mono cs c ht
  simp only [editPos]
  omega

theorem incompleteReadHolds : IncompleteReadHolds := by
  intro x cs pushes
  refine ⟨2 * top x cs + 1, ?_⟩
  show newestOwner (arrange (said x cs pushes false)) = _
  rw [Land.newestOwner_eq_some (arrange_nodup _)]
  refine ⟨arrange_hold (mem_said.2 (.inl ⟨rfl, rfl⟩)), rfl, fun u hu _ => ?_⟩
  rcases arrange_mem hu with h | ⟨w, hw, rfl⟩
  · exact said_le_top h
  · exact said_le_top (w := w) hw

theorem wordTraces : WordTraces := by
  intro x cs pushes b u hu
  have hpos : ∀ w ∈ said x cs pushes b, (∃ d ∈ cs, w.said = 2 * d.id ∨ w.said = 2 * d.id + 1) ∨
      (b = false ∧ w.said = 2 * top x cs + 1) := by
    intro w hw
    rcases mem_said.1 hw with ⟨hb, rfl⟩ | ⟨c, hc, hw⟩
    · exact .inr ⟨hb, rfl⟩
    · rw [word_said hw]; exact .inl (pos_traces _ cs c hc)
  rcases arrange_mem hu with h | ⟨w, hw, rfl⟩
  · refine ⟨?_, hpos u h⟩
    rcases mem_said.1 h with ⟨-, rfl⟩ | h
    · exact .inr rfl
    · exact .inl h
  · exact ⟨.inr rfl, hpos w hw⟩

/-! ### One comment -/

theorem agentRead_agent {x : Ctx} {p : String} {b : List Char} {who : Teammate} {about : Sha}
    (h : agentRead x p b = .agent who about) :
    ∃ body r, (scan b).protocol = [(true, body)] ∧ record? (joinLines body) = .ok r ∧
      r.task = x.pr ∧ r.provider = p ∧ who = ⟨p, r.teammate⟩ ∧ r.head = about := by
  unfold agentRead at h
  split at h
  · next body hs =>
    split at h
    · cases h
    · next r hr =>
      split at h
      · cases h
      · split at h
        · cases h
        · next h1 h2 =>
          cases h
          exact ⟨body, r, hs, hr, by simpa using h1, by simpa using h2, rfl, rfl⟩
  · cases h
  · cases h

theorem record_ok {cs : List Char} {r : Record} (h : record? cs = .ok r) :
    ∃ kvs, fields? cs = some kvs ∧ teammate? (get kvs "as") = some (r.provider, r.teammate) ∧
      sha? (get kvs "head") = some r.head := by
  unfold record? at h
  repeat' split at h
  all_goals cases h
  exact ⟨_, ‹_›, ‹_›, ‹_›⟩

theorem sha?_isSha {v : Option Val} {s : Sha} (h : sha? v = some s) : isSha s.toList = true := by
  unfold sha? at h
  split at h
  · split at h
    · cases h; simpa [String.toList_ofList]
    · cases h
  · cases h

theorem agentNeedsSlugProviderTaskHead : AgentNeedsSlugProviderTaskHead := by
  intro x pushes c who about h
  unfold read at h
  by_cases ho : c.login = x.owner
  · by_cases hu : c.updated = c.created
    · simp only [ho, hu, ne_eq, not_true_eq_false, ite_false] at h
      refine ⟨ho, hu, ?_⟩
      cases hs : c.slug with
      | none =>
        rw [hs] at h
        simp only [ownerRead] at h
        repeat' split at h
        all_goals cases h
      | some s =>
        rw [hs] at h
        simp only at h
        split at h
        · next p hp =>
          obtain ⟨body, r, h1, h2, h3, h4, rfl, h6⟩ := agentRead_agent h
          refine ⟨s, rfl, hp, body, r, h1, h2, h3, h4, rfl, h6, ?_⟩
          obtain ⟨_, -, -, hh⟩ := record_ok h2
          rw [← h6]
          exact sha?_isSha hh
        · cases h
    · simp [ho, hu] at h
  · simp [ho] at h

theorem fenceDuplicateKeyMalformed : FenceDuplicateKeyMalformed := by
  intro cs kvs rest ho hd r hr
  obtain ⟨kvs', hf, ht, -⟩ := record_ok hr
  unfold fields? at hf
  rw [ho] at hf
  simp only at hf
  split at hf
  · next hok =>
    cases hf
    simp only [Bool.and_eq_true] at hok
    rcases hd with hd | ⟨as, ha, hd⟩
    · rw [hok.2] at hd; cases hd
    · rw [ha] at ht
      simp [teammate?, hd] at ht
  · cases hf

theorem read_typed {x : Ctx} {pushes : List Carry.Push} {c : Comment} (ho : c.login = x.owner)
    (hu : c.updated = c.created) (hs : c.slug = none) :
    read x pushes c = ownerRead x pushes c.created c.body.toList := by
  simp [read, ho, hu, hs]

theorem severalWordLinesHold : SeveralWordLinesHold := by
  intro x pushes c ls ho hu hs hl h2
  rw [read_typed ho hu hs, ownerRead, hl]
  match ls, h2 with
  | .hold :: _ :: _, _ => rfl
  | .land _ :: _ :: _, _ => rfl

theorem unresolvedLandHolds : UnresolvedLandHolds := by
  intro x pushes c arg ho hu hs hl ht
  rw [read_typed ho hu hs, ownerRead, hl]
  simp only [ht]
  exact ⟨_, rfl⟩

theorem ownerRead_land {x : Ctx} {pushes : List Carry.Push} {t : Stamp} {b : List Char}
    {s : Sha} (h : ownerRead x pushes t b = .land s) :
    ∃ arg, ownerLines b = .ok [.land arg] ∧ target x pushes t arg = some s := by
  unfold ownerRead at h
  split at h
  · cases h
  · cases h
  · cases h
  · next arg hl =>
    split at h
    · next ht => cases h; exact ⟨arg, hl, ht⟩
    · cases h
  · cases h

theorem ownerLines_footer {b : List Char} {ls : List Line} (h : ownerLines b = .ok ls) :
    footer b = false := by
  unfold ownerLines at h
  split at h
  · cases h
  · next hf => simpa using hf

theorem ownerLandIsTyped : OwnerLandIsTyped := by
  intro x cs pushes b m hm
  obtain ⟨⟨c, hc, hw⟩ | hh, -⟩ := wordTraces x cs pushes b _ hm
  · refine ⟨c, hc, ?_⟩
    have hb := word_byOwner hw
    by_cases ho : c.login = x.owner
    · by_cases hu : c.updated = c.created
      · cases hs : c.slug with
        | some s => rw [read_slug hs hu] at hb; simp [Land.Word.byOwner] at hb
        | none =>
          rw [read_typed ho hu hs] at hw
          refine ⟨ho, rfl, hu, ?_⟩
          cases hr : ownerRead x pushes c.created c.body.toList with
          | land s =>
            rw [hr] at hw
            simp only [Read.word, Read.pos, Option.some.injEq, Land.Word.ownerLand.injEq] at hw
            subst hw
            obtain ⟨arg, hl, ht⟩ := ownerRead_land hr
            exact ⟨ownerLines_footer hl, rfl, arg, hl, ht⟩
          | _ => rw [hr] at hw; simp [Read.word] at hw
      · rw [read_edited ho hu] at hw; simp [Read.word] at hw
    · simp [read, ho, Read.word] at hw
  · cases hh

/-! ### Commits -/

theorem resolveFullSelf : ResolveFullSelf := by
  intro known p hp
  simp [resolve, hp]

theorem resolveUnique : ResolveUnique := by
  intro known p s hp h
  simp only [resolve, Nat.ne_of_lt hp, ite_false] at h
  split at h
  · cases h
  · next s' rest hm =>
    split at h
    · next ha =>
      cases h
      have hmem : s ∈ matching known p := by rw [hm]; exact List.mem_cons_self
      simp only [matching, List.mem_filter] at hmem
      refine ⟨hmem.1, hmem.2, fun t ht htp => ?_⟩
      have : t ∈ matching known p := List.mem_filter.2 ⟨ht, htp⟩
      rw [hm] at this
      rcases List.mem_cons.1 this with rfl | this
      · rfl
      · simpa using List.all_eq_true.1 ha t this
    · cases h

theorem stamps_mem {pushes : List Carry.Push} {ts : List (Stamp × Carry.Push)}
    (h : stamps pushes = some ts) :
    (∀ q ∈ pushes, ∃ tq, stamp? q.time.toList = some tq ∧ (tq, q) ∈ ts) ∧
      ∀ e ∈ ts, e.2 ∈ pushes ∧ stamp? e.2.time.toList = some e.1 := by
  induction pushes generalizing ts with
  | nil => simp [stamps] at h; subst h; simp
  | cons p ps ih =>
    simp only [stamps] at h
    split at h
    · next t r ht hr =>
      cases h
      obtain ⟨h1, h2⟩ := ih hr
      refine ⟨fun q hq => ?_, fun e he => ?_⟩
      · rcases List.mem_cons.1 hq with rfl | hq
        · exact ⟨t, ht, List.mem_cons_self⟩
        · obtain ⟨tq, h, hm⟩ := h1 q hq
          exact ⟨tq, h, List.mem_cons_of_mem _ hm⟩
      · rcases List.mem_cons.1 he with rfl | he
        · exact ⟨List.mem_cons_self, ht⟩
        · obtain ⟨hm, h⟩ := h2 e he
          exact ⟨List.mem_cons_of_mem _ hm, h⟩
    · cases h

theorem latest_ge {l : List (Stamp × Carry.Push)} {e : Stamp × Carry.Push} (h : e ∈ l) :
    e.1 ≤ latest l := by
  induction l with
  | nil => cases h
  | cons f l ih =>
    simp only [latest, List.foldr_cons] at ih ⊢
    rcases List.mem_cons.1 h with rfl | h
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih h) (Nat.le_max_right _ _)

theorem sameSecondUnknown : SameSecondUnknown := by
  intro pushes t p hp ht
  unfold headAt
  split
  · rfl
  · next ts hts =>
    obtain ⟨tq, htq, hm⟩ := (stamps_mem hts).1 p hp
    rw [ht] at htq
    cases htq
    have : ts.any (·.1 == t) = true := List.any_eq_true.2 ⟨_, hm, by simp⟩
    simp [this]

theorem headAtSound : HeadAtSound := by
  intro pushes t s h
  unfold headAt at h
  split at h
  · cases h
  · next ts hts =>
    obtain ⟨hall, hback⟩ := stamps_mem hts
    split at h
    · cases h
    · next hany =>
      split at h
      · cases h
      · next tp p rest hl =>
        split at h
        · next hk =>
          cases h
          simp only [Bool.and_eq_true, List.all_eq_true] at hk
          have hpm : (tp, p) ∈ (ts.filter (·.1 < t)).filter
              (·.1 == latest (ts.filter (·.1 < t))) := by rw [hl]; exact List.mem_cons_self
          simp only [List.mem_filter, decide_eq_true_eq, beq_iff_eq] at hpm
          obtain ⟨⟨hpts, hpt⟩, hplat⟩ := hpm
          obtain ⟨hpin, hpst⟩ := hback _ hpts
          refine ⟨p, hpin, rfl, hk.1, tp, hpst, hpt, fun q hq => ?_⟩
          obtain ⟨tq, hqs, hqm⟩ := hall q hq
          have hne : tq ≠ t := by
            intro he
            subst he
            exact hany (List.any_eq_true.2 ⟨_, hqm, by simp⟩)
          refine ⟨tq, hqs, hne, fun hlt => ?_, fun heq => ?_⟩
          · rw [hplat]
            exact latest_ge (List.mem_filter.2 ⟨hqm, by simpa using hlt⟩)
          · subst heq
            have hqf : (tq, q) ∈ (ts.filter (·.1 < t)).filter
                (·.1 == latest (ts.filter (·.1 < t))) := by
              simp only [List.mem_filter, decide_eq_true_eq, beq_iff_eq]
              exact ⟨⟨hqm, hpt⟩, hplat⟩
            rw [hl] at hqf
            rcases List.mem_cons.1 hqf with he | he
            · cases he; exact ⟨hk.1, rfl⟩
            · have := hk.2 _ he
              simpa using this
        · cases h

namespace Fixture

open Land (Obs Step Stop queueOf step)

def h0 : Sha := "0000000000000000000000000000000000000000"
def hA : Sha := "a1b2c3d0aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
def hB : Sha := "a1b2c3d1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
def hC : Sha := "c0ffee00cccccccccccccccccccccccccccccccc"

def pushes : List Carry.Push :=
  [⟨"2026-11-13T12:00:06Z", "force_push", "owner", hB, hC⟩,
   ⟨"2026-11-13T12:00:04Z", "push", "owner", hA, hB⟩,
   ⟨"2026-11-13T12:00:02Z", "branch_creation", "owner", h0, hA⟩]

def ctx : Ctx := { owner := "owner", pr := 7, known := [hC, hB, h0, hA, hB, hA, hC] }

def at' (s : Nat) : Stamp := 20261113120000 + s

def typed (id s : Nat) (body : String) : Comment := ⟨id, "owner", none, at' s, at' s, body⟩
def app (slug : String) (id s : Nat) (body : String) : Comment :=
  ⟨id, "owner", some slug, at' s, at' s, body⟩
def edited (c : Comment) (s : Nat) : Comment := { c with updated := at' s }

def claudeFooter : String := "\n---\n_Generated by [Claude Code](https://claude.ai/code)_"
def fence (json : String) : String := "```mitos-protocol\n" ++ json ++ "\n```" ++ claudeFooter
def landBy (provider teammate : String) (task : Nat) (head : Sha) : String :=
  "{\"v\":1,\"kind\":\"land\",\"task\":" ++ toString task ++ ",\"as\":{\"provider\":\"" ++
    provider ++ "\",\"teammate\":\"" ++ teammate ++ "\"},\"head\":\"" ++ head ++ "\"}"

def worker : Teammate := ⟨"claude", "worker"⟩

def obs (ws : List Word) (ds : List Teammate := delegates) : Obs :=
  { pr := 7, updatable := true, enforced := true, head := hC, pushes := [⟨false, hB, hC⟩],
    ids := [(hC, "id-c")], paths := some ["README.md"], base := .current, gate := .success,
    author := some ⟨⟨"grok", "builder"⟩, "grok"⟩,
    verdicts := [⟨1, hC, ⟨"claude", "verifier"⟩, "sonnet", .pass⟩], botAt := some hC,
    delegates := ds, words := ws, rest := true }

def stepOf (cs : List Comment) (ds : List Teammate := delegates) (complete := true) : Step :=
  let o := obs (words ctx cs pushes complete).1 ds
  step worker (queueOf [o]) o

def readOf (c : Comment) : Read := read ctx pushes c

theorem typedLandIsPresented : stepOf [typed 112 12 "/land"] = .present hC := by decide +kernel
theorem claudeAppLandIsNoEntry : stepOf [app "claude" 112 12 "/land"] = .stop .noEntry := by
  decide +kernel
theorem cursorAppLandIsNoEntry : stepOf [app "cursor" 112 12 "/land"] = .stop .noEntry := by
  decide +kernel
theorem appLandWithFooterIsNoEntry :
    stepOf [app "claude" 112 12 ("/land" ++ claudeFooter)] = .stop .noEntry := by decide +kernel
theorem otherLoginLandIsNoEntry :
    stepOf [{ typed 112 12 "/land" with login := "someone" }] = .stop .noEntry := by decide +kernel
theorem unknownAppIsIgnored :
    readOf (app "coderabbitai" 112 12 "/land") = .ignored .unknownApp := by decide +kernel

theorem editedLandHolds : stepOf [edited (typed 112 12 "/land") 13] = .stop .held := by
  decide +kernel
theorem editedAppPostHolds : stepOf [edited (app "claude" 112 12 "notes") 13] = .stop .held := by
  decide +kernel
theorem agentLandMergesWhenDelegated :
    stepOf [app "claude" 105 5 "notes",
      app "claude" 111 11 (fence (landBy "claude" "worker" 7 hC))] [worker] = .merge hC := by
  decide +kernel
theorem agentLandAfterAnEditHolds :
    stepOf [edited (app "claude" 105 5 "notes") 10,
      app "claude" 111 11 (fence (landBy "claude" "worker" 7 hC))] [worker] = .stop .held := by
  decide +kernel
theorem secondEditStillHolds :
    stepOf [edited (app "claude" 105 5 "notes") 50,
      app "claude" 111 11 (fence (landBy "claude" "worker" 7 hC))] [worker] = .stop .held := by
  decide +kernel
theorem landBeforeTheEditDoesNotClearIt :
    stepOf [edited (typed 101 1 "hello") 10, typed 105 5 "/land"] = .stop .held := by
  decide +kernel
theorem landAfterTheEditClearsIt :
    stepOf [edited (typed 101 1 "hello") 10, typed 112 12 "/land"] = .present hC := by
  decide +kernel
theorem landInTheEditsSecondHolds :
    stepOf [edited (typed 101 1 "hello") 10, typed 110 10 "/land"] = .stop .held := by
  decide +kernel
theorem secondEditAfterALandHoldsAgain :
    stepOf [edited (typed 101 1 "hello") 50, typed 112 12 "/land"] = .stop .held := by
  decide +kernel
theorem editOfAnOlderCommentHoldsANewerLand :
    stepOf [edited (typed 101 1 "hello") 9, typed 108 8 "/land"] = .stop .held := by
  decide +kernel
theorem holdThenLand : stepOf [typed 108 8 "/hold", typed 112 12 "/land"] = .present hC := by
  decide +kernel
theorem landThenHold :
    stepOf [typed 108 8 "/land", typed 112 12 "/hold because"] = .stop .held := by decide +kernel
theorem incompleteReadHoldsTheLand :
    stepOf [typed 112 12 "/land"] delegates false = .stop .held := by decide +kernel
theorem incompleteEmptyReadHolds : stepOf [] delegates false = .stop .held := by decide +kernel

theorem footerPostIsIgnored :
    readOf (typed 112 12 ("/land" ++ claudeFooter)) = .ignored .footer := by decide +kernel
theorem grokFooterPostIsIgnored :
    readOf (typed 112 12 "/land\n\n---\n_Generated by Grok Bot (builder)_\n") =
      .ignored .footer := by decide +kernel
theorem quotedFooterIsOwnerSpeech :
    readOf (typed 112 12 ("> done\n>\n> ---\n> _Generated by [Claude Code](https://claude.ai/code)_" ++
      "\n\n@claude yes")) = .ignored .noWord := by decide +kernel
theorem quotedFooterThenLand :
    readOf (typed 112 12 ("> ---\n> _Generated by [Claude Code](https://claude.ai/code)_" ++
      "\n\n/land")) = .land hC := by decide +kernel
theorem crlfLand : readOf (typed 112 12 "please land it\r\n/land\r\n") = .land hC := by
  decide +kernel
theorem indentedUpToThreeSpaces : readOf (typed 112 12 "   /land") = .land hC := by
  decide +kernel
theorem quotedLandIsNoWord : readOf (typed 112 12 "> /land") = .ignored .noWord := by
  decide +kernel
theorem fencedLandIsNoWord : readOf (typed 112 12 "```\n/land\n```") = .ignored .noWord := by
  decide +kernel
theorem tildeFencedLandIsNoWord :
    readOf (typed 112 12 "~~~sh\n/land\n~~~~") = .ignored .noWord := by decide +kernel
theorem unclosedFenceRunsToTheEnd :
    readOf (typed 112 12 "````\n```\n/land") = .ignored .noWord := by decide +kernel
theorem indentedLandIsNoWord : readOf (typed 112 12 "    /land") = .ignored .noWord := by
  decide +kernel
theorem tabIndentedLandIsNoWord : readOf (typed 112 12 "\t/land") = .ignored .noWord := by
  decide +kernel
theorem landRunOnIsNoWord : readOf (typed 112 12 "/landing") = .ignored .noWord := by
  decide +kernel
theorem holdRunOnHolds : readOf (typed 112 12 "/holding") = .hold .hold := by decide +kernel
theorem unknownSlashWordIsIgnored : readOf (typed 112 12 "/release\n/land") = .land hC := by
  decide +kernel
theorem landAndHoldHold : readOf (typed 112 12 "/land\n/hold") = .hold .severalWords := by
  decide +kernel
theorem twoLandsHold : readOf (typed 112 12 "/land\n/land") = .hold .severalWords := by
  decide +kernel
theorem landWithBadArgumentHolds :
    readOf (typed 112 12 "/land zzzz") = .hold .badArgument := by decide +kernel
theorem landWithShortPrefixHolds :
    readOf (typed 112 12 "/land a1b2c3") = .hold .badArgument := by decide +kernel
theorem landWithTwoArgumentsHolds :
    readOf (typed 112 12 "/land c0ffee0 now") = .hold .badArgument := by decide +kernel
theorem landBeforeAnyPushHolds : readOf (typed 101 1 "/land") = .hold .noHead := by
  decide +kernel
theorem landInAPushSecondHolds : readOf (typed 104 4 "/land") = .hold .noHead := by
  decide +kernel
theorem landNamesTheHeadOfItsTime : readOf (typed 105 5 "/land") = .land hB := by
  decide +kernel
theorem landOfAnOlderHeadIsNoEntry : stepOf [typed 105 5 "/land"] = .stop .noEntry := by
  decide +kernel
theorem ambiguousPrefixHolds :
    readOf (typed 112 12 "/land a1b2c3d") = .hold .ambiguousCommit := by decide +kernel
theorem uniquePrefixResolves : readOf (typed 112 12 "/land a1b2c3d1") = .land hB := by
  decide +kernel
theorem shortShaOfTheHeadIsPresented :
    stepOf [typed 112 12 "/land c0ffee0"] = .present hC := by decide +kernel
theorem unknownPrefixHolds :
    readOf (typed 112 12 "/land deadbee") = .hold .unknownCommit := by decide +kernel
theorem unseenFullShaIsNoEntry :
    stepOf [typed 112 12 "/land dddddddddddddddddddddddddddddddddddddddd"] = .stop .noEntry := by
  decide +kernel
theorem typedRecordWithFooterIsIgnored :
    readOf (typed 112 12 (fence (landBy "claude" "worker" 7 hC))) = .ignored .footer := by
  decide +kernel
theorem typedRecordIsIgnored :
    readOf (typed 112 12 ("```mitos-protocol\n" ++ landBy "claude" "worker" 7 hC ++ "\n```")) =
      .ignored .protocolFence := by decide +kernel

theorem agentRecordReads :
    readOf (app "claude" 112 12 (fence (landBy "claude" "worker" 7 hC))) = .agent worker hC := by
  decide +kernel
theorem grokRecordReads :
    readOf (app "cursor" 112 12 ("```mitos-protocol\n" ++ landBy "grok" "builder" 7 hC ++
      "\n```\n---\n_Generated by Grok Bot (builder)_")) = .agent ⟨"grok", "builder"⟩ hC := by
  decide +kernel
theorem recordWithCauseReads :
    readOf (app "claude" 112 12 (fence ("{\"v\":1,\"kind\":\"land\",\"task\":7,\"as\":" ++
      "{\"provider\":\"claude\",\"teammate\":\"worker\"},\"head\":\"" ++ hC ++
      "\",\"cause\":{\"kind\":\"comment\",\"url\":\"https://github.com/o/r/pull/7#issuecomment-1\"}}"))) =
      .agent worker hC := by decide +kernel
theorem wrongProviderIsIgnored :
    readOf (app "claude" 112 12 (fence (landBy "grok" "worker" 7 hC))) =
      .ignored .wrongProvider := by decide +kernel
theorem wrongTaskIsIgnored :
    readOf (app "claude" 112 12 (fence (landBy "claude" "worker" 8 hC))) =
      .ignored .wrongTask := by decide +kernel
theorem duplicateKeyIsMalformed :
    readOf (app "claude" 112 12 (fence ("{\"v\":1,\"kind\":\"land\",\"task\":8,\"task\":7,\"as\":" ++
      "{\"provider\":\"claude\",\"teammate\":\"worker\"},\"head\":\"" ++ hC ++ "\"}"))) =
      .ignored .malformed := by decide +kernel
theorem duplicateTeammateKeyIsMalformed :
    readOf (app "claude" 112 12 (fence ("{\"v\":1,\"kind\":\"land\",\"task\":7,\"as\":" ++
      "{\"provider\":\"claude\",\"provider\":\"claude\"},\"head\":\"" ++ hC ++ "\"}"))) =
      .ignored .malformed := by decide +kernel
theorem unknownKeyIsMalformed :
    readOf (app "claude" 112 12 (fence ("{\"v\":1,\"kind\":\"land\",\"task\":7,\"id\":1,\"as\":" ++
      "{\"provider\":\"claude\",\"teammate\":\"worker\"},\"head\":\"" ++ hC ++ "\"}"))) =
      .ignored .malformed := by decide +kernel
theorem shortHeadIsMalformed :
    readOf (app "claude" 112 12 (fence (landBy "claude" "worker" 7 "c0ffee0"))) =
      .ignored .malformed := by decide +kernel
theorem otherKindIsNotLand :
    readOf (app "claude" 112 12 (fence "{\"v\":1,\"kind\":\"claim\",\"task\":7}")) =
      .ignored .notLand := by decide +kernel
theorem twoFencesAreMalformed :
    readOf (app "claude" 112 12 ("```mitos-protocol\n" ++ landBy "claude" "worker" 7 hC ++
      "\n```\n" ++ fence (landBy "claude" "worker" 7 hC))) = .ignored .malformed := by
  decide +kernel
theorem unclosedRecordIsMalformed :
    readOf (app "claude" 112 12 ("```mitos-protocol\n" ++ landBy "claude" "worker" 7 hC ++
      claudeFooter)) = .ignored .malformed := by decide +kernel
theorem quotedRecordIsNoRecord :
    readOf (app "claude" 112 12 ("> ```mitos-protocol\n> " ++ landBy "claude" "worker" 7 hC ++
      "\n> ```" ++ claudeFooter)) = .ignored .noRecord := by decide +kernel
theorem editedRecordHolds :
    readOf (edited (app "claude" 112 12 (fence (landBy "claude" "worker" 7 hC))) 13) =
      .editHold := by decide +kernel

end Fixture

/-! ## No `sorry`, standard axioms only -/

open Lean in
#eval show CoreM Unit from do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  let fixtures := (← getEnv).constants.map₂.foldl (fun acc n c =>
    if (`MitosGate.Speech.Fixture).isPrefixOf n && c.isTheorem then acc.push n else acc) #[]
  if fixtures.isEmpty then throwError "no fixture theorem found"
  for n in [``appNeverOwner, ``footerIsNeverOwner, ``editHoldsWhateverItSays,
      ``editHoldBeatsEarlierComments, ``secondEditOnlyMovesLater,
      ``agentNeedsSlugProviderTaskHead, ``fenceDuplicateKeyMalformed, ``severalWordLinesHold,
      ``unresolvedLandHolds, ``resolveUnique, ``resolveFullSelf, ``headAtSound,
      ``sameSecondUnknown, ``incompleteReadHolds, ``positionsAscendingDistinct, ``wordTraces,
      ``ownerLandIsTyped] ++ fixtures.toList do
    for a in ← collectAxioms n do
      unless standard.contains a do
        throwError "{n} depends on the axiom {a}"

end MitosGate.Speech
