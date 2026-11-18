import copy
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
base = root / "gate/MitosGate"
source = json.loads((root / "gate/provenance-fixtures/488.json").read_text())
model = (base / "ModelIdentity.lean").read_text().split("theorem acceptedNeedsClaude")[0]
land = (base / "Land.lean").read_text().split("theorem next_landable")[0]
start = land.index("theorem reportedCovered_iff")
end = land.index("instance (o : Obs) : Decidable o.Covered", start)
land = land[:start] + land[end:]
provenance = (base / "Provenance.lean").read_text().split("theorem projectionPreservesEvents")[0]
decode = (base / "Provenance/Decode.lean").read_text().split("theorem render_isDecoded")[0]
original = {
    "ModelIdentity": model + "\nend MitosGate.ModelIdentity\n",
    "Land": land + "\nend MitosGate.Land\n",
    "Provenance": provenance + "\nend MitosGate.Provenance\n",
    "Provenance/Decode": decode + "\nend MitosGate.Provenance\n",
}
probe = '''import MitosGate.Provenance.Decode
open MitosGate MitosGate.Provenance
def main (args : List String) : IO UInt32 := do
  let [path, mode] := args | return 2
  let .ok [p] := decode "kitimark/mitos" (← IO.FS.readFile path) | return 1
  let head := "60b10dc1c4428c26e5cbcb78a4f8aaf83e1977cc"
  let o : Land.Obs :=
    { pr := 488, updatable := true, enforced := true, head, pushes := [],
      ids := [(head, "same-content")], paths := some (if mode == "critical" then ["gate/Test.lean"] else ["ordinary"]),
      base := .current, gate := .success, author := none, verdicts := [], botAt := some head,
      delegates := [], words := [], rest := true }
  let p := if mode == "typed-placeholder" then
    { p with author := { p.author with identity := { p.author.identity with actualModel := some "inherited" } } }
    else p
  let value := if mode == "same-provider" then
      ModelIdentity.different "openai" .absent "openai" "gpt-6.2-astra"
    else if mode == "unknown-judge" then ModelIdentity.different "openai" .absent "claude" "unknown"
    else if mode == "noncanonical-relation" then ModelIdentity.different "outside" .absent "claude" "claude-opus-5-5"
    else if mode == "retained" then (authorOf o p).isSome
    else if mode == "covered" then (withFacts o p).covered
    else admitted o p
  IO.println (toString value)
  return 0
'''


def changed(modules, name, old, new):
    assert old in modules[name], (name, old)
    modules[name] = modules[name].replace(old, new)


def case(name, mutate, change_source=lambda p: None, mode="ordinary", scope="admission"):
    payload = copy.deepcopy(source)
    change_source(payload["pulls"][0])
    modules = dict(original)
    mutate(modules)
    return name, modules, payload, mode, scope


def word(p):
    p["verdicts"] = [dict(p["verdicts"][0], actor="root", result="wordingOnly")]


def append(p, result, actor=None):
    event = dict(p["verdicts"][0], result=result, order=2,
                 evidence=p["verdicts"][0]["evidence"] + "-later")
    if actor:
        event["actor"] = actor
    p["verdicts"].append(event)


def remove_word_guards(ms):
    changed(ms, "Land", "a.model ≠ .absent ∧", "True ∧")
    changed(ms, "Provenance", "a.model != .absent &&", "true &&")


def remove_acceptance(ms):
    changed(ms, "Land", "ModelIdentity.acceptedClaude v.judge.provider v.model = true", "True")
    changed(ms, "Provenance",
            'ModelIdentity.acceptedClaude v.identity.provider (v.identity.actualModel.getD "unknown") &&',
            'true &&')

cases = [
    case("canonical membership", lambda ms: changed(ms, "ModelIdentity", '| _ => false\n\ninductive Key',
         '| _ => true\n\ninductive Key'), lambda p: p["author"].update(provider="outside")),
    case("mandatory PASS / both wording branches", remove_word_guards, word),
    case("actual accepted Claude PASS", remove_acceptance,
         lambda p: p["verdicts"][0].update(provider="google", actualModel="gemini-3-pro")),
    case("source wording branch cannot bypass critical effort", lambda ms: changed(ms, "Provenance",
         "a.model != .absent &&", "true &&"),
         lambda p: (p["verdicts"][0].update(effort="low"), append(p, "wordingOnly", "root")), "critical"),
    case("standing PASS retirement", lambda ms: changed(ms, "Land",
         "o.carries v.head = true ∧\n    ∀ w ∈ o.verdicts, o.carries w.head = true → w.judge = v.judge → w.said ≤ v.said",
         "o.carries v.head = true"), lambda p: append(p, "wordingOnly")),
    case("standing adverse veto", lambda ms: changed(ms, "Land",
         "(∀ v ∈ o.verdicts, o.stands v → v.result ≠ .fail ∧ v.result ≠ .hold)", "True"),
         lambda p: append(p, "hold", "adverse")),
    case("author carry", lambda ms: changed(ms, "Provenance", "unless o.carries p.author.head do none",
         "unless true do none"), lambda p: p["author"].update(head="f" * 40)),
    case("critical actual effort", lambda ms: changed(ms, "Provenance", "| _ => false\n\ndef requiresOpus",
         "| _ => true\n\ndef requiresOpus"), lambda p: p["verdicts"][0].update(effort="low"), "critical"),
    case("provider inequality", lambda ms: changed(ms, "ModelIdentity", "authorProvider != judgeProvider &&",
         "true &&"), mode="same-provider", scope="relation helper; accepted-Claude remains separate"),
    case("known actual judge key", lambda ms: changed(ms, "ModelIdentity", "(key judgeProvider judgeModel).isSome",
         "true"), mode="unknown-judge", scope="relation helper; accepted-Claude remains separate"),
    case("absent relation canonical guard", lambda ms: changed(ms, "ModelIdentity",
         "canonicalOutside authorProvider &&", "true &&"), mode="noncanonical-relation", scope="relation helper; retention still rejects"),
    case("absent author retention canonical guard", lambda ms: changed(ms, "Provenance",
         "unless ModelIdentity.canonicalOutside p.author.identity.provider do none", "unless true do none"),
         lambda p: p["author"].update(provider="outside"), "retained", "projection helper; independence still rejects"),
    case("Land wording branch cannot cover absent author", lambda ms: changed(ms, "Land",
         "a.model ≠ .absent ∧", "True ∧"), word, "covered", "Land coverage helper; source still rejects"),
    case("null-only projection", lambda ms: changed(ms, "Provenance",
         'unless (ModelIdentity.key p.author.identity.provider actual).isSome do none\n    return ⟨p.author.identity.who, .reported actual⟩',
         'if (ModelIdentity.key p.author.identity.provider actual).isSome then\n      return ⟨p.author.identity.who, .reported actual⟩\n    else return ⟨p.author.identity.who, .absent⟩'),
         mode="typed-placeholder", scope="typed helper; raw decoder independently rejects inherited"),
]

lean_path = subprocess.check_output(["lake", "env", "printenv", "LEAN_PATH"], cwd=root, text=True).strip()
lean = subprocess.check_output(["lake", "env", "which", "lean"], cwd=root, text=True).strip()
with tempfile.TemporaryDirectory(prefix="mitos-provider-mutants-") as directory:
    work = Path(directory)

    def evaluate(modules, payload, mode, name):
        build = work / name
        env = dict(os.environ, LEAN_PATH=str(build) + os.pathsep + lean_path)
        if not build.exists():
            build.mkdir()
            shutil.copytree(root / ".lake/build/lib/lean/MitosGate", build / "MitosGate")
            for module, contents in modules.items():
                path = build / "MitosGate" / (module + ".lean")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
                result = subprocess.run([lean, "-o", str(path.with_suffix(".olean")), str(path)],
                                        cwd=build, env=env, capture_output=True, timeout=60)
                assert result.returncode == 0, result.stdout.decode() + result.stderr.decode()
            (build / "Probe.lean").write_text(probe)
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode().hex().upper()
        frame = "<!-- mitos-provenance:v2 -->\n```text\n" + "\n".join(raw[i:i+64] for i in range(0, len(raw), 64))
        (build / "source.block").write_text(frame + "\n```\n<!-- /mitos-provenance:v2 -->")
        result = subprocess.run([lean, "--run", "Probe.lean", "source.block", mode], cwd=build, env=env,
                                capture_output=True, timeout=60)
        assert result.returncode == 0, result.stdout.decode() + result.stderr.decode()
        return result.stdout.decode().strip()

    for n, (name, modules, payload, mode, scope) in enumerate(cases):
        baseline = evaluate(original, payload, mode, "baseline")
        mutant = evaluate(modules, payload, mode, str(n) + "-mutant")
        assert baseline == "false" and mutant == "true", (name, baseline, mutant)
        print(f"ok {name}: negative expectation false -> true ({scope}; fresh .olean closure + Lean interpreter)", flush=True)
print(f"{len(cases)} guard mutants rejected by their named negative expectations")
