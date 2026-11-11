export const title = "One task, two providers";

export const colors = {
  waiting: "tan",
  working: "blue",
  owner: "orange",
  finished: "teal",
  expired: "yellow",
};

export const state = (v) => {
  if (v.phase === "done") return "Done";
  if (v.phase === "merged") return "Merged";
  if (v.phase === "asked") return "Waiting on the owner";
  if (v.expired) return "Claim expired";
  if (v.phase === "idle") return "Idle";
  if (v.head === "none") return "Held, no head yet";
  if (v.pass && v.gate === "success") return "Held, green gate, pass covers the head";
  if (v.gate === "success") return "Held, green gate";
  if (v.gate === "skipped") return "Held, gate skipped";
  return "Held, waiting on gate";
};

export const group = (v) => {
  if (v.phase === "done" || v.phase === "merged") return "finished";
  if (v.phase === "asked") return "owner";
  if (v.expired) return "expired";
  if (v.phase === "idle") return "waiting";
  return "working";
};

const labels = {
  Claim: "a provider claims the task",
  Publish: "the holder publishes a head",
  SetGate: "the gate check is reported",
  Handoff: "the holder hands off and names the head",
  Pass: "the other provider records a pass",
  Updater: "the updater rebases and the pass still covers",
  Ask: "the orchestrator asks the owner",
  OwnerReply: "the owner replies",
  OwnerApprovesSpec: "the owner adds spec-approved",
  OwnerDelegates: "the owner delegates merge on this task",
  Expire: "the claim time limit passes",
  Merge: "a permitted actor rebase-merges",
  Close: "the issue closes on the pull request keyword",
};

export const step = (action) => (action === "Finished" ? null : (labels[action] ?? action));
