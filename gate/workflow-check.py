import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "gate/workflow-fixtures"
BIN = pathlib.Path(sys.argv[1]).resolve()


def invoke(verb, file):
    out = subprocess.run([str(BIN), "workflow", verb, str(file)], capture_output=True,
                         text=True, timeout=20)
    assert "PANIC" not in out.stderr, (file, out.stderr)
    return out


def check(case, file):
    parsed = invoke("parse", file)
    dumped = invoke("leaves", file)
    assert not parsed.stdout, (case["name"], parsed.stdout)
    if "leaves" in case:
        assert parsed.returncode == dumped.returncode == 0, (case["name"], parsed.stderr, dumped.stderr)
        assert not parsed.stderr and not dumped.stderr, (case["name"], parsed.stderr, dumped.stderr)
        actual = [json.loads(line) for line in dumped.stdout.splitlines()]
        assert actual == case["leaves"], (case["name"], actual, case["leaves"])
    else:
        assert parsed.returncode == dumped.returncode == 1, (case["name"], parsed.returncode,
                                                            parsed.stderr, dumped.returncode, dumped.stderr)
        assert not dumped.stdout, (case["name"], dumped.stdout)
        assert parsed.stderr == dumped.stderr, (case["name"], parsed.stderr, dumped.stderr)
        if "refusal" in case:
            assert parsed.stderr == str(file) + case["refusal"] + "\n", (case["name"], parsed.stderr)
        else:
            assert case["refusal_contains"] in parsed.stderr, (case["name"], parsed.stderr)


cases = json.loads((FIXTURES / "cases.json").read_text())
with tempfile.TemporaryDirectory(prefix="workflow-test-") as tmp:
    tmp = pathlib.Path(tmp)
    for case in cases:
        file = FIXTURES / case["file"] if "file" in case else tmp / (case["name"] + ".yml")
        if "source" in case:
            file.write_text(case["source"])
        check(case, file)
    ci = (ROOT / ".github/workflows/ci.yml").read_text()
    for char in ["\r", "\t", "\x85", "\u2028", "\u2029"]:
        file = tmp / "control.yml"
        file.write_bytes((ci + "\n# control" + char + "\n").encode())
        check({"name": "copied-control", "refusal_contains": "outside LF and printable ASCII"}, file)
    file = tmp / "copied-block.yml"
    file.write_text(ci + "\n# x: |\nshapeA: plain\nshapeB:\n  - name: |\n    run: echo ok\n")
    check({"name": "copied-block", "refusal_contains": "empty block scalar"}, file)
    file = tmp / "copied-escape.yml"
    file.write_text(ci + 'run: "echo ${{ \\x6eeeds.decide.outputs.pr }}"\n')
    parsed = invoke("parse", file)
    assert parsed.returncode == 0 and not parsed.stdout and not parsed.stderr, parsed
    dumped = invoke("leaves", file)
    assert dumped.returncode == 0 and not dumped.stderr, dumped
    assert {"path": ["run"], "value": "echo ${{ needs.decide.outputs.pr }}"} in [
        json.loads(line) for line in dumped.stdout.splitlines()]
    for verb in ["parse", "leaves"]:
        missing = invoke(verb, tmp / "missing.yml")
        assert missing.returncode == 2 and not missing.stdout and "workflow: cannot read" in missing.stderr
        invalid = tmp / "invalid-utf8.yml"
        invalid.write_bytes(b"a: \xff\n")
        out = invoke(verb, invalid)
        assert out.returncode == 2 and not out.stdout and "workflow: cannot read" in out.stderr
    for args in [[], ["parse"], ["leaves"], ["other", "missing"], ["parse", "one", "two"]]:
        out = subprocess.run([str(BIN), "workflow", *args], capture_output=True, text=True, timeout=20)
        assert out.returncode == 2 and not out.stdout and "usage:" in out.stderr, (args, out)
        assert "PANIC" not in out.stderr, (args, out.stderr)
    cap = tmp / "cap.yml"
    cap.write_text("a: " + "x" * 65533)
    parsed = invoke("parse", cap)
    assert parsed.returncode == 0 and not parsed.stdout and not parsed.stderr, parsed
    cap.write_text('a: "' + "[" * 1024 + '"\n')
    parsed = invoke("parse", cap)
    assert parsed.returncode == 0 and not parsed.stdout and not parsed.stderr, parsed
    structure_cases = [
        ("compact-at-budget", "a:\n" + "- " * 2047 + "x\n",
         {"leaves": [{"path": ["a"] + [0] * 2047, "value": "x"}]}),
        ("compact-over-budget", "a:\n" + "- " * 2048 + "x\n",
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("compact-under-byte-cap", "a:\n" + "- " * 32765 + "x\n",
         {"refusal": ": refused: 32766 structural characters exceeds 2048"}),
        ("compact-over-byte-cap", "a:\n" + "- " * 32766 + "x\n",
         {"refusal": ": refused: 65537 bytes exceeds 65536"}),
        ("flat-flow-at-budget", "a: [" + ",".join(["x"] * 2047) + "]\n",
         {"leaves": [{"path": ["a", i], "value": "x"} for i in range(2047)]}),
        ("flat-flow-over-budget", "a: [" + ",".join(["x"] * 2048) + "]\n",
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("mixed-structure-over-budget", "a:\n" + "- " * 1024 + "[" * 1024 + "x" + "]" * 1024,
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("mixed-structure-at-budget", "a:\n" + "- " * 2046 + "[x]\n",
         {"leaves": [{"path": ["a"] + [0] * 2047, "value": "x"}]}),
        ("multiline-sequence-over-budget", "a:\n" + "- x\n" * 2048,
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("multiline-mapping-over-budget", "".join(f"k{i}: x\n" for i in range(2049)),
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("multiline-explicit-keys-over-budget", "? x\n" * 2049,
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("structure-before-parse", "- " * 2049 + "'",
         {"refusal": ": refused: 2049 structural characters exceeds 2048"}),
        ("char-before-structure", "a:\n\t" + "- " * 2049,
         {"refusal": ":2: refused: character U+0009 outside LF and printable ASCII"}),
        ("openers-before-structure", "[" * 1025 + "-" * 2049,
         {"refusal": ": refused: 1025 opening brackets exceeds 1024"}),
        ("directive-before-structure", "%FOO\na: " + "-" * 2049,
         {"refusal": ": refused: directive"}),
    ]
    for marker in "-?:,":
        for prefix, suffix in [('a: "', '"\n'), ("a: '", "'\n"), ("a: |\n  ", "\n"), ("a: x\n# ", "\n")]:
            structure_cases.append(("raw-punctuation-data", prefix + marker * 2048 + suffix,
                                    {"refusal": ": refused: 2049 structural characters exceeds 2048"}))
        structure_cases.append(("quoted-punctuation-at-budget", 'a: "' + marker * 2047 + '"\n',
                                {"leaves": [{"path": ["a"], "value": marker * 2047}]}))
    assert len(structure_cases[2][1].encode()) == 65535
    for name, source, expected in structure_cases:
        file = tmp / (name + ".yml")
        file.write_text(source)
        check({"name": name, **expected}, file)
for name in ["ci", "nightly", "clear-needs-rebase", "land-protection", "land", "update-prs"]:
    out = invoke("parse", ROOT / f".github/workflows/{name}.yml")
    assert out.returncode == 0 and not out.stdout and not out.stderr, (name, out)
owner = ROOT / ".github/workflows/owner-ping.yml"
out = invoke("parse", owner)
assert out.returncode == 1 and not out.stdout, out
assert out.stderr == str(owner) + ": refused at jobs.issue.steps[0]: anchor\n", out.stderr
print(f"workflow tests passed ({len(cases)} fixtures, {len(structure_cases)} structure cases, both verbs, boundaries and live workflows)")
