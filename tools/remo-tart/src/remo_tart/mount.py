"""Mount manifest management and name derivation."""

from __future__ import annotations

import contextlib
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path


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
    if not path.exists():
        return []
    existing = manifest_read(path)
    kept = [e for e in existing if e.name != name]
    manifest_write(path, kept)
    return kept


def manifest_prune_stale(path: Path) -> tuple[list[MountEntry], int]:
    """Remove entries whose host_path does not exist on disk.

    Returns ``(kept_entries, pruned_count)``.
    """
    if not path.exists():
        return [], 0
    existing = manifest_read(path)
    kept = [e for e in existing if e.host_path.is_dir()]
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
