import argparse
import hashlib
import io
import json
import os
import pathlib
import resource
import shutil
import statistics
import subprocess
import tarfile
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent


def checked_run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (args, result.stdout[-4000:], result.stderr[-4000:])
    return result


def summary(values):
    return {"median_s": statistics.median(values), "min_s": min(values), "max_s": max(values)}


def runtime(output):
    binary = ROOT / ".lake/build/bin/mitos-gate"
    file = ROOT / ".github/workflows/ci.yml"
    dumped = checked_run([str(binary), "workflow", "leaves", str(file)])
    assert not dumped.stderr
    leaves = [json.loads(line) for line in dumped.stdout.splitlines()]
    assert leaves
    checked_run(["strace", "-c", "-o", str(output / "strace.txt"), str(binary),
                 "workflow", "parse", str(file)])
    runs = []
    for i in range(10):
        cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
        start = time.perf_counter()
        result = checked_run([str(binary), "workflow", "parse", str(file)])
        elapsed = time.perf_counter() - start
        cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN)
        assert not result.stdout and not result.stderr, (i, result)
        runs.append({"wall_s": elapsed, "cpu_s": cpu_after.ru_utime + cpu_after.ru_stime
                     - cpu_before.ru_utime - cpu_before.ru_stime})
    return {"input": "ci.yml", "bytes": file.stat().st_size, "leaves": len(leaves),
            "sha256": hashlib.sha256(file.read_bytes()).hexdigest(), "runs": runs,
            "failures": 0, **summary([run["wall_s"] for run in runs])}


def reset(root, side):
    prefixes = ["MitosGate/WorkflowCli", "Main"]
    prefixes += ["MitosGate/Yaml/Line", "MitosGate/Yaml/LineCases"] if side == "before" else [
        "MitosGate/Yaml"]
    if side == "after":
        for area in ["lib/lean/L4YAML", "ir/L4YAML"]:
            shutil.rmtree(root / ".lake/build" / area, ignore_errors=True)
    for area in ["lib/lean", "ir"]:
        for prefix in prefixes:
            target = root / ".lake/build" / area / prefix
            for file in target.parent.glob(target.name + ".*"):
                if file.is_file():
                    file.unlink()
    for file in (root / ".lake/build/bin").glob("mitos-gate*"):
        if file.is_file():
            file.unlink()


def builds(output, base):
    baseline = checked_run(["git", "rev-parse", base + "^{commit}"], cwd=ROOT).stdout.strip()
    archive = subprocess.run(["git", "archive", baseline], cwd=ROOT, capture_output=True, check=True)
    for side in ["before", "after"]:
        root = output / side
        root.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
            tar.extractall(root, filter="data")
        shutil.copytree(ROOT / ".lake", root / ".lake")
        shutil.copytree(ROOT / "core/.lake", root / "core/.lake", dirs_exist_ok=True)
        if side == "after":
            shutil.rmtree(root / "gate")
            shutil.copytree(ROOT / "gate", root / "gate")
            for name in ["lakefile.toml", "lean-toolchain"]:
                shutil.copy2(ROOT / name, root / name)

    def build(side, index):
        root = output / side
        reset(root, side)
        start = time.perf_counter()
        result = checked_run(["lake", "build", "mitos-gate"], cwd=root)
        elapsed = time.perf_counter() - start
        log = result.stdout + result.stderr
        (output / f"{side}-{index}.log").write_text(log)
        assert "Built Main" in log and "Built MitosGate.Yaml" in log, (side, index, log)
        parsed = checked_run([str(root / ".lake/build/bin/mitos-gate"), "workflow", "parse",
                              ".github/workflows/ci.yml"], cwd=root)
        assert not parsed.stdout and not parsed.stderr
        return elapsed

    for side in ["before", "after"]:
        build(side, "warmup")
    runs = []
    for index in range(3):
        for side in ["before", "after"]:
            elapsed = build(side, index + 1)
            runs.append({"side": side, "run": index + 1, "seconds": elapsed})
            print(json.dumps(runs[-1]), flush=True)
    result = {"baseline_ref": base, "baseline_sha": baseline,
              "command": "lake build mitos-gate", "runs": runs, "failures": 0}
    for side in ["before", "after"]:
        result[side] = summary([run["seconds"] for run in runs if run["side"] == side])
    result["delta_s"] = result["after"]["median_s"] - result["before"]["median_s"]
    return result


parser = argparse.ArgumentParser()
parser.add_argument("--base", default="origin/main")
parser.add_argument("--mode", choices=["runtime", "build", "both"], default="both")
parser.add_argument("--output", type=pathlib.Path)
args = parser.parse_args()
output = (args.output or pathlib.Path(tempfile.mkdtemp(prefix="workflow-benchmark-"))).resolve()
output.mkdir(exist_ok=True)
assert not list(output.iterdir()), "benchmark output directory must be empty"
print(json.dumps({"output": str(output), "load": os.getloadavg(), "logical_cpus": os.cpu_count()}), flush=True)
results = {}
if args.mode in ["runtime", "both"]:
    results["runtime"] = runtime(output)
    print(json.dumps(results["runtime"]), flush=True)
if args.mode in ["build", "both"]:
    results["build"] = builds(output, args.base)
(output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print(json.dumps(results, indent=2), flush=True)
