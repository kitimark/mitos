#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
lake build mitos-gate >/dev/null
python3 -I - "$root" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
binary = root / ".lake/build/bin/mitos-gate"
source = json.loads((root / "gate/provenance-fixtures/488.json").read_text())
passed = 0


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], capture_output=True, timeout=60, **kwargs)


def check(name, condition):
    global passed
    assert condition, name
    passed += 1
    print("ok  ", name, flush=True)


with tempfile.TemporaryDirectory(prefix="mitos-provider-") as directory:
    work = Path(directory)

    def project(value):
        payload = work / "source.json"
        payload.write_text(json.dumps(value, sort_keys=True, separators=(",", ":")))
        rendered = run([binary, "provenance", "render", "kitimark/mitos", payload])
        if rendered.returncode:
            if rendered.returncode == 1 and not rendered.stdout and rendered.stderr == b"provenance: source payload refused\n":
                return None
            raise AssertionError("renderer failed unexpectedly: " + str(rendered.returncode) + " " +
                                 rendered.stderr.decode(errors="replace"))
        block = work / "source.block"
        block.write_bytes(rendered.stdout)
        result = run(["lake", "env", "lean", "--run", "gate/ProvenanceProviderTest.lean", block], cwd=root)
        assert result.returncode == 0, result.stdout.decode() + result.stderr.decode()
        return json.loads(result.stdout)

    result = project(source)
    fact = source["pulls"][0]
    raw = result["facts"]
    check("real #488 source keeps null model and exact provider/actor/head",
          raw["head"] == fact["author"]["head"] and raw["author"] == {
              "provider": "openai", "actor": "codex", "actualModel": None, "requestedModel": None})
    event = fact["verdicts"][0]
    check("real raw verifier identity/effort/order/evidence are unchanged", raw["verdicts"] == [{
        "head": event["head"], "identity": {k: event.get(k) for k in
        ["provider", "actor", "actualModel", "requestedModel"]}, "effort": "xhigh",
        "result": "pass", "order": event["order"], "evidence": event["evidence"]}])
    observation = result["snapshot"]["prs"][0]
    check("real source admits through Snapshot with explicit absent knowledge", result["admitted"] and
          observation["rest"] and observation["author"] == {
              "who": {"provider": "openai", "name": "codex"}, "model": None})
    expected_events = [{"said": event["order"], "head": event["head"],
                        "judge": {"provider": event["provider"], "name": event["actor"]},
                        "model": event["actualModel"], "result": event["result"]}]
    check("Snapshot retains the exact complete five-field Land event array", observation["verdicts"] == expected_events)
    decoded = run([binary, "land"], input=json.dumps(result["snapshot"]).encode())
    check("new nested null author is accepted by native Land", decoded.returncode == 0)
    template = json.loads((root / "gate/shadow-fixtures/record-idle.json").read_text())
    template.update(read="2026-11-18T08:00:00Z", main="e12ce99f1af3e3339b57b05241f81d681923ebcb")
    template["mainAfter"] = template["main"]
    template["outcome"].update(snapshot=result["snapshot"], decision=json.loads(decoded.stdout), trees=[], notes=[])
    window = work / "window"
    (window / "records").mkdir(parents=True)
    (window / "records/490-1.json").write_text(json.dumps(template))
    (window / "merges.json").write_text(json.dumps([{"pr": 488, "time": "2026-11-18T08:00:05Z",
                                                   "before": template["main"], "head": event["head"], "tree": ""}]))
    for name in ["runs", "baseline"]:
        (window / (name + ".json")).write_text("[]")
    replayed = run([binary, "shadow", window])
    check("record v1 with nested null replays with no stored-decision drift", replayed.returncode == 0 and
          b"1 records, 0 refused, 0 skipped, 0 drifted, 0 unreadable" in replayed.stdout)
    alias = copy.deepcopy(source)
    alias["pulls"][0]["author"]["requestedModel"] = "opus"
    check("requested alias leaves valid null admission and projection unchanged", project(alias)["snapshot"] == result["snapshot"])
    adverse = copy.deepcopy(source)
    adverse_event = dict(event, actor="adverse", actualModel=None, effort=None, result="fail", order=2,
                         evidence=event["evidence"] + "-adverse", requestedModel="opus")
    adverse["pulls"][0]["verdicts"].append(adverse_event)
    projected = project(adverse)
    check("raw adverse null/effort/requested/evidence survive before projection", projected["facts"]["verdicts"][1] == {
        "head": event["head"], "identity": {"provider": "claude", "actor": "adverse", "actualModel": None,
        "requestedModel": "opus"}, "effort": None, "result": "fail", "order": 2, "evidence": adverse_event["evidence"]})
    check("complete ordered mapped adverse events survive and block", not projected["admitted"] and
          projected["snapshot"]["prs"][0]["verdicts"] == expected_events + [{"said": 2, "head": event["head"],
          "judge": {"provider": "claude", "name": "adverse"}, "model": "unknown", "result": "fail"}])
    for provider in ["claude", "unknown", "outside", "opus", "sonnet", "haiku", "grok", "gemini"]:
        invalid = copy.deepcopy(source)
        invalid["pulls"][0]["author"]["provider"] = provider
        projected = project(invalid)
        check("null provider " + provider + " holds without an author or source rest", not projected["admitted"] and
              "author" not in projected["snapshot"]["prs"][0] and not projected["snapshot"]["prs"][0]["rest"])
    for provider in ["", "OpenAI"]:
        invalid = copy.deepcopy(source)
        invalid["pulls"][0]["author"]["provider"] = provider
        check("noncanonical lexical provider " + repr(provider) + " is refused", project(invalid) is None)
    for model in ["unknown", "inherited", "", "opus"]:
        invalid = copy.deepcopy(source)
        invalid["pulls"][0]["author"].update(actualModel=model, requestedModel="claude-opus-5-5")
        check("reported placeholder " + repr(model) + " is never promoted from requested text", project(invalid) is None)
print(f"{passed} passed")
PY
