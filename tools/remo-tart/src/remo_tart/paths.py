"""Centralised on-disk paths and repo-root discovery."""

from __future__ import annotations

from pathlib import Path

from remo_tart.errors import RemoTartError


def _config_root() -> Path:
    return Path.home() / ".config" / "remo" / "tart"


def state_dir(vm_name: str) -> Path:
    del vm_name  # reserved; state dir is shared across VMs today
    return _config_root()


def mount_manifest_path(vm_name: str) -> Path:
    return _config_root() / f"{vm_name}.mounts"


def vm_log_path(vm_name: str) -> Path:
    return _config_root() / f"{vm_name}.log"


def ssh_include_path() -> Path:
    return _config_root() / "ssh_config"


def ssh_key_path(vm_name: str) -> Path:
    return _config_root() / "ssh" / f"{vm_name}_ed25519"


def user_ssh_config_path() -> Path:
    return Path.home() / ".ssh" / "config"


def find_repo_root(start: Path | None = None) -> Path:
    """Walk upward from ``start`` (default cwd) until ``.tart/project.toml`` is found.

    Raises ``RemoTartError`` if not found.
    """
    current = (start or Path.cwd()).resolve()
    for candidate in [current, *current.parents]:
        if (candidate / ".tart" / "project.toml").is_file():
            return candidate
    raise RemoTartError(
        "unable to find the Remo repo root from the current working directory",
        hint="run remo-tart from inside a Tart-managed project (.tart/project.toml must exist)",
    )
