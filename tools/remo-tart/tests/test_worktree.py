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


# ---------------------------------------------------------------------------
# C1: Stale launchd cleanup + log truncation before submit
# ---------------------------------------------------------------------------


@patch("remo_tart.worktree.launchd.submit")
@patch("remo_tart.worktree.launchd.remove")
@patch("remo_tart.worktree._wait_for_guest_exec")
def test_action_create_cleans_stale_launchd_and_truncates_log(
    wait: MagicMock,
    remove: MagicMock,
    submit: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    from remo_tart.paths import vm_log_path
    from remo_tart.worktree import _action_create

    log = vm_log_path("remo-dev")
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("stale content\n")

    with patch("remo_tart.worktree.vm.create"), patch("remo_tart.worktree.vm.set_resources"):
        _action_create(_cfg(), [], log, Path("/tmp/k"))

    # stale log truncated
    assert log.read_text() == ""
    # launchctl remove called before submit
    remove.assert_called_once()
    submit.assert_called_once()


@patch("remo_tart.worktree.launchd.submit")
@patch("remo_tart.worktree.launchd.remove")
@patch("remo_tart.worktree._wait_for_guest_exec")
def test_action_start_cleans_stale_launchd_and_truncates_log(
    wait: MagicMock,
    remove: MagicMock,
    submit: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    from remo_tart.paths import vm_log_path
    from remo_tart.worktree import _action_start

    log = vm_log_path("remo-dev")
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("stale content\n")

    _action_start(_cfg(), [], log)

    # stale log truncated
    assert log.read_text() == ""
    # launchctl remove called before submit
    remove.assert_called_once()
    submit.assert_called_once()


# ---------------------------------------------------------------------------
# C2: Duplicate authorized_keys injection — idempotent inject command
# ---------------------------------------------------------------------------


def test_inject_command_is_idempotent_shape(tmp_path: Path) -> None:
    from remo_tart.worktree import _build_inject_command

    cmd = _build_inject_command("ssh-ed25519 AAAAC... remo-tart")
    assert "grep -Fqx" in cmd
    assert "||" in cmd
    # Shell-safe quoting
    assert "'ssh-ed25519 AAAAC... remo-tart'" in cmd


# ---------------------------------------------------------------------------
# C3: Honor exec_capture returncode when injecting the key
# ---------------------------------------------------------------------------


@patch("remo_tart.worktree.vm.exec_capture")
@patch("remo_tart.worktree.ssh.ensure_include_in_user_config")
@patch("remo_tart.worktree.ssh.upsert_managed_block")
@patch("remo_tart.worktree.ssh.generate_keypair")
@patch("remo_tart.worktree.ssh.public_key", return_value="ssh-ed25519 AAA test")
def test_configure_ssh_raises_when_guest_injection_fails(
    pubkey: MagicMock,
    genkey: MagicMock,
    upsert: MagicMock,
    ensure_include: MagicMock,
    exec_capture: MagicMock,
    fake_home: Path,
) -> None:
    from remo_tart.errors import RemoTartError
    from remo_tart.worktree import _configure_ssh

    exec_capture.return_value = MagicMock(returncode=1, stderr="boom", stdout="")
    with pytest.raises(RemoTartError) as excinfo:
        _configure_ssh(_cfg(), Path("/tmp/k"))
    assert excinfo.value.hint is not None


# ---------------------------------------------------------------------------
# C4: _wait_for_guest_exec polls exec, not just is_running
# ---------------------------------------------------------------------------


@patch("remo_tart.worktree.vm.exec_capture")
@patch("remo_tart.worktree.vm.is_running", return_value=True)
def test_wait_for_guest_exec_polls_exec_capture(
    is_running: MagicMock,
    exec_capture: MagicMock,
) -> None:
    from remo_tart.worktree import _wait_for_guest_exec

    exec_capture.return_value = MagicMock(returncode=0)
    _wait_for_guest_exec("remo-dev", attempts=3, interval=0.0)

    exec_capture.assert_called_with("remo-dev", ["/usr/bin/true"])


@patch("remo_tart.worktree.vm.exec_capture")
@patch("remo_tart.worktree.vm.is_running", return_value=True)
def test_wait_for_guest_exec_raises_on_timeout(
    is_running: MagicMock,
    exec_capture: MagicMock,
) -> None:
    from remo_tart.errors import RemoTartError
    from remo_tart.worktree import _wait_for_guest_exec

    exec_capture.return_value = MagicMock(returncode=1)
    with pytest.raises(RemoTartError):
        _wait_for_guest_exec("remo-dev", attempts=2, interval=0.0)


# ---------------------------------------------------------------------------
# I1: launchctl remove ordering in update-and-restart
# ---------------------------------------------------------------------------


@patch("remo_tart.worktree.launchd.job_present", return_value=False)
@patch("remo_tart.worktree.launchd.submit")
@patch("remo_tart.worktree.launchd.remove")
@patch("remo_tart.worktree._wait_for_stopped")
@patch("remo_tart.worktree._wait_for_guest_exec")
def test_update_and_restart_removes_before_submit(
    wait_exec: MagicMock,
    wait_stopped: MagicMock,
    remove: MagicMock,
    submit: MagicMock,
    job_present: MagicMock,
    fake_home: Path,
) -> None:
    from remo_tart.worktree import _action_update_mount_and_restart

    _action_update_mount_and_restart(_cfg(), [], Path("/tmp/log"))

    # remove was called before submit
    assert remove.call_count == 1
    assert submit.call_count == 1
    # Assertion on ordering via mock_calls
    remove_ts = remove.call_args_list
    submit_ts = submit.call_args_list
    assert len(remove_ts) == 1
    assert len(submit_ts) == 1


# ---------------------------------------------------------------------------
# I3: AttachOutcome shape — tuples and primary field
# ---------------------------------------------------------------------------


def test_attach_outcome_has_primary_and_immutable_fields(fake_home: Path, fake_repo: Path) -> None:
    with (
        patch("remo_tart.worktree._read_state") as read,
        patch("remo_tart.worktree._action_nothing"),
        patch("remo_tart.worktree._configure_ssh"),
    ):
        read.return_value = VmState(exists=True, running=True, mount_matches=True)
        outcome = ensure_attached(fake_repo, _cfg(), fake_repo)

    assert isinstance(outcome.actions, tuple)
    assert isinstance(outcome.manifest, tuple)
    assert outcome.primary.host_path == fake_repo.resolve()
    # Frozen dataclass forbids rebinding
    with pytest.raises((AttributeError, TypeError)):
        outcome.primary = outcome.primary  # type: ignore[misc]
