"""Worktree attach/boot orchestrator.

Given a worktree path, make the VM running with the right mounts attached
and the SSH config updated.  Ported from:
  - scripts/tart/use-worktree-dev-vm.sh
  - scripts/tart/create-dev-vm.sh
"""

from __future__ import annotations

import shlex
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from remo_tart import launchd, ssh, vm
from remo_tart.config import ProjectConfig
from remo_tart.console import done, get_console, step
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
    *,
    headless: bool = True,
) -> AttachOutcome:
    """Make the VM running with the given worktree attached; idempotent.

    ``headless`` controls whether ``tart run`` is invoked with
    ``--no-graphics``.  Default True (no UI window).  When False, a UI window
    opens.  Note: ``headless`` is set at boot; an already-running VM keeps
    whatever mode it was started with until the next restart.
    """
    vm_name = project.vm.name
    manifest_path = mount_manifest_path(vm_name)
    log_path = vm_log_path(vm_name)
    key_path = ssh_key_path(vm_name)

    # Step 1: Prune stale entries, then upsert the primary + git-root bridge.
    manifest_prune_stale(manifest_path)

    primary_entry = MountEntry(
        name=mount_name_for_path(project.slug, worktree_host_path),
        host_path=worktree_host_path,
    )
    bridge_entry = git_root_bridge_entry(project.slug, _resolve_git_common_dir(worktree_host_path))
    manifest_upsert(manifest_path, primary_entry)
    manifest_upsert(manifest_path, bridge_entry)

    # Step 2: Read VM state.  ``mount_matches`` is computed against the
    # *running* VM's actual mounts (queried via tart exec), not the on-disk
    # manifest — the manifest can drift ahead of the running VM if mounts
    # were upserted between boots.
    vm_state = _read_state(project, manifest_path, worktree_host_path)

    # Step 3: Decide actions from the state machine.
    actions = decide(vm_state)

    # Step 4: Dispatch with the FULL manifest (not just primary + bridge), so a
    # restart from worktree A keeps worktree B's mount alive too. Otherwise
    # every cross-worktree `up` silently drops all other worktree shares.
    mounts = manifest_read(manifest_path)
    for action in actions:
        if action == Action.CREATE:
            _action_create(project, mounts, log_path, key_path, headless=headless)
        elif action == Action.UPDATE_MOUNT_AND_RESTART:
            _action_update_mount_and_restart(project, mounts, log_path, headless=headless)
        elif action == Action.START:
            _action_start(project, mounts, log_path, headless=headless)
        elif action == Action.ATTACH_MOUNT_AND_START:
            _action_attach_mount_and_start(project, mounts, log_path, headless=headless)
        elif action == Action.NOTHING:
            _action_nothing(project)

    # Step 5: Configure SSH unconditionally. All operations are idempotent
    # (keypair generation skips if exists, managed block upsert replaces by VM
    # name, include is added once, authorized_keys uses grep-skip-if-present).
    # This makes the workflow self-healing if a prior `up` was Ctrl-C'd
    # before SSH was configured.
    if vm.is_running(project.vm.name):
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


def _running_mount_names(vm_name: str) -> set[str]:
    """Return the directory-share names actually mounted in the running guest.

    Empty set if the guest is unreachable or the shared-files dir is empty.
    This is **ground truth** — the on-disk manifest can drift ahead of what
    the currently-running VM actually has loaded.
    """
    result = vm.exec_capture(vm_name, ["ls", "/Volumes/My Shared Files/"])
    if result.returncode != 0:
        return set()
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def _read_state(
    project: ProjectConfig,
    manifest_path: Path,
    worktree: Path,
) -> VmState:
    """Read current VM state. ``mount_matches`` reflects whether the running
    guest actually has the worktree's mount loaded — queried via ``tart exec``,
    not the on-disk manifest, because the manifest can drift ahead of the VM.
    """
    name = project.vm.name
    exists = vm.exists(name)
    running = exists and vm.is_running(name)
    if running:
        target_name = mount_name_for_path(project.slug, worktree)
        mount_matches = target_name in _running_mount_names(name)
    else:
        mount_matches = False
    return VmState(exists=exists, running=running, mount_matches=mount_matches)


def _resolve_git_common_dir(worktree: Path) -> Path:
    """Return the absolute git common dir for ``worktree``.

    In a git worktree, ``<worktree>/.git`` is a *file* pointing at the main
    checkout's ``.git`` directory.  Tart can only mount directories, so the
    bridge mount must target the common dir, not the per-worktree gitdir.

    Falls back to ``<worktree>/.git`` if ``git`` is unavailable or the path is
    not a git repository (e.g. unit tests that pass an arbitrary tmp_path).
    """
    try:
        result = subprocess.run(
            ["git", "-C", str(worktree), "rev-parse", "--git-common-dir"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return worktree / ".git"
    return (worktree / result.stdout.strip()).resolve()


def _target_manifest(
    project: ProjectConfig,
    repo_root: Path,
    worktree: Path,
) -> list[MountEntry]:
    """Build the target mount list: primary worktree + git-root bridge."""
    del repo_root  # use git's own opinion of where the common dir lives
    primary = MountEntry(
        name=mount_name_for_path(project.slug, worktree),
        host_path=worktree,
    )
    bridge = git_root_bridge_entry(project.slug, _resolve_git_common_dir(worktree))
    return [primary, bridge]


def _action_create(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
    ssh_key_path: Path,
    *,
    headless: bool = True,
) -> None:
    """Create VM from base image, configure resources, and start it."""
    name = project.vm.name
    label_str = launchd.label(name)

    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    # Remove any stale launchd registration for this label to avoid submit failure
    launchd.remove(label_str)

    step(f"cloning base image {project.vm.base_image} as VM {name} (this can take several minutes)")
    vm.create(name, project.vm.base_image)
    step(f"configuring VM resources (cpu={project.vm.cpu}, memory={project.vm.memory_gb}G)")
    vm.set_resources(name, project.vm.cpu, project.vm.memory_gb)
    tart_args = vm.build_run_args(name, project.vm.network, mounts, headless=headless)
    step(f"submitting launchd job {label_str} ({'headless' if headless else 'with display'})")
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_update_mount_and_restart(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
    *,
    headless: bool = True,
) -> None:
    """Stop the VM, update mounts, and restart."""
    name = project.vm.name
    label_str = launchd.label(name)
    step(f"stopping VM {name} to update mounts")
    launchd.remove(label_str)
    _wait_for_stopped(name)
    # Also wait for launchctl to actually drop the label, to avoid submit conflict
    for _ in range(30):
        if not launchd.job_present(label_str):
            break
        time.sleep(1)
    tart_args = vm.build_run_args(name, project.vm.network, mounts, headless=headless)
    step(f"restarting VM {name} with updated mounts ({'headless' if headless else 'with display'})")
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_start(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
    *,
    headless: bool = True,
) -> None:
    """Submit the VM to launchd and wait for it to be running."""
    name = project.vm.name
    label_str = launchd.label(name)

    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    # Remove any stale launchd registration for this label to avoid submit failure
    launchd.remove(label_str)

    tart_args = vm.build_run_args(name, project.vm.network, mounts, headless=headless)
    step(f"starting VM {name} ({'headless' if headless else 'with display'})")
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_attach_mount_and_start(
    project: ProjectConfig,
    mounts: list[MountEntry],
    log_path: Path,
    *,
    headless: bool = True,
) -> None:
    """Mount is already upserted before state read; just submit and wait."""
    name = project.vm.name
    label_str = launchd.label(name)

    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    # Remove any stale launchd registration for this label to avoid submit failure
    launchd.remove(label_str)

    tart_args = vm.build_run_args(name, project.vm.network, mounts, headless=headless)
    step(f"attaching mount and starting VM {name} ({'headless' if headless else 'with display'})")
    launchd.submit(label_str, tart_args, log_path)
    _wait_for_guest_exec(name)


def _action_nothing(project: ProjectConfig) -> None:
    """No-op — VM is already running with the correct mount."""
    get_console().print(
        f"[dim]VM '{project.vm.name}' is already running with the correct mount. "
        "Nothing to do.[/dim]"
    )


def _build_inject_command(pub: str) -> str:
    """Build a shell command to idempotently inject a public key into authorized_keys.

    Uses ``set -e`` + an explicit ``grep || append`` pattern so the overall
    exit code is unambiguous (0 = success).  The previous implementation
    chained ``&& ... || ... && ...`` which has surprising left-associative
    precedence and produced exit-1 even when the key was already present.
    """
    quoted_pub = shlex.quote(pub)
    return (
        "set -e; "
        "mkdir -p ~/.ssh; "
        "chmod 700 ~/.ssh; "
        "touch ~/.ssh/authorized_keys; "
        "chmod 600 ~/.ssh/authorized_keys; "
        f"grep -Fqx -- {quoted_pub} ~/.ssh/authorized_keys "
        f"|| printf '%s\\n' {quoted_pub} >> ~/.ssh/authorized_keys"
    )


def _configure_ssh(project: ProjectConfig, key_path: Path) -> None:
    """Configure SSH keypair, managed block, include directive, and authorized keys."""
    name = project.vm.name
    step(f"configuring SSH for {name}")

    # 1. Generate keypair (idempotent).
    ssh.generate_keypair(key_path)

    # 2. Build and upsert the managed SSH config block.
    block = ssh.managed_block(name, project.vm.guest_user, key_path)
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
        stderr = (result.stderr or "").strip()
        stdout = (result.stdout or "").strip()
        detail = stderr or stdout or "(no output)"
        raise RemoTartError(
            f"failed to install ssh public key into guest (exit {result.returncode}): {detail}",
            hint=f"check {vm_log_path(name)} and ensure the VM is fully booted",
        )
    done(f"SSH ready: ssh tart-{name}")


# ---------------------------------------------------------------------------
# Wait helpers
# ---------------------------------------------------------------------------


def _wait_for_guest_exec(vm_name: str, *, attempts: int = 300, interval: float = 2.0) -> None:
    """Poll `tart exec true` until success. Raises RemoTartError on timeout.

    "Running" at the Tart/VZ layer just means the VM kernel started; macOS
    inside still needs time to boot its launchd, network, and exec agent. We
    surface intermediate signals (IP assignment, last log line) so the wait
    isn't opaque.
    """
    step(f"waiting for {vm_name} guest agent (macOS boot inside the VM)...")
    get_console().print(
        "[dim]   typical wait: 3-5 minutes (10+ on first boot). "
        "Don't Ctrl-C — the connect step runs only after this finishes.[/dim]"
    )
    log_path = vm_log_path(vm_name)
    last_ip: str | None = None
    last_log_tail: str = ""
    for i in range(attempts):
        if vm.is_running(vm_name):
            result = vm.exec_capture(vm_name, ["/usr/bin/true"])
            if result.returncode == 0:
                done(f"VM {vm_name} guest agent is ready")
                return

        elapsed = int((i + 1) * interval)
        # IP assignment lands ~10-20s before the exec agent on macOS.
        if last_ip is None:
            ip = vm.ip_address(vm_name)
            if ip:
                last_ip = ip
                get_console().print(f"[dim]  ...network up: {ip}[/dim]")

        if elapsed and elapsed % 10 == 0:
            running = "running" if vm.is_running(vm_name) else "VZ-still-booting"
            tail = _last_log_line(log_path)
            extra = ""
            if tail and tail != last_log_tail:
                last_log_tail = tail
                extra = f' last log: "{tail[:80]}"'
            get_console().print(f"[dim]  ...{vm_name} {running} ({elapsed}s elapsed){extra}[/dim]")
        time.sleep(interval)
    raise RemoTartError(
        f"timeout waiting for VM '{vm_name}' to be ready for exec",
        hint=f"check {log_path}",
    )


def _last_log_line(log_path: Path) -> str:
    """Return the last non-empty line of a log file, or empty string."""
    try:
        with log_path.open("rb") as f:
            f.seek(0, 2)
            size = f.tell()
            if size == 0:
                return ""
            chunk = min(2048, size)
            f.seek(size - chunk, 0)
            data = f.read(chunk).decode("utf-8", errors="replace")
        for line in reversed(data.splitlines()):
            if line.strip():
                return line.strip()
    except OSError:
        pass
    return ""


def _wait_for_stopped(name: str) -> None:
    """Poll until the VM has stopped, or raise RemoTartError on timeout."""
    for i in range(_WAIT_ATTEMPTS):
        if not vm.is_running(name):
            return
        elapsed = int((i + 1) * _WAIT_INTERVAL)
        if elapsed and elapsed % 10 == 0:
            get_console().print(f"[dim]  ...waiting for {name} to stop ({elapsed}s)[/dim]")
        time.sleep(_WAIT_INTERVAL)
    raise RemoTartError(
        f"timeout waiting for VM '{name}' to stop",
        hint=f"check {vm_log_path(name)}",
    )
