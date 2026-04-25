from __future__ import annotations

from pathlib import Path

import pytest

from remo_tart.errors import RemoTartError
from remo_tart.paths import (
    find_repo_root,
    mount_manifest_path,
    ssh_include_path,
    ssh_key_path,
    state_dir,
    user_ssh_config_path,
    vm_log_path,
)


def _make_fake_repo(tmp_path: Path) -> Path:
    tart = tmp_path / ".tart"
    tart.mkdir()
    (tart / "project.toml").write_text('[project]\nslug = "x"\n')
    return tmp_path


@pytest.fixture
def fake_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("HOME", str(tmp_path))
    return tmp_path


def test_state_dir(fake_home: Path) -> None:
    assert state_dir("remo-dev") == fake_home / ".config" / "remo" / "tart"


def test_mount_manifest_path(fake_home: Path) -> None:
    expected = fake_home / ".config" / "remo" / "tart" / "remo-dev.mounts"
    assert mount_manifest_path("remo-dev") == expected


def test_vm_log_path(fake_home: Path) -> None:
    assert vm_log_path("remo-dev") == fake_home / ".config" / "remo" / "tart" / "remo-dev.log"


def test_ssh_include_path(fake_home: Path) -> None:
    assert ssh_include_path() == fake_home / ".config" / "remo" / "tart" / "ssh_config"


def test_ssh_key_path(fake_home: Path) -> None:
    expected = fake_home / ".config" / "remo" / "tart" / "ssh" / "remo-dev_ed25519"
    assert ssh_key_path("remo-dev") == expected


def test_user_ssh_config_path(fake_home: Path) -> None:
    assert user_ssh_config_path() == fake_home / ".ssh" / "config"


def test_find_repo_root_walks_upward(tmp_path: Path) -> None:
    repo = _make_fake_repo(tmp_path)
    nested = repo / "a" / "b" / "c"
    nested.mkdir(parents=True)
    assert find_repo_root(nested) == repo


def test_find_repo_root_raises_when_not_found(tmp_path: Path) -> None:
    with pytest.raises(RemoTartError) as excinfo:
        find_repo_root(tmp_path)
    assert excinfo.value.hint is not None
    assert "project.toml" in excinfo.value.hint


def test_git_worktree_root_in_main_checkout(tmp_path: Path) -> None:
    """In the main checkout, worktree root == repo root."""
    import subprocess as sp

    from remo_tart.paths import git_worktree_root

    sp.run(
        ["git", "-C", str(tmp_path), "init", "--initial-branch=main"],
        check=True,
        capture_output=True,
    )
    sub = tmp_path / "tools" / "thing"
    sub.mkdir(parents=True)
    assert git_worktree_root(sub) == tmp_path.resolve()


def test_git_worktree_root_in_linked_worktree(tmp_path: Path) -> None:
    """Inside a `.worktrees/<name>` directory, returns that worktree root."""
    import subprocess as sp

    from remo_tart.paths import git_worktree_root

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
    inner = wt / "deep" / "dir"
    inner.mkdir(parents=True)
    assert git_worktree_root(inner) == wt.resolve()


def test_git_worktree_root_falls_back_when_not_a_repo(tmp_path: Path) -> None:
    """Outside a git repo, return the input path unchanged (resolved)."""
    from remo_tart.paths import git_worktree_root

    assert git_worktree_root(tmp_path) == tmp_path.resolve()
