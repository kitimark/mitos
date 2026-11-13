import MitosGate.Speech.Commit

/-!
# What one comment says

Every agent posts through the owner's account, so the login cannot tell the owner from an agent.
What can: an app post carries the app's slug (`performed_via_github_app`), and a post made through
the account's token without an app ends with the adapter footer. So only an unedited comment from
the owner's login, with no slug and no trailing footer, is the owner typing. A footer inside a
`>` quote is not trailing, and a `/land` inside a quote, a fence or an indented block is not a
word, while a `/hold` holds wherever it sits (`doubt`).

An app may speak only as an agent, through one top-level `mitos-protocol` fence holding a `land`
record for this pull request whose provider is the app's.
-/

namespace MitosGate.Speech

open Land (Sha Pr Teammate Word)

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
  | footer | protocolFence | noWord | markup | quoteContinuation
  | hold | severalWords | badArgument | unknownCommit | ambiguousCommit | noHead
  deriving DecidableEq

inductive Read
  | land (about : Sha)
  | hold (why : Why)
  | editHold
  | agent (who : Teammate) (about : Sha)
  | ignored (why : Why)
  deriving DecidableEq

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

def target (x : Ctx) (pushes : List Carry.Push) (t : Stamp) (arg : List Char) : Option Sha :=
  if arg = [] then headAt pushes t
  else if 7 ≤ arg.length ∧ arg.length ≤ 40 ∧ arg.all hex = true then resolve x.known arg
  else none

def unresolved (x : Ctx) (arg : List Char) : Why :=
  if arg = [] then .noHead
  else if 7 ≤ arg.length ∧ arg.length ≤ 40 ∧ arg.all hex = true then
    if matching x.known arg = [] then .unknownCommit else .ambiguousCommit
  else .badArgument

def holdLine (l : List Char) : Bool :=
  "/hold".toList.isPrefixOf (l.dropWhile (" \t>-*+.)0123456789".toList.contains ·))

def markup (l : List Char) : Bool := marker l || l.contains '`' || l.contains '<'

/-- GitHub's Markdown carries a quote on to the lines after it until a blank line. -/
def inQuote : Bool → List (List Char) → Bool
  | _, [] => false
  | q, l :: ls =>
    match lead l with
    | some ('>' :: _) => inQuote true ls
    | _ => if blank l then inQuote false ls else (q && (word? l).isSome) || inQuote q ls

/-- The scanner places fences, quotes and indents only as top-level Markdown has them, while GitHub
also draws them inside list items and HTML blocks, and runs a code span or an HTML comment across
lines. So a `/hold` at the start of any line, after spaces, quote marks or a list marker, holds
wherever it sits, and a lone `/land` holds in a comment with a backtick, a `<` or three tildes, or
inside a quote. A plain `/land` lifts such a hold. -/
def doubt (b : List Char) : Option Why :=
  if (lines b).any holdLine then some .hold
  else if (lines b).any markup then some .markup
  else if inQuote false (lines b) then some .quoteContinuation
  else none

def ownerRead (x : Ctx) (pushes : List Carry.Push) (t : Stamp) (b : List Char) : Read :=
  match ownerLines b with
  | .error why => .ignored why
  | .ok [] => if (lines b).any holdLine then .hold .hold else .ignored .noWord
  | .ok [.hold] => .hold .hold
  | .ok [.land arg] =>
    match doubt b with
    | some why => .hold why
    | none =>
      match target x pushes t arg with
      | some s => .land s
      | none => .hold (unresolved x arg)
  | .ok _ => .hold .severalWords

/-! ## An agent's record -/

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

/-! ## One comment -/

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

def Read.word : Read → Nat → Option Word
  | .land s, n => some (.ownerLand ⟨n, s⟩)
  | .hold _, n => some (.ownerHold n)
  | .editHold, n => some (.ownerHold n)
  | .agent t s, n => some (.agentLand t ⟨n, s⟩)
  | .ignored _, _ => none

def Read.byOwner : Read → Bool
  | .land _ | .hold _ | .editHold => true
  | .agent _ _ | .ignored _ => false

/-! ## Statements -/

def AppNeverOwner : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) n w, c.slug ≠ none → c.updated = c.created →
    (read x pushes c).word n = some w → w.byOwner = false

def FooterIsNeverOwner : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) n w, footer c.body.toList = true → c.updated = c.created →
    (read x pushes c).word n = some w → w.byOwner = false

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

def HoldLineHolds : Prop :=
  ∀ (x : Ctx) pushes (c : Comment) ls, c.login = x.owner → c.updated = c.created →
    c.slug = none → ownerLines c.body.toList = .ok ls →
    (lines c.body.toList).any holdLine = true → ∃ why, read x pushes c = .hold why

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
  split <;> exact ⟨_, rfl⟩

theorem holdLineHolds : HoldLineHolds := by
  intro x pushes c ls ho hu hs hl hh
  rw [read_typed ho hu hs, ownerRead, hl]
  match ls with
  | [] => simp only [hh, ite_true]; exact ⟨_, rfl⟩
  | [.hold] => exact ⟨_, rfl⟩
  | [.land _] => simp only [doubt, hh, ite_true]; exact ⟨_, rfl⟩
  | .hold :: _ :: _ => exact ⟨_, rfl⟩
  | .land _ :: _ :: _ => exact ⟨_, rfl⟩

theorem ownerRead_land {x : Ctx} {pushes : List Carry.Push} {t : Stamp} {b : List Char}
    {s : Sha} (h : ownerRead x pushes t b = .land s) :
    ∃ arg, ownerLines b = .ok [.land arg] ∧ target x pushes t arg = some s := by
  unfold ownerRead at h
  split at h
  · cases h
  · split at h <;> cases h
  · cases h
  · next arg hl =>
    split at h
    · cases h
    · split at h
      · next ht => cases h; exact ⟨arg, hl, ht⟩
      · cases h
  · cases h

theorem ownerLines_footer {b : List Char} {ls : List Line} (h : ownerLines b = .ok ls) :
    footer b = false := by
  unfold ownerLines at h
  split at h
  · cases h
  · next hf => simpa using hf

end MitosGate.Speech
