"""remo-tart command-line entry point.

PR 2: every subcommand calls into native Python modules.  The bash shim
(dispatch.py / scripts/tart/*.sh) is no longer invoked from here.
"""

from __future__ import annotations

import sys
from pathlib import Path

import click

from remo_tart import __version__, launchd, mount, vm, worktree
from remo_tart import connect as _connect
from remo_tart import doctor as _doctor
from remo_tart import ssh as _ssh
from remo_tart import status as _status
from remo_tart.console import get_console, render_error
from remo_tart.errors import RemoTartError
from remo_tart.mount import manifest_read, mount_name_for_path
from remo_tart.paths import (
    mount_manifest_path,
    ssh_include_path,
    ssh_key_path,
    user_ssh_config_path,
    vm_log_path,
)

# TODO(pr3): move to config
_GUEST_USER = "admin"


# ---------------------------------------------------------------------------
# _load_cfg helper
# ---------------------------------------------------------------------------


def _load_cfg(ctx: click.Context):  # type: ignore[return]
    """Resolve the repo root and load .tart/project.toml. Used by every subcommand."""
    from remo_tart import config, dispatch

    try:
        repo = dispatch.find_repo_root()
    except RemoTartError:
        raise
    project = config.load(repo)
    ctx.obj["repo_root"] = repo
    ctx.obj["project"] = project
    return repo, project


# ---------------------------------------------------------------------------
# CLI-internal helpers
# ---------------------------------------------------------------------------


def _resolve_primary_mount(
    entries: list,  # type: ignore[type-arg]
    cwd: Path,
) -> object:
    """Return the mount entry whose host_path matches cwd, or the first non-bridge entry.

    This is a CLI-specific helper — not exported from mount.py.
    """
    resolved_cwd = cwd.resolve()
    for entry in entries:
        try:
            if entry.host_path.resolve() == resolved_cwd:
                return entry
        except OSError:
            pass
    # Fallback: return the first non-git-root entry, or just the first
    for entry in entries:
        if not entry.name.endswith("-git-root"):
            return entry
    if entries:
        return entries[0]
    from remo_tart.mount import MountEntry

    return MountEntry(name="unknown", host_path=cwd)


# ---------------------------------------------------------------------------
# CLI group
# ---------------------------------------------------------------------------


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.version_option(version=__version__, prog_name="remo-tart")
@click.option("-v", "--verbose", count=True, help="Increase verbosity (repeatable).")
@click.pass_context
def main(ctx: click.Context, verbose: int) -> None:
    """CLI for the Remo Tart development VM."""
    ctx.ensure_object(dict)
    ctx.obj["verbose"] = verbose


# ---- happy path -----------------------------------------------------------


@main.command()
@click.argument("mode", type=click.Choice(["cli", "vscode", "cursor"]), default="cli")
@click.pass_context
def up(ctx: click.Context, mode: str) -> None:
    """Attach the current worktree, ensure the VM is running, and connect."""
    repo, project = _load_cfg(ctx)
    cwd = Path.cwd()
    outcome = worktree.ensure_attached(repo, project, cwd)
    name = project.vm.name
    if mode == "cli":
        code = _connect.connect_cli(name, _GUEST_USER)
    elif mode == "vscode":
        code = _connect.connect_vscode(name, _GUEST_USER, outcome.primary)
    else:  # cursor
        code = _connect.connect_cursor(name, _GUEST_USER, outcome.primary)
    ctx.exit(code)


# ---- explicit lifecycle ---------------------------------------------------


@main.command()
@click.argument("worktree_path", required=False, metavar="PATH")
@click.pass_context
def use(ctx: click.Context, worktree_path: str | None) -> None:
    """Attach a worktree to the VM (mount + restart if needed)."""
    repo, project = _load_cfg(ctx)
    path = Path(worktree_path).resolve() if worktree_path else Path.cwd()
    outcome = worktree.ensure_attached(repo, project, path)
    get_console().print(
        f"[green]Attached[/green] {outcome.primary.name} "
        f"(actions: {', '.join(a.name for a in outcome.actions)})"
    )


@main.command()
@click.pass_context
def start(ctx: click.Context) -> None:
    """Start the VM without changing mounts or connecting."""
    _repo, project = _load_cfg(ctx)
    name = project.vm.name
    if not vm.exists(name):
        raise RemoTartError(
            "vm does not exist",
            hint="run remo-tart up to create it",
        )
    label = launchd.label(name)
    log_path = vm_log_path(name)
    manifest_path = mount_manifest_path(name)
    mounts = manifest_read(manifest_path)
    launchd.remove(label)
    # Truncate log to avoid confusion with stale output
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")
    tart_args = vm.build_run_args(name, project.vm.network, mounts)
    launchd.submit(label, tart_args, log_path)


@main.command()
@click.argument("mode", type=click.Choice(["cli", "vscode", "cursor"]), default="cli")
@click.pass_context
def connect(ctx: click.Context, mode: str) -> None:
    """Connect to the running VM (cli / vscode / cursor)."""
    _repo, project = _load_cfg(ctx)
    name = project.vm.name
    if not vm.is_running(name):
        raise RemoTartError(
            f"vm is not running: {name}",
            hint="run `remo-tart up` to start and connect, or `remo-tart start` to only start",
        )
    # Find the primary mount: the one whose host_path matches cwd or first entry
    manifest_path = mount_manifest_path(name)
    entries = mount.manifest_read(manifest_path)
    primary = _resolve_primary_mount(entries, Path.cwd())
    if mode == "cli":
        code = _connect.connect_cli(name, _GUEST_USER)
    elif mode == "vscode":
        code = _connect.connect_vscode(name, _GUEST_USER, primary)
    else:  # cursor
        code = _connect.connect_cursor(name, _GUEST_USER, primary)
    ctx.exit(code)


# ---- observability --------------------------------------------------------


@main.command()
@click.option("--json", "as_json", is_flag=True, help="Emit machine-readable JSON.")
@click.pass_context
def status(ctx: click.Context, as_json: bool) -> None:
    """Show VM status."""
    repo, project = _load_cfg(ctx)
    name = project.vm.name
    data = _status.collect(name, repo, Path.cwd())
    output = _status.render_json(data) if as_json else _status.render_human(data)
    get_console().print(output)


@main.command()
@click.pass_context
def doctor(ctx: click.Context) -> None:
    """Run host/VM health checks."""
    try:
        repo, project = _load_cfg(ctx)
        name = project.vm.name
    except RemoTartError:
        # doctor.run_all handles config failure gracefully
        repo = Path.cwd()
        name = "unknown"
    findings = _doctor.run_all(name, repo)
    print(_doctor.render(findings))
    ctx.exit(_doctor.exit_code(findings))


@main.command(context_settings={"ignore_unknown_options": True})
@click.argument("ssh_args", nargs=-1, type=click.UNPROCESSED)
@click.pass_context
def ssh(ctx: click.Context, ssh_args: tuple[str, ...]) -> None:
    """Open an SSH session or run a command inside the VM."""
    _repo, project = _load_cfg(ctx)
    name = project.vm.name
    if not vm.is_running(name):
        raise RemoTartError(
            f"vm is not running: {name}",
            hint="run `remo-tart up` to start and connect, or `remo-tart start` to only start",
        )
    code = vm.exec_interactive(name, list(ssh_args))
    ctx.exit(code)


# ---- destructive ----------------------------------------------------------


@main.command()
@click.option("--force", is_flag=True, help="Skip confirmation.")
@click.pass_context
def destroy(ctx: click.Context, force: bool) -> None:
    """Destroy the VM."""
    _repo, project = _load_cfg(ctx)
    name = project.vm.name
    if not force:
        confirmed = click.confirm(f"Destroy VM '{name}'? This cannot be undone.", default=False)
        if not confirmed:
            ctx.exit(1)
            return
    label = launchd.label(name)
    launchd.remove(label)
    if vm.exists(name):
        vm.delete(name)
    _ssh.remove_managed_block(ssh_include_path(), name)
    _ssh.remove_include_from_user_config(user_ssh_config_path(), ssh_include_path())
    # Optionally remove the SSH key file
    key = ssh_key_path(name)
    if key.exists():
        key.unlink(missing_ok=True)
    pub = key.with_suffix(".pub")
    if pub.exists():
        pub.unlink(missing_ok=True)


@main.command(name="clean-worktree")
@click.argument("path", required=False)
@click.pass_context
def clean_worktree(ctx: click.Context, path: str | None) -> None:
    """Remove a worktree from the mount manifest."""
    _repo, project = _load_cfg(ctx)
    resolved = Path(path).resolve() if path else Path.cwd()
    manifest_path = mount_manifest_path(project.vm.name)
    mount_name = mount_name_for_path(project.slug, resolved)
    mount.manifest_remove(manifest_path, mount_name)
    get_console().print(f"[green]Removed[/green] mount entry '{mount_name}' from manifest.")


@main.command()
@click.pass_context
def bootstrap(ctx: click.Context) -> None:
    """First-time VM setup (create + provision)."""
    get_console().print("[bold]First-time setup[/bold] — creating and provisioning VM…")
    repo, project = _load_cfg(ctx)
    cwd = Path.cwd()
    worktree.ensure_attached(repo, project, cwd)
    name = project.vm.name
    code = _connect.connect_cli(name, _GUEST_USER)
    ctx.exit(code)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def _run() -> int:
    try:
        result = main(standalone_mode=False)
        return int(result) if isinstance(result, int) else 0
    except RemoTartError as err:
        render_error(get_console(), err)
        return 1
    except click.exceptions.ClickException as err:
        err.show()
        return err.exit_code
    except click.exceptions.Abort:
        return 130
    except click.exceptions.Exit as err:
        return err.exit_code
    except SystemExit as err:
        return int(err.code) if isinstance(err.code, int) else 0


if __name__ == "__main__":
    sys.exit(_run())
