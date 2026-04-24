from __future__ import annotations

import shutil
import stat
from pathlib import Path

import pytest

from remo_tart.ssh import (
    block_marker_pair,
    ensure_include_in_user_config,
    generate_keypair,
    managed_block,
    public_key,
    remote_authority,
    remove_include_from_user_config,
    remove_managed_block,
    ssh_alias,
    upsert_managed_block,
)


def test_ssh_alias() -> None:
    assert ssh_alias("remo-dev") == "tart-remo-dev"


def test_remote_authority() -> None:
    assert remote_authority("remo-dev", "admin", "10.0.0.2") == "ssh-remote+admin@10.0.0.2"


def test_managed_block_contains_required_fields() -> None:
    block = managed_block("remo-dev", "admin", Path("/k/remo-dev_ed25519"))
    assert "Host tart-remo-dev" in block
    assert "User admin" in block
    assert "IdentityFile /k/remo-dev_ed25519" in block
    assert "StrictHostKeyChecking no" in block
    assert "ProxyCommand tart exec -i remo-dev" in block


def test_block_marker_pair() -> None:
    begin, end = block_marker_pair("remo-dev")
    assert begin.startswith("# >>>") and "remo-dev" in begin  # noqa: PT018
    assert end.startswith("# <<<") and "remo-dev" in end  # noqa: PT018


def test_upsert_managed_block_inserts_into_empty_file(tmp_path: Path) -> None:
    path = tmp_path / "tart_config"
    upsert_managed_block(path, "remo-dev", "Host tart-remo-dev\n  HostName x\n")
    text = path.read_text()
    assert "# >>>" in text
    assert "Host tart-remo-dev" in text
    assert "# <<<" in text


def test_upsert_managed_block_replaces_existing(tmp_path: Path) -> None:
    path = tmp_path / "tart_config"
    upsert_managed_block(path, "remo-dev", "block-v1\n")
    upsert_managed_block(path, "remo-dev", "block-v2\n")
    text = path.read_text()
    assert "block-v1" not in text
    assert "block-v2" in text
    # exactly one marker pair for this VM
    assert text.count(">>>") == 1
    assert text.count("<<<") == 1


def test_remove_managed_block_is_noop_when_absent(tmp_path: Path) -> None:
    path = tmp_path / "tart_config"
    remove_managed_block(path, "remo-dev")
    assert not path.exists() or path.read_text() == ""


def test_remove_managed_block_removes_only_that_vm(tmp_path: Path) -> None:
    path = tmp_path / "tart_config"
    upsert_managed_block(path, "remo-dev", "keep-me-dev\n")
    upsert_managed_block(path, "other-vm", "remove-me\n")
    remove_managed_block(path, "other-vm")
    text = path.read_text()
    assert "keep-me-dev" in text
    assert "remove-me" not in text


def test_ensure_include_adds_include_directive(tmp_path: Path) -> None:
    user = tmp_path / "config"
    include = tmp_path / "tart_config"
    ensure_include_in_user_config(user, include)
    text = user.read_text()
    assert f"Include {include}" in text
    # idempotent
    ensure_include_in_user_config(user, include)
    assert user.read_text().count(f"Include {include}") == 1


def test_remove_include_cleans_up(tmp_path: Path) -> None:
    user = tmp_path / "config"
    include = tmp_path / "tart_config"
    ensure_include_in_user_config(user, include)
    remove_include_from_user_config(user, include)
    assert f"Include {include}" not in user.read_text()


@pytest.mark.skipif(shutil.which("ssh-keygen") is None, reason="ssh-keygen not available")
def test_generate_keypair(tmp_path: Path) -> None:
    key = tmp_path / "k_ed25519"
    generate_keypair(key)
    assert key.is_file()
    assert key.with_suffix(key.suffix + ".pub").is_file()
    # ssh-keygen writes 600 on the private key
    mode = stat.S_IMODE(key.stat().st_mode)
    assert mode & 0o077 == 0
    pub = public_key(key)
    assert pub.startswith("ssh-ed25519 ")


@pytest.mark.skipif(shutil.which("ssh-keygen") is None, reason="ssh-keygen not available")
def test_generate_keypair_idempotent(tmp_path: Path) -> None:
    key = tmp_path / "k_ed25519"
    generate_keypair(key)
    first_content = key.read_bytes()
    generate_keypair(key)  # second call must not regenerate
    assert key.read_bytes() == first_content
