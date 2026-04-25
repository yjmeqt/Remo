"""Aggregate VM/mount/SSH/launchd state into a dict; render human or JSON."""

from __future__ import annotations

import json
from pathlib import Path

from remo_tart import launchd, vm
from remo_tart.mount import manifest_read
from remo_tart.paths import (
    mount_manifest_path,
    ssh_include_path,
    ssh_key_path,
    user_ssh_config_path,
)


def collect(vm_name: str, repo_root: Path, active_worktree: Path) -> dict:  # type: ignore[type-arg]
    """Aggregate state for *vm_name* into a flat dict.

    Parameters
    ----------
    vm_name:
        The tart VM name (e.g. ``"remo-dev"``).
    repo_root:
        Root of the git repository (used to locate the SSH git-root entry).
    active_worktree:
        The currently active worktree path; used to determine *selected* mount.
    """
    # --- VM section ----------------------------------------------------------
    vm_exists = vm.exists(vm_name)
    vm_running = vm.is_running(vm_name) if vm_exists else False
    vm_ip = vm.ip_address(vm_name) if vm_running else None

    # --- Launchd section -----------------------------------------------------
    launchd_label = launchd.label(vm_name)
    launchd_present = launchd.job_present(launchd_label)

    # --- Mounts section ------------------------------------------------------
    manifest_path = mount_manifest_path(vm_name)
    entries = manifest_read(manifest_path)

    resolved_worktree = active_worktree.resolve()
    selected: str | None = None
    for entry in entries:
        try:
            if entry.host_path.resolve() == resolved_worktree:
                selected = entry.name
                break
        except OSError:
            pass

    git_root_present = any(e.name.endswith("-git-root") for e in entries)

    entries_list = [{"name": e.name, "host_path": str(e.host_path)} for e in entries]

    # --- SSH section ---------------------------------------------------------
    inc_path = ssh_include_path()
    key_path = ssh_key_path(vm_name)
    key_present = key_path.is_file()

    user_cfg = user_ssh_config_path()
    include_present = False
    if user_cfg.exists():
        try:
            content = user_cfg.read_text()
            include_present = str(inc_path) in content
        except OSError:
            pass

    return {
        "vm": {
            "name": vm_name,
            "exists": vm_exists,
            "running": vm_running,
            "ip": vm_ip,
        },
        "launchd": {
            "label": launchd_label,
            "job_present": launchd_present,
        },
        "mounts": {
            "manifest_path": str(manifest_path),
            "count": len(entries),
            "entries": entries_list,
            "selected": selected,
            "git_root_present": git_root_present,
        },
        "ssh": {
            "include_path": str(inc_path),
            "key_path": str(key_path),
            "key_present": key_present,
            "include_present_in_user_config": include_present,
        },
    }


def _fmt(value: object) -> str:
    """Format a scalar value for human output."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return str(value).lower()
    return str(value)


def render_human(data: dict) -> str:  # type: ignore[type-arg]
    """Return a multi-line human-readable representation of *data*.

    Sections are rendered in fixed order: vm, launchd, mounts, ssh.
    Booleans are lowercase; ``None`` becomes ``null``.
    """
    lines: list[str] = []

    # vm section
    vm_sec = data["vm"]
    lines.append("vm:")
    for key in ("name", "exists", "running", "ip"):
        lines.append(f"  {key}={_fmt(vm_sec[key])}")

    # launchd section
    ld_sec = data["launchd"]
    lines.append("launchd:")
    for key in ("label", "job_present"):
        lines.append(f"  {key}={_fmt(ld_sec[key])}")

    # mounts section
    mnt_sec = data["mounts"]
    lines.append("mounts:")
    for key in ("manifest_path", "count", "selected", "git_root_present"):
        lines.append(f"  {key}={_fmt(mnt_sec[key])}")
    lines.append("  entries:")
    for entry in mnt_sec["entries"]:
        lines.append(f"    {entry['name']}={entry['host_path']}")

    # ssh section
    ssh_sec = data["ssh"]
    lines.append("ssh:")
    for key in ("include_path", "key_path", "key_present", "include_present_in_user_config"):
        lines.append(f"  {key}={_fmt(ssh_sec[key])}")

    return "\n".join(lines)


def render_json(data: dict) -> str:  # type: ignore[type-arg]
    """Return a pretty-printed JSON string for *data*."""
    return json.dumps(data, indent=2)
