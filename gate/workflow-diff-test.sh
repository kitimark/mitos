#!/usr/bin/env bash
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
exec python3 -I - "$root" <<'PY'
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
gate = root / ".lake/build/bin/mitos-gate"
diff = root / "gate/workflow-diff.sh"
reader = root / "gate/workflow_leaves.py"
assert gate.is_file() and os.access(gate, os.X_OK), "build the real mitos-gate first"
checks = 0


def run(command, status=0, env=None):
    global checks
    result = subprocess.run([str(arg) for arg in command], capture_output=True, text=True, env=env, timeout=30)
    assert result.returncode == status, (command, result.returncode, result.stdout, result.stderr)
    checks += 1
    return result.stdout + result.stderr


with tempfile.TemporaryDirectory(prefix="workflow-diff-test-") as tmp:
    tmp = pathlib.Path(tmp)
    tiny = tmp / "tiny.yml"
    marker = "before ##[warning] legacy ::warning::modern"
    tiny.write_text('on: [push]\npermissions: {}\nempty:\nseq: []\noctal: 0777\ntruth: true\nnull: null\nname: PANIC\njobs:\n  build:\n    steps:\n      - run: ' + json.dumps(marker) + '\n')
    output = run([diff, tiny])
    assert "PyYAML equal" in output and "1 files compared, 0 differences" in output
    leaves = [json.loads(line) for line in run([sys.executable, "-I", reader, tiny]).splitlines()]
    assert {"path": ["on", 0], "value": "push"} in leaves
    for key, value in (("permissions", {}), ("empty", ""), ("seq", []), ("octal", "0777"), ("truth", "true"), ("null", "null"), ("name", "PANIC")):
        assert {"path": [key], "value": value} in leaves
    assert leaves[-1] == {"path": ["jobs", "build", "steps", 0, "run"], "value": marker}

    stub = tmp / "gate-stub"
    stub.write_text("#!/usr/bin/env python3\n" + f"REAL = {str(gate)!r}\n" + '''import json
import os
import subprocess
import sys
mode = os.environ.get("DIFF_STUB", "mismatch")
verb, file = sys.argv[2:]
if verb == "parse" and mode in ("refusal", "drift", "extra", "panic", "panic-stdout"):
    suffix = ": refused at jobs.issue.steps[0]: anchor"
    if mode == "drift": suffix = suffix.replace("anchor", "alias")
    if mode == "extra": suffix += " extra"
    print(file + suffix, file=sys.stderr)
    if mode == "panic": print("PANIC", file=sys.stderr)
    if mode == "panic-stdout": print("PANIC")
    sys.exit(1)
result = subprocess.run([REAL, *sys.argv[1:]], capture_output=True, text=True)
if verb == "leaves" and result.returncode == 0:
    leaves = [json.loads(line) for line in result.stdout.splitlines()]
    if mode == "mismatch": leaves[-1]["value"] += " changed"
    if mode == "order": leaves.reverse()
    if mode == "missing": leaves.pop()
    if mode == "bool-index": leaves[-1]["path"][-2] = False
    if mode == "bool-value": leaves[-1]["value"] = True
    if mode == "malformed": print("PANIC: broken leaf output"); sys.exit(0)
    if mode == "leaves-error": print("leaf failure", file=sys.stderr); sys.exit(1)
    print("\\n".join(json.dumps(leaf) for leaf in leaves))
else:
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
sys.exit(result.returncode)
''')
    stub.chmod(0o755)
    mismatch = run([diff, "--gate", stub, tiny], 1)
    assert "jobs" in mismatch and "run" in mismatch and "leaf " in mismatch
    assert "##[" not in mismatch and "::" not in mismatch
    diagnostic = json.loads(next(line for line in mismatch.splitlines() if "leaf " in line).split(": ", 2)[2])
    wanted = json.loads(diagnostic.split("; PyYAML=", 1)[1])
    assert wanted == leaves[-1]
    for mode in ("order", "missing", "bool-index", "bool-value", "malformed", "leaves-error"):
        run([diff, "--gate", stub, tiny], 1, {**os.environ, "DIFF_STUB": mode})

    refusal = tmp / "refused.yml"
    refusal.write_text("a: &anchor b\n")
    assert "anchor" in run([diff, refusal], 1)
    assert "outside the subset" in run([sys.executable, "-I", reader, refusal], 3)
    for source in ("a: *anchor\n", "a: !!str b\n", "a: &anchor []\n", "a: !tag {}\n"):
        refusal.write_text(source)
        assert "outside the subset" in run([sys.executable, "-I", reader, refusal], 3)

    owner = root / ".github/workflows/owner-ping.yml"
    assert "1 files compared, 0 differences" in run([diff, owner])
    impostor = tmp / owner.name
    shutil.copyfile(owner, impostor)
    run([diff, impostor])
    for mode in ("refusal", "drift", "extra", "panic", "panic-stdout"):
        run([diff, "--gate", stub, owner], 1, {**os.environ, "DIFF_STUB": mode})

    run([diff, "--gate", tmp / "missing-gate", tiny], 2)
    empty_path = tmp / "empty-path"
    empty_path.mkdir()
    assert "missing python3" in run(["/bin/bash", diff, tiny], 2, {**os.environ, "PATH": str(empty_path)})
    no_yaml = tmp / "no-yaml"
    no_yaml.mkdir()
    python = no_yaml / "python3"
    python.write_text(f'#!/bin/bash\nexec {shutil.which("python3")} -S "$@"\n')
    python.chmod(0o755)
    assert "missing PyYAML" in run(["/bin/bash", diff, tiny], 2, {**os.environ, "PATH": str(no_yaml)})

    sandbox = tmp / "discovery"
    (sandbox / "gate").mkdir(parents=True)
    workflows = sandbox / ".github/workflows"
    workflows.mkdir(parents=True)
    shutil.copyfile(reader, sandbox / "gate/workflow_leaves.py")
    shutil.copy2(diff, sandbox / "gate/workflow-diff.sh")
    shutil.copyfile(tiny, workflows / "one.yml")
    shutil.copyfile(tiny, workflows / "two.yaml")
    output = run([sandbox / "gate/workflow-diff.sh", "--gate", gate])
    assert "one.yml" in output and "two.yaml" in output
    assert "2 files compared, 0 differences" in output
    (workflows / "one.yml").unlink()
    (workflows / "two.yaml").unlink()
    assert "no workflows found" in run([sandbox / "gate/workflow-diff.sh", "--gate", gate], 1)
    issue, pr = owner.read_text().split("\n  pr:\n", 1)
    issue = issue.replace("      - name:", "      - &ping\n        name:", 1)
    pr = pr.split("    steps:\n", 1)[0] + "    steps:\n      - *ping\n"
    (workflows / owner.name).write_text(issue + "\n  pr:\n" + pr)
    output = run([sandbox / "gate/workflow-diff.sh", "--gate", gate], 1)
    assert "anchor" in output and "0 files compared, 1 differences" in output

print(f"workflow-diff-test: {checks} checks passed (real mitos-gate and PyYAML)")
PY
