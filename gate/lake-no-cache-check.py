import pathlib
import re
import shutil
import sys
import tempfile

import yaml

ROOT = pathlib.Path(sys.argv[1]).resolve()
WORKFLOWS = ROOT / ".github/workflows"

LAKE_STEP_RE = re.compile(
    r"(?:^|[^A-Za-z0-9_./-])lake(?:\s|$)"
    r"|bump-lean\.sh"
    r"|gate-tests\.py\s+run"
    r"|land-(?:protection|decide|apply|report)\.test\.sh"
    r"|app-token\.test\.sh"
    r"|lock-header-test\.sh"
    r"|mitos-gate\s+cheats(?!\s+aggregate\b)"
)

UNSET_RE = re.compile(
    r"(?:unset\s+(?:-[^\s]+\s+)*LAKE_NO_CACHE\b"
    r"|env\s+[^\n]*(?:-u\s*|--unset=)LAKE_NO_CACHE\b"
    r"|(?<![\w-])--try-cache\b"
    r"|\bLAKE_NO_CACHE=(?!1(?:\s|$|['\"]?\s|['\"]?$)))"
)

GITHUB_ENV_RE = re.compile(r"\bGITHUB_ENV\b")

EXPECTED_LAKE_JOBS = {
    ("ci.yml", "checks"),
    ("ci.yml", "gate-tests"),
    ("ci.yml", "cheat-shard"),
    ("land.yml", "decide"),
    ("nightly.yml", "full"),
    ("nightly.yml", "canary"),
}


def env_map(container):
    raw = container.get("env") if isinstance(container, dict) else None
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise ValueError("non-mapping env")
    return raw


def check_workflows(workflow_dir):
    found_lake_jobs = set()
    problems = []
    files = sorted(
        p for p in workflow_dir.iterdir()
        if p.is_file() and p.suffix in {".yml", ".yaml"}
    )
    for path in files:
        doc = yaml.safe_load(path.read_text())
        if not isinstance(doc, dict):
            problems.append(f"{path.name}: workflow root is not a mapping")
            continue
        try:
            root_env = env_map(doc)
        except ValueError as err:
            problems.append(f"{path.name}: {err}")
            continue
        jobs = doc.get("jobs")
        if not isinstance(jobs, dict):
            continue
        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                continue
            try:
                job_env = {**root_env, **env_map(job)}
            except ValueError as err:
                problems.append(f"{path.name}/{job_name}: {err}")
                continue
            steps = job.get("steps")
            if not isinstance(steps, list):
                continue
            job_has_lake = False
            github_env_steps = []
            for idx, step in enumerate(steps):
                if not isinstance(step, dict):
                    continue
                run_cmd = step.get("run")
                if not isinstance(run_cmd, str):
                    continue
                if GITHUB_ENV_RE.search(run_cmd):
                    github_env_steps.append(idx)
                if not LAKE_STEP_RE.search(run_cmd):
                    continue
                job_has_lake = True
                found_lake_jobs.add((path.name, job_name))
                try:
                    step_env = {**job_env, **env_map(step)}
                except ValueError as err:
                    problems.append(f"{path.name}/{job_name}/steps[{idx}]: {err}")
                    continue
                val = step_env.get("LAKE_NO_CACHE")
                if val != "1":
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: LAKE_NO_CACHE is {val!r}, want '1'"
                    )
                if UNSET_RE.search(run_cmd):
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: run script overrides or unsets LAKE_NO_CACHE"
                    )
            if job_has_lake:
                for idx in github_env_steps:
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: run script writes GITHUB_ENV in a Lake job"
                    )
    missing = EXPECTED_LAKE_JOBS - found_lake_jobs
    if missing:
        problems.append(f"expected Lake jobs not checked: {sorted(missing)}")
    return problems, found_lake_jobs


def check_clean(workflow_dir):
    problems, found = check_workflows(workflow_dir)
    if problems:
        raise AssertionError("\n".join(problems))
    return found


found = check_clean(WORKFLOWS)
assert found == EXPECTED_LAKE_JOBS, (found, EXPECTED_LAKE_JOBS)

mutations = 0
with tempfile.TemporaryDirectory(prefix="lake-no-cache-") as tmp:
    tmp = pathlib.Path(tmp)

    def mutate(name, filename, transform):
        global mutations
        dst = tmp / name
        shutil.copytree(WORKFLOWS, dst)
        target = dst / filename
        before = target.read_text() if target.exists() else ""
        after = transform(before)
        assert after != before, name
        target.write_text(after)
        problems, _ = check_workflows(dst)
        assert problems, f"mutation {name} was not caught"
        mutations += 1

    def accept(name, filename, transform):
        dst = tmp / name
        shutil.copytree(WORKFLOWS, dst)
        target = dst / filename
        before = target.read_text()
        after = transform(before)
        assert after != before, name
        target.write_text(after)
        check_clean(dst)

    for wf_name, job_name in sorted(EXPECTED_LAKE_JOBS):
        def drop_env(text, j=job_name):
            idx = text.index(f"  {j}:\n")
            line = "      LAKE_NO_CACHE: '1'\n"
            pos = text.index(line, idx)
            if text[pos - len("    env:\n"):pos] == "    env:\n":
                after_line = text[pos + len(line):]
                if not after_line.startswith("      "):
                    return text[:pos - len("    env:\n")] + after_line
            return text[:pos] + text[pos + len(line):]

        def zero_env(text, j=job_name):
            idx = text.index(f"  {j}:\n")
            pos = text.index("LAKE_NO_CACHE: '1'", idx)
            return text[:pos] + "LAKE_NO_CACHE: '0'" + text[pos + len("LAKE_NO_CACHE: '1'"):]

        mutate(f"drop-{wf_name}-{job_name}", wf_name, drop_env)
        mutate(f"zero-{wf_name}-{job_name}", wf_name, zero_env)

    mutate(
        "step-override",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n        run: lake build\n",
            "      - name: Build core and gate\n        env:\n          LAKE_NO_CACHE: '0'\n        run: lake build\n",
            1,
        ),
    )
    mutate(
        "run-unset",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: unset LAKE_NO_CACHE && lake build\n",
            1,
        ),
    )
    mutate(
        "run-env-u",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: env -u LAKE_NO_CACHE lake build\n",
            1,
        ),
    )
    mutate(
        "run-env-unset",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: env --unset=LAKE_NO_CACHE lake build\n",
            1,
        ),
    )
    mutate(
        "run-env-unset-space",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: env --unset LAKE_NO_CACHE lake build\n",
            1,
        ),
    )
    mutate(
        "run-assign-zero",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: LAKE_NO_CACHE=0 lake build\n",
            1,
        ),
    )
    mutate(
        "run-try-cache",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: lake --try-cache build\n",
            1,
        ),
    )
    mutate(
        "github-env-zero",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Override cache via GITHUB_ENV\n        run: echo 'LAKE_NO_CACHE=0' >> \"$GITHUB_ENV\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-dynamic",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Dynamic cache via GITHUB_ENV\n        run: echo \"LAKE_NO_CACHE=$VAL\" >> \"$GITHUB_ENV\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-heredoc",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Heredoc cache via GITHUB_ENV\n        run: |\n          { echo 'LAKE_NO_CACHE<<EOF'; echo 0; echo EOF; } >> \"$GITHUB_ENV\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-split",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Split cache via GITHUB_ENV\n        run: echo 'LAKE_NO_'CACHE'=0' >> \"$GITHUB_ENV\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    accept(
        "github-env-non-lake-job",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Cancel this branch's superseded runs, or only this run when the PR is closed\n",
            "      - name: Non-Lake GITHUB_ENV\n        run: echo 'OTHER_VAR=0' >> \"$GITHUB_ENV\"\n      - name: Cancel this branch's superseded runs, or only this run when the PR is closed\n",
            1,
        ),
    )
    mutate(
        "new-lake-build-job",
        "extra.yml",
        lambda _: "jobs:\n  b:\n    steps:\n      - run: lake build\n",
    )
    mutate(
        "new-lake-exe-job",
        "extra.yml",
        lambda _: "jobs:\n  b:\n    steps:\n      - run: lake exe mitos-gate imports\n",
    )

print(f"lake-no-cache: {len(found)} Lake jobs pinned, {mutations} mutations rejected")
