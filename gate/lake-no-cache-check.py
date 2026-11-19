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
ALLOWED_LAKE_DIRS = {"eval/score", "eval/mutants"}
ALLOWED_LAKE_EXES = {"mitos-gate", "mitos-lint-test", "mitos-score", "mitos-mutants"}
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
ACTION_PATH_EXPR_RE = re.compile(r"\$\{\{\s*github\.action_path\s*\}\}")

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


def strip_shell_comments(text):
    out = []
    i = 0
    n = len(text)
    in_sq = False
    in_dq = False
    at_word_start = True
    while i < n:
        ch = text[i]
        if ch == "\\" and not in_sq and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            at_word_start = False
            continue
        if ch == "'" and not in_dq:
            in_sq = not in_sq
            out.append(ch)
            i += 1
            at_word_start = False
            continue
        if ch == '"' and not in_sq:
            in_dq = not in_dq
            out.append(ch)
            i += 1
            at_word_start = False
            continue
        if not in_sq and not in_dq and ch == "#" and at_word_start:
            while i < n and text[i] != "\n":
                i += 1
            continue
        out.append(ch)
        if not in_sq and not in_dq:
            at_word_start = ch in " \t\r\n;|&()"
        else:
            at_word_start = False
        i += 1
    return "".join(out)


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
    lex.commenters = ""
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


def resolve_repo_script(cmd, repo_root):
    if cmd == ".lake/build/bin/mitos-gate":
        return cmd
    candidate = (repo_root / cmd).resolve()
    root_resolved = repo_root.resolve()
    try:
        rel = candidate.relative_to(root_resolved).as_posix()
    except ValueError:
        return None
    if ALLOWED_SCRIPT_RE.match(rel) and candidate.is_file():
        return rel
    return None


def check_lake_args(args):
    for idx, arg in enumerate(args):
        if arg == "--try-cache" or arg.startswith("--try-cache="):
            return f"disallowed lake flag {arg!r}"
        if "$" in arg and not (idx > 0 and args[idx - 1] == "--base"):
            return f"dynamic lake argument {arg!r}"
    rest = list(args)
    if len(rest) >= 2 and rest[0] == "--dir":
        if rest[1] not in ALLOWED_LAKE_DIRS:
            return f"unallowlisted lake --dir {rest[1]!r}"
        rest = rest[2:]
    if not rest:
        return "missing lake subcommand"
    sub = rest[0]
    sub_args = rest[1:]
    if sub == "build":
        if sub_args in ([], ["mitos-gate"]):
            return None
        return f"unallowlisted lake build arguments {sub_args!r}"
    if sub == "check":
        if not sub_args:
            return None
        return f"unallowlisted lake check arguments {sub_args!r}"
    if sub == "comparator":
        if sub_args in ([], ["--paranoid"]):
            return None
        return f"unallowlisted lake comparator arguments {sub_args!r}"
    if sub == "exe":
        if sub_args and sub_args[0] in ALLOWED_LAKE_EXES:
            return None
        return f"unallowlisted lake exe target {sub_args!r}"
    return f"unallowlisted lake subcommand {sub!r}"


def check_command(argv, repo_root):
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
    if resolve_repo_script(cmd, repo_root) is not None:
        return None
    if cmd not in ALLOWED_CMDS:
        return f"disallowed command {cmd!r}"
    if cmd == "lake":
        return check_lake_args(args)
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
        if rest and ALLOWED_PYTHON_SCRIPT_RE.match(rest[0]) and (repo_root / rest[0]).is_file():
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
        err = check_run_script(args[0], repo_root)
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


def check_run_script(script, repo_root=ROOT):
    code = strip_shell_comments(script)
    if FORBIDDEN_RAW_RE.search(code) or FORBIDDEN_RAW_RE.search(QUOTE_ESCAPE_RE.sub("", code)):
        return "forbidden env or shell override token"
    subs, stripped = extract_and_replace_cmd_substs(code)
    if subs is None:
        return "uninspectable quoting, backtick, or command substitution"
    for sub in subs:
        err = check_run_script(sub, repo_root)
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
            err = check_command(argv, repo_root)
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
    return check_command(argv, repo_root)


def is_lake_run_cmd(run_cmd):
    return bool(
        LAKE_STEP_RE.search(run_cmd)
        or LAKE_STEP_RE.search(QUOTE_ESCAPE_RE.sub("", run_cmd))
    )


def inspect_local_action(uses_ref, repo_root, inherited_env, seen):
    root_resolved = repo_root.resolve()
    action_dir = (repo_root / uses_ref).resolve()
    try:
        rel_dir = action_dir.relative_to(root_resolved).as_posix()
    except ValueError:
        return False, [], [f"local action {uses_ref!r} escapes repository root"]
    if action_dir in seen:
        return False, [], [f"cyclic local action reference {uses_ref!r}"]
    action_file = None
    for candidate in ("action.yml", "action.yaml"):
        path = action_dir / candidate
        if path.is_file():
            action_file = path
            break
    if action_file is None:
        return False, [], [f"local action {uses_ref!r} has no action.yml or action.yaml"]
    doc = yaml.safe_load(action_file.read_text())
    if not isinstance(doc, dict):
        return False, [], [f"local action {uses_ref!r} root is not a mapping"]
    runs = doc.get("runs")
    if not isinstance(runs, dict) or runs.get("using") != "composite":
        using = runs.get("using") if isinstance(runs, dict) else None
        return False, [], [f"unclassifiable local action {uses_ref!r} (using={using!r})"]
    steps = runs.get("steps")
    if not isinstance(steps, list):
        return False, [], [f"local action {uses_ref!r} has non-list composite steps"]

    has_lake = False
    lake_step_issues = []
    unclassifiable_issues = []
    next_seen = seen | {action_dir}
    for sub_idx, sub_step in enumerate(steps):
        if not isinstance(sub_step, dict):
            continue
        try:
            sub_env = {**inherited_env, **env_map(sub_step)}
        except ValueError as err:
            lake_step_issues.append(f"{uses_ref}/steps[{sub_idx}]: {err}")
            continue
        for key in FORBIDDEN_ENV_KEYS:
            if key in sub_env:
                lake_step_issues.append(f"{uses_ref}/steps[{sub_idx}]: forbidden env key {key!r}")
        sub_uses = sub_step.get("uses")
        if isinstance(sub_uses, str) and sub_uses.startswith("./"):
            nested_lake, nested_lake_issues, nested_unclassifiable = inspect_local_action(
                sub_uses, repo_root, sub_env, next_seen
            )
            has_lake = has_lake or nested_lake
            lake_step_issues.extend(nested_lake_issues)
            unclassifiable_issues.extend(nested_unclassifiable)
        if "run" not in sub_step:
            continue
        sub_run = sub_step.get("run")
        if not isinstance(sub_run, str):
            lake_step_issues.append(f"{uses_ref}/steps[{sub_idx}]: non-string run")
            continue
        resolved_run = ACTION_PATH_EXPR_RE.sub(rel_dir, sub_run)
        sub_shell = sub_step.get("shell")
        if sub_shell != "bash":
            lake_step_issues.append(
                f"{uses_ref}/steps[{sub_idx}]: unallowlisted shell {sub_shell!r}"
            )
        else:
            err = check_run_script(resolved_run, repo_root)
            if err:
                lake_step_issues.append(f"{uses_ref}/steps[{sub_idx}]: {err}")
        if is_lake_run_cmd(resolved_run):
            has_lake = True
            val = sub_env.get("LAKE_NO_CACHE")
            if val != "1":
                lake_step_issues.append(
                    f"{uses_ref}/steps[{sub_idx}]: LAKE_NO_CACHE is {val!r}, want '1'"
                )
    return has_lake, lake_step_issues, unclassifiable_issues


def check_workflows(workflow_dir, repo_root=ROOT):
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
                job_own_env = env_map(job)
                job_env = {**root_env, **job_own_env}
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
                uses_ref = step.get("uses")
                if isinstance(uses_ref, str) and uses_ref.startswith("./"):
                    action_lake, action_lake_issues, action_unclassifiable = inspect_local_action(
                        uses_ref, repo_root, step_env, set()
                    )
                    for err in action_unclassifiable:
                        problems.append(f"{path.name}/{job_name}/steps[{idx}]: {err}")
                    for err in action_lake_issues:
                        step_script_issues.append((idx, err))
                    if action_lake:
                        job_has_lake = True
                        found_lake_jobs.add((path.name, job_name))
                if "run" not in step:
                    continue
                run_cmd = step.get("run")
                if not isinstance(run_cmd, str):
                    step_script_issues.append((idx, "non-string run"))
                    continue
                shell = step.get("shell", job_shell)
                if shell not in (None, "bash"):
                    step_script_issues.append((idx, f"unallowlisted shell {shell!r}"))
                else:
                    script_err = check_run_script(run_cmd, repo_root)
                    if script_err:
                        step_script_issues.append((idx, script_err))
                if not is_lake_run_cmd(run_cmd):
                    continue
                job_has_lake = True
                found_lake_jobs.add((path.name, job_name))
                val = step_env.get("LAKE_NO_CACHE")
                if val != "1":
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: LAKE_NO_CACHE is {val!r}, want '1'"
                    )
            if job_has_lake:
                if job_own_env.get("LAKE_NO_CACHE") != "1":
                    problems.append(
                        f"{path.name}/{job_name}: job-level env.LAKE_NO_CACHE is "
                        f"{job_own_env.get('LAKE_NO_CACHE')!r}, want '1'"
                    )
                for idx, err in step_script_issues:
                    problems.append(
                        f"{path.name}/{job_name}/steps[{idx}]: {err}"
                    )
    missing = EXPECTED_LAKE_JOBS - found_lake_jobs
    if missing:
        problems.append(f"expected Lake jobs not checked: {sorted(missing)}")
    return problems, found_lake_jobs


def check_clean(workflow_dir, repo_root=ROOT):
    problems, found = check_workflows(workflow_dir, repo_root=repo_root)
    if problems:
        raise AssertionError("\n".join(problems))
    return found


found = check_clean(WORKFLOWS)
assert found == EXPECTED_LAKE_JOBS, (found, EXPECTED_LAKE_JOBS)

mutations = 0
with tempfile.TemporaryDirectory(prefix="lake-no-cache-") as tmp:
    tmp = pathlib.Path(tmp)

    def mutate(name, filename, transform, expect_substr=None):
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
        if expect_substr is not None:
            assert any(expect_substr in p for p in problems), (name, expect_substr, problems)
        mutations += 1

    def mutate_with_action(name, action_rel, action_text, wf_name, wf_text, expect_substr=None):
        global mutations
        fake_root = tmp / name
        shutil.copytree(ROOT / ".github", fake_root / ".github")
        shutil.copytree(ROOT / ".claude/scripts", fake_root / ".claude/scripts")
        (fake_root / "gate").mkdir(parents=True, exist_ok=True)
        for p in (ROOT / "gate").glob("*.sh"):
            shutil.copy2(p, fake_root / "gate" / p.name)
        action_path = fake_root / action_rel
        action_path.parent.mkdir(parents=True, exist_ok=True)
        action_path.write_text(action_text)
        (fake_root / ".github/workflows" / wf_name).write_text(wf_text)
        problems, _ = check_workflows(fake_root / ".github/workflows", repo_root=fake_root)
        assert problems, f"mutation {name} was not caught"
        if expect_substr is not None:
            assert any(expect_substr in p for p in problems), (name, expect_substr, problems)
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
        "workflow-env-only-nightly",
        "nightly.yml",
        lambda s: s.replace(
            "permissions:\n  contents: read\n",
            "permissions:\n  contents: read\n\nenv:\n  LAKE_NO_CACHE: '1'\n",
            1,
        ).replace(
            "  full:\n    runs-on: ubuntu-24.04\n    env:\n      LAKE_NO_CACHE: '1'\n",
            "  full:\n    runs-on: ubuntu-24.04\n",
            1,
        ),
        expect_substr="job-level env.LAKE_NO_CACHE",
    )
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
        "github-env-lake-env",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Override cache via lake env\n        run: |\n          lake env python3 -c 'import os;f=open(os.environ[\"GITHUB_\"+\"ENV\"],\"a\");f.write(\"LAKE_NO_\"+\"CACHE=0\\n\")'\n      - name: Build core and gate\n",
            1,
        ),
        expect_substr="unallowlisted lake subcommand 'env'",
    )
    mutate(
        "step-python-shell",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Override cache via python shell\n        shell: python\n        run: 'true'\n      - name: Build core and gate\n",
            1,
        ),
        expect_substr="unallowlisted shell",
    )
    accept(
        "step-bash-shell",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Explicit bash shell control\n        shell: bash\n        run: 'true'\n      - name: Build core and gate\n",
            1,
        ),
    )
    accept(
        "multiline-quoted-hash",
        "ci.yml",
        lambda s: s.replace(
            "      - name: Build core and gate\n",
            "      - name: Multiline quoted hash and shell comment\n        run: |\n          # don't treat apostrophes in comments as quotes\n          echo 'notes\n          # end of notes'\n      - name: Build core and gate\n",
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
    mutate_with_action(
        "local-action-runs-lake",
        ".github/actions/fake-lake/action.yml",
        "name: fake-lake\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: lake build\n",
        "extra.yml",
        "jobs:\n  b:\n    steps:\n      - uses: ./.github/actions/fake-lake\n",
        expect_substr="LAKE_NO_CACHE",
    )
    mutate_with_action(
        "local-action-non-composite",
        ".github/actions/fake-node/action.yml",
        "name: fake-node\nruns:\n  using: node20\n  main: index.js\n",
        "extra.yml",
        "jobs:\n  b:\n    steps:\n      - uses: ./.github/actions/fake-node\n",
        expect_substr="unclassifiable local action",
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
