"""Tests for pool resolution."""

from __future__ import annotations

import pytest

from remo_tart.config import ProjectConfig, ScriptsConfig, VmConfig
from remo_tart.errors import RemoTartError
from remo_tart.pool import PoolConfig, resolve_pool


def _cfg(vm_name: str = "remo-dev") -> ProjectConfig:
    return ProjectConfig(
        slug="remo",
        vm=VmConfig(
            name=vm_name,
            base_image="img",
            cpu=1,
            memory_gb=1,
            network="shared",
        ),
        packs=["ios"],
        scripts=ScriptsConfig(
            provision=".tart/provision.sh",
            verify_worktree=".tart/verify-worktree.sh",
        ),
    )


def test_resolve_pool_default_uses_project_vm_name() -> None:
    pool = resolve_pool(_cfg(vm_name="remo-dev"), pool_name=None)
    assert isinstance(pool, PoolConfig)
    assert pool.name == "remo-dev"


def test_resolve_pool_override_uses_explicit_name() -> None:
    pool = resolve_pool(_cfg(), pool_name="alpha")
    assert pool.name == "alpha"


def test_resolve_pool_rejects_empty_name() -> None:
    with pytest.raises(RemoTartError):
        resolve_pool(_cfg(), pool_name="")


def test_resolve_pool_rejects_invalid_chars() -> None:
    with pytest.raises(RemoTartError):
        resolve_pool(_cfg(), pool_name="bad name with spaces")


def test_pool_config_is_frozen() -> None:
    pool = resolve_pool(_cfg(), pool_name=None)
    with pytest.raises((AttributeError, TypeError)):
        pool.name = "other"  # type: ignore[misc]
