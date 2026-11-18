#!/usr/bin/env python3
import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


@dataclass(frozen=True)
class Suite:
    path: str
    digest: str


def inventory(root):
    suites = []
    for file in sorted((root / "gate").glob("*-test.sh"), key=lambda p: os.fsencode(p.name)):
        if file.is_symlink() or not file.is_file() or not os.access(file, os.X_OK):
            raise ValueError(f"not an executable regular suite: {file.name}")
        suites.append(Suite(file.relative_to(root).as_posix(), hashlib.sha256(file.read_bytes()).hexdigest()))
    if not suites:
        raise ValueError("the suite inventory is empty")
    return tuple(suites)


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE).decode().strip()


def identity(root):
    run = os.environ.get("GITHUB_RUN_ID", "")
    if not re.fullmatch(r"[1-9][0-9]*", run):
        raise ValueError("GITHUB_RUN_ID is not a positive decimal run id")
    commit, tree = git(root, "rev-parse", "HEAD"), git(root, "rev-parse", "HEAD^{tree}")
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (commit, tree)):
        raise ValueError("the checkout has no supported commit/tree identity")
    return {"run": run, "commit": commit, "tree": tree}


def pristine(root, suites):
    for suite in suites:
        if git(root, "ls-tree", "HEAD", "--", suite.path).partition(" ")[0] != "100755":
            raise ValueError(f"suite is not executable in the checkout: {suite.path}")
        content = subprocess.check_output(["git", "-C", str(root), "show", f"HEAD:{suite.path}"], stderr=subprocess.PIPE)
        if hashlib.sha256(content).hexdigest() != suite.digest:
            raise ValueError(f"suite differs from the checkout: {suite.path}")


def shard(value):
    if not re.fullmatch(r"[0-9]+/[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("expected k/n, with 0 <= k < n")
    index, count = map(int, value.split("/"))
    if index >= count:
        raise argparse.ArgumentTypeError("expected k/n, with 0 <= k < n")
    return index, count


def selected(suites, index, count):
    return tuple(s for position, s in enumerate(suites) if position % count == index)


def run(root, division, output):
    source, suites = identity(root), inventory(root)
    pristine(root, suites)
    temp = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    if not output.resolve().is_relative_to(temp) or output.resolve() == temp:
        raise ValueError("output must be a fresh directory under RUNNER_TEMP")
    output.mkdir(parents=True, exist_ok=False)
    index, count = division
    results = []
    for position, suite in enumerate(selected(suites, index, count)):
        if inventory(root) != suites:
            raise ValueError("suite inventory/content changed during execution")
        log = f"{position:03d}.log"
        print(f"== {suite.path}", flush=True)
        with (output / log).open("wb") as saved:
            try:
                with subprocess.Popen([str(root / suite.path)], cwd=root,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
                    while chunk := process.stdout.read1(65536):
                        saved.write(chunk)
                        sys.stdout.buffer.write(chunk)
                        sys.stdout.buffer.flush()
                    status = process.wait()
            except OSError as error:
                saved.write(f"could not start: {error}\n".encode())
                status = 127
        results.append({"path": suite.path, "digest": suite.digest, "exit": status, "log": log})
    if inventory(root) != suites or identity(root) != source:
        raise ValueError("checkout/suite inventory/content changed during execution")
    record = {"version": 1, **source, "index": index, "count": count, "results": results}
    pending = output / "record.tmp"
    pending.write_text(json.dumps(record, separators=(",", ":")) + "\n")
    pending.rename(output / "record.json")
    failures = [row["path"] for row in results if row["exit"] != 0]
    if failures:
        print("gate-tests: failed: " + ", ".join(failures), file=sys.stderr)
    return int(bool(failures))


def object_once(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def fields(value, keys):
    if type(value) is not dict or set(value) != set(keys.split()):
        raise ValueError("unexpected record fields")


def regular(file):
    if file.is_symlink() or not file.is_file():
        raise ValueError(f"missing or non-regular evidence: {file.name}")


def verify(root, job, count, directories):
    if job != "success":
        raise ValueError(f"gate-tests job result is {job!r}, not success")
    if count <= 0 or len(directories) != count or len(set(directories)) != count:
        raise ValueError("expected exactly one directory per shard")
    parent = directories[0].parent
    if any(d.parent != parent for d in directories) or parent.is_symlink():
        raise ValueError("shard directories must share one regular parent")
    if {p.name for p in parent.iterdir()} != {f"gate-tests-{i}" for i in range(count)}:
        raise ValueError("missing or extra shard directory")
    source, suites = identity(root), inventory(root)
    pristine(root, suites)
    seen, combined = set(), []
    for directory in directories:
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("not a regular shard directory")
        regular(directory / "record.json")
        record = json.loads((directory / "record.json").read_text(), object_pairs_hook=object_once)
        fields(record, "version run commit tree index count results")
        if type(record["version"]) is not int or record["version"] != 1:
            raise ValueError("unsupported record version")
        if any(record[key] != value for key, value in source.items()):
            raise ValueError("record has a different run/checkout")
        index = record["index"]
        if (type(index) is not int or not 0 <= index < count or index in seen or
                type(record["count"]) is not int or record["count"] != count or
                directory.name != f"gate-tests-{index}"):
            raise ValueError("invalid or duplicate shard identity")
        seen.add(index)
        expected = selected(suites, index, count)
        rows = record["results"]
        if type(rows) is not list or len(rows) != len(expected):
            raise ValueError("incomplete shard results")
        logs = {"record.json"}
        for position, (row, suite) in enumerate(zip(rows, expected)):
            fields(row, "path digest exit log")
            log = f"{position:03d}.log"
            if (row["path"] != suite.path or row["digest"] != suite.digest or
                    type(row["exit"]) is not int or row["exit"] != 0 or row["log"] != log):
                raise ValueError("wrong suite, content, exit status or log")
            regular(directory / log)
            logs.add(log)
            combined.append(row["path"])
        if {p.name for p in directory.iterdir()} != logs:
            raise ValueError("extra or incomplete shard evidence")
    if seen != set(range(count)) or Counter(combined) != Counter(s.path for s in suites):
        raise ValueError("suite union is incomplete or duplicated")
    print(f"gate-tests: verified {len(combined)} suites across {count} shards")
    return 0


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    execute = commands.add_parser("run")
    execute.add_argument("--shard", type=shard, required=True)
    execute.add_argument("--out", type=Path, required=True)
    receive = commands.add_parser("verify")
    receive.add_argument("--job", required=True)
    receive.add_argument("--shards", type=int, required=True)
    receive.add_argument("directories", type=Path, nargs="+")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        if args.command == "run":
            return run(root, args.shard, args.out)
        return verify(root, args.job, args.shards, args.directories)
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"gate-tests: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
