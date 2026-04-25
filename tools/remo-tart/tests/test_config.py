from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from remo_tart.config import (
    ProjectConfig,
    legacy_project_sh_present,
    load,
)
from remo_tart.errors import RemoTartError


def _write_toml(repo: Path, content: str) -> None:
    tart_dir = repo / ".tart"
    tart_dir.mkdir(exist_ok=True)
    (tart_dir / "project.toml").write_text(content)


def _valid_toml() -> str:
    return textwrap.dedent(
        """
        [project]
        slug = "remo"

        [vm]
        name = "remo-dev"
        base_image = "ghcr.io/cirruslabs/macos-tahoe-xcode:26"
        cpu = 6
        memory_gb = 12
        network = "bridged:en0"

        [packs]
        enabled = ["ios", "rust"]

        [scripts]
        provision = ".tart/provision.sh"
        verify_worktree = ".tart/verify-worktree.sh"
        """
    ).strip()


def test_load_valid_config(tmp_path: Path) -> None:
    _write_toml(tmp_path, _valid_toml())
    cfg = load(tmp_path)
    assert isinstance(cfg, ProjectConfig)
    assert cfg.slug == "remo"
    assert cfg.vm.name == "remo-dev"
    assert cfg.vm.cpu == 6
    assert cfg.vm.memory_gb == 12
    assert cfg.vm.network == "bridged:en0"
    assert cfg.packs == ["ios", "rust"]
    assert cfg.scripts.provision == ".tart/provision.sh"


def test_load_missing_toml_with_legacy_sh_raises_with_hint(tmp_path: Path) -> None:
    (tmp_path / ".tart").mkdir()
    (tmp_path / ".tart" / "project.sh").write_text("# legacy")
    with pytest.raises(RemoTartError) as excinfo:
        load(tmp_path)
    assert "project.toml" in str(excinfo.value)
    assert excinfo.value.hint is not None
    assert "project.toml" in excinfo.value.hint


def test_load_missing_toml_and_sh_raises(tmp_path: Path) -> None:
    (tmp_path / ".tart").mkdir()
    with pytest.raises(RemoTartError) as excinfo:
        load(tmp_path)
    assert excinfo.value.hint is not None


def test_load_invalid_toml_raises_with_hint(tmp_path: Path) -> None:
    _write_toml(tmp_path, "not = valid = toml")
    with pytest.raises(RemoTartError) as excinfo:
        load(tmp_path)
    assert excinfo.value.hint is not None


def test_load_missing_required_field_raises(tmp_path: Path) -> None:
    incomplete = textwrap.dedent(
        """
        [project]
        slug = "x"

        [vm]
        name = "x"
        base_image = "x"
        cpu = 1
        memory_gb = 1
        """
    ).strip()
    _write_toml(tmp_path, incomplete)
    with pytest.raises(RemoTartError):
        load(tmp_path)


def test_legacy_project_sh_present(tmp_path: Path) -> None:
    assert legacy_project_sh_present(tmp_path) is False
    (tmp_path / ".tart").mkdir()
    (tmp_path / ".tart" / "project.sh").write_text("#")
    assert legacy_project_sh_present(tmp_path) is True


def test_load_prefers_toml_when_both_present(tmp_path: Path) -> None:
    _write_toml(tmp_path, _valid_toml())
    (tmp_path / ".tart" / "project.sh").write_text("# legacy")
    cfg = load(tmp_path)
    assert cfg.slug == "remo"


def test_vm_config_defaults_guest_user(tmp_path: Path) -> None:
    _write_toml(tmp_path, _valid_toml())
    cfg = load(tmp_path)
    assert cfg.vm.guest_user == "admin"
    assert cfg.vm.guest_password == "admin"


def test_vm_config_overrides_guest_credentials(tmp_path: Path) -> None:
    toml = _valid_toml().replace(
        "[vm]",
        '[vm]\nguest_user = "developer"\nguest_password = "s3cret"',
    )
    _write_toml(tmp_path, toml)
    cfg = load(tmp_path)
    assert cfg.vm.guest_user == "developer"
    assert cfg.vm.guest_password == "s3cret"
