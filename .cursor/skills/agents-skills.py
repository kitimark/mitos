#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import re
import stat
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


NAME_RE = re.compile(r"^[a-z0-9-]{1,64}$")
DESCRIPTION_MAX = 1024
HEADER = (
    "name\tclass\tsource\tinvocation\tcursor\tcursor_sha256\tclaude_sha256"
)

FANOUT = (
    "spawn a subagent with your host's tool "
    "(Codex `spawn_agent`, Antigravity `invoke_subagent`, "
    "Cursor `Task`, Claude Code `Agent`); "
    "if none, run the steps one at a time."
)
ASK = "Ask in chat with numbered options."
SKIP = "Cursor-only; skip this step on other hosts."
MODEL = "Inherit the parent model, or the host's default."
ALLOWED_SENTENCES = (FANOUT, ASK, SKIP, MODEL)

CANONICAL_POLICY = "policy:\n  allow_implicit_invocation: false\n"

BANNED_TOKENS = (
    "AskUserQuestion",
    "AskQuestion",
    "generalPurpose",
    "`general-purpose`",
    "subagent_type",
    "run_in_background",
    "pstack-models",
    "api2.cursor.sh",
    "disable-model-invocation",
    "gh pr merge",
    "merge_method",
    "merge-async",
    "`Task`",
    "`Agent`",
    "Bugbot",
)

KEPT_NAMES = (
    "architect",
    "kitimark-mode",
    "no-comments",
    "poteto-mode",
    "principle-split-by-topic",
    "reflect",
    "show-me-your-work",
    "swarm",
)

DIALECT_STAMP_EXTRAS = {
    "no-comments": {
        "cursor": (".cursor/agents/comment-sicko.md",),
        "claude": (".claude/agents/comment-sicko.md",),
    },
}

KITIMARK_PHRASES = (
    "docs/process.md",
    "Never add the label",
    "spec-approved",
    "The owner merges",
    "AGENTS.md",
    "never post a merge command",
)

MERGE_RULE_FILES = (
    ".agents/skills/poteto-mode/playbooks/shipping.md",
    ".agents/skills/poteto-mode/playbooks/autopilot-full.md",
    ".agents/skills/poteto-mode/playbooks/autopilot-stack.md",
    ".agents/skills/poteto-mode/playbooks/babysit.md",
    ".agents/skills/poteto-mode/playbooks/pause-safely.md",
    ".agents/skills/poteto-mode/playbooks/orchestrate.md",
)

FORBIDDEN_PATHS = (
    "AGENTS.md",
    ".agents/rules",
    ".agents/agents",
    ".agents/README.md",
    ".agents/AGENTS.md",
)

POLICY_REL = "agents/openai.yaml"
SLUG_RE = re.compile(
    r"(?<![A-Za-z0-9-])(?:claude-)?(?:opus|sonnet|haiku|fable|grok)"
    r"(?:-[A-Za-z0-9.]+)*(?![A-Za-z0-9-])"
)
MODEL_ASSIGN_RE = re.compile(
    r"(?<![A-Za-z0-9-])model:\s*['\"]?"
    r"(?:opus|sonnet|haiku|fable|grok)(?:-[A-Za-z0-9.]+)*\b"
)
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
SEP_CELL_RE = re.compile(r":?-{3,}:?")


class Class(Enum):
    mirror = "mirror"
    rewrite = "rewrite"
    exclude = "exclude"


class Source(Enum):
    both = "both"
    cursor = "cursor"
    claude = "claude"
    none = "none"


class Invocation(Enum):
    explicit = "explicit"
    named = "named"


class CursorKeep(Enum):
    kept = "kept"
    vendored = "vendored"


class FaultKind(Enum):
    BadName = "BadName"
    NameFolderMismatch = "NameFolderMismatch"
    DescriptionMissing = "DescriptionMissing"
    DescriptionTooLong = "DescriptionTooLong"
    UnknownFrontmatterKey = "UnknownFrontmatterKey"
    InvocationFlagMismatch = "InvocationFlagMismatch"
    OpenAiPolicyMismatch = "OpenAiPolicyMismatch"
    Symlink = "Symlink"
    ExcludedPresent = "ExcludedPresent"
    MirrorMismatch = "MirrorMismatch"
    MirrorSourceSplit = "MirrorSourceSplit"
    RewriteMissing = "RewriteMissing"
    StampMismatch = "StampMismatch"
    UnrosteredSkill = "UnrosteredSkill"
    RosterOrphan = "RosterOrphan"
    RosterInvariant = "RosterInvariant"
    ForbiddenAlwaysOn = "ForbiddenAlwaysOn"
    BannedToken = "BannedToken"
    KitimarkPhraseMissing = "KitimarkPhraseMissing"
    MergeRuleMissing = "MergeRuleMissing"
    ExcludedSkillLink = "ExcludedSkillLink"


@dataclass(frozen=True)
class Fault:
    kind: FaultKind
    path: str
    detail: str


@dataclass(frozen=True)
class RosterRow:
    name: str
    klass: Class
    source: Source
    invocation: Invocation
    cursor: CursorKeep
    cursor_sha256: str | None
    claude_sha256: str | None


@dataclass(frozen=True)
class Roster:
    rows: tuple[RosterRow, ...]


@dataclass(frozen=True)
class SkillFrontmatter:
    name: str | None
    description: str | None
    disable: bool | None
    unknown_keys: tuple[str, ...]
    error: str | None


@dataclass(frozen=True)
class FileEntry:
    rel: str
    data: bytes
    mode: int


class SyncAction:
    pass


@dataclass(frozen=True)
class ExcludeDelete(SyncAction):
    name: str


@dataclass(frozen=True)
class MirrorCopy(SyncAction):
    name: str
    source_dir: str


@dataclass(frozen=True)
class PolicyWrite(SyncAction):
    name: str
    present: bool


def render_fault(fault: Fault) -> str:
    detail = fault.detail.replace("\n", " ").replace("\r", " ")
    return f"{fault.kind.value}: {fault.path}: {detail}"


def roster_path(root: Path) -> Path:
    return root / ".cursor" / "skills" / "agents-roster.tsv"


def _hash_cell(cell: str) -> str | None | Fault:
    if cell == "-":
        return None
    if HASH_RE.fullmatch(cell):
        return cell
    return Fault(FaultKind.RosterInvariant, "agents-roster.tsv", f"bad hash {cell!r}")


def load_roster(path: Path) -> Roster | list[Fault]:
    if not path.is_file() or path.is_symlink():
        return [Fault(FaultKind.RosterInvariant, _rel(path), "roster is missing")]
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != HEADER:
        return [
            Fault(
                FaultKind.RosterInvariant,
                _rel(path),
                "header must be the seven roster columns",
            )
        ]
    rows: list[RosterRow] = []
    faults: list[Fault] = []
    seen: set[str] = set()
    for lineno, line in enumerate(lines[1:], start=2):
        if line == "":
            continue
        parts = line.split("\t")
        if len(parts) != 7:
            faults.append(
                Fault(
                    FaultKind.RosterInvariant,
                    _rel(path),
                    f"line {lineno} does not have 7 columns",
                )
            )
            continue
        name, klass, source, invocation, cursor, cursor_hash, claude_hash = parts
        if name in seen:
            faults.append(
                Fault(FaultKind.RosterInvariant, _rel(path), f"duplicate name {name}")
            )
            continue
        seen.add(name)
        try:
            klass_e = Class(klass)
            source_e = Source(source)
            invocation_e = Invocation(invocation)
            cursor_e = CursorKeep(cursor)
        except ValueError:
            faults.append(
                Fault(
                    FaultKind.RosterInvariant,
                    _rel(path),
                    f"line {lineno} has a bad class, source, invocation, or cursor",
                )
            )
            continue
        cursor_sha = _hash_cell(cursor_hash)
        claude_sha = _hash_cell(claude_hash)
        if isinstance(cursor_sha, Fault) or isinstance(claude_sha, Fault):
            bad = cursor_sha if isinstance(cursor_sha, Fault) else claude_sha
            assert isinstance(bad, Fault)
            faults.append(
                Fault(bad.kind, _rel(path), f"line {lineno}: {bad.detail}")
            )
            continue
        row = RosterRow(
            name, klass_e, source_e, invocation_e, cursor_e, cursor_sha, claude_sha
        )
        shape = _row_shape(row)
        if shape is not None:
            faults.append(Fault(FaultKind.RosterInvariant, _rel(path), f"line {lineno}: {shape}"))
            continue
        rows.append(row)
    if faults:
        return faults
    kept = tuple(row.name for row in rows if row.cursor is CursorKeep.kept)
    if set(kept) != set(KEPT_NAMES) or len(kept) != len(KEPT_NAMES):
        faults.append(
            Fault(
                FaultKind.RosterInvariant,
                _rel(path),
                "cursor=kept must be exactly the eight resync names",
            )
        )
    named = [row for row in rows if row.invocation is Invocation.named]
    if len(named) != 1 or named[0].name != "kitimark-mode" or named[0].klass is not Class.rewrite:
        faults.append(
            Fault(
                FaultKind.RosterInvariant,
                _rel(path),
                "named invocation is only the rewrite row kitimark-mode",
            )
        )
    if any(row.name == "verify-*" for row in rows):
        faults.append(
            Fault(
                FaultKind.RosterInvariant,
                _rel(path),
                "verify-* is not a roster pattern",
            )
        )
    if faults:
        return faults
    return Roster(tuple(rows))


def _row_shape(row: RosterRow) -> str | None:
    empty = row.cursor_sha256 is None and row.claude_sha256 is None
    if row.klass is Class.mirror:
        if row.source not in (Source.both, Source.cursor, Source.claude):
            return "mirror source must be both, cursor, or claude"
        if not empty:
            return "mirror rows do not carry a stamp hash"
    elif row.klass is Class.rewrite:
        if row.source is not Source.none:
            return "rewrite source must be none"
    elif row.klass is Class.exclude:
        if row.source is not Source.cursor or row.invocation is not Invocation.explicit:
            return "exclude rows are cursor and explicit"
        if row.cursor is not CursorKeep.vendored:
            return "exclude rows are vendored"
        if not empty:
            return "exclude rows do not carry a stamp hash"
    return None


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def parse_frontmatter(text: str) -> SkillFrontmatter:
    if not text.startswith("---\n"):
        return SkillFrontmatter(None, None, None, (), "frontmatter is missing")
    end = text.find("\n---\n", 4)
    if end < 0:
        return SkillFrontmatter(None, None, None, (), "frontmatter is unclosed")
    block = text[4:end]
    lines = block.split("\n")
    data: dict[str, object] = {}
    unknown: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip() == "":
            i += 1
            continue
        match = re.match(r"^([A-Za-z0-9-]+):[ \t]*(.*)$", line)
        if match is None:
            return SkillFrontmatter(None, None, None, (), f"cannot parse {line!r}")
        key, rest = match.group(1), match.group(2)
        if key in data or key in unknown:
            return SkillFrontmatter(None, None, None, (), f"duplicate key {key}")
        if rest in (">", ">-", "|", "|-"):
            i += 1
            chunk: list[str] = []
            while i < len(lines) and (lines[i].startswith((" ", "\t")) or lines[i] == ""):
                chunk.append(lines[i])
                i += 1
            value = _fold_block(chunk, rest)
        elif rest == "":
            return SkillFrontmatter(None, None, None, (), f"empty value for {key}")
        elif rest.startswith('"'):
            try:
                value = _unquote_double(rest)
            except ValueError as exc:
                return SkillFrontmatter(None, None, None, (), str(exc))
            i += 1
        elif rest.startswith("'"):
            try:
                value = _unquote_single(rest)
            except ValueError as exc:
                return SkillFrontmatter(None, None, None, (), str(exc))
            i += 1
        else:
            value = rest.strip()
            i += 1
        if key == "name":
            data[key] = value
        elif key == "description":
            data[key] = value
        elif key == "disable-model-invocation":
            data[key] = value == "true"
        else:
            unknown.append(key)
    disable = data.get("disable-model-invocation")
    return SkillFrontmatter(
        data.get("name") if isinstance(data.get("name"), str) else None,
        data.get("description") if isinstance(data.get("description"), str) else None,
        disable if isinstance(disable, bool) else None,
        tuple(unknown),
        None,
    )


def _fold_block(chunk: list[str], style: str) -> str:
    if not chunk:
        text = ""
    else:
        indents = [len(line) - len(line.lstrip(" \t")) for line in chunk if line.strip()]
        margin = min(indents) if indents else 0
        stripped = [(line[margin:] if line.startswith(" " * margin) else line.lstrip(" \t")) for line in chunk]
        if style.startswith(">"):
            paragraphs: list[str] = []
            current: list[str] = []
            for line in stripped:
                if line.strip() == "":
                    if current:
                        paragraphs.append(" ".join(current))
                        current = []
                else:
                    current.append(line.strip())
            if current:
                paragraphs.append(" ".join(current))
            text = "\n".join(paragraphs)
            if style == ">":
                text += "\n"
        else:
            text = "\n".join(stripped)
            if style == "|" and text != "":
                text += "\n"
    return text


def _unquote_double(token: str) -> str:
    if len(token) < 2 or not token.endswith('"'):
        raise ValueError("unterminated double quote")
    inner = token[1:-1]
    out: list[str] = []
    i = 0
    while i < len(inner):
        char = inner[i]
        if char == "\\":
            if i + 1 >= len(inner):
                raise ValueError("bad escape")
            nxt = inner[i + 1]
            mapped = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt)
            if mapped is None:
                raise ValueError(f"bad escape \\{nxt}")
            out.append(mapped)
            i += 2
            continue
        if char == '"':
            raise ValueError("unescaped quote")
        out.append(char)
        i += 1
    return "".join(out)


def _unquote_single(token: str) -> str:
    if len(token) < 2 or not token.endswith("'"):
        raise ValueError("unterminated single quote")
    inner = token[1:-1]
    if re.search(r"(?<!')'(?!')", inner):
        raise ValueError("unescaped single quote")
    return inner.replace("''", "'")


def tree_sha256(files: tuple[tuple[str, bytes], ...]) -> str:
    digest = hashlib.sha256()
    for rel, data in sorted(files, key=lambda item: item[0]):
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        digest.update(data)
    return digest.hexdigest()


def _walk(base: Path) -> tuple[list[FileEntry], list[Fault]]:
    files: list[FileEntry] = []
    faults: list[Fault] = []
    if base.is_symlink():
        return files, [Fault(FaultKind.Symlink, base.as_posix(), "symlink")]
    if not base.exists():
        return files, []
    for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
        current = Path(dirpath)
        kept_dirs: list[str] = []
        for name in dirnames:
            path = current / name
            if path.is_symlink():
                faults.append(Fault(FaultKind.Symlink, path.as_posix(), "symlink"))
            else:
                kept_dirs.append(name)
        dirnames[:] = kept_dirs
        for name in filenames:
            path = current / name
            rel = path.relative_to(base).as_posix()
            if path.is_symlink():
                faults.append(Fault(FaultKind.Symlink, path.as_posix(), "symlink"))
                continue
            if not path.is_file():
                continue
            mode = stat.S_IMODE(path.stat().st_mode)
            files.append(FileEntry(rel, path.read_bytes(), mode))
    return files, faults


def dialect_dir(root: Path, side: str, name: str) -> Path:
    tree = ".cursor" if side == "cursor" else ".claude"
    return root / tree / "skills" / name


def dialect_payload(root: Path, name: str, side: str) -> tuple[tuple[tuple[str, bytes], ...] | None, list[Fault]]:
    directory = dialect_dir(root, side, name)
    if not directory.exists() and not directory.is_symlink():
        return None, []
    files, faults = _walk(directory)
    if directory.is_symlink():
        return None, faults
    payload = [(entry.rel, entry.data) for entry in files]
    for rel in DIALECT_STAMP_EXTRAS.get(name, {}).get(side, ()):
        path = root / rel
        if path.is_symlink() or not path.is_file():
            faults.append(
                Fault(FaultKind.StampMismatch, rel, "dialect stamp file is missing")
            )
            continue
        payload.append((rel, path.read_bytes()))
    return tuple(payload), faults


def cursor_skill_names(root: Path) -> tuple[list[str], list[Fault]]:
    base = root / ".cursor" / "skills"
    names: list[str] = []
    faults: list[Fault] = []
    if not base.is_dir() or base.is_symlink():
        return names, [Fault(FaultKind.RosterInvariant, ".cursor/skills", "skills directory is missing")]
    for child in sorted(base.iterdir(), key=lambda item: item.name):
        if child.is_symlink():
            faults.append(Fault(FaultKind.Symlink, f".cursor/skills/{child.name}", "symlink"))
            continue
        if child.is_dir() and (child / "SKILL.md").is_file() and not (child / "SKILL.md").is_symlink():
            names.append(child.name)
    return names, faults


def evaluate(root: Path) -> tuple[Fault, ...]:
    loaded = load_roster(roster_path(root))
    if isinstance(loaded, list):
        return tuple(loaded)
    roster = loaded
    faults: list[Fault] = []
    excluded = {row.name for row in roster.rows if row.klass is Class.exclude}
    names, walk_faults = cursor_skill_names(root)
    faults.extend(walk_faults)
    by_name = {row.name: row for row in roster.rows}
    for name in names:
        if name not in by_name:
            faults.append(
                Fault(FaultKind.UnrosteredSkill, f".cursor/skills/{name}", "no roster row")
            )
    for row in roster.rows:
        if row.name not in names:
            faults.append(
                Fault(FaultKind.RosterOrphan, f".cursor/skills/{row.name}", "no SKILL.md")
            )
    faults.extend(_forbidden(root))
    faults.extend(_agents_shape(root, roster))
    for row in roster.rows:
        faults.extend(_row_tree(root, row, excluded))
    return tuple(faults)


def _forbidden(root: Path) -> list[Fault]:
    faults: list[Fault] = []
    for rel in FORBIDDEN_PATHS:
        path = root / rel
        if path.is_symlink() or path.exists():
            faults.append(Fault(FaultKind.ForbiddenAlwaysOn, rel, "forbidden path"))
    return faults


def _agents_shape(root: Path, roster: Roster) -> list[Fault]:
    faults: list[Fault] = []
    agents = root / ".agents"
    if not agents.exists() and not agents.is_symlink():
        return faults
    if agents.is_symlink():
        return [Fault(FaultKind.Symlink, ".agents", "symlink")]
    if not agents.is_dir():
        return [Fault(FaultKind.ForbiddenAlwaysOn, ".agents", "not a directory")]
    known = {row.name: row for row in roster.rows}
    for child in sorted(agents.iterdir(), key=lambda item: item.name):
        rel = f".agents/{child.name}"
        if child.is_symlink():
            faults.append(Fault(FaultKind.Symlink, rel, "symlink"))
            continue
        if child.name != "skills":
            faults.append(Fault(FaultKind.ForbiddenAlwaysOn, rel, "only skills/ is allowed"))
    skills = agents / "skills"
    if skills.is_symlink():
        faults.append(Fault(FaultKind.Symlink, ".agents/skills", "symlink"))
        return faults
    if not skills.is_dir():
        return faults
    for child in sorted(skills.iterdir(), key=lambda item: item.name):
        rel = f".agents/skills/{child.name}"
        if child.is_symlink():
            faults.append(Fault(FaultKind.Symlink, rel, "symlink"))
            continue
        if not child.is_dir():
            faults.append(Fault(FaultKind.UnrosteredSkill, rel, "not a skill directory"))
            continue
        row = known.get(child.name)
        if row is None:
            faults.append(Fault(FaultKind.UnrosteredSkill, rel, "no roster row"))
            continue
        if row.klass is Class.exclude:
            faults.append(Fault(FaultKind.ExcludedPresent, rel, "exclude class has a neutral directory"))
        nested, nested_faults = _walk(child)
        faults.extend(
            Fault(item.kind, _under_root(root, item.path), item.detail) for item in nested_faults
        )
        for entry in nested:
            if entry.rel == "AGENTS.md" or entry.rel.endswith("/AGENTS.md"):
                faults.append(
                    Fault(
                        FaultKind.ForbiddenAlwaysOn,
                        f"{rel}/{entry.rel}",
                        "forbidden path",
                    )
                )
    return faults


def _row_tree(root: Path, row: RosterRow, excluded: set[str]) -> list[Fault]:
    faults: list[Fault] = []
    if row.klass is Class.exclude:
        return faults
    cursor_payload, cursor_faults = dialect_payload(root, row.name, "cursor")
    claude_payload, claude_faults = dialect_payload(root, row.name, "claude")
    faults.extend(_retag(cursor_faults, root))
    faults.extend(_retag(claude_faults, root))
    if row.klass is Class.mirror:
        faults.extend(_mirror_source(root, row, cursor_payload, claude_payload))
    elif row.klass is Class.rewrite:
        faults.extend(_stamp(row, cursor_payload, claude_payload))
    neutral = root / ".agents" / "skills" / row.name
    if row.klass is Class.mirror:
        faults.extend(_mirror_dest(root, row, neutral))
    elif not (neutral / "SKILL.md").is_file() or (neutral / "SKILL.md").is_symlink():
        faults.append(
            Fault(FaultKind.RewriteMissing, f".agents/skills/{row.name}/SKILL.md", "missing rewrite body")
        )
    if (neutral / "SKILL.md").is_file() and not (neutral / "SKILL.md").is_symlink():
        faults.extend(_skill_text(root, row, neutral, excluded))
    faults.extend(_policy(row, neutral))
    return faults


def _retag(faults: list[Fault], root: Path) -> list[Fault]:
    out: list[Fault] = []
    for fault in faults:
        path = fault.path
        try:
            path = Path(fault.path).resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            path = fault.path
        out.append(Fault(fault.kind, path, fault.detail))
    return out


def _mirror_source(
    root: Path,
    row: RosterRow,
    cursor_payload: tuple[tuple[str, bytes], ...] | None,
    claude_payload: tuple[tuple[str, bytes], ...] | None,
) -> list[Fault]:
    faults: list[Fault] = []
    cursor_here = cursor_payload is not None
    claude_here = claude_payload is not None
    if row.source is Source.both:
        if not cursor_here or not claude_here:
            faults.append(
                Fault(
                    FaultKind.MirrorSourceSplit,
                    f".cursor/skills/{row.name}",
                    "source=both needs both dialect directories",
                )
            )
        elif _body_map(cursor_payload) != _body_map(claude_payload):
            faults.append(
                Fault(
                    FaultKind.MirrorSourceSplit,
                    f".cursor/skills/{row.name}",
                    "dialect directories differ",
                )
            )
    elif row.source is Source.cursor:
        if not cursor_here:
            faults.append(
                Fault(FaultKind.MirrorSourceSplit, f".cursor/skills/{row.name}", "cursor source is missing")
            )
        if claude_here:
            faults.append(
                Fault(
                    FaultKind.MirrorSourceSplit,
                    f".claude/skills/{row.name}",
                    "source=cursor but the Claude directory exists",
                )
            )
    elif row.source is Source.claude:
        if not claude_here:
            faults.append(
                Fault(FaultKind.MirrorSourceSplit, f".claude/skills/{row.name}", "claude source is missing")
            )
    return faults


def _body_map(payload: tuple[tuple[str, bytes], ...] | None) -> dict[str, bytes]:
    if payload is None:
        return {}
    return {rel: data for rel, data in payload if not rel.startswith(".cursor/") and not rel.startswith(".claude/")}


def _stamp(
    row: RosterRow,
    cursor_payload: tuple[tuple[str, bytes], ...] | None,
    claude_payload: tuple[tuple[str, bytes], ...] | None,
) -> list[Fault]:
    faults: list[Fault] = []
    if cursor_payload is None:
        faults.append(
            Fault(FaultKind.StampMismatch, f".cursor/skills/{row.name}", "cursor dialect is missing")
        )
    else:
        digest = tree_sha256(cursor_payload)
        if digest != row.cursor_sha256:
            faults.append(
                Fault(
                    FaultKind.StampMismatch,
                    f".cursor/skills/{row.name}",
                    "cursor stamp does not match the dialect bytes",
                )
            )
    if claude_payload is None:
        if row.claude_sha256 is not None:
            faults.append(
                Fault(
                    FaultKind.StampMismatch,
                    f".claude/skills/{row.name}",
                    "claude stamp is set but the directory is absent",
                )
            )
    else:
        digest = tree_sha256(claude_payload)
        if digest != row.claude_sha256:
            faults.append(
                Fault(
                    FaultKind.StampMismatch,
                    f".claude/skills/{row.name}",
                    "claude stamp does not match the dialect bytes",
                )
            )
    return faults


def mirror_source_dir(root: Path, row: RosterRow) -> Path | None:
    if row.source is Source.claude:
        return dialect_dir(root, "claude", row.name)
    if row.source is Source.cursor:
        return dialect_dir(root, "cursor", row.name)
    if row.source is Source.both:
        return dialect_dir(root, "claude", row.name)
    return None


def _mirror_dest(root: Path, row: RosterRow, neutral: Path) -> list[Fault]:
    source = mirror_source_dir(root, row)
    if source is None or not source.is_dir() or source.is_symlink():
        return [
            Fault(
                FaultKind.MirrorMismatch,
                f".agents/skills/{row.name}",
                "mirror source is missing",
            )
        ]
    src_files, src_faults = _walk(source)
    if src_faults:
        return [
            Fault(FaultKind.Symlink, f".agents/skills/{row.name}", "mirror source contains a symlink")
        ]
    if not neutral.is_dir() or neutral.is_symlink():
        return [
            Fault(FaultKind.MirrorMismatch, f".agents/skills/{row.name}", "neutral directory is missing")
        ]
    dest_files, _dest_faults = _walk(neutral)
    faults: list[Fault] = []
    src_map = {entry.rel: entry.data for entry in src_files if entry.rel != POLICY_REL}
    dest_map = {entry.rel: entry.data for entry in dest_files if entry.rel != POLICY_REL}
    if src_map != dest_map:
        missing = sorted(set(src_map) - set(dest_map))
        extra = sorted(set(dest_map) - set(src_map))
        changed = sorted(rel for rel in set(src_map) & set(dest_map) if src_map[rel] != dest_map[rel])
        detail = "bytes differ"
        if missing:
            detail = f"missing {missing[0]}"
        elif extra:
            detail = f"extra {extra[0]}"
        elif changed:
            detail = f"changed {changed[0]}"
        faults.append(Fault(FaultKind.MirrorMismatch, f".agents/skills/{row.name}", detail))
    return faults


def _under_root(root: Path, path: str) -> str:
    candidate = Path(path)
    try:
        return candidate.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path


def _skill_text(root: Path, row: RosterRow, neutral: Path, excluded: set[str]) -> list[Fault]:
    faults: list[Fault] = []
    skill = neutral / "SKILL.md"
    text = skill.read_text(encoding="utf-8")
    front = parse_frontmatter(text)
    rel = f".agents/skills/{row.name}/SKILL.md"
    if front.error is not None:
        faults.append(Fault(FaultKind.DescriptionMissing, rel, front.error))
    else:
        if front.name is None:
            faults.append(Fault(FaultKind.BadName, rel, "name is missing"))
        elif not NAME_RE.fullmatch(front.name):
            faults.append(Fault(FaultKind.BadName, rel, "name is not a lowercase skill slug"))
        if front.name is not None and front.name != row.name:
            faults.append(
                Fault(FaultKind.NameFolderMismatch, rel, f"name {front.name} does not match {row.name}")
            )
        if front.description is None:
            faults.append(Fault(FaultKind.DescriptionMissing, rel, "description is missing"))
        elif front.description == "":
            faults.append(Fault(FaultKind.DescriptionMissing, rel, "description is empty"))
        elif len(front.description) > DESCRIPTION_MAX:
            faults.append(
                Fault(
                    FaultKind.DescriptionTooLong,
                    rel,
                    f"description is {len(front.description)} characters",
                )
            )
        for key in front.unknown_keys:
            faults.append(Fault(FaultKind.UnknownFrontmatterKey, rel, key))
        if row.invocation is Invocation.explicit and front.disable is not True:
            faults.append(
                Fault(
                    FaultKind.InvocationFlagMismatch,
                    rel,
                    "explicit skills set disable-model-invocation: true",
                )
            )
        if row.invocation is Invocation.named and front.disable is not None:
            faults.append(
                Fault(
                    FaultKind.InvocationFlagMismatch,
                    rel,
                    "named skills omit disable-model-invocation",
                )
            )
    if row.name == "kitimark-mode":
        for phrase in KITIMARK_PHRASES:
            if phrase not in text:
                faults.append(
                    Fault(FaultKind.KitimarkPhraseMissing, rel, f"missing {phrase}")
                )
    faults.extend(_scan_tree(root, row, neutral, excluded))
    return faults


def _scan_tree(root: Path, row: RosterRow, neutral: Path, excluded: set[str]) -> list[Fault]:
    faults: list[Fault] = []
    files, _walk_faults = _walk(neutral)
    for entry in files:
        rel = f".agents/skills/{row.name}/{entry.rel}"
        try:
            text = entry.data.decode("utf-8")
        except UnicodeError:
            text = entry.data.decode("utf-8", "replace")
        body = text
        if entry.rel == "SKILL.md":
            body = _body_after_frontmatter(text)
        for sentence in ALLOWED_SENTENCES:
            body = body.replace(sentence, "")
        seen: set[str] = set()
        for token in sorted(BANNED_TOKENS, key=len, reverse=True):
            if token in body and token not in seen:
                seen.add(token)
                faults.append(Fault(FaultKind.BannedToken, rel, token))
                body = body.replace(token, "")
        for match in re.finditer(r"`([^`]+)`", body):
            if SLUG_RE.search(match.group(1)):
                faults.append(
                    Fault(FaultKind.BannedToken, rel, f"model slug `{match.group(1)}`")
                )
                break
        assign = MODEL_ASSIGN_RE.search(body)
        if assign is not None:
            faults.append(Fault(FaultKind.BannedToken, rel, assign.group(0)))
        faults.extend(_role_table(rel, body))
        for name in sorted(excluded):
            if _excluded_link(body, name):
                faults.append(Fault(FaultKind.ExcludedSkillLink, rel, name))
                break
    return faults


def _excluded_link(text: str, name: str) -> bool:
    pattern = re.compile(
        rf"(?:^|[\s`(\[])/{re.escape(name)}\b"
        rf"|`{re.escape(name)}`"
        rf"|skills/{re.escape(name)}\b"
    )
    return pattern.search(text) is not None


def _role_table(rel: str, text: str) -> list[Fault]:
    lines = text.splitlines()
    faults: list[Fault] = []
    for index, line in enumerate(lines[:-1]):
        if not line.strip().startswith("|"):
            continue
        headers = _cells(line)
        if not headers or not _is_separator(lines[index + 1]):
            continue
        normalized = [cell.strip().strip("`").casefold() for cell in headers]
        if "model" not in normalized:
            continue
        column = normalized.index("model")
        for row in lines[index + 2 :]:
            if not row.strip().startswith("|") or _is_separator(row):
                break
            cells = _cells(row)
            if column >= len(cells):
                continue
            if SLUG_RE.search(cells[column]):
                faults.append(
                    Fault(FaultKind.BannedToken, rel, "role-table model column")
                )
                return faults
    return faults


def _cells(line: str) -> list[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [cell.strip() for cell in stripped.split("|")]


def _is_separator(line: str) -> bool:
    cells = _cells(line)
    return bool(cells) and all(SEP_CELL_RE.fullmatch(cell.replace(" ", "")) for cell in cells)


def _body_after_frontmatter(text: str) -> str:
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end >= 0:
            return text[end + len("\n---\n") :]
    return text


def _policy(row: RosterRow, neutral: Path) -> list[Fault]:
    path = neutral / "agents" / "openai.yaml"
    rel = f".agents/skills/{row.name}/{POLICY_REL}"
    agents_dir = neutral / "agents"
    faults: list[Fault] = []
    if agents_dir.is_dir() and not agents_dir.is_symlink():
        for child in agents_dir.iterdir():
            if child.name != "openai.yaml":
                faults.append(
                    Fault(
                        FaultKind.OpenAiPolicyMismatch,
                        f".agents/skills/{row.name}/agents/{child.name}",
                        "unexpected file",
                    )
                )
    if row.invocation is Invocation.named:
        if path.exists() or path.is_symlink():
            faults.append(Fault(FaultKind.OpenAiPolicyMismatch, rel, "named skill has openai.yaml"))
        return faults
    if path.is_symlink():
        faults.append(Fault(FaultKind.Symlink, rel, "symlink"))
        return faults
    if not path.is_file():
        faults.append(Fault(FaultKind.OpenAiPolicyMismatch, rel, "missing openai.yaml"))
        return faults
    data = path.read_bytes()
    if data != CANONICAL_POLICY.encode("utf-8"):
        faults.append(Fault(FaultKind.OpenAiPolicyMismatch, rel, "openai.yaml is not the canonical policy"))
    return faults


def _merge_rules(root: Path) -> list[Fault]:
    playbooks = root / ".agents" / "skills" / "poteto-mode" / "playbooks"
    if not playbooks.is_dir() or playbooks.is_symlink():
        return []
    faults: list[Fault] = []
    for rel in MERGE_RULE_FILES:
        path = root / rel
        if not path.is_file() or path.is_symlink():
            faults.append(Fault(FaultKind.MergeRuleMissing, rel, "playbook is missing"))
            continue
        text = path.read_text(encoding="utf-8")
        if "docs/process.md" not in text or "never post a merge command" not in text:
            faults.append(
                Fault(
                    FaultKind.MergeRuleMissing,
                    rel,
                    "playbook must defer merge to docs/process.md",
                )
            )
    return faults


def plan_sync(root: Path) -> tuple[SyncAction, ...] | tuple[Fault, ...]:
    loaded = load_roster(roster_path(root))
    if isinstance(loaded, list):
        return tuple(loaded)
    faults: list[Fault] = []
    actions: list[SyncAction] = []
    for row in loaded.rows:
        if row.klass is Class.exclude:
            actions.append(ExcludeDelete(row.name))
            continue
        if row.klass is Class.mirror:
            cursor_payload, cursor_faults = dialect_payload(root, row.name, "cursor")
            claude_payload, claude_faults = dialect_payload(root, row.name, "claude")
            faults.extend(cursor_faults)
            faults.extend(claude_faults)
            faults.extend(_mirror_source(root, row, cursor_payload, claude_payload))
            source = mirror_source_dir(root, row)
            if source is not None:
                actions.append(MirrorCopy(row.name, str(source)))
        neutral = root / ".agents" / "skills" / row.name
        if row.invocation is Invocation.explicit:
            if row.klass is Class.mirror or neutral.is_dir():
                actions.append(PolicyWrite(row.name, True))
        else:
            actions.append(PolicyWrite(row.name, False))
    if faults:
        return tuple(faults)
    return tuple(actions)


def apply_sync(root: Path, plan: tuple[SyncAction, ...]) -> None:
    for action in plan:
        if isinstance(action, MirrorCopy):
            _apply_mirror(root, action)
        elif isinstance(action, PolicyWrite):
            _apply_policy(root, action)
        elif isinstance(action, ExcludeDelete):
            _apply_exclude(root, action)
        else:
            raise RuntimeError("sync has no rewrite-body action")


def _apply_mirror(root: Path, action: MirrorCopy) -> None:
    source = Path(action.source_dir)
    dest = root / ".agents" / "skills" / action.name
    files, faults = _walk(source)
    if faults:
        return
    dest.mkdir(parents=True, exist_ok=True)
    desired = {entry.rel: entry for entry in files if entry.rel != POLICY_REL}
    for entry in desired.values():
        _write_file(dest / entry.rel, entry.data, entry.mode)
    existing, _existing_faults = _walk(dest)
    for entry in existing:
        if entry.rel == POLICY_REL or entry.rel in desired:
            continue
        path = dest / entry.rel
        if path.is_symlink() or path.is_file():
            path.unlink()
    _prune_empty(dest)


def _apply_policy(root: Path, action: PolicyWrite) -> None:
    path = root / ".agents" / "skills" / action.name / "agents" / "openai.yaml"
    if action.present:
        _write_file(path, CANONICAL_POLICY.encode("utf-8"), 0o644)
        return
    if path.is_symlink() or path.is_file():
        path.unlink()
    agents = path.parent
    if agents.is_dir() and not agents.is_symlink() and not any(agents.iterdir()):
        agents.rmdir()


def _apply_exclude(root: Path, action: ExcludeDelete) -> None:
    path = root / ".agents" / "skills" / action.name
    if path.is_symlink() or path.exists():
        _remove_tree(path)


def _write_file(path: Path, data: bytes, mode: int) -> None:
    if path.is_symlink():
        path.unlink()
    elif path.is_dir():
        _remove_tree(path)
    elif path.is_file():
        current = path.stat()
        if path.read_bytes() == data and stat.S_IMODE(current.st_mode) == (mode & 0o777):
            return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f".{path.name}.agents-tmp"
    temporary.write_bytes(data)
    os.chmod(temporary, mode & 0o777)
    os.replace(temporary, path)


def _remove_tree(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
        return
    if not path.is_dir():
        return
    for child in path.iterdir():
        _remove_tree(child)
    path.rmdir()


def _prune_empty(path: Path) -> None:
    directories = [item for item in path.rglob("*") if item.is_dir() and not item.is_symlink()]
    for directory in sorted(directories, key=lambda item: len(item.parts), reverse=True):
        if directory != path and not any(directory.iterdir()):
            directory.rmdir()


def kept_names(roster: Roster) -> tuple[str, ...]:
    return tuple(row.name for row in roster.rows if row.cursor is CursorKeep.kept)


def stamp_roster(root: Path, roster: Roster) -> Roster:
    stamped: list[RosterRow] = []
    for row in roster.rows:
        if row.klass is not Class.rewrite:
            stamped.append(row)
            continue
        cursor_payload, cursor_faults = dialect_payload(root, row.name, "cursor")
        claude_payload, claude_faults = dialect_payload(root, row.name, "claude")
        if cursor_faults or claude_faults or cursor_payload is None:
            missing = cursor_faults or claude_faults
            detail = missing[0].detail if missing else "cursor dialect is missing"
            raise SystemExit(f"StampMismatch: .cursor/skills/{row.name}: {detail}")
        cursor_hash = tree_sha256(tuple(cursor_payload))
        claude_hash = None
        if claude_payload is not None:
            claude_hash = tree_sha256(tuple(claude_payload))
        stamped.append(
            RosterRow(
                row.name,
                row.klass,
                row.source,
                row.invocation,
                row.cursor,
                cursor_hash,
                claude_hash,
            )
        )
    return Roster(tuple(stamped))


def render_roster(roster: Roster) -> str:
    lines = [HEADER]
    for row in roster.rows:
        lines.append(
            "\t".join(
                (
                    row.name,
                    row.klass.value,
                    row.source.value,
                    row.invocation.value,
                    row.cursor.value,
                    row.cursor_sha256 or "-",
                    row.claude_sha256 or "-",
                )
            )
        )
    return "\n".join(lines) + "\n"


def _root_from(argv: list[str]) -> tuple[Path, list[str]] | None:
    if "--root" not in argv:
        completed = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            return None
        return Path(completed.stdout.strip()), argv
    index = argv.index("--root")
    if index + 1 >= len(argv):
        return None
    root = Path(argv[index + 1])
    rest = argv[:index] + argv[index + 2 :]
    if rest:
        return None
    return root, []


def _print_faults(faults: tuple[Fault, ...]) -> None:
    for fault in faults:
        print(render_fault(fault))


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in {"check", "sync", "kept", "stamp"}:
        return 2
    command = argv[0]
    parsed = _root_from(argv[1:])
    if parsed is None:
        return 2
    root, rest = parsed
    if rest or not root.is_dir():
        return 2
    if command == "check":
        loaded = load_roster(roster_path(root))
        if isinstance(loaded, list):
            _print_faults(tuple(loaded))
            return 1
        faults = evaluate(root) + tuple(_merge_rules(root))
        _print_faults(faults)
        return 1 if faults else 0
    if command == "sync":
        plan = plan_sync(root)
        if plan and isinstance(plan[0], Fault):
            _print_faults(tuple(item for item in plan if isinstance(item, Fault)))
            return 1
        apply_sync(root, tuple(item for item in plan if isinstance(item, SyncAction)))
        faults = evaluate(root) + tuple(_merge_rules(root))
        _print_faults(faults)
        return 1 if faults else 0
    if command == "kept":
        loaded = load_roster(roster_path(root))
        if isinstance(loaded, list):
            _print_faults(tuple(loaded))
            return 1
        for name in kept_names(loaded):
            print(name)
        return 0
    loaded = load_roster(roster_path(root))
    if isinstance(loaded, list):
        _print_faults(tuple(loaded))
        return 1
    try:
        stamped = stamp_roster(root, loaded)
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return 1
    rendered = render_roster(stamped)
    path = roster_path(root)
    if not path.is_file() or path.read_text(encoding="utf-8") != rendered:
        _write_file(path, rendered.encode("utf-8"), 0o644)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
