import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BIN = pathlib.Path(sys.argv[1]).resolve()


def invoke(file):
    out = subprocess.run([str(BIN), "workflow", "placement", str(file)],
                         capture_output=True, text=True, timeout=20)
    assert "PANIC" not in out.stderr and not out.stdout, (file, out)
    return out


def check(file, reason=None, line=None):
    out = invoke(file)
    assert out.returncode == (1 if reason else 0), (file, out)
    if reason:
        assert reason in out.stderr, (file, out.stderr)
        if line is not None:
            assert out.stderr.startswith(f"{file}:{line}: refused"), out.stderr
        if reason.startswith("rule "):
            assert ": refused at " in out.stderr, out.stderr
            assert len(out.stderr.splitlines()) == 1, out.stderr
    else:
        assert not out.stderr, (file, out.stderr)


bases = [ROOT / ".github/workflows/land.yml",
         ROOT / "gate/workflow-fixtures/placement-land-336.yml"]
needs = "${{ needs.d.outputs.p }}"
prefix = "jobs:\n  a:\n    steps:\n"
cases = [
    ("shape-a", prefix + "      # x: |\n      - run: echo " + needs + "\n", "rule N"),
    ("shape-b", prefix + "      - name: |\n          step\n        run: echo " + needs + "\n", "rule N"),
    ("shape-d", prefix + '      - run: "${{ \\x6eeeds.d.outputs.p }}"\n', "rule N"),
    ("shape-d2", prefix + '      - run: "\\x24{{ needs.d.outputs.p }}"\n', "expression count differs"),
    ("alias", prefix + "      - run: *answers\n", "alias"),
    ("to-json", prefix + "      - run: toJSON(needs)\n", "rule N"),
    ("computed", prefix + "      - run: needs.decide[format('{0}puts','out')]\n", "rule N"),
    ("from-json", prefix + "      - run: fromJSON(toJSON(needs)).decide.outputs.answers\n", "rule N"),
    ("upper-needs", prefix + "      - run: NEEDS.x\n", "rule N"),
    ("with-script", prefix + "      - with:\n          script: " + needs + "\n", "rule N"),
    ("hash-content", prefix + "      - run: echo a#" + needs + "\n", "rule N"),
    ("shape-e", "env:\n  X: " + needs + "\n" + prefix + "      - run: echo ${{ env.X }}\n", "rule X"),
    ("script-indirection", "env:\n  X: " + needs + "\n" + prefix + "      - with:\n          script: ${{ env.X }}\n", "rule X"),
    ("step-output", prefix + "      - run: echo ${{ steps.a.outputs.x }}\n", "rule X"),
    ("github-env", prefix + "      - run: echo ${{ env.FROM_GITHUB_ENV }}\n", "rule X"),
    ("literal", prefix + "      - run: |\n          echo " + needs + "\n", "rule N"),
    ("folded", prefix + "      - run: >-\n          echo\n          " + needs + "\n", "rule N"),
    ("step-if", prefix + "      - if: " + needs + "\n", "rule N"),
    ("job-name", "jobs:\n  a:\n    name: " + needs + "\n", "rule N"),
    ("nested-env", "env:\n  X:\n    Y: " + needs + "\n", "rule N"),
]
for char in ["\r", "\x85", "\u2028", "\u2029"]:
    cases.append(("shape-c", prefix + "      - run: echo ok" + char + "needs.x\n",
                  "outside LF and printable ASCII"))

lines = {"shape-a": 5, "shape-b": 6, "with-script": 5, "script-indirection": 7,
         "shape-e": 6, "job-name": 3, "nested-env": 3}

accepted = [
    "env:\n  X: " + needs + "\n",
    "env:\n  X: \"${{ \\x6eeeds.d.outputs.p }}\"\n",
    "jobs:\n  a:\n    env:\n      X: " + needs + "\n",
    prefix + "      - env:\n          X: " + needs + "\n        run: echo $X\n",
    "jobs:\n  a:\n    if: " + needs + "\n",
    "jobs:\n  a:\n    needs: needs\n",
    "jobs:\n  a:\n    needs: [needs, other]\n",
    prefix + "      - run: echo unneeds-x needs_x 2needs needs2 _needs\n",
    prefix + "      - uses: a/b@c\n        with:\n          value: ${{ github.sha }}\n",
    "jobs:\n  a:\n    env: {}\n    steps: []\n",
]

with tempfile.TemporaryDirectory(prefix="workflow-placement-") as tmp:
    tmp = pathlib.Path(tmp)
    for base in bases:
        check(base)
        original = base.read_text()
        for i, (name, source, reason) in enumerate(cases):
            file = tmp / f"{base.stem}-{name}-{i}.yml"
            if source.startswith("env:"):
                env, separator, job = source.partition("jobs:\n  a:\n")
                existing = "\nenv:\n" in original
                mutated = original.replace("\nenv:\n", "\n" + env, 1) if existing else env + original
                if separator:
                    mutated += "\n  placement-fixture:\n" + job
                    offset = len(original.splitlines()) - int(existing)
                else:
                    offset = original.splitlines().index("env:") if existing else 0
            else:
                mutated = original + "\n  placement-fixture:\n" + source.removeprefix("jobs:\n  a:\n")
                offset = len(original.splitlines())
            file.write_bytes(mutated.encode())
            check(file, reason, offset + lines.get(name, 4))
    for i, source in enumerate(accepted):
        file = tmp / f"accepted-{i}.yml"
        file.write_text(source)
        check(file)
    escaped = tmp / "escaped-with-matching-comment.yml"
    escaped.write_text(prefix + '      - run: "\\x6eeeds.x"\n# needs.x\n')
    check(escaped, "rule N", 4)
    assert ": refused at jobs.a.steps[0].run:" in invoke(escaped).stderr
    missing = invoke(tmp / "missing.yml")
    assert missing.returncode == 2 and "workflow: cannot read" in missing.stderr, missing
    for args in [["placement"], ["placement", "one", "two"]]:
        out = subprocess.run([str(BIN), "workflow", *args], capture_output=True, text=True, timeout=20)
        assert out.returncode == 2 and not out.stdout and "usage:" in out.stderr, out

print(f"workflow placement passed ({len(bases)} land workflows, {len(cases) * len(bases)} mutations, {len(accepted)} accepted controls, IO and usage)")
