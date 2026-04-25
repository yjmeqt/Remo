from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

from remo_tart.connect import connect_cli, connect_cursor, connect_vscode
from remo_tart.mount import MountEntry


@patch("subprocess.run")
def test_connect_cli_runs_ssh_with_alias(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    assert connect_cli("remo-dev", "admin") == 0
    (called_argv,) = run.call_args[0]
    assert called_argv == ["ssh", "tart-remo-dev"]


@patch("subprocess.run")
def test_connect_cli_propagates_nonzero(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=130)
    assert connect_cli("remo-dev", "admin") == 130


@patch("subprocess.run")
def test_connect_vscode_default_reuses_window(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    mount = MountEntry("remo-feat", Path("/r"))
    connect_vscode("remo-dev", "admin", mount)
    (called_argv,) = run.call_args[0]
    assert called_argv[0] == "code"
    assert "--folder-uri" in called_argv
    idx = called_argv.index("--folder-uri")
    uri = called_argv[idx + 1]
    assert uri == "vscode-remote://ssh-remote+tart-remo-dev/Volumes/My Shared Files/remo-feat"
    assert "--reuse-window" in called_argv
    assert "--new-window" not in called_argv


@patch("subprocess.run")
def test_connect_vscode_new_window(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    mount = MountEntry("remo-feat", Path("/r"))
    connect_vscode("remo-dev", "admin", mount, new_window=True)
    (called_argv,) = run.call_args[0]
    assert "--new-window" in called_argv
    assert "--reuse-window" not in called_argv


@patch("subprocess.run")
def test_connect_cursor_uses_cursor_binary(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    mount = MountEntry("remo-feat", Path("/r"))
    connect_cursor("remo-dev", "admin", mount)
    (called_argv,) = run.call_args[0]
    assert called_argv[0] == "cursor"
    # Same URI as vscode (cursor accepts vscode-remote://)
    idx = called_argv.index("--folder-uri")
    uri = called_argv[idx + 1]
    assert uri.startswith("vscode-remote://ssh-remote+tart-remo-dev/")


@patch("subprocess.run")
def test_connect_vscode_propagates_returncode(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=2)
    mount = MountEntry("remo-feat", Path("/r"))
    assert connect_vscode("remo-dev", "admin", mount) == 2
