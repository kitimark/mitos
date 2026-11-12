export const title = "Two pull requests";

export const colors = {
  waiting: "tan",
  working: "blue",
  finished: "teal",
  stuck: "yellow",
};

function phaseOf(v, name) {
  const ph = v.phase;
  if (ph && typeof ph === "object") return ph[name];
  return undefined;
}

function rank(s) {
  if (s === "green") return 6;
  if (s === "gating") return 5;
  if (s === "behind") return 4;
  if (s === "opted") return 3;
  if (s === "held") return 2;
  if (s === "skipped") return 1;
  if (s === "merged") return 0;
  return 0;
}

function word(s) {
  if (s === "merged") return "Merged";
  if (s === "held") return "Held";
  if (s === "skipped") return "Gate skipped";
  if (s === "green") return "Green on main";
  if (s === "gating") return "Waiting on gate";
  if (s === "behind") return "Behind";
  if (s === "opted") return "Queued";
  return "Idle";
}

export const state = (v) => {
  const a = phaseOf(v, "P1");
  const b = phaseOf(v, "P2");
  const left = rank(a) >= rank(b) ? a : b;
  return word(left);
};

export const group = (v) => {
  const label = state(v);
  if (label === "Merged") return "finished";
  if (label === "Held" || label === "Gate skipped") return "stuck";
  if (label === "Idle" || label === "Queued") return "waiting";
  return "working";
};

const labels = {
  Queue: "someone opts in",
  Hold: "the owner types /hold",
  ReleaseHold: "the owner's next /land clears the hold",
  Update: "the updater replays the next pull request",
  GateGreen: "gate succeeds",
  GateSkip: "gate is skipped",
  AgentMerge: "an agent rebase-merges the next pull request",
  OwnerMerge: "the owner merges",
};

export const step = (action) => (action === "Finished" ? null : (labels[action] ?? action));
