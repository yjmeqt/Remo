"""Centralised on-disk paths. Pure — no I/O."""

from __future__ import annotations

from pathlib import Path


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
