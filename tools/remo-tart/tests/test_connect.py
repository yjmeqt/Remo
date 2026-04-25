from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

from remo_tart.connect import connect_cli, connect_cursor, connect_vscode
from remo_tart.worktree import WorktreeAttachment


def _attachment(
    guest_path: str = "/Volumes/My Shared Files/remo-dev/.worktrees/foo",
) -> WorktreeAttachment:
    return WorktreeAttachment(
        pool_name="remo-dev",
        host_path=Path("/users/x/remo/.worktrees/foo"),
        guest_path=guest_path,
    )


@patch("remo_tart.connect.subprocess.run")
def test_connect_cli_runs_ssh_with_alias(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    assert connect_cli("remo-dev", "admin") == 0
    (called_argv,) = run.call_args[0]
    assert called_argv == ["ssh", "tart-remo-dev"]


@patch("remo_tart.connect.subprocess.run")
def test_connect_cli_propagates_nonzero(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=130)
    assert connect_cli("remo-dev", "admin") == 130


@patch("remo_tart.connect.subprocess.run")
def test_connect_vscode_builds_uri_from_attachment_guest_path(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    code = connect_vscode("remo-dev", "admin", _attachment())
    assert code == 0
    argv = run.call_args.args[0]
    assert argv[0] == "code"
    folder_uri_idx = argv.index("--folder-uri") + 1
    assert argv[folder_uri_idx] == (
        "vscode-remote://ssh-remote+tart-remo-dev/Volumes/My Shared Files/remo-dev/.worktrees/foo"
    )
    assert "--reuse-window" in argv
    assert "--new-window" not in argv


@patch("remo_tart.connect.subprocess.run")
def test_connect_vscode_new_window(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    connect_vscode("remo-dev", "admin", _attachment(), new_window=True)
    argv = run.call_args.args[0]
    assert "--new-window" in argv
    assert "--reuse-window" not in argv


@patch("remo_tart.connect.subprocess.run")
def test_connect_cursor_builds_uri_from_attachment_guest_path(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=0)
    connect_cursor("remo-dev", "admin", _attachment("/Volumes/My Shared Files/remo-dev"))
    argv = run.call_args.args[0]
    assert argv[0] == "cursor"
    folder_uri_idx = argv.index("--folder-uri") + 1
    assert argv[folder_uri_idx] == (
        "vscode-remote://ssh-remote+tart-remo-dev/Volumes/My Shared Files/remo-dev"
    )


@patch("remo_tart.connect.subprocess.run")
def test_connect_vscode_propagates_returncode(run: MagicMock) -> None:
    run.return_value = MagicMock(returncode=2)
    assert connect_vscode("remo-dev", "admin", _attachment()) == 2
