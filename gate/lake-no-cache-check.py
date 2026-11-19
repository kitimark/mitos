import pathlib
import re
import shlex
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

SAFE_WRITE_TARGET_RE = re.compile(
    r"^(?:"
    r"/dev/null"
    r"|(?:\$GITHUB_OUTPUT|\$\{GITHUB_OUTPUT\})"
    r"|(?:\$GITHUB_STEP_SUMMARY|\$\{GITHUB_STEP_SUMMARY\})"
    r"|(?:\$RUNNER_TEMP|\$\{RUNNER_TEMP\})/(?!.*\.\.)[A-Za-z0-9._/-]+"
    r"|\.lake/(?!.*\.\.)[A-Za-z0-9._/-]+"
    r"|/tmp/mitos-gate\.ldd"
    r")$"
)

ALLOWED_CMDS = {
    "set", "[", "cd", "echo", "printf", "exit", "true", "command", "trap",
    "lake", "rm", "mkdir", "cat", "git", "grep", "sed", "ldd", "strip",
    "tar", "tee", "date", "sudo", "python3",
}

ALLOWED_SCRIPT_RE = re.compile(
    r"^(?:\.claude/scripts/|\.github/scripts/|gate/)[A-Za-z0-9._-]+\.sh$"
    r"|^\.lake/build/bin/mitos-gate$"
)

ALLOWED_PYTHON_SCRIPT_RE = re.compile(r"^\.github/scripts/[A-Za-z0-9._-]+\.py$")
ALLOWED_PYTHON_SNIPPETS = {
    "import yaml",
    "import yaml; print(yaml.__version__)",
}
ALLOWED_SUDO_ARGS = {
    ("apt-get", "update", "-q"),
    ("apt-get", "install", "-y", "-q", "shellcheck"),
    ("apt-get", "install", "-y", "python3-yaml"),
    ("sysctl", "-w", "kernel.apparmor_restrict_unprivileged_userns=0"),
}
FORBIDDEN_ENV_KEYS = {"BASH_ENV", "ENV"}
LOCAL_ASSIGN_RE = re.compile(r"^[a-z_][a-z0-9_]*=")
CONTROL_WORDS = {"if", "then", "else", "elif", "fi", "!", "{", "}"}
WRITE_REDIRECT_OPS = {">", ">>", ">|", "<>", "&>", "&>>", "1>", "1>>", "2>", "2>>"}
DUP_REDIRECT_OPS = {">&", "1>&", "2>&"}
SEPARATORS = {";", "|", "||", "&&", "&", "\n", "(", ")"}
PUNCT_CHARS = set(";|&<>()\n")
PUNCT_SPLIT_RE = re.compile(r"&>>|&>|>>|>\||<>|>&|\|\||&&|<<|[;|&<>()\n]")
FORBIDDEN_RAW_RE = re.compile(
    r"\bLAKE_NO_CACHE\b"
    r"|\bGITHUB_ENV\b"
    r"|(?<![\w-])--try-cache\b"
    r"|\$\{!"
    r"|\$\{[^}]*="
    r"|\$\(\("
    r"|\$'"
    r"|[<>]\("
    r"|<<"
)
QUOTE_ESCAPE_RE = re.compile(r"""['"\\]""")

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


def default_shell(container):
    defaults = container.get("defaults") if isinstance(container, dict) else None
    if defaults is None:
        return None
    if not isinstance(defaults, dict):
        raise ValueError("non-mapping defaults")
    run_cfg = defaults.get("run")
    if run_cfg is None:
        return None
    if not isinstance(run_cfg, dict):
        raise ValueError("non-mapping defaults.run")
    return run_cfg.get("shell")


def extract_and_replace_cmd_substs(text):
    subs = []
    out = []
    i = 0
    in_sq = False
    in_dq = False
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\" and not in_sq and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        if ch == "'" and not in_dq:
            in_sq = not in_sq
            out.append(ch)
            i += 1
            continue
        if ch == '"' and not in_sq:
            in_dq = not in_dq
            out.append(ch)
            i += 1
            continue
        if not in_sq and ch == "`":
            return None, None
        if not in_sq and text[i:i + 2] == "$(":
            depth = 1
            j = i + 2
            sub_sq = False
            sub_dq = False
            while j < n and depth > 0:
                c = text[j]
                if c == "\\" and not sub_sq and j + 1 < n:
                    j += 2
                    continue
                if c == "'" and not sub_dq:
                    sub_sq = not sub_sq
                elif c == '"' and not sub_sq:
                    sub_dq = not sub_dq
                elif not sub_sq:
                    if text[j:j + 2] == "$(":
                        depth += 1
                        j += 1
                    elif not sub_dq and c == "(":
                        depth += 1
                    elif not sub_dq and c == ")":
                        depth -= 1
                j += 1
            if depth != 0:
                return None, None
            subs.append(text[i + 2:j - 1])
            out.append("__CMD_SUBST__")
            i = j
            continue
        out.append(ch)
        i += 1
    if in_sq or in_dq:
        return None, None
    return subs, "".join(out)


def tokenize_shell(script):
    joined = re.sub(r"\\\n", " ", script)
    lex = shlex.shlex(joined, posix=True, punctuation_chars=";|&<>()\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = "#"
    tokens = []
    while True:
        tok = lex.get_token()
        if tok is None:
            break
        if tok and all(ch in PUNCT_CHARS for ch in tok):
            tokens.extend(PUNCT_SPLIT_RE.findall(tok))
        else:
            tokens.append(tok)
    return tokens


def check_command(argv):
    if not argv:
        return None
    while argv and argv[0] in CONTROL_WORDS:
        argv = argv[1:]
    if not argv:
        return None
    while argv and LOCAL_ASSIGN_RE.match(argv[0]):
        argv = argv[1:]
    if not argv:
        return None
    cmd = argv[0]
    args = argv[1:]
    if ALLOWED_SCRIPT_RE.match(cmd):
        if cmd != ".lake/build/bin/mitos-gate" and not (ROOT / cmd).is_file():
            return f"unknown repo script {cmd!r}"
        return None
    if cmd not in ALLOWED_CMDS:
        return f"disallowed command {cmd!r}"
    if cmd == "lake":
        for idx, arg in enumerate(args):
            if arg == "--try-cache" or arg.startswith("--try-cache="):
                return f"disallowed lake flag {arg!r}"
            if "$" in arg and not (idx > 0 and args[idx - 1] == "--base"):
                return f"dynamic lake argument {arg!r}"
    elif cmd == "cd":
        if args not in (["core"], ["examples/acme"]):
            return f"unallowlisted cd target {args!r}"
    elif cmd == "printf":
        if args and args[0].startswith("-"):
            return f"disallowed printf option {args[0]!r}"
        for arg in args:
            if arg == "-v" or arg.startswith("-v"):
                return "printf -v is disallowed"
    elif cmd == "tee":
        in_flags = True
        for arg in args:
            if in_flags and arg == "--":
                in_flags = False
                continue
            if in_flags and arg.startswith("-"):
                continue
            if not SAFE_WRITE_TARGET_RE.match(arg):
                return f"unallowlisted tee target {arg!r}"
    elif cmd == "strip":
        for idx, arg in enumerate(args):
            if arg == "-o":
                if idx + 1 >= len(args) or not SAFE_WRITE_TARGET_RE.match(args[idx + 1]):
                    return f"unallowlisted strip -o target {args[idx + 1:idx + 2]!r}"
    elif cmd == "tar":
        if args != ["-x", "-C", "$dir"]:
            return f"unallowlisted tar invocation {args!r}"
    elif cmd == "python3":
        idx = 0
        while idx < len(args) and args[idx] == "-I":
            idx += 1
        rest = args[idx:]
        if len(rest) == 2 and rest[0] == "-c" and rest[1] in ALLOWED_PYTHON_SNIPPETS:
            return None
        if rest and ALLOWED_PYTHON_SCRIPT_RE.match(rest[0]) and (ROOT / rest[0]).is_file():
            return None
        return f"unallowlisted python3 invocation {args!r}"
    elif cmd == "sudo":
        if tuple(args) not in ALLOWED_SUDO_ARGS:
            return f"unallowlisted sudo command {args!r}"
    elif cmd == "command":
        if not args or args[0] != "-v":
            return f"unallowlisted command invocation {args!r}"
    elif cmd == "trap":
        if len(args) < 2:
            return f"unallowlisted trap invocation {args!r}"
        err = check_run_script(args[0])
        if err:
            return f"trap body: {err}"
    elif cmd == "git":
        if args == ["diff"]:
            return None
        if len(args) == 3 and args[0] == "merge-base" and not any(a.startswith("-") for a in args[1:]):
            return None
        if len(args) == 3 and args[0] == "cat-file" and args[1] == "-e":
            return None
        if len(args) == 3 and args[0] == "archive" and args[2] == "ops/runs" and not args[1].startswith("-"):
            return None
        return f"unallowlisted git invocation {args!r}"
    elif cmd == "sed":
        if args != ["s/^/### /"]:
            return f"unallowlisted sed invocation {args!r}"
    return None


def check_run_script(script):
    code_lines = [line for line in script.splitlines() if not line.lstrip().startswith("#")]
    code = "\n".join(code_lines)
    if FORBIDDEN_RAW_RE.search(code) or FORBIDDEN_RAW_RE.search(QUOTE_ESCAPE_RE.sub("", code)):
        return "forbidden env or shell override token"
    subs, stripped = extract_and_replace_cmd_substs(code)
    if subs is None:
        return "uninspectable quoting, backtick, or command substitution"
    for sub in subs:
        err = check_run_script(sub)
        if err:
            return f"command substitution: {err}"
    try:
        tokens = tokenize_shell(stripped)
    except ValueError as err:
        return f"shell parse error: {err}"
    merged = []
    idx = 0
    while idx < len(tokens):
        tok = tokens[idx]
        if tok in {"1", "2"} and idx + 1 < len(tokens) and tokens[idx + 1] in {">", ">>", ">|", "<>", ">&"}:
            merged.append(tok + tokens[idx + 1])
            idx += 2
            continue
        merged.append(tok)
        idx += 1
    argv = []
    idx = 0
    while idx < len(merged):
        tok = merged[idx]
        if tok == "(" and any(word not in CONTROL_WORDS for word in argv):
            return f"unexpected subshell/function syntax after {argv!r}"
        if tok in SEPARATORS:
            err = check_command(argv)
            if err:
                return err
            argv = []
            idx += 1
            continue
        if tok in DUP_REDIRECT_OPS:
            if idx + 1 >= len(merged) or merged[idx + 1] not in {"1", "2"}:
                return f"unsafe fd redirect {tok!r} {merged[idx + 1:idx + 2]!r}"
            idx += 2
            continue
        if tok in WRITE_REDIRECT_OPS:
            if idx + 1 >= len(merged):
                return f"dangling redirect {tok!r}"
            target = merged[idx + 1]
            if not SAFE_WRITE_TARGET_RE.match(target):
                return f"unallowlisted redirect target {target!r}"
            idx += 2
            continue
        if tok == "<":
            return "input redirect is disallowed"
        argv.append(tok)
        idx += 1
    return check_command(argv)


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
            root_shell = default_shell(doc)
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
                job_shell = default_shell(job) if default_shell(job) is not None else root_shell
            except ValueError as err:
                problems.append(f"{path.name}/{job_name}: {err}")
                continue
            steps = job.get("steps")
            if not isinstance(steps, list):
                continue
            job_has_lake = False
            step_script_issues = []
            for idx, step in enumerate(steps):
                if not isinstance(step, dict):
                    continue
                try:
                    step_env = {**job_env, **env_map(step)}
                except ValueError as err:
                    step_script_issues.append((idx, str(err)))
                    continue
                for key in FORBIDDEN_ENV_KEYS:
                    if key in step_env:
                        step_script_issues.append((idx, f"forbidden env key {key!r}"))
                run_cmd = step.get("run")
                if not isinstance(run_cmd, str):
                    continue
                shell = step.get("shell", job_shell)
                if shell not in (None, "bash"):
                    step_script_issues.append((idx, f"unallowlisted shell {shell!r}"))
                else:
                    script_err = check_run_script(run_cmd)
                    if script_err:
                        step_script_issues.append((idx, script_err))
                if not (LAKE_STEP_RE.search(run_cmd) or LAKE_STEP_RE.search(QUOTE_ESCAPE_RE.sub("", run_cmd))):
                    continue
                job_has_lake = True
                found_lake_jobs.add((path.name, job_name))
                val = step_env.get("LAKE_NO_CACHE")
                if val != "1":
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: LAKE_NO_CACHE is {val!r}, want '1'"
                    )
            if job_has_lake:
                for idx, err in step_script_issues:
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: {err}"
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
        "run-try-cache",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: lake --try-cache build\n",
            1,
        ),
    )
    mutate(
        "run-try-cache-split",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: lake --try-''cache build\n",
            1,
        ),
    )
    mutate(
        "run-dynamic-lake-arg",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: |\n          f=--try-; g=cache\n          lake \"$f$g\" build\n",
            1,
        ),
    )
    mutate(
        "run-printf-v",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: |\n          printf -v LAKE_NO_CACHE 0\n          lake build\n",
            1,
        ),
    )
    mutate(
        "run-printf-v-indirect",
        "ci.yml",
        lambda s: s.replace(
            "        run: lake build\n",
            "        run: |\n          printf -v foo 0\n          lake build\n",
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
    mutate(
        "github-env-split-indirect",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Split indirect cache via GITHUB_ENV\n        run: |\n          target=GITHUB_''ENV\n          printf '%s\\n' 'LAKE_NO_'CACHE'=0' >> \"${!target}\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-concat-indirect",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Concat indirect cache via GITHUB_ENV\n        run: |\n          a=GITHUB_; b=ENV; target=\"$a$b\"\n          echo 'LAKE_NO_CACHE=0' >> \"${!target}\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-arbitrary-redirect",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Arbitrary redirect in Lake job\n        run: echo 'LAKE_NO_CACHE=0' >> \"$env_file\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-arbitrary-tee",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Arbitrary tee in Lake job\n        run: echo 'LAKE_NO_CACHE=0' | tee \"$env_file\"\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-perl-sysopen",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Override cache via perl\n        run: |\n          perl -e 'use Fcntl; sysopen(F,$ENV{\"GITHUB_\".\"ENV\"},O_WRONLY|O_APPEND) or die $!; print F \"LAKE_NO_CACHE=0\\n\"'\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "github-env-perl-split",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Override cache via split perl\n        run: |\n          perl -e 'use Fcntl; sysopen(F,$ENV{\"GITHUB_\".\"ENV\"},O_WRONLY|O_APPEND) or die $!; print F \"LAKE_NO_\".\"CACHE=0\\n\"'\n      - name: Build core and gate\n",
            1,
        ),
    )
    mutate(
        "step-python-shell",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Override cache via python shell\n        shell: python\n        run: print('hi')\n      - name: Build core and gate\n",
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
