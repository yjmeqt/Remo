"""Legacy bash dispatcher. Slated for deletion in PR 3 Task 5.

`find_repo_root` lives in `remo_tart.paths` now; this re-export keeps the
existing `test_dispatch.py` importable until that test file is also deleted.
"""

from __future__ import annotations

import subprocess

from remo_tart.errors import RemoTartError
from remo_tart.paths import find_repo_root  # re-export for backward compat

__all__ = ["bash_dispatch", "find_repo_root"]


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
