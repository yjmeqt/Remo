"""Locate the repo and forward argv to scripts/tart/*.sh (PR 1 shim)."""

from __future__ import annotations

import subprocess
from pathlib import Path

from remo_tart.errors import RemoTartError


def find_repo_root(start: Path | None = None) -> Path:
    """Walk upward from ``start`` (default cwd) until we find scripts/tart/.

    Raises ``RemoTartError`` if not found.
    """
    current = (start or Path.cwd()).resolve()
    for candidate in [current, *current.parents]:
        if (candidate / "scripts" / "tart").is_dir():
            return candidate
    raise RemoTartError(
        "unable to find the Remo repo root from the current working directory",
        hint="run remo-tart from inside a Remo checkout (scripts/tart/ must exist)",
    )


def bash_dispatch(
    script_name: str,
    args: list[str],
    *,
    capture: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run scripts/tart/<script_name> with the given args.

    - ``capture=False`` (default): inherit stdin/stdout/stderr — suitable for
      interactive commands like ``ssh``.
    - ``capture=True``: capture output (used by tests).
    """
    repo = find_repo_root()
    script = repo / "scripts" / "tart" / script_name
    if not script.is_file():
        raise RemoTartError(
            f"missing dispatch target: scripts/tart/{script_name}",
            hint="this is a remo-tart bug — please file an issue",
        )
    cmd = ["bash", str(script), *args]
    if capture:
        return subprocess.run(cmd, check=False, capture_output=True, text=True)
    return subprocess.run(cmd, check=False)
