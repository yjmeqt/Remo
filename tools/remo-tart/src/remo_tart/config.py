"""Load and validate .tart/project.toml."""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field, ValidationError

from remo_tart.errors import RemoTartError


class VmConfig(BaseModel):
    name: str
    base_image: str
    cpu: int = Field(ge=1)
    memory_gb: int = Field(ge=1)
    network: str
    guest_user: str = "admin"
    guest_password: str = "admin"


class ScriptsConfig(BaseModel):
    provision: str
    verify_worktree: str


class ProjectConfig(BaseModel):
    slug: str
    vm: VmConfig
    packs: list[str]
    scripts: ScriptsConfig


def _toml_path(repo_root: Path) -> Path:
    return repo_root / ".tart" / "project.toml"


def _legacy_sh_path(repo_root: Path) -> Path:
    return repo_root / ".tart" / "project.sh"


def legacy_project_sh_present(repo_root: Path) -> bool:
    return _legacy_sh_path(repo_root).is_file()


def _parse(raw: bytes, repo_root: Path) -> ProjectConfig:
    try:
        data: dict[str, Any] = tomllib.loads(raw.decode("utf-8"))
    except tomllib.TOMLDecodeError as err:
        raise RemoTartError(
            f"invalid TOML in {_toml_path(repo_root)}: {err}",
            hint="fix the syntax error; see docs/tart-dev-vm.md for the expected schema",
        ) from err
    # pydantic expects structure: {slug, vm, packs, scripts}
    project = data.get("project", {}) or {}
    payload = {
        "slug": project.get("slug"),
        "vm": data.get("vm"),
        "packs": (data.get("packs") or {}).get("enabled", []),
        "scripts": data.get("scripts"),
    }
    try:
        return ProjectConfig.model_validate(payload)
    except ValidationError as err:
        raise RemoTartError(
            f"invalid config in {_toml_path(repo_root)}: {err}",
            hint="see docs/tart-dev-vm.md for the expected schema",
        ) from err


def load(repo_root: Path) -> ProjectConfig:
    toml = _toml_path(repo_root)
    if not toml.is_file():
        if legacy_project_sh_present(repo_root):
            raise RemoTartError(
                f"missing {toml} (found legacy .tart/project.sh)",
                hint=(
                    "create .tart/project.toml from your project.sh values; see "
                    "docs/tart-dev-vm.md for the schema and a migration example"
                ),
            )
        raise RemoTartError(
            f"missing {toml}",
            hint="create .tart/project.toml; see docs/tart-dev-vm.md for the schema",
        )
    return _parse(toml.read_bytes(), repo_root)
