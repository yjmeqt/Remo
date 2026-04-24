"""Mount manifest management, name derivation, and guest bridge script generation."""

from __future__ import annotations

import contextlib
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path

# Guest-side shared folder root (tart virtiofs mount point).
_SHARED_ROOT = "/Volumes/My Shared Files"


@dataclass(frozen=True)
class MountEntry:
    name: str
    host_path: Path


# ---------------------------------------------------------------------------
# Manifest I/O
# ---------------------------------------------------------------------------


def manifest_read(path: Path) -> list[MountEntry]:
    """Return entries from a manifest file, or [] if the file is absent."""
    if not path.exists():
        return []
    entries: list[MountEntry] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        name, _, host = line.partition("\t")
        if not name or not host:
            continue
        entries.append(MountEntry(name, Path(host)))
    return entries


def manifest_write(path: Path, entries: list[MountEntry]) -> None:
    """Atomically write *entries* to *path*, creating parent dirs as needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    content = "".join(f"{e.name}\t{e.host_path}\n" for e in entries)
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        os.write(fd, content.encode())
        os.close(fd)
        os.replace(tmp, path)
    except Exception:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def manifest_upsert(path: Path, entry: MountEntry) -> list[MountEntry]:
    """Insert or replace *entry* (matched by name), persist, and return the new list."""
    existing = manifest_read(path)
    updated: list[MountEntry] = []
    replaced = False
    for e in existing:
        if e.name == entry.name:
            updated.append(entry)
            replaced = True
        else:
            updated.append(e)
    if not replaced:
        updated.append(entry)
    manifest_write(path, updated)
    return updated


def manifest_remove(path: Path, name: str) -> list[MountEntry]:
    """Remove all entries with *name*, persist, and return the new list."""
    existing = manifest_read(path)
    kept = [e for e in existing if e.name != name]
    manifest_write(path, kept)
    return kept


def manifest_prune_stale(path: Path) -> tuple[list[MountEntry], int]:
    """Remove entries whose host_path does not exist on disk.

    Returns ``(kept_entries, pruned_count)``.
    """
    existing = manifest_read(path)
    kept = [e for e in existing if e.host_path.exists()]
    pruned = len(existing) - len(kept)
    manifest_write(path, kept)
    return kept, pruned


# ---------------------------------------------------------------------------
# Mount name derivation
# ---------------------------------------------------------------------------


def _slugify(text: str) -> str:
    """Lowercase, collapse non-alphanumeric runs to '-', strip leading/trailing '-'."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def mount_name_for_path(project_slug: str, host_path: Path) -> str:
    """Derive a guest mount name from *host_path* following the slug rules.

    1. Take the basename of *host_path*.
    2. Slugify it.
    3. If equal to *project_slug* → return as-is.
    4. If already prefixed with ``<project_slug>-`` → return as-is.
    5. Otherwise → return ``<project_slug>-<slug>``.
    """
    worktree_slug = _slugify(host_path.name)
    if worktree_slug == project_slug:
        return project_slug
    if worktree_slug.startswith(f"{project_slug}-"):
        return worktree_slug
    return f"{project_slug}-{worktree_slug}"


def git_root_bridge_entry(project_slug: str, git_root: Path) -> MountEntry:
    """Return a ``MountEntry`` for the git-root bridge mount."""
    return MountEntry(f"{project_slug}-git-root", git_root)


def parse_mount_spec(project_slug: str, spec: str) -> MountEntry:
    """Parse a mount spec of the form ``host[:name[:guest-root]]``.

    * ``host`` is resolved to an absolute ``Path`` (but need not exist).
    * ``name`` overrides the slug-derived name when provided.
    * A third colon-separated component (guest-root) is accepted but ignored.
    """
    parts = spec.split(":")
    host_path = Path(parts[0]).resolve()
    if len(parts) >= 2 and parts[1]:
        name = parts[1]
    else:
        name = mount_name_for_path(project_slug, host_path)
    return MountEntry(name, host_path)


# ---------------------------------------------------------------------------
# Guest bridge script
# ---------------------------------------------------------------------------


def guest_bridge_script(entries: list[MountEntry], git_root_name: str) -> str:
    """Return a bash script that wires up ``.git`` symlinks inside the guest.

    For each entry in *entries* that is NOT the git-root bridge itself, the
    script creates a symlink:

        /Volumes/My Shared Files/<name>/.git
            → /Volumes/My Shared Files/<git_root_name>

    This mirrors the logic of ``remo_tart_guest_git_root_bridge_script`` in
    ``scripts/tart/common.sh`` (lines 418-450).
    """
    lines: list[str] = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
    ]

    git_root_mount = f"{_SHARED_ROOT}/{git_root_name}"

    for entry in entries:
        if entry.name == git_root_name:
            continue

        guest_git_root = f"{_SHARED_ROOT}/{entry.name}/.git"
        guest_bridge_source = git_root_mount
        guest_git_parent = f"{_SHARED_ROOT}/{entry.name}"

        lines += [
            f"guest_git_root={_shell_quote(guest_git_root)}",
            f"guest_bridge_source={_shell_quote(guest_bridge_source)}",
            f"guest_git_parent={_shell_quote(guest_git_parent)}",
            'if [[ -L "${guest_git_parent}" ]]; then',
            f'    printf "%s\\n" admin | sudo -S rm -f {_shell_quote(guest_git_parent)}',
            "fi",
            'if [[ -e "${guest_git_parent}" && ! -d "${guest_git_parent}" ]]; then',
            '    echo "guest git parent exists and is not a directory: ${guest_git_parent}" >&2',
            "    exit 1",
            "fi",
            'if [[ -L "${guest_git_root}" ]]; then',
            '    current_target="$(readlink "${guest_git_root}")"',
            '    if [[ "${current_target}" == "${guest_bridge_source}" ]]; then',
            "        exit 0",
            "    fi",
            "fi",
            'if [[ -e "${guest_git_root}" && ! -L "${guest_git_root}" ]]; then',
            (
                '    echo "guest git root bridge target already exists'
                ' and is not a symlink: ${guest_git_root}" >&2'
            ),
            "    exit 1",
            "fi",
            f'printf "%s\\n" admin | sudo -S mkdir -p {_shell_quote(guest_git_parent)}',
            (
                f'printf "%s\\n" admin | sudo -S ln -sfn'
                f" {_shell_quote(guest_bridge_source)} {_shell_quote(guest_git_root)}"
            ),
            "",
        ]

    return "\n".join(lines)


def _shell_quote(s: str) -> str:
    """Minimal single-quote shell escaping for paths."""
    return "'" + s.replace("'", "'\\''") + "'"
