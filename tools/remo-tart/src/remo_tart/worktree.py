"""Worktree attach/boot orchestrator.

Given a worktree path, make the VM running with the right mounts attached
and the SSH config updated.  Ported from:
  - scripts/tart/use-worktree-dev-vm.sh
  - scripts/tart/create-dev-vm.sh
"""

from __future__ import annotations

import shlex
import time
from dataclasses import dataclass
from pathlib import Path

from remo_tart import launchd, ssh, vm
from remo_tart.config import ProjectConfig
from remo_tart.errors import RemoTartError
from remo_tart.mount import (
    MountEntry,
    git_root_bridge_entry,
    manifest_prune_stale,
    manifest_read,
    manifest_upsert,
    mount_name_for_path,
)
from remo_tart.paths import (
    mount_manifest_path,
    ssh_include_path,
    ssh_key_path,
    user_ssh_config_path,
    vm_log_path,
)
from remo_tart.state import Action, VmState, decide

# TODO(pr3): move to config
_GUEST_USER = "admin"

_WAIT_INTERVAL = 2  # seconds between polls
_WAIT_ATTEMPTS = 90  # maximum polling attempts (~3 minutes total)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class AttachOutcome:
    actions: tuple[Action, ...]
    manifest: tuple[MountEntry, ...]
    primary: MountEntry


def ensure_attached(
    repo_root: Path,
    project: ProjectConfig,
    worktree_host_path: Path,
) -> AttachOutcome:
    """Make the VM running with the given worktree attached; idempotent."""
    vm_name = project.vm.name
    manifest_path = mount_manifest_path(vm_name)
    log_path = vm_log_path(vm_name)
    key_path = ssh_key_path(vm_name)

    # Step 1: Snapshot pre-upsert state, prune stale entries, then upsert the
    # primary + git-root bridge entries.
    pre_upsert = manifest_read(manifest_path)
    worktree_already_present = any(
        e.host_path.resolve() == worktree_host_path.resolve() for e in pre_upsert
    )

    manifest_prune_stale(manifest_path)
    target = _target_manifest(project, repo_root, worktree_host_path)

    primary_entry = MountEntry(
        name=mount_name_for_path(project.slug, worktree_host_path),
        host_path=worktree_host_path,
    )
    bridge_entry = git_root_bridge_entry(project.slug, repo_root / ".git")
    manifest_upsert(manifest_path, primary_entry)
    manifest_upsert(manifest_path, bridge_entry)

    # Step 2: Read VM state.  Pass worktree_already_present so _read_state can
    # use the pre-upsert view when deciding mount_matches (the running VM loaded
    # the OLD manifest at boot — a restart is needed if the mount wasn't there).
    vm_state = _read_state(project, manifest_path, worktree_host_path, worktree_already_present)

    # Step 3: Decide actions from the state machine.
    actions = decide(vm_state)

    # Step 4: Dispatch.
    mounts = target
    for action in actions:
        if action == Action.CREATE:
            _action_create(project, mounts, log_path, key_path)
        elif action == Action.UPDATE_MOUNT_AND_RESTART:
            _action_update_mount_and_restart(project, mounts, log_path)
        elif action == Action.START:
            _action_start(project, mounts, log_path)
        elif action == Action.ATTACH_MOUNT_AND_START:
            _action_attach_mount_and_start(project, mounts, log_path)
        elif action == Action.NOTHING:
            _action_nothing(project)

    # Step 5: Configure SSH for all actions except NOTHING.
    if actions != [Action.NOTHING]:
        _configure_ssh(project, key_path)

    # Step 6: Return outcome with the final manifest.
    final_manifest = manifest_read(manifest_path)
    return AttachOutcome(
        actions=tuple(actions),
        manifest=tuple(final_manifest),
        primary=primary_entry,
    )


# ---------------------------------------------------------------------------
# Module-level helpers (patchable by tests)
# ---------------------------------------------------------------------------


def _read_state(
    project: ProjectConfig,
    manifest_path: Path,
    worktree: Path,
    worktree_already_present: bool = False,
) -> VmState:
    """Read current VM and manifest state.

    ``worktree_already_present`` reflects whether the worktree path was in the
    manifest BEFORE the current upsert.  A running VM loaded the old manifest at
    boot, so ``mount_matches`` is True only when the path was already present —
    meaning no restart is required to expose the mount inside the guest.
    """
    name = project.vm.name
    exists = vm.exists(name)
    running = exists and vm.is_running(name)
    # A running VM has the OLD manifest loaded; we need a restart only when the
    # worktree was not already mounted at boot time.
    mount_matches = running and worktree_already_present
    return VmState(exists=exists, running=running, mount_matches=mount_matches)


def _target_manifest(
    project: ProjectConfig,
    repo_root: Path,
    worktree: Path,
) -> list[MountEntry]:
    """Build the target mount list: primary worktree + git-root bridge."""
    primary = MountEntry(
        name=mount_name_for_path(project.slug, worktree),
        host_path=worktree,
    )
    bridge = git_root_bridge_entry(project.slug, repo_root / ".git")
    return [primary, bridge]


def _action_create(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
    ssh_key_path: Path,
) -> None:
    """Create VM from base image, configure resources, and start it."""
    name = project.vm.name
    label_str = launchd.label(name)

    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    # Remove any stale launchd registration for this label to avoid submit failure
    launchd.remove(label_str)

    vm.create(name, project.vm.base_image)
    vm.set_resources(name, project.vm.cpu, project.vm.memory_gb)
    tart_args = vm.build_run_args(name, project.vm.network, mounts)
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_update_mount_and_restart(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
) -> None:
    """Stop the VM, update mounts, and restart."""
    name = project.vm.name
    label_str = launchd.label(name)
    launchd.remove(label_str)
    _wait_for_stopped(name)
    # Also wait for launchctl to actually drop the label, to avoid submit conflict
    for _ in range(30):
        if not launchd.job_present(label_str):
            break
        time.sleep(1)
    tart_args = vm.build_run_args(name, project.vm.network, mounts)
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_start(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
) -> None:
    """Submit the VM to launchd and wait for it to be running."""
    name = project.vm.name
    label_str = launchd.label(name)

    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    # Remove any stale launchd registration for this label to avoid submit failure
    launchd.remove(label_str)

    tart_args = vm.build_run_args(name, project.vm.network, mounts)
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_attach_mount_and_start(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
) -> None:
    """Mount is already upserted before state read; just submit and wait."""
    name = project.vm.name
    label_str = launchd.label(name)

    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    # Remove any stale launchd registration for this label to avoid submit failure
    launchd.remove(label_str)

    tart_args = vm.build_run_args(name, project.vm.network, mounts)
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_nothing(project: ProjectConfig) -> None:
    """No-op — VM is already running with the correct mount."""
    from remo_tart.console import console

    console.print(
        f"[dim]VM '{project.vm.name}' is already running with the correct mount. "
        "Nothing to do.[/dim]"
    )


def _build_inject_command(pub: str) -> str:
    """Build a shell command to idempotently inject a public key into authorized_keys."""
    quoted_pub = shlex.quote(pub)
    return (
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && "
        f"grep -Fqx -- {quoted_pub} ~/.ssh/authorized_keys 2>/dev/null || "
        f"printf '%s\\n' {quoted_pub} >> ~/.ssh/authorized_keys && "
        "chmod 600 ~/.ssh/authorized_keys"
    )


def _configure_ssh(project: ProjectConfig, key_path: Path) -> None:
    """Configure SSH keypair, managed block, include directive, and authorized keys."""
    name = project.vm.name

    # 1. Generate keypair (idempotent).
    ssh.generate_keypair(key_path)

    # 2. Build and upsert the managed SSH config block.
    block = ssh.managed_block(name, _GUEST_USER, key_path)
    include_path = ssh_include_path()
    ssh.upsert_managed_block(include_path, name, block)

    # 3. Ensure the include directive is in the user's SSH config.
    user_config = user_ssh_config_path()
    ssh.ensure_include_in_user_config(user_config, include_path)

    # 4. Inject the public key into the guest's authorized_keys (idempotent).
    pub = ssh.public_key(key_path)
    inject_cmd = _build_inject_command(pub)
    result = vm.exec_capture(name, ["sh", "-c", inject_cmd])
    if result.returncode != 0:
        raise RemoTartError(
            f"failed to install ssh public key into guest (exit {result.returncode})",
            hint=f"check {vm_log_path(name)} and ensure the VM is fully booted",
        )


# ---------------------------------------------------------------------------
# Wait helpers
# ---------------------------------------------------------------------------


def _wait_for_guest_exec(vm_name: str, *, attempts: int = 90, interval: float = 2.0) -> None:
    """Poll `tart exec true` until success. Raises RemoTartError on timeout.

    This is stricter than `vm.is_running` — it waits for the guest agent to
    respond, which is what downstream SSH key injection actually needs.
    """
    for _ in range(attempts):
        # Quick readiness check — `tart exec <name> -- /usr/bin/true`
        if not vm.is_running(vm_name):
            time.sleep(interval)
            continue
        result = vm.exec_capture(vm_name, ["/usr/bin/true"])
        if result.returncode == 0:
            return
        time.sleep(interval)
    raise RemoTartError(
        f"timeout waiting for VM '{vm_name}' to be ready for exec",
        hint=f"check {vm_log_path(vm_name)}",
    )


def _wait_for_stopped(name: str) -> None:
    """Poll until the VM has stopped, or raise RemoTartError on timeout."""
    for _ in range(_WAIT_ATTEMPTS):
        if not vm.is_running(name):
            return
        time.sleep(_WAIT_INTERVAL)
    raise RemoTartError(
        f"timeout waiting for VM '{name}' to stop",
        hint=f"check {vm_log_path(name)}",
    )
