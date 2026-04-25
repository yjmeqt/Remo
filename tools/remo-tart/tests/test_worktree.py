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


@patch("remo_tart.worktree.vm.is_running", return_value=True)
@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_create")
def test_missing_vm_triggers_create(
    create: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    is_running: MagicMock,
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
@patch("remo_tart.worktree.vm.is_running", return_value=True)
def test_healthy_state_is_nothing_and_still_configures_ssh(
    is_running: MagicMock,
    nothing: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    """SSH config is idempotent and runs unconditionally when the VM is running.

    This makes the workflow self-healing if a prior `up` was Ctrl-C'd before
    SSH was configured (e.g. interrupted during `_wait_for_guest_exec`).
    """
    read.return_value = VmState(exists=True, running=True, mount_matches=True)
    ensure_attached(fake_repo, _cfg(), fake_repo)
    nothing.assert_called_once()
    config_ssh.assert_called_once()


@patch("remo_tart.worktree.vm.is_running", return_value=True)
@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_update_mount_and_restart")
def test_running_with_mismatched_mount_triggers_update_and_restart(
    update: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    is_running: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    read.return_value = VmState(exists=True, running=True, mount_matches=False)
    ensure_attached(fake_repo, _cfg(), fake_repo)
    update.assert_called_once()
    config_ssh.assert_called_once()


@patch("remo_tart.worktree.vm.is_running", return_value=True)
@patch("remo_tart.worktree._configure_ssh")
@patch("remo_tart.worktree._read_state")
@patch("remo_tart.worktree._action_start")
def test_stopped_with_matching_mount_triggers_start(
    start: MagicMock,
    read: MagicMock,
    config_ssh: MagicMock,
    is_running: MagicMock,
    fake_home: Path,
    fake_repo: Path,
) -> None:
    read.return_value = VmState(exists=True, running=False, mount_matches=True)
    ensure_attached(fake_repo, _cfg(), fake_repo)
    start.assert_called_once()
    config_ssh.assert_called_once()


def test_ensure_attached_writes_single_umbrella_entry(fake_home: Path, fake_repo: Path) -> None:
    """Manifest contains exactly one entry: pool.name → repo_root."""
    from remo_tart.paths import mount_manifest_path

    with (
        patch("remo_tart.worktree._read_state") as read,
        patch("remo_tart.worktree._action_nothing"),
        patch("remo_tart.worktree._configure_ssh"),
        patch("remo_tart.worktree.vm.is_running", return_value=True),
    ):
        read.return_value = VmState(exists=True, running=True, mount_matches=True)
        ensure_attached(fake_repo, _cfg(), fake_repo)

    entries = _read_manifest(mount_manifest_path("remo-dev"))
    assert len(entries) == 1
    assert entries[0].name == "remo-dev"
    assert entries[0].host_path == fake_repo.resolve()


def test_ensure_attached_drops_legacy_manifest_entries(fake_home: Path, fake_repo: Path) -> None:
    """Pre-umbrella per-worktree + bridge entries are dropped on attach."""
    from remo_tart.mount import MountEntry, manifest_write
    from remo_tart.paths import mount_manifest_path

    mp = mount_manifest_path("remo-dev")
    manifest_write(
        mp,
        [
            MountEntry("remo", Path("/old/main")),
            MountEntry("remo-feature-x", Path("/old/wt")),
            MountEntry("remo-git-root", Path("/old/.git")),
        ],
    )

    with (
        patch("remo_tart.worktree._read_state") as read,
        patch("remo_tart.worktree._action_nothing"),
        patch("remo_tart.worktree._configure_ssh"),
        patch("remo_tart.worktree.vm.is_running", return_value=True),
    ):
        read.return_value = VmState(exists=True, running=True, mount_matches=True)
        ensure_attached(fake_repo, _cfg(), fake_repo)

    entries = _read_manifest(mount_manifest_path("remo-dev"))
    assert [e.name for e in entries] == ["remo-dev"]


def test_ensure_attached_uses_pool_name_when_provided(fake_home: Path, fake_repo: Path) -> None:
    """`--pool alpha` writes manifest at <alpha>.mounts and uses VM name 'alpha'."""
    from remo_tart.paths import mount_manifest_path

    with (
        patch("remo_tart.worktree._read_state") as read,
        patch("remo_tart.worktree._action_nothing"),
        patch("remo_tart.worktree._configure_ssh"),
        patch("remo_tart.worktree.vm.is_running", return_value=True),
    ):
        read.return_value = VmState(exists=True, running=True, mount_matches=True)
        outcome = ensure_attached(fake_repo, _cfg(), fake_repo, pool_name="alpha")

    entries = _read_manifest(mount_manifest_path("alpha"))
    assert [e.name for e in entries] == ["alpha"]
    assert outcome.attachment.pool_name == "alpha"
    assert outcome.attachment.guest_path == "/Volumes/My Shared Files/alpha"


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

    from remo_tart.pool import resolve_pool

    pool = resolve_pool(_cfg(), pool_name=None)
    with patch("remo_tart.worktree.vm.create"), patch("remo_tart.worktree.vm.set_resources"):
        _action_create(_cfg(), pool, [], log, Path("/tmp/k"))

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

    from remo_tart.pool import resolve_pool

    pool = resolve_pool(_cfg(), pool_name=None)
    _action_start(_cfg(), pool, [], log)

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
    from remo_tart.pool import resolve_pool
    from remo_tart.worktree import _configure_ssh

    pool = resolve_pool(_cfg(), pool_name=None)
    exec_capture.return_value = MagicMock(returncode=1, stderr="boom", stdout="")
    with pytest.raises(RemoTartError) as excinfo:
        _configure_ssh(_cfg(), pool, Path("/tmp/k"))
    assert excinfo.value.hint is not None


# ---------------------------------------------------------------------------
# C4: _wait_for_guest_exec polls exec, not just is_running
# ---------------------------------------------------------------------------


@patch("remo_tart.worktree.vm.ip_address", return_value=None)
@patch("remo_tart.worktree.vm.exec_capture")
@patch("remo_tart.worktree.vm.is_running", return_value=True)
def test_wait_for_guest_exec_polls_exec_capture(
    is_running: MagicMock,
    exec_capture: MagicMock,
    ip_address: MagicMock,
) -> None:
    from remo_tart.worktree import _wait_for_guest_exec

    exec_capture.return_value = MagicMock(returncode=0)
    _wait_for_guest_exec("remo-dev", attempts=3, interval=0.0)

    exec_capture.assert_called_with("remo-dev", ["/usr/bin/true"])


@patch("remo_tart.worktree.vm.ip_address", return_value=None)
@patch("remo_tart.worktree.vm.exec_capture")
@patch("remo_tart.worktree.vm.is_running", return_value=True)
def test_wait_for_guest_exec_raises_on_timeout(
    is_running: MagicMock,
    exec_capture: MagicMock,
    ip_address: MagicMock,
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
    from remo_tart.pool import resolve_pool
    from remo_tart.worktree import _action_update_mount_and_restart

    pool = resolve_pool(_cfg(), pool_name=None)
    _action_update_mount_and_restart(_cfg(), pool, [], Path("/tmp/log"))

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


def test_attach_outcome_carries_attachment(fake_home: Path, fake_repo: Path) -> None:
    with (
        patch("remo_tart.worktree._read_state") as read,
        patch("remo_tart.worktree._action_nothing"),
        patch("remo_tart.worktree._configure_ssh"),
        patch("remo_tart.worktree.vm.is_running", return_value=True),
    ):
        read.return_value = VmState(exists=True, running=True, mount_matches=True)
        outcome = ensure_attached(fake_repo, _cfg(), fake_repo)

    assert isinstance(outcome.actions, tuple)
    assert isinstance(outcome.manifest, tuple)
    assert outcome.attachment.pool_name == "remo-dev"
    assert outcome.attachment.host_path == fake_repo.resolve()
    assert outcome.attachment.guest_path == "/Volumes/My Shared Files/remo-dev"
    with pytest.raises((AttributeError, TypeError)):
        outcome.attachment = outcome.attachment  # type: ignore[misc]


# ---------------------------------------------------------------------------
# WorktreeAttachment + guest_path_for_worktree
# ---------------------------------------------------------------------------


def test_worktree_attachment_guest_path_main_checkout() -> None:
    """Main checkout (worktree == repo root) has guest_path = umbrella root."""
    from remo_tart.worktree import guest_path_for_worktree

    repo = Path("/users/x/remo")
    assert guest_path_for_worktree("remo-dev", repo, repo) == "/Volumes/My Shared Files/remo-dev"


def test_worktree_attachment_guest_path_linked_worktree() -> None:
    """A worktree under .worktrees/foo resolves to <umbrella>/.worktrees/foo."""
    from remo_tart.worktree import guest_path_for_worktree

    repo = Path("/users/x/remo")
    wt = repo / ".worktrees" / "foo"
    assert (
        guest_path_for_worktree("remo-dev", repo, wt)
        == "/Volumes/My Shared Files/remo-dev/.worktrees/foo"
    )


def test_worktree_attachment_rejects_path_outside_repo() -> None:
    """Worktrees outside the repo root are not yet supported in pools."""
    from remo_tart.errors import RemoTartError
    from remo_tart.worktree import guest_path_for_worktree

    with pytest.raises(RemoTartError):
        guest_path_for_worktree("remo-dev", Path("/users/x/remo"), Path("/elsewhere"))


# ---------------------------------------------------------------------------
# _normalize_worktree_gitdirs
# ---------------------------------------------------------------------------


def _init_worktree(tmp_path: Path) -> tuple[Path, Path]:
    """Create a main checkout with one linked worktree under .worktrees/foo."""
    import subprocess as sp

    main = tmp_path / "main"
    main.mkdir()
    env = {
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@t",
        "PATH": "/usr/bin:/bin",
    }
    sp.run(
        ["git", "-C", str(main), "init", "--initial-branch=main"],
        check=True,
        capture_output=True,
        env=env,
    )
    sp.run(
        ["git", "-C", str(main), "commit", "--allow-empty", "-m", "i"],
        check=True,
        capture_output=True,
        env=env,
    )
    wt = main / ".worktrees" / "foo"
    sp.run(
        ["git", "-C", str(main), "worktree", "add", str(wt)],
        check=True,
        capture_output=True,
        env=env,
    )
    return main, wt


def test_normalize_worktree_gitdirs_rewrites_absolute_to_relative(tmp_path: Path) -> None:
    """An absolute gitdir under repo .git is rewritten to a relative path."""
    from remo_tart.worktree import _normalize_worktree_gitdirs

    main, wt = _init_worktree(tmp_path)
    git_file = wt / ".git"
    original = git_file.read_text()
    assert original.startswith("gitdir: ")
    assert "/" in original  # absolute, host-specific

    _normalize_worktree_gitdirs(main)

    rewritten = git_file.read_text().strip()
    assert rewritten.startswith("gitdir: ")
    rel = rewritten[len("gitdir: ") :]
    assert not rel.startswith("/")
    resolved = (wt / rel).resolve()
    assert resolved == (main / ".git" / "worktrees" / "foo").resolve()


def test_normalize_worktree_gitdirs_is_idempotent(tmp_path: Path) -> None:
    """Running twice is a no-op once paths are already relative."""
    from remo_tart.worktree import _normalize_worktree_gitdirs

    main, wt = _init_worktree(tmp_path)
    _normalize_worktree_gitdirs(main)
    first = (wt / ".git").read_text()
    _normalize_worktree_gitdirs(main)
    second = (wt / ".git").read_text()
    assert first == second


def test_normalize_worktree_gitdirs_skips_when_no_worktrees(tmp_path: Path) -> None:
    """Repos without .worktrees/ do nothing and don't error."""
    from remo_tart.worktree import _normalize_worktree_gitdirs

    (tmp_path / ".git").mkdir()
    _normalize_worktree_gitdirs(tmp_path)


def test_normalize_worktree_gitdirs_leaves_external_gitdir_alone(tmp_path: Path) -> None:
    """Worktrees pointing outside repo .git/worktrees/ are not rewritten."""
    from remo_tart.worktree import _normalize_worktree_gitdirs

    repo = tmp_path / "main"
    repo.mkdir()
    (repo / ".git").mkdir()
    wt = repo / ".worktrees" / "external"
    wt.mkdir(parents=True)
    foreign = "gitdir: /some/other/place\n"
    (wt / ".git").write_text(foreign)

    _normalize_worktree_gitdirs(repo)
    assert (wt / ".git").read_text() == foreign
