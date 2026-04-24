from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from click.testing import CliRunner

from remo_tart import __version__
from remo_tart.cli import main


def test_help_does_not_crash() -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["--help"])
    assert result.exit_code == 0
    assert "Usage:" in result.output


def test_version_prints_version() -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["--version"])
    assert result.exit_code == 0
    assert __version__ in result.output


def test_all_subcommands_appear_in_help() -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["--help"])
    for cmd in [
        "up",
        "use",
        "start",
        "connect",
        "status",
        "doctor",
        "ssh",
        "destroy",
        "clean-worktree",
        "bootstrap",
    ]:
        assert cmd in result.output, f"{cmd} missing from --help"


@pytest.fixture
def mock_dispatch() -> MagicMock:
    with patch("remo_tart.cli.bash_dispatch") as m:
        m.return_value = MagicMock(returncode=0)
        yield m


def test_use_forwards_to_use_worktree_script(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["use"])
    assert result.exit_code == 0
    mock_dispatch.assert_called_once()
    assert mock_dispatch.call_args.args[0] == "use-worktree-dev-vm.sh"


def test_connect_forwards_mode(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["connect", "vscode"])
    assert result.exit_code == 0
    mock_dispatch.assert_called_once()
    assert mock_dispatch.call_args.args[0] == "connect-dev-vm.sh"
    assert "vscode" in mock_dispatch.call_args.args[1]


def test_connect_defaults_to_cli(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["connect"])
    assert result.exit_code == 0
    assert "cli" in mock_dispatch.call_args.args[1]


def test_status_forwards(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["status"])
    assert result.exit_code == 0
    assert mock_dispatch.call_args.args[0] == "status-dev-vm.sh"


def test_doctor_forwards(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["doctor"])
    assert result.exit_code == 0
    assert mock_dispatch.call_args.args[0] == "doctor-dev-vm.sh"


def test_ssh_forwards_with_passthrough_args(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["ssh", "--", "uname", "-a"])
    assert result.exit_code == 0
    assert mock_dispatch.call_args.args[0] == "ssh-dev-vm.sh"
    assert "uname" in mock_dispatch.call_args.args[1]
    assert "-a" in mock_dispatch.call_args.args[1]


def test_destroy_forwards_force_flag(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["destroy", "--force"])
    assert result.exit_code == 0
    assert mock_dispatch.call_args.args[0] == "destroy-dev-vm.sh"
    assert "--force" in mock_dispatch.call_args.args[1]


def test_clean_worktree_forwards_path(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["clean-worktree", "/tmp/foo"])
    assert result.exit_code == 0
    assert mock_dispatch.call_args.args[0] == "clean-worktree-dev-vm.sh"
    assert "/tmp/foo" in mock_dispatch.call_args.args[1]


def test_bootstrap_forwards(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["bootstrap"])
    assert result.exit_code == 0
    assert mock_dispatch.call_args.args[0] == "bootstrap-dev-vm.sh"


def test_up_forwards_to_use_and_connect(mock_dispatch: MagicMock) -> None:
    runner = CliRunner()
    result = runner.invoke(main, ["up", "vscode"])
    assert result.exit_code == 0
    # up is approximated in PR 1 as use-worktree + connect
    calls = [c.args[0] for c in mock_dispatch.call_args_list]
    assert "use-worktree-dev-vm.sh" in calls
    assert "connect-dev-vm.sh" in calls


def test_up_stops_on_use_failure(mock_dispatch: MagicMock) -> None:
    mock_dispatch.side_effect = [MagicMock(returncode=1)]
    runner = CliRunner()
    result = runner.invoke(main, ["up"])
    assert result.exit_code == 1
    # only use-worktree was called; connect skipped
    assert mock_dispatch.call_count == 1


def test_run_returns_child_exit_code(
    monkeypatch: pytest.MonkeyPatch, mock_dispatch: MagicMock
) -> None:
    from remo_tart.cli import _run

    mock_dispatch.return_value = MagicMock(returncode=42)
    monkeypatch.setattr("sys.argv", ["remo-tart", "status"])
    assert _run() == 42
