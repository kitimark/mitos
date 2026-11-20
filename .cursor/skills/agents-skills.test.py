#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parent / "agents-skills.py"
REPO = Path(__file__).resolve().parents[2]

KEPT = (
    "architect",
    "kitimark-mode",
    "no-comments",
    "poteto-mode",
    "principle-split-by-topic",
    "reflect",
    "show-me-your-work",
    "swarm",
)

FANOUT = (
    "spawn a subagent with your host's tool "
    "(Codex `spawn_agent`, Antigravity `invoke_subagent`, "
    "Cursor `Task`, Claude Code `Agent`); "
    "if none, run the steps one at a time."
)

KITIMARK = f"""\
# kitimark mode

The process lives in `docs/process.md`. Never add the label `spec-approved`. The owner merges a PR that needs that label or that touches a path the owner keeps. Never enable auto-merge, and never post a merge command. The repository has no `AGENTS.md`.

{FANOUT}

Inherit the parent model, or the host's default.
"""

HEADER = (
    "name\tclass\tsource\tinvocation\tcursor\tcursor_sha256\tclaude_sha256\n"
)


class Check:
    def __init__(self) -> None:
        self.count = 0

    def expect(self, condition: bool, message: str) -> None:
        self.count += 1
        if not condition:
            raise SystemExit(f"FAIL {message}")


def run(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args, "--root", str(root)],
        check=False,
        capture_output=True,
        text=True,
    )


def skill_text(name: str, description: str, body: str, disable: bool) -> str:
    lines = ["---", f"name: {name}", f"description: {description!r}"]
    lines = ["---", f"name: {name}", "description: " + _quote(description)]
    if disable:
        lines.append("disable-model-invocation: true")
    lines.extend(["---", "", body if body.endswith("\n") else body + "\n"])
    return "\n".join(lines)


def _quote(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def write_skill(root: Path, tree: str, name: str, text: str) -> None:
    path = root / tree / "skills" / name / "SKILL.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def policy(root: Path, name: str) -> None:
    path = root / ".agents" / "skills" / name / "agents" / "openai.yaml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("policy:\n  allow_implicit_invocation: false\n", encoding="utf-8")


def roster_line(name: str, klass: str, source: str, invocation: str, cursor: str) -> str:
    return f"{name}\t{klass}\t{source}\t{invocation}\t{cursor}\t-\t-\n"


def build_base(root: Path) -> None:
    explicit = skill_text("placeholder", "Do the task.", "Read the task and do it.\n", True)
    mirror = skill_text(
        "tdd",
        "Keep the test red first.",
        "Keep general-purpose mechanism inside the module.\n",
        True,
    )
    kit = skill_text(
        "kitimark-mode",
        "How the Mitos owner (kitimark) wants agents to work. Invoke explicitly as $kitimark-mode or /kitimark-mode.",
        KITIMARK,
        False,
    )
    rows = [HEADER]
    for name in KEPT:
        text = kit if name == "kitimark-mode" else explicit.replace("name: placeholder", f"name: {name}", 1)
        for tree in (".cursor", ".claude", ".agents"):
            write_skill(root, tree, name, text)
        if name != "kitimark-mode":
            policy(root, name)
        if name == "no-comments":
            for rel in (".cursor/agents/comment-sicko.md", ".claude/agents/comment-sicko.md"):
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("keep list\n", encoding="utf-8")
        invocation = "named" if name == "kitimark-mode" else "explicit"
        rows.append(roster_line(name, "rewrite", "none", invocation, "kept"))
    write_skill(root, ".cursor", "tdd", mirror)
    write_skill(root, ".claude", "tdd", mirror)
    write_skill(root, ".agents", "tdd", mirror)
    policy(root, "tdd")
    rows.append(roster_line("tdd", "mirror", "both", "explicit", "vendored"))
    (root / ".cursor" / "skills" / "agents-roster.tsv").write_text("".join(rows), encoding="utf-8")
    stamped = run(root, "stamp")
    if stamped.returncode != 0:
        raise SystemExit(f"base stamp failed\n{stamped.stderr}\n{stamped.stdout}")


def snapshot(root: Path) -> dict[str, tuple[bytes, int]]:
    found: dict[str, tuple[bytes, int]] = {}
    agents = root / ".agents"
    if not agents.exists():
        return found
    for path in agents.rglob("*"):
        if path.is_file() and not path.is_symlink():
            stat = path.stat()
            found[str(path.relative_to(root))] = (path.read_bytes(), stat.st_mtime_ns)
    return found


def faults_of(proc: subprocess.CompletedProcess[str]) -> str:
    return proc.stdout


def main() -> int:
    check = Check()
    with tempfile.TemporaryDirectory() as tmp:
        base_dir = Path(tmp)
        build_base(base_dir)
        clean = run(base_dir, "check")
        check.expect(clean.returncode == 0 and clean.stdout == "", f"base check\n{clean.stdout}")
        mirror = (base_dir / ".agents" / "skills" / "tdd" / "SKILL.md").read_text(encoding="utf-8")
        check.expect("general-purpose" in mirror and "`general-purpose`" not in mirror, "prose form")
        kept = run(base_dir, "kept")
        check.expect(kept.returncode == 0 and kept.stdout.splitlines() == list(KEPT), kept.stdout)

        fixture_bad_name(check)
        fixture_folder_mismatch(check)
        fixture_description_length(check)
        fixture_paths_key(check)
        fixture_symlink(check)
        fixture_agents_md(check)
        fixture_rules(check)
        fixture_excluded_present(check)
        fixture_mirror_drift(check)
        fixture_source_split(check)
        fixture_stamp(check)
        fixture_openai_missing(check)
        fixture_named_has_yaml(check)
        fixture_kitimark_phrase(check)
        fixture_banned_token(check)
        fixture_allowed_sentence(check)
        fixture_verify_not_exempt(check)
        fixture_unrostered(check)
        fixture_sync_preserves_rewrite(check)
        fixture_sync_idempotent(check)

    real = run(REPO, "check")
    check.expect(real.returncode == 0 and real.stdout == "", f"real tree\n{real.stdout}")
    print(f"checks: {check.count}")
    return 0


def clone(mutate) -> None:
    raise AssertionError("use with_base")


def with_base(mutate) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        build_base(root)
        mutate(root)
        return run(root, "check")


def fixture_bad_name(check: Check) -> None:
    def mutate(root: Path) -> None:
        text = skill_text("bad_name", "A skill.", "Body.\n", True)
        write_skill(root, ".cursor", "bad_name", text)
        write_skill(root, ".agents", "bad_name", text)
        policy(root, "bad_name")
        _append_row(root, roster_line("bad_name", "mirror", "cursor", "explicit", "vendored"))

    proc = with_base(mutate)
    check.expect(proc.returncode == 1 and "BadName:" in proc.stdout, proc.stdout)


def fixture_folder_mismatch(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "skills" / "tdd" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8").replace("name: tdd", "name: tdx", 1), encoding="utf-8")
        for tree in (".cursor", ".claude"):
            source = root / tree / "skills" / "tdd" / "SKILL.md"
            source.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")

    proc = with_base(mutate)
    check.expect("NameFolderMismatch:" in proc.stdout, proc.stdout)
    check.expect("BadName:" not in proc.stdout, proc.stdout)


def fixture_description_length(check: Check) -> None:
    def write_len(root: Path, length: int) -> None:
        description = "d" * length
        text = skill_text("tdd", description, "Keep general-purpose mechanism inside the module.\n", True)
        for tree in (".cursor", ".claude", ".agents"):
            write_skill(root, tree, "tdd", text)

    def too_long(root: Path) -> None:
        write_len(root, 1025)

    proc = with_base(too_long)
    check.expect("DescriptionTooLong:" in proc.stdout, proc.stdout)

    def exact(root: Path) -> None:
        write_len(root, 1024)

    proc = with_base(exact)
    check.expect(proc.returncode == 0 and proc.stdout == "", proc.stdout)


def fixture_paths_key(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "skills" / "tdd" / "SKILL.md"
        text = path.read_text(encoding="utf-8").replace(
            "disable-model-invocation: true\n",
            "disable-model-invocation: true\npaths: src\n",
            1,
        )
        for tree in (".cursor", ".claude", ".agents"):
            (root / tree / "skills" / "tdd" / "SKILL.md").write_text(text, encoding="utf-8")

    proc = with_base(mutate)
    check.expect("UnknownFrontmatterKey:" in proc.stdout and "paths" in proc.stdout, proc.stdout)


def fixture_symlink(check: Check) -> None:
    def mutate(root: Path) -> None:
        target = root / ".agents" / "skills" / "tdd" / "SKILL.md"
        link = root / ".agents" / "skills" / "tdd" / "alias.md"
        link.symlink_to(target)

    proc = with_base(mutate)
    check.expect("Symlink:" in proc.stdout, proc.stdout)


def fixture_agents_md(check: Check) -> None:
    def mutate(root: Path) -> None:
        (root / "AGENTS.md").write_text("no\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect("ForbiddenAlwaysOn:" in proc.stdout and "AGENTS.md" in proc.stdout, proc.stdout)


def fixture_rules(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "rules"
        path.mkdir()
        (path / "rule.md").write_text("no\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect("ForbiddenAlwaysOn:" in proc.stdout and ".agents/rules" in proc.stdout, proc.stdout)


def fixture_excluded_present(check: Check) -> None:
    def mutate(root: Path) -> None:
        text = skill_text("setup-pstack", "Configure models.", "Body.\n", True)
        write_skill(root, ".cursor", "setup-pstack", text)
        write_skill(root, ".agents", "setup-pstack", text)
        _append_row(root, roster_line("setup-pstack", "exclude", "cursor", "explicit", "vendored"))

    proc = with_base(mutate)
    check.expect("ExcludedPresent:" in proc.stdout, proc.stdout)


def fixture_mirror_drift(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "skills" / "tdd" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8") + "\nextra\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect("MirrorMismatch:" in proc.stdout, proc.stdout)


def fixture_source_split(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".claude" / "skills" / "tdd" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8") + "\nchanged\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect("MirrorSourceSplit:" in proc.stdout, proc.stdout)


def fixture_stamp(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".cursor" / "skills" / "architect" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8") + "\nchanged\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect("StampMismatch:" in proc.stdout, proc.stdout)


def fixture_openai_missing(check: Check) -> None:
    def mutate(root: Path) -> None:
        (root / ".agents" / "skills" / "tdd" / "agents" / "openai.yaml").unlink()

    proc = with_base(mutate)
    check.expect("OpenAiPolicyMismatch:" in proc.stdout, proc.stdout)


def fixture_named_has_yaml(check: Check) -> None:
    def mutate(root: Path) -> None:
        policy(root, "kitimark-mode")

    proc = with_base(mutate)
    check.expect("OpenAiPolicyMismatch:" in proc.stdout and "kitimark-mode" in proc.stdout, proc.stdout)


def fixture_kitimark_phrase(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "skills" / "kitimark-mode" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8").replace("AGENTS.md", "a root instruction file"), encoding="utf-8")

    proc = with_base(mutate)
    check.expect("KitimarkPhraseMissing:" in proc.stdout, proc.stdout)


def fixture_banned_token(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "skills" / "architect" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8") + "\nRun gh pr merge when green.\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect("BannedToken:" in proc.stdout and "gh pr merge" in proc.stdout, proc.stdout)


def fixture_allowed_sentence(check: Check) -> None:
    def mutate(root: Path) -> None:
        path = root / ".agents" / "skills" / "architect" / "SKILL.md"
        path.write_text(path.read_text(encoding="utf-8") + "\n" + FANOUT + "\n", encoding="utf-8")

    proc = with_base(mutate)
    check.expect(proc.returncode == 0 and proc.stdout == "", proc.stdout)


def fixture_verify_not_exempt(check: Check) -> None:
    def mutate(root: Path) -> None:
        text = skill_text("verify-demo", "Drive the app.", "Launch and look.\n", True)
        write_skill(root, ".agents", "verify-demo", text)
        policy(root, "verify-demo")

    proc = with_base(mutate)
    check.expect("UnrosteredSkill:" in proc.stdout and "verify-demo" in proc.stdout, proc.stdout)


def fixture_unrostered(check: Check) -> None:
    def mutate(root: Path) -> None:
        text = skill_text("extra-skill", "Extra.", "Body.\n", True)
        write_skill(root, ".agents", "extra-skill", text)

    proc = with_base(mutate)
    check.expect("UnrosteredSkill:" in proc.stdout and "extra-skill" in proc.stdout, proc.stdout)


def fixture_sync_preserves_rewrite(check: Check) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        build_base(root)
        skill = root / ".agents" / "skills" / "architect" / "SKILL.md"
        original = skill.read_text(encoding="utf-8")
        skill.write_text(original + "DIRTY-REWRITE\n", encoding="utf-8")
        note = root / ".agents" / "skills" / "architect" / "references" / "note.md"
        note.parent.mkdir()
        note.write_text("DIRTY-NOTE\n", encoding="utf-8")
        first = run(root, "sync")
        check.expect("DIRTY-REWRITE" in skill.read_text(encoding="utf-8"), "rewrite body was overwritten")
        check.expect(note.read_text(encoding="utf-8") == "DIRTY-NOTE\n", "companion was overwritten")
        check.expect(first.returncode == 0, first.stdout)
        before = snapshot(root)
        second = run(root, "sync")
        check.expect(second.returncode == 0 and snapshot(root) == before, "second sync wrote")


def fixture_sync_idempotent(check: Check) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        build_base(root)
        mirror = root / ".agents" / "skills" / "tdd" / "SKILL.md"
        mirror.unlink()
        first = run(root, "sync")
        check.expect(first.returncode == 0 and mirror.is_file(), first.stdout)
        before = snapshot(root)
        second = run(root, "sync")
        check.expect(second.returncode == 0 and snapshot(root) == before, "second sync changed bytes or mtimes")
        check.expect(mirror.read_bytes() == (root / ".cursor" / "skills" / "tdd" / "SKILL.md").read_bytes(), "mirror bytes")


def _append_row(root: Path, line: str) -> None:
    path = root / ".cursor" / "skills" / "agents-roster.tsv"
    path.write_text(path.read_text(encoding="utf-8") + line, encoding="utf-8")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(exc.code, file=sys.stderr)
            sys.exit(1)
        raise
