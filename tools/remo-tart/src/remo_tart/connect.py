"""Connect dispatchers — CLI (ssh), VS Code, and Cursor."""

from __future__ import annotations

import subprocess

from remo_tart.mount import MountEntry
from remo_tart.ssh import ssh_alias

# Guest-side shared folder root (tart virtiofs / directory-share mount point).
_GUEST_SHARED_ROOT = "/Volumes/My Shared Files"


def connect_cli(vm_name: str, guest_user: str) -> int:
    """Drop into an interactive SSH shell on *vm_name*.

    Uses the SSH alias ``tart-<vm-name>`` (baked into the SSH config by
    :func:`remo_tart.ssh.upsert_managed_block`).  *guest_user* is kept for
    future use when we may bypass the alias and connect directly.

    Returns the ssh process exit code.
    """
    alias = ssh_alias(vm_name)
    return subprocess.run(["ssh", alias], check=False).returncode


def connect_vscode(
    vm_name: str,
    guest_user: str,
    mount: MountEntry,
    *,
    new_window: bool = False,
) -> int:
    """Open *mount* in VS Code via the SSH remote extension.

    Builds a ``vscode-remote://ssh-remote+<alias>/<guest-path>`` URI and
    passes it to the ``code`` CLI.  *guest_user* is kept for future use.

    Returns the ``code`` process exit code.
    """
    alias = ssh_alias(vm_name)
    guest_path = f"{_GUEST_SHARED_ROOT}/{mount.name}"
    uri = f"vscode-remote://ssh-remote+{alias}{guest_path}"
    window_flag = "--new-window" if new_window else "--reuse-window"
    argv = ["code", window_flag, "--folder-uri", uri]
    return subprocess.run(argv, check=False).returncode


def connect_cursor(
    vm_name: str,
    guest_user: str,
    mount: MountEntry,
    *,
    new_window: bool = False,
) -> int:
    """Open *mount* in Cursor via the SSH remote extension.

    Identical to :func:`connect_vscode` but invokes ``cursor`` instead of
    ``code``.  Cursor accepts the same ``vscode-remote://`` URI scheme.

    Returns the ``cursor`` process exit code.
    """
    alias = ssh_alias(vm_name)
    guest_path = f"{_GUEST_SHARED_ROOT}/{mount.name}"
    uri = f"vscode-remote://ssh-remote+{alias}{guest_path}"
    window_flag = "--new-window" if new_window else "--reuse-window"
    argv = ["cursor", window_flag, "--folder-uri", uri]
    return subprocess.run(argv, check=False).returncode
