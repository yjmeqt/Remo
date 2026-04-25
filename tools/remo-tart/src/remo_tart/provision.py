"""Guest-side provisioning orchestrator.

Builds a bash script that runs inside the tart VM to source each enabled
pack, call its ``tart_pack_<name>_ensure`` function, run the project-level
provision hook, and optionally run the verify-worktree hook.
"""

from __future__ import annotations

import shlex

from remo_tart import vm
from remo_tart.config import ProjectConfig
from remo_tart.errors import RemoTartError
from remo_tart.mount import MountEntry

_SHARED_ROOT = "/Volumes/My Shared Files"


def _always_quote(s: str) -> str:
    """Always wrap *s* in double-quotes, escaping ``"`` and ``$`` inside."""
    escaped = s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
    return f'"{escaped}"'


def _primary_mount(mounts: list[MountEntry]) -> MountEntry:
    """Return the first mount that is not the git-root bridge.

    Raises :exc:`~remo_tart.errors.RemoTartError` if no such mount exists.
    """
    for entry in mounts:
        if not entry.name.endswith("-git-root"):
            return entry
    raise RemoTartError(
        "no primary mount found — all mounts are git-root bridges",
        hint="add at least one worktree mount before calling provision",
    )


def build_guest_script(
    project: ProjectConfig,
    mounts: list[MountEntry],
    packs_dir_guest: str,
    *,
    verify: bool,
) -> str:
    """Return a bash script the guest will run to provision itself."""
    primary = _primary_mount(mounts)
    primary_guest_path = f"{_SHARED_ROOT}/{primary.name}"

    lines: list[str] = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
    ]

    # Source the shared helper library first; packs depend on its functions
    # (retry_command, ensure_xcode, ensure_node_and_npm, ensure_codex,
    # remo_tart_worktree_env_exports).
    lines.append(f"source {_always_quote(f'{packs_dir_guest}/_lib.sh')}")
    lines.append("")

    # Source each enabled pack
    for pack in project.packs:
        pack_path = f"{packs_dir_guest}/{pack}.sh"
        lines.append(f"source {_always_quote(pack_path)}")

    if project.packs:
        lines.append("")

    # Call the ensure function for each enabled pack
    for pack in project.packs:
        lines.append(f"tart_pack_{pack}_ensure")

    if project.packs:
        lines.append("")

    # Run project-level provision hook
    provision_path = f"{primary_guest_path}/.tart/provision.sh"
    lines.append(f"bash {shlex.quote(provision_path)}")

    # Optionally run verify-worktree
    if verify:
        lines.append("")
        verify_path = f"{primary_guest_path}/.tart/verify-worktree.sh"
        lines.append(f"bash {shlex.quote(verify_path)}")

    lines.append("")
    return "\n".join(lines)


def run_provision(
    vm_name: str,
    project: ProjectConfig,
    mounts: list[MountEntry],
    *,
    verify: bool = True,
) -> int:
    """Ship the guest script via vm.exec_interactive, return exit code."""
    packs_dir = _packs_dir_guest(mounts)
    script = build_guest_script(project, mounts, packs_dir_guest=packs_dir, verify=verify)
    return vm.exec_interactive(vm_name, ["bash", "-c", script])


def _packs_dir_guest(mounts: list[MountEntry]) -> str:
    """Derive the guest-side packs directory from the git-root bridge mount.

    The packs dir lives under the git-root bridge at ``.tart/packs``.
    Falls back to the primary mount if no git-root bridge exists.
    """
    for entry in mounts:
        if entry.name.endswith("-git-root"):
            return f"{_SHARED_ROOT}/{entry.name}/.tart/packs"
    primary = _primary_mount(mounts)
    return f"{_SHARED_ROOT}/{primary.name}/.tart/packs"
