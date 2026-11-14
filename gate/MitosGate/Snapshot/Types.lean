import MitosGate.Speech

namespace MitosGate.Snapshot

open Land (Sha Pr Teammate Obs Verdict Author Result Base Gate Word Mark Push Entry)
open Speech (Comment Stamp lines lead blank isSha hex digit)

structure Protection where
  admins : Bool
  strict : Bool
  checks : List String

structure Global where
  repo : String
  owner : String
  protection : Option Protection
  stacked : Option (List Nat)
  rows : Option (List (Nat × List Char))

structure Pull where
  number : Nat
  state : String
  draft : Bool
  head : Sha
  headRepo : Option String
  baseRef : String
  baseRepo : String
  labels : List String
  body : String

structure Check where
  id : Nat
  name : String
  app : String
  sha : Sha
  status : String
  conclusion : String

/-- The review routes have no app field. -/
structure Post where
  login : String
  slug : Option String
  created : Stamp
  updated : Stamp
  body : String

structure Review where
  id : Nat
  login : String
  state : String
  commit : String
  submitted : Stamp
  body : String

structure Reads where
  comments : Option (List Comment)
  reviewComments : Option (List Post)
  reviews : Option (List Review)
  activity : Option (List Carry.Push)
  files : Option (List String)
  checks : Option (List Check)

structure Git where
  ids : List (Sha × String)
  base : Base

end MitosGate.Snapshot
