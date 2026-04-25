"""Pool resolution.

A *pool* is a named Tart VM identity. Every worktree's `up` joins exactly one
pool. The pool name parameterises the VM name (`tart` CLI), launchd label,
SSH key file, log path, and mount manifest path.

Default pool name is the project's configured ``vm.name`` so existing
single-VM setups keep working unchanged. ``--pool <name>`` opts a worktree
into a distinct pool (i.e. a distinct VM) for parallel/isolated work.

VM image, CPU, memory, and network are still read from the project config —
this minimum-viable pool is purely a VM-identity namespace. Cross-project
pools and per-pool config persistence are intentionally out of scope.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from remo_tart.config import ProjectConfig
from remo_tart.errors import RemoTartError

_VALID_NAME = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9._-]*$")


@dataclass(frozen=True)
class PoolConfig:
    """Resolved pool identity for one ``ensure_attached`` invocation."""

    name: str


def resolve_pool(project: ProjectConfig, pool_name: str | None) -> PoolConfig:
    """Return the resolved pool for *project*.

    *pool_name* of ``None`` falls back to ``project.vm.name`` (the default
    pool, preserving backward compatibility). Any other value is validated
    against the same character class Tart accepts for VM names.
    """
    name = pool_name if pool_name is not None else project.vm.name
    if not name or not _VALID_NAME.match(name):
        raise RemoTartError(
            f"invalid pool name: {name!r}",
            hint="pool names must start with [A-Za-z0-9] and contain only [A-Za-z0-9._-]",
        )
    return PoolConfig(name=name)
