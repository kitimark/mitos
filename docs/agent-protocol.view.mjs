export const title = "Two pull requests, no background rebase";

export const colors = {
  waiting: "tan",
  working: "blue",
  owner: "orange",
  finished: "teal",
  stuck: "yellow",
};

function phaseOf(v, name) {
  const ph = v.phase;
  if (ph && typeof ph === "object") return ph[name];
  return undefined;
}

function bucket(s) {
  if (s === "merged") return "done";
  if (s === "held") return "held";
  if (s === "skipped") return "skip";
  if (s === "green") return "green";
  if (s === "gating") return "gating";
  if (s === "behind") return "behind";
  if (s === "opted") return "opted";
  return "idle";
}

export const state = (v) => {
  const a = bucket(phaseOf(v, "P1"));
  const b = bucket(phaseOf(v, "P2"));
  const both = [a, b];
  if (both.includes("green")) return "Green on main";
  if (both.includes("gating")) return "Waiting on gate";
  if (both.includes("behind")) return "Behind";
  if (both.includes("opted")) return "Queued";
  if (both.includes("held")) return "Held";
  if (both.includes("skip")) return "Gate skipped";
  if (both.includes("done")) return "Merged";
  return "Idle";
};

export const group = (v) => {
  const label = state(v);
  if (label === "Merged") return "finished";
  if (label === "Held" || label === "Gate skipped") return "stuck";
  if (label === "Idle" || label === "Queued") return "waiting";
  return "working";
};

const labels = {
  Queue: "the owner or an allowed teammate opts in",
  Hold: "the owner types /hold",
  MainMove: "main moves and no branch is rebased",
  Update: "the updater replays the next pull request and keeps the content id",
  GateGreen: "gate succeeds on that head",
  GateSkip: "gate is skipped",
  Merge: "a permitted actor rebase-merges the next pull request",
};

export const step = (action) => (action === "Finished" ? null : (labels[action] ?? action));
