"""remo-tart command-line entry point.

PR 1: every subcommand dispatches to scripts/tart/*.sh. The real logic
moves to Python in PR 2.
"""

from __future__ import annotations

import sys

import click

from remo_tart import __version__
from remo_tart.console import get_console, render_error
from remo_tart.dispatch import bash_dispatch
from remo_tart.errors import RemoTartError


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
    """Attach the current worktree, ensure the VM is running, and connect.

    In PR 1 this is approximated as ``use`` + ``connect``. A true idempotent
    state machine lands in PR 2.
    """
    use_result = bash_dispatch("use-worktree-dev-vm.sh", [])
    if use_result.returncode != 0:
        ctx.exit(use_result.returncode)
    connect_result = bash_dispatch("connect-dev-vm.sh", [mode])
    ctx.exit(connect_result.returncode)


# ---- explicit lifecycle ---------------------------------------------------


@main.command()
@click.argument("worktree", required=False)
@click.pass_context
def use(ctx: click.Context, worktree: str | None) -> None:
    """Attach a worktree to the VM (mount + restart if needed)."""
    args = [worktree] if worktree else []
    result = bash_dispatch("use-worktree-dev-vm.sh", args)
    ctx.exit(result.returncode)


@main.command()
@click.pass_context
def start(ctx: click.Context) -> None:
    """Start the VM without changing mounts or connecting.

    PR 1 approximates this by running use-worktree with --no-verify; a real
    start-only command lands in PR 2.
    """
    result = bash_dispatch("use-worktree-dev-vm.sh", ["--no-verify"])
    ctx.exit(result.returncode)


@main.command()
@click.argument("mode", type=click.Choice(["cli", "vscode", "cursor"]), default="cli")
@click.argument("extra", nargs=-1, type=click.UNPROCESSED)
@click.pass_context
def connect(ctx: click.Context, mode: str, extra: tuple[str, ...]) -> None:
    """Connect to the running VM (cli / vscode / cursor)."""
    result = bash_dispatch("connect-dev-vm.sh", [mode, *extra])
    ctx.exit(result.returncode)


# ---- observability --------------------------------------------------------


@main.command()
@click.option("--json", "as_json", is_flag=True, help="Emit machine-readable JSON.")
@click.pass_context
def status(ctx: click.Context, as_json: bool) -> None:
    """Show VM status."""
    args = ["--json"] if as_json else []
    result = bash_dispatch("status-dev-vm.sh", args)
    ctx.exit(result.returncode)


@main.command()
@click.pass_context
def doctor(ctx: click.Context) -> None:
    """Run host/VM health checks."""
    result = bash_dispatch("doctor-dev-vm.sh", [])
    ctx.exit(result.returncode)


@main.command(context_settings={"ignore_unknown_options": True})
@click.argument("ssh_args", nargs=-1, type=click.UNPROCESSED)
@click.pass_context
def ssh(ctx: click.Context, ssh_args: tuple[str, ...]) -> None:
    """Open an SSH session or run a command inside the VM."""
    result = bash_dispatch("ssh-dev-vm.sh", list(ssh_args))
    ctx.exit(result.returncode)


# ---- destructive ----------------------------------------------------------


@main.command()
@click.option("--force", is_flag=True, help="Skip confirmation.")
@click.pass_context
def destroy(ctx: click.Context, force: bool) -> None:
    """Destroy the VM."""
    args = ["--force"] if force else []
    result = bash_dispatch("destroy-dev-vm.sh", args)
    ctx.exit(result.returncode)


@main.command(name="clean-worktree")
@click.argument("path", required=False)
@click.pass_context
def clean_worktree(ctx: click.Context, path: str | None) -> None:
    """Remove a worktree from the mount manifest."""
    args = [path] if path else []
    result = bash_dispatch("clean-worktree-dev-vm.sh", args)
    ctx.exit(result.returncode)


@main.command()
@click.pass_context
def bootstrap(ctx: click.Context) -> None:
    """First-time VM setup (create + provision)."""
    result = bash_dispatch("bootstrap-dev-vm.sh", [])
    ctx.exit(result.returncode)


def _run() -> int:
    try:
        main(standalone_mode=False)
    except RemoTartError as err:
        render_error(get_console(), err)
        return 1
    except click.exceptions.ClickException as err:
        err.show()
        return err.exit_code
    except click.exceptions.Abort:
        return 130
    except click.exceptions.Exit as err:
        return int(err.code) if isinstance(err.code, int) else 0
    except SystemExit as err:
        return int(err.code) if isinstance(err.code, int) else 0
    return 0


if __name__ == "__main__":
    sys.exit(_run())
