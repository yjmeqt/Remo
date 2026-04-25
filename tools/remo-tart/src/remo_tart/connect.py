"""Connect dispatchers — CLI (ssh), VS Code, and Cursor."""

from __future__ import annotations

import subprocess

from remo_tart.ssh import ssh_alias
from remo_tart.worktree import WorktreeAttachment


def connect_cli(vm_name: str, guest_user: str) -> int:
    """Drop into an interactive SSH shell on *vm_name*."""
    del guest_user  # ssh alias already encodes the user
    alias = ssh_alias(vm_name)
    return subprocess.run(["ssh", alias], check=False).returncode


def connect_vscode(
    vm_name: str,
    guest_user: str,
    attachment: WorktreeAttachment,
    *,
    new_window: bool = False,
) -> int:
    """Open the worktree referenced by *attachment* in VS Code via SSH-remote."""
    del guest_user
    alias = ssh_alias(vm_name)
    uri = f"vscode-remote://ssh-remote+{alias}{attachment.guest_path}"
    window_flag = "--new-window" if new_window else "--reuse-window"
    argv = ["code", window_flag, "--folder-uri", uri]
    return subprocess.run(argv, check=False).returncode


def connect_cursor(
    vm_name: str,
    guest_user: str,
    attachment: WorktreeAttachment,
    *,
    new_window: bool = False,
) -> int:
    """Open the worktree referenced by *attachment* in Cursor."""
    del guest_user
    alias = ssh_alias(vm_name)
    uri = f"vscode-remote://ssh-remote+{alias}{attachment.guest_path}"
    window_flag = "--new-window" if new_window else "--reuse-window"
    argv = ["cursor", window_flag, "--folder-uri", uri]
    return subprocess.run(argv, check=False).returncode
