#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
(cd "$root" && lake build mitos-gate >/dev/null)
python3 -I - "$root/.lake/build/bin/mitos-gate" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

binary = sys.argv[1]
passed = 0


def check(name, condition):
    global passed
    if not condition:
        raise AssertionError(name)
    passed += 1
    print("ok  ", name, flush=True)


def compact(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def frame(payload, version=2):
    fence = "json" if version == 1 else "text"
    return f"<!-- mitos-provenance:v{version} -->\n```{fence}\n{payload}\n```\n<!-- /mitos-provenance:v{version} -->"


def hex64(raw):
    digits = raw.hex().upper()
    return "\n".join(digits[n:n + 64] for n in range(0, len(digits), 64))


head = "a" * 40
author = {"head": head, "provider": "openai", "actor": "builder",
          "actualModel": "gpt-6.2-astra", "requestedModel": "https://example.invalid/requested/opus"}
verdict = {"head": head, "provider": "claude", "actor": "reviewer",
           "actualModel": "claude-opus-4-6", "requestedModel": None,
           "effort": "xhigh", "result": "pass", "order": 1,
           "evidence": "https://github.com/owner/mitos/pull/7#https://example.invalid/" + "x" * 180}
source = {"version": 1, "repository": "owner/mitos",
          "pulls": [{"number": 7, "author": author, "verdicts": [verdict]}]}
for actor, actual, effort, result, order, event_head in [
        ("unknown-reviewer", None, None, "fail", 3, head),
        ("hold-reviewer", "claude-opus-4-6", "low", "hold", 2, "b" * 40)]:
    event = copy.deepcopy(verdict)
    event.update(actor=actor, actualModel=actual, effort=effort, result=result, order=order, head=event_head,
                 requestedModel="https://example.invalid/requested/opus", evidence=verdict["evidence"] + result)
    source["pulls"][0]["verdicts"].append(event)
raw = compact(source)


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    (work / "open.json").write_text("[]")

    def decode(body):
        (work / "dash.json").write_text(compact({"title": "Owner dashboard", "state": "open",
                                               "user": {"login": "owner"}, "body": body}))
        result = subprocess.run([binary, "provenance", "candidates", directory, "owner/mitos", "owner"],
                                capture_output=True, timeout=30)
        return result.returncode == 0 and result.stdout == b"{}\n", result

    def render(text):
        (work / "payload.json").write_text(text)
        return subprocess.run([binary, "provenance", "render", "owner/mitos", str(work / "payload.json")],
                              capture_output=True, timeout=30)

    expected = frame(hex64(raw.encode()))
    rendered = render(raw)
    check("default writer emits exact uppercase hex64 text frame", rendered.returncode == 0 and
          rendered.stdout == (expected + "\n").encode())
    check("v2 accepts opaque nested evidence URL and requested URL", decode(expected)[0])
    check("external legacy full-URL source remains accepted", decode(frame(raw, 1))[0])

    (work / "legacy.txt").write_text(frame(raw, 1))
    (work / "current.txt").write_text(expected)
    (work / "Facts.lean").write_text('''import MitosGate.Provenance.Decode
open MitosGate.Provenance
def identityView (i : Identity) : List String :=
  [i.provider, i.actor, reprStr i.actualModel, reprStr i.requestedModel]
def factView (p : PullFact) : List (List String) :=
  ([toString p.number, p.author.head] ++ identityView p.author.identity) ::
    p.verdicts.map fun v =>
      [v.head, reprStr v.effort, (match v.result with
        | .pass => "pass" | .fail => "fail" | .hold => "hold" | .wordingOnly => "wordingOnly"),
        toString v.order, v.evidence] ++ identityView v.identity
def main (args : List String) : IO UInt32 := do
  let [oldPath, newPath] := args | return 2
  let .ok old := decode "owner/mitos" (← IO.FS.readFile oldPath) | return 1
  let .ok fresh := decode "owner/mitos" (← IO.FS.readFile newPath) | return 1
  return if old.map factView = fresh.map factView then 0 else 1
''')
    parity = subprocess.run(["lake", "env", "lean", "--run", str(work / "Facts.lean"),
                             str(work / "legacy.txt"), str(work / "current.txt")],
                            cwd=Path(binary).parents[3], capture_output=True, timeout=30)
    if parity.returncode != 0:
        print(parity.stdout.decode(), parity.stderr.decode(), file=sys.stderr)
    check("v1/v2 full typed facts preserve actual/requested/null/effort/giver/head/order/adverse evidence",
          parity.returncode == 0)

    payload = hex64(raw.encode())
    damaged = {
        "lowercase hex": frame(payload.lower()),
        "nonhex alphabet": frame("G" + payload[1:]),
        "odd nibble": frame(payload[:-1]),
        "short first row": frame(payload[:62] + "\n" + payload[62:].replace("\n", "")),
        "unwrapped long atom": frame(payload.replace("\n", "")),
        "blank row": frame(payload.replace("\n", "\n\n", 1)),
        "leading row": frame("\n" + payload),
        "trailing row": frame(payload + "\n"),
        "space": frame(" " + payload),
        "tab": frame("\t" + payload),
        "CRLF": expected.replace("\n", "\r\n"),
        "wrong fence": expected.replace("```text", "```json"),
        "unknown version": expected.replace(":v2", ":v3"),
        "mismatched close": expected.replace("/mitos-provenance:v2", "/mitos-provenance:v1"),
        "unclosed frame": expected.rsplit("\n", 1)[0],
        "duplicate section": expected + "\n" + expected,
        "mixed versions": expected + "\n" + frame(raw, 1),
        "duplicate prefix": expected + "\n<!-- mitos-provenance:v9 -->",
        "invalid UTF-8": frame("FF"),
        "overlong UTF-8": frame("C0AF"),
        "surrogate UTF-8": frame("EDA080"),
        "noncanonical inner JSON": frame(hex64(json.dumps(source, sort_keys=True).encode())),
        "duplicate inner key": frame(hex64(b'{"pulls":[],"repository":"owner/mitos","version":1,"version":1}')),
        "nested duplicate inner key": frame(hex64(raw.replace('"actor":"builder"',
                                                              '"actor":"builder","actor":"builder"').encode())),
    }
    for name, body in damaged.items():
        accepted, result = decode(body)
        check(name + " refuses with empty stdout", not accepted and result.returncode == 1 and not result.stdout)

    for prefix in ["<!-- mitos-provenance:v1 -->", "<!-- /mitos-provenance:v1 -->"]:
        inner = copy.deepcopy(source)
        inner["pulls"][0]["author"]["requestedModel"] = prefix
        text = compact(inner)
        check("inner legacy framing-sensitive prefix refuses in both versions",
              not decode(frame(text, 1))[0] and not decode(frame(hex64(text.encode())))[0])
        result = render(text)
        check("writer preserves inner framing-sensitive refusal", result.returncode == 1 and not result.stdout)

    for version, block in [(1, frame(raw, 1)), (2, expected)]:
        at_cap = "x" * (262144 - len(block.encode())) + block
        check(f"v{version} exact dashboard cap accepts", decode(at_cap)[0])
        accepted, result = decode("x" + at_cap)
        check(f"v{version} dashboard cap plus one refuses", not accepted and result.returncode == 1 and not result.stdout)

    def sized(target):
        value = copy.deepcopy(source)
        events = []
        for n in range(180):
            event = copy.deepcopy(verdict)
            event["actor"] = f"reviewer-{n}"
            event["order"] = n + 1
            event["evidence"] = f"https://github.com/owner/mitos/pull/7#e-{n}"
            events.append(event)
        value["pulls"][0]["verdicts"] = events
        needed = target - len(compact(value).encode())
        assert needed >= 0
        for event in events:
            extra = min(needed, 512 - len(event["evidence"]))
            event["evidence"] += "x" * extra
            needed -= extra
        assert needed == 0
        text = compact(value)
        assert len(text.encode()) == target
        return text

    boundary = sized(64528)
    result = render(boundary)
    exact = frame(hex64(boundary.encode()))
    check("64528-byte source renders through native shared decoder at exact physical cap",
          len(hex64(boundary.encode())) == 131072 and result.returncode == 0 and result.stdout == (exact + "\n").encode())
    check("exact physical-cap v2 source decodes natively", decode(exact)[0])
    over = sized(64529)
    result = render(over)
    check("64529-byte source refuses publication with empty stdout",
          len(hex64(over.encode())) == 131074 and result.returncode == 1 and not result.stdout)
    check("64529-byte source remains valid external legacy input", decode(frame(over, 1))[0])
    accepted, result = decode(frame(hex64(over.encode())))
    check("over-cap v2 reader refuses with empty stdout", not accepted and result.returncode == 1 and not result.stdout)

print(f"{passed} provenance transport checks passed")
PY
