import argparse
import collections
import json
import pathlib
import random
import subprocess
import tempfile

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ["ci", "clear-needs-rebase", "land-protection", "land", "nightly", "owner-ping", "update-prs"]


def leaves(node, path=()):
    if isinstance(node, yaml.ScalarNode):
        return [{"path": list(path), "value": node.value}]
    if isinstance(node, yaml.SequenceNode):
        return [leaf for i, child in enumerate(node.value) for leaf in leaves(child, (*path, i))] if node.value else [
            {"path": list(path), "value": []}]
    if isinstance(node, yaml.MappingNode):
        return [leaf for key, child in node.value for leaf in leaves(child, (*path, key.value))] if node.value else [
            {"path": list(path), "value": {}}]
    raise AssertionError(node)


def mutations(seed):
    rng = random.Random(seed)
    bases = [(ROOT / f".github/workflows/{name}.yml").read_text() for name in WORKFLOWS]
    bases.append("name: test\njobs:\n  test:\n    steps:\n      - run: echo ${{ needs.a.outputs.x }}\n")
    kinds = list(range(28)) * 25
    rng.shuffle(kinds)
    for i, kind in enumerate(kinds):
        key = f"mutation_{i}"
        word = "".join(rng.choices("abcdefABCDEF012345", k=8))
        expression = "${{ needs." + word + ".outputs.x }}"
        suffixes = [
            f"{key}: {word}\n",
            f'{key}: "\\x6e{word}"\n',
            f'{key}: "\\x24{{{{ needs.a.outputs.x }}}}"\n',
            f'{key}: "${{{{ \\x6eeeds.a.outputs.x }}}}"\n',
            f"{key}: |-\n  {word}\n  {expression}\n",
            f"{key}: |2\n  {word}\n",
            f"{key}: [{word}, 'two', \"three\"]\n",
            f"{key}: {{a: {word}}}\n",
            f"{key}: {word}\n{key.upper()}: duplicate\n",
            f"? {key}\n: {word}\n",
            f"{key}: {word}\n---\nother: value\n",
            f"# {expression}\n{key}: {word}\n",
            f"{key}: {word}\r\n",
            f"'{key}': {word}\n",
            f"{key}: !foo.bar {word}\n",
            f"{key}: &anchor_{i} {word}\n",
            f"{key}: *missing_{i}\n",
            f"? [{word}, x]\n: value\n",
            f"{key}: |++\n  {word}\n",
            f"{key}: >+\n\n",
            f'{key}: "\\t{word}"\n',
            f"{key}: [?{word}, y]\n",
            f"{key}: ['?{word}', y]\n",
            f"{key}: [[{word}]]\n",
            f"{key}: >-\n  {word}\n  next\n",
            f"{key}: plain\n  continued {word}\n",
            f'{key}: "line\n  continued {word}"\n',
            f"{key}: {word}#hash\n",
        ]
        yield f"mutant-{i:03d}-kind-{kind}", rng.choice(bases) + suffixes[kind]


def compare(binary, source, file, name):
    file.write_bytes(source.encode())
    result = subprocess.run([str(binary), "workflow", "leaves", str(file)], capture_output=True,
                            text=True, timeout=20)
    assert "PANIC" not in result.stderr, (name, result.stderr)
    assert result.returncode in [0, 1], (name, result.returncode, result.stderr)
    if result.returncode:
        assert not result.stdout and result.stderr, (name, result)
        return None
    assert not result.stderr, (name, result.stderr)
    try:
        node = yaml.compose(source)
    except yaml.YAMLError as error:
        raise AssertionError((name, "accepted invalid YAML", str(error), source)) from error
    assert isinstance(node, yaml.MappingNode), (name, "accepted non-mapping", source)
    expected = leaves(node)
    actual = [json.loads(line) for line in result.stdout.splitlines()]
    assert actual == expected, (name, "leaf drift", actual, expected, source)
    return len(actual)


parser = argparse.ArgumentParser()
parser.add_argument("--bin", type=pathlib.Path, default=ROOT / ".lake/build/bin/mitos-gate")
parser.add_argument("--seed", type=int, default=354405)
parser.add_argument("--extra", type=pathlib.Path, action="append", default=[])
args = parser.parse_args()
counts = collections.Counter()
with tempfile.TemporaryDirectory(prefix="workflow-differential-") as tmp:
    file = pathlib.Path(tmp) / "input.yml"
    for name in WORKFLOWS:
        source = (ROOT / f".github/workflows/{name}.yml").read_text()
        count = compare(args.bin, source, file, name)
        assert count is not None, (name, "live workflow refused")
        print(f"{name}.yml leaves={count} PyYAML-equal")
    for extra in args.extra:
        count = compare(args.bin, extra.read_text(), file, extra.name)
        assert count is not None, (extra, "extra workflow refused")
        print(f"{extra.name} leaves={count} PyYAML-equal")
    for name, source in mutations(args.seed):
        count = compare(args.bin, source, file, name)
        counts["accepted" if count is not None else "refused"] += 1
assert sum(counts.values()) == 700, counts
print(json.dumps({"seed": args.seed, "mutants": 700, "PyYAML": yaml.__version__, **counts}, sort_keys=True))
