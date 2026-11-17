import pathlib
import subprocess
import sys
import tempfile

BIN = pathlib.Path(sys.argv[1]).resolve()
CHECK = pathlib.Path(sys.argv[2]).resolve()
ROOT = CHECK.parent.parent
CLEANUP = "Drop restored cheat and mutant logs"
STEP = f"      - name: {CLEANUP}\n        if: always()\n        run: rm -rf .lake/cheats .lake/mutants\n"

with tempfile.TemporaryDirectory(prefix="cache-logs-mutations-") as tmp:
    for workflow, jobs in [("ci", ["checks", "cheat-shard"]), ("nightly", ["full"])]:
        source = (ROOT / f".github/workflows/{workflow}.yml").read_text()
        assert source.count(STEP) == len(jobs)
        for position, job in enumerate(jobs):
            offset = 0
            for _ in range(position + 1):
                offset = source.index(STEP, offset) + len(STEP)
            before, after = source[:offset - len(STEP)], source[offset:]
            for mutation, replacement in [
                ("missing", ""),
                ("condition", STEP.replace("always()", "success()")),
                ("moved", "      - run: echo intervening\n" + STEP),
                ("duplicated", STEP + "\n" + STEP),
                ("no-run", STEP.replace("        run: rm -rf .lake/cheats .lake/mutants\n", "")),
                ("retains-logs", STEP.replace("rm -rf .lake/cheats .lake/mutants", "true")),
                ("removes-build", STEP.replace("rm -rf .lake/cheats .lake/mutants", "rm -rf .lake core/.lake")),
            ]:
                file = pathlib.Path(tmp) / f"{workflow}-{job}-{mutation}.yml"
                file.write_text(before + replacement + after)
                parsed = subprocess.run([str(BIN), "workflow", "parse", str(file)],
                                        capture_output=True, text=True, timeout=20)
                assert parsed.returncode == 0, (mutation, parsed)
                predecessor = {"checks": "actions/cache@v4", "cheat-shard": "actions/cache/restore@v4",
                               "full": "./.github/actions/setup"}[job]
                out = subprocess.run([str(CHECK), str(file), job, predecessor],
                                     capture_output=True, text=True, timeout=30)
                assert out.returncode != 0, (workflow, job, mutation, out)
                assert "FAIL" in out.stderr, (workflow, job, mutation, out)
                print(f"ok cache-logs rejects {workflow}/{job}/{mutation}")
