import argparse
import itertools
import json
import pathlib
import shutil
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("workflow-diff: missing PyYAML", file=sys.stderr)
    sys.exit(2)


ROOT = pathlib.Path(__file__).resolve().parent.parent


class OutsideSubset(ValueError):
    pass


def safe_json(value):
    return json.dumps(value, ensure_ascii=True).replace("::", "\\u003a\\u003a").replace("##[", "\\u0023\\u0023[")


def pyyaml_leaves(file):
    with file.open(encoding="utf-8") as stream:
        events = list(yaml.parse(stream, Loader=yaml.SafeLoader))
    for event in events:
        if isinstance(event, yaml.AliasEvent) or getattr(event, "anchor", None) is not None or getattr(event, "tag", None) is not None:
            raise OutsideSubset("outside the subset: anchor, alias or tag")
    events = iter(events)

    def expect(kind):
        if not isinstance(next(events), kind):
            raise OutsideSubset("outside the subset: expected one document")

    def node(event, path):
        if isinstance(event, yaml.ScalarEvent):
            return [{"path": path, "value": event.value}]
        if isinstance(event, yaml.SequenceStartEvent):
            result = []
            index = 0
            while not isinstance(child := next(events), yaml.SequenceEndEvent):
                result.extend(node(child, [*path, index]))
                index += 1
            return result or [{"path": path, "value": []}]
        if isinstance(event, yaml.MappingStartEvent):
            result = []
            while not isinstance(key := next(events), yaml.MappingEndEvent):
                if not isinstance(key, yaml.ScalarEvent):
                    raise OutsideSubset("outside the subset: non-scalar key")
                result.extend(node(next(events), [*path, key.value]))
            return result or [{"path": path, "value": {}}]
        raise OutsideSubset("outside the subset: expected a node")

    expect(yaml.StreamStartEvent)
    expect(yaml.DocumentStartEvent)
    leaves = node(next(events), [])
    expect(yaml.DocumentEndEvent)
    expect(yaml.StreamEndEvent)
    return leaves


def gate_leaves(text):
    leaves = [json.loads(line) for line in text.splitlines()]
    for leaf in leaves:
        if not isinstance(leaf, dict) or set(leaf) != {"path", "value"}:
            raise ValueError("invalid leaf object")
        path, value = leaf["path"], leaf["value"]
        if not isinstance(path, list) or any(type(seg) not in (str, int) for seg in path):
            raise ValueError("invalid leaf path")
        if not (isinstance(value, str) or type(value) is dict and not value or type(value) is list and not value):
            raise ValueError("invalid leaf value")
    return leaves


def compare_file(gate, file):
    label = safe_json(file.name)[1:-1]

    def run(verb):
        result = subprocess.run([gate, "workflow", verb, str(file)], capture_output=True, text=True, timeout=30)
        if "PANIC" in result.stderr or verb == "parse" and "PANIC" in result.stdout:
            raise ValueError("gate PANIC")
        return result

    parsed = run("parse")
    if parsed.returncode:
        raise ValueError(f"parse exited {parsed.returncode}; stdout={safe_json(parsed.stdout)}; stderr={safe_json(parsed.stderr)}")
    if parsed.stdout or parsed.stderr:
        raise ValueError("unexpected output from successful parse")
    result = run("leaves")
    if result.returncode or result.stderr:
        raise ValueError(f"leaves exited {result.returncode}; stderr={safe_json(result.stderr)}")
    actual = gate_leaves(result.stdout)
    expected = pyyaml_leaves(file)
    for index, (got, want) in enumerate(itertools.zip_longest(actual, expected)):
        if got != want:
            raise ValueError(f"leaf {index}: gate={safe_json(got)}; PyYAML={safe_json(want)}")
    print(f"workflow-diff: {label}: {len(actual)} leaves; PyYAML equal")
    return "compared"


def differential(args):
    print(f"workflow-diff: PyYAML {yaml.__version__}", flush=True)
    gate = shutil.which(args.gate)
    if gate is None:
        print(f"workflow-diff: missing gate binary {safe_json(args.gate)}", file=sys.stderr)
        return 2
    files = [pathlib.Path(file) for file in args.files] if args.files else sorted(
        (ROOT / ".github/workflows").glob("*.yml")) + sorted((ROOT / ".github/workflows").glob("*.yaml"))
    if not files:
        print("workflow-diff: no workflows found", file=sys.stderr)
        return 1
    counts = {"compared": 0, "differences": 0}
    for file in files:
        try:
            counts[compare_file(gate, file)] += 1
        except (OSError, ValueError, yaml.YAMLError, StopIteration, RecursionError, subprocess.SubprocessError) as error:
            print(f"workflow-diff: {safe_json(file.name)}: {safe_json(str(error))}", file=sys.stderr)
            counts["differences"] += 1
    print(f"workflow-diff: {counts['compared']} files compared, {counts['differences']} differences")
    return int(counts["differences"] != 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--diff", action="store_true")
    parser.add_argument("--gate", default=str(ROOT / ".lake/build/bin/mitos-gate"))
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()
    if args.diff:
        return differential(args)
    if len(args.files) != 1:
        parser.error("expected one FILE")
    try:
        leaves = pyyaml_leaves(pathlib.Path(args.files[0]))
    except OutsideSubset as error:
        print(str(error), file=sys.stderr)
        return 3
    except (OSError, yaml.YAMLError, StopIteration, RecursionError) as error:
        print(safe_json(str(error)), file=sys.stderr)
        return 1
    for leaf in leaves:
        print(json.dumps(leaf, ensure_ascii=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
