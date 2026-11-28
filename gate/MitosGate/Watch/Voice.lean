import MitosGate.Land
import MitosGate.Util
import MitosGate.Speech
import MitosGate.Snapshot.Fields
import MitosGate.Watch.Time

namespace MitosGate.Watch

open Land (Pr)

inductive Place
  | issueComment
  | reviewComment
  | review
  deriving DecidableEq, Repr

inductive Via
  | noKey
  | null
  | app (slug : String)
  deriving DecidableEq, Repr

inductive Speaker
  | typed
  | app (slug : String)
  | untold
  deriving DecidableEq, Repr

structure Said where
  place : Place
  id : Nat
  thread : Pr
  login : String
  via : Via
  created : Epoch
  updated : Epoch
  state : Option String
  body : String
  deriving Repr

def Said.speaker (p : Said) : Speaker :=
  match p.place, p.via with
  | .issueComment, .null => .typed
  | _, .app s => .app s
  | _, _ => .untold

def Said.slug (p : Said) : Option String :=
  match p.via with
  | .app s => some s
  | _ => none

structure Excerpt where
  text : String
  ok : ∀ c ∈ text.toList, printable c = true ∨ c = '\\'

instance : DecidableEq Excerpt := fun a b =>
  if h : a.text = b.text then isTrue (by cases a; cases b; simp_all) else isFalse (by
    intro e; cases e; exact h rfl)

def squeezeGo : List Char → Bool → List Char
  | [], _ => []
  | c :: cs, gap =>
    if c.isWhitespace then (if gap then squeezeGo cs true else ' ' :: squeezeGo cs true)
    else c :: squeezeGo cs false

def squeeze (n : Nat) (b : String) : String := String.ofList ((squeezeGo b.toList true).take n)

def Excerpt.of (b : String) : Excerpt := ⟨oneLine (squeeze 120 b), oneLine_printable _⟩

def Excerpt.ofStored? (s : String) : Option Excerpt :=
  if h : ∀ c ∈ s.toList, printable c = true ∨ c = '\\' then some ⟨s, h⟩ else none

structure Post where
  place : Place
  id : Nat
  thread : Pr
  speaker : Speaker
  created : Epoch
  updated : Epoch
  state : Option String
  excerpt : Excerpt
  deriving DecidableEq

def Post.of (p : Said) : Post :=
  ⟨p.place, p.id, p.thread, p.speaker, p.created, p.updated, p.state, Excerpt.of p.body⟩

def Post.edited (p : Post) : Bool := p.created != p.updated

def answerApps : List String := Speech.apps.map (·.1)

def footer (p : Said) : Bool := Speech.footer p.body.toList

def counts (p : Said) : Bool :=
  match p.place with
  | .review => p.state == some "APPROVED" || p.state == some "CHANGES_REQUESTED" || p.body != ""
  | _ => true

def words (p : Said) : Bool :=
  match p.speaker with
  | .typed => true
  | _ => p.slug.isNone && !footer p

def answer (apps : List String) (p : Said) : Bool :=
  match p.speaker with
  | .typed => false
  | _ => p.slug.any (apps.contains ·) || footer p

def unansweredIn (owner : String) (apps : List String) (posts : List Said) (thread : Pr) :
    List Nat :=
  let mine := posts.filter fun p => p.login == owner && p.thread == thread && counts p
  let answers := mine.filter (answer apps)
  let newer (p : Said) := answers.all fun q => q.created < p.created
  ((mine.filter fun p => words p && newer p).map (·.id)).eraseDups

def unanswered (owner : String) (apps : List String) (posts : List Said) : List (Pr × List Nat) :=
  let threads := (posts.map (·.thread)).eraseDups
  threads.filterMap fun t =>
    match unansweredIn owner apps posts t with
    | [] => none
    | ids => some (t, ids)

def TypedOnlyFromAnIssueCommentWithNoApp : Prop :=
  ∀ p : Said, p.speaker = .typed ↔ (p.place = .issueComment ∧ p.via = .null)

def ReviewRoutesAreNeverTyped : Prop :=
  ∀ p : Said, p.place ≠ .issueComment → p.speaker ≠ .typed

def TypedIsAlwaysWords : Prop :=
  ∀ (apps : List String) (p : Said), p.speaker = .typed → words p = true ∧ answer apps p = false

def AnAppPostIsNeverWords : Prop :=
  ∀ (apps : List String) (p : Said) s, p.speaker = .app s →
    words p = false ∧ (s ∉ apps → answer apps p = footer p)

def SpeaksAsLandUnlessTyped : Prop :=
  ∀ (g : Snapshot.Global) (p : Said) (l : Snapshot.Post), p.speaker ≠ .typed →
    l.login = g.owner → l.slug = p.slug → l.body = p.body → words p = Snapshot.speaks g l

def AnswersAsLandUnlessTyped : Prop :=
  ∀ (g : Snapshot.Global) (p : Said) (l : Snapshot.Post), p.speaker ≠ .typed →
    l.login = g.owner → l.slug = p.slug → l.body = p.body →
    answer answerApps p = Snapshot.answers g l

def TypedWordsAreListedUntilAnswered : Prop :=
  ∀ (owner : String) (apps : List String) (posts : List Said) (p : Said), p ∈ posts →
    p.login = owner → p.speaker = .typed →
    (∀ q ∈ posts, q.login = owner → q.thread = p.thread → counts q = true → answer apps q = true →
      q.created < p.created) →
    p.id ∈ unansweredIn owner apps posts p.thread

def ExcerptIsOneLine : Prop :=
  ∀ b : String, ∀ c ∈ (Excerpt.of b).text.toList, printable c = true ∨ c = '\\'

theorem typedOnlyFromAnIssueCommentWithNoApp : TypedOnlyFromAnIssueCommentWithNoApp := by
  intro p
  unfold Said.speaker
  cases p.place <;> cases p.via <;> simp

theorem reviewRoutesAreNeverTyped : ReviewRoutesAreNeverTyped :=
  fun p h t => h ((typedOnlyFromAnIssueCommentWithNoApp p).1 t).1

theorem typedIsAlwaysWords : TypedIsAlwaysWords := by
  intro apps p h
  simp [words, answer, h]

theorem slug_of_app {p : Said} {s : String} (h : p.speaker = .app s) : p.slug = some s := by
  unfold Said.speaker at h
  unfold Said.slug
  cases hp : p.place <;> cases hv : p.via <;> simp_all

theorem anAppPostIsNeverWords : AnAppPostIsNeverWords := by
  intro apps p s h
  have hs := slug_of_app h
  refine ⟨by simp [words, h, hs], fun hn => ?_⟩
  simp [answer, h, hs, hn]

theorem speaksAsLandUnlessTyped : SpeaksAsLandUnlessTyped := by
  intro g p l h hl hs hb
  unfold words Snapshot.speaks footer
  split
  · exact absurd ‹_› h
  · simp [hl, hs, hb]

theorem lookup_isSome_eq_contains (x : String) (l : List (String × String)) :
    (l.lookup x).isSome = (l.map (·.1)).contains x := by
  induction l with
  | nil => rfl
  | cons e es ih =>
    obtain ⟨k, v⟩ := e
    simp only [List.lookup, List.map_cons, List.contains_cons]
    cases hk : x == k <;> simp [ih]

theorem answersAsLandUnlessTyped : AnswersAsLandUnlessTyped := by
  intro g p l h hl hs hb
  unfold answer Snapshot.answers footer answerApps
  split
  · exact absurd ‹_› h
  · simp [hl, hs, hb, lookup_isSome_eq_contains]

theorem typedWordsAreListedUntilAnswered : TypedWordsAreListedUntilAnswered := by
  intro owner apps posts p hp ho ht hq
  have hplace := ((typedOnlyFromAnIssueCommentWithNoApp p).1 ht).1
  have hw := (typedIsAlwaysWords apps p ht).1
  unfold unansweredIn
  simp only [List.mem_eraseDups, List.mem_map, List.mem_filter]
  refine ⟨p, ⟨⟨hp, by simp [ho, counts, hplace]⟩, ?_⟩, rfl⟩
  simp only [hw, Bool.true_and, List.all_eq_true, List.mem_filter, decide_eq_true_eq]
  rintro q ⟨⟨hqm, hqo⟩, hqa⟩
  simp only [Bool.and_eq_true, beq_iff_eq] at hqo
  exact hq q hqm hqo.1.1 hqo.1.2 hqo.2 hqa

theorem excerptIsOneLine : ExcerptIsOneLine := fun b => (Excerpt.of b).ok

namespace Fixture

def footerText : String := "\n\n---\n_Generated by [Claude Code](https://claude.ai/code)_\n"

def ownerQuotesAFooter : Said :=
  { place := .issueComment, id := 11, thread := 501, login := "o", via := .null, created := ⟨10⟩,
    updated := ⟨10⟩, state := none, body := "> it is done" ++ footerText }

def codexCatchUp : Said :=
  { place := .issueComment, id := 12, thread := 336, login := "o",
    via := .app "chatgpt-codex-connector", created := ⟨20⟩, updated := ⟨20⟩, state := none,
    body := "## Catch-up: review the fix" ++ footerText }

def codexBare : Said := { codexCatchUp with id := 14, body := "## Catch-up: review the fix" }

def claudeBare : Said :=
  { codexCatchUp with id := 15, via := .app "claude", body := "Fixed in abc1234." }

def agentReviewReply : Said :=
  { place := .reviewComment, id := 13, thread := 512, login := "o", via := .noKey,
    created := ⟨30⟩, updated := ⟨30⟩, state := none, body := "Fixed in abc1234." ++ footerText }

def emptyReview : Said :=
  { place := .review, id := 16, thread := 512, login := "o", via := .noKey, created := ⟨31⟩,
    updated := ⟨31⟩, state := some "COMMENTED", body := "" }

def quotedFooterReply : Said :=
  { agentReviewReply with
    id := 17
    body := "> Fixed in abc1234.\n>\n> ---\n> _Generated by [Claude Code](https://claude.ai/code)_" }

def otherToolReply : Said :=
  { agentReviewReply with
    id := 18
    body := "Fixed in abc1234.\n\n---\n_Generated by Grok Bot (builder)_\n" }

theorem quotedFooterIsStillTyped : ownerQuotesAFooter.speaker = .typed := by decide +kernel

theorem quotedFooterIsWordsForPrState :
    words ownerQuotesAFooter = true ∧ answer answerApps ownerQuotesAFooter = false := by
  decide +kernel

theorem codexWithTheFooterAnswers :
    words codexCatchUp = false ∧ answer answerApps codexCatchUp = true := by decide +kernel

theorem codexWithoutTheFooterIsNeither :
    words codexBare = false ∧ answer answerApps codexBare = false := by decide +kernel

theorem claudeWithoutTheFooterAnswers : answer answerApps claudeBare = true := by decide +kernel

theorem reviewReplyIsUntold : agentReviewReply.speaker = .untold := by decide +kernel

theorem reviewReplyWithFooterAnswersForPrState : answer answerApps agentReviewReply = true := by
  decide +kernel

theorem aQuotedFooterLineIsNoFooter :
    words quotedFooterReply = true ∧ answer answerApps quotedFooterReply = false := by
  decide +kernel

theorem anotherToolsFooterAnswers :
    words otherToolReply = false ∧ answer answerApps otherToolReply = true := by decide +kernel

theorem anEmptyCommentedReviewDoesNotCount : counts emptyReview = false := by decide +kernel

theorem quotedWordsStayUnanswered :
    unansweredIn "o" answerApps
      [ownerQuotesAFooter, { codexBare with thread := 501, created := ⟨40⟩ }] 501 = [11] := by
  decide +kernel

theorem aLaterAnswerHidesWords :
    unansweredIn "o" answerApps
      [ownerQuotesAFooter, { claudeBare with thread := 501, created := ⟨40⟩ }] 501 = [] := by
  decide +kernel

theorem ownerReviewWordsAreListed :
    unansweredIn "o" answerApps
      [agentReviewReply, { quotedFooterReply with created := ⟨35⟩ }] 512 = [17] := by
  decide +kernel

theorem unansweredIsPerThread :
    unanswered "o" answerApps
      [ownerQuotesAFooter, agentReviewReply, { quotedFooterReply with created := ⟨35⟩ }] =
      [(501, [11]), (512, [17])] := by
  decide +kernel

end Fixture

end MitosGate.Watch
