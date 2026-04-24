"""remo-tart command-line entry point."""

from __future__ import annotations

import sys

import click

from remo_tart import __version__
from remo_tart.console import get_console, render_error
from remo_tart.errors import RemoTartError


@click.group(context_settings={"help_option_names": ["-h", "--help"]})
@click.version_option(version=__version__, prog_name="remo-tart")
@click.option("-v", "--verbose", count=True, help="Increase verbosity (repeatable).")
@click.pass_context
def main(ctx: click.Context, verbose: int) -> None:
    """CLI for the Remo Tart development VM."""
    ctx.ensure_object(dict)
    ctx.obj["verbose"] = verbose


def _run() -> int:
    """Top-level entry with structured error handling."""
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
    return 0


if __name__ == "__main__":
    sys.exit(_run())
