import argparse
import hashlib
import json
import os
import pathlib
import statistics
import subprocess
import tempfile
import time

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
CAP = 65536


def padded(source):
    gap = CAP - len(source.encode())
    assert gap >= 0, len(source.encode())
    if gap < 2:
        return "\n" * gap + source
    return "#" + "x" * (gap - 2) + "\n" + source


def oracle(source):
    pending = [(yaml.compose(source, Loader=yaml.SafeLoader), [])]
    result = []
    while pending:
        node, path = pending.pop()
        if isinstance(node, yaml.ScalarNode):
            result.append({"path": path, "value": node.value})
        elif isinstance(node, yaml.MappingNode):
            if not node.value:
                result.append({"path": path, "value": {}})
            pending.extend((child, path + [key.value]) for key, child in reversed(node.value))
        elif isinstance(node, yaml.SequenceNode):
            if not node.value:
                result.append({"path": path, "value": []})
            pending.extend((child, path + [i]) for i, child in reversed(list(enumerate(node.value))))
        else:
            raise AssertionError(node)
    return result


def workloads():
    yield "compact-65535", "a:\n" + "- " * 32765 + "x\n", 1, None
    yield "compact-at-budget", padded("a:\n" + "- " * 2047 + "x\n"), 0, [
        {"path": ["a"] + [0] * 2047, "value": "x"}]
    yield "compact-over-budget", padded("a:\n" + "- " * 2048 + "x\n"), 1, None
    yield "mixed-at-budget", padded("a:\n" + "- " * 1023 + "[" * 1024 + "x" + "]" * 1024), 1, None
    yield "explicit-at-budget", padded("a:\n" + "? " * 2047 + "x\n"), 1, None
    yield "malformed-at-budget", padded("a:\n" + "- " * 2047 + "'"), 1, None
    yield "wide-map-late", padded("".join(f"k{i:04}: x\n" for i in range(2048))), 0, None
    yield "wide-map-long-keys", padded("".join(f"{'k' * 20}{i:04}: x\n" for i in range(2048))), 0, None
    yield "wide-map-over-budget", padded("".join(f"k{i}: x\n" for i in range(7405))), 1, None
    yield "flat-flow-at-budget", padded("a: [" + ",".join(["x"] * 2047) + "]\n"), 0, None
    yield "block-scalars-late", padded("".join(f"k{i:04}: |\n  x\n" for i in range(2048))), 0, None
    yield "deep-mapping", padded("".join(" " * i + "k:\n" for i in range(250)) + " " * 250 + "x\n"), 0, [
        {"path": ["k"] * 250, "value": "x"}]
    yield "plain-scalar", "a: " + "x" * (CAP - 3), 0, None
    yield "quoted-scalar", 'a: "' + "x" * (CAP - 6) + '"\n', 0, None
    yield "quoted-punctuation", padded('a: "' + "-?:," * 511 + "---" + '"\n'), 0, None
    yield "quoted-openers", padded('a: "' + "[" * 1024 + '"\n'), 0, None
    yield "blank-lines", "\n" * (CAP - 5) + "a: x\n", 0, None
    yield "comment-lines", padded("#\n" * 32764 + "a: x\n"), 0, None
    yield "multiline-plain", padded("a: x\n" + "  x\n" * 16000), 0, None
    yield "multiline-quoted", padded('a: "x\n' + "  x\n" * 16000 + '  x"\n'), 0, None
    yield "multiline-quoted-min-indent", padded('a: "x\n' + " x\n" * 21840 + ' x"\n'), 0, None
    yield "folded-scalar", padded("a: >\n" + "  x\n" * 16000), 0, None
    yield "ci", (ROOT / ".github/workflows/ci.yml").read_text(), 0, None


def measured(command):
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        started = time.perf_counter()
        child = subprocess.Popen(command, stdout=stdout, stderr=stderr)
        while True:
            pid, status, usage = os.wait4(child.pid, os.WNOHANG)
            if pid:
                break
            if time.perf_counter() - started > 30:
                child.kill()
                os.wait4(child.pid, 0)
                raise TimeoutError(command)
            time.sleep(0.001)
        elapsed = time.perf_counter() - started
        child.returncode = os.waitstatus_to_exitcode(status)
        stdout.seek(0)
        stderr.seek(0)
        return {"wall_s": elapsed, "cpu_s": usage.ru_utime + usage.ru_stime,
                "peak_rss_kib": usage.ru_maxrss, "exit": child.returncode}, stdout.read(), stderr.read()


parser = argparse.ArgumentParser()
parser.add_argument("--bin", type=pathlib.Path, default=ROOT / ".lake/build/bin/mitos-gate")
parser.add_argument("--output", required=True, type=pathlib.Path)
parser.add_argument("--runs", default=5, type=int)
parser.add_argument("--family", action="append")
args = parser.parse_args()
assert args.runs >= 5
binary = args.bin.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
load_before = os.getloadavg()
refusals = {
    "compact-65535": ": refused: 32766 structural characters exceeds 2048",
    "compact-over-budget": ": refused: 2049 structural characters exceeds 2048",
    "wide-map-over-budget": ": refused: 7405 structural characters exceeds 2048",
    "mixed-at-budget": ": refused at a" + "[0]" * 1023 + ": unsupported flow collection",
    "explicit-at-budget": ": refused at <root>: complex or explicit key",
    "malformed-at-budget": ": refused: parse: unterminated single-quoted scalar at line 2",
}
records = []
for name, source, status, expected in workloads():
    if args.family and name not in args.family:
        continue
    file = output / (name + ".yml")
    file.write_text(source)
    if name != "ci":
        assert len(source.encode()) == (65535 if name == "compact-65535" else CAP)
    dump = subprocess.run([str(binary), "workflow", "leaves", str(file)], capture_output=True, timeout=30)
    assert dump.returncode == status and b"PANIC" not in dump.stderr, (name, dump)
    if status == 0:
        assert not dump.stderr, (name, dump.stderr)
        expected = oracle(source) if expected is None else expected
        actual = [json.loads(line) for line in dump.stdout.splitlines()]
        assert actual == expected, (name, "leaf mismatch")
    else:
        assert not dump.stdout and dump.stderr.decode() == str(file) + refusals[name] + "\n", (name, dump)
    records.append({"name": name, "bytes": len(source.encode()),
                    "structure_chars": sum(source.count(c) for c in "-?:,[{"),
                    "sha256": hashlib.sha256(source.encode()).hexdigest(),
                    "expected_exit": status, "leaves": len(expected) if expected is not None else None,
                    "diagnostic": dump.stderr.decode().replace(str(file), "<input>").strip(), "runs": []})
    print(json.dumps({"qualified": name, "exit": status}), flush=True)
assert records and (not args.family or {r["name"] for r in records} == set(args.family)), args.family
for trial in range(args.runs):
    for record in records if trial % 2 == 0 else reversed(records):
        file = output / (record["name"] + ".yml")
        run, stdout, stderr = measured([str(binary), "workflow", "parse", str(file)])
        assert run["exit"] == record["expected_exit"] and not stdout and b"PANIC" not in stderr, record["name"]
        assert stderr.decode().replace(str(file), "<input>").strip() == record["diagnostic"], record["name"]
        record["runs"].append(run)
    print(json.dumps({"completed_trial": trial + 1}), flush=True)
for record in records:
    record["wall_s"] = {"median": statistics.median(r["wall_s"] for r in record["runs"]),
                        "min": min(r["wall_s"] for r in record["runs"]),
                        "max": max(r["wall_s"] for r in record["runs"])}
result = {"command": "mitos-gate workflow parse <input>", "runs_per_family": args.runs,
          "failures": 0, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
          "reader_sha256": hashlib.sha256((ROOT / "gate/MitosGate/Yaml.lean").read_bytes()).hexdigest(),
          "runner_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
          "PyYAML": yaml.__version__, "logical_cpus": os.cpu_count(),
          "load_before": load_before, "load_after": os.getloadavg(),
          "cpu_max": pathlib.Path("/sys/fs/cgroup/cpu.max").read_text().strip(),
          "memory_max": pathlib.Path("/sys/fs/cgroup/memory.max").read_text().strip(), "families": records}
(output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"slowest": max(records, key=lambda r: r["wall_s"]["median"])["name"],
                  "results": str(output / "results.json")}), flush=True)
