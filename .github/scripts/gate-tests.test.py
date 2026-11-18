#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / ".github/scripts/gate-tests.py"
WORKFLOW = (ROOT / ".github/workflows/ci.yml").read_text()


class Fixture:
    def __init__(self, count=7, first=None):
        self.temp = tempfile.TemporaryDirectory(prefix="gate-suite-fixture-")
        self.base = Path(self.temp.name)
        self.root = self.base / "repo"
        self.output = self.base / "bundles"
        scripts = self.root / ".github/scripts"
        scripts.mkdir(parents=True)
        (self.root / "gate").mkdir()
        self.helper = scripts / "gate-tests.py"
        shutil.copyfile(HELPER, self.helper)
        self.names = [f"gate/{i:02d}{' space' if i == 1 else ''}-test.sh" for i in range(count)]
        for i, name in enumerate(self.names):
            body = f'#!/bin/sh\nprintf "%s\\n" "{name}" >> "$MARKER"\nprintf "ran {i}\\n"\n'
            if i == 0 and first is not None:
                body = first
            (self.root / name).write_text(body)
            (self.root / name).chmod(0o755)
        self.env = {**os.environ, "GITHUB_RUN_ID": "12345", "RUNNER_TEMP": str(self.base),
                    "MARKER": str(self.base / "markers")}
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "fixture")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def cli(self, *args, env=None):
        return subprocess.run([sys.executable, "-I", str(self.helper), *map(str, args)],
                              cwd=self.root, env=env or self.env, capture_output=True, text=True, timeout=20)

    def execute(self, index):
        return self.cli("run", "--shard", f"{index}/3", "--out", self.output / f"gate-tests-{index}")

    def all(self):
        for index in range(3):
            result = self.execute(index)
            if result.returncode:
                raise AssertionError(result.stderr + result.stdout)

    def verify(self, status="success", parent=None, env=None):
        return self.cli("verify", "--job", status, "--shards", "3",
                        *[(parent or self.output) / f"gate-tests-{i}" for i in range(3)], env=env)

    def close(self):
        self.temp.cleanup()


class GateTests(unittest.TestCase):
    def fixture(self, *args, **kwargs):
        fixture = Fixture(*args, **kwargs)
        self.addCleanup(fixture.close)
        return fixture

    def good(self, result):
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def bad(self, result, reason=None):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("gate-tests: verified", result.stdout)
        if reason:
            self.assertIn(reason, result.stderr)

    def test_complete_current_and_changed_inventories(self):
        for count in (1, 2, 4, 7, 27, 28):
            with self.subTest(count=count):
                f = self.fixture(count)
                f.all()
                self.good(f.verify())
                actual = (f.base / "markers").read_text().splitlines()
                self.assertCountEqual(actual, f.names)
                for index in range(3):
                    record = json.loads((f.output / f"gate-tests-{index}/record.json").read_text())
                    self.assertEqual([r["path"] for r in record["results"]], f.names[index::3])
        f = self.fixture(4)
        (f.root / f.names[0]).unlink()
        (f.root / "gate/00-added-test.sh").write_text('#!/bin/sh\nprintf "%s\\n" gate/00-added-test.sh >> "$MARKER"\n')
        (f.root / "gate/00-added-test.sh").chmod(0o755)
        f.git("add", ".")
        f.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "replace suite")
        f.all()
        self.good(f.verify())
        self.assertCountEqual((f.base / "markers").read_text().splitlines(),
                              ["gate/00-added-test.sh", *f.names[1:]])

    def test_empty_dirty_and_nonexecutable_sources_refuse(self):
        self.bad(self.fixture(0).execute(0), "inventory is empty")
        for mutation in ("dirty", "unexecutable", "symlink", "untracked", "deleted"):
            with self.subTest(mutation=mutation):
                f = self.fixture()
                file = f.root / f.names[0]
                if mutation == "dirty":
                    file.write_text(file.read_text() + "echo changed\n")
                elif mutation == "unexecutable":
                    file.chmod(0o644)
                elif mutation == "symlink":
                    file.unlink()
                    file.symlink_to(f.root / f.names[1])
                elif mutation == "deleted":
                    file.unlink()
                else:
                    (f.root / "gate/new-test.sh").write_text("#!/bin/sh\ntrue\n")
                    (f.root / "gate/new-test.sh").chmod(0o755)
                self.bad(f.execute(0))

    def test_hidden_files_match_original_bash_glob(self):
        f = self.fixture()
        hidden = f.root / "gate/.hidden-test.sh"
        hidden.write_text("#!/bin/sh\nexit 99\n")
        hidden.chmod(0o755)
        f.git("add", ".")
        f.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
              "commit", "-qm", "hidden file")
        oracle = subprocess.run(["bash", "-c", 'printf "%s\\n" gate/*-test.sh'], cwd=f.root,
                                env={**f.env, "LC_ALL": "C"}, capture_output=True, text=True, check=True)
        self.assertEqual(oracle.stdout.splitlines(), f.names)
        f.all()
        self.good(f.verify())
        self.assertCountEqual((f.base / "markers").read_text().splitlines(), f.names)

    def test_receiver_rejects_missing_tracked_source(self):
        f = self.fixture()
        f.all()
        self.good(f.verify())
        (f.root / f.names[-1]).unlink()
        self.bad(f.verify(), "inventory differs from Git HEAD")

    def test_failed_suite_still_runs_later_suites(self):
        for first, status in (("#!/bin/sh\nexit 9\n", 9), ("#!/not-a-real-interpreter\n", 127)):
            with self.subTest(status=status):
                f = self.fixture(first=first)
                self.bad(f.execute(0))
                record = json.loads((f.output / "gate-tests-0/record.json").read_text())
                self.assertEqual([r["exit"] for r in record["results"]], [status, 0, 0])
                self.assertEqual((f.base / "markers").read_text().splitlines(), [f.names[3], f.names[6]])

    def test_output_and_source_changes_refuse_completion(self):
        f = self.fixture()
        self.good(f.execute(0))
        self.bad(f.execute(0))
        self.bad(f.cli("run", "--shard", "0/3", "--out", f.root.parent.parent / "outside"))
        for division in ("3/3", "0/0", "-1/3", "a/3"):
            self.bad(f.cli("run", "--shard", division, "--out", f.base / "unused"))
        f = self.fixture(first='#!/bin/sh\nprintf "changed\\n" >> gate/03-test.sh\n')
        self.bad(f.execute(0), "changed during execution")
        self.assertFalse((f.output / "gate-tests-0/record.json").exists())

    def test_status_and_schema_mutations(self):
        f = self.fixture()
        f.all()
        for status in ("failure", "cancelled", "skipped", "timed_out", "", "unknown"):
            self.bad(f.verify(status), "not success")
        original = f.output / "gate-tests-0/record.json"
        content = original.read_text()
        changes = {
            "version": lambda r: r.update(version=2),
            "boolean-version": lambda r: r.update(version=True),
            "run": lambda r: r.update(run="6789"),
            "commit": lambda r: r.update(commit="0" * 40),
            "tree": lambda r: r.update(tree="0" * 40),
            "index": lambda r: r.update(index=1),
            "count": lambda r: r.update(count=4),
            "boolean-index": lambda r: r.update(index=False),
            "unknown": lambda r: r.update(extra="unknown"),
            "missing": lambda r: r.pop("tree"),
            "omitted-suite": lambda r: r["results"].pop(),
            "duplicated-suite": lambda r: r["results"].append(r["results"][0]),
            "wrong-suite": lambda r: r["results"][0].update(path=f.names[1]),
            "digest": lambda r: r["results"][0].update(digest="0" * 64),
            "nonzero": lambda r: r["results"][0].update(exit=1),
            "boolean-exit": lambda r: r["results"][0].update(exit=False),
            "float-exit": lambda r: r["results"][0].update(exit=0.0),
            "log-traversal": lambda r: r["results"][0].update(log="../outside"),
            "row-extra": lambda r: r["results"][0].update(extra=True),
            "reordered": lambda r: r["results"].reverse(),
        }
        for label, change in changes.items():
            with self.subTest(mutation=label):
                record = json.loads(content)
                change(record)
                original.write_text(json.dumps(record))
                self.bad(f.verify())
        for malformed in ("{", content.replace('"version":1', '"version":1,"version":1'), "[]"):
            original.write_text(malformed)
            self.bad(f.verify())
        original.write_text(content)
        self.good(f.verify(env={**f.env, "GITHUB_RUN_ATTEMPT": "2"}))

    def test_missing_extra_partial_and_symlink_evidence(self):
        for mutation in ("missing-log", "symlink-log", "missing-record", "partial", "extra-file",
                         "extra-shard", "missing-shard", "symlink-shard"):
            with self.subTest(mutation=mutation):
                f = self.fixture(4)
                f.all()
                shard = f.output / "gate-tests-0"
                if mutation in ("missing-log", "symlink-log"):
                    (shard / "000.log").unlink()
                    if mutation == "symlink-log":
                        (shard / "000.log").symlink_to(f.output / "gate-tests-1/000.log")
                elif mutation == "missing-record":
                    (shard / "record.json").unlink()
                elif mutation == "partial":
                    (shard / "record.json").rename(shard / "record.tmp")
                elif mutation == "extra-file":
                    (shard / "extra").touch()
                elif mutation == "extra-shard":
                    (f.output / "gate-tests-3").mkdir()
                elif mutation == "missing-shard":
                    shutil.rmtree(shard)
                else:
                    shutil.rmtree(shard)
                    shard.symlink_to(f.output / "gate-tests-1", target_is_directory=True)
                self.bad(f.verify())

    def test_shared_selector_omission_is_rejected_by_union(self):
        f = self.fixture()
        source = f.helper.read_text()
        source = source.replace("if position % count == index)",
                                "if position % count == index and position != len(suites) - 1)")
        self.assertNotEqual(source, f.helper.read_text())
        f.helper.write_text(source)
        f.all()
        self.bad(f.verify(), "union is incomplete")

    def test_real_workflow_composition(self):
        workflow = yaml.safe_load(WORKFLOW)
        prove = workflow["jobs"]["prove"]
        step = next(s for s in prove["steps"] if s.get("name", "").startswith("Cheat corpus is rejected"))
        self.assertEqual(step["env"], {"CHECKS": "${{ needs.checks.result }}",
                         "SHARDS": "${{ needs.cheat-shard.result }}",
                         "GATE_TESTS": "${{ needs.gate-tests.result }}"})
        f = self.fixture()
        f.all()
        shutil.copytree(f.output, f.root / "gate-test-logs")
        (f.root / "gate-bin").mkdir()
        (f.root / "gate-bin/mitos-gate").write_text(
            '#!/bin/sh\nprintf "%s\\n" "$*" > "$NATIVE_MARKER"\nmkdir merged\n')
        marker = f.base / "native-called"
        for status in ("failure", "cancelled", "skipped", "timed_out", "", "unknown", "success"):
            with self.subTest(status=status):
                result = subprocess.run(["bash", "-c", step["run"]], cwd=f.root,
                    env={**f.env, "CHECKS": "success", "SHARDS": "success", "GATE_TESTS": status,
                         "NATIVE_MARKER": str(marker)}, capture_output=True, text=True, timeout=20)
                if status == "success":
                    self.good(result)
                    self.assertTrue(marker.exists())
                    self.assertIn('--checks success --shards success --merged merged', marker.read_text())
                else:
                    self.bad(result)
                    self.assertFalse(marker.exists())
                    self.assertFalse((f.root / "merged").exists())
        marker.unlink()
        shutil.rmtree(f.root / "merged")
        (f.root / "gate-test-logs/gate-tests-0/record.json").unlink()
        result = subprocess.run(["bash", "-c", step["run"]], cwd=f.root,
            env={**f.env, "CHECKS": "success", "SHARDS": "success", "GATE_TESTS": "success",
                 "NATIVE_MARKER": str(marker)}, capture_output=True, text=True, timeout=20)
        self.bad(result)
        self.assertFalse(marker.exists())
        self.assertFalse((f.root / "merged").exists())

    def test_workflow_shape_and_contract_mutations(self):
        jobs = yaml.safe_load(WORKFLOW)["jobs"]
        worker = jobs["gate-tests"]
        self.assertEqual(set(worker), {"if", "runs-on", "timeout-minutes", "permissions", "strategy", "steps"})
        self.assertEqual(worker["permissions"], {"contents": "read"})
        self.assertEqual(worker["strategy"], {"fail-fast": False, "matrix": {"shard": [0, 1, 2]}})
        self.assertEqual(worker["if"], jobs["checks"]["if"])
        execute = next(s for s in worker["steps"] if "gate-tests.py run" in s.get("run", ""))
        self.assertEqual(set(execute), {"name", "run"})
        self.assertEqual(jobs["prove"]["needs"], ["checks", "gate-tests", "cheat-shard"])
        self.assertNotIn("needs", jobs["gate"])
        self.assertNotIn("if", jobs["gate"])
        f = self.fixture(1)
        checker = f.root / ".github/scripts/cheat-shard.test.sh"
        shutil.copyfile(ROOT / ".github/scripts/cheat-shard.test.sh", checker)
        sentence = f.root / "gate/MitosGate/CheatsShard.lean"
        sentence.parent.mkdir()
        shutil.copyfile(ROOT / "gate/MitosGate/CheatsShard.lean", sentence)
        workflow = f.root / ".github/workflows/ci.yml"
        workflow.parent.mkdir()

        def check(source):
            workflow.write_text(source)
            return subprocess.run(["bash", str(checker)], capture_output=True, text=True, timeout=20)

        self.good(check(WORKFLOW))
        start, end = WORKFLOW.index("  gate-tests:\n"), WORKFLOW.index("  cheat-shard:\n")
        worker_source = WORKFLOW[start:end]
        changes = {
            "matrix": worker_source.replace("shard: [0, 1, 2]", "shard: [0, 1]"),
            "count": worker_source.replace('matrix.shard }}/3', 'matrix.shard }}/2'),
            "swallowed failure": worker_source.replace('        run: python3 -I .github/scripts/gate-tests.py run',
                '        continue-on-error: true\n        run: python3 -I .github/scripts/gate-tests.py run'),
            "skipped executor": worker_source.replace('        run: python3 -I .github/scripts/gate-tests.py run',
                '        if: success()\n        run: python3 -I .github/scripts/gate-tests.py run'),
            "deadline": worker_source.replace("timeout-minutes: 20", "timeout-minutes: 30"),
            "privilege": worker_source.replace("contents: read", "contents: write"),
        }
        mutations = {name: WORKFLOW[:start] + source + WORKFLOW[end:] for name, source in changes.items()}
        mutations.update({
            "needs": WORKFLOW.replace("needs: [checks, gate-tests, cheat-shard]", "needs: [checks, cheat-shard]"),
            "constant status": WORKFLOW.replace("GATE_TESTS: ${{ needs.gate-tests.result }}", "GATE_TESTS: success"),
            "gate needs": WORKFLOW.replace("  gate:\n", "  gate:\n    needs: prove\n"),
            "gate skip": WORKFLOW.replace("  gate:\n", "  gate:\n    if: success()\n"),
            "removed verification": WORKFLOW.replace("gate-tests.py verify", "gate-tests.py omitted"),
            "missing protocol test": WORKFLOW.replace("gate-tests.test.py", "omitted.test.py"),
        })
        lines = WORKFLOW.splitlines(keepends=True)
        verify_at = next(i for i, line in enumerate(lines) if "gate-tests.py verify" in line)
        verify_lines = lines[verify_at:verify_at + 2]
        del lines[verify_at:verify_at + 2]
        aggregate_end = next(i for i, line in enumerate(lines) if "shards/cheat-shard-logs-0 shards/" in line)
        lines[aggregate_end + 1:aggregate_end + 1] = verify_lines
        mutations["late verification"] = "".join(lines)
        for name, source in mutations.items():
            with self.subTest(mutation=name):
                self.assertNotEqual(source, WORKFLOW)
                result = check(source)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("FAIL", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
