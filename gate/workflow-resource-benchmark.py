import argparse
import hashlib
import json
import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
import time

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


def filled(prefix, suffix):
    gap = CAP - len((prefix + suffix).encode())
    assert gap > 0
    source = prefix + "x" * gap + suffix
    assert len(source.encode()) == CAP
    return source


def source_work(source):
    return sum(i for i, byte in enumerate(source.encode(), 1) if byte == 10)


def work_refusal(source):
    return f": refused: cumulative line-prefix bytes {source_work(source)} exceeds 16777216"


def last_admitted(make):
    low, high = 2, 10000
    while low + 1 < high:
        mid = (low + high) // 2
        if source_work(make(mid)) <= 16777216:
            low = mid
        else:
            high = mid
    assert source_work(make(low)) <= 16777216 < source_work(make(high))
    return low


def workloads():
    yield "compact-65535", "a:\n" + "- " * 32765 + "x\n", 1, None
    yield "compact-at-budget", padded("a:\n" + "- " * 2047 + "x\n"), 0, [
        {"path": ["a"] + [0] * 2047, "value": "x"}]
    yield "compact-over-budget", padded("a:\n" + "- " * 2048 + "x\n"), 1, None
    yield "mixed-at-budget", padded("a:\n" + "- " * 1023 + "[" * 1024 + "x" + "]" * 1024), 1, None
    yield "explicit-at-budget", padded("a:\n" + "? " * 2047 + "x\n"), 1, None
    yield "malformed-at-budget", padded("a:\n" + "- " * 2047 + "'"), 1, None
    for name, source in [
        ("wide-map-late", padded("".join(f"k{i:04}: x\n" for i in range(2048)))),
        ("wide-map-long-keys", padded("".join(f"{'k' * 20}{i:04}: x\n" for i in range(2048)))),
    ]:
        yield name, source, 1, work_refusal(source)
    yield "wide-map-over-budget", padded("".join(f"k{i}: x\n" for i in range(7405))), 1, None
    yield "flat-flow-at-budget", padded("a: [" + ",".join(["x"] * 2047) + "]\n"), 0, None
    source = padded("".join(f"k{i:04}: |\n  x\n" for i in range(2048)))
    yield "block-scalars-late", source, 1, work_refusal(source)
    yield "deep-mapping", padded("".join(" " * i + "k:\n" for i in range(250)) + " " * 250 + "x\n"), 0, [
        {"path": ["k"] * 250, "value": "x"}]
    yield "plain-scalar", "a: " + "x" * (CAP - 3), 0, None
    yield "quoted-scalar", 'a: "' + "x" * (CAP - 6) + '"\n', 0, None
    yield "quoted-punctuation", padded('a: "' + "-?:," * 511 + "---" + '"\n'), 0, None
    yield "quoted-openers", padded('a: "' + "[" * 1024 + '"\n'), 0, None
    for name, source in [
        ("blank-lines", "\n" * (CAP - 5) + "a: x\n"),
        ("comment-lines", padded("#\n" * 32764 + "a: x\n")),
        ("multiline-plain", padded("a: x\n" + "  x\n" * 16000)),
        ("multiline-quoted", padded('a: "x\n' + "  x\n" * 16000 + '  x"\n')),
        ("multiline-quoted-min-indent", padded('a: "x\n' + " x\n" * 21840 + ' x"\n')),
        ("folded-scalar", padded("a: >\n" + "  x\n" * 16000)),
        ("root-plain-historic", "x\n" * 32768),
        ("root-double-historic", '"' + "x\n" * 32766 + 'x"\n'),
        ("root-single-historic", "'" + "x\n" * 32766 + "x'\n"),
        ("document-ends-historic", "...\n" * 16384),
        ("compact-ends-historic", padded("a:\n" + "- " * 2047 + "x\n" + "...\n" * 15000)),
    ]:
        yield name, source, 1, work_refusal(source)
    builders = {
        "double": lambda n: filled('a: "', "\n" + " x\n" * (n - 2) + ' x"\n'),
        "single": lambda n: filled("a: '", "\n" + " x\n" * (n - 2) + " x'\n"),
        "plain": lambda n: filled("a: ", "\n" + " x\n" * (n - 1)),
        "plain-two-space": lambda n: filled("a: ", "\n" + "  x\n" * (n - 1)),
        "literal": lambda n: filled("a: |\n  ", "\n" + "  x\n" * (n - 2)),
        "folded": lambda n: filled("a: >\n  ", "\n" + "  x\n" * (n - 2)),
        "escaped-double": lambda n: filled('a: "', "\\\n" + " x\\\n" * (n - 2) + ' x"\n'),
        "blank-double": lambda n: filled('a: "', "\n" * (n - 1) + ' x"\n'),
    }
    for style, make in builders.items():
        frontier = last_admitted(make)
        for count in [frontier - 1, frontier, frontier + 1]:
            source = make(count)
            status = 0 if count <= frontier else 1
            yield f"frontier-{style}-{count}", source, status, None if status == 0 else work_refusal(source)
    for style, quote in [("plain", ""), ("single", "'"), ("double", '"')]:
        def make(n):
            suffix = "\n" + "x\n" * (n - 1) if not quote else "\n" + "x\n" * (n - 2) + "x" + quote + "\n"
            return filled(quote, suffix)
        frontier = last_admitted(make)
        for count in [frontier, frontier + 1]:
            source = make(count)
            expected = ": refused: root is not a mapping" if count == frontier else work_refusal(source)
            yield f"frontier-root-{style}-{count}", source, 1, expected
        def make_short(n):
            return quote + "x\n" * (n - 1) + "x" + quote + "\n"
        frontier = last_admitted(make_short)
        for count in [frontier, frontier + 1]:
            source = make_short(count)
            expected = ": refused: root is not a mapping" if count == frontier else work_refusal(source)
            yield f"frontier-root-short-{style}-{count}", source, 1, expected
    for style, make in [
        ("plain", lambda n: "a: x\n" + " x\n" * (n - 1)),
        ("single", lambda n: "a: 'x\n" + " x\n" * (n - 2) + " x'\n"),
        ("double", lambda n: 'a: "x\n' + " x\n" * (n - 2) + ' x"\n'),
        ("escaped", lambda n: 'a: "x\\\n' + " x\\\n" * (n - 2) + ' x"\n'),
    ]:
        frontier = last_admitted(make)
        for count in [frontier, frontier + 1]:
            source = make(count)
            yield f"frontier-dense-{style}-{count}", source, int(count > frontier), work_refusal(source) if count > frontier else None
    for delta in [-1, 0, 1]:
        source = "a: x\n" + "\n" * 5786 + "#" + "x" * (697 + delta) + "\n"
        assert source_work(source) == 16777216 + delta
        yield f"frontier-exact-{delta}", source, int(delta > 0), work_refusal(source) if delta > 0 else None
    for count in [5792, 5793]:
        source = "\n" * count
        expected = ": refused: expected one document, found 0" if count == 5792 else work_refusal(source)
        yield f"frontier-blanks-{count}", source, 1, expected
    for values in [2, 16]:
        def make(n):
            lines = [n // values + (i < n % values) for i in range(values)]
            content = "".join(f"k{i}: " + "x" * ((CAP - 2000) // values) + "\n" + " x\n" * (lines[i] - 1) for i in range(values))
            return content + "#" + "x" * (CAP - len(content.encode()) - 1)
        frontier = last_admitted(make)
        for count in [frontier, frontier + 1]:
            source = make(count)
            yield f"frontier-scalars-{values}-{count}", source, int(count > frontier), work_refusal(source) if count > frontier else None
    for padding in ["front", "middle", "back"]:
        def make(n):
            parts = ["a: x\n" + " x\n" * (n // 2 - 1), "b: x\n" + " x\n" * (n - n // 2 - 1)]
            gap = CAP - len("".join(parts).encode())
            comment = "#" + "x" * (gap - 2) + "\n"
            return comment + "".join(parts) if padding == "front" else (parts[0] + comment + parts[1] if padding == "middle" else "".join(parts) + comment)
        frontier = last_admitted(make)
        yield f"frontier-padding-{padding}", make(frontier), 0, None
    for label, make, expected in [
        ("document-ends", lambda n: "...\n" * n, ": refused: expected one document, found 0"),
        ("compact-ends", lambda n: "a:\n" + "- " * 2047 + "x\n" + "...\n" * n,
         [{"path": ["a"] + [0] * 2047, "value": "x"}]),
    ]:
        frontier = last_admitted(make)
        for count in [frontier, frontier + 1]:
            source = make(count)
            above = count > frontier
            yield f"frontier-{label}-{count}", source, 1 if above or isinstance(expected, str) else 0, work_refusal(source) if above else expected
    malformed = builders["single"](last_admitted(builders["single"]))[:-2]
    yield "frontier-malformed-single", malformed, 1, ": refused: parse: unterminated single-quoted scalar at line 0"
    yield "short-many-lines", "a: x\n" + "\n" * 1024, 0, None
    yield "ci", (ROOT / ".github/workflows/ci.yml").read_text(), 0, None


def measure_child(command):
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


if sys.argv[1:2] == ["--measure-child"]:
    sample, stdout, stderr = measure_child(sys.argv[2:])
    print(json.dumps([sample, stdout.hex(), stderr.hex()]))
    raise SystemExit


import yaml


def measured(command):
    helper = subprocess.run([sys.executable, str(pathlib.Path(__file__).resolve()), "--measure-child", *command],
                            capture_output=True, check=True, timeout=35)
    sample, stdout, stderr = json.loads(helper.stdout)
    return sample, bytes.fromhex(stdout), bytes.fromhex(stderr)


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
    assert len(source.encode()) <= CAP
    dump = subprocess.run([str(binary), "workflow", "leaves", str(file)], capture_output=True, timeout=30)
    assert dump.returncode == status and b"PANIC" not in dump.stderr, (name, dump)
    if status == 0:
        assert not dump.stderr, (name, dump.stderr)
        expected = oracle(source) if expected is None else expected
        actual = [json.loads(line) for line in dump.stdout.splitlines()]
        assert actual == expected, (name, "leaf mismatch")
    else:
        diagnostic = expected if isinstance(expected, str) else refusals[name]
        assert not dump.stdout and dump.stderr.decode() == str(file) + diagnostic + "\n", (name, dump)
    records.append({"name": name, "bytes": len(source.encode()),
                    "LF": source.count("\n"),
                    "line_prefix_bytes": source_work(source),
                    "passes_work_admission": source_work(source) <= 16777216,
                    "structure_chars": sum(source.count(c) for c in "-?:,[{"),
                    "sha256": hashlib.sha256(source.encode()).hexdigest(),
                    "expected_exit": status, "leaves": len(expected) if status == 0 else None,
                    "qualified_leaves_sha256": hashlib.sha256(dump.stdout).hexdigest() if status == 0 else None,
                    "scalar_frontier_gate": name.startswith("frontier-"),
                    "diagnostic": dump.stderr.decode().replace(str(file), "<input>").strip(), "runs": []})
    print(json.dumps({"qualified": name, "exit": status}), flush=True)
assert records and (not args.family or {r["name"] for r in records} == set(args.family)), args.family
result = {"command": "mitos-gate workflow parse <input>", "runs_per_family": args.runs,
          "measurement": "fresh standard-library Python helper exec; wait4 of native child; helper startup and leaf qualification excluded",
          "python": sys.version,
          "host": {field: getattr(os.uname(), field) for field in ["sysname", "release", "version", "machine"]},
          "cpu_model": next(line.split(":", 1)[1].strip() for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")),
          "failures": 0, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
          "reader_sha256": hashlib.sha256((ROOT / "gate/MitosGate/Yaml.lean").read_bytes()).hexdigest(),
          "runner_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
          "PyYAML": yaml.__version__, "logical_cpus": os.cpu_count(),
          "load_before": load_before, "cpu_max": pathlib.Path("/sys/fs/cgroup/cpu.max").read_text().strip(),
          "memory_max": pathlib.Path("/sys/fs/cgroup/memory.max").read_text().strip(),
          "scalar_frontier_limits": {"child_cpu_s": 2, "peak_rss_kib": 262144},
          "qualification_pass": False, "families": records}


def save():
    for record in records:
        if record["runs"]:
            for field in ["wall_s", "cpu_s", "peak_rss_kib"]:
                samples = [r[field] for r in record["runs"]]
                record[field] = {"median": statistics.median(samples), "min": min(samples), "max": max(samples)}
    result["load_after"] = os.getloadavg()
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")


for trial in range(args.runs):
    for record in records if trial % 2 == 0 else reversed(records):
        file = output / (record["name"] + ".yml")
        run, stdout, stderr = measured([str(binary), "workflow", "parse", str(file)])
        assert run["exit"] == record["expected_exit"] and not stdout and b"PANIC" not in stderr, record["name"]
        assert stderr.decode().replace(str(file), "<input>").strip() == record["diagnostic"], record["name"]
        record["runs"].append(run)
        if record["scalar_frontier_gate"] and (run["cpu_s"] > 2 or run["peak_rss_kib"] > 262144):
            result["gate_failure"] = {"family": record["name"], "trial": trial + 1, **run}
            result["failures"] += 1
            save()
            raise SystemExit(f"scalar frontier gate failed: {result['gate_failure']}")
    print(json.dumps({"completed_trial": trial + 1}), flush=True)
result["qualification_pass"] = True
save()
print(json.dumps({"slowest": max(records, key=lambda r: r["wall_s"]["median"])["name"],
                  "results": str(output / "results.json")}), flush=True)
