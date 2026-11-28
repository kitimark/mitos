import MitosGate.Snapshot.Obs

/-!
# Why a pull request holds or is not admitted

An `Obs` says only that some read failed, as a hold above every owner word, or that `rest` is
false. The land report names which read and which part of `rest` (#509, #520), so the snapshot
carries a `Note` beside each `Obs`. A note decides nothing: `land` reads only the `Obs`.
-/

namespace MitosGate.Snapshot

open Land (Word newestOwner)

inductive Unread
  | protection | stacks | dashboard | comments | reviewComments | reviews | activity | files | checks
  deriving DecidableEq

def Unread.name : Unread → String
  | .protection => "protection" | .stacks => "stacks" | .dashboard => "dashboard"
  | .comments => "comments" | .reviewComments => "review-comments" | .reviews => "reviews"
  | .activity => "activity" | .files => "files" | .checks => "checks"

def Unread.all : List Unread :=
  [.protection, .stacks, .dashboard, .comments, .reviewComments, .reviews, .activity, .files, .checks]

inductive Unmet
  | footer | unanswered | label | provenance | entry | author | verdict
  deriving DecidableEq

def Unmet.name : Unmet → String
  | .footer => "footer" | .unanswered => "unanswered" | .label => "label"
  | .provenance => "provenance" | .entry => "entry" | .author => "author" | .verdict => "verdict"

def Unmet.all : List Unmet := [.footer, .unanswered, .label, .provenance, .entry, .author, .verdict]

structure Note where
  unread : List Unread
  unmet : List Unmet
  /-- The owner has a `/land` or a `/hold` on the pull request, or its comments were not read. -/
  owner : Bool
  deriving DecidableEq

def flagged (l : List (α × Bool)) : List α := l.filterMap fun (k, b) => if b then some k else none

def unreadOf (g : Global) (p : Pull) (r : Reads) : List Unread :=
  flagged [(.protection, g.protection.isNone), (.stacks, g.stacked.isNone),
    (.dashboard, g.verdictCells.isNone), (.comments, r.comments.isNone),
    (.reviewComments, r.reviewComments.isNone), (.reviews, r.reviews.isNone),
    (.activity, (activity p r).isNone), (.files, r.files.isNone), (.checks, r.checks.isNone)]

def unmetOf (g : Global) (p : Pull) (r : Reads) (x : Git) : List Unmet :=
  let fact := provenanceFact g p.number
  let author := fun f => Provenance.authorOf (sourceObs g p r x) f
  flagged [(.footer, !oneFooter p.body), (.unanswered, !(unanswered g (posts r)).isEmpty),
    (.label, (r.files.map (·.any specPath)).getD true && !p.labels.contains "spec-approved"),
    (.provenance, g.provenance.isNone), (.entry, g.provenance.isSome && fact.isNone),
    (.author, fact.any fun f => (author f).isNone),
    (.verdict, fact.any fun f =>
      (author f).isSome && !Provenance.sourceGuard (sourceObs g p r x) f p.labels)]

def ownerDecides (g : Global) (p : Pull) (r : Reads) : Bool :=
  r.comments.isNone ||
    (Speech.words (ctx g p r) (r.comments.getD []) ((activity p r).getD []) true).1.any (·.decides)

def note (g : Global) (p : Pull) (r : Reads) (x : Git) : Note :=
  ⟨unreadOf g p r, unmetOf g p r x, ownerDecides g p r⟩

def EveryFailedReadIsNamed : Prop :=
  ∀ g p r x, complete g p r = false ↔ (note g p r x).unread ≠ []

def UnmetRestIsNamed : Prop :=
  ∀ g p r x, (obs g p r x).rest = false ↔ (note g p r x).unmet ≠ []

/-- Where the note says the owner decided nothing, the comments were read, and read with nothing
missing they hold no `/land` and no `/hold` of the owner's. -/
def NoOwnerWordWhereTheOwnerDecidedNothing : Prop :=
  ∀ g p r x, (note g p r x).owner = false →
    r.comments.isSome = true ∧
      newestOwner (withReviewSpeech g p r (Speech.words (ctx g p r) (r.comments.getD [])
        ((activity p r).getD []) true).1) = none

theorem flagged_ne_nil (l : List (α × Bool)) : flagged l ≠ [] ↔ l.any (·.2) = true := by
  induction l with
  | nil => simp [flagged]
  | cons a l _ =>
    obtain ⟨k, b⟩ := a
    cases b <;> simp [flagged]

theorem everyFailedReadIsNamed : EveryFailedReadIsNamed := by
  intro g p r x
  have bools : ∀ a b c d e f h i j : Bool,
      (a && b && c && d && e && f && h && i && j) = false ↔
        (!a || (!b || (!c || (!d || (!e || (!f || (!h || (!i || (!j || false))))))))) = true := by
    decide
  simp only [note, unreadOf, flagged_ne_nil, List.any_cons, List.any_nil, complete,
    ← Option.not_isSome]
  exact bools ..

theorem unguardedWithoutAuthor {o : Land.Obs} {f : Provenance.PullFact} {labels : List String}
    (h : Provenance.authorOf o f = none) : Provenance.sourceGuard o f labels = false := by
  simp [Provenance.sourceGuard, Provenance.withFacts, h]

theorem unmetRestIsNamed : UnmetRestIsNamed := by
  intro g p r x
  have bools : ∀ a b c d s : Bool,
      (a && b && (!c || d) && s) = false ↔
        (!a || (!b || (c && !d || (false || (true && false || (false || (true && !s || false))))))) =
          true := by decide
  simp only [note, unmetOf, flagged_ne_nil, List.any_cons, List.any_nil, obs_projection]
  show (rest g p r && _) = false ↔ _
  cases hf : provenanceFact g p.number with
  | none => cases hp : g.provenance <;> simp
  | some f =>
    have hp : g.provenance.isSome = true := by
      cases hq : g.provenance with
      | none => simp [provenanceFact, hq] at hf
      | some _ => rfl
    have hn : g.provenance.isNone = false := by
      cases hq : g.provenance with
      | none => rw [hq] at hp; cases hp
      | some _ => rfl
    cases ha : Provenance.authorOf (sourceObs g p r x) f with
    | none => simp [hp, ha, unguardedWithoutAuthor ha]
    | some a =>
      simp only [Option.any_some, hp, hn, ha]
      exact bools ..

theorem noOwnerWordWhereTheOwnerDecidedNothing : NoOwnerWordWhereTheOwnerDecidedNothing := by
  intro g p r x h
  simp only [note, ownerDecides, Bool.or_eq_false_iff] at h
  refine ⟨by simpa using h.1, ?_⟩
  rw [newestOwner_withReviewSpeech, Land.onlyLandOrHoldChangesTheWord]
  have : (Speech.words (ctx g p r) (r.comments.getD []) ((activity p r).getD []) true).1.filter
      (·.decides) = [] := by
    simpa [List.filter_eq_nil_iff] using h.2
  rw [this]
  rfl

end MitosGate.Snapshot
