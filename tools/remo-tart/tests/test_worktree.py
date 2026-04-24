from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from remo_tart.config import ProjectConfig, ScriptsConfig, VmConfig
from remo_tart.state import Action, VmState
from remo_tart.worktree import AttachOutcome, ensure_attached


def _cfg() -> ProjectConfig:
    return ProjectConfig(
        slug="remo",
        vm=VmConfig(
            name="remo-dev",
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


@pytest.fixture
def fake_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("HOME", str(tmp_path))
    return tmp_path


@pytest.fixture
def fake_repo(tmp_path: Path) -> Path:
    (tmp_path / ".git").mkdir()
    return tmp_path


@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_create")
def test_missing_vm_triggers_create(
    create: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    read.return_value = VmState(exists=False, running=False, mount_matches=False)
    outcome = ensure_attached(fake_repo, _cfg(), fake_repo)
    create.assert_called_once()
    config_ssh.assert_called_once()
    assert isinstance(outcome, AttachOutcome)
    assert Action.CREATE in outcome.actions


@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_nothing")
def test_healthy_state_is_nothing_and_skips_ssh_reconfig(
    nothing: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    read.return_value = VmState(exists=True, running=True, mount_matches=True)
    ensure_attached(fake_repo, _cfg(), fake_repo)
    nothing.assert_called_once()
    # NOTHING path does NOT re-configure SSH (no duplicate key injection)
    config_ssh.assert_not_called()


@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_update_mount_and_restart")
def test_running_with_mismatched_mount_triggers_update_and_restart(
    update: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    read.return_value = VmState(exists=True, running=True, mount_matches=False)
    ensure_attached(fake_repo, _cfg(), fake_repo)
    update.assert_called_once()
    config_ssh.assert_called_once()


@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_start")
def test_stopped_with_matching_mount_triggers_start(
    start: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    read.return_value = VmState(exists=True, running=False, mount_matches=True)
    ensure_attached(fake_repo, _cfg(), fake_repo)
    start.assert_called_once()
    config_ssh.assert_called_once()


def test_ensure_attached_upserts_primary_and_git_root(fake_home: Path, fake_repo: Path) -> None:
    """The manifest must contain both the worktree entry and the git-root bridge."""
    from remo_tart.paths import mount_manifest_path

    with (
        patch("remo_tart.worktree._read_state") as read,
        patch("remo_tart.worktree._action_nothing"),
        patch("remo_tart.worktree._configure_ssh"),
    ):
        read.return_value = VmState(exists=True, running=True, mount_matches=True)
        ensure_attached(fake_repo, _cfg(), fake_repo)

    entries = list(_read_manifest(mount_manifest_path("remo-dev")))
    names = {e.name for e in entries}
    assert "remo-git-root" in names
    # primary mount name is derived from worktree basename
    assert any(n.startswith("remo") and n != "remo-git-root" for n in names)


def _read_manifest(path: Path) -> list:
    from remo_tart.mount import manifest_read

    return manifest_read(path)
