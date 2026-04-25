"""Shared rich Console and error rendering."""

from __future__ import annotations

from rich.console import Console

from remo_tart.errors import RemoTartError

_console: Console | None = None


def get_console() -> Console:
    global _console
    if _console is None:
        _console = Console(stderr=False, highlight=False)
    return _console


def render_error(console: Console, err: RemoTartError) -> None:
    console.print(f"[red]error:[/red] {err}")
    if err.hint:
        console.print(f"[dim]hint:[/dim] {err.hint}")


def step(msg: str) -> None:
    """Print a progress step. Use for long-running orchestrator phases."""
    get_console().print(f"[cyan]→[/cyan] {msg}")


def done(msg: str) -> None:
    """Print a completion step."""
    get_console().print(f"[green]✓[/green] {msg}")
