"""remo-tart command-line entry point.

Every subcommand calls into native Python modules.
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
    find_repo_root,
    mount_manifest_path,
    ssh_include_path,
    ssh_key_path,
    user_ssh_config_path,
    vm_log_path,
)

# ---------------------------------------------------------------------------
# _load_cfg helper
# ---------------------------------------------------------------------------


def _load_cfg(ctx: click.Context):  # type: ignore[return]
    """Resolve the repo root and load .tart/project.toml. Used by every subcommand."""
    from remo_tart import config

    repo = find_repo_root()
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
    if not entries:
        raise RemoTartError(
            "no mounts attached to this VM",
            hint="run `remo-tart use` from this worktree to attach it",
        )
    cwd_resolved = cwd.resolve()
    for entry in entries:
        try:
            if entry.host_path.resolve() == cwd_resolved:
                return entry
        except OSError:
            continue
    # No exact match — fall back to first non-git-root entry, but warn
    non_bridge = [e for e in entries if not e.name.endswith("-git-root")]
    if non_bridge:
        get_console().print(
            f"[yellow]warning:[/yellow] cwd {cwd} does not match any mount; "
            f"using mount '{non_bridge[0].name}'"
        )
        return non_bridge[0]
    raise RemoTartError(
        f"cwd {cwd} is not a recorded mount and no non-bridge mount exists",
        hint="run `remo-tart use` from this worktree to attach it",
    )


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
@click.option(
    "--display",
    is_flag=True,
    help="Boot with a UI window. Triggers a restart if VM is currently headless.",
)
@click.pass_context
def up(ctx: click.Context, mode: str, display: bool) -> None:
    """Attach the current worktree, ensure the VM is running, and connect.

    By default the VM runs headless (no UI window). Use ``--display`` if you
    need to see the VM screen (rarely needed; macOS guest is normally driven
    via SSH / Remote SSH editors).
    """
    from remo_tart.console import done as _done
    from remo_tart.console import step as _step

    repo, project = _load_cfg(ctx)
    cwd = Path.cwd()
    _step(f"up({mode}) for worktree {cwd}")
    outcome = worktree.ensure_attached(repo, project, cwd, headless=not display)
    _done(f"actions: {', '.join(a.name for a in outcome.actions)}")
    name = project.vm.name
    _step(f"connecting via {mode}")
    if mode == "cli":
        code = _connect.connect_cli(name, project.vm.guest_user)
    elif mode == "vscode":
        code = _connect.connect_vscode(name, project.vm.guest_user, outcome.primary)
    else:  # cursor
        code = _connect.connect_cursor(name, project.vm.guest_user, outcome.primary)
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
@click.option(
    "--display",
    is_flag=True,
    help="Boot with a UI window. Default is headless.",
)
@click.pass_context
def start(ctx: click.Context, display: bool) -> None:
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
    tart_args = vm.build_run_args(name, project.vm.network, mounts, headless=not display)
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
        code = _connect.connect_cli(name, project.vm.guest_user)
    elif mode == "vscode":
        code = _connect.connect_vscode(name, project.vm.guest_user, primary)
    else:  # cursor
        code = _connect.connect_cursor(name, project.vm.guest_user, primary)
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
    argv = list(ssh_args) if ssh_args else ["/bin/zsh", "-l"]
    code = vm.exec_interactive(name, argv)
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
    code = _connect.connect_cli(name, project.vm.guest_user)
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
