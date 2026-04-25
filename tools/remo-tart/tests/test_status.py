from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from remo_tart.mount import MountEntry, manifest_write
from remo_tart.paths import mount_manifest_path, ssh_include_path, ssh_key_path
from remo_tart.status import collect, render_human, render_json


@pytest.fixture
def fake_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setenv("HOME", str(tmp_path))
    return tmp_path


@patch("remo_tart.status.vm.exists")
@patch("remo_tart.status.vm.is_running")
@patch("remo_tart.status.vm.ip_address")
@patch("remo_tart.status.launchd.job_present")
def test_collect_running_vm(
    job_present: MagicMock,
    ip: MagicMock,
    is_running: MagicMock,
    exists: MagicMock,
    fake_home: Path,
    tmp_path: Path,
) -> None:
    exists.return_value = True
    is_running.return_value = True
    ip.return_value = "10.0.0.2"
    job_present.return_value = True

    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / ".git").mkdir()

    # Pre-populate manifest
    manifest_write(
        mount_manifest_path("remo-dev"),
        [
            MountEntry("remo-feat", repo),
            MountEntry("remo-git-root", repo / ".git"),
        ],
    )

    data = collect("remo-dev", repo, repo)
    assert data["vm"]["name"] == "remo-dev"
    assert data["vm"]["exists"] is True
    assert data["vm"]["running"] is True
    assert data["vm"]["ip"] == "10.0.0.2"
    assert data["launchd"]["label"].startswith("com.remo.tart.")
    assert data["launchd"]["job_present"] is True
    assert data["mounts"]["count"] == 2
    assert data["mounts"]["selected"] == "remo-feat"
    assert data["mounts"]["git_root_present"] is True
    assert {"name": "remo-feat", "host_path": str(repo)} in data["mounts"]["entries"]


@patch("remo_tart.status.vm.exists", return_value=False)
@patch("remo_tart.status.vm.is_running", return_value=False)
@patch("remo_tart.status.vm.ip_address", return_value=None)
@patch("remo_tart.status.launchd.job_present", return_value=False)
def test_collect_missing_vm(
    job_present: MagicMock,
    ip: MagicMock,
    is_running: MagicMock,
    exists: MagicMock,
    fake_home: Path,
    tmp_path: Path,
) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    data = collect("remo-dev", repo, repo)
    assert data["vm"]["exists"] is False
    assert data["vm"]["ip"] is None
    assert data["mounts"]["count"] == 0
    assert data["mounts"]["selected"] is None
    assert data["mounts"]["git_root_present"] is False


@patch("remo_tart.status.vm.exists", return_value=True)
@patch("remo_tart.status.vm.is_running", return_value=True)
@patch("remo_tart.status.vm.ip_address", return_value=None)
@patch("remo_tart.status.launchd.job_present", return_value=False)
def test_collect_includes_ssh_section(
    mock_job_present: MagicMock,
    mock_ip: MagicMock,
    mock_is_running: MagicMock,
    mock_exists: MagicMock,
    fake_home: Path,
    tmp_path: Path,
) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    data = collect("remo-dev", repo, repo)
    assert "ssh" in data
    assert data["ssh"]["include_path"] == str(ssh_include_path())
    assert data["ssh"]["key_path"] == str(ssh_key_path("remo-dev"))
    assert data["ssh"]["key_present"] is False
    assert data["ssh"]["include_present_in_user_config"] is False


def test_render_human_includes_section_headers() -> None:
    data = {
        "vm": {"name": "remo-dev", "exists": True, "running": True, "ip": "10.0.0.2"},
        "launchd": {"label": "com.remo.tart.remo-dev", "job_present": True},
        "mounts": {
            "manifest_path": "/m.mounts",
            "count": 1,
            "selected": "remo-feat",
            "git_root_present": True,
            "entries": [{"name": "remo-feat", "host_path": "/r"}],
        },
        "ssh": {
            "include_path": "/i",
            "key_path": "/k",
            "key_present": True,
            "include_present_in_user_config": False,
        },
    }
    text = render_human(data)
    assert "vm:" in text
    assert "launchd:" in text
    assert "mounts:" in text
    assert "ssh:" in text
    # Booleans rendered as lowercase
    assert "running=true" in text
    assert "include_present_in_user_config=false" in text
    # Entries listed
    assert "remo-feat=/r" in text


def test_render_human_handles_none_and_empty_entries() -> None:
    data = {
        "vm": {"name": "x", "exists": False, "running": False, "ip": None},
        "launchd": {"label": "com.remo.tart.x", "job_present": False},
        "mounts": {
            "manifest_path": "/m",
            "count": 0,
            "selected": None,
            "git_root_present": False,
            "entries": [],
        },
        "ssh": {
            "include_path": "/i",
            "key_path": "/k",
            "key_present": False,
            "include_present_in_user_config": False,
        },
    }
    text = render_human(data)
    assert "ip=null" in text
    assert "selected=null" in text


def test_status_collect_with_umbrella_manifest(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("HOME", str(tmp_path))
    repo = tmp_path / "repo"
    repo.mkdir()
    manifest_write(mount_manifest_path("alpha"), [MountEntry("alpha", repo)])

    with patch("remo_tart.status.vm.exists", return_value=False):
        data = collect("alpha", repo, repo)
    assert data["mounts"]["count"] == 1
    assert data["mounts"]["entries"][0]["name"] == "alpha"
    assert data["mounts"]["selected"] == "alpha"


def test_render_json_is_valid_json() -> None:
    data = {
        "vm": {"name": "x", "exists": True, "running": True, "ip": "1.2.3.4"},
        "launchd": {"label": "com.remo.tart.x", "job_present": True},
        "mounts": {
            "manifest_path": "/m",
            "count": 0,
            "selected": None,
            "git_root_present": False,
            "entries": [],
        },
        "ssh": {
            "include_path": "/i",
            "key_path": "/k",
            "key_present": False,
            "include_present_in_user_config": False,
        },
    }
    out = render_json(data)
    parsed = json.loads(out)
    assert parsed == data
